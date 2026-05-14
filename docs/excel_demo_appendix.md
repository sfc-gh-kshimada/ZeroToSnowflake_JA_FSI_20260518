# Excel デモ補足資料

## 1. Snowpark (Virtual Warehouse) vs SPCS の使い分け

本ハンズオンの Excel 取り込みは **Snowpark ウェアハウス上の Stored Procedure** で実行しています。

| 観点 | Snowpark (WH) | SPCS (Snowpark Container Services) |
|---|---|---|
| **実行環境** | Virtual Warehouse (Anaconda パッケージ利用可) | カスタム Docker コンテナ |
| **適するファイルサイズ** | 〜数百 MB | 数 GB 〜 TB 級 |
| **処理時間** | 〜数分 | 数十分〜数時間 |
| **パッケージ制約** | Anaconda Channel にあるもの (openpyxl, pandas 等) | 任意のパッケージ (pip install 自由) |
| **課金モデル** | WH クレジット (実行中のみ) | コンテナ稼働時間 |
| **セットアップ難易度** | 低 (SQL 内で完結) | 高 (Docker ビルド + イメージレジストリ) |
| **推奨ユースケース** | 定型的な Excel/CSV 変換 + テーブル書き込み | ML モデル推論 / 大規模ファイル処理 / GPU 利用 |

**結論**: 100〜数千行の Excel 取り込みであれば **Snowpark (WH)** で十分。SPCS は「カスタム Docker 環境が必要」「長時間バッチ」「数 GB 級ファイル」の場合に検討。

---

## 2. Openflow ExcelReader との比較

本ハンズオンでは Snowflake ネイティブ (Snowpark SP) を採用しましたが、Openflow (NiFi ベース) との比較も参考になります。

| 観点 | Snowflake ネイティブ (Snowpark SP) | Openflow ExcelReader |
|---|---|---|
| **Stage からの直接読み取り** | ✅ `session.file.get_stream()` | ❌ Stage 直接 Fetch 不可 (S3 経由が必要) |
| **追加インフラ** | 不要 (WH のみ) | Openflow ランタイム維持必要 |
| **GUI フロー設計** | なし (Task History で確認) | ✅ NiFi Canvas でフロー可視化 |
| **複雑な変換** | Python コード修正 | Processor チェーンで視覚的に構成 |
| **運用コスト** | Task 実行時のみ WH 課金 | ランタイム常時稼働 or オンデマンド起動 |
| **保守性** | SQL + Python で完結、シンプル | NiFi + Controller Service の理解が必要 |

**結論**: 「Snowflake Stage 上のファイルを直接取り込み」の要件には **Snowflake ネイティブが最適**。Openflow は「複数ソース統合」「GUI フロー設計が組織要件」の場合に検討。

### Openflow で利用可能な Excel 関連コンポーネント

| 種類 | コンポーネント名 |
|---|---|
| Controller Service | `org.apache.nifi.excel.ExcelReader` |
| Processor | `org.apache.nifi.processors.excel.SplitExcel` |
| Processor | `com.snowflake.openflow.runtime.processors.office.ParseExcelCellReference` |

---

## 3. 本番運用へのステップアップ

| # | 観点 | ハンズオン | 本番 |
|---|---|---|---|
| 1 | ファイルアップロード | Snowsight UI (ドラッグ&ドロップ) | SnowSQL `PUT` / Snowflake Connector for Python / 自動連携 |
| 2 | ロール | `ACCOUNTADMIN` | 専用ロール (`excel_handson_user_role` 等) に最小権限付与 |
| 3 | Task スケジュール | `CRON 0 9 * * * Asia/Tokyo` (日次) | 業務要件に応じた頻度 + 依存 Task チェーン |
| 4 | エラーハンドリング | なし (成功前提) | TRY/CATCH + Alert + 監視ダッシュボード |
| 5 | データ品質 | なし | Data Metric Functions (DMF) でカラムレベル品質チェック |
| 6 | 参加者ごとの環境分離 | 個別トライアルアカウント | 組織内アカウント + スキーマ分離 or Database 分離 |

---

## 4. 参考資料

- [Snowpark Python Developer Guide](https://docs.snowflake.com/ja/developer-guide/snowpark/python/index)
- [Snowpark Container Services (SPCS)](https://docs.snowflake.com/ja/developer-guide/snowpark-container-services/overview)
- [Openflow Documentation](https://docs.snowflake.com/ja/user-guide/data-load/openflow/openflow-about)
- [Tasks](https://docs.snowflake.com/ja/user-guide/tasks-intro)
- [File Upload via Snowsight](https://docs.snowflake.com/ja/user-guide/data-load-local-file-system-stage-ui)
