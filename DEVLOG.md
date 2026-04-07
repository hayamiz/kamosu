# kamosu — Development Log

> 実装中に発見した知見・判断・ハマりどころを時系列で記録する。
> エントリは新しいものが上。各エントリは日付・カテゴリ・内容で構成する。
>
> カテゴリ: `decision` | `discovery` | `gotcha` | `idea`
> - **decision**: 設計判断とその理由
> - **discovery**: 実装中に分かった事実（ライブラリの挙動、制約等）
> - **gotcha**: ハマったポイントと解決策
> - **idea**: 将来の改善アイデア

---

## 2026-04-07 | decision | Remove kb- prefix from generated directory names

`kamosu init my-topic` previously created `kb-my-topic/`. The `kb-` prefix was redundant — the user already chose the name intentionally. Now the directory name matches the input exactly: `kamosu init my-topic` → `my-topic/`.

## 2026-04-07 | decision | Fix root-owned files on host via gosu + HOST_UID/HOST_GID

When running `kamosu init` or any compose-based command, files created on host bind mounts were owned by root because the container ran as root (no `USER` directive in Dockerfile).

**Approach chosen**: Install `gosu` in the image. The host CLI exports `HOST_UID`/`HOST_GID` env vars. The entrypoint creates a runtime user with matching UID/GID and uses `gosu` to drop privileges before executing the command. This is the standard Docker pattern (used by official postgres, redis, mysql images).

**Alternatives considered**:
- `--user` flag: Would break entrypoint credential setup (needs root to copy files into the new user's home)
- Post-creation `chown`: Fragile — every future script would need to remember to fix ownership
- `fixuid`: Extra binary dependency for a problem that `gosu` + `useradd` solves natively

**Backward compatible**: If `HOST_UID`/`HOST_GID` are unset or zero, the container runs as root (existing behavior).

## 2026-04-05 | idea | kamosu-ingest: Jina Reader による CLI データ投入

[Jina Reader](https://jina.ai/reader/) (`r.jina.ai`) を使い、URL を指定して `raw/web-clips/` に Markdown として保存するコマンド。Obsidian Web Clipper の補完として、ブラウザを開かずに CLI だけで Web データを投入できる。

```bash
docker compose run kb kamosu-ingest https://arxiv.org/abs/2401.12345
# → raw/web-clips/2026-04-05-arxiv-2401-12345.md
```

実装は `curl https://r.jina.ai/<URL>` + ファイル保存の薄いスクリプト。無料枠 1,000 万トークン、API キーなしでも 20 RPM。

参照: https://jina.ai/reader/ / https://github.com/jina-ai/reader

## 2026-04-05 | idea | 信頼度タグ（Coverage Indicator）

[llm-wiki-compiler](https://github.com/ussumant/llm-wiki-compiler) で実装されている仕組み。**セクション単位**で寄与ソース数に基づく信頼度を付与する。

```markdown
## Summary [coverage: high -- 15 sources]
## Experiments [coverage: medium -- 3 sources]
## Gotchas [coverage: low -- 1 source]
```

判定基準: high (5+), medium (2-4), low (0-1)。compile 時に LLM が付与、lint 時に low を検出してフラグ。

**検討ポイント**: ソース数だけで十分か（原著論文1本なら high にすべきケースもある）、Obsidian での見出しのノイジーさ、記事単位 vs セクション単位の粒度。

## 2026-04-05 | idea | qmd による検索エンジン置き換え（優先度高）

[qmd](https://github.com/tobi/qmd) — Tobi Lutke (Shopify CEO) 作。BM25 + vector + LLM re-ranking のハイブリッド検索。完全ローカル動作（GGUF モデル、node-llama-cpp）。CLI + MCP サーバー。Karpathy が gist で直接推奨。

kamosu の `tools/search-engine/`（TF-IDF ベース自前実装予定）を qmd で置き換えるか、qmd を推奨ツールとしてドキュメントに追加する方向で検討すべき。自前実装より成熟度が高い可能性がある。Phase 2 の kamosu-search 実装時に評価する。

## 2026-04-05 | discovery | Karpathy LLM Wiki エコシステム調査

Karpathy の [LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) と派生プロダクト・コミュニティの議論を包括的に調査した。

### kamosu の現設計との一致点

kamosu は gist のパターン（raw/ → wiki/ → schema、ingest/query/lint の3オペレーション、階層インデックス）をほぼ忠実に実装済み。kamosu 独自の差別化要素: Docker コンテナ化、ツール/データ分離、`_cross_references.md`、差分コンパイル機構。

### 取り込み候補（高優先度）

1. **Query 結果の wiki ファイリング**: 良い回答を outputs/ から wiki/concepts/ へ昇格させるプロトコル。gist の核心的アイデアの一つで、kamosu では Future に記載済みだが具体的なプロトコルが未設計。
2. **信頼度タグ (confidence indicator)**: frontmatter に `confidence: high|medium|low` を追加。[llm-wiki-compiler](https://github.com/ussumant/llm-wiki-compiler) で実装済み（383ファイル→13記事、81倍圧縮の実績あり）。Model Collapse 対策としても HN で議論あり。
3. **qmd の統合検討**: Tobi Lutke 作の [qmd](https://github.com/tobi/qmd)（BM25 + vector + LLM re-ranking）。Karpathy が gist で直接推奨。kamosu の自前 search-engine より成熟度が高い可能性。

### 取り込み候補（中優先度）

4. **クエリ深度の段階分け**: Quick / Standard / Deep。[llm-knowledge-bases](https://github.com/rvk7895/llm-knowledge-bases) で実装済み。
5. **インジェストパイプライン拡充**: Jina Reader (`r.jina.ai`, URL→Markdown)、Docling (IBM, PDF/DOCX→Markdown) との連携ガイド。[awesome-llm-knowledge-bases](https://github.com/SingggggYee/awesome-llm-knowledge-bases) にツール一覧あり。
6. **出力フォーマット多様化**: Marp スライド、Mermaid ダイアグラム生成。

### コミュニティからの批判と対策

- **Model Collapse**: raw/ の不変性保証と frontmatter `sources` による traceability で対応済み。信頼度タグで補強可能。
- **認知的価値の喪失**: `wiki/my-drafts/` が部分的に対応（人間の思考プロセスを保持する場所）。
- **「フロンティアモデル提供者が3週間で同じことをやる」論**: Docker ベースの環境分離とデータポータビリティが差別化。

### 参照URL一覧

- Gist: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
- Twitter: https://x.com/karpathy/status/2039805659525644595
- HN: https://news.ycombinator.com/item?id=47640875
- VentureBeat: https://venturebeat.com/data/karpathy-shares-llm-knowledge-base-architecture-that-bypasses-rag-with-an
- Pebblous (分析的): https://blog.pebblous.ai/report/karpathy-llm-wiki/en/
- Extended Brain (Zettelkasten 接続): https://extendedbrain.substack.com/p/postscript-the-wiki-that-writes-itself
- DEV.to (コンパイラ比喩): https://dev.to/rotiferdev/compile-your-knowledge-dont-search-it-what-llm-knowledge-bases-reveal-about-agent-memory-32pg
- llm-wiki-compiler: https://github.com/ussumant/llm-wiki-compiler
- llm-knowledge-bases: https://github.com/rvk7895/llm-knowledge-bases
- awesome-llm-knowledge-bases: https://github.com/SingggggYee/awesome-llm-knowledge-bases
- qmd: https://github.com/tobi/qmd
- DeepWiki: https://github.com/AsyncFuncAI/deepwiki-open

## 2026-04-05 | decision | テンプレートファイルのリネーム

`templates/CLAUDE.md.template` → `templates/kb-claude.md.tmpl` にリネーム。

**理由**: プロジェクトルートの `CLAUDE.md`（Claude Code の指示書）とテンプレートファイルの名前が似すぎており、Claude Code が混同するリスクがあった。他テンプレート（`*.tmpl`）と命名規則を統一した。

## 2026-04-05 | discovery | Docker-in-Docker でのイメージビルド

devcontainer 内で `docker build` と `docker run hello-world` が正常動作することを確認。Docker クライアント/サーバーともに v29.3.1-1。kamosu イメージ (187MB) のビルドも成功。
