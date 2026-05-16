/***************************************************************************************************
Asset:        FSI Zero to Snowflake - データロード (Excel → Snowpark Stored Procedure)
Script:       02b_data_load_excel.sql
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

  1. ステージの確認とファイルアップロード
  2. Python Stored Procedure の作成 (Snowpark + openpyxl)
  3. ストアドプロシージャの実行
  4. 結果確認とアドホック分析
  5. Task で日次自動化
  6. 動作確認 (Task 実行と履歴確認)
  7. まとめ (Snowpark WH vs SPCS の使い分け)

前提: fallback/setup.sql が実行済みで、データベース fsi_zts_101 とスキーマ raw_excel が存在すること
      (Section 8 で Git リポジトリから Excel ファイルを内部ステージに転送済み)
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

-- ステージにExcelファイルがあることを確認 (setup.sql で Git リポジトリから格納済み)
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
    INPUT_STAGE VARCHAR,     -- 例: 'fsi_zts_101.raw_excel.excel_demo_stage'
    ARCHIVE_STAGE VARCHAR,   -- 例: 'fsi_zts_101.raw_excel.excel_archive_stage'
    TARGET_TABLE VARCHAR     -- 例: 'fsi_zts_101.raw_excel.corporate_sales'
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'openpyxl', 'pandas')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import pandas as pd
from openpyxl import load_workbook
from io import BytesIO
from datetime import datetime, date

def main(session, input_stage: str, archive_stage: str, target_table: str) -> str:
    """
    入力ステージ内の全 .xlsx ファイルを自動検出して取り込み、
    処理済みファイルをアーカイブステージに移動する。

    フロー:
      1. LIST @input_stage で .xlsx ファイルを検出
      2. 各ファイルを get_stream → openpyxl → pandas → テーブル書き込み
      3. 処理済みファイルを COPY FILES でアーカイブステージに移動
      4. 入力ステージから処理済みファイルを REMOVE

    Parameters
    ----------
    input_stage : str
        入力ステージの完全修飾名 (例: 'fsi_zts_101.raw_excel.excel_demo_stage')
    archive_stage : str
        アーカイブステージの完全修飾名 (例: 'fsi_zts_101.raw_excel.excel_archive_stage')
    target_table : str
        書き込み先テーブルの完全修飾名 (例: 'fsi_zts_101.raw_excel.corporate_sales')
    """
    # @ の正規化
    input_ref  = input_stage  if input_stage.startswith('@')  else f"@{input_stage}"
    archive_ref = archive_stage if archive_stage.startswith('@') else f"@{archive_stage}"

    # ----------------------------------------------------------------
    # Step 1: 入力ステージ内の .xlsx ファイルを検出
    # ----------------------------------------------------------------
    try:
        files_result = session.sql(f"LIST {input_ref}").collect()
    except Exception as e:
        # ステージが存在しない or 権限不足の場合、スタックトレースを出さずにメッセージ返却
        return (
            f"Error: Cannot access input stage '{input_stage}'. "
            f"Stage may not exist or current role lacks READ privilege. "
            f"Run setup.sql first, or check: SHOW STAGES IN SCHEMA fsi_zts_101.raw_excel; "
            f"Detail: {str(e)[:200]}"
        )

    xlsx_files = [
        row['name'] for row in files_result
        if row['name'].lower().endswith('.xlsx')
    ]

    # ----------------------------------------------------------------
    # Step 1b: 入力ステージが空の場合 → 正常終了 (処理対象なし)
    #   実運用: アーカイブ済みファイルは処理完了の証跡。
    #          入力ステージに新しいファイルが配置されるまで待機。
    #   ハンズオン: 再実行したい場合は以下を先に実行してください:
    #     COPY FILES INTO @fsi_zts_101.raw_excel.excel_demo_stage
    #       FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/excel/;
    # ----------------------------------------------------------------
    if not xlsx_files:
        return (
            "No .xlsx files found in input stage. Nothing to process. "
            "If files were already archived, this is expected behavior (idempotent). "
            "To re-run: execute COPY FILES from Git repo to input stage first."
        )

    total_rows = 0
    processed_files = []
    errors = []

    for file_path in xlsx_files:
        try:
            # ----------------------------------------------------------------
            # Step 2: Excel ファイルを読み込み → テーブルに書き込み
            # ----------------------------------------------------------------
            # LIST の結果は "stage_name/path/filename.xlsx" 形式 (@ なし)
            stream_path = f"@{file_path}"
            input_stream = session.file.get_stream(stream_path, decompress=False)
            workbook = load_workbook(filename=BytesIO(input_stream.read()), read_only=True, data_only=True)
            sheet = workbook.active
            data = list(sheet.values)

            if not data or len(data) < 2:
                workbook.close()
                errors.append(f"{file_path}: empty or header-only")
                continue

            headers = [str(h).strip() for h in data[0]]
            df = pd.DataFrame(data[1:], columns=headers)

            # 日付列の変換
            date_columns = ['last_visit_date', 'expected_close_date']
            for col in date_columns:
                if col in df.columns:
                    df[col] = pd.to_datetime(df[col], errors='coerce').dt.date

            # 数値列の変換
            if 'opportunity_amount' in df.columns:
                df['opportunity_amount'] = pd.to_numeric(df['opportunity_amount'], errors='coerce')

            # メタデータ列
            df['loaded_at'] = datetime.now()
            file_name = file_path.split('/')[-1]
            df['source_file'] = file_name

            # カラム名大文字化
            df.columns = [c.upper() for c in df.columns]

            # テーブルに書き込み
            snowpark_df = session.create_dataframe(df)
            snowpark_df.write.mode("append").save_as_table(target_table)

            total_rows += len(df)
            processed_files.append(file_name)
            workbook.close()

        except Exception as e:
            errors.append(f"{file_path}: {str(e)}")
            continue

    # ----------------------------------------------------------------
    # Step 3: 処理済みファイルをアーカイブステージに移動
    # ----------------------------------------------------------------
    if processed_files:
        # COPY FILES で入力ステージ → アーカイブステージに転送
        session.sql(f"COPY FILES INTO {archive_ref} FROM {input_ref}").collect()

        # Step 4: 入力ステージから処理済みファイルを削除
        for file_name in processed_files:
            session.sql(f"REMOVE {input_ref}/{file_name}").collect()

    # ----------------------------------------------------------------
    # 結果サマリ
    # ----------------------------------------------------------------
    result_parts = [
        f"Processed: {len(processed_files)} file(s), {total_rows} rows loaded into '{target_table}'."
    ]
    if processed_files:
        result_parts.append(f"Archived to: {archive_stage}")
        result_parts.append(f"Files: {', '.join(processed_files)}")
    if errors:
        result_parts.append(f"Errors ({len(errors)}): {'; '.join(errors)}")

    return ' | '.join(result_parts)
$$;


/*--
 3. ストアドプロシージャの実行
    アップロード済みの Excel ファイルを指定してプロシージャを呼び出します。
--*/

-- テーブルが5,000件であることを確認 (初回実行前)
SELECT COUNT(*) AS before_count FROM fsi_zts_101.raw_excel.corporate_sales;

-- プロシージャを実行して Excel データを取り込み
-- (ステージ内の全 .xlsx を自動検出 → テーブル取り込み → アーカイブに移動)
CALL fsi_zts_101.raw_excel.load_excel_to_table(
    'fsi_zts_101.raw_excel.excel_demo_stage',      -- 入力ステージ
    'fsi_zts_101.raw_excel.excel_archive_stage',   -- アーカイブステージ
    'fsi_zts_101.raw_excel.corporate_sales'        -- ターゲットテーブル
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
        'fsi_zts_101.raw_excel.excel_demo_stage',
        'fsi_zts_101.raw_excel.excel_archive_stage',
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

-- 取り込み後の件数確認 (手動でデータ格納済みなので数は変わらない)
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

ALTER TASK fsi_zts_101.raw_excel.load_excel_daily_task SUSPEND;


/*--
 7. まとめ: レガシー Excel 取り込みパイプラインの近代化

    今回学んだこと:
    - Internal Stage に Excel をアップロードする方法 (UI / PUT)
    - Snowpark Python SP で openpyxl + pandas を使った Excel パース
    - session.file.get_stream() による Stage ファイルの読み込み
    - save_as_table() による append モードの書き込み
    - Task + CRON でスケジュール自動化
--*/
