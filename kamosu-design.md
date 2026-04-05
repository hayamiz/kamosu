# kamosu — LLM-Powered Knowledge Base Toolkit

## Design Document v0.1.0

### 1. Overview

kamosu（醸す）は、LLM を活用して個人・チームの研究知識ベースを構築・運用するためのツールキットである。生データ（論文、Web記事、コードリポジトリ等）を LLM が Markdown wiki に「醸成（コンパイル）」し、Obsidian で閲覧・探索できる形にする。

#### 1.1 Design Philosophy

- **LLM がデータコンパイラ**: wiki の記事は LLM が生成・保守する。人間は直接編集しない。
- **ツールとデータの分離**: ツールキット（kamosu）と知識ベースデータは別リポジトリで管理する。ツールは Docker イメージとして配布し、データリポジトリは各ユーザーが自由な Git リモートで管理する。
- **段階的スケーリング**: 小規模ではフラットインデックスで運用し、成長に応じて階層インデックス → 検索ツールと段階的に拡張する。
- **Obsidian ネイティブ**: wiki は Obsidian の Vault としてそのまま開ける。`[[wikilink]]` 記法、YAML frontmatter を活用し、グラフビューやバックリンクの恩恵を受ける。

#### 1.2 Key Concepts

| 用語 | 説明 |
|------|------|
| raw data | ユーザーが投入する生データ（PDF、Webクリップ、コードスニペット等） |
| compile | raw data を wiki 記事に変換するプロセス。LLM が実行する。 |
| wiki | LLM が生成・保守する Markdown 記事群。Obsidian Vault として閲覧する。 |
| lint | wiki の健全性チェック。矛盾検出、欠損補完、接続提案を行う。 |
| toolkit repo | kamosu 本体（Dockerfile、スクリプト、テンプレート、検索ツール） |
| data repo | 知識ベースの実データ（raw/、wiki/、outputs/、CLAUDE.md） |

---

### 2. Architecture

#### 2.1 System Overview

```
┌─────────────────┐     ┌─────────────────┐
│  Client A        │     │  Client B        │
│  Obsidian        │     │  Obsidian        │
│  + Git plugin    │     │  + Git plugin    │
└────────┬─────────┘     └────────┬─────────┘
         │       git push/pull    │
         └───────────┬────────────┘
                     │
              ┌──────▼──────┐
              │  Git Remote  │
              │  (per user)  │
              └──────┬───────┘
                     │  git pull / push
              ┌──────▼──────┐
              │  EC2 / Local │
              │  Docker      │
              │  (kamosu)    │
              │  Claude Code │
              │  + Bedrock   │
              └──────────────┘
```

#### 2.2 Repository Structure

**Toolkit Repository (`kamosu`)**

```
kamosu/
├── Dockerfile
├── docker-compose.yml          # 開発・テスト用
├── VERSION                     # セマンティックバージョン
├── claude-base.md              # 全 KB 共通の LLM プロトコル
├── scripts/
│   ├── kamosu-init             # 新規データリポジトリの初期化
│   ├── kamosu-compile          # raw → wiki コンパイル
│   ├── kamosu-lint             # wiki 健全性チェック
│   ├── kamosu-search           # wiki 検索 CLI
│   └── kamosu-migrate          # ツールバージョンアップ時のマイグレーション
├── tools/
│   └── search-engine/          # 検索エンジン（Python）
│       ├── requirements.txt
│       ├── indexer.py           # wiki の全文インデックス構築
│       ├── searcher.py          # 検索 CLI 本体
│       └── server.py            # Web UI（オプション）
├── migrate/                    # バージョンごとのマイグレーションスクリプト
│   └── X.Y.Z.sh               # そのバージョンへ上げるためのスクリプト
├── templates/
│   ├── kb-claude.md.tmpl       # データ側 CLAUDE.md の雛形
│   ├── _master_index.md        # マスターインデックスの初期ファイル
│   ├── docker-compose.yml.tmpl # データリポジトリ用 compose テンプレート
│   ├── .gitignore.tmpl
│   └── .env.example
├── CHANGELOG.md                # リリースごとの変更記録
└── tests/                      # ツール自体のテスト
```

**Data Repository (per user/project, e.g. `kb-energy-db`)**

```
kb-energy-db/
├── .kb-toolkit-version         # 使用する kamosu バージョンのピン留め
├── CLAUDE.md                   # claude-base.md を継承 + KB 固有の指示
├── docker-compose.yml          # kamosu イメージ参照（薄い）
├── .env                        # AWS 認証情報等（.gitignore 対象）
├── .env.example
├── .gitignore
├── raw/                        # ユーザーが投入する生データ
│   ├── papers/                 # 論文 PDF
│   ├── web-clips/              # Obsidian Web Clipper 出力
│   └── repos/                  # コードスニペット・README 等
├── wiki/                       # LLM が生成・保守（人間は原則編集しない）
│   ├── _master_index.md        # カテゴリ一覧 + 1行要約
│   ├── _category/              # カテゴリ別インデックス
│   │   └── (auto-generated)
│   ├── _cross_references.md    # カテゴリ横断の関連性マップ
│   ├── concepts/               # 記事本体（LLM 管理）
│   │   └── (auto-generated)
│   └── my-drafts/              # ユーザーの手書きメモ・アイデア（LLM は読むが編集しない）
│       └── (user-created)
├── outputs/                    # Q&A 結果、スライド、可視化等
└── .last-compile-timestamp     # 最終コンパイル時刻
```

---

### 3. Core Components

#### 3.1 claude-base.md — Base LLM Protocol

全知識ベース共通の LLM 指示書。以下のセクションを含む。

**Wiki Structure Protocol**
- `_master_index.md` の形式と保守ルール
- `_category/*.md` の形式と保守ルール
- `_cross_references.md` の形式と保守ルール
- wiki 更新時に必ずインデックスを同期する義務

**Article Format**
- YAML frontmatter の必須フィールド: title, date_created, date_updated, sources (raw/ 内のパス), tags
- 記事構成: Summary（2-3文）→ Main Content → Related Articles（`[[wikilink]]`）→ Source References
- `[[wikilink]]` 記法による相互参照の規約

**Compilation Protocol**
1. `.ingest-queue` または指定ファイルを読む
2. raw データの内容を理解する
3. 既存の `_master_index.md` を読み、関連するカテゴリインデックスと記事を特定する
4. 新規記事の作成 or 既存記事の更新を行う
5. 関連記事からのバックリンクを追加する
6. `_master_index.md`、影響を受けた `_category/*.md`、`_cross_references.md` を更新する

**Query Protocol**
1. `_master_index.md` を読む（カテゴリレベルの概観）
2. 関連カテゴリの `_category/*.md` を読む（記事レベルの要約）
3. 必要な記事本体を読む
4. 回答を生成し、wiki 記事への参照を含める

**Lint Protocol**
- 孤立記事（どこからもリンクされていない）の検出
- 矛盾する記述の検出
- 引用元（raw/ 内のソース）の欠落検出
- カテゴリ横断の新たな接続の提案
- インデックスと実際の記事群の整合性チェック

#### 3.2 CLAUDE.md（データリポジトリ側）

テンプレートから生成され、ユーザーが自分の研究ドメインに合わせて編集する。

```markdown
# Knowledge Base: [TOPIC_NAME]

> Base protocol: /opt/kamosu/claude-base.md を必ず先に読み、従うこと。
> 以下はこの知識ベース固有の指示。

## Domain Context
[この KB が扱う研究領域の説明]
[主要な研究テーマのリスト]

## Category Structure
[このKBのカテゴリ定義。compile 時に LLM が記事を分類する基準となる]
- category-a: [説明]
- category-b: [説明]

## Terminology
[ドメイン固有の用語定義。LLM が記事生成時に正確な用語を使うための辞書]
- TERM1: [定義]

## Special Instructions
[その他 KB 固有の指示。例: 特定のフォーマット要件、重視する観点等]
```

#### 3.3 Scripts

##### kamosu-init

新規データリポジトリを初期化するスクリプト。Docker コンテナ内で実行され、出力先ディレクトリにスキャフォールディングを生成する。認証モードの選択もこのスクリプトで行う。

**使い方**:
```bash
kamosu-init [OPTIONS] <kb-name>        # 新規作成
kamosu-init --reconfigure [OPTIONS]    # 既存リポジトリの認証再設定
```

**認証オプション**:

| オプション | 説明 |
|-----------|------|
| `--claude-oauth` | Claude OAuth モード（ホスト credential マウント） |
| `--claude-bedrock` | AWS Bedrock モード |
| `--aws-profile <name>` | AWS プロファイル名（`--claude-bedrock` と併用、省略時は EC2 IAM Role） |
| `--aws-region <region>` | AWS リージョン（`--claude-bedrock` 時は必須） |
| `--reconfigure` | 既存データリポジトリの認証設定を再構成 |

認証オプション未指定時はインタラクティブプロンプトを表示する。stdin が tty でない場合はデフォルト（OAuth）にフォールバックする。

**認証モード（3種）**:

| モード | COMPOSE_FILE | 追加設定 |
|--------|-------------|---------|
| Claude OAuth | `docker-compose.yml:docker-compose.claude-auth.yml` | なし |
| Bedrock (profile) | `docker-compose.yml` | AWS_PROFILE, AWS_REGION |
| Bedrock (EC2 IAM Role) | `docker-compose.yml` | AWS_REGION のみ |

**処理フロー（新規作成）**:
1. 引数パース・バリデーション
2. 認証モード決定（引数指定 or インタラクティブプロンプト）
3. ディレクトリ構造の作成（raw/, wiki/, wiki/my-drafts/, outputs/ とサブディレクトリ）
4. テンプレートからのファイル生成（CLAUDE.md, docker-compose.yml, .gitignore, .env.example）
5. `.env` を認証モードに応じて直接生成
6. wiki/ 初期ファイルの配置（_master_index.md, _category/, _log.md）
7. `.kb-toolkit-version` にイメージバージョンを記録

**処理フロー（--reconfigure）**:
1. データリポジトリの検出（`/workspace` or カレントディレクトリ）
2. 既存 `.env` のバックアップ（`.env.backup.YYYYMMDD-HHMMSS`）
3. 認証モード決定 → `.env` を再生成

Git 初期化は行わない（ユーザーが自分のリモートを設定するため）。

##### kamosu-shell

Claude Code のインタラクティブセッションを起動する薄いラッパースクリプト。引数はすべて `claude` コマンドにパススルーする。

**使い方**:
```bash
# インタラクティブセッション
docker compose run kb kamosu-shell

# ワンショット
docker compose run kb kamosu-shell -p "NVMe のアイドル時電力についてまとめて"

# claude オプションのパススルー
docker compose run kb kamosu-shell --model claude-sonnet-4-20250514
```

**処理**:
1. `/workspace` がデータリポジトリか検証（`.kb-toolkit-version` の存在チェック）
2. `exec claude "$@"`

**将来の拡張ポイント**:
- `ANTHROPIC_MODEL` 環境変数からの `--model` 自動付与
- `--allowedTools` のデフォルト設定（kamosu-search 等の許可）
- セッション開始時のヘルプメッセージ表示

##### kamosu-compile

raw/ の新規・更新ファイルを wiki にコンパイルする。

**処理フロー**:
1. Git pull（リモートがある場合）
2. `.last-compile-timestamp` 以降に更新されたファイルを `raw/` から検出
3. 検出ファイルリストを `.ingest-queue` に書き出す
4. 新規ファイルがなければ終了
5. Claude Code を呼び出し、コンパイルを実行（claude-base.md のプロトコルに従う）
6. `.last-compile-timestamp` を更新
7. 変更を git commit
8. Git push（リモートがある場合）

**オプション**:
- `--force`: 全 raw ファイルを再コンパイル
- `--dry-run`: 対象ファイル一覧の表示のみ
- `--file <path>`: 特定ファイルのみコンパイル

##### kamosu-lint

wiki の健全性チェックを実行する。

**処理フロー**:
1. Claude Code を呼び出し、lint プロトコルに従って wiki を検査
2. 結果を `outputs/lint-report-<date>.md` に出力
3. 自動修正可能な項目（インデックスの不整合等）はオプションで自動修正

**オプション**:
- `--fix`: 自動修正可能な問題を修正
- `--check-only`: レポート生成のみ（デフォルト）

##### kamosu-search

wiki の全文検索 CLI。LLM が Q&A 時にツールとして使用することも想定。

**処理フロー**:
1. wiki/ 以下の全 .md ファイルのインデックスを構築（キャッシュあり）
2. クエリに基づいて関連記事をランキング
3. 上位 N 件の記事パスとスニペットを出力

**オプション**:
- `--top <N>`: 表示件数（デフォルト: 5）
- `--rebuild-index`: インデックスの強制再構築
- `--json`: JSON 出力（LLM ツール連携用）

**初期実装**: TF-IDF ベース。将来的に sentence-transformers によるセマンティック検索に拡張可能。

##### kamosu-migrate

ツールバージョンアップ時にデータリポジトリ側の構造をマイグレーションする。`migrate/` ディレクトリ内のスクリプトをチェーン適用する。

**使い方**:
```bash
docker compose run kb kamosu-migrate            # イメージバージョンまで自動適用
docker compose run kb kamosu-migrate --dry-run   # 実行予定の一覧を表示
docker compose run kb kamosu-migrate --to 0.3.0  # 特定バージョンまで適用
docker compose run kb kamosu-migrate --force      # ダーティ状態でも強制実行
```

**処理フロー**:
1. Git ダーティチェック: ワーキングツリーに未コミットの変更がある場合はエラー終了（`--force` で無視）
2. `.kb-toolkit-version` から現在のデータバージョンを読む
3. ターゲットバージョンを決定（デフォルト: イメージの `KB_TOOLKIT_VERSION`、`--to` で上書き可）
4. `migrate/` から 現在 < バージョン ≤ ターゲット のスクリプトを昇順で列挙
5. 各スクリプトを順番に実行（スクリプトがないバージョンはスキップ）
6. `.kb-toolkit-version` をターゲットバージョンに更新
7. 変更を git commit（`--force` でダーティチェックをスキップした場合はコミットしない）

**マイグレーションスクリプトの規約** (`migrate/X.Y.Z.sh`):
- ファイル名はターゲットバージョン（例: `0.2.0.sh` = 「0.2.0 に上げるための処理」）
- 冪等であること（何回実行しても同じ結果）
- `set -euo pipefail` で始める
- 先頭コメントに何をするか・なぜ必要かを記述
- マイグレーション不要なバージョンにはスクリプトを作らない

---

### 4. Docker Image

#### 4.1 Dockerfile Design

- ベースイメージ: `ubuntu:24.04`
- 含めるもの: git, curl, jq, Node.js, npm, Python3, pip, Claude Code CLI
- kamosu のスクリプト群: `/opt/kamosu/scripts/` にインストール、PATH に追加
- 検索ツール: `/opt/kamosu/tools/` にインストール、依存関係を pip install
- claude-base.md: `/opt/kamosu/claude-base.md` に配置
- テンプレート: `/opt/kamosu/templates/` に配置
- 環境変数: `KB_TOOLKIT_VERSION` を VERSION ファイルから設定

#### 4.2 Image Distribution

- レジストリ: `ghcr.io/goda-lab/kamosu:<version>`
- タグ規約: セマンティックバージョニング（e.g., `0.1.0`, `0.2.0`）+ `latest`
- CI/CD: toolkit repo への tag push で GitHub Actions が自動ビルド・プッシュ

#### 4.3 Data Repository側の docker-compose.yml

```yaml
services:
  kb:
    image: ghcr.io/goda-lab/kamosu:${KB_TOOLKIT_VERSION:-latest}
    volumes:
      - .:/workspace
    env_file:
      - .env
    working_dir: /workspace
    stdin_open: true
    tty: true
```

---

### 5. Wiki Structure & Index Design

#### 5.1 Hierarchical Index

LLM のコンテキストウィンドウ制約に対処するため、二段階インデックスを採用する。

**_master_index.md** — 全カテゴリの一覧と1行要約。LLM が最初に読む。

```markdown
# Master Index

Last updated: 2026-04-05

## Categories

| Category | Articles | Summary |
|----------|----------|---------|
| [query-execution](_category/query-execution.md) | 12 | クエリ実行エンジンの省電力手法 |
| [measurement](_category/measurement.md) | 8 | 電力測定手法とツール |
| ... | ... | ... |

## Statistics
- Total articles: 45
- Total categories: 6
- Last compiled: 2026-04-05T10:30:00+09:00
```

**_category/*.md** — カテゴリ別の記事一覧と2-3行要約。

```markdown
# Category: Query Execution

## Articles

### [oode-model](../concepts/oode-model.md)
Out-of-Order Dynamic Execution モデルの概要。タスク単位の細粒度スケジューリングに
よりCPUパイプラインの利用効率を最大化する。anagodb の中核アーキテクチャ。

### [prepare-getnext-protocol](../concepts/prepare-getnext-protocol.md)
Iterator モデルを拡張し、Prepare フェーズでエネルギーコストを事前推定する手法。
...
```

**_cross_references.md** — カテゴリ横断の関連性マップ。

```markdown
# Cross References

## query-execution ↔ measurement
- OoODE のタスクスケジューリング効率は RAPL 測定で定量評価可能
- See: [[oode-model]] → [[rapl-measurement]]

## query-execution ↔ hardware
- P-core/E-core の使い分けは OoODE のタスク割り当てに直結
- See: [[oode-model]] → [[pcore-ecore-characteristics]]
```

#### 5.2 Article Format

```markdown
---
title: "Out-of-Order Dynamic Execution Model"
date_created: 2026-04-01
date_updated: 2026-04-05
sources:
  - raw/papers/oode-original-paper.pdf
  - raw/repos/anagodb-scheduler-readme.md
tags: [query-execution, scheduling, anagodb]
category: query-execution
---

# Out-of-Order Dynamic Execution Model

## Summary
[2-3文の要約]

## Main Content
[詳細な記述。他の記事への [[wikilink]] を含む]

## Related Articles
- [[prepare-getnext-protocol]] — Iterator モデルの拡張
- [[pcore-ecore-characteristics]] — ハードウェアレベルの最適化

## Sources
- [原著論文](../raw/papers/oode-original-paper.pdf)
```

#### 5.3 my-drafts/ — ユーザー手書き領域

ユーザーがアイデア・仮説・ブレストメモを自由に書くための領域。Obsidian 上で concepts/ と同じ Vault 内にあるため、`[[wikilink]]` で記事と相互にリンクできる。

**所在**: `wiki/my-drafts/`

**ルール**:
- ユーザーが自由に作成・編集・削除する。LLM は読むが、作成・編集・削除しない
- compile 時、`my-drafts/` 内のファイルもソースとして認識する。concepts 記事に統合する場合は `sources:` に `my-drafts/xxx.md` を記録する
- lint 時、`my-drafts/` は孤立チェックの対象外とする
- `_master_index.md` の Statistics には my-drafts のカウントを含めない

**フォーマット**（推奨、強制しない）:

```markdown
---
title: "NVMe スケジューリングのアイデア"
date: 2026-04-05
status: idea | draft | to-compile
---

# NVMe スケジューリングのアイデア

自由に記述。[[existing-concept]] へのリンクも可。
```

`status: to-compile` にすることで、次回 compile 時に LLM がソースとして拾い concepts 記事に醸成する。元の draft はユーザーが残すか消すか判断する。

#### 5.4 Scale Thresholds

| 規模 | 記事数 | アクセス戦略 |
|------|--------|-------------|
| Small | ~100 | _master_index.md のみで十分 |
| Medium | 100-500 | 二段インデックス（master + category） |
| Large | 500-1000 | 二段インデックス + kamosu-search CLI |
| XLarge | 1000+ | セマンティック検索 or RAG パイプライン検討 |

---

### 6. User Workflows

#### 6.1 Initial Setup (New User)

```bash
# 1. Docker image から KB を初期化
docker run --rm -v $(pwd):/output ghcr.io/goda-lab/kamosu:latest \
  kamosu-init my-research-topic

# 2. Git 初期化 & リモート設定
cd kb-my-research-topic
git init
git remote add origin <user's git remote URL>

# 3. CLAUDE.md を自分の研究テーマに合わせて編集
vim CLAUDE.md

# 4. AWS 認証情報の設定
cp .env.example .env
vim .env  # AWS_PROFILE, AWS_REGION 等を設定

# 5. 初回コミット & プッシュ
git add -A && git commit -m "init: knowledge base"
git push -u origin main
```

#### 6.2 Data Ingestion (Compile)

```bash
# raw/ に新しいデータを投入
cp ~/Downloads/new-paper.pdf raw/papers/
# or: Obsidian Web Clipper で raw/web-clips/ に保存

# コンパイル実行
docker compose run kb kamosu-compile

# 結果を Obsidian で確認（自動 pull されるか、手動 pull）
```

#### 6.3 Q&A

```bash
# コンテナに入ってインタラクティブに質問
docker compose run kb
claude -p "NVMe のアイドル時電力消費とクエリスケジューリングの関係について、
          wiki の知識を基にまとめてください。結果は outputs/ に保存してください。"
```

#### 6.4 Lint

```bash
docker compose run kb kamosu-lint
# レポートが outputs/lint-report-<date>.md に生成される
# 自動修正する場合:
docker compose run kb kamosu-lint --fix
```

#### 6.5 Toolkit Update

```bash
# .kb-toolkit-version を更新
echo "0.2.0" > .kb-toolkit-version
export KB_TOOLKIT_VERSION=0.2.0
docker compose pull

# マイグレーションが必要な場合
docker compose run kb kamosu-migrate 0.2.0
```

#### 6.6 Multi-Device Sync (with Obsidian)

- Obsidian Git プラグインで auto-pull / auto-push を設定（推奨間隔: 5分）
- wiki/ は LLM の領域なので、Obsidian 側は pull 優先（force pull）
- raw/ への投入は人間が行い、compile はコンテナ内で実行

---

### 7. Bedrock / Claude Code Integration

#### 7.1 Authentication

- EC2 上: IAM Role（推奨、profile 名 `as110-haya`）
- ローカル: `.env` に `AWS_PROFILE` を設定

#### 7.2 Model Selection

- Compile / Q&A: Claude Sonnet 4 以上（品質重視）
- Lint（軽量チェック）: Haiku でも可（将来的にモデル切替対応時）
- デフォルト: `ANTHROPIC_MODEL` 環境変数で指定

#### 7.3 Cost Management

- 研究室展開時は IAM ポリシーでメンバーごとの Bedrock 利用上限を設定可能
- compile は差分のみ処理するため、増分コストは投入データ量に比例

---

### 8. Version Management & Migration

#### 8.1 Versioning

- Toolkit: セマンティックバージョニング（MAJOR.MINOR.PATCH）
- Docker Image: バージョンタグ + `latest`
- Data Repo: `.kb-toolkit-version` でピン留め

#### 8.2 Semantic Versioning Rules

| バンプ | 条件 | マイグレーション |
|--------|------|-----------------|
| PATCH (0.1.x) | バグ修正、ドキュメント修正 | 不要 |
| MINOR (0.x.0) | 機能追加、非破壊的なデータ構造変更 | あれば `migrate/` にスクリプト追加 |
| MAJOR (x.0.0) | 破壊的変更（既存 wiki の再コンパイルが必要等） | 必須。CHANGELOG に移行手順を詳述 |

#### 8.3 Migration Infrastructure

**CHANGELOG.md** — リリース単位の変更記録。[Keep a Changelog](https://keepachangelog.com/) フォーマット準拠。各バージョンに `Migration Required` セクションを設け、マイグレーションの要否と内容を明記する。

**migrate/ ディレクトリ** — バージョンごとのマイグレーションスクリプト。`kamosu-migrate` がチェーン適用する。詳細は Section 3.3 kamosu-migrate を参照。

#### 8.4 Version Compatibility Check

スクリプト起動時（entrypoint.sh または各スクリプトの冒頭）で `.kb-toolkit-version` と Docker イメージのバージョンを比較する。

| 状態 | 動作 |
|------|------|
| 一致 | 正常起動 |
| データ < イメージ | 警告:「`kamosu-migrate` を実行してください」 |
| データ > イメージ | エラー:「イメージが古いです。イメージを更新してください」 |
| `.kb-toolkit-version` がない | エラー:「kamosu データリポジトリではありません」 |

#### 8.5 Migration Safety

- **Git ダーティチェック**: `kamosu-migrate` はデータリポジトリに未コミットの変更がある場合、実行を拒否する。マイグレーション前に必ずクリーンな状態にさせることで、問題発生時に `git revert` で復元可能にする
- **`--force`**: ダーティ状態でも強制マイグレーションを実行する。この場合 git commit は行わない（ユーザーが手動でコミットする想定）
- **冪等性**: 各マイグレーションスクリプトは冪等であること。途中失敗時に再実行しても安全
- **ドライラン**: `kamosu-migrate --dry-run` で実行予定のマイグレーション一覧を確認可能

---

### 9. Implementation Phases

> タスクの進捗管理は `TASKS.md` で行う。ここではフェーズの目的と含まれる機能を定義する。

#### Phase 1: Core (MVP)
Dockerfile、claude-base.md、kamosu-init、kamosu-compile、テンプレート群。最小限の動作可能なツールキットを構築する。

#### Phase 2: Quality & Search
kamosu-lint、kamosu-search（TF-IDF）、kamosu-migrate、GitHub Actions CI/CD。wiki の品質管理と検索機能を追加する。

#### Phase 3: Lab Deployment
セマンティック検索、Web UI、Bedrock コスト管理用 IAM ポリシーテンプレート、運用ドキュメント。研究室メンバーが自律的に使える状態にする。

#### Future (未定)
- Query 結果の wiki 還元 — Q&A の回答を wiki ページとして保存し、知識を蓄積する仕組み（ref: Karpathy LLM Wiki の "good answers can be filed back into the wiki"）
- 画像ハンドリング — raw/assets/ への画像ローカル保存と LLM からの参照（ref: Karpathy LLM Wiki の画像ダウンロード手法）
