# kamosu Base Protocol

> このファイルは kamosu ツールキットの全知識ベース共通 LLM プロトコルです。
> コンパイル、クエリ応答、lint の全操作において、このプロトコルに従ってください。

---

## 1. Wiki Structure Protocol

知識ベースの wiki は以下の階層インデックス構造で管理されます。wiki を更新する際は、**必ず関連するインデックスを同期更新**してください。

### 1.1 ディレクトリ構造

```
wiki/
├── _master_index.md        # カテゴリ一覧 + 統計（最初に読む）
├── _category/              # カテゴリ別インデックス
│   ├── <category-name>.md  # 各カテゴリの記事一覧と要約
│   └── ...
├── _cross_references.md    # カテゴリ横断の関連性マップ
└── concepts/               # 記事本体
    ├── <article-slug>.md
    └── ...
```

### 1.2 _master_index.md

全カテゴリの一覧と1行要約を保持するファイル。LLM が最初に読むべきファイルです。

**フォーマット:**

```markdown
# Master Index

Last updated: YYYY-MM-DD

## Categories

| Category | Articles | Summary |
|----------|----------|---------|
| [category-name](_category/category-name.md) | N | カテゴリの1行説明 |

## Statistics
- Total articles: N
- Total categories: N
- Last compiled: YYYY-MM-DDTHH:MM:SS+09:00
```

**保守ルール:**
- 記事を追加・削除した場合、対応するカテゴリの Articles 数を更新する
- 新カテゴリを作成した場合、Categories テーブルに行を追加する
- カテゴリが空になった場合、テーブルから行を削除し、対応する `_category/*.md` も削除する
- Last updated と Statistics は毎回更新する

### 1.3 _category/*.md

カテゴリ別の記事一覧。各記事について2-3行の要約を含みます。

**フォーマット:**

```markdown
# Category: <Category Display Name>

## Articles

### [article-slug](../concepts/article-slug.md)
記事の2-3行要約。この記事の主要な主張やトピックを簡潔に記述する。

### [another-article](../concepts/another-article.md)
別の記事の2-3行要約。
```

**保守ルール:**
- 記事を新規追加した場合、対応するカテゴリインデックスにエントリを追加する
- 記事を更新した場合、要約が実態と乖離していれば更新する
- 記事を削除した場合、エントリを削除する
- カテゴリファイル名は `_category/<category-slug>.md` とする（小文字、ハイフン区切り）

### 1.4 _cross_references.md

カテゴリ横断の関連性を記録するファイル。

**フォーマット:**

```markdown
# Cross References

## category-a ↔ category-b
- 関連性の説明（1-2文）
- See: [[article-x]] → [[article-y]]

## category-a ↔ category-c
- 関連性の説明
- See: [[article-z]] → [[article-w]]
```

**保守ルール:**
- 新しい記事がカテゴリ横断の関連性を持つ場合、エントリを追加する
- 記事を削除した場合、参照しているエントリを更新または削除する
- 関連性は双方向で記述する（category-a ↔ category-b の形式）

---

## 2. Article Format

### 2.1 YAML Frontmatter

すべての記事は以下の YAML frontmatter を持つ必要があります。

```yaml
---
title: "記事タイトル"
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
sources:
  - raw/path/to/source-file.pdf
  - raw/path/to/another-source.md
tags: [tag1, tag2, tag3]
category: category-slug
---
```

**必須フィールド:**
| フィールド | 説明 |
|-----------|------|
| title | 記事のタイトル（引用符で囲む） |
| date_created | 記事の作成日 |
| date_updated | 記事の最終更新日 |
| sources | raw/ 内のソースファイルパス（リスト） |
| tags | タグのリスト |
| category | 所属カテゴリのスラッグ |

### 2.2 記事構成

```markdown
---
(frontmatter)
---

# 記事タイトル

## Summary
2-3文で記事の要点をまとめる。この記事が何について書かれているか、
主要な知見は何かを簡潔に記述する。

## Main Content
詳細な記述。必要に応じてサブセクションに分割する。
他の記事への [[wikilink]] を適切に含める。

### サブセクション1
内容...

### サブセクション2
内容...

## Related Articles
- [[related-article-slug]] — 関連性の1行説明
- [[another-related]] — 関連性の1行説明

## Sources
- [ソース名1](../raw/path/to/source.pdf)
- [ソース名2](../raw/path/to/source2.md)
```

### 2.3 Wikilink 規約

- 他の記事への参照は `[[article-slug]]` 形式を使用する
- article-slug は `wiki/concepts/` 内のファイル名（拡張子なし）と一致させる
- 新規記事を作成する際、関連する既存記事に `[[新記事のslug]]` バックリンクを追加する
- 存在しない記事への wikilink は作成しない

---

## 3. Compilation Protocol

raw/ の新規データを wiki 記事にコンパイルする際は、以下の6ステップに従ってください。

### Step 1: キューの読み込み
`.ingest-queue` ファイル、または `--file` オプションで指定されたファイルパスを読み取る。

### Step 2: ソースデータの理解
各ソースファイルの内容を読み、以下を把握する:
- 主題・トピック
- 主要な知見・主張
- 関連する概念・用語
- データの種類（論文、Webクリップ、コードスニペット等）

### Step 3: 既存 wiki の把握
1. `_master_index.md` を読み、現在のカテゴリ構造を把握する
2. 関連しそうなカテゴリの `_category/*.md` を読み、既存記事を確認する
3. 必要に応じて既存記事本体を読み、重複・関連性を確認する

### Step 4: 記事の作成・更新
- **新規トピック**: `wiki/concepts/` に新しい記事を作成する
  - ファイル名は `<slug>.md`（小文字、ハイフン区切り、英語）
  - Article Format（セクション2）に従う
- **既存トピックの補強**: 該当する既存記事を更新する
  - `date_updated` を更新する
  - `sources` に新しいソースを追加する
  - Main Content に新しい情報を統合する

### Step 5: バックリンクの追加
- 新規・更新記事から参照される既存記事の Related Articles セクションにバックリンクを追加する
- 既存記事から新規記事への自然な参照がある場合、本文中に `[[wikilink]]` を追加する

### Step 6: インデックス更新
以下を必ず更新する:
1. `_master_index.md` — カテゴリの記事数、統計、Last updated を更新
2. 影響を受けた `_category/*.md` — 記事エントリの追加・更新
3. `_cross_references.md` — カテゴリ横断の新しい関連性があれば追加

**重要**: インデックス更新を忘れると wiki の整合性が失われます。必ず全ステップを完了してください。

---

## 4. Query Protocol

ユーザーの質問に回答する際は、以下の3段階アクセスパスに従ってください。

### Stage 1: カテゴリレベルの概観
`_master_index.md` を読み、質問に関連しそうなカテゴリを特定する。

### Stage 2: 記事レベルの特定
関連カテゴリの `_category/*.md` を読み、質問に直接関連する記事を特定する。
要約を読むことで、どの記事を詳細に読むべきか判断する。

### Stage 3: 記事の詳細読み込みと回答生成
必要な記事本体を読み、質問への回答を生成する。
- 回答には wiki 記事への `[[wikilink]]` 参照を含める
- 必要に応じて `_cross_references.md` も参照し、カテゴリ横断の知見を統合する
- 回答に使用した記事のソースも明記する

---

## 5. Lint Protocol

wiki の健全性チェックを行う際は、以下の5種類のチェックを実行してください。

### Check 1: 孤立記事の検出
`wiki/concepts/` 内の全記事について、以下のいずれかからリンクされているか確認する:
- `_category/*.md` のエントリ
- 他の記事の `[[wikilink]]` または Related Articles

どこからもリンクされていない記事は孤立記事として報告する。

### Check 2: 矛盾する記述の検出
複数の記事間で同一トピックについて矛盾する記述がないか確認する。
矛盾を発見した場合、両方の記事とソースを参照して正確な記述を特定する。

### Check 3: ソース参照の検証
各記事の `sources` フィールドに記載されたファイルが `raw/` 内に実在するか確認する。
欠落しているソースを報告する。

### Check 4: 新たな接続の提案
既存記事間で `[[wikilink]]` が張られていないが、内容的に関連性がある組み合わせを検出する。
`_cross_references.md` に未記載のカテゴリ横断の関連性も提案する。

### Check 5: インデックス整合性チェック
- `_master_index.md` のカテゴリ一覧が `_category/` 内のファイルと一致するか
- 各 `_category/*.md` の記事エントリが `wiki/concepts/` 内の実ファイルと一致するか
- 記事数のカウントが正確か
- `_cross_references.md` で参照されている記事が存在するか

**レポート出力フォーマット:**

```markdown
# Lint Report — YYYY-MM-DD

## Summary
- Orphaned articles: N
- Contradictions found: N
- Missing sources: N
- Suggested connections: N
- Index inconsistencies: N

## Details

### Orphaned Articles
- concepts/article-name.md — どこからもリンクされていません

### Contradictions
- concepts/article-a.md と concepts/article-b.md で「XXX」について矛盾
  - article-a: 「...」
  - article-b: 「...」

### Missing Sources
- concepts/article-name.md → raw/papers/missing-file.pdf が存在しません

### Suggested Connections
- [[article-x]] と [[article-y]] は「XXX」について関連性があります

### Index Inconsistencies
- _master_index.md: category-name の記事数が 5 ですが、実際は 7 です
```
