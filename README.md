# kintone-photo-app-2025

杭打ち施工写真の管理を kintone と連携して行う Rails アプリです。

## 現在の前提

- 施工機マスタアプリ: `898`
- 写真・物件情報アプリ: `779`
- ゲストスペース: `57`
- Ruby: `3.3.6`
- Node.js: `20.x`

## Heroku デプロイ方針

このリポジトリは Heroku へ再デプロイできる前提で調整済みです。

- `Procfile` あり
- `app.json` あり
- `package.json` に Node バージョン固定あり
- `heroku-postbuild` で CSS ビルド実行
- `release` フェーズで `rails db:migrate` 実行
- production では Heroku dyno 上で静的アセット配信を有効化

## Heroku で必要な buildpack

順番が重要です。

1. `heroku/nodejs`
2. `heroku/ruby`

## Heroku で必要な主な環境変数

最低限、以下を設定してください。

- `RAILS_MASTER_KEY`
- `KINTONE_HOST`
- `KINTONE_API_TOKEN_898`
- `KINTONE_API_TOKEN_779`
- `APP_MACHINES=898`
- `APP_PHOTOS=779`
- `GUEST_SPACE=57`
- `APP_ACCOUNT_1`
- `APP_PASSWORD_1`

必要に応じて複数ログインを追加できます。

- `APP_ACCOUNT_2` / `APP_PASSWORD_2`
- `APP_ACCOUNT_3` / `APP_PASSWORD_3`
- `APP_ACCOUNT_4` / `APP_PASSWORD_4`
- `APP_ACCOUNT_5` / `APP_PASSWORD_5`

互換用に以下も使えます。

- `APP_MACHINE`
- `APP_PHOTO`
- `KINTONE_API_TOKEN`
- `APP_ACCOUNT`
- `APP_PASSWORD`
- `APP_ACCOUNTS`

## Heroku でのデプロイ手順

### 1. Heroku CLI をインストール

未インストールの場合は公式手順で導入してください。

### 2. ログイン

```bash
heroku login
```

### 3. Heroku アプリを作成

```bash
heroku create your-app-name
```

### 4. buildpack を設定

```bash
heroku buildpacks:clear -a your-app-name
heroku buildpacks:add heroku/nodejs -a your-app-name
heroku buildpacks:add heroku/ruby -a your-app-name
```

### 5. Postgres を追加

```bash
heroku addons:create heroku-postgresql:essential-0 -a your-app-name
```

### 6. 環境変数を設定

```bash
heroku config:set RAILS_MASTER_KEY=xxxxx -a your-app-name
heroku config:set KINTONE_HOST=aizawa-group.cybozu.com -a your-app-name
heroku config:set KINTONE_API_TOKEN_898=xxxxx -a your-app-name
heroku config:set KINTONE_API_TOKEN_779=xxxxx -a your-app-name
heroku config:set APP_MACHINES=898 -a your-app-name
heroku config:set APP_PHOTOS=779 -a your-app-name
heroku config:set GUEST_SPACE=57 -a your-app-name
heroku config:set APP_ACCOUNT_1=xxxxx -a your-app-name
heroku config:set APP_PASSWORD_1=xxxxx -a your-app-name
```

必要なら静的ファイル配信用に以下も入れて問題ありません。

```bash
heroku config:set RAILS_SERVE_STATIC_FILES=enabled -a your-app-name
```

### 7. デプロイ

```bash
git push heroku main
```

ブランチ名が `master` の場合は以下です。

```bash
git push heroku master
```

### 8. ログ確認

```bash
heroku logs --tail -a your-app-name
```

## デプロイ後の確認ポイント

1. `/sign_in` でログインできること
2. `/machines` で施工機一覧が表示されること
3. `/photos#machine-施工機名` から写真一覧へ遷移できること
4. `/photos/:id` で詳細画面が表示されること
5. 既存ファイル画像が `/files?key=...` 経由で見えること

## 現時点でできていること

- Render で発生していたログイン問題への対応
- 施工機マスタ `898` と写真アプリ `779` の分離
- 施工機一覧から写真一覧への遷移改善
- `/photos` 一覧画面の再構築
- `/photos/:id` 詳細画面の土台実装
- kintone ファイルダウンロード経路の復旧
- Heroku 向けビルド設定の追加

## まだ段階的に詰める部分

- 詳細画面での「追加」「編集」「撮影(変更)」の完全移植
- 旧 Heroku 版の React ベース編集UIの本格移植
- サブテーブル編集保存の再現

## 補足

- `former_source/` は比較用の旧ソース置き場であり、デプロイ対象には含めません。
- `node_modules/` は Git 管理対象外です。
- CSS ビルドは Heroku 上で自動実行されます。
