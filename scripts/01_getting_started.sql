/***************************************************************************************************       
Asset:        FSI Zero to Snowflake - Getting Started
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン
Disclaimer:   This is a demo asset using synthetic data. Not affiliated with any specific institution.
Copyright(c): 2026 Snowflake Inc. All rights reserved.
****************************************************************************************************

Snowflake 入門 ― Getting Started

  1. Snowflake UI ツアー
  2. 仮想ウェアハウスの探索
  3. クエリ結果キャッシュ
  4. RBAC (ロールベースアクセス制御)
  5. ゼロコピークローニング
  6. タイムトラベル (Time Travel)
  7. リソースモニター / バジェット
  8. ユニバーサルサーチ
  9. まとめ

****************************************************************************************************/

-- 開始前に、このクエリを実行してセッションのクエリタグを設定してください。
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"industry":"financial_services","vignette":"getting_started"}}';

-- ワークシートのコンテキストを設定します
USE DATABASE fsi_zts_101;
USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;


/*----------------------------------------------------------------------------------
  1. Snowflake UI ツアー
----------------------------------------------------------------------------------

  ■ メインメニュー (左側ナビゲーション)
    - Workspaces   : SQL ワークシート / ノートブック / Streamlit アプリ
    - Data         : データベース・スキーマ・テーブルの一覧、データプレビュー
    - AI & ML      : Cortex Analyst / Cortex Search / Document AI
    - Monitoring   : Query History / Dynamic Tables / Task Runs / Alerts
    - Admin        : Warehouses / Resource Monitors / Cost Management / Users & Roles

  ■ 右上のコンテキストバー
    - 現在のロール / ウェアハウス / データベース.スキーマ が表示されています
    - ワークシートでは上部のドロップダウンからも切り替え可能です

  ■ 本日使用するデータベース: fsi_zts_101
    - raw_trade      : 貿易取引の生データ
    - raw_customer   : 顧客マスタ・参照データ
    - raw_excel      : Excel 取り込みデータ
    - harmonized     : 結合済みの中間レイヤ
    - analytics      : ビジネス分析ビュー
    - governance     : マスキングポリシー・タグ
    - semantic_layer : Cortex Analyst 用ビュー

  準備ができたら、次のセクションに進みましょう。
----------------------------------------------------------------------------------*/


/*----------------------------------------------------------------------------------
  2. 仮想ウェアハウスの探索
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/warehouses-overview
----------------------------------------------------------------------------------

  仮想ウェアハウスは、Snowflake のコンピュートエンジンです。
  ストレージとは完全に分離されており、ワークロードに応じて
  サイズ変更 / 起動 / 停止 を柔軟に行えます。

  金融機関では、データエンジニアリング・開発・分析・AI/ML など
  用途ごとにウェアハウスを分けることで、コスト管理とパフォーマンス分離を実現します。

  主なパラメータ:
    > WAREHOUSE_SIZE     : XSmall〜6XLarge (サイズが倍になるごとにクレジット消費も倍)
    > AUTO_SUSPEND       : 非アクティブ後の自動停止までの秒数 (デフォルト: 600 秒)
    > AUTO_RESUME        : クエリ受信時に自動再開するか (デフォルト: TRUE)
    > MIN/MAX_CLUSTER_COUNT : マルチクラスタの設定 (同時実行ユーザが多い場合)
----------------------------------------------------------------------------------*/

-- まず、アクセス権限を持つ既存ウェアハウスを一覧で確認しましょう
SHOW WAREHOUSES;

/*
    結果に 4 つのウェアハウスが表示されます:
    - fsi_de_wh       : データエンジニアリング用 (XSmall)
    - fsi_dev_wh      : 開発者用 (XSmall)
    - fsi_analyst_wh  : アナリスト用 (Large, マルチクラスタ)
    - fsi_cortex_wh   : Cortex AI 用 (Large)

    サイズ、状態 (STARTED / SUSPENDED)、AUTO_SUSPEND 設定などを確認してください。
    Snowsight の Admin > Warehouses ページでも同じ情報を GUI で確認できます。
*/

-- 現在のウェアハウスサイズを確認します
SHOW WAREHOUSES LIKE 'fsi_de_wh';

/*
    ウェアハウスのスケーラビリティを体験してみましょう。
    Snowflake では ALTER WAREHOUSE 一つでオンザフライにサイズ変更が可能です。
    稼働中のクエリに影響を与えることなく、次のクエリから新しいサイズが適用されます。
*/

-- XSmall → Medium にスケールアップ
ALTER WAREHOUSE fsi_de_wh SET WAREHOUSE_SIZE = 'MEDIUM';

-- スケールアップした状態で、貿易取引データを集計してみましょう
-- 拠点別・取引種別ごとの取引件数と総額を確認します
SELECT
    booking_branch,
    transaction_type,
    COUNT(*)                        AS tx_count,
    SUM(amount)                     AS total_amount,
    ROUND(AVG(amount), 2)           AS avg_amount,
    MIN(trade_date)                 AS earliest_trade,
    MAX(trade_date)                 AS latest_trade
FROM raw_trade.trade_transactions
GROUP BY booking_branch, transaction_type
ORDER BY total_amount DESC;

/*
    クエリ結果を確認してください。
    - Tokyo / NewYork / London / Singapore の 4 拠点
    - IMPORT / EXPORT / REMITTANCE の 3 種別
    が表示されているはずです。
*/

-- コスト最適化のため、ウェアハウスを XSmall に戻します
ALTER WAREHOUSE fsi_de_wh SET WAREHOUSE_SIZE = 'XSMALL';

/*
    補足 ― Adaptive Warehouse (Public Preview)
    ウェアハウスサイズの選択が不要な Adaptive Warehouse が現在 Public Preview として提供されています。
    ワークロードに応じてコンピュートリソースを自動的に最適化するため、サイズ選択の手間がなくなります。

    公式ドキュメント: https://docs.snowflake.com/ja/user-guide/warehouses-adaptive
*/

-- ウェアハウスの一時停止 (SUSPEND) と再開 (RESUME) も試してみましょう
ALTER WAREHOUSE fsi_de_wh SUSPEND;

-- サスペンド状態を確認
SHOW WAREHOUSES LIKE 'fsi_de_wh';

-- 再開
ALTER WAREHOUSE fsi_de_wh RESUME;

/*
    AUTO_RESUME = TRUE に設定されているため、クエリを実行すると自動的に再開されます。
    実務では AUTO_SUSPEND を適切な時間 に設定し、不要なクレジット消費を抑えるのが一般的です。
*/


/*----------------------------------------------------------------------------------
  3. クエリ結果キャッシュ
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/querying-persisted-results
----------------------------------------------------------------------------------

  Snowflake には「クエリ結果キャッシュ」という強力な機能があります。
  同じクエリを 24 時間以内に再実行すると、ウェアハウスを使わずに
  キャッシュされた結果が即座に返されます。

  仕組み:
    - キャッシュはクラウドサービスレイヤに保存 (ウェアハウス非消費)
    - 対象テーブルのデータが変更されるまで有効 (最大 24 時間)
    - 同一アカウント内の全ユーザ・全ウェアハウスからアクセス可能
    - 定常的なレポート / ダッシュボードのコスト削減に有効

  実際に体験してみましょう！
----------------------------------------------------------------------------------*/

-- 1 回目: このクエリを実行して、実行時間を「Query Details」で確認してください
SELECT
    booking_branch,
    currency_code,
    COUNT(*)       AS tx_count,
    SUM(amount)    AS total_amount
FROM raw_trade.trade_transactions
GROUP BY booking_branch, currency_code
ORDER BY total_amount DESC;

/*
    Query Details の「Duration」を確認してください (例: 1 秒程度)
*/

-- 2 回目: 全く同じクエリをもう一度実行してください
SELECT
    booking_branch,
    currency_code,
    COUNT(*)       AS tx_count,
    SUM(amount)    AS total_amount
FROM raw_trade.trade_transactions
GROUP BY booking_branch, currency_code
ORDER BY total_amount DESC;

/*
    2 回目の実行時間を確認してください ― 数十ミリ秒に短縮されているはずです！

    Query Profile (クエリ履歴) を開いてみてください:
    - 1 回目: 通常のスキャン処理が表示される
    - 2 回目: 「QUERY RESULT REUSE」と表示される

    これがクエリ結果キャッシュの効果です。
    毎朝のレポートや BI ダッシュボードで同一クエリが繰り返し実行される場合、
    ウェアハウスのクレジットを消費せずに結果を返せるため、大幅なコスト削減になります。
*/


/*----------------------------------------------------------------------------------
  4. RBAC (ロールベースアクセス制御)
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/security-access-control-overview
----------------------------------------------------------------------------------

  金融機関では、データへのアクセス権限を厳密に管理することが必須です。
  Snowflake の RBAC (Role-Based Access Control) では、
  ロール → 権限 → オブジェクト の関係でアクセスを制御します。

  本ハンズオンのロール階層:

    SYSADMIN
      └── fsi_admin           (管理者: 全スキーマ・全ウェアハウス)
            └── fsi_data_engineer   (データエンジニア: RAW / Harmonized / Analytics)
                  ├── fsi_developer       (開発者: Cortex / アプリケーション)
                  └── fsi_analyst         (アナリスト: Analytics 参照のみ)

  ロールごとにアクセスできるスキーマやウェアハウスが異なります。
  実際に切り替えて体験してみましょう。
----------------------------------------------------------------------------------*/

-- 現在のロールとアクセス可能なオブジェクトを確認
SELECT CURRENT_ROLE() AS current_role;

-- ハンズオン用のロール一覧を確認
SHOW ROLES LIKE 'fsi_%';

-- fsi_analyst ロールに付与されている権限を確認
SHOW GRANTS TO ROLE fsi_analyst;

/*
    fsi_analyst には以下の権限が付与されています:
    - harmonized / analytics スキーマへの ALL (SELECT 含む)
    - fsi_analyst_wh への OPERATE, USAGE
    - raw_trade / raw_customer / raw_excel への権限は「ない」ことに注目してください
*/

-- アナリストロールに切り替えてみましょう
USE ROLE fsi_analyst;
USE WAREHOUSE fsi_analyst_wh;

-- analytics ビューへのクエリ → 成功するはずです
SELECT * FROM analytics.daily_trade_summary_v
WHERE booking_branch = 'Tokyo'
ORDER BY trade_date DESC
LIMIT 20;

-- raw_trade のテーブルに直接アクセス → エラーになるはずです
-- (コメントを外して実行し、権限エラーを確認してください)
/*
USE SECONDARY ROLES NONE;
SELECT * FROM raw_trade.trade_transactions LIMIT 10;
*/

/*
    上の SELECT を実行すると、以下のようなエラーが表示されます:
    "Object 'TRADE_TRANSACTIONS' does not exist or not authorized."

    fsi_analyst ロールには raw_trade スキーマへのアクセス権限がないため、
    生データには直接触れられません。これが RBAC による最小権限の原則です。
    アナリストは analytics レイヤの集計ビューのみを参照できます。
*/

-- raw_trade スキーマにテーブルを作成してみましょう → エラーになるはずです
-- (コメントを外して実行し、権限エラーを確認してください)
-- CREATE TABLE raw_trade.test_table (id NUMBER);

/*
    "Insufficient privileges to operate on schema 'RAW_TRADE'."

    アナリストにはテーブル作成権限もありません。
    データの変更はデータエンジニアまたは管理者ロールに限定されています。
*/

-- データエンジニアロールに戻しましょう
USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;

-- fsi_data_engineer は raw_trade スキーマにもアクセスできます
SELECT COUNT(*) AS total_transactions FROM raw_trade.trade_transactions;


/*----------------------------------------------------------------------------------
  5. ゼロコピークローニング
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/tables-storage-considerations#label-cloning-tables
----------------------------------------------------------------------------------

  Snowflake のゼロコピークローニングは、テーブル・スキーマ・データベース全体の
  「完全なコピー」を追加ストレージなしで瞬時に作成できる機能です。

  仕組み:
    - クローンは元テーブルとマイクロパーティションを共有します
    - 片方を変更しても、もう片方には影響しません
    - 変更された部分だけ新しいマイクロパーティションが作成されます

  金融機関での活用例:
    - 本番データのスナップショットを開発環境で利用
    - 規制報告のための時点データ保存
    - 新ロジックのテスト用データセット作成
----------------------------------------------------------------------------------*/

-- 貿易取引テーブルの行数を確認
SELECT COUNT(*) AS original_count FROM raw_trade.trade_transactions;

-- ゼロコピークローンを作成 (数秒で完了！)
CREATE TABLE raw_trade.trade_transactions_clone
    CLONE raw_trade.trade_transactions;

-- クローンの行数を確認 → 元テーブルと同じ件数
SELECT COUNT(*) AS clone_count FROM raw_trade.trade_transactions_clone;

/*
    大量のデータが瞬時にコピーされました。
    しかし、この時点では追加ストレージは「ゼロ」です。

    TABLE_STORAGE_METRICS ビューで確認することもできます:
    SELECT * FROM snowflake.account_usage.table_storage_metrics
    WHERE table_name = 'TRADE_TRANSACTIONS_CLONE';
    (反映まで数分かかる場合があります)
*/

-- クローンのデータを変更してみましょう (NewYork 拠点のデータを削除)
DELETE FROM raw_trade.trade_transactions_clone
WHERE booking_branch = 'NewYork';

-- クローン: NewYork が削除され、件数が減っている
SELECT booking_branch, COUNT(*) AS tx_count
FROM raw_trade.trade_transactions_clone
GROUP BY booking_branch
ORDER BY booking_branch;

-- 元テーブル: 全拠点のデータがそのまま残っている
SELECT booking_branch, COUNT(*) AS tx_count
FROM raw_trade.trade_transactions
GROUP BY booking_branch
ORDER BY booking_branch;

/*
    クローンの変更は元テーブルに影響しません！
    これが「ゼロコピー」の威力です。
    本番データを安全に保ったまま、開発・テストが行えます。
*/

-- クリーンアップ: クローンテーブルを削除
DROP TABLE raw_trade.trade_transactions_clone;


/*----------------------------------------------------------------------------------
  6. タイムトラベル (Time Travel)
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/data-time-travel
----------------------------------------------------------------------------------

  Snowflake のタイムトラベル機能を使うと、過去の任意の時点のデータに
  アクセスしたり、誤って変更・削除したデータを復元できます。

  保持期間:
    - Standard Edition: 最大 1 日 (24 時間)
    - Enterprise Edition 以上: 最大 90 日

  アクセス方法:
    - AT (OFFSET => -N)          : N 秒前のデータ
    - AT (TIMESTAMP => '...')    : 指定タイムスタンプ時点のデータ
    - BEFORE (STATEMENT => '...'): 指定クエリ ID 実行前のデータ

  シナリオ: 「本番テーブルの取引データを誤って削除してしまった！」
----------------------------------------------------------------------------------*/

-- まず、現在の Tokyo 拠点の取引件数を確認しておきましょう
SELECT
    booking_branch,
    COUNT(*) AS tx_count
FROM raw_trade.trade_transactions
WHERE booking_branch = 'Tokyo'
GROUP BY booking_branch;

-- ここで、現在のタイムスタンプを記録しておきます (復元時に使用)
SELECT CURRENT_TIMESTAMP() AS before_delete_timestamp;

/*
    !! 注意: 上のクエリ結果のタイムスタンプを控えておいてください !!
    
    これから、"誤って" Tokyo 拠点の 2025 年より前のデータを削除します。
    実際の運用でも、WHERE 条件の間違いや想定外の DELETE は起こりえます。
*/

-- 誤った DELETE を実行！ (Tokyo 拠点の 2025年1月以前の取引を削除してしまった)
DELETE FROM raw_trade.trade_transactions
WHERE booking_branch = 'Tokyo'
  AND trade_date < '2025-01-01';

-- 大変です！ データが消えてしまいました...
SELECT
    booking_branch,
    COUNT(*) AS tx_count
FROM raw_trade.trade_transactions
WHERE booking_branch = 'Tokyo'
GROUP BY booking_branch;

/*
    Tokyo 拠点の取引件数が大幅に減少しているはずです！
    
    通常のデータベースであれば、ここでバックアップからの復元が必要になり、
    数時間〜数日の作業になることもあります。

    しかし Snowflake のタイムトラベルがあれば、たった 1 つの SQL で復元できます！
*/

-- タイムトラベルで 120 秒前のデータを参照し、削除されたデータを復元
INSERT INTO raw_trade.trade_transactions
SELECT *
FROM raw_trade.trade_transactions AT(OFFSET => -120)
WHERE booking_branch = 'Tokyo'
  AND trade_date < '2025-01-01'
  AND transaction_id NOT IN (
      SELECT transaction_id FROM raw_trade.trade_transactions
  );

-- 復元後の件数を確認
SELECT
    booking_branch,
    COUNT(*) AS tx_count
FROM raw_trade.trade_transactions
WHERE booking_branch = 'Tokyo'
GROUP BY booking_branch;

/*
    Tokyo 拠点のデータが元の件数に戻りました！

    補足: OFFSET ではなくタイムスタンプ指定も可能です:
    SELECT * FROM raw_trade.trade_transactions
        AT(TIMESTAMP => '<先ほど控えたタイムスタンプ>'::TIMESTAMP_TZ);
*/

-- おまけ: UNDROP TABLE パターン
-- テーブル全体を誤って DROP した場合でも復元可能です

-- テスト用にクローンを作成して DROP してみましょう
CREATE TABLE raw_trade.undrop_test CLONE raw_trade.trade_transactions;
DROP TABLE raw_trade.undrop_test;

-- UNDROP で復元！
UNDROP TABLE raw_trade.undrop_test;

-- 復元されたことを確認
SELECT COUNT(*) AS recovered_count FROM raw_trade.undrop_test;

-- クリーンアップ
DROP TABLE raw_trade.undrop_test;

/*
    タイムトラベルと UNDROP は金融機関のデータ管理において非常に重要です:
    - 監査対応: 過去の任意時点のデータを確認可能
    - 障害復旧: 誤操作からの迅速なリカバリ
    - 規制準拠: データの変更履歴を追跡可能
*/


/*----------------------------------------------------------------------------------
  7. リソースモニター / バジェット
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/resource-monitors
  https://docs.snowflake.com/ja/user-guide/budgets
----------------------------------------------------------------------------------

  金融機関のクラウドコスト管理は非常に重要です。
  Snowflake はリソースモニターと予算管理 (Budgets) の 2 つの仕組みを提供しています。

  ■ リソースモニター
    - ウェアハウスのクレジット使用量を監視
    - しきい値に達したときのアクション: NOTIFY / SUSPEND / SUSPEND_IMMEDIATELY
    - ACCOUNTADMIN ロールで作成・管理

  ■ 予算管理 (Budgets)
    - ウェアハウスだけでなく、あらゆる Snowflake サービスのコストを追跡
    - ドル金額ベースでの管理
    - アカウントレベル / カスタム予算の作成が可能
----------------------------------------------------------------------------------*/

-- リソースモニターの作成には ACCOUNTADMIN が必要です
USE ROLE accountadmin;

-- リソースモニターを作成
CREATE OR REPLACE RESOURCE MONITOR fsi_monitor
    WITH CREDIT_QUOTA = 100          -- 月間クレジット上限: 100
    FREQUENCY = MONTHLY              -- DAILY / WEEKLY / YEARLY / NEVER も指定可能
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50 PERCENT DO NOTIFY                -- 50% 到達で通知
        ON 75 PERCENT DO NOTIFY                -- 75% 到達で通知
        ON 90 PERCENT DO SUSPEND               -- 90% 到達でサスペンド (実行中クエリは完了を許可)
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;   -- 100% 到達で即時サスペンド

/*
    TRIGGER の種類:
    - NOTIFY             : アカウント管理者にメール通知を送信
    - SUSPEND            : ウェアハウスをサスペンド (実行中のクエリは完了させる)
    - SUSPEND_IMMEDIATE  : ウェアハウスを即時サスペンド (実行中のクエリもキャンセル)

    金融機関では、90% で SUSPEND、100% で SUSPEND_IMMEDIATE を設定し、
    予算超過を防止するのが一般的です。
*/

-- リソースモニターをウェアハウスに適用
ALTER WAREHOUSE fsi_de_wh SET RESOURCE_MONITOR = fsi_monitor;

-- 作成したリソースモニターを確認
SHOW RESOURCE MONITORS;

/*
    ■ 予算管理 (Budgets) について

    リソースモニターがウェアハウスのクレジット使用量に特化しているのに対し、
    Budgets はすべての Snowflake サービス (ストレージ、コンピュート、
    サーバレス機能、データ転送等) のコストを横断的に管理できます。

    Budgets は Snowsight の Admin > Cost Management > Budgets ページから
    GUI で作成・管理するのが便利です。

    機能の概要:
    - アカウントレベル予算: アカウント全体の月間支出上限を設定
    - カスタム予算: 特定のウェアハウスやスキーマ単位で予算を設定
    - メール通知: 設定したしきい値に達した際に通知
    - 支出予測: 現在のペースでの月末支出を予測表示
*/

-- クリーンアップ: リソースモニターの関連付けを解除して削除
ALTER WAREHOUSE fsi_de_wh SET RESOURCE_MONITOR = NULL;
DROP RESOURCE MONITOR fsi_monitor;

-- ロールを戻します
USE ROLE fsi_data_engineer;
USE WAREHOUSE fsi_de_wh;


/*----------------------------------------------------------------------------------
  8. ユニバーサルサーチ
----------------------------------------------------------------------------------
  ユーザーガイド:
  https://docs.snowflake.com/ja/user-guide/ui-snowsight-universal-search
----------------------------------------------------------------------------------

  ここでも SQL は使用しません。Snowsight で試してみましょう。

  ■ 起動方法
    - Cmd + K (Mac) / Ctrl + K (Windows) でユニバーサルサーチを開く
    - または、画面上部の検索バーをクリック

  ■ 試してみましょう
    1. 「trade_transactions」と入力
       → テーブル、ビュー、ステージなど関連オブジェクトが一覧表示されます

    2. 「通貨別の取引件数」と自然言語で入力
       → 関連するテーブル・ビューが候補として表示されます

    3. 「resource monitor」と入力
       → Snowflake ドキュメントへのリンクも表示されます

  ユニバーサルサーチは、大量のテーブルやビューが存在する環境で
  目的のオブジェクトを素早く見つけるのに非常に便利です。
  Snowflake Marketplace のデータ製品も検索対象に含まれます。
----------------------------------------------------------------------------------*/


/*----------------------------------------------------------------------------------
  9. まとめ
----------------------------------------------------------------------------------

  このセクションでは、Snowflake の基本機能を体験しました:

  ✓ 仮想ウェアハウス
    - オンザフライでサイズ変更が可能 (XSmall ↔ Medium)
    - SUSPEND / RESUME でコンピュートコストを最適化
    - AUTO_SUSPEND / AUTO_RESUME でコスト管理を自動化

  ✓ クエリ結果キャッシュ
    - 同一クエリの再実行はウェアハウス不要で即座に結果を返す
    - ダッシュボード / レポートのコスト削減に有効

  ✓ RBAC (ロールベースアクセス制御)
    - ロール階層でアクセス範囲を制御
    - アナリストは analytics のみ、エンジニアは raw データにもアクセス可能
    - 金融機関のコンプライアンス要件に対応

  ✓ ゼロコピークローニング
    - 追加ストレージなしでテーブルの完全コピーを瞬時に作成
    - 本番データを安全に保ったまま開発・テストが可能

  ✓ タイムトラベル
    - 過去の任意時点のデータにアクセス / 復元可能
    - 誤操作からの迅速なリカバリ
    - UNDROP でドロップしたオブジェクトも復元可能

  ✓ リソースモニター / バジェット
    - クレジット使用量の監視とコスト制御
    - 金融機関のクラウドコスト管理に必須

  次のセクションでは、CSV / JSON / XML / Excel ファイルの
  データロード手法を学びます。
----------------------------------------------------------------------------------*/
