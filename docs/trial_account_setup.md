# 参加者向け: Snowflake トライアルアカウントの取得手順

本ハンズオンでは、参加者 1 名につき 1 つの Snowflake トライアルアカウントを使用します。
事前に以下の手順でアカウントを作成してください。

---

## ステップ 1: サインアップ

1. [Snowflake 30 日間無料トライアル](https://signup.snowflake.com/) にアクセスします。
2. フォームに以下を入力:
   - **First Name / Last Name**: ご自身のお名前
   - **Email**: 業務メールアドレス
   - **Company**: ご所属企業名
   - **Country**: `Japan`
3. **Continue** をクリック

## ステップ 2: エディションとリージョンの選択

| 設定項目 | 推奨値 | 理由 |
|---|---|---|
| **Snowflake Edition** | `Enterprise` | Row Access Policy / Masking Policy / Trust Center を使用するため |
| **Cloud Provider** | `AWS` | 本ハンズオンのデモデータ・Cortex AI 設定が AWS 前提 |
| **Region** | `Asia Pacific (Tokyo)` | `CORTEX_ENABLED_CROSS_REGION = 'AWS_JP'` で東京/大阪に限定するため |

4. 上記を選択し、**Get Started** をクリック

## ステップ 3: アカウント有効化

5. 登録メールアドレスにアクティベーションリンクが届きます (数分以内)
6. リンクをクリックし、ユーザー名とパスワードを設定します
   - ユーザー名は後から変更できません。シンプルな名前 (例: `admin`) を推奨
   - パスワードは 8 文字以上、大文字・小文字・数字を含む

## ステップ 4: ログイン確認

7. アクティベーション完了後に表示される Snowflake アカウント URL (例: `https://xxxxxxx-xxxxxxx.snowflakecomputing.com`) にアクセス
8. 設定したユーザー名とパスワードでログイン
9. Snowsight (Web UI) が表示されれば成功です

---

## ハンズオン当日に必要なもの

| 項目 | 詳細 |
|---|---|
| **ブラウザ** | Chrome / Firefox / Edge / Safari (最新版) |
| **Snowflake アカウント URL** | アクティベーションメールに記載 |
| **ユーザー名 / パスワード** | ステップ 3 で設定したもの |
| **ロール** | `ACCOUNTADMIN` (トライアルアカウントではデフォルトで利用可能) |

---

## トラブルシュート

### アクティベーションメールが届かない

- 迷惑メールフォルダを確認してください
- 企業のメールフィルタで `snowflake.com` ドメインがブロックされている場合があります
- 5 分以上経っても届かない場合は [Snowflake Support](https://community.snowflake.com/s/article/How-To-Submit-a-Support-Case-in-Snowflake-Lodge) に問い合わせてください

### Enterprise エディションが選択できない

- 2024 年以降のトライアルでは Enterprise がデフォルトで選択可能です
- 選択肢が表示されない場合は Standard でも進められますが、Section 4 (ガバナンス) の一部機能が制限されます

### リージョンに Asia Pacific (Tokyo) がない

- AWS を選択後に表示される地域一覧から `Asia Pacific (Tokyo)` を探してください
- 見つからない場合は `US West (Oregon)` でも演習可能ですが、`setup.sql` 内の `CORTEX_ENABLED_CROSS_REGION` を `'AWS_US'` に変更してください

---

## 注意事項

- トライアルアカウントは **30 日間有効**、クレジットカード不要です
- **$400 相当のクレジット** が付与されます (本ハンズオンの全セクションを実行しても十分な量です)
- ハンズオン終了後も継続利用可能です。不要なリソースは [`cleanup.sql`](../cleanup.sql) で削除してください
- 本番環境への接続やデータ移行には使用しないでください (トライアルアカウントは評価目的)

---

## 事前準備チェックリスト

- [ ] トライアルアカウントにログインできる
- [ ] `ACCOUNTADMIN` ロールが選択できる (左メニュー下部のロールセレクタ)
- [ ] Snowsight の左メニューで `Projects → Workspaces` が表示される
- [ ] ブラウザで日本語が正しく表示される
