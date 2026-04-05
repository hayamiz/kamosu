# kamosu — LLM-Powered Knowledge Base Toolkit

kamosu（醸す）は、LLM を活用して研究知識ベースを構築・運用するためのツールキットです。論文・Web記事・コードスニペット等の生データを Claude Code が Markdown wiki に「醸成（コンパイル）」し、Obsidian で閲覧・探索できる形にします。

## 特徴

- **LLM がデータコンパイラ** — wiki 記事は LLM が生成・保守。人間は生データを投入するだけ
- **ツールとデータの分離** — ツールキットは Docker イメージとして配布、データは各自の Git リポジトリで管理
- **Obsidian ネイティブ** — `[[wikilink]]`・YAML frontmatter 対応、グラフビューやバックリンクがそのまま使える
- **段階的スケーリング** — 小規模はフラットインデックス、成長に応じて階層インデックス → 検索ツールへ拡張

## クイックスタート

### 1. 知識ベースの初期化

```bash
# インタラクティブ（認証モードを対話的に選択）
docker run --rm -it -v $(pwd):/output hayamiz/kamosu:latest kamosu-init my-topic

# または非インタラクティブ（認証モードを引数で指定）
docker run --rm -v $(pwd):/output hayamiz/kamosu:latest kamosu-init --claude-oauth my-topic
```

`kb-my-topic/` ディレクトリと `.env` が認証設定済みの状態で生成されます。

### 2. セットアップ

```bash
cd kb-my-topic

# CLAUDE.md を自分の研究テーマに合わせて編集
vim CLAUDE.md

# Git の初期化
git init
git remote add origin <your-remote-url>
git add -A && git commit -m "init: knowledge base"
git push -u origin main
```

### 3. データの投入とコンパイル

```bash
# raw/ に生データを配置
cp ~/Downloads/paper.pdf raw/papers/

# コンパイル実行（Claude Code が wiki 記事を生成）
docker compose run kb kamosu-compile
```

### 4. 閲覧

Obsidian で `kb-my-topic/` フォルダを Vault として開きます。`wiki/` 以下の記事がグラフビュー付きで閲覧できます。

## 生成されるデータリポジトリの構造

```
kb-my-topic/
├── CLAUDE.md                 # KB 固有の LLM 指示（ユーザーが編集）
├── docker-compose.yml
├── docker-compose.claude-auth.yml  # OAuth 認証用オーバーライド
├── .env / .env.example
├── .gitignore
├── .kb-toolkit-version
├── raw/                      # 生データ（ユーザーが投入）
│   ├── papers/
│   ├── web-clips/
│   └── repos/
├── wiki/                     # LLM が生成・保守（人間は編集しない）
│   ├── _master_index.md
│   ├── _category/
│   ├── _cross_references.md
│   └── concepts/
└── outputs/                  # Q&A 結果等
```

## コマンドリファレンス

### kamosu-init

新規知識ベースを初期化します。認証モードの選択も行います。

```bash
kamosu-init [OPTIONS] <kb-name>        # 新規作成
kamosu-init --reconfigure [OPTIONS]    # 認証の再設定
```

| オプション | 説明 |
|-----------|------|
| `--claude-oauth` | Claude OAuth モード（ホスト credential マウント） |
| `--claude-bedrock` | AWS Bedrock モード |
| `--aws-profile <name>` | AWS プロファイル名（`--claude-bedrock` と併用） |
| `--aws-region <region>` | AWS リージョン（`--claude-bedrock` 時は必須） |
| `--reconfigure` | 既存リポジトリの認証再設定 |

認証オプション未指定時はインタラクティブプロンプトで選択できます。

### kamosu-compile

`raw/` の新規・更新ファイルを wiki にコンパイルします。

```bash
kamosu-compile [OPTIONS]
```

| オプション | 説明 |
|-----------|------|
| `--force` | 全 raw ファイルを再コンパイル |
| `--dry-run` | 対象ファイル一覧の表示のみ（実行しない） |
| `--file <path>` | 特定ファイルのみコンパイル |

## 認証設定

kamosu は 3 つの認証モードをサポートします。`kamosu-init` 実行時にインタラクティブに選択するか、引数で指定します。後から `kamosu-init --reconfigure` で変更可能です。

### モード 1: Claude OAuth（デフォルト）

ホストマシンの Claude Code 認証情報をコンテナに引き継ぎます。

**前提条件**: ホストで `claude` コマンドを一度実行し、OAuth 認証を完了してください。

```bash
# 初期化時に選択
kamosu-init --claude-oauth my-topic
```

**仕組み**:
- ホストの `~/.claude/` を読み取り専用でコンテナにマウント
- エントリポイントスクリプトがコンテナ内 `$HOME/.claude/` にコピー
- コンテナ内の変更はホストに影響しない

### モード 2: AWS Bedrock（credentials/profile）

```bash
kamosu-init --claude-bedrock --aws-profile your-profile --aws-region us-east-1 my-topic
```

### モード 3: AWS Bedrock（EC2 IAM Role）

EC2 インスタンスの IAM Role を使用します。`--aws-profile` を省略します。

```bash
kamosu-init --claude-bedrock --aws-region us-east-1 my-topic
```

### 認証の変更

```bash
docker compose run kb kamosu-init --reconfigure
```

既存の `.env` はバックアップされ、新しい認証設定で上書きされます。

## 開発（ローカルビルドで使う）

Docker Hub にプッシュされたイメージを使わず、ローカルでビルドしたイメージで開発・テストする手順です。

### 1. イメージのビルド

```bash
cd kamosu/
docker build -t kamosu:local .
```

### 2. 知識ベースの初期化

```bash
docker run --rm -v $(pwd):/output kamosu:local kamosu-init my-topic
cd kb-my-topic
```

### 3. docker-compose.yml をローカルイメージに切り替え

生成された `docker-compose.yml` のイメージ名をローカルビルドに書き換えます:

```yaml
services:
  kb:
    image: kamosu:local   # ← ghcr.io/... から変更
```

または `.env` で上書き:

```bash
KB_TOOLKIT_VERSION=local
```

※ デフォルトのテンプレートは `hayamiz/kamosu:${KB_TOOLKIT_VERSION:-latest}` なので、`KB_TOOLKIT_VERSION` を設定しない場合はレジストリから pull しようとします。

### 4. 動作確認

```bash
cp .env.example .env
# .env を編集して認証設定

# コンテナに入る
docker compose run kb bash

# または直接コンパイル
docker compose run kb kamosu-compile --dry-run
```

### テスト（ツールキット開発者向け）

```bash
# スキャフォールディングの検証
docker run --rm -v $(pwd)/test-output:/output kamosu:local kamosu-init test-kb
ls test-output/kb-test-kb/

# エントリポイントの検証（OAuth credential のコピー）
docker run --rm \
  -v ~/.claude:/tmp/.claude-host:ro \
  kamosu:local bash -c 'ls -la ~/.claude/'
```

## ライセンス

TBD
