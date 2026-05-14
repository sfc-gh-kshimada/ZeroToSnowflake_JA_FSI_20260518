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
  2. CLASSIFY_TEXT — 取引コメントの自動分類
  3. SENTIMENT — センチメント分析
  4. COMPLETE — LLM による自由文生成 (コンプライアンスリスク判定)
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
    │ SNOWFLAKE.CORTEX.CLASSIFY_TEXT│ テキストをユーザー定義カテゴリに自動分類     │
    │ AI_CLASSIFY                  │ CLASSIFY_TEXT の後継 (マルチラベル/画像対応)  │
    │ SNOWFLAKE.CORTEX.SENTIMENT   │ テキストの感情スコア (-1.0 〜 1.0)           │
    │ SNOWFLAKE.CORTEX.COMPLETE    │ LLM によるテキスト生成 (プロンプト応答)      │
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
 2. CLASSIFY_TEXT — 取引コメントの自動分類
    -------------------------------------------------
    trade_transactions テーブルの free_text_notes カラムには以下 5 種類のテキストが
    含まれています (setup.sql で合成データとして生成):

      1. 'Standard transaction. No issues reported.'
      2. 'Counterparty requested expedited settlement due to year-end closing.'
      3. 'Suspicious pattern detected. Manual review escalated to compliance.'
      4. 'Customer disputed amount; resolved after reconciliation.'
      5. 'High-priority client. Premium handling.'

    これらを SNOWFLAKE.CORTEX.CLASSIFY_TEXT で自動分類します。
    人手で仕分けルールを書く代わりに、LLM がテキストの意味を理解して分類します。

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

-- 2-2. CLASSIFY_TEXT で 5 カテゴリに分類
--      結果は JSON オブジェクト { "label": "..." } で返るため ['label'] で抽出
SELECT
    transaction_id,
    free_text_notes,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        free_text_notes,
        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority']
    )['label']::VARCHAR AS classification
FROM raw_trade.trade_transactions
LIMIT 20;

-- 2-3. 分類結果の分布を集計
--      50,000 件全件は時間がかかるため、SAMPLE で 1,000 件に絞って実行
SELECT
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        free_text_notes,
        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority']
    )['label']::VARCHAR AS classification,
    COUNT(*)            AS cnt,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM raw_trade.trade_transactions
    SAMPLE (1000 ROWS)
GROUP BY classification
ORDER BY cnt DESC;

-- 2-4. (発展) task_description を付けて精度を上げる
--      金融コンテキストを伝えることで、LLM の分類精度が向上します
SELECT
    transaction_id,
    free_text_notes,
    SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
        free_text_notes,
        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority'],
        {
            'task_description': 'Classify trade transaction notes in a banking context. Focus on compliance risk and operational priority.'
        }
    )['label']::VARCHAR AS classification
FROM raw_trade.trade_transactions
LIMIT 10;


/*----------------------------------------------------------------------------------
 3. SENTIMENT — センチメント分析
    -------------------------------------------------
    SNOWFLAKE.CORTEX.SENTIMENT は、テキストの感情を -1.0 (非常にネガティブ) 〜
    +1.0 (非常にポジティブ) のスコアで返します。

    期待される結果:
      - "Suspicious pattern detected..." → ネガティブ (< 0)
      - "Standard transaction. No issues reported." → ニュートラル〜ポジティブ (>= 0)
      - "High-priority client. Premium handling." → ポジティブ (> 0)
      - "Customer disputed amount..." → ネガティブ (< 0)

    金融ユースケース:
      - 取引コメントの異常検知 (ネガティブスコアの急増をアラート)
      - 顧客コミュニケーションのトーン分析
      - コンプライアンスレビュー優先度の自動付与
----------------------------------------------------------------------------------*/

-- 3-1. 各取引コメントのセンチメントスコアを取得
SELECT
    transaction_id,
    free_text_notes,
    SNOWFLAKE.CORTEX.SENTIMENT(free_text_notes) AS sentiment_score
FROM raw_trade.trade_transactions
LIMIT 20;

-- 3-2. コメント種別ごとの平均センチメントスコア
--      "Suspicious" 系がネガティブ、"Standard" 系がニュートラル〜ポジティブになるか確認
SELECT
    free_text_notes,
    COUNT(*)                                            AS cnt,
    ROUND(AVG(SNOWFLAKE.CORTEX.SENTIMENT(free_text_notes)), 4) AS avg_sentiment
FROM raw_trade.trade_transactions
GROUP BY free_text_notes
ORDER BY avg_sentiment ASC;

-- 3-3. センチメントが特に低い取引を抽出 (コンプライアンス要注意)
--      実務ではこの結果を Dynamic Table やアラートに接続し、自動エスカレーションを構築できます
SELECT
    transaction_id,
    trade_date,
    booking_branch,
    amount,
    free_text_notes,
    SNOWFLAKE.CORTEX.SENTIMENT(free_text_notes) AS sentiment_score
FROM raw_trade.trade_transactions
WHERE SNOWFLAKE.CORTEX.SENTIMENT(free_text_notes) < -0.3
LIMIT 20;


/*----------------------------------------------------------------------------------
 4. COMPLETE — LLM による自由文生成 (コンプライアンスリスク判定)
    -------------------------------------------------
    SNOWFLAKE.CORTEX.COMPLETE は、指定した LLM モデルにプロンプトを送信し、
    テキスト応答を取得します。

    利用可能なモデル例 (AWS_JP クロスリージョン):
      - 'mistral-large2'    : 高品質な汎用モデル
      - 'claude-3-5-sonnet' : Anthropic の高性能モデル
      - 'llama3.1-70b'      : Meta の大規模オープンモデル
      - 'snowflake-arctic'  : Snowflake 自社開発モデル

    注意: モデルの利用可能性はリージョンとクロスリージョン設定に依存します。
          エラーが出た場合は別のモデル名に変更してください。

    金融ユースケース:
      - 取引コメントからコンプライアンスリスクを自動判定
      - 規制報告書の下書き生成
      - 顧客向けレターの自動生成
----------------------------------------------------------------------------------*/

-- 4-1. 基本的な COMPLETE: シンプルなプロンプト
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Snowflake Cortex AI を金融業界で活用する主なユースケースを 3 つ、日本語で簡潔に挙げてください。'
) AS ai_response;

-- 4-2. 取引コメントからコンプライアンスリスクを判定
--      LLM にコンテキストと判定基準を与え、構造化された回答を得る
SELECT
    transaction_id,
    free_text_notes,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
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
/*
SELECT
    message_id,
    XMLGET(payload, 'RmtInf'):"$"::VARCHAR AS remittance_info,
    SNOWFLAKE.CORTEX.COMPLETE(
        'mistral-large2',
        'Analyze the following SWIFT remittance information and determine if it contains any AML red flags. ' ||
        'Respond with: RISK_LEVEL (HIGH/MEDIUM/LOW) and a brief explanation.' ||
        CHR(10) || 'Remittance Info: ' || XMLGET(payload, 'RmtInf'):"$"::VARCHAR
    ) AS aml_analysis
FROM raw_trade.swift_messages_xml
WHERE message_type = 'pacs.008'
LIMIT 5;
*/


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
    results.value:amount::NUMBER(18,2)      AS amount
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
    results.value:amount::NUMBER(18,2)      AS amount
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
      - CLASSIFY_TEXT: テキストをカテゴリに自動分類
        → 取引コメントの仕分け、コンプライアンス自動エスカレーション
      - SENTIMENT: テキストの感情スコアを取得
        → ネガティブスコアの急増検知、異常取引の早期発見
      - COMPLETE: LLM にプロンプトを送信してテキスト生成
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
-- ハンズオン終了後のクリーンアップ (必要に応じて実行)
-- =====================================================================

-- Cortex Search Service を削除 (検索インデックス分のストレージを解放)
-- DROP CORTEX SEARCH SERVICE IF EXISTS harmonized.trade_notes_search;

-- ウェアハウスを SUSPEND (コスト最適化)
-- ALTER WAREHOUSE fsi_cortex_wh SUSPEND;
