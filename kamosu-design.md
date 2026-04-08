# kamosu — LLM-Powered Knowledge Base Toolkit

## Design Document v0.2.0

### 1. Overview

kamosu（醸す）は、LLM を活用して個人・チームの研究知識ベースを構築・運用するためのツールキットである。生データ（論文、Web記事、コードリポジトリ等）を LLM が Markdown wiki に「醸成（コンパイル）」し、Obsidian で閲覧・探索できる形にする。

#### 1.1 Design Philosophy

- **LLM がデータコンパイラ**: wiki の記事は LLM が生成・保守する。人間は直接編集しない。
- **ツールとデータの分離**: ツールキット（kamosu）と知識ベースデータは別リポジトリで管理する。ツールは Docker イメージとして配布し、データリポジトリは各ユーザーが自由な Git リモートで管理する。
- **ホストオーケストレーション・Docker最小化**: Git 操作・ファイル検出・タイムスタンプ管理などのオーケストレーションはホスト側 CLI で行い、Docker はLLM（Claude Code）と検索エンジン（Python）の実行のみに使用する。これにより Git 認証問題を回避し、ホストの既存ツールチェーンをそのまま活用できる。
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
                     │  git pull / push (native host git)
              ┌──────▼──────────────────────────────┐
              │  EC2 / Local Host                    │
              │  ┌────────────────────────────────┐  │
              │  │ kamosu CLI (host)              │  │
              │  │  git, file detect, queue, etc. │  │
              │  └──────────┬─────────────────────┘  │
              │             │ docker run              │
              │  ┌──────────▼─────────────────────┐  │
              │  │ Docker Container               │  │
              │  │  claude (LLM)                  │  │
              │  │  python3 (search engine)       │  │
              │  └────────────────────────────────┘  │
              └──────────────────────────────────────┘
```

**Hybrid Architecture**: The host CLI (`cli/kamosu`) handles all orchestration — git operations, file detection, queue management, timestamp updates. Docker containers are invoked only for LLM (Claude Code CLI) and search engine (Python) execution. This eliminates the need to forward Git credentials into containers.

#### 2.2 Repository Structure

**Toolkit Repository (`kamosu`)**

```
kamosu/
├── Dockerfile
├── docker-compose.yml          # 開発・テスト用
├── VERSION                     # セマンティックバージョン
├── claude-base.md              # 全 KB 共通の LLM プロトコル
├── cli/
│   └── kamosu                  # ホスト側 CLI（オーケストレーション本体）
├── scripts/
│   ├── kamosu-init             # 新規データリポジトリの初期化（Docker 内実行）
│   └── entrypoint.sh           # コンテナ起動時の認証・権限設定
├── prompts/                    # LLM に渡すプロンプトテンプレート
│   ├── compile.txt             # compile 用プロンプト
│   ├── lint.txt                # lint 用プロンプト
│   ├── lint-fix.txt            # lint --fix 用プロンプト
│   └── promote.txt             # promote 用プロンプト
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
│   # docker-compose.yml はテンプレートではなく kamosu-init が認証モード別に直接生成
│   ├── .gitignore.tmpl
│   └── .kamosu-config.example
├── CHANGELOG.md                # リリースごとの変更記録
└── tests/                      # ツール自体のテスト
```

**Data Repository (per user/project, e.g. `energy-db`)**

```
energy-db/
├── .kamosu-version         # 使用する kamosu バージョンのピン留め
├── CLAUDE.md                   # claude-base.md を継承 + KB 固有の指示
├── docker-compose.yml          # 認証モード別に kamosu init が生成
├── .kamosu-config              # 認証モード・AWS設定等（.gitignore 対象）
├── .kamosu-config.example
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

**Promote Protocol**
1. `outputs/` 内の指定ファイルを読み、内容を理解する
2. 既存 wiki を参照し、統合先を判断（既存記事への統合 or 新規記事作成）
3. Compilation Protocol の Step 4-6 と同じ手順で記事を作成・更新する
4. `sources:` に元の outputs ファイルパスを記録する
5. `_log.md` に promote エントリを追記する

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

#### 3.3 Docker Contract

Docker コンテナは以下の目的でのみ使用する。オーケストレーション（Git 操作、ファイル検出、キュー管理等）はすべてホスト側 CLI が担当する。

| 目的 | コマンド | Docker が必要な理由 |
|------|---------|-------------------|
| LLM コンパイル/lint/promote | `claude -p "..." --allowedTools "..."` | Claude Code CLI + Node.js |
| LLM インタラクティブセッション | `claude [args...]` | Claude Code CLI |
| wiki 検索 | `python3 searcher.py [args...]` | Python + TF-IDF ライブラリ |
| マイグレーションスクリプト | `bash /opt/kamosu/migrate/X.Y.Z.sh` | イメージ固有のツールが必要な場合 |
| データリポジトリ初期化 | `kamosu-init [args...]` | テンプレートとバージョン情報がイメージ内にある |

#### 3.4 Prompts

LLM に渡すプロンプトはDocker イメージ内の `/opt/kamosu/prompts/` にテキストファイルとして配置する。ホスト CLI はプロンプトを埋め込まず、Docker 経由で読み取る。

**配置ファイル**:
- `prompts/compile.txt` — compile 用プロンプト
- `prompts/lint.txt` — lint (check-only) 用プロンプト
- `prompts/lint-fix.txt` — lint --fix 用プロンプト
- `prompts/promote.txt` — promote 用プロンプト
- `prompts/promote-dry-run.txt` — promote --dry-run 用プロンプト

**Design Rationale**: プロンプトを Docker イメージに配置することで、プロンプトの更新と CLI の更新を分離する。CLIはプロンプトの内容を知る必要がなく、イメージバージョンの更新だけでプロンプト改善が反映される。

#### 3.5 Stream Monitor (`tools/stream-monitor.py`)

Claude Code の `--output-format stream-json --verbose` 出力をリアルタイムで処理し、進捗表示・ログ保存・結果検証を行う Python スクリプト。Docker イメージ内に配置し、`claude` コマンドの出力をパイプで受け取る。

**パイプライン**:

```
compose_run kb bash -c 'set -o pipefail; \
  claude -p "$(cat /workspace/.kamosu-prompt-tmp)" \
    --output-format stream-json --verbose --allowedTools "..." \
  | python3 /opt/kamosu/tools/stream-monitor.py \
    --log /workspace/.kamosu/logs/stream-XXXXXX.jsonl'
```

プロンプトは一時ファイル (`/workspace/.kamosu-prompt-tmp`) に書き出して `cat` で読み取る。`bash -c` 内でのエスケープ問題を回避するため。`set -o pipefail` により `claude` 側の失敗がパイプライン全体に伝播する。

**機能**:

| 出力先 | 内容 |
|--------|------|
| stderr | スピナー + フェーズ表示（TTY 時のみ） |
| ファイル | `.kamosu/logs/stream-*.jsonl`（生の JSONL 全イベント） |
| stdout | 人間可読なサマリー（成功時: 記事数・コスト・所要時間、失敗時: 原因・ログパス） |
| exit code | 0（成功）or 1（失敗） |

**フェーズ表示**: ファイル単位ではなく、ツール使用パターンからフェーズを推定して表示する。

```
⠋ Reading source files...       (Read on raw/ or PDF)
⠙ Analyzing existing wiki...    (Read/Grep/Glob on wiki/)
⠹ Writing articles...           (Write/Edit on wiki/concepts/)
⠸ Updating indexes...           (Edit on _master_index.md 等)
⠼ Thinking...                   (text のみ、tool_use なし)
⠴ Rate limited, retrying...     (rate_limit_event)
✓ Done (45s, $0.34)             (result: success)
✗ Failed: budget exceeded        (result: error)
```

**結果検証**: `result` イベントの `subtype`, `is_error`, `permission_denials` を検査。成功条件: `subtype == "success"` かつ `is_error == false` かつ `permission_denials` が空。

**テスト**: `--json-summary` フラグでサマリーを JSON 出力し、`jq` で正確なアサーション。フィクスチャファイル（`tests/fixtures/stream-*.jsonl`）を使用し、実際の Claude 呼び出しなしでテスト。

#### 3.6 Host CLI Commands

以下は `cli/kamosu` で実装されるサブコマンドの仕様。各コマンドのオーケストレーション（Git、ファイル操作）はホスト側で実行し、LLM 呼び出しのみ Docker に委譲する（stream-monitor.py 経由でストリーミング処理）。

##### kamosu init

新規データリポジトリを初期化する。Docker コンテナ内の `kamosu-init` スクリプトを呼び出す。

**使い方**:
```bash
kamosu init [OPTIONS] <kb-name>        # 新規作成
kamosu init --reconfigure [OPTIONS]    # 既存リポジトリの認証再設定
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

`kamosu init` は認証モードに応じた `docker-compose.yml` を直接生成する（テンプレートファイルは使用しない）。

| モード | docker-compose.yml の差分 | .kamosu-config の内容 |
|--------|--------------------------|---------------------|
| Claude OAuth | `~/.claude`, `~/.claude.json` をマウント | `ANTHROPIC_MODEL=` のみ |
| Bedrock (profile) | `~/.aws` をマウント | `AWS_PROFILE`, `AWS_REGION`, `ANTHROPIC_MODEL` |
| Bedrock (EC2 IAM Role) | `~/.aws` をマウント | `AWS_REGION`, `ANTHROPIC_MODEL` |

**処理フロー（新規作成）** — Docker 内の `kamosu-init` で実行:
1. 引数パース・バリデーション
2. 認証モード決定（引数指定 or インタラクティブプロンプト）
3. ディレクトリ構造の作成（raw/, wiki/, wiki/my-drafts/, outputs/ とサブディレクトリ）
4. テンプレートからのファイル生成（CLAUDE.md, .gitignore, .kamosu-config.example）+ 認証モード別 docker-compose.yml 生成
5. `.kamosu-config` を認証モードに応じて直接生成
6. wiki/ 初期ファイルの配置（_master_index.md, _category/, _log.md）
7. `.kamosu-version` にイメージバージョンを記録

Git 初期化は行わない（ユーザーが自分のリモートを設定するため）。

##### kamosu compile

raw/ の新規・更新ファイルを wiki にコンパイルする。

**処理フロー** — ホスト側とDocker側の役割分担:
1. `git pull --rebase` — **ホスト**（ネイティブ Git 認証を使用）
2. `.ingest-queue` 残存チェック — **ホスト**（前回の中断検出。存在時は `--resume` / `--clean` を提案）
3. `.last-compile-timestamp` 以降に更新されたファイルを `raw/` から検出 — **ホスト**（bash `find`）
4. 検出ファイルリストを `.ingest-queue` に書き出す — **ホスト**
5. 新規ファイルがなければ終了 — **ホスト**
6. Claude Code を呼び出し、コンパイルを実行 — **Docker**（`claude -p` + `/opt/kamosu/prompts/compile.txt`）
7. Claude の exit code を検証。失敗時は `.ingest-queue` を残してエラー終了 — **ホスト**
8. `.last-compile-timestamp` を更新 — **ホスト**
9. `.ingest-queue` を削除 — **ホスト**
10. `git add wiki/ .last-compile-timestamp && git commit && git push` — **ホスト**

**オプション**:
- `--force`: 全 raw ファイルを再コンパイル
- `--dry-run`: 対象ファイル一覧の表示のみ（Docker 不要）
- `--file <path>`: 特定ファイルのみコンパイル
- `--resume`: 前回中断時の `.ingest-queue` を再利用してコンパイル再開
- `--clean`: 前回中断時の `.ingest-queue` を削除してやり直し

**クラッシュリカバリ**: Claude が失敗した場合、`.ingest-queue` はディスク上に残るが `.last-compile-timestamp` は更新されない。次回 `kamosu compile` 実行時に `.ingest-queue` の存在を検出し、`--resume` or `--clean` を提案する。

##### kamosu lint

wiki の健全性チェックを実行する。

**処理フロー**:
1. `outputs/` ディレクトリ作成 — **ホスト**
2. Claude Code を呼び出し、lint プロトコルに従って wiki を検査 — **Docker**
3. Claude の exit code を検証 — **ホスト**
4. `--fix` 時かつ変更がある場合: `git add wiki/ && git commit` — **ホスト**

**オプション**:
- `--fix`: 自動修正可能な問題を修正
- `--check-only`: レポート生成のみ（デフォルト）

##### kamosu promote

Q&A の結果（`outputs/` 内のファイル）を wiki 記事として統合する。Query で得られた知見を wiki に蓄積し、知識を複利的に成長させるための仕組み。

**Design Rationale**:
- Q&A の回答には、複数記事を横断した比較分析や新たな接続の発見が含まれることがある
- これらは chat history に埋もれるべきではなく、wiki に還元すべき（ref: Karpathy LLM Wiki）
- Human-gated: ユーザーが「良い回答」を明示的に選んで promote する。自動ファイリングは wiki 品質を損なうリスクがあるため採用しない

**使い方**:
```bash
kamosu promote outputs/analysis-2026-04-06.md       # 特定ファイルを promote
kamosu promote outputs/comparison-*.md               # glob 指定
kamosu promote --dry-run outputs/analysis.md         # 統合プランの表示のみ
kamosu promote --list                                 # promote 候補の一覧
```

**処理フロー**:
1. ファイルの存在チェック — **ホスト**
2. `--list` 時: `.promote-history` を参照して未 promote ファイルを表示 — **ホスト**（Docker 不要）
3. `--dry-run` 時: Claude Code で統合プランのみ生成 — **Docker**
4. 通常実行: Claude Code で Promote Protocol に従い処理 — **Docker**
5. Claude の exit code を検証 — **ホスト**
6. `.promote-history` に記録 — **ホスト**
7. `git add wiki/ .promote-history && git commit && git push` — **ホスト**

**オプション**:
- `--dry-run`: 統合プランの表示のみ（実際の変更なし）
- `--list`: `outputs/` 内のまだ promote されていないファイル一覧を表示
- `--file <path>`: 対象ファイルの指定（`outputs/` 外のファイルも指定可能）

**promote 済み追跡**:
- promote 実行時、対象ファイルのパスを `.promote-history` に記録する（1行1パス、タイムスタンプ付き）
- `--list` は `.promote-history` に記録されていない `outputs/*.md` を表示する
- 元ファイルは削除しない（ユーザーが判断する）

##### kamosu shell

Claude Code のインタラクティブセッションを Docker 経由で起動する。引数はすべて `claude` コマンドにパススルーする。

**使い方**:
```bash
kamosu shell                                           # インタラクティブセッション
kamosu shell -p "NVMe のアイドル時電力についてまとめて"   # ワンショット
kamosu shell --model claude-sonnet-4-20250514           # モデル指定
```

**処理フロー**:
1. `compose_run kb claude "$@"` — **Docker**

##### kamosu search

wiki の全文検索 CLI。LLM が Q&A 時にツールとして使用することも想定。Docker 内の Python 検索エンジンを呼び出す。

**処理フロー**:
1. `compose_run kb python3 /opt/kamosu/tools/search-engine/searcher.py [args...]` — **Docker**

**オプション**:
- `--top <N>`: 表示件数（デフォルト: 5）
- `--rebuild-index`: インデックスの強制再構築
- `--json`: JSON 出力（LLM ツール連携用）

**初期実装**: TF-IDF ベース。将来的に sentence-transformers によるセマンティック検索に拡張可能。

##### kamosu migrate

ツールバージョンアップ時にデータリポジトリ側の構造をマイグレーションする。

**使い方**:
```bash
kamosu migrate                # イメージバージョンまで自動適用
kamosu migrate --dry-run      # 実行予定の一覧を表示
kamosu migrate --to 0.3.0     # 特定バージョンまで適用
kamosu migrate --force         # ダーティ状態でも強制実行
```

**処理フロー**:
1. Git ダーティチェック — **ホスト**（`--force` で無視）
2. `.kamosu-version` から現在のデータバージョンを読む — **ホスト**
3. Docker イメージラベルからターゲットバージョンを取得 — **ホスト**（`docker inspect`）
4. `migrate/` から対象スクリプトを列挙 — **ホスト**（バージョン比較）
5. 各スクリプトを Docker 内で順番に実行 — **Docker**
6. `.kamosu-version` をターゲットバージョンに更新 — **ホスト**
7. `git commit` — **ホスト**

**マイグレーションスクリプトの規約** (`migrate/X.Y.Z.sh`):
- ファイル名はターゲットバージョン（例: `0.2.0.sh` = 「0.2.0 に上げるための処理」）
- 冪等であること（何回実行しても同じ結果）
- `set -euo pipefail` で始める
- 先頭コメントに何をするか・なぜ必要かを記述
- マイグレーション不要なバージョンにはスクリプトを作らない

#### 3.7 Host CLI (`kamosu` command)

The main orchestration script that runs on the host machine. All git operations, file detection, queue management, and timestamp handling run natively on the host. Docker is invoked only for Claude Code and Python execution.

**Design Principles**:
- **Host-side orchestration**: Git, file I/O, version checks all run on the host, using the user's native credentials and tools
- **Docker for LLM only**: `claude` and `python3` invocations are delegated to Docker
- **Single-file distribution**: Installable via a single `curl` command
- **Version compatibility**: CLI と Docker イメージは同一バージョンを共有。`VERSION` ファイルが Single Source of Truth

**Host Dependencies**: `bash`, `git`, `docker` (with compose plugin or standalone `docker-compose`). All other commands (`find`, `grep`, `date`, `touch`, `wc`, `sort`, `mkdir`) are standard coreutils, universally available on Linux, macOS, and WSL.

**Installation**:
```bash
curl -fsSL https://raw.githubusercontent.com/hayamiz/kamosu/master/cli/kamosu | \
  sudo install /dev/stdin /usr/local/bin/kamosu
```

**Internal Structure**:

```bash
cli/kamosu
  # === HELPERS ===
  die(), require_docker(), detect_compose_cmd(), compose_run()

  # === GIT HELPERS ===
  git_pull_if_remote()        # git pull --rebase; no-op if no remote
  git_push_if_remote()        # git push; no-op if no remote
  git_commit_and_push()       # args: message, paths-to-stage...

  # === DOCKER HELPERS ===
  docker_claude()             # compose_run kb claude -p "..." --allowedTools "..."
  docker_search()             # compose_run kb python3 /opt/kamosu/tools/...
  read_image_label()          # docker inspect --format for image labels

  # === VERSION CHECK ===
  check_version_compat()      # CLI version == image version check

  # === COMMANDS ===
  cmd_init(), cmd_compile(), cmd_lint(), cmd_search(),
  cmd_shell(), cmd_promote(), cmd_migrate(),
  cmd_update(), cmd_version(), cmd_help()
```

**Subcommands**:

| Subcommand | Host work | Docker work | Description |
|------------|-----------|-------------|-------------|
| `kamosu init <kb-name>` | — | `kamosu-init` | Initialize a new data repository |
| `kamosu compile [opts]` | git, file detect, queue, timestamp, commit | `claude -p` | Compile raw data into wiki |
| `kamosu lint [opts]` | mkdir, git commit (if --fix) | `claude -p` | Run wiki health checks |
| `kamosu search <query>` | — | `python3 searcher.py` | Search the wiki |
| `kamosu shell [args]` | — | `claude [args]` | Interactive Claude Code session |
| `kamosu promote <file>` | validate, history, git commit | `claude -p` | Promote Q&A into wiki |
| `kamosu migrate [opts]` | version check, dirty check, git commit | migration scripts | Run migrations |
| `kamosu update` | `docker pull` | — | Pull latest Docker image |
| `kamosu version` | show info | `docker inspect` | Show version information |
| `kamosu help` | show help | — | Show usage |

**`git_commit_and_push()` helper**:

```bash
git_commit_and_push() {
  local message="$1"; shift
  # remaining args are paths to git add
  git add "$@"
  git commit -m "$message" || { warn "Nothing to commit."; return 0; }
  git_push_if_remote
}
```

Pre-commit guards (e.g., lint's `git diff --quiet` check) are kept at each call site, not inside the helper.

**CLI Location**: `cli/kamosu` in the toolkit repo. Distributed as a single file download — no package manager required.

---

### 4. Docker Image

#### 4.1 Dockerfile Design

- ベースイメージ: `ubuntu:24.04`
- 含めるもの: git, curl, jq, Node.js, npm, Python3, pip, Claude Code CLI, gosu
- kamosu スクリプト: `/opt/kamosu/scripts/` に `kamosu-init` と `entrypoint.sh` のみ
- プロンプト: `/opt/kamosu/prompts/` に LLM プロンプトテンプレートを配置
- 検索ツール: `/opt/kamosu/tools/` にインストール、依存関係を pip install
- claude-base.md: `/opt/kamosu/claude-base.md` に配置
- テンプレート: `/opt/kamosu/templates/` に配置
- 環境変数: `KB_TOOLKIT_VERSION` を VERSION ファイルから設定
- イメージラベル: `LABEL kamosu.version=X.Y.Z` をビルド時に付与。ホスト CLI が `docker inspect --format` でコンテナ起動なしに読み取る
- UID/GID マッピング: `gosu` をインストール。`HOST_UID`/`HOST_GID` 環境変数が渡された場合、entrypoint でホストユーザーと同じ UID/GID の実行ユーザーを作成し、`gosu` で権限を降格してからコマンドを実行する。これにより、バインドマウント上に作成されるファイル（Claude Code が書く wiki 記事）がホストユーザーの所有になる

**Note**: Git 操作はホスト側で行うため、Docker イメージ内の git は `kamosu-init` と LLM ツールの用途のみ。

#### 4.2 Image Distribution

- レジストリ: `hayamiz/kamosu:<version>` (Docker Hub)
- タグ規約: セマンティックバージョニング（e.g., `0.1.0`, `0.2.0`）+ `latest`
- CI/CD: toolkit repo への tag push で GitHub Actions が自動ビルド・プッシュ

#### 4.3 Data Repository側の docker-compose.yml

`kamosu init` が認証モードに応じて `docker-compose.yml` を直接生成する。テンプレートファイルは使用しない。`kamosu init --reconfigure` で再生成可能。

**OAuth モード時:**

```yaml
services:
  kb:
    image: hayamiz/kamosu:${KB_TOOLKIT_VERSION:-latest}
    volumes:
      - .:/workspace
      - ${HOME}/.claude:/tmp/.claude-host:ro
      - ${HOME}/.claude.json:/tmp/.claude-host.json:ro
    env_file:
      - .kamosu-config
    environment:
      - HOST_UID=${HOST_UID:-0}
      - HOST_GID=${HOST_GID:-0}
    working_dir: /workspace
    stdin_open: true
    tty: true
```

**Bedrock モード時:**

```yaml
services:
  kb:
    image: hayamiz/kamosu:${KB_TOOLKIT_VERSION:-latest}
    volumes:
      - .:/workspace
      - ${HOME}/.aws:/home/kamosu/.aws:ro
    env_file:
      - .kamosu-config
    environment:
      - HOST_UID=${HOST_UID:-0}
      - HOST_GID=${HOST_GID:-0}
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
# 0. Install the kamosu CLI (one-time)
curl -fsSL https://raw.githubusercontent.com/hayamiz/kamosu/master/cli/kamosu | \
  sudo install /dev/stdin /usr/local/bin/kamosu

# 1. Initialize a new knowledge base
kamosu init my-research-topic

# 2. Git init & remote setup
cd my-research-topic
git init
git remote add origin <user's git remote URL>

# 3. Edit CLAUDE.md for your research domain
vim CLAUDE.md

# 4. Configure AWS credentials (if using Bedrock)
cp .kamosu-config.example .kamosu-config
vim .kamosu-config  # AWS_PROFILE, AWS_REGION, etc.

# 5. Initial commit & push
git add -A && git commit -m "init: knowledge base"
git push -u origin main
```

#### 6.2 Data Ingestion (Compile)

```bash
# Add new data to raw/
cp ~/Downloads/new-paper.pdf raw/papers/
# or: Obsidian Web Clipper saves to raw/web-clips/

# Run compilation
kamosu compile

# Review results in Obsidian (auto-pull or manual pull)
```

#### 6.3 Q&A

```bash
# Open an interactive Claude Code session
kamosu shell

# Or run a one-shot query
kamosu shell -p "Summarize the relationship between NVMe idle power and
                 query scheduling based on the wiki. Save to outputs/."
```

#### 6.4 Promote Q&A Results to Wiki

```bash
# List outputs not yet promoted
kamosu promote --list

# Preview what would be integrated
kamosu promote --dry-run outputs/nvme-scheduling-analysis.md

# Promote into the wiki
kamosu promote outputs/nvme-scheduling-analysis.md
```

#### 6.5 Lint

```bash
kamosu lint
# Report generated at outputs/lint-report-<date>.md
# Auto-fix:
kamosu lint --fix
```

#### 6.6 Toolkit Update

```bash
# Pull the latest Docker image
kamosu update

# Run migrations if needed
kamosu migrate
```

#### 6.7 Multi-Device Sync (with Obsidian)

- Obsidian Git プラグインで auto-pull / auto-push を設定（推奨間隔: 5分）
- wiki/ は LLM の領域なので、Obsidian 側は pull 優先（force pull）
- raw/ への投入は人間が行い、compile はホスト CLI から実行（git 操作はホストのネイティブ認証を使用）

---

### 7. Bedrock / Claude Code Integration

#### 7.1 Authentication

- EC2 上: IAM Role（推奨、profile 名 `as110-haya`）
- ローカル: `.kamosu-config` に `AWS_PROFILE` を設定

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
- Data Repo: `.kamosu-version` でピン留め

#### 8.2 Semantic Versioning Rules

| バンプ | 条件 | マイグレーション |
|--------|------|-----------------|
| PATCH (0.1.x) | バグ修正、ドキュメント修正 | 不要 |
| MINOR (0.x.0) | 機能追加、非破壊的なデータ構造変更 | あれば `migrate/` にスクリプト追加 |
| MAJOR (x.0.0) | 破壊的変更（既存 wiki の再コンパイルが必要等） | 必須。CHANGELOG に移行手順を詳述 |

#### 8.3 Migration Infrastructure

**CHANGELOG.md** — リリース単位の変更記録。[Keep a Changelog](https://keepachangelog.com/) フォーマット準拠。各バージョンに `Migration Required` セクションを設け、マイグレーションの要否と内容を明記する。

**migrate/ ディレクトリ** — バージョンごとのマイグレーションスクリプト。`kamosu-migrate` がチェーン適用する。詳細は Section 3.3 kamosu-migrate を参照。

#### 8.4 Single Version Policy

CLI と Docker イメージは **同一のバージョン番号** を共有する。`VERSION` ファイルが Single Source of Truth。

```
VERSION (e.g. "0.2.0")
  ├── Docker image tag: hayamiz/kamosu:0.2.0
  ├── Docker image label: kamosu.version=0.2.0
  ├── CLI version (stamped at release): KAMOSU_CLI_VERSION="0.2.0"
  └── Data repo pin: .kamosu-version → 0.2.0
```

**CLI バージョン管理**:
- 開発中: `KAMOSU_CLI_VERSION="dev"` — バージョンチェックをスキップ
- リリース時: `make release` が `VERSION` ファイルの値を `cli/kamosu` に `sed` で注入し、コミット → タグ → プッシュ

**CLI ↔ イメージ互換性チェック**:

| 状態 | 動作 |
|------|------|
| CLI == イメージ | 正常 |
| CLI == "dev" | チェックスキップ（開発中） |
| CLI != イメージ | 警告 + 両方の更新コマンドを表示 |

**データリポジトリ → イメージ互換性チェック** (entrypoint.sh で実行):

| 状態 | 動作 |
|------|------|
| 一致 | 正常起動 |
| データ < イメージ | 警告:「`kamosu migrate` を実行してください」 |
| データ > イメージ | エラー:「イメージが古いです。`kamosu update` を実行してください」 |
| `.kamosu-version` がない | エラー:「kamosu データリポジトリではありません」 |

**Design Rationale**: CLI と image のバージョン対応表の管理は不要。「同じバージョンを使え」という単一ルールで十分。kamosu は個人/小チーム向けツールであり、CLI と image を別々にバージョニングするユースケースはない。

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
kamosu-lint、kamosu-search（TF-IDF）、kamosu-migrate、kamosu-promote。wiki の品質管理、検索、知識蓄積機能を追加する。

#### Phase 2.5: Host CLI
Host-side `kamosu` CLI command. A single shell script installable via `curl`, wrapping all Docker invocations behind subcommands (`kamosu init`, `kamosu compile`, etc.). Eliminates the need for users to remember Docker commands.

#### Phase 3: Host-Centric Redesign
アーキテクチャを「全処理 Docker 内」から「ホストオーケストレーション + Docker は LLM/検索のみ」に移行する。See Section 2.1, 3.3, 3.6.

- Git 操作（pull/commit/push）をホスト CLI に移動
- ファイル検出・キュー管理・タイムスタンプ管理をホスト CLI に移動
- container 内スクリプト（kamosu-compile, kamosu-lint 等）を廃止、プロンプトは `/opt/kamosu/prompts/` に分離
- Docker image label によるバージョン互換性チェック
- クラッシュリカバリ（`.ingest-queue` 残存検出、`--resume`/`--clean`）
- テスト3層化（unit / integration / git）

#### Phase 4: Lab Deployment
セマンティック検索、Web UI、Bedrock コスト管理用 IAM ポリシーテンプレート、運用ドキュメント。研究室メンバーが自律的に使える状態にする。

#### Future (未定)
- LLM-suggested promote — Query 終了時に LLM が「この回答は wiki に統合すべき」と提案し、ユーザーが承認するフロー（Pattern B）。kamosu-promote の上位互換として検討
- 画像ハンドリング — raw/assets/ への画像ローカル保存と LLM からの参照（ref: Karpathy LLM Wiki の画像ダウンロード手法）
- Docker 不要モード — ホストに Claude Code がインストール済みの場合、Docker をスキップして直接実行
