# 講師用 最終確認チェックリスト

ハンズオン開始前に以下を確認してください。

---

## 1. 環境確認

- [ ] 全参加者 (8 名) がトライアルアカウントにログインできる
- [ ] 全アカウントで `setup.sql` が正常完了 (`✓ FSI Zero To Snowflake セットアップが完了しました。` 表示)
- [ ] `fsi_zts_101` データベースが表示される
- [ ] `raw_trade.trade_transactions` に 50,000 行、`raw_customer.customers` に 1,000 行、`raw_excel.corporate_sales` に 100 行が存在
- [ ] ウェアハウス (`fsi_de_wh` 等) が Suspended 状態 (コスト抑制)
- [ ] `CORTEX_ENABLED_CROSS_REGION = 'AWS_JP'` が設定済み (`SHOW PARAMETERS LIKE 'CORTEX%' IN ACCOUNT;` で確認)

## 2. サンプルファイル

- [ ] `assets/sample_data/swift_xml/` 配下に pacs.008 × 5 件 + camt.053 × 2 件
- [ ] `assets/excel/corporate_sales_data.xlsx` (100 行)
- [ ] 各ファイルを Snowsight からステージにアップロードする手順を準備 (or 事前アップロード済み)

## 3. Cortex AI 確認

- [ ] `SELECT SNOWFLAKE.CORTEX.SENTIMENT('This is a test');` が正常に実行できる
- [ ] エラーが出る場合は `CORTEX_ENABLED_CROSS_REGION` を `'AWS_APJ'` or `'ANY_REGION'` に変更

## 4. セクション SQL

- [ ] `scripts/01_getting_started.sql` 〜 `05_cortex_ai.sql` を通しで一度実行し、エラーがないことを確認
- [ ] Time Travel (Section 1) の DELETE → 復旧が正しく動作することを確認 (直近削除が AT(OFFSET) で復元できること)
- [ ] Task (Section 2b / 3) の `EXECUTE TASK` が SUCCEEDED になること
- [ ] Masking Policy (Section 4) で `fsi_analyst` ロールから見ると `***MASKED***` になることを確認

## 5. 公開対応

- [ ] リポジトリ内に `mizuho` / `GTMP` / `みずほ` / `DEMOAPP` が含まれていないこと
  ```bash
  grep -ri "mizuho\|GTMP\|gtmp\|みずほ\|DEMOAPP\|demoapp" . | grep -v ".git/" | grep -v ".cortex/"
  ```
- [ ] 個人情報・実在企業名がサンプルデータに含まれていないこと
- [ ] `internal_talking_points.md` が `.gitignore` に含まれていること

## 6. 時間配分

| セクション | 想定時間 | SQL 行数目安 | 注意点 |
|---|---|---|---|
| 0. オープニング | 20 分 | — | スライドベース、SQL 実行なし |
| 1. Getting Started | 45 分 | ~450 行 | Time Travel のデモが印象的なので丁寧に |
| 2. データロード | 30 分 (15+15) | ~930 行 | XML の XMLGET が初見では難しいのでゆっくり |
| ☕ 休憩 | 15 分 | — | |
| 3. データ変換 | 50 分 | ~500 行 | Dynamic Tables vs Tasks の比較が肝 |
| 4. ガバナンス | 40 分 | ~400 行 | ロール切り替えデモを必ず実施 |
| 5. Cortex AI | 30 分 | ~350 行 | Cortex 関数がリージョンで使えない場合の代替手順を準備 |
| 6. まとめ | 10 分 | — | Next Steps を具体的に |

## 7. 当日の運営

- [ ] WiFi / 有線 LAN の接続確認
- [ ] プロジェクタ / モニタに Snowsight を表示できる
- [ ] 休憩時にコーヒー / 軽食を準備
- [ ] 参加者に GitHub URL (or USB) でアセットを共有する手段を確認
- [ ] 質問対応用に `internal_talking_points.md` を手元に準備

---

## Quick SQL チェック (開始 30 分前に実行)

```sql
USE ROLE accountadmin;
USE DATABASE fsi_zts_101;
USE WAREHOUSE fsi_de_wh;

-- データ確認
SELECT 'trade_transactions' AS tbl, COUNT(*) AS cnt FROM raw_trade.trade_transactions
UNION ALL
SELECT 'customers', COUNT(*) FROM raw_customer.customers
UNION ALL
SELECT 'corporate_sales', COUNT(*) FROM raw_excel.corporate_sales;

-- Cortex 動作確認
SELECT SNOWFLAKE.CORTEX.SENTIMENT('All systems operational. Ready for the workshop.');

-- ステージ確認
LIST @raw_trade.xml_stage;
LIST @raw_excel.excel_demo_stage;
```
