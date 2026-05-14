# ハンズオン詳細アジェンダ

**所要時間**: 4 時間 (240 分、休憩込み)
**対象者**: Python / SQL 基礎レベルのデータエンジニア・データサイエンティスト・アーキテクト
**形式**: オンサイトハンズオン (1 人 1 トライアルアカウント)

---

## タイムテーブル

| 開始 | 終了 | # | セクション | 内容 | 主要ファイル | 時間 |
|------|------|---|---|---|---|---|
| 14:00 | 14:20 | 0 | オープニング | Snowflake AI Data Cloud 全体像 / 銀行業務における 4 データ登録パターンと課題 / As-Is → To-Be アーキ概観 | [`scripts/00_opening_overview.md`](../scripts/00_opening_overview.md) | 20分 |
| 14:20 | 15:05 | 1 | Getting Started | UI ツアー / Virtual Warehouse / RBAC / Time Travel / Resource Monitor / Budget | [`scripts/01_getting_started.sql`](../scripts/01_getting_started.sql) | 45分 |
| 15:05 | 15:35 | 2 | データロード | (a) S3 → COPY INTO / Snowpipe — CSV / JSON / **XML (SWIFT MX 電文 ISO 20022: pacs.008 / camt.053)** [15分]<br>(b) **法人営業 Excel** → Snowpark Stored Procedure + Task で日次自動化 [15分] | [`scripts/02a_data_load_s3_snowpipe.sql`](../scripts/02a_data_load_s3_snowpipe.sql)<br>[`scripts/02b_data_load_excel.sql`](../scripts/02b_data_load_excel.sql) | 30分 |
| 15:35 | 15:50 | ☕ | 休憩 | — | — | 15分 |
| 15:50 | 16:40 | 3 | データ変換 | Tasks + Streams (オンプレバッチ代替) と Dynamic Tables の対比デモ / DAG 可視化 | [`scripts/03_data_transform.sql`](../scripts/03_data_transform.sql) | 50分 |
| 16:40 | 17:20 | 4 | ガバナンス | タグベースマスキング / 行アクセスポリシー / Access History / データ分類 / Trust Center | [`scripts/04_governance.sql`](../scripts/04_governance.sql) | 40分 |
| 17:20 | 17:50 | 5 | Cortex AI | AI 関数 (`AI_CLASSIFY` 等) / Cortex Search / Cortex Analyst / **Dataiku Pushdown 紹介** (デモなし) | [`scripts/05_cortex_ai.sql`](../scripts/05_cortex_ai.sql) | 30分 |
| 17:50 | 18:00 | 6 | まとめ & Next Steps | To-Be アーキ確認 / 必要ナレッジ対応表 / 次のアクション提案 | [`scripts/06_wrap_up.md`](../scripts/06_wrap_up.md) | 10分 |

**合計: 240 分**

---

## 各セクションの目的とゴール

### Section 0 - オープニング (20 分)

**目的**: 本ハンズオンが解決する 4 つの典型的なデータ登録課題と Snowflake によるアーキテクチャ刷新の全体像を把握する。

**ゴール**:
- Snowflake AI Data Cloud の主要コンポーネント (Compute / Storage / Cloud Services) を理解
- 銀行業務における 4 データ登録パターン (① SQL only / ② S3 + Glue / ③ オンプレバッチ / ④ 手動 Excel) と各課題を認識
- 本日 5 セクションがどの課題に対応するかをマッピング

**講師ティップス**: スライドベース。SQL 実行なし。

### Section 1 - Getting Started (45 分)

**目的**: Snowflake の基礎オブジェクト (Warehouse / Role / Time Travel) を実機で体験する。

**ゴール**:
- Virtual Warehouse の作成・スケール変更・サスペンド/リジューム
- RBAC のロール階層 (`fsi_admin` → `fsi_data_engineer` → `fsi_developer`) と GRANT
- Time Travel / UNDROP / クローニング (取引データ誤削除からの即時復旧)
- Resource Monitor / Budget でコスト監視

**講師ティップス**: 各クエリの実行時間とウェアハウスサイズの関係を体感させる。

### Section 2 - データロード (30 分)

**目的**: 既存 ETL (Glue / 手動 Excel) を Snowflake ネイティブの仕組みで置き換える。

#### Section 2(a) - S3 → COPY INTO / Snowpipe (15 分)

**ゴール**:
- 内部ステージ (`@raw_trade.csv_stage` / `json_stage` / `xml_stage`) へのファイルアップロード
- `COPY INTO` での CSV 取り込み (補完サンプル)
- `COPY INTO` での **JSON 取り込み** (`raw_payload` VARIANT)
- `COPY INTO` での **XML (SWIFT MX 電文 ISO 20022: pacs.008 / camt.053) 取り込み** + `XMLGET` / `LATERAL FLATTEN` で構造化
  - `pacs.008` (Customer Credit Transfer / 顧客送金) を 3-5 件
  - `camt.053` (Bank-to-Customer Statement / 口座明細) を 1-2 件
  - 通貨別集計 / 大口取引検出のクエリ例
- `CREATE PIPE ... AUTO_INGEST = TRUE` 構文紹介 (S3 イベント連携は手順説明)

#### Section 2(b) - Excel (法人営業) → Snowpark Stored Procedure (15 分)

**ゴール**:
- `@raw_excel.excel_demo_stage` への `corporate_sales_data.xlsx` (100 行) アップロード
- Python Stored Procedure (`openpyxl` + `pandas`) で Excel を読み取り → `raw_excel.corporate_sales` テーブルへ INSERT
  - 10 カラム: `deal_id` / `sales_rep` / `customer_name` / `industry` / `company_size` / `opportunity_amount` / `stage` / `region` / `last_visit_date` / `expected_close_date`
- `Task` で日次 09:00 JST 自動実行を設定
- `EXECUTE TASK` 即時実行と `TASK_HISTORY` での結果確認

### Section 3 - データ変換 (50 分)

**目的**: オンプレバッチサーバを廃止し、Snowflake 内で SQL 完結のパイプラインを実現する。

**ゴール**:
- (A) `Tasks + Streams` 方式での増分処理パイプラインの構築
- (B) `Dynamic Tables` 方式での宣言的パイプライン (TARGET_LAG)
- DAG 可視化 (Snowsight)
- 両方式の比較と推奨 (Dynamic Tables を主推奨)
- **演習データ**:
  - **法人営業パイプライン分析** (`raw_excel.corporate_sales`): 営業担当別 KPI / 業種別受注率 / 月次受注推移 (ウィンドウ関数)
  - **SWIFT MX 電文の構造化展開** (`raw_trade.swift_messages_xml` → harmonized テーブル): 通貨別 / 相手行別 / 金額帯別の集計
  - **貿易取引** (`raw_trade.trade_transactions` 50K 件): 日次集計を Dynamic Tables で再構築

### Section 4 - ガバナンス (40 分)

**目的**: 銀行業務に必要なデータ保護と監査の仕組みを Snowflake Horizon で実装する。

**ゴール**:
- タグ (`pii_tag` / `financial_amount_tag`) の作成と付与
- タグベースマスキングポリシー (PII / 取引額しきい値)
  - **法人営業**: `customer_name` を PII としてマスキング
  - **取引額**: `opportunity_amount` / `amount` の閾値超過のみマスク
- 行アクセスポリシー
  - **法人営業**: `sales_rep` 別 Row Access (担当案件のみ閲覧可能)
  - **貿易取引**: 拠点 (`booking_branch`) 別 Row Access (Tokyo/NY/London/Singapore)
- `ACCESS_HISTORY` / `QUERY_HISTORY` で監査
- Classification (データ分類) と Trust Center

### Section 5 - Cortex AI + Dataiku 紹介 (30 分)

**目的**: 将来の AI 活用と外部分析基盤との連携アーキテクチャを示す。

**ゴール**:
- Cortex AI 関数 (`AI_CLASSIFY` / `AI_SUMMARIZE_AGG` / `AI_FILTER`) を以下に適用
  - **貿易取引コメント** (`free_text_notes`): 異常検知メモのセンチメント / 分類
  - **SWIFT MX 電文の `RmtInf` (送金理由)**: テキスト解析 / 分類
- Cortex Search Service の作成と検索
- Cortex Analyst (会話形式 BI) のセマンティックモデル `FSI_TRADE_ANALYTICS.yaml`
  - `semantic_layer.corporate_sales_v` (法人営業) と `semantic_layer.trade_orders_v` (貿易取引) を統合
- **Dataiku × Snowflake Pushdown の設計紹介** (`fsi_dataiku_svc` ロール / PrivateLink) — デモなし

### Section 6 - まとめ & Next Steps (10 分)

**目的**: 本日のハンズオンを振り返り、本番展開に向けた次の一歩を整理する。

**ゴール**:
- To-Be アーキテクチャの再確認 (Mermaid)
- [`docs/knowledge_mapping.md`](knowledge_mapping.md) で必要ナレッジを整理
- Next Steps: ① アーキ設計レビュー ② PoC ③ Dataiku 連携設計 ④ ガバナンス設計 ⑤ 本番移行計画

---

## 講師向けチェックリスト

ハンズオン開始前に以下を確認してください ([`docs/verification_checklist.md`](verification_checklist.md) も参照)。

- [ ] 全参加者がトライアルアカウントにログインできている
- [ ] `setup.sql` を全アカウントで実行済み (`✓ FSI Zero To Snowflake セットアップが完了しました。` 表示確認)
- [ ] サンプルファイル ( `assets/sample_data/` 配下の SWIFT MX XML / CSV / JSON、`assets/excel/corporate_sales_data.xlsx` ) が各アカウントの内部ステージにアップロード済み、または各セクション冒頭でアップロード手順を案内する準備ができている
- [ ] Cortex 関数のリージョン適合確認
- [ ] 各セクションの SQL ファイルを参加者のワークスペースに事前共有 (or GitHub URL 共有)
- [ ] 休憩 (15:35-15:50) にコーヒー / 軽食を準備
- [ ] 終了後の次回フォローアップ案内 (PoC / 設計レビュー)
