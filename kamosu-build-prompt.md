# kamosu Phase 1 Build Prompt

以下のプロンプトを Claude Code に入力してください。事前に kamosu-design.md を作業ディレクトリに配置しておくこと。

---

```
kamosu-design.md を読み、Phase 1 (Core MVP) を構築してください。

## 作業内容

kamosu-design.md の "Implementation Phases > Phase 1" に記載された全コンポーネントを実装してください。

### 1. プロジェクト構造
kamosu-design.md の "Repository Structure > Toolkit Repository" に従い、ディレクトリ構造を作成。

### 2. Dockerfile
kamosu-design.md の "Section 4: Docker Image" の仕様に従う。
- ベース: ubuntu:24.04
- Claude Code CLI、Python3、Git 等の必要ツールをインストール
- スクリプト群を /opt/kamosu/scripts/ に配置し PATH に追加
- claude-base.md を /opt/kamosu/claude-base.md に配置
- テンプレートを /opt/kamosu/templates/ に配置
- VERSION ファイルから KB_TOOLKIT_VERSION 環境変数を設定
- WORKDIR は /workspace

### 3. claude-base.md
kamosu-design.md の "Section 3.1" と "Section 5" の仕様を忠実に実装。これが最も重要なファイル。LLM が wiki を正しく構築・保守するための全プロトコルを含むこと。
- Wiki Structure Protocol（インデックスの階層構造、保守ルール）
- Article Format（YAML frontmatter、記事構成、wikilink 規約）
- Compilation Protocol（6ステップの手順）
- Query Protocol（3段階のアクセスパス）
- Lint Protocol（5種類のチェック項目）
_master_index.md、_category/*.md、_cross_references.md、記事の具体的なフォーマット例を含め、LLM がこのファイルだけ読めば正確に作業できるレベルの詳細さにすること。

### 4. kamosu-init
kamosu-design.md の "Section 3.3 > kamosu-init" の仕様に従う。
- Docker コンテナ内で実行され、/output/ にスキャフォールディングを生成
- Git 初期化は行わない
- テンプレートからファイルを生成
- 実行例: `docker run --rm -v $(pwd):/output hayamiz/kamosu:latest kamosu-init my-topic`

### 5. kamosu-compile
kamosu-design.md の "Section 3.3 > kamosu-compile" の仕様に従う。
- .last-compile-timestamp ベースの差分検出
- .ingest-queue への書き出し
- Claude Code の呼び出し（claude -p でプロンプトを渡す）
- compile 後の git commit（リモートがあれば push）
- --force, --dry-run, --file オプション対応

### 6. Templates
- kb-claude.md.tmpl: kamosu-design.md の "Section 3.2" のフォーマット。ユーザーが編集する箇所を [PLACEHOLDER] で明示
- _master_index.md: 空の初期状態
- docker-compose.yml.tmpl: kamosu-design.md の "Section 4.3" の内容
- .gitignore.tmpl: .kamosu-config, *.pyc, __pycache__/, .last-compile-timestamp, .ingest-queue
- .kamosu-config.example: AWS_PROFILE, AWS_REGION, ANTHROPIC_MODEL のテンプレート

### 7. VERSION
"0.1.0" を記載。

## 品質基準
- 全 bash スクリプトは `set -euo pipefail` で始めること
- 全スクリプトに --help オプションを実装すること
- エラーメッセージは具体的で対処方法がわかるものにすること
- claude-base.md はこのシステムの品質を決定づけるため、特に丁寧に作り込むこと

## 確認方法
構築完了後、以下を確認できるようにすること:
1. `docker build -t kamosu:test .` が成功する
2. `docker run --rm -v $(pwd)/test-output:/output kamosu:test kamosu-init test-kb` でスキャフォールディングが正しく生成される
3. 生成された test-output/test-kb/ のディレクトリ構造が kamosu-design.md と一致する
```
