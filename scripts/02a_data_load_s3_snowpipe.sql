/***************************************************************************************************
Asset:        FSI Zero to Snowflake - データロード (S3 / Snowpipe / XML)
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

セクション 2(a) - データロード
  1. ステージの確認とファイル一覧
  2. CSV からの COPY INTO
  3. JSON からの COPY INTO (VARIANT)
  4. XML (SWIFT MX 電文 ISO 20022) からの COPY INTO ★メイン
  5. Snowpipe 構文紹介 (参考)
  6. まとめ

前提条件:
  - setup.sql を実行済み (データベース・スキーマ・テーブル・ステージ・ファイルフォーマット作成済み)
  - assets/sample_data/swift_xml/ 配下の XML ファイルを
    Snowsight UI からステージ @fsi_zts_101.raw_trade.xml_stage にアップロード済み
****************************************************************************************************/

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"data_load_s3"}}';

USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;

/*----------------------------------------------------------------------------------
 1. ステージの確認とファイル一覧
    -------------------------------------------------
    setup.sql で作成した 3 つの内部ステージにファイルが存在するかを確認します。
    まだアップロードしていない場合は Snowsight の左メニュー Data > Databases から
    該当ステージを開き、[+ Files] ボタンでアップロードしてください。

    対応するサンプルファイル:
      - CSV:  assets/sample_data/trade_csv/       → @raw_trade.csv_stage
      - JSON: assets/sample_data/customer_json/   → @raw_trade.json_stage
      - XML:  assets/sample_data/swift_xml/       → @raw_trade.xml_stage
----------------------------------------------------------------------------------*/

-- CSV ステージのファイル一覧
LIST @fsi_zts_101.raw_trade.csv_stage;

-- JSON ステージのファイル一覧
LIST @fsi_zts_101.raw_trade.json_stage;

-- XML ステージのファイル一覧 (pacs.008 / camt.053 の SWIFT MX サンプル)
LIST @fsi_zts_101.raw_trade.xml_stage;


/*----------------------------------------------------------------------------------
 2. CSV からの COPY INTO
    -------------------------------------------------
    CSV ファイルを raw_trade.trade_transactions_csv_raw テーブルへロードします。
    ステージ作成時に FILE_FORMAT = fsi_zts_101.public.csv_ff を紐づけ済みのため、
    COPY INTO 側でファイルフォーマットを指定する必要はありません。

    ポイント:
      - METADATA$FILENAME でソースファイル名を取得できる
      - ON_ERROR = 'CONTINUE' でエラー行をスキップして残りを取り込む
      - COPY INTO は冪等 (同一ファイルの再ロードは自動でスキップ)
----------------------------------------------------------------------------------*/

COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw
    (transaction_id, trade_date, settlement_date, customer_id,
     counterparty_country, transaction_type, currency_code, amount,
     booking_branch, instrument_type, free_text_notes, source_file)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
        METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.s3_assets_stage/trade_csv/
)
FILE_FORMAT = fsi_zts_101.public.csv_ff
ON_ERROR = 'CONTINUE';

/*-- バックアップパターン A: 内部ステージ経由 (事前に COPY FILES で S3 → 内部ステージに転送済みの場合)
COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw
    (transaction_id, trade_date, settlement_date, customer_id,
     counterparty_country, transaction_type, currency_code, amount,
     booking_branch, instrument_type, free_text_notes, source_file)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.csv_stage
)
ON_ERROR = 'CONTINUE';
--*/

/*-- バックアップパターン B: Git Integration 経由 (Git リポジトリ → 内部ステージ → COPY INTO)
-- 前提: setup.sql で以下を実行済み
--   COPY FILES INTO @fsi_zts_101.raw_trade.csv_stage
--     FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/trade_csv/;
COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw
    (transaction_id, trade_date, settlement_date, customer_id,
     counterparty_country, transaction_type, currency_code, amount,
     booking_branch, instrument_type, free_text_notes, source_file)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.csv_stage
)
ON_ERROR = 'CONTINUE';
--*/

/*-- 代替パターン (バックアップ):

    -- パターン A: 内部ステージ経由 (事前に COPY FILES で S3 → 内部ステージに転送済みの場合)
    COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw (...)
    FROM (SELECT ... FROM @fsi_zts_101.raw_trade.csv_stage)
    ON_ERROR = 'CONTINUE';

    -- パターン B: Git Repository 経由 (COPY FILES で Git → 内部ステージに転送後)
    -- ※ Git Stage からの直接 COPY INTO は非対応。事前に COPY FILES が必要:
    --   COPY FILES INTO @fsi_zts_101.raw_trade.csv_stage
    --     FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/trade_csv/;
    COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw (...)
    FROM (SELECT ... FROM @fsi_zts_101.raw_trade.csv_stage)
    ON_ERROR = 'CONTINUE';
--*/

-- 結果確認: 件数・日付範囲
SELECT
    COUNT(*)            AS row_count,
    MIN(trade_date)     AS min_trade_date,
    MAX(trade_date)     AS max_trade_date,
    COUNT(DISTINCT source_file) AS file_count
FROM fsi_zts_101.raw_trade.trade_transactions_csv_raw;

/*----------------------------------------------------------------------------------
 3. JSON からの COPY INTO (VARIANT)
    -------------------------------------------------
    JSON ファイルを raw_customer.customers_json_raw テーブルへロードします。
    JSON は VARIANT 型カラムにそのまま格納し、後から : (パス記法) で展開します。

    ポイント:
      - VARIANT 型は最大 16 MB のドキュメントを 1 行として格納可能
      - STRIP_OUTER_ARRAY = TRUE により JSON 配列の [ ] が除去され、
        各オブジェクトが個別の行として取り込まれる
      - スキーマ変更に強い (新しいキーが追加されても取り込み側の変更不要)
----------------------------------------------------------------------------------*/

COPY INTO fsi_zts_101.raw_customer.customers_json_raw
    (raw_payload, source_file)
FROM (
    SELECT
        $1,
        METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.s3_assets_stage/customer_json/
)
FILE_FORMAT = fsi_zts_101.public.json_ff
ON_ERROR = 'CONTINUE';

/*-- バックアップパターン A: 内部ステージ経由
COPY INTO fsi_zts_101.raw_customer.customers_json_raw (raw_payload, source_file)
FROM (SELECT $1, METADATA$FILENAME FROM @fsi_zts_101.raw_trade.json_stage)
ON_ERROR = 'CONTINUE';
--*/

/*-- バックアップパターン B: Git Integration 経由 (内部ステージに事前転送後)
-- COPY FILES INTO @fsi_zts_101.raw_trade.json_stage
--   FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/customer_json/;
COPY INTO fsi_zts_101.raw_customer.customers_json_raw (raw_payload, source_file)
FROM (SELECT $1, METADATA$FILENAME FROM @fsi_zts_101.raw_trade.json_stage)
ON_ERROR = 'CONTINUE';
--*/

-- 結果確認
SELECT COUNT(*) AS row_count FROM fsi_zts_101.raw_customer.customers_json_raw;

-- VARIANT データの展開: : (パス記法) でネストされたフィールドにアクセス
-- :: でキャスト (例: ::STRING, ::NUMBER, ::DATE)
SELECT
    raw_payload:customer_id::NUMBER      AS customer_id,
    raw_payload:customer_name::STRING    AS customer_name,  -- name → customer_name
    raw_payload:contact_email::STRING    AS contact_email,  -- email → contact_email
    raw_payload:country_code::STRING     AS country_code,
    raw_payload:customer_segment::STRING AS customer_segment, -- segment → customer_segment
    raw_payload:risk_rating::STRING      AS risk_rating,
    source_file,
    loaded_at
FROM fsi_zts_101.raw_customer.customers_json_raw
LIMIT 10;


/*----------------------------------------------------------------------------------
 4. XML (SWIFT MX 電文 ISO 20022) からの COPY INTO  ★メインセクション
    -------------------------------------------------
    ISO 20022 準拠の SWIFT MX 電文 (XML) を VARIANT 型として取り込み、
    XMLGET 関数や : (パス記法) で構造化データとして展開します。

    サンプルファイル:
      - pacs_008_sample_01~05.xml  ... FI to FI Customer Credit Transfer (送金指図)
      - camt_053_sample_01~02.xml  ... Bank to Customer Statement (口座明細)

    XML 名前空間:
      - pacs.008: urn:iso:std:iso:20022:tech:xsd:pacs.008.001.10
      - camt.053: urn:iso:std:iso:20022:tech:xsd:camt.053.001.08

    ポイント:
      - FILE_FORMAT の STRIP_OUTER_ELEMENT = TRUE により
        ルート要素 <Document> が除去される
      - VARIANT に格納された XML は XMLGET() / : / @ で要素・属性にアクセス
----------------------------------------------------------------------------------*/

-- 4.1 COPY INTO: XML ファイルを S3 外部ステージから VARIANT 列へ取り込み
COPY INTO fsi_zts_101.raw_trade.swift_messages_xml
    (message_id, received_at, message_type, payload, source_file)
FROM (
    SELECT
        METADATA$FILENAME || '-' || METADATA$FILE_ROW_NUMBER  AS message_id,
        CURRENT_TIMESTAMP()                                    AS received_at,
        -- ファイル名から電文タイプを判定 (pacs_008 / camt_053)
        CASE
            WHEN METADATA$FILENAME ILIKE '%pacs_008%' THEN 'pacs.008'
            WHEN METADATA$FILENAME ILIKE '%camt_053%' THEN 'camt.053'
            ELSE 'unknown'
        END                                                    AS message_type,
        $1                                                     AS payload,
        METADATA$FILENAME                                      AS source_file
    FROM @fsi_zts_101.raw_trade.s3_assets_stage/swift_xml/
)
FILE_FORMAT = (TYPE = 'XML')
ON_ERROR = 'CONTINUE';

/*-- バックアップパターン A: 内部ステージ経由
COPY INTO fsi_zts_101.raw_trade.swift_messages_xml
    (message_id, received_at, message_type, payload, source_file)
FROM (
    SELECT
        METADATA$FILENAME || '-' || METADATA$FILE_ROW_NUMBER,
        CURRENT_TIMESTAMP(),
        CASE WHEN METADATA$FILENAME ILIKE '%pacs_008%' THEN 'pacs.008'
             WHEN METADATA$FILENAME ILIKE '%camt_053%' THEN 'camt.053'
             ELSE 'unknown' END,
        $1, METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.xml_stage
)
FILE_FORMAT = (TYPE = 'XML')
ON_ERROR = 'CONTINUE';
--*/

/*-- バックアップパターン B: Git Integration 経由 (内部ステージに事前転送後)
-- COPY FILES INTO @fsi_zts_101.raw_trade.xml_stage
--   FROM @fsi_zts_101.public.fsi_zts_repo/branches/main/assets/sample_data/swift_xml/;
-- (上記実行後に パターン A と同じ COPY INTO を実行)
--*/

-- 4.2 取り込み確認: 全件表示
SELECT
    message_id,
    message_type,
    received_at,
    source_file
FROM fsi_zts_101.raw_trade.swift_messages_xml
ORDER BY message_type, source_file;

-- 生の VARIANT データを確認 (XML が VARIANT としてどう格納されるかを体感)
SELECT
    message_type,
    payload
FROM fsi_zts_101.raw_trade.swift_messages_xml
LIMIT 1;


/*----------------------------------------------------------------------------------
 4.3 pacs.008 の構造化展開 (XMLGET / パス記法)
     -------------------------------------------------
     pacs.008 (FI to FI Customer Credit Transfer) は以下の構造:

     <Document>                              ← STRIP_OUTER_ELEMENT で除去済み
       <FIToFICstmrCdtTrf>
         <GrpHdr>
           <MsgId>MSG202605140001</MsgId>    ← メッセージ ID
           <CreDtTm>2026-05-03T...</CreDtTm> ← 作成日時
           <NbOfTxs>1</NbOfTxs>              ← 取引件数
         </GrpHdr>
         <CdtTrfTxInf>
           <PmtId>
             <EndToEndId>E2E-154907</EndToEndId>
           </PmtId>
           <IntrBkSttlmAmt Ccy="USD">17973510</IntrBkSttlmAmt>
           <Dbtr><Nm>Alpha Trading Co</Nm></Dbtr>
           <Cdtr><Nm>Zeta Corporation</Nm></Cdtr>
           <RmtInf><Ustrd>Quarterly dividend...</Ustrd></RmtInf>
         </CdtTrfTxInf>
       </FIToFICstmrCdtTrf>

     XMLGET の基本構文:
       XMLGET(variant_column, 'ElementName') → 子要素を VARIANT で返す
       XMLGET(...):"$"::STRING               → テキストノードの値を取得
       XMLGET(...):@AttributeName::STRING    → 属性値を取得 (@ プレフィックス)
----------------------------------------------------------------------------------*/

-- pacs.008: グループヘッダ情報の展開
SELECT
    message_id,
    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'GrpHdr'),
        'MsgId'
    ):"$"::STRING       AS msg_id,

    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'GrpHdr'),
        'CreDtTm'
    ):"$"::TIMESTAMP    AS created_at,

    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'GrpHdr'),
        'NbOfTxs'
    ):"$"::NUMBER       AS num_transactions

FROM fsi_zts_101.raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008';


-- pacs.008: 送金取引明細の展開
SELECT
    message_id,
    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'PmtId'),
        'EndToEndId'
    ):"$"::STRING                  AS end_to_end_id,

    -- 修正: XMLGET で IntrBkSttlmAmt を取り出す
XMLGET(
    XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
    'IntrBkSttlmAmt'
):"$"::NUMBER(18,2)    AS settlement_amount,

XMLGET(
    XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
    'IntrBkSttlmAmt'
):"@Ccy"::STRING       AS currency,

    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'Dbtr'),
        'Nm'
    ):"$"::STRING                  AS debtor_name,

    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'Cdtr'),
        'Nm'
    ):"$"::STRING                  AS creditor_name,

    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'RmtInf'),
        'Ustrd'
    ):"$"::STRING                  AS remittance_info,

    XMLGET(
        XMLGET(XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'InstgAgt'), 'FinInstnId'),
        'BICFI'
    ):"$"::STRING                  AS instructing_agent_bic

FROM fsi_zts_101.raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008';


/*----------------------------------------------------------------------------------
 4.4 通貨別送金集計
     pacs.008 電文から通貨別の送金合計額・件数を集計します。
----------------------------------------------------------------------------------*/

SELECT
    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
        'IntrBkSttlmAmt'
    ):"@Ccy"::STRING                            AS currency,

    COUNT(*)                                     AS msg_count,

    SUM(
        XMLGET(
            XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
            'IntrBkSttlmAmt'
        ):"$"::NUMBER(18,2)
    )                                            AS total_amount,

    AVG(
        XMLGET(
            XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
            'IntrBkSttlmAmt'
        ):"$"::NUMBER(18,2)
    )                                            AS avg_amount

FROM fsi_zts_101.raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008'
GROUP BY currency
ORDER BY total_amount DESC;


/*----------------------------------------------------------------------------------
 4.5 大口取引の検出 (しきい値: 10 億円相当)
     -------------------------------------------------
     AML (Anti-Money Laundering) / コンプライアンスの観点から、
     一定金額を超える送金をフラグ付けするクエリ例です。
     ここでは簡易的に 1,000,000,000 (10 億) を USD 換算なしで比較します。
----------------------------------------------------------------------------------*/

SELECT
    message_id,
    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'GrpHdr'),
        'MsgId'
    ):"$"::STRING                               AS msg_id,

    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
        'IntrBkSttlmAmt'
    ):"@Ccy"::STRING                            AS currency,

    XMLGET(
        XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
        'IntrBkSttlmAmt'
    ):"$"::NUMBER(18,2)                         AS settlement_amount,

    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'Dbtr'),
        'Nm'
    ):"$"::STRING                               AS debtor_name,

    XMLGET(
        XMLGET(XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'), 'Cdtr'),
        'Nm'
    ):"$"::STRING                               AS creditor_name,

    'LARGE_VALUE_ALERT' AS flag

FROM fsi_zts_101.raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008'
  AND XMLGET(
          XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
          'IntrBkSttlmAmt'
      ):"$"::NUMBER(18,2) >= 1000000000
ORDER BY settlement_amount DESC;


/*----------------------------------------------------------------------------------
 4.6 camt.053 口座明細の展開 (LATERAL FLATTEN)
     -------------------------------------------------
     camt.053 (Bank to Customer Statement) は 1 つの <Stmt> 内に
     複数の <Ntry> (明細行) を持ちます。

     <BkToCstmrStmt>
       <Stmt>
         <Acct><Id><IBAN>JP1234567801</IBAN></Id></Acct>
         <Ntry>  ← 明細 1
           <Amt Ccy="EUR">5979642</Amt>
           <CdtDbtInd>DBIT</CdtDbtInd>
           ...
         </Ntry>
         <Ntry>  ← 明細 2  (複数)
           ...
         </Ntry>
       </Stmt>

     1 つの XML ドキュメントに複数の繰り返し要素がある場合は
     LATERAL FLATTEN で行に展開します。

     FLATTEN の対象:
       payload:"Stmt":"Ntry"   → 配列化された Ntry 要素群
----------------------------------------------------------------------------------*/

-- camt.053: 口座情報 + 明細行を LATERAL FLATTEN で展開
WITH stmt AS (
    SELECT
        message_id,
        XMLGET(XMLGET(payload, 'BkToCstmrStmt'), 'Stmt') AS stmt_elem
    FROM fsi_zts_101.raw_trade.swift_messages_xml
    WHERE message_type = 'camt.053'
)
SELECT
    s.message_id,

    XMLGET(XMLGET(XMLGET(s.stmt_elem, 'Acct'), 'Id'), 'IBAN'):"$"::STRING   AS account_iban,

    XMLGET(XMLGET(s.stmt_elem, 'Acct'), 'Ccy'):"$"::STRING                  AS account_currency,

    XMLGET(XMLGET(s.stmt_elem, 'Ntry', e.index), 'Amt'):"$"::NUMBER(18,2)   AS entry_amount,
    XMLGET(XMLGET(s.stmt_elem, 'Ntry', e.index), 'Amt'):"@Ccy"::STRING      AS entry_currency,
    XMLGET(XMLGET(s.stmt_elem, 'Ntry', e.index), 'CdtDbtInd'):"$"::STRING   AS debit_credit_indicator,

    XMLGET(
        XMLGET(XMLGET(s.stmt_elem, 'Ntry', e.index), 'BookgDt'),
        'Dt'
    ):"$"::DATE                                                              AS booking_date,

    XMLGET(
        XMLGET(
            XMLGET(
                XMLGET(XMLGET(s.stmt_elem, 'Ntry', e.index), 'NtryDtls'),
                'TxDtls'
            ),
            'RmtInf'
        ),
        'Ustrd'
    ):"$"::STRING                                                            AS remittance_info

FROM stmt s,
     LATERAL FLATTEN(input => s.stmt_elem:"Ntry") e
ORDER BY s.message_id, booking_date;


-- camt.053: 口座ごとの入出金集計
WITH stmt AS (
    SELECT
        message_id,
        XMLGET(XMLGET(payload, 'BkToCstmrStmt'), 'Stmt') AS stmt_elem
    FROM fsi_zts_101.raw_trade.swift_messages_xml
    WHERE message_type = 'camt.053'
)
SELECT
    XMLGET(XMLGET(XMLGET(s.stmt_elem, 'Acct'), 'Id'), 'IBAN'):"$"::STRING  AS account_iban,

    XMLGET(
        XMLGET(s.stmt_elem, 'Ntry', e.index),
        'CdtDbtInd'
    ):"$"::STRING                                                            AS debit_credit,

    COUNT(*)                                                                 AS entry_count,
    SUM(
        XMLGET(
            XMLGET(s.stmt_elem, 'Ntry', e.index),
            'Amt'
        ):"$"::NUMBER(18,2)
    )                                                                        AS total_amount

FROM stmt s,
     LATERAL FLATTEN(input => s.stmt_elem:"Ntry") e
GROUP BY account_iban, debit_credit
ORDER BY account_iban, debit_credit;


/*----------------------------------------------------------------------------------
 5. Snowpipe 構文紹介 (参考)
    -------------------------------------------------
    Snowpipe は外部ステージ (S3 / GCS / Azure Blob) のイベント通知と連携し、
    新しいファイルが到着するたびに自動で COPY INTO を実行する仕組みです。

    構成要素:
      1. 外部ステージ (S3 バケット + Storage Integration)
      2. PIPE オブジェクト (COPY INTO 文を内包 + AUTO_INGEST = TRUE)
      3. S3 Event Notification → SQS → Snowpipe (自動トリガー)

    ★ 以下は構文のみ確認してください (実行しません)。
      ハンズオン参加者ごとに個別の S3 イベント通知設定が必要なため、
      今回は PIPE の定義構文と運用コマンドの紹介にとどめます。

    金融ユースケース:
      - S3 に到着する新規取引ファイルを数秒〜数分以内に自動取り込み
      - 既存の Glue ETL → Snowpipe に置き換えて運用コスト削減
      - ファイル到着からテーブル反映までのラグを最小化

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/data-load-snowpipe-intro
----------------------------------------------------------------------------------*/

-- 参考: Snowpipe の定義例 (実行しません — 構文確認用)
/*
CREATE OR REPLACE PIPE fsi_zts_101.raw_trade.trade_csv_pipe
    AUTO_INGEST = TRUE
    COMMENT = 'S3 から CSV バッチファイルを自動取り込みする Snowpipe'
AS
COPY INTO fsi_zts_101.raw_trade.trade_transactions_csv_raw
    (transaction_id, trade_date, settlement_date, customer_id,
     counterparty_country, transaction_type, currency_code, amount,
     booking_branch, instrument_type, free_text_notes, source_file)
FROM (
    SELECT
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
        METADATA$FILENAME
    FROM @fsi_zts_101.raw_trade.s3_assets_stage/snowpipe_csv/
)
FILE_FORMAT = fsi_zts_101.public.csv_ff;
*/

/*--
    Snowpipe 運用コマンド (参考):

    -- Snowpipe のステータス確認
    SELECT SYSTEM$PIPE_STATUS('fsi_zts_101.raw_trade.trade_csv_pipe');

    -- 手動 REFRESH (S3 イベント通知なしでファイルを検出・取り込み)
    ALTER PIPE fsi_zts_101.raw_trade.trade_csv_pipe REFRESH;

    -- Snowpipe の通知チャネル ARN 確認 (S3 Event Notification に設定する値)
    SHOW PIPES LIKE 'trade_csv_pipe' IN SCHEMA fsi_zts_101.raw_trade;

    -- 取り込み履歴の確認
    SELECT * FROM TABLE(information_schema.copy_history(
        TABLE_NAME => 'fsi_zts_101.raw_trade.trade_transactions_csv_raw',
        START_TIME => DATEADD(hour, -1, CURRENT_TIMESTAMP())
    )) ORDER BY LAST_LOAD_TIME DESC;

    -- Snowpipe の停止
    ALTER PIPE fsi_zts_101.raw_trade.trade_csv_pipe SET PIPE_EXECUTION_PAUSED = TRUE;
--*/

/*--
    ★ 本番環境での Snowpipe セットアップ手順 (参考):

    1. Storage Integration を作成 (IAM Role ベース)
       CREATE STORAGE INTEGRATION s3_integration
         TYPE = EXTERNAL_STAGE
         STORAGE_PROVIDER = 'S3'
         ENABLED = TRUE
         STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-role'
         STORAGE_ALLOWED_LOCATIONS = ('s3://your-bucket/path/');

    2. 外部ステージを Storage Integration 付きで作成
       CREATE STAGE your_stage
         URL = 's3://your-bucket/path/'
         STORAGE_INTEGRATION = s3_integration;

    3. Snowpipe を作成 (AUTO_INGEST = TRUE)

    4. SHOW PIPES で notification_channel (SQS ARN) を取得

    5. AWS Console → S3 → Event notifications で以下を設定:
       - Event type: s3:ObjectCreated:*
       - Prefix: your/path/
       - Destination: SQS queue (上記 ARN)

    6. 設定完了後、S3 にファイルを配置すれば自動で Snowpipe がトリガー

    参考: https://docs.snowflake.com/ja/user-guide/data-load-snowpipe-auto-s3
--*/


/*----------------------------------------------------------------------------------
 6. まとめ
    -------------------------------------------------
    このセクションで学んだこと:

    [データロードの基本]
      - LIST コマンドでステージ上のファイルを確認する方法
      - COPY INTO による CSV / JSON / XML ファイルの一括取り込み
      - METADATA$FILENAME / METADATA$FILE_ROW_NUMBER の活用
      - ON_ERROR オプションによるエラーハンドリング
      - COPY INTO の冪等性 (同一ファイルの再ロード防止)

    [半構造化データ (Semi-Structured Data)]
      - VARIANT 型: JSON / XML をそのまま格納するスキーマレスな型
      - JSON の展開:  : (パス記法) と :: (キャスト) を組み合わせた列抽出
      - XML の展開:   XMLGET() でネストされた要素へのアクセス
                      :"$" でテキストノード、:"@attr" で属性値を取得
      - LATERAL FLATTEN: 1 行に複数子要素がある場合の行展開

    [金融業界ユースケース]
      - ISO 20022 SWIFT MX 電文 (pacs.008 / camt.053) の解析
      - 大口取引の検出 (AML / コンプライアンス)
      - 通貨別集計・入出金分析

    [Snowpipe (参考)]
      - AUTO_INGEST = TRUE による S3 イベント駆動の自動取り込み
      - PIPE オブジェクトの構文と運用コマンド

    次のセクション: 2(b) Excel からのデータロード
----------------------------------------------------------------------------------*/
