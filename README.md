# FSI Zero To Snowflake ハンズオン

> Original (English): https://www.snowflake.com/en/developers/guides/zero-to-snowflake/
> このリポジトリは、金融サービス業界 (Financial Services Industry / FSI) 向けに Zero To Snowflake を再構成したハンズオンアセットです。
> **本資料は架空の合成データを使用しており、特定の金融機関・企業とは関係ありません。**

## 概要

FSI 向け Zero to Snowflake ハンズオンへようこそ。
本ガイドは「Global Trade Bank (架空)」というジェネリック銀行を主役に、銀行業務で頻出する 2 つの代表的なデータシナリオを題材に Snowflake AI Data Cloud の主要機能を 4 時間で体験する設計です。

### データシナリオ

| # | シナリオ | データソース | データ形式 | 想定ユースケース |
|---|---|---|---|---|
| ① | **法人営業 × Tableau 分析** | `corporate_sales_data.xlsx` (100 行) | Excel | 法人向け営業活動データを Tableau / Streamlit で可視化・分析。手動 Excel 取り込み運用を Snowpark Stored Procedure + Task で自動化 |
| ② | **SWIFT MX 電文取り込み** | `pacs.008` / `camt.053` 等 (ISO 20022 XML) | XML | SWIFT MX 電文 (顧客送金 / 口座明細) を VARIANT 型で取り込み、`XMLGET` / パス記法で構造化展開 |

加えてバルクサンプルとして合成貿易取引 (50,000 件) と顧客マスタ (1,000 社) を生成し、Section 1 (基礎) / Section 3 (変換) / Section 4 (ガバナンス) の演習で使用します。

### 学習内容 (アジェンダ)

| # | セクション | 内容 | 時間 |
|---|---|---|---|
| 0 | オープニング | Snowflake によるハンズオン/今後のご提案 全体像 | 20分 |
| 1 | Getting Started | Snowflake の基礎 (UI / Warehouse / RBAC / Time Travel) | 45分 |
| 2 | データロード | (a) S3 → COPY INTO / Snowpipe (CSV / JSON / XML) + (b) Excel → Snowpark Stored Procedure | 30分 |
| ☕ | 休憩 | — | 15分 |
| 3 | データ変換 | Dynamic Tables / Tasks + Streams (オンプレバッチ代替) | 50分 |
| 4 | ガバナンス | Masking / Row Access / Access History / Trust Center | 40分 |
| 5 | Cortex AI | AI 関数 / Search / Analyst + Dataiku × Snowflake Pushdown 紹介 (デモなし) | 30分 |
| 6 | まとめ & Next Steps | To-Be アーキ + ナレッジ対応表 | 10分 |

**合計: 240 分 (4 時間)**

詳細は [`docs/agenda.md`](docs/agenda.md) を参照してください。

### 構築するもの

- **データプラットフォーム**: 貿易取引 50,000 件・顧客 1,000 社・SWIFT MX 風電文・Excel 取り込みデータを統合した分析基盤
- **データパイプライン**: COPY INTO / Snowpipe による自動取り込み + Dynamic Tables による宣言的変換
- **ガバナンスフレームワーク**: タグベースマスキング / 行アクセスポリシー / Access History
- **AI レイヤー**: Cortex AI 関数 / Cortex Search / Cortex Analyst を活用した会話形式分析
- **将来拡張**: Dataiku × Snowflake Pushdown 連携の設計パターン

## 前提条件

- Snowflake のブラウザベース Web Interface である **Snowsight** へアクセスできる [ブラウザ](https://docs.snowflake.com/ja/user-guide/setup#browser-requirements)
- **Enterprise** 以上の Snowflake アカウント
  - Snowflake アカウントをお持ちでない場合: [30 日間無料トライアルアカウントにサインアップ](https://signup.snowflake.com/) (Enterprise エディション選択)
  - 詳細手順: [`docs/trial_account_setup.md`](docs/trial_account_setup.md)
- 本ハンズオンを実行する Snowflake アカウントで `ACCOUNTADMIN` ロールが利用可能であること
- Cortex AI 機能が有効なリージョン (`setup.sql` 内で `CORTEX_ENABLED_CROSS_REGION = 'AWS_JP'` を設定し、推論を **AWS 東京 / 大阪** リージョンのみに限定。日本の金融機関のデータ残留性要件に最適化)

## ディレクトリ構成

```
ZeroToSnowflake_JA_FSI_20260518/
├── README.md                    # 本ファイル
├── setup.sql                    # 環境構築スクリプト (DB / スキーマ / WH / ロール / 合成データ)
├── cleanup.sql                  # 環境クリーンアップスクリプト
├── assets/                      # ヘッダー画像 + サンプルデータ
│   ├── excel/
│   │   └── corporate_sales_data.xlsx  # セクション 2(b) 用 法人営業データ (100 行)
│   └── sample_data/
│       ├── swift_xml/                  # セクション 2(a) 用 SWIFT MX 電文 (pacs.008 / camt.053)
│       ├── customer_json/              # セクション 2(a) 用 JSON サンプル
│       └── trade_csv/                  # セクション 2(a) 用 CSV サンプル
├── scripts/
│   ├── 00_opening_overview.md       # セクション 0 講師スクリプト
│   ├── 01_getting_started.sql       # セクション 1
│   ├── 02a_data_load_s3_snowpipe.sql # セクション 2(a)
│   ├── 02b_data_load_excel.sql      # セクション 2(b)
│   ├── 02b_excel_loader_proc.py     # セクション 2(b) Python 部分 (参考)
│   ├── 03_data_transform.sql        # セクション 3
│   ├── 04_governance.sql            # セクション 4
│   ├── 05_cortex_ai.sql             # セクション 5
│   ├── 06_wrap_up.md                # セクション 6 講師スクリプト
│   ├── streamlit_app.py             # 補完: 取り込みデータ可視化
│   └── FSI_TRADE_ANALYTICS.yaml     # Cortex Analyst セマンティックモデル
└── docs/
    ├── agenda.md                # 詳細タイムテーブル
    ├── architecture.md          # As-Is / To-Be アーキテクチャ図
    ├── knowledge_mapping.md     # 必要ナレッジ対応表 (★優先度)
    ├── trial_account_setup.md   # 参加者向け事前案内
    ├── cleanup_guide.md         # クリーンアップ手順
    ├── excel_demo_appendix.md   # Excel デモ補足 (Snowpark vs SPCS / Openflow 比較)
    ├── dataiku_integration_notes.md # Dataiku Pushdown 設計詳細
    └── verification_checklist.md    # 講師用最終確認
```

## セットアップ

### ステップ 1: トライアルアカウント作成 (参加者ごと)

参加者ごとに専用の Snowflake トライアルアカウントを利用します。
詳細手順は [`docs/trial_account_setup.md`](docs/trial_account_setup.md) を参照してください。

### ステップ 2: setup.sql の実行

1. Snowsight にログインし、左メニュー **Projects → Workspaces** を開きます。
2. **+ Add New → SQL File** で新しい SQL ファイルを作成し、`Setup` のような名前を付けます。
3. 本リポジトリの [`setup.sql`](setup.sql) の内容をコピーして貼り付けます。
4. エディタ左上の **Run All** ボタンですべて実行します。
5. 末尾のステータス行で `✓ FSI Zero To Snowflake セットアップが完了しました。` が表示されれば成功です。

### ステップ 3: サンプルファイルのアップロード

セクション 2(a) で取り込む CSV / JSON / XML、セクション 2(b) で取り込む Excel ファイルを Snowsight から内部ステージにアップロードします。
- `assets/sample_data/trade_csv/*.csv` → `@fsi_zts_101.raw_trade.csv_stage`
- `assets/sample_data/customer_json/*.json` → `@fsi_zts_101.raw_trade.json_stage`
- `assets/sample_data/swift_xml/*.xml` (SWIFT MX 電文 ISO 20022: pacs.008 / camt.053) → `@fsi_zts_101.raw_trade.xml_stage`
- `assets/excel/corporate_sales_data.xlsx` (法人営業データ 100 行) → `@fsi_zts_101.raw_excel.excel_demo_stage`

詳細手順は各セクションの SQL ファイル冒頭コメントに記載されています。

### ステップ 4: 各セクションの SQL を順次実行

セクション 1 から順に [`scripts/`](scripts/) 配下の SQL を新規 SQL ファイルとして開き、実行します。
ノートブック形式の補完資料は [`scripts/streamlit_app.py`](scripts/streamlit_app.py) 等を参照してください。

## クリーンアップ

ハンズオン終了後、トライアルアカウントを継続利用する場合は [`cleanup.sql`](cleanup.sql) を実行してリソースを削除してください。
詳細は [`docs/cleanup_guide.md`](docs/cleanup_guide.md) を参照してください。

## トラブルシュート

### Cortex 関数が利用できない場合

- `setup.sql` で `CORTEX_ENABLED_CROSS_REGION = 'AWS_JP'` (東京/大阪のみ) を設定しています。`AWS_JP` がアカウントで利用できない場合は以下にフォールバックしてください。
  - `'AWS_APJ'` — APAC 全域 (東京/大阪/ソウル/シンガポール/シドニー 等)
  - `'ANY_REGION'` — 全世界 (制限なし)
  - 該当リージョン値 (例: `'AWS_US'` / `'AWS_EU'`)
- 設定値が組織のポリシーで許可されていない可能性もあるため、組織の管理者に確認してください。
- Cortex 関数が利用可能な[リージョン一覧](https://docs.snowflake.com/ja/user-guide/snowflake-cortex/aisql#availability) と [Cross-region inference](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cross-region-inference) を確認してください。

### COPY INTO が `0 files loaded` を返す場合

- ステージ名・ファイルパスが正しいか確認してください。
- `LIST @stage_name;` でステージ内のファイル一覧を確認できます。

### Task が実行されない場合

- `ALTER TASK ... RESUME;` を実行したか確認してください (デフォルトは Suspended)。
- `EXECUTE TASK <task_name>;` で手動実行して動作確認できます。

## 参考リンク

- [Snowflake Documentation](https://docs.snowflake.com/ja/)
- [Snowflake Cortex AI](https://docs.snowflake.com/ja/user-guide/snowflake-cortex/aisql)
- [Cortex Analyst](https://docs.snowflake.com/ja/user-guide/snowflake-cortex/cortex-analyst)
- [Dynamic Tables](https://docs.snowflake.com/ja/user-guide/dynamic-tables-about)
- [Tasks](https://docs.snowflake.com/ja/user-guide/tasks-intro)

---

**License**: 本資料は ZeroToSnowflake (https://github.com/Snowflake-Labs/sfquickstarts) を派生元とします。
**Last Updated**: 2026-05-11
**Disclaimer**: 本資料は FSI 向けデモアセットです。データはすべて合成データであり、特定の金融機関・企業を指すものではありません。
