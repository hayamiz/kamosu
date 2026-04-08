# kamosu — Implementation Tasks

> タスクの洗い出しと実装は並行して行う。新しいタスクはいつでも追加してよい。
> 完了したタスクは `[x]` にし、完了日を記入する。
> タスクの粒度は自由。大きなタスクを分割してもよい。

## Phase 1: Core (MVP)

- [x] Dockerfile（Ubuntu 24.04 + Claude Code + Python3） — 2026-04-05
- [x] claude-base.md（compilation, query, article format protocols） — 2026-04-05
- [x] kamosu-init（スキャフォールディング生成） — 2026-04-05
- [x] kb-claude.md.tmpl（データリポジトリ用 CLAUDE.md テンプレート） — 2026-04-05
- [x] templates/（_master_index.md, docker-compose.yml, .gitignore, .kamosu-config.example） — 2026-04-05
- [x] entrypoint.sh（OAuth credential のコンテナ引き継ぎ） — 2026-04-05
- [x] docker-compose.claude-auth.yml テンプレート — 2026-04-05
- [x] kamosu-shell（claude コマンドの薄いラッパー、引数パススルー） — 2026-04-05
- [x] kamosu-compile（差分検出 + Claude Code 呼び出し + git commit） — 2026-04-05
- [x] my-drafts/ 対応 — 2026-04-05
  - [x] kamosu-init で wiki/my-drafts/ ディレクトリを生成
  - [x] claude-base.md に my-drafts プロトコル追加（読むが編集しない、compile 時のソース認識、lint 対象外）
  - [x] kamosu-compile で status: to-compile の draft をソースとして認識
- [x] Dockerfile 改善: ENV KB_TOOLKIT_VERSION のハードコード廃止（ARG + --build-arg 方式に変更） — 2026-04-05
- [x] CHANGELOG.md 作成（Keep a Changelog フォーマット、[Unreleased] + 0.1.0 初期エントリ） — 2026-04-05
- [x] Makefile（開発・ビルド・リリースの自動化） — 2026-04-05
  - [x] build / build-nc（Docker イメージビルド、VERSION を --build-arg で渡す）
  - [x] test / test-init / smoke（テスト実行、スキャフォールディングテスト、一気通貫テスト）
  - [x] shell / run-init / clean（開発用ユーティリティ）
  - [x] help（デフォルトターゲット、ターゲット一覧表示）
  - [x] release-check（リリース前チェック）
    - [x] CHANGELOG.md に [VERSION] エントリ + 日付があるか
    - [x] git tag vX.Y.Z がまだ存在しないか
    - [x] ワーキングツリーがクリーンか
    - [x] main ブランチ上にいるか
    - [x] MINOR/MAJOR なら Migration Required セクションがあるか
    - [x] ~~Migration Required 記載時に migrate/X.Y.Z.sh が存在するか~~ → Phase 2 に移動
  - [x] release（release-check → git tag → push、確認プロンプト付き）
  - [x] push（Docker Hub プッシュ、確認プロンプト付き）
- [x] テスト基盤（tests/run_tests.sh テストランナー、CI 連携を見据えた終了コード管理） — 2026-04-05
- [x] テスト: kamosu-init スキャフォールディング検証 — 2026-04-05
  - [x] 生成ディレクトリ構造が kamosu-design.md の仕様と一致するか
  - [x] テンプレート変数（`[TOPIC_NAME]` 等）の置換が正しいか
  - [x] 不正な KB 名（特殊文字、空文字、先頭ハイフン）のバリデーション
  - [x] 既存ディレクトリへの上書き防止
- [x] テスト: Docker イメージの検証 — 2026-04-05
  - [x] 必要コマンドが PATH 上に存在するか（kamosu-init, claude, git, jq, python3）
  - [x] スクリプトの実行権限
  - [x] claude-base.md, templates/ の配置パス
  - [x] KB_TOOLKIT_VERSION 環境変数
- [x] テスト: entrypoint.sh の認証ハンドリング — 2026-04-05
  - [x] credential ファイルがある場合のコピー動作
  - [x] credential ファイルがない場合のスキップ（エラーにならないこと）
  - [x] .claude.json（onboarding flag）の生成
- [x] テスト: kamosu-compile（--dry-run ベース、claude CLI 呼び出し前のロジック） — 2026-04-05
  - [x] --dry-run で実際のコンパイルが走らないこと
  - [x] .last-compile-timestamp による差分検出
  - [x] --file で存在しないファイル指定時のエラー
  - [x] raw/ が空の場合の正常終了
- [x] テスト: プロトコル文書の整合性（claude-base.md と kamosu-init の生成物の構造一致） — 2026-04-05

## Phase 2: Quality & Search

- [x] kamosu-lint（健全性チェック + レポート生成） — 2026-04-05
- [x] kamosu-search（TF-IDF ベース全文検索 CLI + Python 検索エンジン） — 2026-04-05
- [x] kamosu-promote (Q&A results → wiki filing) — 2026-04-06
  - [x] Promote Protocol in claude-base.md (reuses Compilation Protocol Steps 4-6)
  - [x] `scripts/kamosu-promote` shell script
    - [x] Read specified outputs/ files
    - [x] Call Claude Code with Promote Protocol
    - [x] Update indexes (_master_index, _category, _cross_references)
    - [x] Append promote entry to _log.md
    - [x] Record promoted files in `.promote-history`
    - [x] git commit
  - [x] `--dry-run`: show integration plan without changes
  - [x] `--list`: show unpromoted outputs/ files
  - [x] `--file <path>`: promote a file outside outputs/
  - [x] Add `promote` subcommand to host CLI (`cli/kamosu`)
  - [x] Tests for kamosu-promote
    - [x] --dry-run does not modify wiki
    - [x] --list filters out already-promoted files
    - [x] .promote-history tracking
    - [x] Error on non-existent file
- [x] kamosu-migrate（バージョン間マイグレーション） — 2026-04-05
  - [x] migrate/ ディレクトリ構造とスクリプト規約
  - [x] チェーン適用ロジック（現在バージョン → ターゲットまで昇順実行）
  - [x] Git ダーティチェック（未コミット変更があればエラー、--force で無視）
  - [x] --dry-run（実行予定の一覧表示）
  - [x] --to オプション（特定バージョンまで適用）
  - [x] マイグレーション後の .kamosu-version 更新 + git commit
- [x] バージョン互換性チェック（entrypoint.sh 起動時にデータ版とイメージ版を比較） — 2026-04-05
- [x] release-check: Migration Required 記載時に migrate/X.Y.Z.sh が存在するかチェック — 2026-04-05

## Phase 2.5: Host CLI

- [x] `cli/kamosu` — Host-side CLI script (single-file shell script) — 2026-04-06
  - [x] Subcommand dispatcher (`init`, `compile`, `lint`, `search`, `shell`, `migrate`, `update`, `version`, `help`)
  - [x] `kamosu init`: `docker run --rm -it -v $(pwd):/output IMAGE kamosu-init ...`
  - [x] `kamosu compile|lint|search|shell|migrate`: `docker compose run --rm kb kamosu-<cmd> ...`
  - [x] `kamosu update`: pull Docker image pinned in `.kamosu-version`
  - [x] `kamosu version`: show CLI version + Docker image version
  - [x] `kamosu help` and `--help` for each subcommand
  - [x] Docker availability check with clear error message
  - [x] Image tag resolution from `.kamosu-version` (or `latest` for init)
- [x] Installation script / instructions (curl one-liner) — 2026-04-06
- [x] Tests for host CLI — 2026-04-06
  - [x] Subcommand routing (each subcommand calls the correct docker command)
  - [x] Error handling (Docker not installed, not in a data repo, etc.)
- [x] Update README.md with new installation and usage instructions — 2026-04-06

## Phase 3: Host-Centric Redesign

- [x] Architecture redesign analysis (4 options evaluated, Option C Hybrid selected) — 2026-04-08
  - [x] Independent review from 3 perspectives (DevOps, CLI UX, End-user)
  - [x] Decision documented in DEVLOG.md, full analysis in git history (commit 0dce104)
- [x] Update kamosu-design.md with Option C architecture — 2026-04-08
  - [x] New Section 2.1 system overview diagram (host orchestration + Docker for LLM only)
  - [x] New Section 3.3 Docker Contract (explicit boundary)
  - [x] New Section 3.4 Prompts (Docker image stores LLM prompts)
  - [x] New Section 3.5 Host CLI Commands (host/Docker role for each command)
  - [x] New Section 3.6 Host CLI design (internal structure, helpers, version compat)
  - [x] Updated Section 4 Dockerfile (image labels, reduced scripts)
  - [x] Updated Section 8.4 Version Compatibility (docker inspect, no container startup)
  - [x] New Phase 3 in Section 9 Implementation Phases
- [x] Implement host-centric CLI (`cli/kamosu` rewrite, 913 LOC) — 2026-04-08
  - [x] Git operations (pull/commit/push) run natively on host
  - [x] File detection, queue management, timestamps on host
  - [x] Docker Compose V1/V2 auto-detection (`detect_compose_cmd`)
  - [x] Version compatibility via Docker image labels + `docker inspect`
  - [x] `docker_claude()` / `compose_run()` helpers for Docker-only invocations
  - [x] `git_commit_and_push()` shared helper (variadic paths, message arg)
  - [x] Crash recovery: stale `.ingest-queue` detection with `--resume`/`--clean`
  - [x] `--dry-run` works without Docker for compile
  - [x] `--list` works without Docker for promote
- [x] Create `prompts/` directory with LLM prompt templates — 2026-04-08
  - [x] compile.txt, lint.txt, lint-fix.txt, promote.txt, promote-dry-run.txt
  - [x] Template placeholders: `{{REPORT_FILE}}`, `{{TODAY}}`, `{{FILE_LIST}}`
- [x] Update Dockerfile — 2026-04-08
  - [x] Add `LABEL kamosu.version` and `LABEL kamosu.min_cli_version`
  - [x] Copy `prompts/` to `/opt/kamosu/prompts/`
  - [x] Remove obsolete script copies (only kamosu-init + entrypoint.sh remain)
- [x] Remove obsolete container scripts — 2026-04-08
  - [x] Deleted: kamosu-compile, kamosu-lint, kamosu-promote, kamosu-search, kamosu-shell, kamosu-migrate
  - [x] Kept: kamosu-init (needs templates/version from image), entrypoint.sh (credential setup)
- [x] Rewrite tests for new architecture — 2026-04-08
  - [x] test_cli.sh: 36 assertions (help, routing, --dry-run no-Docker, Docker-not-running)
  - [x] test_kamosu_compile.sh: 15 assertions (file detect, timestamp, --resume, --clean, my-drafts)
  - [x] test_kamosu_promote.sh: 16 assertions (--list, history, --dry-run, Docker routing)
  - [x] test_docker_image.sh: updated for reduced scripts + prompts/ checks

## Phase 4: Lab Deployment

- [ ] セマンティック検索（sentence-transformers）
- [ ] Web UI for search
- [ ] Bedrock コスト管理用 IAM ポリシーテンプレート
- [ ] 運用ドキュメント（研究室メンバー向け）

## Future

- [ ] Docker 不要モード: ホストに Claude Code がインストール済みの場合、Docker をスキップして直接実行
- [ ] GitHub Actions CI/CD（tag push で Docker image 自動ビルド・プッシュ + GitHub Release 作成）
- [ ] クエリ深度の段階分け（Quick / Standard / Deep）— Query Protocol 拡張
- [ ] kamosu-ingest: Jina Reader (`r.jina.ai`) による CLI データ投入（URL → raw/web-clips/ に Markdown 保存）
- [ ] インジェストパイプライン拡充（Docling 等の外部ツール連携ガイド）
- [ ] 出力フォーマット多様化（Marp スライド、Mermaid ダイアグラム生成プロトコル）
- [ ] 画像ハンドリング（raw/assets/ へのローカル保存）
- [ ] マルチエージェント並列リサーチ（Deep query モード）
- [ ] Dataview 互換 frontmatter（Obsidian Dataview プラグイン対応）
- [ ] qmd (tobi/qmd) との比較評価: kamosu-search の将来的な代替/統合を検討
- [ ] 信頼度タグ: frontmatter に `confidence: high|medium|low` 追加
- [ ] LLM-suggested promote: Query 終了時に LLM が promote を提案 → ユーザー承認フロー（Pattern B）

## Backlog

- Makefile: Phase 3 の構造変更を反映（Docker イメージテスト等のターゲット更新）
- test_docker_image.sh / test_entrypoint.sh / test_kamosu_init.sh / test_smoke.sh / test_protocol_consistency.sh: Docker イメージのリビルドが必要なため Phase 3 変更後は未検証。次回 `make build` 後に通すこと
- entrypoint.sh の semver 比較バグ修正: 辞書順比較 (`[[ "0.9.0" > "0.10.0" ]]`) を数値比較に置き換え
