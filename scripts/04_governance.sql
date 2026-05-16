/***************************************************************************************************
Asset:        FSI Zero to Snowflake - ガバナンス
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

セクション 4 - ガバナンス (40 分)
  1. タグの作成と付与
  2. ダイナミックデータマスキング (タグベース)
  3. 行アクセスポリシー (Row Access Policy)
  4. Access History / Query History
  5. データ分類 (Classification) と Trust Center
  6. まとめとクリーンアップ

前提条件:
  - setup.sql を実行済み (データベース・スキーマ・テーブル・ロール作成済み)
  - fsi_zts_101.governance スキーマが存在すること
  - raw_trade.trade_transactions / raw_customer.customers / raw_excel.corporate_sales にデータが存在すること
****************************************************************************************************/

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"governance"}}';

USE ROLE fsi_admin;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;

/*----------------------------------------------------------------------------------
 0. 事前準備: アナリストロールにデモ用の SELECT 権限を付与
    -------------------------------------------------
    通常の運用では RAW ゾーンへのアナリスト直接アクセスは推奨しませんが、
    このセクションではマスキング・行アクセスの「効果を体感する」ために
    一時的に SELECT を付与します。

    ポイント:
      金融機関の本番環境では、アナリストは harmonized / analytics レイヤの
      ビューのみにアクセスし、RAW データへの直接アクセスは禁止するのが
      ベストプラクティスです。ビューに適用されたマスキングポリシーは、
      参照元テーブルのタグベースポリシーが自動的に適用されます。
----------------------------------------------------------------------------------*/

USE ROLE securityadmin;

-- アナリストが RAW テーブルを直接クエリできるよう一時権限を付与
GRANT USAGE ON SCHEMA fsi_zts_101.raw_customer TO ROLE fsi_analyst;
GRANT USAGE ON SCHEMA fsi_zts_101.raw_trade    TO ROLE fsi_analyst;
GRANT USAGE ON SCHEMA fsi_zts_101.raw_excel    TO ROLE fsi_analyst;
GRANT SELECT ON TABLE fsi_zts_101.raw_customer.customers        TO ROLE fsi_analyst;
GRANT SELECT ON TABLE fsi_zts_101.raw_trade.trade_transactions  TO ROLE fsi_analyst;
GRANT SELECT ON TABLE fsi_zts_101.raw_excel.corporate_sales     TO ROLE fsi_analyst;

-- ウェアハウスの利用権限 (fsi_analyst_wh は setup.sql で付与済みだが、fsi_de_wh も追加)
GRANT USAGE ON WAREHOUSE fsi_de_wh TO ROLE fsi_analyst;

USE ROLE fsi_admin;

/*----------------------------------------------------------------------------------
 1. タグの作成と付与  ~5分
    -------------------------------------------------
    Snowflake のオブジェクトタグ (Object Tagging) は、テーブル・カラム・
    スキーマなどのメタデータとして任意のキーバリューペアを付与する機能です。

    金融機関のガバナンスにおける活用例:
      - PII (個人情報) カラムの特定と追跡
      - 取引額など機密性の高い財務データの分類
      - 規制要件 (GDPR / 個人情報保護法 / FISC) 対応のカラム管理

    タグの ALLOWED_VALUES を指定すると、付与できる値を制限でき、
    分類の一貫性を保証できます。

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/object-tagging
----------------------------------------------------------------------------------*/

-- PII タグ: 個人情報の種類を分類
CREATE OR REPLACE TAG fsi_zts_101.governance.pii_tag
    ALLOWED_VALUES 'NAME', 'EMAIL', 'PHONE'
    COMMENT = '個人情報 (PII) を分類するタグ。NAME / EMAIL / PHONE の 3 種類';

-- 財務金額タグ: 取引額・見込み額など金額カラムを分類
CREATE OR REPLACE TAG fsi_zts_101.governance.financial_amount_tag
    ALLOWED_VALUES 'TRADE_AMOUNT', 'DEAL_AMOUNT'
    COMMENT = '財務金額カラムを分類するタグ。TRADE_AMOUNT / DEAL_AMOUNT の 2 種類';

/*
    タグをカラムに付与します。
    ALTER TABLE ... MODIFY COLUMN ... SET TAG 構文を使用します。

    銀行のデータガバナンスでは、PII カラムへの一貫したタグ付けが
    マスキングポリシーの自動適用 (タグベースマスキング) の前提条件となります。
*/

-- === 顧客マスタ (raw_customer.customers) ===
ALTER TABLE fsi_zts_101.raw_customer.customers
    MODIFY COLUMN customer_name SET TAG fsi_zts_101.governance.pii_tag = 'NAME';

ALTER TABLE fsi_zts_101.raw_customer.customers
    MODIFY COLUMN contact_email SET TAG fsi_zts_101.governance.pii_tag = 'EMAIL';

ALTER TABLE fsi_zts_101.raw_customer.customers
    MODIFY COLUMN contact_phone SET TAG fsi_zts_101.governance.pii_tag = 'PHONE';

-- === 法人営業データ (raw_excel.corporate_sales) ===
ALTER TABLE fsi_zts_101.raw_excel.corporate_sales
    MODIFY COLUMN customer_name SET TAG fsi_zts_101.governance.pii_tag = 'NAME';

-- === 貿易取引 (raw_trade.trade_transactions) — 金額カラム ===
ALTER TABLE fsi_zts_101.raw_trade.trade_transactions
    MODIFY COLUMN amount SET TAG fsi_zts_101.governance.financial_amount_tag = 'TRADE_AMOUNT';

-- === 法人営業データ — 見込み額カラム ===
ALTER TABLE fsi_zts_101.raw_excel.corporate_sales
    MODIFY COLUMN opportunity_amount SET TAG fsi_zts_101.governance.financial_amount_tag = 'DEAL_AMOUNT';

-- タグの付与状況を確認する
-- TAG_REFERENCES 関数でテーブル内の全タグ付きカラムを一覧取得
SELECT *
FROM TABLE(fsi_zts_101.information_schema.tag_references_all_columns(
    'fsi_zts_101.raw_customer.customers', 'TABLE'));

SELECT *
FROM TABLE(fsi_zts_101.information_schema.tag_references_all_columns(
    'fsi_zts_101.raw_trade.trade_transactions', 'TABLE'));

SELECT *
FROM TABLE(fsi_zts_101.information_schema.tag_references_all_columns(
    'fsi_zts_101.raw_excel.corporate_sales', 'TABLE'));


/*----------------------------------------------------------------------------------
 2. ダイナミックデータマスキング (タグベース)  ~10分
    -------------------------------------------------
    ダイナミックデータマスキングは、クエリ実行時にカラムの値を
    リアルタイムでマスク処理する機能です。元データは変更されません。

    本セクションの核心: タグベースマスキング
    ─────────────────────────────────────────
    一般的なマスキングポリシーはカラム単位で個別に適用しますが、
    タグベースマスキングでは「タグにポリシーを紐づける」ことで、
    同じタグが付与されたすべてのカラムに一括適用されます。

    エンタープライズ環境での利点:
      - 数百テーブル × 数千カラムに対して個別設定が不要
      - 新しいテーブルにタグを付けるだけでマスキングが自動適用
      - ポリシーの一元管理 (governance スキーマ)
      - 監査時にタグ → ポリシー の対応関係を即座に把握可能

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/tag-based-masking-policies
----------------------------------------------------------------------------------*/

-- PII マスキングポリシー: STRING 型の個人情報をマスク
-- fsi_admin / fsi_data_engineer は平文で閲覧可能、それ以外は '***MASKED***'
CREATE OR REPLACE MASKING POLICY fsi_zts_101.governance.pii_mask
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('FSI_ADMIN', 'FSI_DATA_ENGINEER') THEN val
        ELSE '***MASKED***'
    END
    COMMENT = 'PII 文字列マスキング: 管理者・DE は平文、その他はマスク';

-- 金額しきい値マスキングポリシー: 高額取引をアナリストから隠蔽
-- 1 億円 (100,000,000) 超の取引額はアナリストには NULL で非表示
CREATE OR REPLACE MASKING POLICY fsi_zts_101.governance.amount_threshold_mask
    AS (val NUMBER) RETURNS NUMBER ->
    CASE
        WHEN CURRENT_ROLE() IN ('FSI_ADMIN', 'FSI_DATA_ENGINEER') THEN val
        WHEN val > 100000000 THEN NULL   -- 1 億超はアナリストに非表示
        ELSE val
    END
    COMMENT = '金額しきい値マスキング: 1 億超はアナリストに NULL';

/*
    ★ ここがポイント: タグにマスキングポリシーを紐づけます。
    ALTER TAG ... SET MASKING POLICY 構文を使用することで、
    そのタグが付与されたすべてのカラムにポリシーが自動適用されます。

    これにより:
      pii_tag = 'NAME' / 'EMAIL' / 'PHONE' が付いた全カラム → pii_mask が適用
      financial_amount_tag = 'TRADE_AMOUNT' / 'DEAL_AMOUNT' が付いた全カラム → amount_threshold_mask が適用
*/
ALTER TAG fsi_zts_101.governance.pii_tag
    SET MASKING POLICY fsi_zts_101.governance.pii_mask;

ALTER TAG fsi_zts_101.governance.financial_amount_tag
    SET MASKING POLICY fsi_zts_101.governance.amount_threshold_mask;


-- ===== マスキングの動作確認 =====

-- まず、マスキング適用前の状態を fsi_admin (管理者) で確認
-- → 平文が見える
USE ROLE fsi_admin;

SELECT customer_name, contact_email, contact_phone
FROM fsi_zts_101.raw_customer.customers
LIMIT 5;

-- 金額も全額表示される
SELECT transaction_id, amount, booking_branch
FROM fsi_zts_101.raw_trade.trade_transactions
WHERE amount > 100000000
LIMIT 5;

/*
    ★ ロールを fsi_analyst に切り替えて同じクエリを実行します。
    マスキングポリシーの効果を体感してください。
*/

USE ROLE fsi_analyst;
USE WAREHOUSE fsi_de_wh;

-- PII がマスクされていることを確認 → customer_name / contact_email / contact_phone が '***MASKED***'
SELECT customer_name, contact_email, contact_phone
FROM fsi_zts_101.raw_customer.customers
LIMIT 5;

-- 1 億超の取引額が NULL になっていることを確認
SELECT transaction_id, amount, booking_branch
FROM fsi_zts_101.raw_trade.trade_transactions
ORDER BY amount DESC NULLS FIRST
LIMIT 10;

-- 法人営業データでも同様にマスキングが効いている
-- customer_name → '***MASKED***', opportunity_amount で 1 億超 → NULL
SELECT deal_id, customer_name, opportunity_amount, stage
FROM fsi_zts_101.raw_excel.corporate_sales
ORDER BY opportunity_amount DESC NULLS FIRST
LIMIT 10;

/*
    ★ ロールを fsi_data_engineer に切り替えると平文が見える
    → ロールベースのきめ細かいアクセス制御が確認できます
*/
USE ROLE fsi_data_engineer;

SELECT customer_name, contact_email, contact_phone
FROM fsi_zts_101.raw_customer.customers
LIMIT 5;

-- harmonized ビュー経由でもマスキングが効くことを確認
-- → タグベースマスキングは元テーブルのカラムを参照するビューにも自動伝播
USE ROLE fsi_analyst;
USE WAREHOUSE fsi_de_wh;

SELECT transaction_id, customer_name, contact_email, amount
FROM fsi_zts_101.harmonized.trade_orders_v
LIMIT 5;


/*----------------------------------------------------------------------------------
 3. 行アクセスポリシー (Row Access Policy)  ~10分
    -------------------------------------------------
    行アクセスポリシー (RAP) は、ユーザーのロール・属性に応じて
    テーブルの行レベルでアクセスを制御する機能です。

    金融機関での典型的なユースケース:
      A) 拠点別データ分離: Tokyo 拠点の担当者は Tokyo の取引のみ閲覧
      B) 営業担当者別の案件フィルタ: 自分が担当する案件のみ閲覧

    本セクションではシナリオ A (拠点別) を実装し、
    シナリオ B (営業担当者別) はパターン紹介にとどめます。

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/security-row-intro
----------------------------------------------------------------------------------*/

USE ROLE fsi_admin;

/*
    シナリオ A: 拠点別データ分離 (booking_branch ベース)
    ─────────────────────────────────────────
    - fsi_admin / fsi_data_engineer → すべての拠点のデータを閲覧可
    - fsi_analyst → Tokyo 拠点のデータのみ閲覧可
    
    本番環境では、ロール→拠点のマッピングテーブルを使うのが一般的ですが、
    ハンズオンでは簡潔さのために CASE 式で直接記述します。
*/

CREATE OR REPLACE ROW ACCESS POLICY fsi_zts_101.governance.branch_row_access
    AS (branch VARCHAR) RETURNS BOOLEAN ->
    -- 管理者・DE・開発者は全拠点アクセス可
    CURRENT_ROLE() IN ('FSI_ADMIN', 'FSI_DATA_ENGINEER', 'FSI_DEVELOPER', 'ACCOUNTADMIN')
    OR
    -- アナリストは Tokyo 拠点のみ
    (CURRENT_ROLE() = 'FSI_ANALYST' AND branch = 'Tokyo')
    COMMENT = '拠点別行アクセスポリシー: アナリストは Tokyo のみ';


-- ★ まず適用前の状態を確認 (全拠点が見える)
USE ROLE fsi_analyst;
USE WAREHOUSE fsi_de_wh;

SELECT DISTINCT booking_branch, COUNT(*) AS tx_count
FROM fsi_zts_101.raw_trade.trade_transactions
GROUP BY booking_branch
ORDER BY booking_branch;

-- ★ 行アクセスポリシーを適用
USE ROLE fsi_admin;

ALTER TABLE fsi_zts_101.raw_trade.trade_transactions
    ADD ROW ACCESS POLICY fsi_zts_101.governance.branch_row_access
    ON (booking_branch);

-- ★ 適用後: fsi_analyst で同じクエリを実行 → Tokyo のみ表示される
USE ROLE fsi_analyst;
USE WAREHOUSE fsi_de_wh;

SELECT DISTINCT booking_branch, COUNT(*) AS tx_count
FROM fsi_zts_101.raw_trade.trade_transactions
GROUP BY booking_branch
ORDER BY booking_branch;

-- Tokyo 拠点の取引件数を確認 (全体の約 25% = 約 12,500 件)
SELECT COUNT(*) AS tokyo_tx_count
FROM fsi_zts_101.raw_trade.trade_transactions;

-- ★ fsi_data_engineer では全拠点が見える
USE ROLE fsi_data_engineer;

SELECT DISTINCT booking_branch, COUNT(*) AS tx_count
FROM fsi_zts_101.raw_trade.trade_transactions
GROUP BY booking_branch
ORDER BY booking_branch;


/*
    シナリオ B: 営業担当者別の案件アクセス制御 (参考パターン)
    ─────────────────────────────────────────────────
    本番環境で営業担当者ベースの行アクセスを実装する場合、
    「Snowflake ユーザー名 → 営業担当者名」のマッピングテーブルを
    使用するのが一般的です。

    実装パターン (コンセプト):

    -- 1. マッピングテーブルを作成
    CREATE TABLE governance.user_salesrep_mapping (
        snowflake_user  VARCHAR,
        sales_rep       VARCHAR
    );

    -- 2. マッピングデータを投入
    INSERT INTO governance.user_salesrep_mapping VALUES
        ('SATO_USER',     'sato.taro'),
        ('SUZUKI_USER',   'suzuki.hanako'),
        ...;

    -- 3. 行アクセスポリシーを作成
    CREATE ROW ACCESS POLICY governance.salesrep_row_access
        AS (rep VARCHAR) RETURNS BOOLEAN ->
        CURRENT_ROLE() IN ('FSI_ADMIN', 'FSI_DATA_ENGINEER')
        OR EXISTS (
            SELECT 1 FROM governance.user_salesrep_mapping
            WHERE snowflake_user = CURRENT_USER()
              AND sales_rep = rep
        );

    -- 4. テーブルに適用
    ALTER TABLE raw_excel.corporate_sales
        ADD ROW ACCESS POLICY governance.salesrep_row_access
        ON (sales_rep);

    この設計により、AD グループ → Snowflake ロール のマッピングと組み合わせて
    「誰が何を見られるか」をテーブル駆動で管理できます。
*/


/*----------------------------------------------------------------------------------
 4. Access History / Query History  ~10分
    -------------------------------------------------
    Snowflake は「誰が」「いつ」「どのカラムに」アクセスしたかを
    自動的に記録しています。金融機関の規制対応 (監査対応) において
    極めて重要な機能です。

    主要ビュー:
      - snowflake.account_usage.access_history    (カラムレベルのアクセス記録)
      - snowflake.account_usage.query_history     (クエリ実行履歴)
      - INFORMATION_SCHEMA.QUERY_HISTORY()        (リアルタイム版、直近 7 日)

    注意: account_usage ビューには最大 45 分の遅延があります。
          ハンズオン中にデータが表示されない場合は遅延が原因です。

    公式ドキュメント:
      https://docs.snowflake.com/ja/sql-reference/account-usage/access_history
      https://docs.snowflake.com/ja/sql-reference/account-usage/query_history
----------------------------------------------------------------------------------*/

USE ROLE fsi_admin;
USE WAREHOUSE fsi_de_wh;

/*
    4-1. Access History: 誰がどのテーブル・カラムにアクセスしたか
    ─────────────────────────────────────────────────
    access_history ビューの base_objects_accessed / direct_objects_accessed 
    カラムに、アクセスされたオブジェクトとカラムの情報が ARRAY で格納されています。

    注意: このクエリはセッション開始から 45 分以上経過してから結果が反映されます。
          データが 0 件の場合は時間をおいて再実行してください。
*/

SELECT
    query_id,
    query_start_time,
    user_name,
    direct_objects_accessed,
    base_objects_accessed
FROM snowflake.account_usage.access_history
WHERE query_start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND ARRAY_SIZE(base_objects_accessed) > 0
ORDER BY query_start_time DESC
LIMIT 10;

/*
    4-2. Access History から特定テーブルへのアクセスを抽出
    ─────────────────────────────────────────────────
    FLATTEN を使って base_objects_accessed 配列を展開し、
    customers テーブルへのアクセスを抽出します。
    
    カラムレベルのアクセス記録も確認できます:
      obj.value:"columns" にアクセスされたカラム名が配列で格納されています。
*/

SELECT
    h.query_id,
    h.query_start_time,
    h.user_name,
    obj.value:"objectName"::STRING AS accessed_object,
    obj.value:"columns" AS accessed_columns
FROM snowflake.account_usage.access_history h,
    LATERAL FLATTEN(input => h.base_objects_accessed) obj
WHERE h.query_start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND obj.value:"objectName"::STRING ILIKE '%CUSTOMERS%'
ORDER BY h.query_start_time DESC
LIMIT 10;

/*
    4-3. Query History: 直近のクエリ実行履歴
    ─────────────────────────────────────────────────
    query_history ビューでは実行されたクエリのテキスト、
    実行時間、スキャンされた行数などを確認できます。
*/

SELECT
    query_id,
    query_text,
    user_name,
    role_name,
    warehouse_name,
    execution_status,
    start_time,
    total_elapsed_time
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND database_name = 'FSI_ZTS_101'
ORDER BY start_time DESC
LIMIT 10;

/*
    4-4. INFORMATION_SCHEMA.QUERY_HISTORY() — リアルタイム版
    ─────────────────────────────────────────────────
    account_usage ビューの 45 分遅延を待てない場合は、
    INFORMATION_SCHEMA のテーブル関数を使用します。
    直近 7 日分のクエリ履歴をリアルタイムで取得できます。

    ハンズオン中はこちらが確実に結果を返します。
*/

SELECT
    query_id,
    SUBSTR(query_text, 1, 100) AS query_text_preview,
    user_name,
    role_name,
    execution_status,
    start_time,
    total_elapsed_time
FROM TABLE(information_schema.query_history(
    dateadd('hours', -1, current_timestamp()),
    current_timestamp(),
    result_limit => 20
))
WHERE database_name = 'FSI_ZTS_101'
ORDER BY start_time DESC;


/*----------------------------------------------------------------------------------
 5. データ分類 (Classification) と Trust Center  ~5分
    -------------------------------------------------
    Snowflake のデータ分類機能は、テーブル内のカラムを自動的にスキャンし、
    個人情報 (PII) や機密データを検出して分類タグを付与します。

    金融機関での活用:
      - 新しいテーブルを取り込んだ際の PII 自動検出
      - GDPR / 個人情報保護法対応のデータカタログ作成
      - セキュリティ監査時のエビデンス生成

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/classify-ui-trust-center
----------------------------------------------------------------------------------*/

USE ROLE fsi_admin;

/*
    SYSTEM$CLASSIFY を使用して顧客マスタを自動分類します。
    'auto_tag': true を指定すると、検出された PII カラムに
    Snowflake の組み込み分類タグ (SEMANTIC_CATEGORY / PRIVACY_CATEGORY) が
    自動的に付与されます。

    実行には数秒〜数十秒かかります。
*/

CALL SYSTEM$CLASSIFY('fsi_zts_101.raw_customer.customers', {'auto_tag': true});

-- 分類結果を確認: Snowflake が自動付与した分類タグを確認
SELECT *
FROM TABLE(fsi_zts_101.information_schema.tag_references_all_columns(
    'fsi_zts_101.raw_customer.customers', 'TABLE'))
ORDER BY column_name;

/*
    上記の結果で、Snowflake が自動的に検出した分類が確認できます:
      - customer_name  → SEMANTIC_CATEGORY = 'NAME' / PRIVACY_CATEGORY = 'IDENTIFIER'
      - contact_email  → SEMANTIC_CATEGORY = 'EMAIL' / PRIVACY_CATEGORY = 'IDENTIFIER'
      - contact_phone  → SEMANTIC_CATEGORY = 'PHONE_NUMBER' / PRIVACY_CATEGORY = 'IDENTIFIER'

    セクション 1 で手動付与した governance.pii_tag と合わせて、
    「手動分類」と「自動分類」の両方が 1 つのテーブルに共存していることが分かります。

    ★ Trust Center について
    ─────────────────────────────────────────────────
    Snowsight の 管理者 → セキュリティ → Trust Center から
    アカウント全体のセキュリティスキャン結果を確認できます:

      - Security Essentials: MFA 未設定ユーザー、ネットワークポリシー未設定など
      - CIS Benchmark: CIS Snowflake Benchmark に基づくコンプライアンスチェック
      - Threat Intelligence: 異常なアクセスパターンの検出

    金融機関では、定期的に Trust Center のスキャン結果を確認し、
    セキュリティリスクの早期発見に活用することが推奨されます。
*/


/*----------------------------------------------------------------------------------
 6. まとめとクリーンアップ
    -------------------------------------------------
    このセクションで学んだデータガバナンス機能の全体像:

    ┌────────────────────┬──────────────────────────────────────┐
    │ 機能               │ 用途                                 │
    ├────────────────────┼──────────────────────────────────────┤
    │ オブジェクトタグ     │ PII・機密データのカラム分類           │
    │ タグベースマスキング  │ タグ単位でのマスキング一括適用        │
    │ 行アクセスポリシー   │ 拠点別・担当者別のデータ分離          │
    │ Access History     │ カラムレベルのアクセス監査             │
    │ Query History      │ クエリ実行履歴の監査                  │
    │ データ分類          │ PII の自動検出と分類タグ付与           │
    │ Trust Center       │ セキュリティリスクの包括的スキャン      │
    └────────────────────┴──────────────────────────────────────┘

    銀行の AD グループ → Snowflake ロール マッピング設計パターン:
    ─────────────────────────────────────────────────
    実際の運用では、Active Directory (AD) グループと Snowflake ロールを
    SCIM プロビジョニング等で同期し、以下のような構成にします:

    ┌───────────────────────┬──────────────────────┬────────────────────────────┐
    │ AD グループ            │ Snowflake ロール      │ アクセス範囲               │
    ├───────────────────────┼──────────────────────┼────────────────────────────┤
    │ BK-DATA-ADMIN         │ FSI_ADMIN            │ 全スキーマ・全拠点 (平文)   │
    │ BK-DATA-ENGINEER      │ FSI_DATA_ENGINEER    │ 全スキーマ・全拠点 (平文)   │
    │ BK-DEVELOPER          │ FSI_DEVELOPER        │ 開発系スキーマのみ          │
    │ BK-ANALYST-TOKYO      │ FSI_ANALYST          │ harmonized/analytics       │
    │                       │                      │ (PII マスク + Tokyo のみ)  │
    │ BK-ANALYST-NEWYORK    │ FSI_ANALYST_NY       │ harmonized/analytics       │
    │                       │                      │ (PII マスク + NewYork のみ) │
    │ BK-EXTERNAL-VENDOR    │ FSI_READONLY         │ analytics のみ (全マスク)   │
    └───────────────────────┴──────────────────────┴────────────────────────────┘

    これにより「AD グループへの追加 = Snowflake での権限自動付与」が実現し、
    入退社・異動時の権限管理が自動化されます。
----------------------------------------------------------------------------------*/

-- クリーンアップ (必要に応じて実行。他のセクションに影響する場合はスキップ)
-- 行アクセスポリシーの解除
-- USE ROLE fsi_admin;
-- ALTER TABLE fsi_zts_101.raw_trade.trade_transactions
--     DROP ROW ACCESS POLICY fsi_zts_101.governance.branch_row_access;

-- タグベースマスキングの解除
-- ALTER TAG fsi_zts_101.governance.pii_tag
--     UNSET MASKING POLICY fsi_zts_101.governance.pii_mask;
-- ALTER TAG fsi_zts_101.governance.financial_amount_tag
--     UNSET MASKING POLICY fsi_zts_101.governance.amount_threshold_mask;

-- アナリストの一時権限を取り消し
-- USE ROLE securityadmin;
-- REVOKE SELECT ON TABLE fsi_zts_101.raw_customer.customers       FROM ROLE fsi_analyst;
-- REVOKE SELECT ON TABLE fsi_zts_101.raw_trade.trade_transactions FROM ROLE fsi_analyst;
-- REVOKE SELECT ON TABLE fsi_zts_101.raw_excel.corporate_sales    FROM ROLE fsi_analyst;

-- セクション 4 完了
SELECT '✓ セクション 4: ガバナンス が完了しました。' AS status,
       'タグ → タグベースマスキング → 行アクセスポリシー → 監査 → 分類 を体験しました。' AS summary;
