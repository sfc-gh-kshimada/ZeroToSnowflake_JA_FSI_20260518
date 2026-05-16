/***************************************************************************************************       
Asset:        FSI Zero to Snowflake - セットアップ
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

このスクリプトは、FSI 向け Zero to Snowflake ハンズオンに必要なリソースを一括作成します。

  1. データベース / スキーマ / ウェアハウスの作成
  2. ロール階層と権限付与
  3. ファイルフォーマット・内部ステージ (CSV / JSON / XML) の作成
  4. RAW ゾーンのテーブル定義 (貿易取引・顧客・参照データ・SWIFT 電文・Excel 取り込み先)
  5. 合成データ投入 (GENERATOR を使用、外部 S3 不要)
  6. Harmonized / Analytics / Semantic Layer のビュー作成
  7. Cortex / クロスリージョン設定 ('AWS_JP' で日本のみに限定)
  8. ウェアハウスのスケールダウン

実行ロール: ACCOUNTADMIN を推奨 (ハンズオン参加者は専用のトライアルアカウントを利用)
****************************************************************************************************/

USE ROLE sysadmin;
USE SECONDARY ROLES NONE;

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"setup"}}';

/*--
 1. データベース / スキーマ / ウェアハウスの作成
--*/

CREATE OR REPLACE DATABASE fsi_zts_101
COMMENT = 'FSI Zero to Snowflake ハンズオン用データベース (合成データ)';

CREATE OR REPLACE SCHEMA fsi_zts_101.raw_trade
COMMENT = '貿易取引・SWIFT 電文 (架空) の生データゾーン';

CREATE OR REPLACE SCHEMA fsi_zts_101.raw_customer
COMMENT = '顧客マスタ・参照データ (国・通貨) の生データゾーン';

CREATE OR REPLACE SCHEMA fsi_zts_101.raw_excel
COMMENT = 'Excel ファイル取り込み先の生データゾーン';

CREATE OR REPLACE SCHEMA fsi_zts_101.harmonized
COMMENT = '結合済みデータの harmonized レイヤ';

CREATE OR REPLACE SCHEMA fsi_zts_101.analytics
COMMENT = 'ビジネス分析向けの analytics レイヤ';

CREATE OR REPLACE SCHEMA fsi_zts_101.governance
COMMENT = 'マスキングポリシー・タグ・行アクセスポリシーを格納するガバナンスレイヤ';

CREATE OR REPLACE SCHEMA fsi_zts_101.semantic_layer
COMMENT = 'Cortex Analyst 向けセマンティックレイヤ';

-- ウェアハウス
CREATE OR REPLACE WAREHOUSE fsi_de_wh
    WAREHOUSE_SIZE = 'large'
    WAREHOUSE_TYPE = 'standard'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
COMMENT = 'FSI ZTS データエンジニアリング用ウェアハウス';

CREATE OR REPLACE WAREHOUSE fsi_dev_wh
    WAREHOUSE_SIZE = 'xsmall'
    WAREHOUSE_TYPE = 'standard'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
COMMENT = 'FSI ZTS 開発者用ウェアハウス';

CREATE OR REPLACE WAREHOUSE fsi_analyst_wh
    COMMENT = 'FSI ZTS アナリスト用マルチクラスタウェアハウス'
    WAREHOUSE_TYPE = 'standard'
    WAREHOUSE_SIZE = 'large'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'standard'
    AUTO_SUSPEND = 60
    INITIALLY_SUSPENDED = TRUE
    AUTO_RESUME = TRUE;

CREATE OR REPLACE WAREHOUSE fsi_cortex_wh
    WAREHOUSE_SIZE = 'LARGE'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
COMMENT = 'Cortex AI / Cortex Analyst 専用のラージウェアハウス';

/*--
 2. ロール階層と権限付与
--*/

USE ROLE securityadmin;

-- 機能ロール
CREATE ROLE IF NOT EXISTS fsi_admin           COMMENT = 'FSI ZTS 管理者ロール';
CREATE ROLE IF NOT EXISTS fsi_data_engineer   COMMENT = 'FSI ZTS データエンジニアロール';
CREATE ROLE IF NOT EXISTS fsi_developer       COMMENT = 'FSI ZTS 開発者ロール';
CREATE ROLE IF NOT EXISTS fsi_analyst         COMMENT = 'FSI ZTS アナリストロール';

-- ロール階層
GRANT ROLE fsi_admin           TO ROLE sysadmin;
GRANT ROLE fsi_data_engineer   TO ROLE fsi_admin;
GRANT ROLE fsi_developer       TO ROLE fsi_data_engineer;
GRANT ROLE fsi_analyst         TO ROLE fsi_data_engineer;

-- アカウント横断権限
USE ROLE accountadmin;
GRANT IMPORTED PRIVILEGES ON DATABASE snowflake TO ROLE fsi_data_engineer;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE fsi_admin;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE fsi_data_engineer;
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE fsi_data_engineer;

-- データベース・スキーマ権限
USE ROLE securityadmin;

GRANT USAGE ON DATABASE fsi_zts_101 TO ROLE fsi_admin;
GRANT USAGE ON DATABASE fsi_zts_101 TO ROLE fsi_data_engineer;
GRANT USAGE ON DATABASE fsi_zts_101 TO ROLE fsi_developer;
GRANT USAGE ON DATABASE fsi_zts_101 TO ROLE fsi_analyst;

GRANT USAGE ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_admin;
GRANT USAGE ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_data_engineer;
GRANT USAGE ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_developer;
GRANT USAGE ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_analyst;

-- スキーマ権限: DB 内の全スキーマに一括付与
GRANT ALL ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_admin;
GRANT ALL ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_data_engineer;
GRANT ALL ON ALL SCHEMAS IN DATABASE fsi_zts_101 TO ROLE fsi_developer;

-- ウェアハウス権限
GRANT OWNERSHIP ON WAREHOUSE fsi_de_wh TO ROLE fsi_admin COPY CURRENT GRANTS;
GRANT ALL ON WAREHOUSE fsi_de_wh        TO ROLE fsi_admin;
GRANT ALL ON WAREHOUSE fsi_de_wh        TO ROLE fsi_data_engineer;
GRANT ALL ON WAREHOUSE fsi_dev_wh       TO ROLE fsi_admin;
GRANT ALL ON WAREHOUSE fsi_dev_wh       TO ROLE fsi_data_engineer;
GRANT ALL ON WAREHOUSE fsi_dev_wh       TO ROLE fsi_developer;
GRANT ALL ON WAREHOUSE fsi_analyst_wh   TO ROLE fsi_admin;
GRANT ALL ON WAREHOUSE fsi_analyst_wh   TO ROLE fsi_data_engineer;
GRANT ALL ON WAREHOUSE fsi_analyst_wh   TO ROLE fsi_analyst;
GRANT ALL ON WAREHOUSE fsi_cortex_wh    TO ROLE fsi_admin;
GRANT ALL ON WAREHOUSE fsi_cortex_wh    TO ROLE fsi_data_engineer;
GRANT ALL ON WAREHOUSE fsi_cortex_wh    TO ROLE fsi_developer;

-- 将来作成されるオブジェクトへの自動権限付与 (DB レベル一括)
GRANT ALL ON FUTURE TABLES IN DATABASE fsi_zts_101 TO ROLE fsi_admin;
GRANT ALL ON FUTURE TABLES IN DATABASE fsi_zts_101 TO ROLE fsi_data_engineer;
GRANT ALL ON FUTURE TABLES IN DATABASE fsi_zts_101 TO ROLE fsi_developer;
GRANT ALL ON FUTURE VIEWS  IN DATABASE fsi_zts_101 TO ROLE fsi_admin;
GRANT ALL ON FUTURE VIEWS  IN DATABASE fsi_zts_101 TO ROLE fsi_data_engineer;
GRANT ALL ON FUTURE VIEWS  IN DATABASE fsi_zts_101 TO ROLE fsi_developer;

-- マスキングポリシー / 行アクセスポリシー / タグ / DMF
USE ROLE accountadmin;
GRANT APPLY MASKING POLICY    ON ACCOUNT TO ROLE fsi_admin;
GRANT APPLY MASKING POLICY    ON ACCOUNT TO ROLE fsi_data_engineer;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE fsi_admin;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE fsi_data_engineer;
GRANT APPLY TAG               ON ACCOUNT TO ROLE fsi_admin;
GRANT APPLY TAG               ON ACCOUNT TO ROLE fsi_data_engineer;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE fsi_admin;

-- アナリスト向け権限
GRANT ALL ON SCHEMA fsi_zts_101.harmonized TO ROLE fsi_analyst;
GRANT ALL ON SCHEMA fsi_zts_101.analytics  TO ROLE fsi_analyst;
GRANT OPERATE, USAGE ON WAREHOUSE fsi_analyst_wh TO ROLE fsi_analyst;

-- Cortex 関連
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE fsi_developer;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE fsi_data_engineer;
GRANT USAGE ON SCHEMA fsi_zts_101.harmonized TO ROLE fsi_developer;
GRANT USAGE ON WAREHOUSE fsi_cortex_wh       TO ROLE fsi_developer;

/*--
 3. ファイルフォーマット・内部ステージの作成
    -------------------------------------------------
    セクション 2(a) のデータロード用に CSV / JSON / XML
    の各ファイルフォーマットと内部ステージを事前作成します。
    実際のサンプルファイル (assets/sample_data/) は
    Snowsight UI または PUT コマンドでアップロードします。
--*/

USE ROLE sysadmin;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;

-- public スキーマにファイルフォーマットを集約
CREATE OR REPLACE FILE FORMAT fsi_zts_101.public.csv_ff
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
NULL_IF = ('NULL', 'null', '');

CREATE OR REPLACE FILE FORMAT fsi_zts_101.public.json_ff
TYPE = 'JSON'
STRIP_OUTER_ARRAY = TRUE;

CREATE OR REPLACE FILE FORMAT fsi_zts_101.public.xml_ff
TYPE = 'XML'
STRIP_OUTER_ELEMENT = TRUE;

-- データ形式別の内部ステージ (Git リポジトリ → COPY FILES → 内部ステージ → COPY INTO で取り込む)
-- Section 8 で Git リポジトリからファイルを転送し、Section 2 で COPY INTO テーブルに取り込む
CREATE OR REPLACE STAGE fsi_zts_101.raw_trade.csv_stage
COMMENT = 'CSV ファイル取り込み用の内部ステージ'
FILE_FORMAT = fsi_zts_101.public.csv_ff;

CREATE OR REPLACE STAGE fsi_zts_101.raw_trade.json_stage
COMMENT = 'JSON ファイル取り込み用の内部ステージ'
FILE_FORMAT = fsi_zts_101.public.json_ff;

CREATE OR REPLACE STAGE fsi_zts_101.raw_trade.xml_stage
COMMENT = 'XML (SWIFT MX 電文 ISO 20022) ファイル取り込み用の内部ステージ'
FILE_FORMAT = fsi_zts_101.public.xml_ff;

-- Excel 取り込み用ステージ (セクション 2(b) で使用)
CREATE OR REPLACE STAGE fsi_zts_101.raw_excel.excel_demo_stage
COMMENT = 'Excel ファイル取り込み用の内部ステージ (法人営業データ)';

-- Excel 処理済みファイルのアーカイブステージ
CREATE OR REPLACE STAGE fsi_zts_101.raw_excel.excel_archive_stage
COMMENT = '処理済み Excel ファイルの退避先。取り込み完了後に COPY FILES で移動される';

/*--
 4. RAW ゾーン テーブル定義
--*/

-- 国マスタ (参照データ)
CREATE OR REPLACE TABLE fsi_zts_101.raw_customer.countries
(
    country_code   VARCHAR(2),    -- ISO 3166-1 alpha-2
    country_name   VARCHAR(100),
    region         VARCHAR(20)    -- Tokyo / US / UK / APAC など仮想拠点
);

-- 通貨マスタ (参照データ)
CREATE OR REPLACE TABLE fsi_zts_101.raw_customer.currencies
(
    currency_code  VARCHAR(3),    -- ISO 4217
    currency_name  VARCHAR(50),
    decimal_places NUMBER(2,0)
);

-- 顧客マスタ (架空)
CREATE OR REPLACE TABLE fsi_zts_101.raw_customer.customers
(
    customer_id        NUMBER(38,0),
    customer_name      VARCHAR(200),       -- 顧客担当者名 (個人の PII — マスキング対象)
    contact_email      VARCHAR(200),       -- マスキング対象 (PII)
    contact_phone      VARCHAR(50),        -- マスキング対象 (PII)
    country_code       VARCHAR(2),
    region             VARCHAR(20),
    customer_segment   VARCHAR(20),        -- CORPORATE / SME / RETAIL
    onboarded_date     DATE,
    risk_rating        VARCHAR(10)         -- LOW / MEDIUM / HIGH
);

-- 貿易取引 (架空。実際の SWIFT MX 電文構造を簡略化)
CREATE OR REPLACE TABLE fsi_zts_101.raw_trade.trade_transactions
(
    transaction_id       VARCHAR(20),       -- TX-YYYYMMDD-NNNN
    trade_date           DATE,
    settlement_date      DATE,
    customer_id          NUMBER(38,0),
    counterparty_country VARCHAR(2),
    transaction_type     VARCHAR(20),       -- IMPORT / EXPORT / REMITTANCE
    currency_code        VARCHAR(3),
    amount               NUMBER(18,2),      -- マスキング対象 (取引額)
    booking_branch       VARCHAR(20),       -- Tokyo / NewYork / London / Singapore
    instrument_type      VARCHAR(30),       -- LC / TT / DOC_COLL
    free_text_notes      VARCHAR(2000),     -- Cortex AI 解析対象
    created_at           TIMESTAMP_NTZ
);

-- セクション 2(a) で XML ファイル (ISO 20022 SWIFT MX 電文 pacs.008 / camt.053) から取り込む先
-- setup 時点では空。Section 8 で Git リポジトリから内部ステージに転送後、
-- Section 2(a) の COPY INTO で VARIANT 列に取り込みます。
-- 取り込み後は XMLGET / : (パス記法) で MsgId / Amt / Ccy などの要素を抽出します。
CREATE OR REPLACE TABLE fsi_zts_101.raw_trade.swift_messages_xml
(
    message_id           VARCHAR(40),       -- ISO 20022 GrpHdr/MsgId
    received_at          TIMESTAMP_NTZ,
    message_type         VARCHAR(20),       -- pacs.008 / pacs.009 / camt.053 / pain.001 など
    payload              VARIANT,           -- COPY INTO で XML を VARIANT として格納
    source_file          VARCHAR(500)
);

-- セクション 2(a) で JSON ファイルから取り込む先 (setup 時点では空)
CREATE OR REPLACE TABLE fsi_zts_101.raw_customer.customers_json_raw
(
    raw_payload  VARIANT,
    source_file  VARCHAR(500),
    loaded_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- セクション 2(a) で CSV ファイルから取り込む先 (setup 時点では空、補完サンプル)
CREATE OR REPLACE TABLE fsi_zts_101.raw_trade.trade_transactions_csv_raw
(
    transaction_id       VARCHAR(20),
    trade_date           DATE,
    settlement_date      DATE,
    customer_id          NUMBER(38,0),
    counterparty_country VARCHAR(2),
    transaction_type     VARCHAR(20),
    currency_code        VARCHAR(3),
    amount               NUMBER(18,2),
    booking_branch       VARCHAR(20),
    instrument_type      VARCHAR(30),
    free_text_notes      VARCHAR(2000),
    source_file          VARCHAR(500),
    loaded_at            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 手動 Excel 取り込み先: 法人営業 (Corporate Sales) データ
-- セクション 2(b) で @raw_excel.excel_demo_stage に 格納 した excelファイルを→ Snowpark Stored Procedure で取り込みます。
-- ユースケース: 法人向け営業活動データをより高度に 可視化・分析 
CREATE OR REPLACE TABLE fsi_zts_101.raw_excel.corporate_sales
(
    deal_id              VARCHAR(20),       -- 案件ID
    sales_rep            VARCHAR(100),      -- 営業担当者 (Row Access Policy 適用候補)
    customer_name        VARCHAR(200),      -- 法人顧客名 (PII マスキング候補)
    industry             VARCHAR(50),       -- 業種 (製造 / 金融 / IT / 小売 / サービス / 公共)
    company_size         VARCHAR(20),       -- 企業規模 (大手 / 中堅 / 中小)
    opportunity_amount   NUMBER(18,2),      -- 見込み額 (取引額しきい値マスキング候補)
    stage                VARCHAR(20),       -- 案件ステージ (提案 / 見積 / 受注 / 失注)
    region               VARCHAR(20),       -- 地域 (関東 / 関西 / 中部 / 九州 / 海外)
    last_visit_date      DATE,              -- 最終訪問日
    expected_close_date  DATE,              -- 受注予定日
    loaded_at            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_file          VARCHAR(500)
);

/*--
 5. 合成データの投入 (GENERATOR を使用、外部 S3 不要)
    注: SWIFT MX 風 XML / 補完用 CSV / JSON はファイルとして
        セクション 2(a) でアップロード→ COPY INTO します。
--*/

-- 国マスタ (12 か国)
INSERT INTO fsi_zts_101.raw_customer.countries (country_code, country_name, region) VALUES
    ('JP', 'Japan',          'Tokyo'),
    ('US', 'United States',  'US'),
    ('GB', 'United Kingdom', 'UK'),
    ('SG', 'Singapore',      'APAC'),
    ('HK', 'Hong Kong',      'APAC'),
    ('AU', 'Australia',      'APAC'),
    ('DE', 'Germany',        'EU'),
    ('FR', 'France',         'EU'),
    ('CN', 'China',          'APAC'),
    ('KR', 'South Korea',    'APAC'),
    ('TH', 'Thailand',       'APAC'),
    ('IN', 'India',          'APAC');

-- 通貨マスタ (ISO 4217)
INSERT INTO fsi_zts_101.raw_customer.currencies (currency_code, currency_name, decimal_places) VALUES
    ('JPY', 'Japanese Yen',         0),
    ('USD', 'US Dollar',            2),
    ('GBP', 'Pound Sterling',       2),
    ('EUR', 'Euro',                 2),
    ('SGD', 'Singapore Dollar',     2),
    ('HKD', 'Hong Kong Dollar',     2),
    ('AUD', 'Australian Dollar',    2),
    ('CNY', 'Chinese Yuan',         2),
    ('KRW', 'South Korean Won',     0),
    ('THB', 'Thai Baht',            2),
    ('INR', 'Indian Rupee',         2);

-- 顧客マスタ (50,000 件 — リアルな人名で生成)
-- 日本語名 60% (姓50種 × 名50種 = 2,500パターン) + 英語名 40% (First50 × Last50 = 2,500パターン)
-- SYSTEM$CLASSIFY が SEMANTIC_CATEGORY = 'NAME' を正しく検出するためリアルな人名にしている
INSERT INTO fsi_zts_101.raw_customer.customers (
    customer_id, customer_name, contact_email, contact_phone,
    country_code, region, customer_segment, onboarded_date, risk_rating
)
SELECT
    SEQ4() + 1 AS customer_id,
    -- 人名を生成: 前半 30,000 件 = 日本語 (姓50×名50=2,500パターン), 後半 20,000 件 = 英語
    -- SYSTEM$CLASSIFY が SEMANTIC_CATEGORY = 'NAME' を正しく検出するためリアルな人名にする
    CASE
      WHEN MOD(SEQ4(), 5) < 3 THEN
        -- 日本語 (60%): 姓 + ' ' + 名
        DECODE(MOD(FLOOR(SEQ4() / 50), 50),
            0, '佐藤', 1, '鈴木', 2, '高橋', 3, '田中', 4, '渡辺',
            5, '伊藤', 6, '山本', 7, '中村', 8, '小林', 9, '加藤',
            10, '吉田', 11, '山田', 12, '佐々木', 13, '松本', 14, '井上',
            15, '木村', 16, '林', 17, '清水', 18, '斎藤', 19, '森',
            20, '池田', 21, '橋本', 22, '阿部', 23, '石川', 24, '前田',
            25, '藤田', 26, '岡田', 27, '後藤', 28, '長谷川', 29, '村上',
            30, '近藤', 31, '坂本', 32, '遠藤', 33, '青木', 34, '藤井',
            35, '西村', 36, '福田', 37, '太田', 38, '三浦', 39, '岡本',
            40, '松田', 41, '中川', 42, '中野', 43, '原田', 44, '小野',
            45, '竹内', 46, '金子', 47, '和田', 48, '中山', 49, '石井')
        || ' ' ||
        DECODE(MOD(SEQ4(), 50),
            0, '太郎', 1, '花子', 2, '一郎', 3, '裕子', 4, '健二',
            5, '麻衣', 6, '明', 7, '理恵', 8, '大輝', 9, '恵',
            10, '翔太', 11, '美咲', 12, '拓也', 13, '由美', 14, '浩二',
            15, '真由美', 16, '達也', 17, '久美子', 18, '直樹', 19, '恵子',
            20, '雄大', 21, '千尋', 22, '和也', 23, '紀子', 24, '隆',
            25, '智子', 26, '修', 27, '陽子', 28, '誠', 29, '幸子',
            30, '亮', 31, '愛', 32, '健太', 33, '美穂', 34, '淳',
            35, '綾', 36, '大介', 37, '麻美', 38, '勇気', 39, '沙織',
            40, '圭介', 41, '瞳', 42, '将太', 43, '舞', 44, '哲也',
            45, '彩', 46, '慎一', 47, '菜々子', 48, '悠斗', 49, '桜')
      ELSE
        -- 英語 (40%): First + ' ' + Last
        DECODE(MOD(SEQ4(), 50),
            0, 'James', 1, 'Mary', 2, 'Robert', 3, 'Patricia', 4, 'John',
            5, 'Jennifer', 6, 'Michael', 7, 'Linda', 8, 'David', 9, 'Elizabeth',
            10, 'William', 11, 'Barbara', 12, 'Richard', 13, 'Susan', 14, 'Joseph',
            15, 'Jessica', 16, 'Thomas', 17, 'Sarah', 18, 'Christopher', 19, 'Karen',
            20, 'Charles', 21, 'Lisa', 22, 'Daniel', 23, 'Nancy', 24, 'Matthew',
            25, 'Betty', 26, 'Anthony', 27, 'Margaret', 28, 'Mark', 29, 'Sandra',
            30, 'Donald', 31, 'Ashley', 32, 'Steven', 33, 'Dorothy', 34, 'Paul',
            35, 'Kimberly', 36, 'Andrew', 37, 'Emily', 38, 'Joshua', 39, 'Donna',
            40, 'Kenneth', 41, 'Michelle', 42, 'Kevin', 43, 'Carol', 44, 'Brian',
            45, 'Amanda', 46, 'George', 47, 'Melissa', 48, 'Timothy', 49, 'Deborah')
        || ' ' ||
        DECODE(MOD(FLOOR(SEQ4() / 50), 50),
            0, 'Smith', 1, 'Johnson', 2, 'Williams', 3, 'Brown', 4, 'Jones',
            5, 'Garcia', 6, 'Miller', 7, 'Davis', 8, 'Rodriguez', 9, 'Martinez',
            10, 'Hernandez', 11, 'Lopez', 12, 'Gonzalez', 13, 'Wilson', 14, 'Anderson',
            15, 'Thomas', 16, 'Taylor', 17, 'Moore', 18, 'Jackson', 19, 'Martin',
            20, 'Lee', 21, 'Perez', 22, 'Thompson', 23, 'White', 24, 'Harris',
            25, 'Sanchez', 26, 'Clark', 27, 'Ramirez', 28, 'Lewis', 29, 'Robinson',
            30, 'Walker', 31, 'Young', 32, 'Allen', 33, 'King', 34, 'Wright',
            35, 'Scott', 36, 'Torres', 37, 'Nguyen', 38, 'Hill', 39, 'Flores',
            40, 'Green', 41, 'Adams', 42, 'Nelson', 43, 'Baker', 44, 'Hall',
            45, 'Rivera', 46, 'Campbell', 47, 'Mitchell', 48, 'Carter', 49, 'Roberts')
    END AS customer_name,
    'contact' || (SEQ4() + 1) || '@example-fsi.com' AS contact_email,
    '+81-3-' || LPAD(UNIFORM(1000, 9999, RANDOM(1)), 4, '0') || '-' || LPAD(UNIFORM(1000, 9999, RANDOM(2)), 4, '0') AS contact_phone,
    DECODE(ROUND(UNIFORM(0, 11, RANDOM(3))),
        0, 'JP', 1, 'US', 2, 'GB', 3, 'SG', 4, 'HK', 5, 'AU',
        6, 'DE', 7, 'FR', 8, 'CN', 9, 'KR', 10, 'TH', 11, 'IN') AS country_code,
    DECODE(ROUND(UNIFORM(0, 4, RANDOM(4))),
        0, 'Tokyo', 1, 'US', 2, 'UK', 3, 'APAC', 4, 'EU')        AS region,
    DECODE(ROUND(UNIFORM(0, 2, RANDOM(5))),
        0, 'CORPORATE', 1, 'SME', 2, 'RETAIL')                   AS customer_segment,
    DATEADD(day, -1 * UNIFORM(0, 3650, RANDOM(6)), CURRENT_DATE()) AS onboarded_date,
    DECODE(ROUND(UNIFORM(0, 2, RANDOM(7))),
        0, 'LOW', 1, 'MEDIUM', 2, 'HIGH')                        AS risk_rating
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

-- 貿易取引 (1,000,000 件、過去 3 年分)
-- 金額分布: 対数正規分布を近似 (少額取引が多数 + 大口取引が少数)
-- free_text_notes: 日本語/英語混在で 30 パターン以上 (Cortex AI の分類精度デモに最適)
INSERT INTO fsi_zts_101.raw_trade.trade_transactions (
    transaction_id, trade_date, settlement_date, customer_id,
    counterparty_country, transaction_type, currency_code, amount,
    booking_branch, instrument_type, free_text_notes, created_at
)
SELECT
    'TX-' || TO_VARCHAR(DATEADD(day, -1 * UNIFORM(0, 1095, RANDOM(11)), CURRENT_DATE()), 'YYYYMMDD') || '-' || LPAD(SEQ4() + 1, 7, '0') AS transaction_id,
    DATEADD(day, -1 * UNIFORM(0, 1095, RANDOM(11)), CURRENT_DATE()) AS trade_date,
    DATEADD(day, UNIFORM(2, 30, RANDOM(12)), DATEADD(day, -1 * UNIFORM(0, 1095, RANDOM(11)), CURRENT_DATE())) AS settlement_date,
    UNIFORM(1, 50000, RANDOM(13))                      AS customer_id,
    DECODE(ROUND(UNIFORM(0, 11, RANDOM(14))),
        0, 'JP', 1, 'US', 2, 'GB', 3, 'SG', 4, 'HK', 5, 'AU',
        6, 'DE', 7, 'FR', 8, 'CN', 9, 'KR', 10, 'TH', 11, 'IN') AS counterparty_country,
    DECODE(ROUND(UNIFORM(0, 2, RANDOM(15))),
        0, 'IMPORT', 1, 'EXPORT', 2, 'REMITTANCE')              AS transaction_type,
    DECODE(ROUND(UNIFORM(0, 7, RANDOM(16))),
        0, 'JPY', 1, 'USD', 2, 'EUR', 3, 'GBP',
        4, 'SGD', 5, 'HKD', 6, 'AUD', 7, 'CNY')                AS currency_code,
    -- 対数正規分布を近似: EXP(NORMAL(15, 3)) で 数千円〜数百億円の幅を生成
    -- 中央値 ≈ 3,300万円、95%タイル ≈ 13億円、最大 ≈ 100億円+
    ROUND(LEAST(EXP(NORMAL(15, 3, RANDOM(17))), 50000000000), 2) AS amount,
    DECODE(ROUND(UNIFORM(0, 3, RANDOM(18))),
        0, 'Tokyo', 1, 'NewYork', 2, 'London', 3, 'Singapore') AS booking_branch,
    DECODE(ROUND(UNIFORM(0, 2, RANDOM(19))),
        0, 'LC', 1, 'TT', 2, 'DOC_COLL')                       AS instrument_type,
    -- 30 パターンの free_text_notes (英語 20 + 日本語 10)
    -- Cortex AI の CLASSIFY / SENTIMENT デモで多様な分類結果を得るためバリエーションを確保
    DECODE(ROUND(UNIFORM(0, 29, RANDOM(20))),
        -- 英語 (Standard / Urgent / Suspicious / Dispute / VIP)
        0,  'Standard transaction. No issues reported.',
        1,  'Routine payment processed within normal parameters.',
        2,  'Regular settlement. All documentation verified.',
        3,  'Counterparty requested expedited settlement due to year-end closing.',
        4,  'Urgent: client requires same-day value. Escalated to operations.',
        5,  'Priority processing requested. Deadline T+0 settlement.',
        6,  'Suspicious pattern detected. Manual review escalated to compliance.',
        7,  'AML flag raised. Transaction amount exceeds threshold. Pending SAR filing.',
        8,  'Unusual transaction pattern: multiple small transfers to same beneficiary.',
        9,  'Potential sanctions match on counterparty name. Requires enhanced due diligence.',
        10, 'Customer disputed amount; resolved after reconciliation.',
        11, 'Beneficiary claims non-receipt. Investigation opened. Ref: INV-2026-0042.',
        12, 'Partial payment received. Shortfall of 15%. Customer notified.',
        13, 'Amendment request: incorrect beneficiary account. Awaiting corrected details.',
        14, 'High-priority client. Premium handling.',
        15, 'VIP client instruction. Relationship manager approval obtained.',
        16, 'White-glove service. Board-level transaction requiring CEO sign-off.',
        17, 'Cross-border regulatory requirement met. Documentation filed with central bank.',
        18, 'Trade finance: Letter of Credit confirmed. Advising bank notified.',
        19, 'Documentary collection: Documents released against payment.',
        -- 日本語 (通常 / 緊急 / 不正検知 / 紛争 / VIP)
        20, '通常取引。問題なし。',
        21, '定例の仕入代金支払い。書類確認完了。',
        22, '年度末決算に伴い早期決済を依頼されました。営業部承認済み。',
        23, '緊急: 顧客より当日中の着金を要請。オペレーション部門へエスカレーション。',
        24, 'AMLフラグ: 短期間に同一受取人への少額送金が複数回検出。コンプライアンス部門にて精査中。',
        25, '取引先名が制裁リストと部分一致。EDD(強化された顧客管理)を実施。',
        26, '顧客より金額相違の申告あり。調査の結果、為替レート差異と判明。解決済み。',
        27, '受取人より未着の連絡あり。中継銀行へトレーサー送信。回答待ち。',
        28, '重要顧客(プライベートバンキング)。担当マネージャー承認取得済み。',
        29, '信用状(L/C)開設完了。通知銀行への連絡済み。船積書類待ち。'
    ) AS free_text_notes,
    DATEADD(second, -1 * UNIFORM(0, 94608000, RANDOM(21)), CURRENT_TIMESTAMP()) AS created_at
FROM TABLE(GENERATOR(ROWCOUNT => 1000000));

-- 法人営業 (Corporate Sales) — 5,000 件
-- メイン経路はセクション 2(b) で Excel ファイルからの取り込み (100 行)。
-- setup では 5,000 件を投入し、パイプライン分析 / ウィンドウ関数 / Dynamic Tables の
-- 演習で十分なデータ量を確保します。
INSERT INTO fsi_zts_101.raw_excel.corporate_sales (
    deal_id, sales_rep, customer_name, industry, company_size,
    opportunity_amount, stage, region, last_visit_date, expected_close_date,
    source_file
)
SELECT
    'DEAL-' || LPAD(SEQ4() + 1, 7, '0') AS deal_id,
    -- 営業担当 20 名 (Section 4 の Row Access Policy 演習用に充実)
    DECODE(ROUND(UNIFORM(0, 19, RANDOM(101))),
        0,  'sato.taro',       1,  'suzuki.hanako',    2,  'takahashi.ichiro',
        3,  'tanaka.yuki',     4,  'watanabe.kenji',   5,  'ito.mai',
        6,  'yamamoto.akira',  7,  'nakamura.rie',     8,  'kobayashi.daiki',
        9,  'kato.megumi',     10, 'yoshida.hiroshi',  11, 'yamada.sakura',
        12, 'sasaki.ryota',    13, 'matsumoto.ayumi',  14, 'inoue.shota',
        15, 'kimura.haruka',   16, 'hayashi.takeshi',  17, 'shimizu.nana',
        18, 'saito.kentaro',   19, 'mori.yui') AS sales_rep,
    -- 法人顧客名 — 営業先の法人名 (架空企業名 100 パターン)
    -- ※ raw_customer.customers の customer_name は「個人名」、
    --    こちらの customer_name は「法人名」で PII の性質が異なる
    DECODE(MOD(ROUND(UNIFORM(0, 99, RANDOM(102))), 100),
        0, '株式会社アルファ商事',      1, '株式会社ベータ製作所',       2, 'ガンマホールディングス',
        3, 'デルタ電機株式会社',         4, 'イプシロン物流株式会社',     5, '株式会社ゼータコーポレーション',
        6, 'エータ精密工業',             7, 'シータ・テクノロジーズ',      8, '株式会社イオタファイナンス',
        9, 'カッパ・ソリューションズ',   10, 'ラムダ・キャピタル',          11, '株式会社ミュー・ロジスティクス',
        12, 'ニュー・エネルギー株式会社', 13, 'クサイ重工業',               14, 'オミクロン食品株式会社',
        15, '株式会社パイ通信',          16, '株式会社ロー不動産',          17, 'シグマ建設株式会社',
        18, 'タウ医薬品株式会社',         19, 'ウプシロン証券',              20, 'ファイ・インシュアランス',
        21, 'カイ・アセットマネジメント', 22, 'プサイ情報システム',          23, 'オメガ・パートナーズ',
        24, '北海道フロンティア商事',     25, '東北マテリアル株式会社',      26, '関東テクノサービス',
        27, '中部オートメーション',       28, '関西フードサイエンス',        29, '中国地方開発株式会社',
        30, '四国マリンプロダクツ',       31, '九州エナジー株式会社',        32, '沖縄リゾートグループ',
        33, '第一生命エンジニアリング',   34, '三友化学工業',               35, '大和精密機器',
        36, '新日本テレコム',             37, '東洋エレクトロニクス',        38, '西部運輸株式会社',
        39, '南方貿易株式会社',           40, '北陸電子工業',               41, '信越バイオテック',
        42, '常磐エネルギー',             43, '京浜重機工業',               44, '阪神物流システム',
        45, '紀州化成株式会社',           46, '播磨鋼材',                   47, '但馬農産加工',
        48, '丹波食品工業',               49, '摂津半導体',                 50, '河内精密',
        51, '大阪ロジテック',             52, '名古屋メカトロニクス',        53, '横浜マリンサービス',
        54, '札幌デジタルラボ',           55, '仙台クリエイティブ',          56, '広島オプティクス',
        57, '福岡ソフトウェア開発',       58, '神戸トレーディング',          59, '京都アドバンス',
        60, '千葉ネットワーク',           61, '埼玉メディカル',             62, '静岡プレシジョン',
        63, '新潟アグリテック',           64, '長野クリーンエナジー',        65, '岡山データサイエンス',
        66, '熊本インフラ開発',           67, '鹿児島バイオファーム',        68, '金沢クラフト',
        69, '富山マテリアル',             70, '松山テクノパーク',            71, '高松フィナンシャル',
        72, '徳島ライフサイエンス',       73, '山口ケミカル',               74, '佐賀エンバイロメント',
        75, '長崎シッピング',             76, '大分オートモーティブ',        77, '宮崎サンライズ',
        78, '青森ウッドプロダクツ',       79, '岩手鋼構造',                 80, '秋田エコシステム',
        81, '山形プレシジョン工業',       82, '福島再生エネルギー',          83, '茨城セラミックス',
        84, '栃木オプトエレクトロ',       85, '群馬スチール',               86, '山梨ワイナリーズ',
        87, '三重石油化学',               88, '滋賀環境テック',             89, '奈良ファーマシー',
        90, '和歌山マリンフーズ',         91, '鳥取ジオパーク',             92, '島根メタル',
        93, '香川デジタルソリューション', 94, '愛媛シトラスグループ',        95, '高知アクアテック',
        96, '沖縄トロピカルフーズ',       97, '北九州スチール',             98, '中央コンサルタンツ',
        99, '日本ブリッジテクノ') AS customer_name,
    DECODE(ROUND(UNIFORM(0, 5, RANDOM(103))),
        0, '製造', 1, '金融', 2, 'IT', 3, '小売', 4, 'サービス', 5, '公共') AS industry,
    DECODE(ROUND(UNIFORM(0, 9, RANDOM(104))),
        0, '大手', 1, '大手',
        2, '中堅', 3, '中堅', 4, '中堅',
        5, '中小', 6, '中小', 7, '中小', 8, '中小', 9, '中小') AS company_size,
    -- 見込み額: 対数正規分布 (中央値 ≈ 5000万円、最大50億円)
    ROUND(LEAST(EXP(NORMAL(17.7, 1.5, RANDOM(105))), 5000000000), 0) AS opportunity_amount,
    DECODE(ROUND(UNIFORM(0, 19, RANDOM(106))),
        0, '提案', 1, '提案', 2, '提案', 3, '提案', 4, '提案', 5, '提案',
        6, '見積', 7, '見積', 8, '見積', 9, '見積', 10, '見積', 11, '見積',
        12, '受注', 13, '受注', 14, '受注', 15, '受注', 16, '受注',
        17, '失注', 18, '失注', 19, '失注') AS stage,
    DECODE(ROUND(UNIFORM(0, 9, RANDOM(107))),
        0, '関東', 1, '関東', 2, '関東', 3, '関東', 4, '関東',
        5, '関西', 6, '関西',
        7, '中部',
        8, '九州',
        9, '海外') AS region,
    DATEADD(day, -1 * UNIFORM(0, 365, RANDOM(108)), CURRENT_DATE()) AS last_visit_date,
    DATEADD(day, UNIFORM(0, 365, RANDOM(109)), CURRENT_DATE()) AS expected_close_date,
    'setup_synthetic' AS source_file
FROM TABLE(GENERATOR(ROWCOUNT => 5000));

/*--
 6. Harmonized / Analytics / Semantic Layer のビュー作成
--*/

CREATE OR REPLACE VIEW fsi_zts_101.harmonized.trade_orders_v
COMMENT = '貿易取引と顧客マスタを結合した harmonized ビュー'
AS
SELECT
    t.*,
    c.customer_name,
    c.contact_email,
    c.contact_phone,
    c.region AS customer_region,
    c.customer_segment,
    c.risk_rating
FROM fsi_zts_101.raw_trade.trade_transactions t
LEFT JOIN fsi_zts_101.raw_customer.customers c
    ON t.customer_id = c.customer_id;

CREATE OR REPLACE VIEW fsi_zts_101.analytics.daily_trade_summary_v
COMMENT = '日次・通貨別・拠点別の貿易取引集計ビュー'
AS
SELECT
    trade_date,
    booking_branch,
    currency_code,
    transaction_type,
    COUNT(*)        AS tx_count,
    SUM(amount)     AS total_amount,
    AVG(amount)     AS avg_amount
FROM fsi_zts_101.raw_trade.trade_transactions
GROUP BY trade_date, booking_branch, currency_code, transaction_type;

CREATE OR REPLACE VIEW fsi_zts_101.analytics.customer_trade_summary_v
COMMENT = '顧客別の累計取引額・件数サマリ'
AS
SELECT
    c.customer_id,
    c.customer_name,
    c.region,
    c.customer_segment,
    c.risk_rating,
    COUNT(t.transaction_id)                   AS tx_count,
    SUM(t.amount)                             AS total_amount,
    MAX(t.trade_date)                         AS latest_trade_date
FROM fsi_zts_101.raw_customer.customers c
LEFT JOIN fsi_zts_101.raw_trade.trade_transactions t
    ON c.customer_id = t.customer_id
GROUP BY c.customer_id, c.customer_name, c.region, c.customer_segment, c.risk_rating;

CREATE OR REPLACE VIEW fsi_zts_101.semantic_layer.trade_orders_v
COMMENT = 'Cortex Analyst 向けの整形済み貿易取引ビュー (PII 除外)'
AS
SELECT
    transaction_id, trade_date, settlement_date,
    customer_id::VARCHAR AS customer_id,
    customer_region, customer_segment, risk_rating,
    counterparty_country, transaction_type, currency_code,
    amount, booking_branch, instrument_type
FROM fsi_zts_101.harmonized.trade_orders_v;

-- 法人営業データを参照する harmonized ビュー
CREATE OR REPLACE VIEW fsi_zts_101.harmonized.corporate_sales_v
COMMENT = '法人営業データを正規化した harmonized ビュー'
AS
SELECT *,
    CASE WHEN stage = '受注' THEN 1 ELSE 0 END AS won_flag,
    CASE WHEN stage = '失注' THEN 1 ELSE 0 END AS lost_flag,
    CASE WHEN stage IN ('提案', '見積') THEN 1 ELSE 0 END AS active_flag
FROM fsi_zts_101.raw_excel.corporate_sales;

-- 営業担当者別パフォーマンスサマリ (Section 3 / 4 演習用)
CREATE OR REPLACE VIEW fsi_zts_101.analytics.sales_rep_performance_v
COMMENT = '営業担当者別の案件件数・受注率・受注額サマリ'
AS
SELECT
    sales_rep,
    COUNT(*)                                                      AS total_deals,
    SUM(won_flag)                                                 AS won_deals,
    SUM(lost_flag)                                                AS lost_deals,
    SUM(active_flag)                                              AS active_deals,
    DIV0(SUM(won_flag), NULLIF(SUM(won_flag) + SUM(lost_flag), 0)) AS win_rate,
    SUM(CASE WHEN stage = '受注' THEN opportunity_amount END)     AS won_amount,
    SUM(opportunity_amount)                                       AS pipeline_amount
FROM fsi_zts_101.harmonized.corporate_sales_v
GROUP BY sales_rep;

-- 業種別パイプラインサマリ (Section 3 演習用)
CREATE OR REPLACE VIEW fsi_zts_101.analytics.sales_pipeline_summary_v
COMMENT = '業種・ステージ別の案件件数・金額サマリ'
AS
SELECT
    industry,
    company_size,
    region,
    stage,
    COUNT(*)                AS deal_count,
    SUM(opportunity_amount) AS total_amount,
    AVG(opportunity_amount) AS avg_amount
FROM fsi_zts_101.harmonized.corporate_sales_v
GROUP BY industry, company_size, region, stage;

-- Cortex Analyst 向けの法人営業ビュー (PII 除外、自然言語 BI 対応)
CREATE OR REPLACE VIEW fsi_zts_101.semantic_layer.corporate_sales_v
COMMENT = 'Cortex Analyst 向けの法人営業ビュー (顧客名は除外)'
AS
SELECT deal_id, sales_rep, industry, company_size,
       opportunity_amount, stage, region, last_visit_date, expected_close_date
FROM fsi_zts_101.harmonized.corporate_sales_v;

USE ROLE securityadmin;
GRANT SELECT ON VIEW fsi_zts_101.semantic_layer.trade_orders_v        TO ROLE PUBLIC;
GRANT SELECT ON VIEW fsi_zts_101.semantic_layer.corporate_sales_v     TO ROLE PUBLIC;
GRANT SELECT ON VIEW fsi_zts_101.analytics.daily_trade_summary_v      TO ROLE PUBLIC;
GRANT SELECT ON VIEW fsi_zts_101.analytics.customer_trade_summary_v   TO ROLE PUBLIC;
GRANT SELECT ON VIEW fsi_zts_101.analytics.sales_rep_performance_v    TO ROLE PUBLIC;
GRANT SELECT ON VIEW fsi_zts_101.analytics.sales_pipeline_summary_v   TO ROLE PUBLIC;

/*--
 7. Cortex / クロスリージョン設定
--*/

USE ROLE accountadmin;

-- Cortex のクロスリージョン推論を日本国内に限定して有効化
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_JP';

/*--
 8. Git リポジトリ統合
    ────────────────────────────────────────────────────────────────
    GitHub リポジトリを Snowflake Workspaces に接続 → SQL ファイルを Snowsight で編集・実行
--*/

-- 8.1 API Integration (GitHub HTTPS 用 — Workspaces 連携)
CREATE OR REPLACE API INTEGRATION git_api_integration
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kshimada/')
    ENABLED = TRUE;

-- 8.2 Git Repository オブジェクト作成 (SQL ファイル用 — Workspaces から接続)
CREATE OR REPLACE GIT REPOSITORY fsi_zts_101.public.fsi_zts_repo
    API_INTEGRATION = git_api_integration
    ORIGIN = 'https://github.com/sfc-gh-kshimada/ZeroToSnowflake_JA_FSI_20260518.git';

ALTER GIT REPOSITORY fsi_zts_101.public.fsi_zts_repo FETCH;

-- 8.3 Git リポジトリからサンプルデータを内部ステージに転送
--     S3 外部ステージが使えない場合のフォールバック経路:
--       Git Repository Stage → COPY FILES → 内部ステージ → COPY INTO テーブル (Section 2)
--
--     ※ Git Repository Stage から直接 COPY INTO テーブルはサポートされていないため、
--       必ず内部ステージを経由する必要がある

-- CSV サンプルデータ → 内部ステージ
COPY FILES INTO @fsi_zts_101.raw_trade.csv_stage
  FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/trade_csv/;

-- JSON サンプルデータ → 内部ステージ
COPY FILES INTO @fsi_zts_101.raw_trade.json_stage
  FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/customer_json/;

-- XML (SWIFT MX 電文) サンプルデータ → 内部ステージ
COPY FILES INTO @fsi_zts_101.raw_trade.xml_stage
  FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/swift_xml/;

-- Excel サンプルデータ → 内部ステージ (SP の session.file.get_stream 用)
COPY FILES INTO @fsi_zts_101.raw_excel.excel_demo_stage
  FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/excel/;

-- 転送結果確認
LIST @fsi_zts_101.raw_trade.csv_stage;
LIST @fsi_zts_101.raw_trade.json_stage;
LIST @fsi_zts_101.raw_trade.xml_stage;
LIST @fsi_zts_101.raw_excel.excel_demo_stage;

/*--
 9. ウェアハウスのスケールダウン (コスト最適化)
--*/

USE ROLE sysadmin;
ALTER WAREHOUSE fsi_de_wh SET WAREHOUSE_SIZE = 'XSmall';

-- セットアップ完了
SELECT '✓ FSI Zero To Snowflake セットアップが完了しました。' AS status,
       'fsi_zts_101 データベース・スキーマ・ロール・合成データ・Git連携 が利用可能です。' AS message,
       '次のステップ: Snowsight Workspaces で「From Git repository」から https://github.com/sfc-gh-kshimada/ZeroToSnowflake_JA_FSI_20260518 へ接続し、' ||
       'scripts/ 配下の SQL を順次実行してください。' ||
       'サンプルデータは Git リポジトリから内部ステージに転送済みです。' AS next_step;
