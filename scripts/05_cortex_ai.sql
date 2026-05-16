/***************************************************************************************************
Asset:        FSI Zero to Snowflake - Cortex AI
Script:       05_cortex_ai.sql
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.

このスクリプトでは、Snowflake Cortex AI の主要機能を金融取引データに適用し、
LLM を活用した分類・感情分析・テキスト生成・全文検索の実践例を学びます。

金融業界のユースケース:
  - 取引コメントの自動分類 (コンプライアンス仕分け)
  - フリーテキストのセンチメント分析 (異常検知の補助)
  - LLM によるコンプライアンスリスク判定
  - Cortex Search による取引メモの全文セマンティック検索
  - Cortex Analyst による自然言語 BI (紹介)

  1. Cortex AI 関数の概要
  2. AI_CLASSIFY — 取引コメントの自動分類
  3. AI_SENTIMENT — センチメント分析
  4. AI_COMPLETE — LLM による自由文生成 (コンプライアンスリスク判定)
  5. Cortex Search (全文セマンティック検索サービス)
  6. Cortex Analyst 紹介 (セマンティックモデル)
  7. Dataiku x Snowflake Pushdown 紹介 (説明のみ)
  8. まとめ

所要時間: 約 30 分
前提: setup.sql が実行済みで、fsi_zts_101 データベースと raw_trade.trade_transactions に
      50,000 件の合成データが投入済みであること
****************************************************************************************************/

-- =====================================================================
-- ロール / ウェアハウス / データベースのセット
-- =====================================================================
USE ROLE fsi_developer;
USE WAREHOUSE fsi_cortex_wh;
USE DATABASE fsi_zts_101;

-- セッションにクエリタグを設定する (利用状況トラッキング用)
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"cortex_ai"}}';


/*----------------------------------------------------------------------------------
 1. Cortex AI 関数の概要
    -------------------------------------------------
    Snowflake Cortex AI は、SQL から直接 LLM を呼び出せるフルマネージドサービスです。
    データを外部に出すことなく、Snowflake 内で AI 推論を実行できます。

    主要な関数:
    ┌──────────────────────────────┬──────────────────────────────────────────────┐
    │ 関数                         │ 用途                                         │
    ├──────────────────────────────┼──────────────────────────────────────────────┤
    │ AI_CLASSIFY                  │ テキスト/画像/ドキュメントをカテゴリに分類   │
    │                              │ (CLASSIFY_TEXT の後継、マルチラベル対応)     │
    │ AI_SENTIMENT                 │ テキストの感情スコア (-1.0 〜 1.0)           │
    │ AI_COMPLETE                   │ LLM によるテキスト生成 (プロンプト応答)      │
    │ SNOWFLAKE.CORTEX.SUMMARIZE   │ テキスト要約                                 │
    │ SNOWFLAKE.CORTEX.TRANSLATE   │ 翻訳 (多言語対応)                            │
    │ AI_EMBED / EMBED_TEXT_1024   │ テキストのベクトル埋め込み生成               │
    │ Cortex Search Service        │ セマンティック全文検索 (RAG の基盤)           │
    │ Cortex Analyst               │ 自然言語 BI (セマンティックモデル経由)       │
    └──────────────────────────────┴──────────────────────────────────────────────┘

    クロスリージョン設定:
      setup.sql で ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_JP' を
      設定済み。推論リクエストは AWS 東京 (ap-northeast-1) と AWS 大阪 (ap-northeast-3) に
      限定され、金融機関が求めるデータ残留性 (data residency) 要件を満たします。
      推論ペイロードはトランジェントに転送のみで、処理リージョンに永続化されません。

    権限:
      Cortex 関数を使うには SNOWFLAKE.CORTEX_USER データベースロールが必要です。
      setup.sql で fsi_developer ロールに付与済みです。
----------------------------------------------------------------------------------*/

-- 現在のクロスリージョン設定を確認
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;


/*----------------------------------------------------------------------------------
 2. AI_CLASSIFY — 取引コメントの自動分類
    -------------------------------------------------
    trade_transactions テーブルの free_text_notes カラムには 30 種類のテキストが
    含まれています (setup.sql で合成データとして生成、英語 20 + 日本語 10)。

    これらを AI_CLASSIFY で自動分類します。
    AI_CLASSIFY は CLASSIFY_TEXT の後継で、以下の拡張に対応しています:
      - マルチラベル分類 (output_mode: 'multi')
      - 画像/ドキュメント分類 (TO_FILE 経由)
      - label descriptions による精度向上
      - few-shot examples による精度向上
    
    戻り値: {"labels": ["category1"]} (配列形式)
    単一ラベルの場合は :labels[0] で先頭要素を取得します。

    金融ユースケース:
      - コンプライアンス部門への自動エスカレーション判定
      - 取引メモの定型/非定型分類
      - AML (アンチマネーロンダリング) スクリーニング補助
----------------------------------------------------------------------------------*/

-- 2-1. まずデータを確認 (free_text_notes の種類と分布)
SELECT
    free_text_notes,
    COUNT(*) AS cnt
FROM raw_trade.trade_transactions
GROUP BY free_text_notes
ORDER BY cnt DESC;

-- 2-2. AI_CLASSIFY で 5 カテゴリに分類
--      結果は JSON オブジェクト { "labels": ["..."] } で返るため :labels[0] で抽出
--      AI_CLASSIFY は CLASSIFY_TEXT の後継で、マルチラベル分類や画像/ドキュメント分類にも対応
SELECT
    transaction_id,
    free_text_notes,
    AI_CLASSIFY(
        free_text_notes,
        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority']
    ):labels[0]::VARCHAR AS classification
FROM raw_trade.trade_transactions
LIMIT 20;

-- 2-3. 分類結果の分布を集計
--      1,000,000 件全件は時間がかかるため、SAMPLE で 1,000 件に絞って実行
SELECT
    AI_CLASSIFY(
        free_text_notes,
        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority']
    ):labels[0]::VARCHAR AS classification,
    COUNT(*)            AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM raw_trade.trade_transactions
    SAMPLE (1000 ROWS)
GROUP BY classification
ORDER BY cnt DESC;

-- 2-4. (発展) task_description + label descriptions で精度を上げる
--      金融コンテキストを伝えることで、LLM の分類精度が向上します
SELECT
    transaction_id,
    free_text_notes,
    AI_CLASSIFY(
        free_text_notes,
        [
            {'label': 'Standard',                'description': 'Routine transactions with no issues or special handling'},
            {'label': 'Urgent/Expedited',        'description': 'Time-sensitive transactions requiring priority processing'},
            {'label': 'Suspicious/Compliance',   'description': 'Transactions flagged for AML, sanctions, or compliance review'},
            {'label': 'Dispute',                 'description': 'Transactions with customer complaints or amount disagreements'},
            {'label': 'VIP/Priority',            'description': 'High-value client transactions requiring premium service'}
        ],
        {
            'task_description': 'Classify trade transaction notes in a banking context. Focus on compliance risk and operational priority.'
        }
    ):labels[0]::VARCHAR AS classification
FROM raw_trade.trade_transactions
LIMIT 10;


/*----------------------------------------------------------------------------------
 3. AI_SENTIMENT — センチメント分析
    -------------------------------------------------
    AI_SENTIMENT は、テキストの感情を分析し、以下の形式で結果を返します:

    {"categories": [{"name": "overall", "sentiment": "negative"}]}

    sentiment の値: "positive" / "negative" / "neutral" / "mixed"

    期待される結果:
      - "Suspicious pattern detected..." → negative
      - "Standard transaction. No issues reported." → neutral
      - "High-priority client. Premium handling." → positive
      - "Customer disputed amount..." → negative

    金融ユースケース:
      - 取引コメントの異常検知 (negative の急増をアラート)
      - 顧客コミュニケーションのトーン分析
      - コンプライアンスレビュー優先度の自動付与
----------------------------------------------------------------------------------*/

-- 3-1. 各取引コメントのセンチメントを取得
SELECT
    transaction_id,
    free_text_notes,
    AI_SENTIMENT(free_text_notes) AS sentiment_raw,
    AI_SENTIMENT(free_text_notes):categories[0]:sentiment::VARCHAR AS sentiment
FROM raw_trade.trade_transactions
LIMIT 20;

-- 3-2. コメント種別ごとのセンチメント分布
SELECT
    free_text_notes,
    COUNT(*) AS cnt,
    AI_SENTIMENT(free_text_notes):categories[0]:sentiment::VARCHAR AS sentiment
FROM raw_trade.trade_transactions
GROUP BY free_text_notes, sentiment
ORDER BY sentiment, cnt DESC;

-- 3-3. negative センチメントの取引を抽出 (コンプライアンス要注意)
--      実務ではこの結果を Dynamic Table やアラートに接続し、自動エスカレーションを構築できます
SELECT * FROM (
    SELECT
        transaction_id,
        trade_date,
        booking_branch,
        amount,
        free_text_notes,
        AI_SENTIMENT(free_text_notes):categories[0]:sentiment::VARCHAR AS sentiment
    FROM raw_trade.trade_transactions
    LIMIT 100
)
WHERE sentiment = 'negative';


/*----------------------------------------------------------------------------------
 4. AI_COMPLETE — LLM による自由文生成 (コンプライアンスリスク判定)
    -------------------------------------------------
    AI_COMPLETE は、指定した LLM モデルにプロンプトを送信し、
    テキスト応答を取得します。SNOWFLAKE.CORTEX.COMPLETE の後継です。

    AI_COMPLETEで    利用可能なモデル例 (AWS_JP クロスリージョン):
      - 'claude-sonnet-4-6'  : Anthropic 最新 Sonnet (高品質・高速バランス)
      - 'claude-sonnet-4-5'  : Anthropic Sonnet 4.5 (推論力重視)
      - 'claude-haiku-4-5'   : Anthropic Haiku (高速・低コスト)
    参考: https://docs.snowflake.com/en/sql-reference/parameters#cortex_enabled_cross_region

    注意: モデルの利用可能性はリージョンとクロスリージョン設定に依存します。
          エラーが出た場合は別のモデル名に変更してください。

    金融ユースケース:
      - 取引コメントからコンプライアンスリスクを自動判定
      - 規制報告書の下書き生成
      - 顧客向けレターの自動生成
----------------------------------------------------------------------------------*/

-- 4-1. 基本的な AI_COMPLETE: シンプルなプロンプト
SELECT AI_COMPLETE(
    'claude-sonnet-4-6',
    'Snowflake Cortex AI を金融業界で活用する主なユースケースを 3 つ、日本語で簡潔に挙げてください。'
) AS ai_response;

-- 4-2. 取引コメントからコンプライアンスリスクを判定
--      LLM にコンテキストと判定基準を与え、構造化された回答を得る
SELECT
    transaction_id,
    free_text_notes,
    AI_COMPLETE(
        'claude-sonnet-4-6',
        'あなたは金融機関のコンプライアンス審査官です。' ||
        '以下の取引コメントを分析し、リスクレベルを HIGH / MEDIUM / LOW の 3 段階で判定してください。' ||
        '判定理由も 1 文で簡潔に述べてください。回答は日本語でお願いします。' ||
        CHR(10) || CHR(10) ||
        '取引コメント: ' || free_text_notes
    ) AS compliance_assessment
FROM raw_trade.trade_transactions
LIMIT 5;

-- 4-3. (発展) SWIFT 電文の送金目的 (RmtInf/Ustrd) を解析
--      セクション 2(a) で XML をロード済みの場合のみ実行可能
--      payload カラムから送金目的テキストを抽出し、LLM で分析
SELECT
    message_id,
    XMLGET(
        XMLGET(
            XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
            'RmtInf'
        ),
        'Ustrd'
    ):"$"::VARCHAR AS remittance_info,
    AI_COMPLETE(
        'claude-sonnet-4-6',
        'Analyze the following SWIFT remittance information and determine if it contains any AML red flags. ' ||
        'Respond with: RISK_LEVEL (HIGH/MEDIUM/LOW) and a brief explanation in Japanese.' ||
        CHR(10) || 'Remittance Info: ' ||
        XMLGET(
            XMLGET(
                XMLGET(XMLGET(payload, 'FIToFICstmrCdtTrf'), 'CdtTrfTxInf'),
                'RmtInf'
            ),
            'Ustrd'
        ):"$"::VARCHAR
    ) AS aml_analysis
FROM fsi_zts_101.raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008'
LIMIT 5;


/*----------------------------------------------------------------------------------
 5. Cortex Search (全文セマンティック検索サービス)
    -------------------------------------------------
    Cortex Search は、Snowflake 内にフルマネージドなセマンティック検索サービスを
    構築する機能です。従来のキーワード検索 (LIKE / CONTAINS) と異なり、
    テキストの「意味」を理解したベクトル検索を SQL から直接利用できます。

    アーキテクチャ:
      ソーステーブル → 自動ベクトル埋め込み → インデックス構築
                                              ↓
                               検索クエリ → セマンティックマッチング → 結果

    金融ユースケース:
      - 取引メモの全文検索 (コンプライアンス調査)
      - 社内規程・マニュアルの RAG (Retrieval-Augmented Generation) 基盤
      - 顧客問い合わせの類似事例検索
----------------------------------------------------------------------------------*/

-- 5-1. Cortex Search Service の作成
--      free_text_notes をセマンティック検索対象とし、取引属性を ATTRIBUTES に指定
--      TARGET_LAG = '1 hour' でソーステーブル変更後 1 時間以内にインデックスを更新
--      ※ ハンズオン高速化のため直近 3 ヶ月 (~163K 行) に絞る (全件: ~2M 行, 約 30 分)
CREATE OR REPLACE CORTEX SEARCH SERVICE harmonized.trade_notes_search
    ON free_text_notes
    ATTRIBUTES transaction_type, booking_branch
    WAREHOUSE = fsi_cortex_wh
    TARGET_LAG = '1 hour'
AS (
    SELECT
        transaction_id,
        free_text_notes,
        transaction_type,
        booking_branch,
        currency_code,
        amount
    FROM raw_trade.trade_transactions
    WHERE trade_date >= DATEADD(month, -3, CURRENT_DATE())
);

-- 5-2. サービスが作成されたことを確認
SHOW CORTEX SEARCH SERVICES IN SCHEMA harmonized;

-- 5-3. SEARCH_PREVIEW でセマンティック検索を実行
--      "suspicious compliance" で検索すると、意味的に関連する取引コメントがヒット
--      キーワード完全一致ではなく、意味的類似度に基づいてランキングされます
SELECT
    results.value:transaction_id::VARCHAR   AS transaction_id,
    results.value:free_text_notes::VARCHAR  AS free_text_notes,
    results.value:transaction_type::VARCHAR AS transaction_type,
    results.value:booking_branch::VARCHAR   AS booking_branch,
    TRY_TO_DECIMAL(results.value:amount::VARCHAR, 18, 2) AS amount
FROM TABLE(
    FLATTEN(
        PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'harmonized.trade_notes_search',
                '{
                    "query": "suspicious compliance review",
                    "columns": ["transaction_id", "free_text_notes", "transaction_type", "booking_branch", "amount"],
                    "limit": 10
                }'
            )
        ):results
    )
) AS results;

-- 5-4. 別の検索: 決済の急ぎ対応 (expedited settlement)
SELECT
    results.value:transaction_id::VARCHAR   AS transaction_id,
    results.value:free_text_notes::VARCHAR  AS free_text_notes,
    results.value:booking_branch::VARCHAR   AS booking_branch,
    TRY_TO_DECIMAL(results.value:amount::VARCHAR, 18, 2) AS amount
FROM TABLE(
    FLATTEN(
        PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'harmonized.trade_notes_search',
                '{
                    "query": "urgent expedited settlement year-end",
                    "columns": ["transaction_id", "free_text_notes", "booking_branch", "amount"],
                    "limit": 10
                }'
            )
        ):results
    )
) AS results;

/*--
    補足: Snowsight での Cortex Search 利用
    ------------------------------------------
    Snowsight の [AI & ML Studio] > [Cortex Search] から、
    UI 上でサービスの作成・テスト検索・フィルタ設定が可能です。
    コードを書かずにセマンティック検索を試したい場合に便利です。

    また、Cortex Search は Cortex Analyst や Streamlit アプリから
    RAG (Retrieval-Augmented Generation) の検索バックエンドとして
    利用することで、社内ナレッジに基づいた回答生成が可能になります。
--*/


/*----------------------------------------------------------------------------------
 6. Cortex Analyst 紹介 (セマンティックモデル)
    -------------------------------------------------
    Cortex Analyst は、自然言語の質問を SQL に変換して実行する
    「自然言語 BI」機能です。事前にセマンティックモデル (YAML) を定義し、
    テーブル/カラムのビジネス意味を記述しておくことで、
    ユーザーは SQL を知らなくてもデータに質問できます。

    アーキテクチャ:
      セマンティックモデル (YAML)
        ├── テーブル定義 (name, base_table, description)
        ├── カラム定義 (name, data_type, description, synonyms)
        ├── メジャー (集計関数: SUM, COUNT, AVG ...)
        └── フィルター (time_dimension, default_filter ...)
                 ↓
      ユーザーの自然言語質問 → Cortex Analyst → SQL 生成 → 実行 → 結果

    対象データ (setup.sql で作成済み):
      - semantic_layer.trade_orders_v     : 貿易取引ビュー (PII 除外)
      - semantic_layer.corporate_sales_v  : 法人営業ビュー (顧客名除外)

    セマンティックモデルの定義ファイル:
      - scripts/FSI_TRADE_ANALYTICS.yaml (別途作成)
      - Snowsight の [AI & ML Studio] > [Cortex Analyst] から YAML をアップロード

    質問の例:
      「今月の東京拠点の取引件数は?」
      「通貨別の取引額トップ 5 は?」
      「受注率が最も高い業種は?」

    ※ Cortex Analyst のセットアップは別セッションで実施します。
       ここでは対象ビューの内容を確認しておきます。
----------------------------------------------------------------------------------*/

-- 6-1. 貿易取引のセマンティックレイヤービューを確認
SELECT * FROM semantic_layer.trade_orders_v LIMIT 10;

-- 6-2. 法人営業のセマンティックレイヤービューを確認
SELECT * FROM semantic_layer.corporate_sales_v LIMIT 10;

-- 6-3. Cortex Analyst が参照するカラムの統計情報
--      セマンティックモデル定義時に参考にする
SELECT
    'trade_orders_v'      AS view_name,
    COUNT(*)              AS row_count,
    COUNT(DISTINCT transaction_type) AS distinct_tx_types,
    COUNT(DISTINCT booking_branch)   AS distinct_branches,
    COUNT(DISTINCT currency_code)    AS distinct_currencies,
    MIN(trade_date)       AS min_date,
    MAX(trade_date)       AS max_date
FROM semantic_layer.trade_orders_v
UNION ALL
SELECT
    'corporate_sales_v',
    COUNT(*),
    COUNT(DISTINCT stage),
    COUNT(DISTINCT region),
    COUNT(DISTINCT industry),
    MIN(last_visit_date),
    MAX(expected_close_date)
FROM semantic_layer.corporate_sales_v;


/*----------------------------------------------------------------------------------
 7. Dataiku x Snowflake Pushdown 紹介 (説明のみ / デモなし)
    -------------------------------------------------
    Dataiku は、ノーコード/ローコードの ML プラットフォームです。
    Snowflake と組み合わせる場合、「In-Database (Pushdown)」モードにより
    データ移動なしで Snowflake 上で直接計算を実行できます。

    ■ アーキテクチャ概要

    ┌──────────────────────┐         ┌──────────────────────────────┐
    │  Dataiku DSS         │         │  Snowflake                   │
    │  (オーケストレーション│  SQL    │                              │
    │   レシピ定義         │ ------> │  fsi_cortex_wh (計算実行)    │
    │   ビジュアルML)      │ Pushdown│  harmonized.* (データ参照)   │
    │                      │         │  analytics.* (結果書き込み)  │
    └──────────────────────┘         └──────────────────────────────┘

    ■ セキュリティ設計のポイント

    1. 専用サービスロール (fsi_dataiku_svc):
       - USAGE + SELECT のみ (書き込み権限なし)
       - harmonized / analytics スキーマに限定
       - 本番データ (raw_trade / raw_customer) への直接アクセスなし

    2. ネットワーク制御:
       - PrivateLink 経由でのみ接続 (パブリックインターネット不可)
       - ネットワークポリシーで Dataiku の IP レンジに限定

    3. 監査:
       - query_tag でクエリの出自を追跡可能
       - ACCESS_HISTORY で「誰が何のデータにアクセスしたか」を記録

    ■ setup.sql で設定済みの権限:
----------------------------------------------------------------------------------*/

-- 7-1. Dataiku サービスロールの権限を確認
--      USAGE と SELECT のみが付与されていることを確認
SHOW GRANTS TO ROLE fsi_dataiku_svc;

-- 7-2. ロール階層を確認 (fsi_dataiku_svc → fsi_admin → sysadmin)
SHOW GRANTS OF ROLE fsi_dataiku_svc;

/*--
    ■ Dataiku 側の設定 (参考: 実際の接続設定は別途実施)

    Dataiku DSS > Administration > Connections で以下を設定:
      - Type: Snowflake
      - Account: <your_account>.snowflakecomputing.com
      - Authentication: OAuth 2.0 (推奨) or Key Pair
      - Warehouse: fsi_cortex_wh
      - Role: fsi_dataiku_svc
      - Database: fsi_zts_101
      - Schema: harmonized (デフォルト)

    Dataiku レシピで「In-Database (SQL)」エンジンを選択すると、
    レシピの処理が Snowflake 側にプッシュダウンされ、
    データが Dataiku サーバーに転送されません。

    これにより:
      - 大規模データでも高速処理 (Snowflake の分散コンピュートを活用)
      - データガバナンス維持 (データが Snowflake の外に出ない)
      - コスト最適化 (WH の AUTO_SUSPEND / AUTO_RESUME で使った分だけ課金)
--*/


/*----------------------------------------------------------------------------------
 8. まとめ
    -------------------------------------------------
    このセクションで学んだこと:

    [Cortex AI 関数]
      - AI_CLASSIFY: テキストをカテゴリに自動分類 (マルチラベル/画像/ドキュメントにも対応)
        → 取引コメントの仕分け、コンプライアンス自動エスカレーション
      - AI_SENTIMENT: テキストの感情スコアを取得
        → ネガティブスコアの急増検知、異常取引の早期発見
      - AI_COMPLETE: LLM にプロンプトを送信してテキスト生成
        → コンプライアンスリスク判定、レポート下書き生成

    [Cortex Search]
      - CREATE CORTEX SEARCH SERVICE でセマンティック検索サービスを構築
      - キーワード完全一致ではなく「意味」で検索
      - TARGET_LAG で鮮度を制御 (ニアリアルタイム〜日次)
      - RAG (Retrieval-Augmented Generation) の検索バックエンドとして活用可能

    [Cortex Analyst]
      - セマンティックモデル (YAML) を定義 → 自然言語で BI
      - SQL を知らないビジネスユーザーでもデータに質問可能
      - セマンティックレイヤーのビュー (PII 除外) を参照

    [Dataiku 連携]
      - Pushdown モードでデータ移動なしの ML パイプライン
      - 最小権限のサービスロール設計
      - PrivateLink + ネットワークポリシーによるセキュリティ

    ┌──────────────────────────────────────────────────────────────┐
    │  将来の AI 活用ロードマップ (参考)                           │
    ├──────────────────────────────────────────────────────────────┤
    │  1. LLM as a Judge:                                         │
    │     COMPLETE を使って PII (個人情報) をテキストから検出し、   │
    │     マスキングポリシーと連携して自動匿名化                   │
    │                                                              │
    │  2. Cortex Search + RAG:                                     │
    │     社内コンプライアンス規程を Cortex Search に格納し、       │
    │     取引コメントに対して「関連する社内規程」を検索 →          │
    │     COMPLETE で規程に基づいたリスク判定を生成                 │
    │                                                              │
    │  3. Cortex Analyst + Dynamic Tables:                         │
    │     リアルタイム更新されるデータに自然言語で質問              │
    │     経営ダッシュボードの代替として活用                        │
    │                                                              │
    │  4. Cortex Fine-tuning:                                      │
    │     自社の過去の判定結果を教師データとして、                   │
    │     ドメイン特化モデルをファインチューニング                   │
    └──────────────────────────────────────────────────────────────┘

    次のステップ:
      - Cortex Analyst のセマンティックモデル (YAML) を作成
      - Streamlit in Snowflake で検索 UI を構築
      - Dynamic Table + Cortex で異常検知パイプラインを自動化
----------------------------------------------------------------------------------*/


-- =====================================================================
-- [Option] Semantic View + Cortex Agent + Snowflake Intelligence
-- =====================================================================

/*----------------------------------------------------------------------------------
 9. [Option] Semantic View の作成 (Cortex Analyst 用)
    -------------------------------------------------
    Semantic View は SQL DDL でテーブルの「ビジネス上の意味」を定義するオブジェクトです。
    YAML ファイル (FSI_TRADE_ANALYTICS.yaml) の代替として SQL で直接作成できます。

    Cortex Analyst はこの Semantic View を参照して、
    自然言語の質問 → SQL 変換 → 実行 → 回答 を行います。

    公式ドキュメント:
      https://docs.snowflake.com/ja/user-guide/snowflake-cortex/cortex-analyst/semantic-view
----------------------------------------------------------------------------------*/

USE ROLE fsi_data_engineer;
USE DATABASE fsi_zts_101;
USE WAREHOUSE fsi_cortex_wh;

-- Semantic View: 貿易取引分析
CREATE OR REPLACE SEMANTIC VIEW fsi_zts_101.semantic_layer.fsi_trade_analytics

    TABLES (
        TRADE_ORDERS AS fsi_zts_101.semantic_layer.trade_orders_v
            WITH SYNONYMS = ('取引', '貿易', 'trade', 'transactions', '送金')
            COMMENT = '貿易取引データ。拠点別・通貨別・顧客セグメント別の取引分析の起点。1行=1取引。',
        CORPORATE_SALES AS fsi_zts_101.semantic_layer.corporate_sales_v
            WITH SYNONYMS = ('営業', '案件', 'sales', 'deals', 'パイプライン')
            COMMENT = '法人営業パイプラインデータ。営業担当別・業種別・地域別の受注分析用。1行=1案件。'
    )

    FACTS (
        TRADE_ORDERS.AMOUNT AS AMOUNT
            COMMENT = '取引金額 (各通貨建て)',
        CORPORATE_SALES.OPPORTUNITY_AMOUNT AS OPPORTUNITY_AMOUNT
            COMMENT = '案件見込み額 (円)'
    )

    DIMENSIONS (
        TRADE_ORDERS.TRANSACTION_ID AS TRANSACTION_ID
            COMMENT = '取引ID (一意)',
        TRADE_ORDERS.CUSTOMER_ID AS CUSTOMER_ID
            WITH SYNONYMS = ('顧客ID', 'customer')
            COMMENT = '顧客ID',
        TRADE_ORDERS.CUSTOMER_REGION AS CUSTOMER_REGION
            WITH SYNONYMS = ('顧客リージョン', '地域', 'region')
            COMMENT = '顧客の所属リージョン (Tokyo / US / UK / APAC / EU)',
        TRADE_ORDERS.CUSTOMER_SEGMENT AS CUSTOMER_SEGMENT
            WITH SYNONYMS = ('セグメント', 'segment', '顧客種別')
            COMMENT = '顧客セグメント (CORPORATE / SME / RETAIL)',
        TRADE_ORDERS.RISK_RATING AS RISK_RATING
            WITH SYNONYMS = ('リスク格付', 'risk', 'リスク')
            COMMENT = '顧客リスク格付け (LOW / MEDIUM / HIGH)',
        TRADE_ORDERS.COUNTERPARTY_COUNTRY AS COUNTERPARTY_COUNTRY
            WITH SYNONYMS = ('相手国', '取引先国', 'counterparty')
            COMMENT = '取引相手国 (ISO 3166-1 alpha-2)',
        TRADE_ORDERS.TRANSACTION_TYPE AS TRANSACTION_TYPE
            WITH SYNONYMS = ('取引種別', '種別', 'type')
            COMMENT = '取引種別 (IMPORT / EXPORT / REMITTANCE)',
        TRADE_ORDERS.CURRENCY_CODE AS CURRENCY_CODE
            WITH SYNONYMS = ('通貨', 'currency', '為替')
            COMMENT = '取引通貨 (ISO 4217: JPY / USD / EUR / GBP 等)',
        TRADE_ORDERS.BOOKING_BRANCH AS BOOKING_BRANCH
            WITH SYNONYMS = ('拠点', '支店', 'branch', 'オフィス')
            COMMENT = '記帳拠点 (Tokyo / NewYork / London / Singapore)',
        TRADE_ORDERS.INSTRUMENT_TYPE AS INSTRUMENT_TYPE
            WITH SYNONYMS = ('取引手段', 'instrument')
            COMMENT = '取引手段 (LC=信用状 / TT=電信送金 / DOC_COLL=書類取立)',
        TRADE_ORDERS.TRADE_DATE AS TRADE_DATE
            WITH SYNONYMS = ('取引日', '日付', 'date')
            COMMENT = '取引日',
        TRADE_ORDERS.TRADE_YEAR AS YEAR(TRADE_DATE)
            WITH SYNONYMS = ('年', 'year')
            COMMENT = '取引年',
        TRADE_ORDERS.TRADE_MONTH AS MONTH(TRADE_DATE)
            WITH SYNONYMS = ('月', 'month')
            COMMENT = '取引月',
        CORPORATE_SALES.DEAL_ID AS DEAL_ID
            COMMENT = '案件ID (一意)',
        CORPORATE_SALES.SALES_REP AS SALES_REP
            WITH SYNONYMS = ('営業担当', '担当者', 'rep')
            COMMENT = '営業担当者',
        CORPORATE_SALES.INDUSTRY AS INDUSTRY
            WITH SYNONYMS = ('業種', 'industry', '業界')
            COMMENT = '業種 (製造 / 金融 / IT / 小売 / サービス / 公共)',
        CORPORATE_SALES.COMPANY_SIZE AS COMPANY_SIZE
            WITH SYNONYMS = ('企業規模', 'size', '規模')
            COMMENT = '企業規模 (大手 / 中堅 / 中小)',
        CORPORATE_SALES.STAGE AS STAGE
            WITH SYNONYMS = ('ステージ', 'stage', '案件状態', 'フェーズ')
            COMMENT = '案件ステージ (提案 / 見積 / 受注 / 失注)',
        CORPORATE_SALES.REGION AS REGION
            WITH SYNONYMS = ('営業地域', '地域', 'area')
            COMMENT = '営業地域 (関東 / 関西 / 中部 / 九州 / 海外)',
        CORPORATE_SALES.EXPECTED_CLOSE_DATE AS EXPECTED_CLOSE_DATE
            WITH SYNONYMS = ('受注予定日', 'close date')
            COMMENT = '受注予定日'
    )

    METRICS (
        TRADE_ORDERS.TOTAL_TRADE_AMOUNT AS SUM(TRADE_ORDERS.AMOUNT)
            WITH SYNONYMS = ('取引総額', '総額', 'total amount', '売上')
            COMMENT = '取引金額の合計',
        TRADE_ORDERS.TRADE_COUNT AS COUNT(TRADE_ORDERS.TRANSACTION_ID)
            WITH SYNONYMS = ('取引件数', '件数', 'count', '取引数')
            COMMENT = '取引の総件数',
        TRADE_ORDERS.AVG_TRADE_AMOUNT AS AVG(TRADE_ORDERS.AMOUNT)
            WITH SYNONYMS = ('平均取引額', '平均額', 'average')
            COMMENT = '1取引あたりの平均金額',
        CORPORATE_SALES.TOTAL_PIPELINE AS SUM(CORPORATE_SALES.OPPORTUNITY_AMOUNT)
            WITH SYNONYMS = ('パイプライン総額', 'pipeline', '見込み総額')
            COMMENT = '案件見込み額の合計',
        CORPORATE_SALES.DEAL_COUNT AS COUNT(CORPORATE_SALES.DEAL_ID)
            WITH SYNONYMS = ('案件数', 'deals', '案件件数')
            COMMENT = '案件の総件数',
        CORPORATE_SALES.WIN_RATE AS COUNT_IF(CORPORATE_SALES.STAGE = '受注') / NULLIF(COUNT_IF(CORPORATE_SALES.STAGE IN ('受注', '失注')), 0)
            WITH SYNONYMS = ('受注率', 'win rate', '成約率')
            COMMENT = '受注率 (受注件数 / (受注+失注)件数)'
    )

    COMMENT = 'FSI 貿易取引 + 法人営業の統合分析用セマンティックビュー。Cortex Analyst で自然言語クエリ可能。'

    AI_SQL_GENERATION $$
このセマンティックビューは金融サービス業界の貿易取引データと法人営業パイプラインデータの分析用です。

数値フォーマット:
- 金額は小数点以下を省略し、カンマ区切りで表示（ROUND(..., 0) + TO_CHAR(..., '999,999,999,999')）
- 比率は % 表記で小数点第1位まで (ROUND(...*100, 1) || '%')

デフォルト設定:
- 期間指定がない場合は全期間のデータを使用
- TOP N の指定がない場合はデフォルト上位10件

取引データ:
- 通貨が混在するため、通貨別に集計すること (通貨を跨いだ合算は避ける)
- 拠点別分析は BOOKING_BRANCH でグループ化
- 取引種別は TRANSACTION_TYPE (IMPORT / EXPORT / REMITTANCE)

営業データ:
- 受注率は (受注件数 / (受注+失注)件数) で計算 (提案・見積は分母に含めない)
- パイプライン残高は stage IN ('提案', '見積') の見込み額合計

曖昧な質問への対応:
- 「取引を分析して」→ 通貨別 × 拠点別の取引件数と金額を返す
- 「営業の状況は」→ 営業担当者別の案件数・受注率・パイプライン残高を返す
$$
    COPY GRANTS;

-- Semantic View の確認
SHOW SEMANTIC VIEWS IN SCHEMA fsi_zts_101.semantic_layer;
DESC SEMANTIC VIEW fsi_zts_101.semantic_layer.fsi_trade_analytics;


/*----------------------------------------------------------------------------------
 10. [Option] Cortex Agent — BI エージェントの構築
    -------------------------------------------------
    Cortex Agent は、Cortex Search と Cortex Analyst (Semantic View) を束ねて
    自律的に動作する AI エージェントです。

    Agent は fsi_zts_101.semantic_layer に作成します
    (snowflake_intelligence DB への作成は非推奨)。
----------------------------------------------------------------------------------*/

-- Agent 作成権限の付与
USE ROLE accountadmin;
GRANT CREATE AGENT ON SCHEMA fsi_zts_101.semantic_layer TO ROLE fsi_developer;
USE ROLE fsi_developer;

-- Cortex Agent の作成
CREATE OR REPLACE AGENT fsi_zts_101.semantic_layer.fsi_trade_bi_agent
    COMMENT = '貿易取引の意味検索と数値分析を横断的に行う FSI BI エージェント'
FROM SPECIFICATION $$
{
  "instructions": {
    "response": "あなたは金融サービス企業の高度なトレード分析アシスタントです。2つの専門ツールを使い分けて、ユーザーの質問に日本語で丁寧に回答してください。数値データは適切にフォーマットしてください（金額はカンマ区切り、比率は%表記）。",
    "orchestration": "ツールの使い分けルール:\n\n(1) 取引コメントの検索・コンプライアンス関連メモの確認\n    → TRADE_SEARCH を使用\n\n(2) 取引額・件数・通貨別集計・拠点別分析など数値の質問\n    → TRADE_ANALYST を使用\n\n複合的な質問:\nまず TRADE_SEARCH で関連コメントを確認し、TRADE_ANALYST で数値を分析。",
    "sample_questions": [
      {"question": "通貨別の取引額トップ5を教えてください。"},
      {"question": "コンプライアンス上の懸念がある取引コメントを検索して。"},
      {"question": "東京拠点の月別取引件数の推移を見せてください。"},
      {"question": "営業担当者別の受注率ランキングは？"},
      {"question": "大口取引に付されたコメントの傾向は？"}
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "TRADE_ANALYST",
        "description": "FSI 貿易取引・法人営業データの数値分析。取引金額集計、通貨別・拠点別分析、営業パイプライン、受注率計算に使用。"
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "TRADE_SEARCH",
        "description": "取引コメントの意味検索。コンプライアンス懸念・緊急対応・VIP対応など特定パターンの取引メモを検索。"
      }
    }
  ],
  "tool_resources": {
    "TRADE_ANALYST": {
      "semantic_view": "fsi_zts_101.semantic_layer.fsi_trade_analytics",
      "execution_environment": {"type": "warehouse", "warehouse": "FSI_CORTEX_WH"}
    },
    "TRADE_SEARCH": {
      "name": "fsi_zts_101.harmonized.trade_notes_search",
      "max_results": 10
    }
  }
}
$$;

SHOW AGENTS IN SCHEMA fsi_zts_101.semantic_layer;


/*----------------------------------------------------------------------------------
 11. [Option] Snowflake Intelligence — 会話型 BI インターフェース
    -------------------------------------------------
    Snowflake Intelligence は、Cortex Agent を Snowsight の
    統合インターフェースから利用できるようにする機能です。
----------------------------------------------------------------------------------*/

USE ROLE accountadmin;

-- Snowflake Intelligence オブジェクトの作成
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- エージェントを Snowflake Intelligence に追加
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT fsi_zts_101.semantic_layer.fsi_trade_bi_agent;

/*--
    Snowflake Intelligence へのアクセス:

    1. Snowsight → [AI & ML Studio] → [Snowflake Intelligence]
    2. エージェント 'fsi_trade_bi_agent' を選択
    3. 自然言語で質問:
       - 「通貨別の取引額を教えて」
       - 「東京拠点の先月の取引件数は？」
       - 「コンプライアンス上の懸念があるコメントを検索して」
       - 「営業担当者別の受注率ランキングは？」
--*/


-- =====================================================================
-- ハンズオン終了後のクリーンアップ (必要に応じて実行)
-- =====================================================================

-- Cortex Search Service を削除 (検索インデックス分のストレージを解放)
-- DROP CORTEX SEARCH SERVICE IF EXISTS harmonized.trade_notes_search;

-- Cortex Agent を削除
-- DROP AGENT IF EXISTS snowflake_intelligence.agents.fsi_trade_bi_agent;

-- Snowflake Intelligence からエージェントを解除
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
--   DROP AGENT snowflake_intelligence.agents.fsi_trade_bi_agent;

-- ウェアハウスを SUSPEND (コスト最適化)
-- ALTER WAREHOUSE fsi_cortex_wh SUSPEND;
