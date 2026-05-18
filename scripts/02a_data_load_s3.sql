/***************************************************************************************************
Asset:        FSI Zero to Snowflake - データロード (S3 / XML)
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

セクション 2(a) - データロード
  1. CSV からの COPY INTO
  2. JSON からの COPY INTO (VARIANT)
  3. XML (SWIFT MX 電文 ISO 20022) からの COPY INTO ★メイン
  4. まとめ

前提条件:
  - setup.sql を実行済み (データベース・スキーマ・テーブル・ステージ・ファイルフォーマット作成済み)
****************************************************************************************************/

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"data_load_s3"}}';

USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;
USE DATABASE fsi_zts_101;

/*----------------------------------------------------------------------------------
 1. CSV からの COPY INTO
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

-- 結果確認: 件数・日付範囲
SELECT
    COUNT(*)            AS row_count,
    MIN(trade_date)     AS min_trade_date,
    MAX(trade_date)     AS max_trade_date,
    COUNT(DISTINCT source_file) AS file_count
FROM fsi_zts_101.raw_trade.trade_transactions_csv_raw;

/*----------------------------------------------------------------------------------
 2. JSON からの COPY INTO (VARIANT)
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
 3. XML (SWIFT MX 電文 ISO 20022) からの COPY INTO  ★メインセクション
    -------------------------------------------------
    ISO 20022 準拠の SWIFT MX 電文 (XML) を VARIANT 型として取り込み、
    XMLGET 関数や : (パス記法) で構造化データとして展開します。

    サンプルファイル:
      - pacs_008_sample_01~05.xml  ... FI to FI Customer Credit Transfer (送金指図)
      - camt_053_sample_01~02.xml  ... Bank to Customer Statement (口座明細)

    XML 名前空間:
      - pacs.008: urn:iso:std:iso:20022:tech:xsd:pacs.008.001.10
      - camt.053: urn:iso:std:iso:20022:tech:xsd:camt.053.001.08
----------------------------------------------------------------------------------*/

-- 3.1 COPY INTO: XML ファイルを S3 外部ステージから VARIANT 列へ取り込み
COPY INTO fsi_zts_101.raw_trade.swift_messages_xml
    (message_id, received_at, message_type, payload, source_file)
FROM (
    SELECT
        SPLIT_PART(METADATA$FILENAME, '/', -1) || '-' || METADATA$FILE_ROW_NUMBER  AS message_id,
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

-- 3.2 取り込み確認: 全件表示
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
 3.3 pacs.008 の構造化展開 (XMLGET / パス記法)
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

    -- XMLGET で IntrBkSttlmAmt を取り出す
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
 3.4 通貨別送金集計
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
 3.5 大口取引の検出 (しきい値: 10 億円相当)
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
 3.6 camt.053 口座明細の展開 (LATERAL FLATTEN)
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
 4. まとめ
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

    次のセクション: 2(b) Excel からのデータロード
----------------------------------------------------------------------------------*/
