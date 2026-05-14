/***************************************************************************************************       
Asset:        FSI Zero to Snowflake - クリーンアップ
Version:      v1
Audience:     金融サービス業界 (FSI) 向けハンズオン

このスクリプトは setup.sql で作成したリソースを一括削除します。
ハンズオン終了後、トライアルアカウントを継続利用する場合に実行してください。

実行ロール: ACCOUNTADMIN を推奨
****************************************************************************************************/

USE ROLE accountadmin;

ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"fsi_zts","attributes":{"is_quickstart":1,"vignette":"cleanup"}}';

/*--
 1. Task の SUSPEND と DROP (Excel デモで作成された Task を含む)
--*/

-- セクション 2(b) で作成される Task を停止
ALTER TASK IF EXISTS fsi_zts_101.raw_excel.load_excel_daily_task SUSPEND;
DROP TASK IF EXISTS fsi_zts_101.raw_excel.load_excel_daily_task;

-- セクション 3 (データ変換) で作成され得る Task / Stream を停止
ALTER TASK IF EXISTS fsi_zts_101.harmonized.daily_trade_aggregate_task SUSPEND;
DROP TASK IF EXISTS fsi_zts_101.harmonized.daily_trade_aggregate_task;
DROP STREAM IF EXISTS fsi_zts_101.raw_trade.trade_transactions_stream;

-- セクション 2(a) で作成され得る Snowpipe
DROP PIPE IF EXISTS fsi_zts_101.raw_trade.trade_csv_pipe;

/*--
 2. Dynamic Tables の DROP
--*/

DROP DYNAMIC TABLE IF EXISTS fsi_zts_101.harmonized.trade_orders_dt;
DROP DYNAMIC TABLE IF EXISTS fsi_zts_101.analytics.daily_trade_summary_dt;

/*--
 3. ストアドプロシージャ・関数の DROP
--*/

DROP PROCEDURE IF EXISTS fsi_zts_101.raw_excel.load_excel_to_table(VARCHAR, VARCHAR);

/*--
 4. Cortex Search Service の DROP
--*/

DROP CORTEX SEARCH SERVICE IF EXISTS fsi_zts_101.harmonized.trade_notes_search;

/*--
 5. ガバナンス: タグ・マスキングポリシー・行アクセスポリシーの DROP
    依存関係エラー回避のため、UNSET 後に DROP します
--*/

-- 既存のオブジェクトからポリシーを解除 (個別カラムへの解除はセクション 4 のクリーンアップ部分で対応)
-- ここではガバナンススキーマ配下のオブジェクトのみ削除を試みる
DROP MASKING POLICY IF EXISTS fsi_zts_101.governance.pii_mask;
DROP MASKING POLICY IF EXISTS fsi_zts_101.governance.amount_threshold_mask;
DROP ROW ACCESS POLICY IF EXISTS fsi_zts_101.governance.branch_row_access;
DROP TAG IF EXISTS fsi_zts_101.governance.pii_tag;
DROP TAG IF EXISTS fsi_zts_101.governance.financial_amount_tag;

/*--
 6. データベース全体の DROP (もっとも確実なクリーンアップ)
--*/

DROP DATABASE IF EXISTS fsi_zts_101;

/*--
 7. ウェアハウスの DROP
--*/

DROP WAREHOUSE IF EXISTS fsi_de_wh;
DROP WAREHOUSE IF EXISTS fsi_dev_wh;
DROP WAREHOUSE IF EXISTS fsi_analyst_wh;
DROP WAREHOUSE IF EXISTS fsi_cortex_wh;

/*--
 8. ロールの DROP (依存関係エラー時はコメントアウト)
--*/

USE ROLE securityadmin;
DROP ROLE IF EXISTS fsi_dataiku_svc;
DROP ROLE IF EXISTS fsi_analyst;
DROP ROLE IF EXISTS fsi_developer;
DROP ROLE IF EXISTS fsi_data_engineer;
DROP ROLE IF EXISTS fsi_admin;

/*--
 9. アカウント設定のリセット (任意)
--*/

USE ROLE accountadmin;
-- ALTER ACCOUNT UNSET CORTEX_ENABLED_CROSS_REGION;  -- 必要に応じて手動でアンセット

SELECT '✓ FSI Zero To Snowflake クリーンアップが完了しました。' AS status;
