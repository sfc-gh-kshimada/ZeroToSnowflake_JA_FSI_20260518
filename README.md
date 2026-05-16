# FSI Zero To Snowflake ハンズオン

> Original (English): https://www.snowflake.com/en/developers/guides/zero-to-snowflake/
> このリポジトリは、金融サービス業界 (Financial Services Industry / FSI) 向けに Zero To Snowflake を再構成したハンズオンアセットです。
> **本資料は架空の合成データを使用しており、特定の金融機関・企業とは関係ありません。**

## 概要

FSI 向け Zero to Snowflake ハンズオンへようこそ。
本ガイドは「Global Trade Bank (架空)」というジェネリック銀行を主役に、Snowflake AI Data Cloud の主要機能を体験する設計です。

### 学習内容

- Getting Started
  - Snowflake の基礎 (UI / Warehouse / RBAC / Time Travel)
- データロード
  - (a) S3 → COPY INTO / Snowpipe (CSV / JSON / XML)
  - (b) Excel → Snowpark Stored Procedure
- データ変換 | Dynamic Tables / Tasks + Streams 
- ガバナンス | Masking / Row Access / Access History / Trust Center
- Cortex AI | AI 関数 / Search / Analyst

### 構築するもの

- **データプラットフォーム**: 貿易取引・顧客・SWIFT MX 風電文・Excel 取り込みデータを統合した分析基盤
- **データパイプライン**: COPY INTO / Snowpipe による自動取り込み + Dynamic Tables による宣言的変換
- **ガバナンスフレームワーク**: タグベースマスキング / 行アクセスポリシー / Access History
- **AI レイヤー**: Cortex AI 関数 / Cortex Search / Cortex Analyst を活用した会話形式分析

## 前提条件

- Snowflake のブラウザベース Web Interface である **Snowsight** へアクセスできる [ブラウザ](https://docs.snowflake.com/ja/user-guide/setup#browser-requirements)
- **Enterprise** 以上の Snowflake アカウント
  - Snowflake アカウントをお持ちでない場合: [30 日間無料トライアルアカウントにサインアップ](https://signup.snowflake.com/) (Enterprise エディション選択)
- 本ハンズオンを実行する Snowflake アカウントで `ACCOUNTADMIN` ロールが利用可能であること
- Cortex AI 機能が有効なリージョン

## セットアップ

### ステップ 1: トライアルアカウント作成 (参加者ごと)

参加者ごとに専用の Snowflake トライアルアカウントを利用します。

### ステップ 2: setup.sql の実行

1. Snowsight にログインし、左メニュー **Projects → Workspaces** を開きます。
2. **+ Add New → SQL File** で新しい SQL ファイルを作成し、`Setup` のような名前を付けます。
3. 本リポジトリの [`setup.sql`](setup.sql) の内容をコピーして貼り付けます。
4. エディタ左上の **Run All** ボタンですべて実行します。
5. 末尾のステータス行で `✓ FSI Zero To Snowflake セットアップが完了しました。` が表示されれば成功です。

### ステップ 3: サンプルファイルのアップロード (本ハンズオンでは不要だが、バックアップとして記載)

セクション 2(a) で取り込む CSV / JSON / XML、セクション 2(b) で取り込む Excel ファイルを Snowsight から内部ステージにアップロードします。
- `assets/sample_data/trade_csv/*.csv` → `@fsi_zts_101.raw_trade.csv_stage`
- `assets/sample_data/customer_json/*.json` → `@fsi_zts_101.raw_trade.json_stage`
- `assets/sample_data/swift_xml/*.xml` (SWIFT MX 電文 ISO 20022: pacs.008 / camt.053) → `@fsi_zts_101.raw_trade.xml_stage`
- `assets/excel/corporate_sales_data.xlsx` (法人営業データ 100 行) → `@fsi_zts_101.raw_excel.excel_demo_stage`

### ステップ 4: 各セクションの SQL を順次実行

セクション 1 から順に [`scripts/`](scripts/) 配下の SQL を新規 SQL ファイルとして開き、実行します。
ノートブック形式の補完資料は [`scripts/streamlit_app.py`](scripts/streamlit_app.py) 等を参照してください。

---

**License**: 本資料は ZeroToSnowflake (https://github.com/Snowflake-Labs/sfquickstarts) を派生元とします。
**Last Updated**: 2026-05-16
**Disclaimer**: 本資料は FSI 向けデモアセットです。データはすべて合成データであり、特定の金融機関・企業を指すものではありません。
