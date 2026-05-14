# クリーンアップ手順

ハンズオン終了後、トライアルアカウントのリソースを削除する手順です。

---

## 方法 1: データベース一括削除 (推奨)

最もシンプルな方法です。`fsi_zts_101` データベースとその配下の全オブジェクト (テーブル / ビュー / ステージ / Dynamic Tables / Tasks / Procedures) が一括削除されます。

```sql
USE ROLE accountadmin;
DROP DATABASE IF EXISTS fsi_zts_101;
```

その後ウェアハウスとロールを削除:

```sql
DROP WAREHOUSE IF EXISTS fsi_de_wh;
DROP WAREHOUSE IF EXISTS fsi_dev_wh;
DROP WAREHOUSE IF EXISTS fsi_analyst_wh;
DROP WAREHOUSE IF EXISTS fsi_cortex_wh;

USE ROLE securityadmin;
DROP ROLE IF EXISTS fsi_dataiku_svc;
DROP ROLE IF EXISTS fsi_analyst;
DROP ROLE IF EXISTS fsi_developer;
DROP ROLE IF EXISTS fsi_data_engineer;
DROP ROLE IF EXISTS fsi_admin;
```

## 方法 2: 完全版スクリプト

プロジェクトルートの [`cleanup.sql`](../cleanup.sql) を Snowsight で開いて **Run All** してください。
Task の SUSPEND → DROP、Dynamic Tables、Cortex Search Service なども個別に DROP してからデータベースを削除します。

---

## 注意事項

- `DROP DATABASE` は **元に戻せません** (Time Travel 期間内であれば `UNDROP DATABASE fsi_zts_101;` で復元可能)
- トライアルアカウント自体を削除したい場合は、30 日間の有効期限切れで自動削除されます
- `CORTEX_ENABLED_CROSS_REGION` のアカウント設定は `cleanup.sql` では変更しません。必要に応じて手動で:
  ```sql
  ALTER ACCOUNT UNSET CORTEX_ENABLED_CROSS_REGION;
  ```
