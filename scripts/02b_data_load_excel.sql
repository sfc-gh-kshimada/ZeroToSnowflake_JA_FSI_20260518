/***************************************************************************************************
Asset:        FSI Zero to Snowflake - データロード (Excel → Snowpark Stored Procedure)
Script:       02b_data_load_excel.sql
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

このスクリプトでは、Excel ファイルを Snowflake に取り込む一連の手順を学びます。
金融機関では Excel が依然としてデータ連携の主要フォーマットであり、
法人営業データ・リスク報告・規制当局向け報告等で日常的に利用されています。

従来は「Windows サーバー + .bat + タスクスケジューラ」で定期取り込みしていた Excel 処理を
Snowflake の Snowpark Stored Procedure + Task で完全にクラウド移行するパターンを紹介します。

  1. ステージの確認とファイルアップロード
  2. Python Stored Procedure の作成 (Snowpark + openpyxl)
  3. ストアドプロシージャの実行
  4. 結果確認とアドホック分析
  5. Task で日次自動化
  6. 動作確認 (Task 実行と履歴確認)
  7. まとめ (Snowpark WH vs SPCS の使い分け)

所要時間: 約 15 分
前提: setup.sql が実行済みで、データベース fsi_zts_101 とスキーマ raw_excel が存在すること
****************************************************************************************************/

-- =====================================================================
-- ロール / ウェアハウス / データベースのセット
-- =====================================================================
USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;
USE SCHEMA raw_excel;

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"data_load_excel"}}';


/*--
 1. ステージの確認とファイルアップロード
    setup.sql で作成済みの内部ステージに Excel ファイルをアップロードします。
--*/

-- ステージが存在することを確認
SHOW STAGES LIKE 'excel_demo_stage' IN SCHEMA fsi_zts_101.raw_excel;

-- ■ アップロード方法 (いずれか一方を実施)
--
-- 【方法 A】 Snowsight UI からドラッグ & ドロップ
--   1. Snowsight 左メニュー > [Data] > [Databases]
--   2. fsi_zts_101 > raw_excel > Stages > EXCEL_DEMO_STAGE を開く
--   3. 右上 [+ Files] をクリックし、assets/excel/corporate_sales_data.xlsx をドラッグ & ドロップ
--   4. [Upload] で完了
--
-- 【方法 B】 SnowSQL / SnowCLI から PUT コマンド (ローカル環境がある場合)
--   PUT file://./assets/excel/corporate_sales_data.xlsx
--       @fsi_zts_101.raw_excel.excel_demo_stage
--       AUTO_COMPRESS = FALSE
--       OVERWRITE = TRUE;

-- アップロード結果を確認
LIST @fsi_zts_101.raw_excel.excel_demo_stage;


/*--
 2. Python Stored Procedure の作成 (Snowpark + openpyxl)

    Snowpark Python Stored Procedure を使い、ステージ上の Excel ファイルを読み込み、
    指定したテーブルに append モードで書き込みます。

    処理フロー:
      ステージ (Excel) → session.file.get_stream() → openpyxl → pandas DataFrame
        → 日付変換 → メタデータ列追加 → Snowpark DataFrame → save_as_table (append)

    ポイント:
    - PACKAGES に 'openpyxl' を指定すると、Anaconda チャネルから自動インストールされます
    - Python は WH 上で実行されるため、ファイルサイズに応じた WH サイズを選択してください
    - RUNTIME_VERSION = '3.11' で Python 3.11 を使用 (2026 年時点の推奨)
--*/

CREATE OR REPLACE PROCEDURE fsi_zts_101.raw_excel.load_excel_to_table(
    STAGE_PATH VARCHAR,    -- 例: 'fsi_zts_101.raw_excel.excel_demo_stage/corporate_sales_data.xlsx'
    TARGET_TABLE VARCHAR   -- 例: 'fsi_zts_101.raw_excel.corporate_sales'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'openpyxl', 'pandas')
HANDLER = 'main'
COMMENT = 'Excel ファイルをステージから読み込み、指定テーブルに append するプロシージャ'
AS
$$
import pandas as pd
from openpyxl import load_workbook
from io import BytesIO
from datetime import datetime, date

def main(session, stage_path: str, target_table: str) -> str:
    """
    Excel ファイルをステージから取得し、対象テーブルに挿入する。

    Parameters
    ----------
    session : snowflake.snowpark.Session
        Snowpark セッション (自動注入)
    stage_path : str
        ステージ上の Excel ファイルパス (例: 'db.schema.stage/file.xlsx')
    target_table : str
        書き込み先テーブルの完全修飾名 (例: 'db.schema.table')
    """

    # ----------------------------------------------------------------
    # Step 1: ステージから Excel ファイルをストリームとして読み込み
    # ----------------------------------------------------------------
    input_stream = session.file.get_stream(f"@{stage_path}", decompress=False)
    workbook = load_workbook(filename=BytesIO(input_stream.read()), read_only=True, data_only=True)
    sheet = workbook.active

    # ----------------------------------------------------------------
    # Step 2: openpyxl → pandas DataFrame に変換
    # ----------------------------------------------------------------
    data = list(sheet.values)
    if not data:
        return "Error: Excel file is empty."

    # 1 行目をヘッダー、2 行目以降をデータとして DataFrame 作成
    headers = [str(h).strip() for h in data[0]]
    df = pd.DataFrame(data[1:], columns=headers)

    if df.empty:
        return "Error: Excel file has headers but no data rows."

    # ----------------------------------------------------------------
    # Step 3: 日付列の型変換
    #   Excel のセルが datetime 型で読み込まれた場合 → date に変換
    #   文字列の場合 → pd.to_datetime でパース後 date に変換
    # ----------------------------------------------------------------
    date_columns = ['last_visit_date', 'expected_close_date']
    for col in date_columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors='coerce').dt.date

    # ----------------------------------------------------------------
    # Step 4: 数値列の型変換 (opportunity_amount)
    # ----------------------------------------------------------------
    if 'opportunity_amount' in df.columns:
        df['opportunity_amount'] = pd.to_numeric(df['opportunity_amount'], errors='coerce')

    # ----------------------------------------------------------------
    # Step 5: メタデータ列の追加
    # ----------------------------------------------------------------
    df['loaded_at'] = datetime.now()
    # ステージパスからファイル名を抽出
    file_name = stage_path.split('/')[-1] if '/' in stage_path else stage_path
    df['source_file'] = file_name

    # ----------------------------------------------------------------
    # Step 6: カラム名を大文字に変換 (Snowflake の規約に合わせる)
    # ----------------------------------------------------------------
    df.columns = [c.upper() for c in df.columns]

    # ----------------------------------------------------------------
    # Step 7: Snowpark DataFrame に変換してテーブルに書き込み
    # ----------------------------------------------------------------
    snowpark_df = session.create_dataframe(df)
    snowpark_df.write.mode("append").save_as_table(target_table)

    row_count = len(df)
    workbook.close()

    return f"Success: {row_count} rows loaded from '{file_name}' into '{target_table}'."
$$;


/*--
 3. ストアドプロシージャの実行
    アップロード済みの Excel ファイルを指定してプロシージャを呼び出します。
--*/

-- テーブルが空であることを確認 (初回実行前)
SELECT COUNT(*) AS before_count FROM fsi_zts_101.raw_excel.corporate_sales;

-- プロシージャを実行して Excel データを取り込み
CALL fsi_zts_101.raw_excel.load_excel_to_table(
    'fsi_zts_101.raw_excel.excel_demo_stage/corporate_sales_data.xlsx',
    'fsi_zts_101.raw_excel.corporate_sales'
);

-- 取り込み後の件数確認
SELECT COUNT(*) AS after_count FROM fsi_zts_101.raw_excel.corporate_sales;


/*--
 4. 結果確認とアドホック分析
    取り込まれたデータの内容を確認し、簡単な分析クエリを実行します。
--*/

-- 先頭 10 行をプレビュー
SELECT * FROM fsi_zts_101.raw_excel.corporate_sales LIMIT 10;

-- 基本統計: 総行数・ユニーク案件数・合計見込額・平均見込額
SELECT
    COUNT(*)                           AS total_rows,
    COUNT(DISTINCT deal_id)            AS unique_deals,
    SUM(opportunity_amount)            AS total_opportunity_amount,
    ROUND(AVG(opportunity_amount), 2)  AS avg_opportunity_amount,
    MIN(last_visit_date)               AS earliest_visit,
    MAX(expected_close_date)           AS latest_close_date
FROM fsi_zts_101.raw_excel.corporate_sales;

-- 案件ステージ別の分布 (パイプライン分析)
SELECT
    stage,
    COUNT(*)                          AS deal_count,
    SUM(opportunity_amount)           AS total_amount,
    ROUND(AVG(opportunity_amount), 0) AS avg_amount
FROM fsi_zts_101.raw_excel.corporate_sales
GROUP BY stage
ORDER BY total_amount DESC;

-- 営業担当者別の見込額トップ 5
SELECT
    sales_rep,
    COUNT(*)                AS deal_count,
    SUM(opportunity_amount) AS total_amount
FROM fsi_zts_101.raw_excel.corporate_sales
GROUP BY sales_rep
ORDER BY total_amount DESC
LIMIT 5;

-- 業種別の案件分布
SELECT
    industry,
    COUNT(*)                AS deal_count,
    SUM(opportunity_amount) AS total_amount,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_deals
FROM fsi_zts_101.raw_excel.corporate_sales
GROUP BY industry
ORDER BY deal_count DESC;

-- 地域 × ステージのクロス集計
SELECT
    region,
    COUNT_IF(stage = '提案') AS proposals,
    COUNT_IF(stage = '見積') AS quotes,
    COUNT_IF(stage = '受注') AS won,
    COUNT_IF(stage = '失注') AS lost,
    COUNT(*)                 AS total
FROM fsi_zts_101.raw_excel.corporate_sales
GROUP BY region
ORDER BY total DESC;


/*--
 5. Task で日次自動化
    Snowflake Task を作成し、毎朝 9:00 (JST) にストアドプロシージャを自動実行します。
    これにより「Windows .bat + タスクスケジューラ」相当の処理を完全にクラウド化できます。

    ポイント:
    - CRON 式で日本時間 (Asia/Tokyo) のスケジュールを指定
    - WAREHOUSE を指定してサーバーレスタスクではなくウェアハウスベースで実行
    - 作成直後は SUSPENDED 状態。ALTER TASK ... RESUME で有効化
--*/

CREATE OR REPLACE TASK fsi_zts_101.raw_excel.load_excel_daily_task
    WAREHOUSE = fsi_de_wh
    SCHEDULE  = 'USING CRON 0 9 * * * Asia/Tokyo'
    COMMENT   = '毎朝 9:00 (JST) に Excel データを取り込む日次タスク'
AS
    CALL fsi_zts_101.raw_excel.load_excel_to_table(
        'fsi_zts_101.raw_excel.excel_demo_stage/corporate_sales_data.xlsx',
        'fsi_zts_101.raw_excel.corporate_sales'
    );

-- タスクが SUSPENDED 状態であることを確認
SHOW TASKS LIKE 'load_excel_daily_task' IN SCHEMA fsi_zts_101.raw_excel;

-- タスクを有効化 (RESUME)
ALTER TASK fsi_zts_101.raw_excel.load_excel_daily_task RESUME;


/*--
 6. 動作確認 (Task の即時実行と履歴確認)
    EXECUTE TASK でスケジュールを待たずに即時テスト実行できます。

    注意: EXECUTE TASK は手動トリガーのため、TASK_HISTORY に
    scheduled_time = NULL の実行レコードとして記録されます。
--*/

-- 即時実行 (テスト用)
EXECUTE TASK fsi_zts_101.raw_excel.load_excel_daily_task;

-- 少し待ってから実行履歴を確認 (state = 'SUCCEEDED' になれば成功)
SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_code,
    error_message
FROM TABLE(information_schema.task_history(
    task_name           => 'load_excel_daily_task',
    scheduled_time_range_start => DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
ORDER BY completed_time DESC
LIMIT 5;

-- 取り込み後の件数確認 (2 回分ロードされているはず: 手動 + Task)
SELECT
    COUNT(*)            AS total_rows,
    COUNT(DISTINCT deal_id) AS unique_deals,
    source_file,
    MIN(loaded_at)      AS first_loaded,
    MAX(loaded_at)      AS last_loaded
FROM fsi_zts_101.raw_excel.corporate_sales
GROUP BY source_file;


/*--
 ■ ハンズオン終了後のクリーンアップ (必要に応じて実行)
    本番環境では Task を SUSPEND しておくことを推奨します。
--*/

-- ALTER TASK fsi_zts_101.raw_excel.load_excel_daily_task SUSPEND;


/*--
 7. まとめ: レガシー Excel 取り込みパイプラインの近代化

    ┌──────────────────────────┐      ┌──────────────────────────────────────┐
    │  Before (従来構成)        │      │  After (Snowflake 構成)               │
    ├──────────────────────────┤      ├──────────────────────────────────────┤
    │  Windows Server          │      │  不要 (フルマネージド)                 │
    │  .bat / PowerShell       │  →   │  Snowpark Stored Procedure (Python)  │
    │  Task Scheduler          │      │  Snowflake Task (CRON)               │
    │  共有フォルダ (\\NAS)     │      │  Internal Stage (@stage)             │
    │  手動リトライ            │      │  Task Retry / Alert 連携             │
    └──────────────────────────┘      └──────────────────────────────────────┘

    今回学んだこと:
    - Internal Stage に Excel をアップロードする方法 (UI / PUT)
    - Snowpark Python SP で openpyxl + pandas を使った Excel パース
    - session.file.get_stream() による Stage ファイルの読み込み
    - save_as_table() による append モードの書き込み
    - Task + CRON でスケジュール自動化

    ─────────────────────────────────────────────────────────────────
    ■ 補足: Snowpark (Warehouse) vs SPCS (Container) の使い分け
    ─────────────────────────────────────────────────────────────────

    ┌─────────────────────┬────────────────────────┬─────────────────────────┐
    │                     │ Snowpark (WH 実行)     │ SPCS (コンテナ実行)     │
    ├─────────────────────┼────────────────────────┼─────────────────────────┤
    │ 適したケース        │ 単一ファイルの変換     │ 常駐 API / Web アプリ   │
    │                     │ バッチ ETL             │ GPU / ML 推論           │
    │                     │ ≤ 数 GB の処理         │ 大量ファイル並列処理    │
    ├─────────────────────┼────────────────────────┼─────────────────────────┤
    │ 実行モデル          │ WH 上でプロセス起動    │ Docker コンテナ常駐     │
    ├─────────────────────┼────────────────────────┼─────────────────────────┤
    │ 課金                │ WH クレジット (秒単位) │ Compute Pool (秒単位)   │
    ├─────────────────────┼────────────────────────┼─────────────────────────┤
    │ ライブラリ制約      │ Anaconda チャネルのみ  │ 任意 (Docker イメージ)  │
    ├─────────────────────┼────────────────────────┼─────────────────────────┤
    │ セットアップ難易度  │ 低 (SQL + Python)      │ 中〜高 (Docker + YAML)  │
    └─────────────────────┴────────────────────────┴─────────────────────────┘

    本ハンズオンの Excel 取り込み (100 行、1 ファイル) は Snowpark (WH) が最適です。
    ファイル数が数百〜数千、または外部 API 連携が必要な場合は SPCS を検討してください。
--*/
