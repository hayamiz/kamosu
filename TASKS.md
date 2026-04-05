# kamosu — Implementation Tasks

> タスクの洗い出しと実装は並行して行う。新しいタスクはいつでも追加してよい。
> 完了したタスクは `[x]` にし、完了日を記入する。
> タスクの粒度は自由。大きなタスクを分割してもよい。

## Phase 1: Core (MVP)

- [x] Dockerfile（Ubuntu 24.04 + Claude Code + Python3） — 2026-04-05
- [x] claude-base.md（compilation, query, article format protocols） — 2026-04-05
- [x] kamosu-init（スキャフォールディング生成） — 2026-04-05
- [x] kb-claude.md.tmpl（データリポジトリ用 CLAUDE.md テンプレート） — 2026-04-05
- [x] templates/（_master_index.md, docker-compose.yml, .gitignore, .env.example） — 2026-04-05
- [x] entrypoint.sh（OAuth credential のコンテナ引き継ぎ） — 2026-04-05
- [x] docker-compose.claude-auth.yml テンプレート — 2026-04-05
- [ ] kamosu-shell（claude コマンドの薄いラッパー、引数パススルー）
- [ ] kamosu-compile（差分検出 + Claude Code 呼び出し + git commit）
- [ ] my-drafts/ 対応
  - [ ] kamosu-init で wiki/my-drafts/ ディレクトリを生成
  - [ ] claude-base.md に my-drafts プロトコル追加（読むが編集しない、compile 時のソース認識、lint 対象外）
  - [ ] kamosu-compile で status: to-compile の draft をソースとして認識
- [ ] Dockerfile 改善: ENV KB_TOOLKIT_VERSION のハードコード廃止（ARG + --build-arg 方式に変更）
- [ ] CHANGELOG.md 作成（Keep a Changelog フォーマット、[Unreleased] + 0.1.0 初期エントリ）
- [ ] Makefile（開発・ビルド・リリースの自動化）
  - [ ] build / build-nc（Docker イメージビルド、VERSION を --build-arg で渡す）
  - [ ] test / test-init / smoke（テスト実行、スキャフォールディングテスト、一気通貫テスト）
  - [ ] shell / run-init / clean（開発用ユーティリティ）
  - [ ] help（デフォルトターゲット、ターゲット一覧表示）
  - [ ] release-check（リリース前チェック）
    - [ ] CHANGELOG.md に [VERSION] エントリ + 日付があるか
    - [ ] git tag vX.Y.Z がまだ存在しないか
    - [ ] ワーキングツリーがクリーンか
    - [ ] main ブランチ上にいるか
    - [ ] MINOR/MAJOR なら Migration Required セクションがあるか
    - [ ] Migration Required 記載時に migrate/X.Y.Z.sh が存在するか
  - [ ] release（release-check → git tag → push、確認プロンプト付き）
  - [ ] push（Docker Hub プッシュ、確認プロンプト付き）
- [ ] テスト基盤（tests/run_tests.sh テストランナー、CI 連携を見据えた終了コード管理）
- [ ] テスト: kamosu-init スキャフォールディング検証
  - [ ] 生成ディレクトリ構造が kamosu-design.md の仕様と一致するか
  - [ ] テンプレート変数（`[TOPIC_NAME]` 等）の置換が正しいか
  - [ ] 不正な KB 名（特殊文字、空文字、先頭ハイフン）のバリデーション
  - [ ] 既存ディレクトリへの上書き防止
- [ ] テスト: Docker イメージの検証
  - [ ] 必要コマンドが PATH 上に存在するか（kamosu-init, claude, git, jq, python3）
  - [ ] スクリプトの実行権限
  - [ ] claude-base.md, templates/ の配置パス
  - [ ] KB_TOOLKIT_VERSION 環境変数
- [ ] テスト: entrypoint.sh の認証ハンドリング
  - [ ] credential ファイルがある場合のコピー動作
  - [ ] credential ファイルがない場合のスキップ（エラーにならないこと）
  - [ ] .claude.json（onboarding flag）の生成
- [ ] テスト: kamosu-compile（kamosu-compile 実装後）
  - [ ] --dry-run で実際のコンパイルが走らないこと
  - [ ] .last-compile-timestamp による差分検出
  - [ ] --file による特定ファイル指定
  - [ ] raw/ が空の場合の正常終了
- [ ] テスト: プロトコル文書の整合性（claude-base.md と kamosu-init の生成物の構造一致）

## Phase 2: Quality & Search

- [ ] kamosu-lint（健全性チェック + レポート生成）
- [ ] kamosu-search（TF-IDF ベース、または qmd 統合を検討）
  - [ ] qmd（tobi/qmd）との比較評価: 自前実装 vs qmd 推奨/統合
- [ ] 信頼度タグ: frontmatter に `confidence: high|medium|low` 追加（Article Format 拡張）
- [ ] Query 結果の wiki ファイリングプロトコル（outputs/ → wiki/concepts/ への昇格フロー）
- [ ] kamosu-migrate（バージョン間マイグレーション）
  - [ ] migrate/ ディレクトリ構造とスクリプト規約
  - [ ] チェーン適用ロジック（現在バージョン → ターゲットまで昇順実行）
  - [ ] Git ダーティチェック（未コミット変更があればエラー、--force で無視）
  - [ ] --dry-run（実行予定の一覧表示）
  - [ ] --to オプション（特定バージョンまで適用）
  - [ ] マイグレーション後の .kb-toolkit-version 更新 + git commit
- [ ] バージョン互換性チェック（entrypoint.sh またはスクリプト起動時にデータ版とイメージ版を比較）

## Phase 3: Lab Deployment

- [ ] セマンティック検索（sentence-transformers）
- [ ] Web UI for search
- [ ] Bedrock コスト管理用 IAM ポリシーテンプレート
- [ ] 運用ドキュメント（研究室メンバー向け）

## Future

- [ ] GitHub Actions CI/CD（tag push で Docker image 自動ビルド・プッシュ + GitHub Release 作成）
- [ ] クエリ深度の段階分け（Quick / Standard / Deep）— Query Protocol 拡張
- [ ] kamosu-ingest: Jina Reader (`r.jina.ai`) による CLI データ投入（URL → raw/web-clips/ に Markdown 保存）
- [ ] インジェストパイプライン拡充（Docling 等の外部ツール連携ガイド）
- [ ] 出力フォーマット多様化（Marp スライド、Mermaid ダイアグラム生成プロトコル）
- [ ] 画像ハンドリング（raw/assets/ へのローカル保存）
- [ ] マルチエージェント並列リサーチ（Deep query モード）
- [ ] Dataview 互換 frontmatter（Obsidian Dataview プラグイン対応）

## Backlog

<!-- 実装中に発見した追加タスクをここに追加 -->
