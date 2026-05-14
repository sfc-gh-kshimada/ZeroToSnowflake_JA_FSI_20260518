# 必要ナレッジ対応表

本ハンズオンで扱う Snowflake 機能と、現行システムのコンポーネントとのマッピングを **★ 優先度** つきで整理します。
本番運用に向けて習得すべきナレッジの全体像として活用してください。

---

## 凡例

- ★★★ — **最重要**: 本日のハンズオンで体験。本番展開でも必ず利用
- ★★  — **重要**: ハンズオンで一部触れる。設計時には深掘り必須
- ★   — **基礎**: 一般的な Snowflake 利用知識として押さえておきたい

---

## 必要ナレッジ対応表

| # | 現行コンポーネント / 業務 | Snowflake 対応技術 | 優先度 | 本ハンズオン該当セクション |
|---|---|---|---|---|
| 1 | **データ取り込み (S3 + Glue ETL)** | `Stage` / `COPY INTO` / **`Snowpipe`** (自動取り込み) / `File Format` | ★★★ | [Section 2(a)](../scripts/02a_data_load_s3_snowpipe.sql) |
| 2 | **データ取り込み (XML/JSON 半構造化)** | `VARIANT` 型 / `XMLGET` / `LATERAL FLATTEN` / `PARSE_JSON` / **ISO 20022 SWIFT MX (pacs.008 / camt.053) パース** | ★★★ | [Section 2(a)](../scripts/02a_data_load_s3_snowpipe.sql) |
| 3 | **データ取り込み (法人営業 Excel)** | `Internal Stage` + `PUT` / **Snowpark Stored Procedure** (`openpyxl` + `pandas`) + `Task` (日次 09:00 JST) | ★★★ | [Section 2(b)](../scripts/02b_data_load_excel.sql) |
| 4 | **オンプレ/EC2 バッチ処理** | **`Tasks` + `Streams`** (増分処理) / **`Dynamic Tables`** (宣言的) | ★★★ | [Section 3](../scripts/03_data_transform.sql) |
| 5 | **Amazon RDS (永続化)** | `Snowflake Tables` / **`Time Travel`** / `Fail-safe` / `Zero-Copy Cloning` | ★★ | [Section 1](../scripts/01_getting_started.sql) |
| 6 | **アクセス管理 (AD / IAM)** | **`RBAC`** (Role / Grant / Privilege Hierarchy) / SCIM / SAML 2.0 / OAuth 2.0 | ★★★ | [Section 1](../scripts/01_getting_started.sql), [Section 4](../scripts/04_governance.sql) |
| 7 | **データ保護 (PII / 取引額)** | **タグベースマスキング** (`Tag` + `Masking Policy`) / `Row Access Policy` / `External Tokenization` | ★★★ | [Section 4](../scripts/04_governance.sql) |
| 8 | **監査・ログ** | `ACCESS_HISTORY` / `QUERY_HISTORY` / `LOGIN_HISTORY` | ★★ | [Section 4](../scripts/04_governance.sql) |
| 9 | **データ分類 (PII 自動検出)** | `Classification` (Built-in + Custom Rules) / Trust Center | ★★ | [Section 4](../scripts/04_governance.sql) |
| 10 | **可視化ツール (Tableau)** | `Snowflake Connector for Tableau` (既存接続継続) / `Streamlit in Snowflake` | ★ | (既存接続継続のため省略) |
| 11 | **Dataiku 連携 (新規)** | **`Snowpark` / Pushdown** / Service Account 設計 / PrivateLink ネットワークポリシー | ★★★ | [Section 5](../scripts/05_cortex_ai.sql), [`docs/dataiku_integration_notes.md`](dataiku_integration_notes.md) |
| 12 | **AI / LLM 活用** | **Cortex AI 関数** (`AI_CLASSIFY` / `AI_SUMMARIZE_AGG` / `AI_FILTER`) / `Cortex Search` / `Cortex Analyst` | ★★ | [Section 5](../scripts/05_cortex_ai.sql) |
| 13 | **コスト管理** | `Resource Monitor` / `Budget` / `WAREHOUSE_METERING_HISTORY` | ★★ | [Section 1](../scripts/01_getting_started.sql) |
| 14 | **ネットワークセキュリティ** | `Network Policy` / `PrivateLink` (AWS / Azure / GCP) / `Outbound Network Rule` | ★★ | (本ハンズオン外、設計時に検討) |
| 15 | **災害対策・BCP** | `Time Travel` / `Fail-safe` / `Replication` / `Failover` | ★ | [Section 1](../scripts/01_getting_started.sql) |
| 16 | **データ共有 (拠点間)** | `Direct Sharing` / `Data Clean Room` / `Marketplace` | ★ | (本ハンズオン外) |

---

## 既存接続維持 (ハンズオン外)

以下は本ハンズオンの対象外ですが、既存の接続を継続利用する設計が可能です。

- **AWS との接続**: 既存の `PrivateLink` + `Direct Connect` を継続利用 (追加設定不要)
- **オンプレからの接続**: PrivateLink を介した安全な通信
- **Tableau Server 接続**: 既存の `Snowflake Connector for Tableau` を継続利用

---

## 本日カバーしないが押さえておきたい関連トピック

| トピック | 概要 | 参考ドキュメント |
|---|---|---|
| Snowflake Native App Framework | Snowflake 上でアプリを開発・配布 | [Native Apps Documentation](https://docs.snowflake.com/ja/developer-guide/native-apps/native-apps-about) |
| Snowpark Container Services (SPCS) | カスタム Docker コンテナを Snowflake 内で実行 (大規模 Excel / 長時間処理向け) | [`docs/excel_demo_appendix.md`](excel_demo_appendix.md) Section 9.1 |
| Iceberg Tables | Apache Iceberg 形式のテーブルを Snowflake で管理 | [Iceberg Tables](https://docs.snowflake.com/ja/user-guide/tables-iceberg) |
| Openflow | NiFi ベースの GUI フロー設計 (複数ソース統合に強み) | [`docs/excel_demo_appendix.md`](excel_demo_appendix.md) Section 3 |

---

## 本番移行に向けた推奨学習順序

1. **Section 1 の RBAC + Time Travel** を理解 → ロール設計とリカバリ戦略を確立
2. **Section 2 のデータロード** を本番データで PoC → 既存 Glue / バッチを段階的に置換
3. **Section 4 のガバナンス** を設計 → タグベースポリシーで一元管理
4. **Section 3 の Dynamic Tables** で本番パイプライン構築
5. **Section 5 の Cortex AI / Dataiku 連携** を高度活用

---

## 関連資料

- [`docs/agenda.md`](agenda.md) — 詳細アジェンダ
- [`docs/architecture.md`](architecture.md) — As-Is / To-Be アーキテクチャ
- [`docs/dataiku_integration_notes.md`](dataiku_integration_notes.md) — Dataiku Pushdown 設計
- [`docs/excel_demo_appendix.md`](excel_demo_appendix.md) — Snowpark vs SPCS / Openflow 比較
