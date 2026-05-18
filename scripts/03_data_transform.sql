/***************************************************************************************************
Asset:        FSI Zero to Snowflake - データ変換
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

セクション 3 - データ変換
  Part A: Tasks + Streams (増分処理)                     ~20 分
    1. Stream の作成
    2. 増分集計テーブルの作成と変換ロジック
    3. Task の作成 (MERGE INTO パターン)
    4. Task の実行と確認
  Part B: Dynamic Tables (宣言的パイプライン)            ~25 分
    5. Dynamic Table とは
    6. 貿易取引の Dynamic Table 作成
    7. 日次取引サマリの Dynamic Table
    8. DAG 可視化 (Snowsight 手順)
    9. 法人営業データの分析クエリ
  Part C: まとめ                                          ~5 分
   10. Task+Stream vs Dynamic Table 比較と推奨
   11. クリーンアップ

前提条件:
  - setup.sql を実行済み (データベース・スキーマ・テーブル・ビュー作成済み)
  - セクション 2 のデータロードが完了していること

銀行のオンプレバッチサーバで夜間に実行していた集計処理を、Snowflake に移行する
シナリオで、命令的 (Task + Stream) と宣言的 (Dynamic Table) の2つのアプローチを
体験します。
****************************************************************************************************/

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"data_transform"}}';

USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;

/******************************************************************************
  Tasks + Streams  -- 増分処理 
 ******************************************************************************/

/*----------------------------------------------------------------------------------
 1. Stream の作成
    -------------------------------------------------
    Stream は Snowflake の変更データキャプチャ (CDC) 機能です。
    テーブルに対する INSERT / UPDATE / DELETE を自動的に追跡し、
    まだ処理されていない差分データだけを取得できます。

    参考: https://docs.snowflake.com/ja/user-guide/streams-intro
----------------------------------------------------------------------------------*/

CREATE OR REPLACE STREAM raw_trade.trade_transactions_stream
    ON TABLE raw_trade.trade_transactions
    APPEND_ONLY = TRUE
    COMMENT = '貿易取引テーブルの増分データを追跡する Stream (INSERT のみ)';

-- Stream の状態を確認 (作成直後は差分データなし)
SELECT * FROM raw_trade.trade_transactions_stream LIMIT 10;

-- Stream のメタデータを確認
SHOW STREAMS IN SCHEMA raw_trade;

/*----------------------------------------------------------------------------------
 2. 増分集計テーブルの作成と変換ロジック
    -------------------------------------------------
    拠点 (booking_branch) × 通貨 (currency_code) × 取引種別 (transaction_type)
    の粒度で、日ごとの件数と合計金額を集計します。

    Snowflake の Task + Stream では:
      - Stream が差分を自動追跡
      - Task が定期的に MERGE で増分反映
      - 失敗時は Task History で確認、自動リトライ可能
----------------------------------------------------------------------------------*/

CREATE OR REPLACE TABLE harmonized.trade_daily_agg_incremental
(
    trade_date          DATE,
    booking_branch      VARCHAR(20),
    currency_code       VARCHAR(3),
    transaction_type    VARCHAR(20),
    tx_count            NUMBER(18,0),
    total_amount        NUMBER(38,2),
    last_updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Task + Stream による増分集計テーブル (日次 × 拠点 × 通貨 × 取引種別)';

/*----------------------------------------------------------------------------------
 3. Task の作成 (MERGE INTO パターン)
    -------------------------------------------------
    Task はスケジュール実行されるジョブです。
    WHEN 句で Stream にデータがあるときだけ実行されるため、
    データが来ていないのに無駄に起動することがありません。

    MERGE INTO パターンを使うことで:
      - 既に同日・同拠点・同通貨・同取引種別の集計行がある → UPDATE (加算)
      - まだない → INSERT (新規作成)
    というべき等な増分処理を実現します。

    参考: https://docs.snowflake.com/ja/user-guide/tasks-intro
----------------------------------------------------------------------------------*/

CREATE OR REPLACE TASK harmonized.daily_trade_aggregate_task
    WAREHOUSE = fsi_de_wh
    SCHEDULE  = '5 MINUTE'          -- デモ用に短い間隔 (本番では CRON 式で夜間バッチを推奨)
    COMMENT   = 'Stream の差分データを MERGE で増分集計する Task'
    WHEN SYSTEM$STREAM_HAS_DATA('raw_trade.trade_transactions_stream')
AS
    MERGE INTO harmonized.trade_daily_agg_incremental AS tgt
    USING (
        -- Stream から差分データを集計
        SELECT
            trade_date,
            booking_branch,
            currency_code,
            transaction_type,
            COUNT(*)    AS tx_count,
            SUM(amount) AS total_amount
        FROM raw_trade.trade_transactions_stream
        GROUP BY trade_date, booking_branch, currency_code, transaction_type
    ) AS src
    ON  tgt.trade_date        = src.trade_date
    AND tgt.booking_branch    = src.booking_branch
    AND tgt.currency_code     = src.currency_code
    AND tgt.transaction_type  = src.transaction_type
    WHEN MATCHED THEN
        UPDATE SET
            tgt.tx_count        = tgt.tx_count + src.tx_count,
            tgt.total_amount    = tgt.total_amount + src.total_amount,
            tgt.last_updated_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN
        INSERT (trade_date, booking_branch, currency_code, transaction_type,
                tx_count, total_amount, last_updated_at)
        VALUES (src.trade_date, src.booking_branch, src.currency_code, src.transaction_type,
                src.tx_count, src.total_amount, CURRENT_TIMESTAMP());

-- Task の状態を確認 (作成直後は SUSPENDED)
SHOW TASKS IN SCHEMA harmonized;

/*----------------------------------------------------------------------------------
 4. Task の実行と確認
    -------------------------------------------------
    Task を RESUME して有効化し、テストデータを挿入して動作を確認します。
    Stream にデータが入ると、次回スケジュール時に Task が自動起動します。
    デモでは EXECUTE TASK で即時実行も行います。
----------------------------------------------------------------------------------*/

-- Task を有効化 (RESUME)
ALTER TASK harmonized.daily_trade_aggregate_task RESUME;

-- テスト用に新しい取引データを 5 件挿入
-- (Stream がこれをキャプチャします)
INSERT INTO raw_trade.trade_transactions
    (transaction_id, trade_date, settlement_date, customer_id,
     counterparty_country, transaction_type, currency_code, amount,
     booking_branch, instrument_type, free_text_notes, created_at)
VALUES
    ('TX-DEMO-0001', CURRENT_DATE(), DATEADD(day, 5, CURRENT_DATE()), 1,
     'US', 'EXPORT', 'USD', 5000000.00,
     'Tokyo', 'LC', 'Task + Stream デモ用テストデータ (1)', CURRENT_TIMESTAMP()),
    ('TX-DEMO-0002', CURRENT_DATE(), DATEADD(day, 3, CURRENT_DATE()), 2,
     'GB', 'IMPORT', 'GBP', 3200000.00,
     'London', 'TT', 'Task + Stream デモ用テストデータ (2)', CURRENT_TIMESTAMP()),
    ('TX-DEMO-0003', CURRENT_DATE(), DATEADD(day, 7, CURRENT_DATE()), 3,
     'SG', 'EXPORT', 'USD', 1500000.00,
     'Singapore', 'LC', 'Task + Stream デモ用テストデータ (3)', CURRENT_TIMESTAMP()),
    ('TX-DEMO-0004', CURRENT_DATE(), DATEADD(day, 4, CURRENT_DATE()), 4,
     'JP', 'REMITTANCE', 'JPY', 80000000.00,
     'Tokyo', 'TT', 'Task + Stream デモ用テストデータ (4)', CURRENT_TIMESTAMP()),
    ('TX-DEMO-0005', CURRENT_DATE(), DATEADD(day, 10, CURRENT_DATE()), 5,
     'DE', 'IMPORT', 'EUR', 2700000.00,
     'NewYork', 'DOC_COLL', 'Task + Stream デモ用テストデータ (5)', CURRENT_TIMESTAMP());

-- Stream にデータが溜まっていることを確認
SELECT * FROM raw_trade.trade_transactions_stream;

-- Task を即時実行 (スケジュールを待たずに手動トリガー)
EXECUTE TASK harmonized.daily_trade_aggregate_task;

-- 数秒待ってから結果を確認 (Task の実行には少し時間がかかります)
-- Snowsight の UI で カタログ > データベースエクスプローラー > fsi_zts_101 > HARMONIZED > Tasks からも
-- 実行履歴を確認できます。

-- 集計結果を確認
SELECT *
FROM harmonized.trade_daily_agg_incremental
ORDER BY trade_date DESC, booking_branch, currency_code;

-- Task の実行履歴を確認
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'daily_trade_aggregate_task',
    SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP())
))
ORDER BY scheduled_time DESC;

-- デモ後は Task を停止 (不要なウェアハウス起動を防ぐ)
ALTER TASK harmonized.daily_trade_aggregate_task SUSPEND;


/******************************************************************************
  Dynamic Tables  -- 宣言的パイプライン                  
 ******************************************************************************/

/*----------------------------------------------------------------------------------
 5. Dynamic Table とは
    -------------------------------------------------
    Dynamic Table は Snowflake のデータパイプラインを劇的に簡素化する機能です。
    「結果がどうあるべきか」を SQL で宣言するだけで、Snowflake が自動的に
    データを最新に保ちます。

    ┌─────────────────────────────────────────────────────────────────┐
    │              Task + Stream  vs  Dynamic Table 比較              │
    ├──────────────────┬──────────────────┬───────────────────────────┤
    │ 観点             │ Task + Stream    │ Dynamic Table             │
    ├──────────────────┼──────────────────┼───────────────────────────┤
    │ パラダイム       │ 命令的 (HOW)     │ 宣言的 (WHAT)             │
    │ 定義方法         │ MERGE/INSERT文   │ SELECT 文のみ             │
    │ 依存関係管理     │ 手動 (DAG 構築)  │ 自動解決                  │
    │ データ鮮度       │ SCHEDULE で制御  │ TARGET_LAG で制御         │
    │ エラーハンドリング│ 自前で実装       │ 組み込み (自動リトライ)   │
    │ 監視             │ TASK_HISTORY()   │ Snowsight DAG ビュー      │
    │ 推奨ユースケース │ 複雑な条件分岐   │ ETL / ELT パイプライン    │
    │                  │ 外部 API 連携    │ マテリアライズドビュー    │
    └──────────────────┴──────────────────┴───────────────────────────┘

    TARGET_LAG (データ鮮度):
      - '1 minute' : ほぼリアルタイム (コスト高)
      - '1 hour'   : 一般的な分析用途 (コストと鮮度のバランス)
      - '1 day'    : 日次バッチ相当 (低コスト)
      - DOWNSTREAM : 下流の Dynamic Table のラグに合わせて自動調整

    参考: https://docs.snowflake.com/ja/user-guide/dynamic-tables-about
----------------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------------
 6. 貿易取引の Dynamic Table 作成
    -------------------------------------------------
    setup.sql で作成した harmonized.trade_orders_v (ビュー) と同じロジックを
    Dynamic Table として作成します。
    ビューは毎回クエリ時に JOIN を実行しますが、Dynamic Table は結果を
    マテリアライズ (実体化) して保持するため、読み取りが高速です。

    これは「オンプレの夜間バッチで顧客マスタと取引データを JOIN して
    中間テーブルに書き出していた処理」に相当します。
----------------------------------------------------------------------------------*/

CREATE OR REPLACE DYNAMIC TABLE harmonized.trade_orders_dt
    TARGET_LAG = DOWNSTREAM
    WAREHOUSE  = fsi_de_wh
    COMMENT    = '貿易取引 + 顧客マスタの結合済み Dynamic Table (中間ノード: 下流のラグに従いリフレッシュ)'
AS
SELECT
    t.transaction_id,
    t.trade_date,
    t.settlement_date,
    t.customer_id,
    c.customer_name,
    c.region                AS customer_region,
    c.customer_segment,
    c.risk_rating,
    t.counterparty_country,
    t.transaction_type,
    t.currency_code,
    t.amount,
    t.booking_branch,
    t.instrument_type,
    t.free_text_notes,
    t.created_at
FROM raw_trade.trade_transactions t
LEFT JOIN raw_customer.customers c
    ON t.customer_id = c.customer_id;

-- Dynamic Table の初回データを確認 (初回リフレッシュに少し時間がかかる場合があります)
SELECT * FROM harmonized.trade_orders_dt LIMIT 20;

-- レコード数の確認
SELECT COUNT(*) AS row_count FROM harmonized.trade_orders_dt;

/*----------------------------------------------------------------------------------
 7. 日次取引サマリの Dynamic Table
    -------------------------------------------------
    Part A で Task + Stream を使って作った「日次集計」と同じロジックを
    Dynamic Table で実現します。わずか数行の SQL で同じ結果が得られます。

    さらにこの Dynamic Table は trade_orders_dt を参照しているため、
    Snowflake が自動的に依存関係 (DAG) を構築します:

      raw_trade.trade_transactions (ソーステーブル)
              ↓
      harmonized.trade_orders_dt        (TARGET_LAG = DOWNSTREAM)
              ↓                          → 自身ではリフレッシュスケジュールを持たず、
              ↓                            下流が必要とするタイミングでのみリフレッシュ
      analytics.daily_trade_summary_dt  (TARGET_LAG = '1 hour')
                                         → ビジネス要件「1時間以内の鮮度」を表現

    この設計により:
      - 末端 DT にのみ SLA (データ鮮度) を定義
      - 中間 DT は不要なリフレッシュを回避しコスト削減
      - DAG 全体が末端の TARGET_LAG に従って自動調整
----------------------------------------------------------------------------------*/

CREATE OR REPLACE DYNAMIC TABLE analytics.daily_trade_summary_dt
    TARGET_LAG = '1 hour'
    WAREHOUSE  = fsi_de_wh
    COMMENT    = '日次 × 拠点 × 通貨 × 取引種別の集計 Dynamic Table'
AS
SELECT
    trade_date,
    booking_branch,
    currency_code,
    transaction_type,
    COUNT(*)        AS tx_count,
    SUM(amount)     AS total_amount,
    AVG(amount)     AS avg_amount,
    MIN(amount)     AS min_amount,
    MAX(amount)     AS max_amount
FROM harmonized.trade_orders_dt
GROUP BY trade_date, booking_branch, currency_code, transaction_type;

-- 結果を確認
SELECT *
FROM analytics.daily_trade_summary_dt
ORDER BY trade_date DESC, total_amount DESC
LIMIT 20;

-- Part A の Task + Stream の結果と Dynamic Table の結果を比較
-- 双方に含まれる同じデータを出力 (同じ集計ロジックなのでデータは5行で出力するはず)
SELECT
    dt.trade_date,
    dt.booking_branch,
    dt.currency_code,
    dt.transaction_type,
    dt.tx_count   AS dt_tx_count,
    inc.tx_count  AS stream_tx_count,
    dt.total_amount  AS dt_total_amount,
    inc.total_amount AS stream_total_amount
FROM analytics.daily_trade_summary_dt dt
INNER JOIN harmonized.trade_daily_agg_incremental inc
    ON  dt.trade_date        = inc.trade_date
    AND dt.booking_branch    = inc.booking_branch
    AND dt.currency_code     = inc.currency_code
    AND dt.transaction_type  = inc.transaction_type
ORDER BY dt.trade_date DESC
LIMIT 20;

/*----------------------------------------------------------------------------------
 8. DAG 可視化 (Snowsight 手順)
    -------------------------------------------------
    Snowsight で Dynamic Table の依存関係 (DAG) をグラフィカルに確認できます。

    手順:
      1. Snowsight の左メニューで [データベースエクスプローラー] をクリック
      2. [データベース]における FSI_ZTS_101 を選択
      3. HARMONIZED スキーマを展開 → [動的テーブル] を展開
      4. trade_orders_dt をクリック
      5. 上部の [グラフ] タブをクリック

    DAG ビューでは以下が確認できます:
      - 各 Dynamic Table の TARGET_LAG 設定
      - 最終更新時刻
      - リフレッシュの状態 (成功 / 失敗 / 実行中)
      - 上流・下流の依存関係

    また、グラフ上のノードをクリックすると手動リフレッシュも可能です。
----------------------------------------------------------------------------------*/

-- 現在のデータベース内の全 Dynamic Table を一覧表示
SHOW DYNAMIC TABLES IN DATABASE fsi_zts_101;

-- Dynamic Table のリフレッシュ履歴を確認
SELECT *
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME => 'fsi_zts_101.harmonized.trade_orders_dt'
))
ORDER BY refresh_start_time DESC
LIMIT 10;

/*----------------------------------------------------------------------------------
 9. 法人営業データの分析クエリ (Dynamic Table の結果を活用)
    -------------------------------------------------
    Dynamic Table と既存のビューを活用して、法人営業データを分析します。
    これらのクエリは Streamlit ダッシュボードや BI ツール の
    バックエンドとしてそのまま使えるパターンです。
----------------------------------------------------------------------------------*/

-- 9-1. 営業担当者別パイプライン分析
-- 各営業担当者のパイプライン状況を可視化
SELECT
    sales_rep                                                    AS "営業担当者",
    COUNT(*)                                                     AS "案件数",
    SUM(won_flag)                                                AS "受注件数",
    SUM(lost_flag)                                               AS "失注件数",
    SUM(active_flag)                                             AS "進行中件数",
    ROUND(DIV0(SUM(won_flag),
          NULLIF(SUM(won_flag) + SUM(lost_flag), 0)) * 100, 1)  AS "受注率_pct",
    TO_CHAR(SUM(CASE WHEN stage = '受注'
                     THEN opportunity_amount END), '999,999,999,999') AS "受注額",
    TO_CHAR(SUM(CASE WHEN stage IN ('提案', '見積')
                     THEN opportunity_amount END), '999,999,999,999') AS "パイプライン残額"
FROM harmonized.corporate_sales_v
GROUP BY sales_rep
ORDER BY "受注率_pct" DESC;

-- 9-2. 業種別受注率分析
-- 業種ごとにどの程度の受注率があるかを把握
SELECT
    industry                                                      AS "業種",
    COUNT(*)                                                      AS "総案件数",
    SUM(won_flag)                                                 AS "受注件数",
    SUM(lost_flag)                                                AS "失注件数",
    ROUND(DIV0(SUM(won_flag),
          NULLIF(SUM(won_flag) + SUM(lost_flag), 0)) * 100, 1)   AS "受注率_pct",
    TO_CHAR(SUM(opportunity_amount), '999,999,999,999')           AS "総パイプライン額",
    TO_CHAR(SUM(CASE WHEN stage = '受注'
                     THEN opportunity_amount END), '999,999,999,999') AS "受注額",
    TO_CHAR(AVG(opportunity_amount), '999,999,999,999')           AS "平均案件単価"
FROM harmonized.corporate_sales_v
GROUP BY industry
ORDER BY "受注率_pct" DESC;

-- 9-3. 月次受注推移 (ウィンドウ関数: 累計合計)
-- expected_close_date を月単位で集計し、累積受注額を算出
-- ウィンドウ関数 SUM() OVER (ORDER BY ...) で累計を計算するパターン
SELECT
    close_month                                                    AS "受注予定月",
    monthly_won_count                                              AS "月次受注件数",
    TO_CHAR(monthly_won_amount, '999,999,999,999')                 AS "月次受注額",
    SUM(monthly_won_count)
        OVER (ORDER BY close_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)    AS "累計受注件数",
    TO_CHAR(
        SUM(monthly_won_amount)
            OVER (ORDER BY close_month
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
        '999,999,999,999')                                         AS "累計受注額"
FROM (
    SELECT
        DATE_TRUNC('month', expected_close_date)  AS close_month,
        COUNT(*)                                  AS monthly_won_count,
        SUM(opportunity_amount)                   AS monthly_won_amount
    FROM harmonized.corporate_sales_v
    WHERE stage = '受注'
    GROUP BY close_month
)
ORDER BY close_month;

-- 9-4. 地域 × 企業規模のクロス集計 (ピボット分析)
SELECT
    region                                                AS "地域",
    COUNT(CASE WHEN company_size = '大手' THEN 1 END)    AS "大手_件数",
    COUNT(CASE WHEN company_size = '中堅' THEN 1 END)    AS "中堅_件数",
    COUNT(CASE WHEN company_size = '中小' THEN 1 END)    AS "中小_件数",
    TO_CHAR(SUM(CASE WHEN company_size = '大手'
                     THEN opportunity_amount END), '999,999,999,999') AS "大手_金額",
    TO_CHAR(SUM(CASE WHEN company_size = '中堅'
                     THEN opportunity_amount END), '999,999,999,999') AS "中堅_金額",
    TO_CHAR(SUM(CASE WHEN company_size = '中小'
                     THEN opportunity_amount END), '999,999,999,999') AS "中小_金額"
FROM harmonized.corporate_sales_v
GROUP BY region
ORDER BY region;


/******************************************************************************
  まとめ                                           
 ******************************************************************************/

/*----------------------------------------------------------------------------------
 10. Task + Stream vs Dynamic Table: 比較と推奨
    -------------------------------------------------

    ┌──────────────────────────────────────────────────────────────────────┐
    │   Snowflake 移行のメリット                    │
    ├──────────────────────────────────────────────────────────────────────┤
    │                                                                      │
    │  [Snowflake Dynamic Table のメリット]                                │
    │   - SELECT 文だけで宣言 → 運用コードゼロ                            │
    │   - TARGET_LAG でデータ鮮度を SLA として定義                        │
    │   - 依存関係 (DAG) を Snowflake が自動構築・可視化                  │
    │   - 必要なときだけウェアハウスが起動 → コスト最適化                  │
    │   - 増分処理 (インクリメンタルリフレッシュ) を自動判定              │
    │   - Snowsight でリフレッシュ履歴・エラーを一元監視                  │
    │                                                                      │
    │  [推奨パターン]                                                      │
    │   - 標準的な ETL / ELT → Dynamic Table (まずこちらを検討)           │
    │   - 条件分岐・外部 API 連携・複雑なエラー処理 → Task + Stream       │
    │   - 両方を組み合わせることも可能                                      │
    └──────────────────────────────────────────────────────────────────────┘

----------------------------------------------------------------------------------*/

/*----------------------------------------------------------------------------------
 11. クリーンアップ
    -------------------------------------------------
    Task は明示的に SUSPEND しないとスケジュール通りに起動し続けます。
    Dynamic Table は DROP しない限りリフレッシュが継続されますが、
    後続セクションで使用する可能性があるため残しておきます。
----------------------------------------------------------------------------------*/

-- Task を確実に停止
ALTER TASK IF EXISTS harmonized.daily_trade_aggregate_task SUSPEND;

-- (オプション) 不要な場合は Dynamic Table を削除
-- DROP DYNAMIC TABLE IF EXISTS analytics.daily_trade_summary_dt;
-- DROP DYNAMIC TABLE IF EXISTS harmonized.trade_orders_dt;

-- セクション 3 完了
SELECT '--- セクション 3: データ変換 完了 ---' AS status,
       'Task + Stream による命令的パイプラインと Dynamic Table による宣言的パイプラインを体験しました。' AS summary,
       '次のステップ: セクション 4 (データガバナンス) に進んでください。' AS next_step;
