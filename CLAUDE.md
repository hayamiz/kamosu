# kamosu — Toolkit Development Guide

## Project Overview

kamosu は LLM を活用して研究知識ベースを構築・運用する Docker ベースのツールキット。詳細な設計は [kamosu-design.md](kamosu-design.md) を参照。

## Architecture

- **ツールとデータの分離**: このリポジトリ（toolkit repo）は Docker イメージとして配布される。ユーザーのデータは別リポジトリ（data repo）で管理される。
- **Docker イメージ**: Ubuntu 24.04 + Node.js + Claude Code CLI + kamosu スクリプト群
- **テンプレート**: `templates/` 内のファイルは `kamosu-init` でデータリポジトリに展開される

## Key Files

| ファイル | 役割 |
|---------|------|
| `kamosu-design.md` | 設計ドキュメント（設計変更時は必ずここを更新） |
| `claude-base.md` | 全 KB 共通の LLM プロトコル（compile, query, lint） |
| `Dockerfile` | ツールキットの Docker イメージ定義 |
| `scripts/kamosu-init` | データリポジトリのスキャフォールディング生成 |
| `scripts/entrypoint.sh` | コンテナ起動時の認証設定 |
| `templates/kb-claude.md.tmpl` | データリポジトリ用 CLAUDE.md の雛形 |
| `templates/docker-compose.yml.tmpl` | データリポジトリ用 compose テンプレート |
| `VERSION` | セマンティックバージョン（現在 0.1.0） |
| `TASKS.md` | 実装タスクと進捗管理 |
| `DEVLOG.md` | 実装中の知見・判断・発見の記録 |

## Development Rules

### 設計ドキュメントの同期
- 機能追加・設計変更を行った場合、**必ず `kamosu-design.md` に反映する**こと
- `kamosu-design.md` はこのプロジェクトの Single Source of Truth（仕様と設計）

### タスク管理（TASKS.md）
- 実装タスクの洗い出し・進捗管理は `TASKS.md` で行う
- タスクの追加はいつでも可。実装中に発見したタスクは Backlog セクションに追記する
- タスクを完了したら `[x]` にして完了日を記入する
- `kamosu-design.md` にはフェーズの目的と機能定義のみ記載し、チェックボックスは置かない

### 開発知見の記録（DEVLOG.md）
- 実装中に以下を発見・判断した場合、**`DEVLOG.md` に追記する**こと:
  - **decision**: 設計判断とその理由（なぜその方法を選んだか）
  - **discovery**: 実装中に分かった事実（ライブラリの挙動、環境の制約等）
  - **gotcha**: ハマったポイントと解決策
  - **idea**: 将来の改善アイデア
- フォーマット: `## YYYY-MM-DD | category | タイトル` + 本文
- 新しいエントリが上

### コーディング規約
- bash スクリプトは `set -euo pipefail` で始める
- 全スクリプトに `--help` オプションを実装する
- エラーメッセージは具体的で対処方法がわかるものにする

### テンプレートの命名規約
- テンプレートファイルは `*.tmpl` 拡張子を使う（例: `docker-compose.yml.tmpl`）
- **注意**: `templates/kb-claude.md.tmpl` はデータリポジトリ用 CLAUDE.md の雛形であり、このプロジェクトの `CLAUDE.md`（このファイル）とは別物

### Docker イメージ
- ローカルビルド: `docker build -t kamosu:latest .`
- テスト: `docker run --rm -v $(pwd)/test-output:/output kamosu:latest kamosu-init test-kb`

### 認証モード
- **ホスト OAuth 継承**（デフォルト）: ホストの `~/.claude/` をマウントしてコンテナに引き継ぐ
- **AWS Bedrock**: `.env` に `AWS_PROFILE`, `AWS_REGION` を設定

## References

- [LLM Wiki — Andrej Karpathy](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — kamosu の設計思想の参考。LLM が wiki を incremental に構築・保守するパターン。
