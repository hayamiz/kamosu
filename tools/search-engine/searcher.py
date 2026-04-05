#!/usr/bin/env python3
"""
kamosu wiki search engine — TF-IDF based full-text search.

Indexes all .md files under wiki/concepts/ and provides ranked search results.
Index is cached to .search-index.json and rebuilt when wiki files change.
"""

import argparse
import json
import math
import os
import re
import sys
from collections import Counter
from pathlib import Path


INDEX_FILE = ".search-index.json"


def tokenize(text: str) -> list[str]:
    """Simple tokenizer: lowercase, split on non-alphanumeric, filter short tokens."""
    text = text.lower()
    # Remove YAML frontmatter
    text = re.sub(r'^---\n.*?\n---\n', '', text, flags=re.DOTALL)
    # Remove markdown syntax
    text = re.sub(r'[#*\[\]()>`_~]', ' ', text)
    tokens = re.findall(r'[a-z0-9\u3040-\u9fff]+', text)
    return [t for t in tokens if len(t) > 1]


def build_index(wiki_dir: str) -> dict:
    """Build TF-IDF index from wiki markdown files."""
    concepts_dir = Path(wiki_dir) / "concepts"
    if not concepts_dir.exists():
        return {"documents": {}, "idf": {}, "doc_count": 0}

    documents = {}
    df = Counter()  # document frequency

    md_files = list(concepts_dir.glob("*.md"))

    for md_file in md_files:
        try:
            content = md_file.read_text(encoding="utf-8")
        except Exception:
            continue

        tokens = tokenize(content)
        if not tokens:
            continue

        # Term frequency
        tf = Counter(tokens)
        total = len(tokens)
        rel_path = str(md_file.relative_to(wiki_dir))

        # Extract title from frontmatter or first heading
        title = rel_path
        title_match = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', content, re.MULTILINE)
        if title_match:
            title = title_match.group(1)
        else:
            heading_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
            if heading_match:
                title = heading_match.group(1)

        # Extract summary
        summary = ""
        summary_match = re.search(r'## Summary\n+(.+?)(?:\n\n|\n##)', content, re.DOTALL)
        if summary_match:
            summary = summary_match.group(1).strip()[:200]

        documents[rel_path] = {
            "title": title,
            "summary": summary,
            "tf": {term: count / total for term, count in tf.items()},
            "token_count": total,
        }

        for term in set(tokens):
            df[term] += 1

    # Compute IDF
    doc_count = len(documents)
    idf = {}
    if doc_count > 0:
        for term, freq in df.items():
            idf[term] = math.log(doc_count / freq)

    return {"documents": documents, "idf": idf, "doc_count": doc_count}


def save_index(index: dict, wiki_dir: str) -> None:
    index_path = Path(wiki_dir).parent / INDEX_FILE
    # Store tf as sparse dict (only keep top terms per doc to save space)
    compact = {
        "doc_count": index["doc_count"],
        "idf": index["idf"],
        "documents": {},
    }
    for path, doc in index["documents"].items():
        compact["documents"][path] = {
            "title": doc["title"],
            "summary": doc["summary"],
            "tf": dict(sorted(doc["tf"].items(), key=lambda x: -x[1])[:500]),
            "token_count": doc["token_count"],
        }
    index_path.write_text(json.dumps(compact, ensure_ascii=False), encoding="utf-8")


def load_index(wiki_dir: str) -> dict | None:
    index_path = Path(wiki_dir).parent / INDEX_FILE
    if not index_path.exists():
        return None
    try:
        return json.loads(index_path.read_text(encoding="utf-8"))
    except Exception:
        return None


def index_is_stale(wiki_dir: str) -> bool:
    index_path = Path(wiki_dir).parent / INDEX_FILE
    if not index_path.exists():
        return True

    index_mtime = index_path.stat().st_mtime
    concepts_dir = Path(wiki_dir) / "concepts"
    if not concepts_dir.exists():
        return False

    for md_file in concepts_dir.glob("*.md"):
        if md_file.stat().st_mtime > index_mtime:
            return True
    return False


def search(query: str, index: dict, top_n: int = 5) -> list[dict]:
    """Search the index and return ranked results."""
    query_tokens = tokenize(query)
    if not query_tokens:
        return []

    idf = index["idf"]
    results = []

    for path, doc in index["documents"].items():
        score = 0.0
        tf = doc["tf"]
        for token in query_tokens:
            if token in tf and token in idf:
                score += tf[token] * idf[token]

        if score > 0:
            results.append({
                "path": path,
                "title": doc["title"],
                "summary": doc["summary"],
                "score": round(score, 4),
            })

    results.sort(key=lambda x: -x["score"])
    return results[:top_n]


def main():
    parser = argparse.ArgumentParser(description="kamosu wiki search")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--wiki-dir", default="wiki", help="Wiki directory path")
    parser.add_argument("--top", type=int, default=5, help="Number of results")
    parser.add_argument("--rebuild-index", action="store_true", help="Force rebuild index")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    wiki_dir = args.wiki_dir

    # Build or load index
    index = None
    if not args.rebuild_index:
        if not index_is_stale(wiki_dir):
            index = load_index(wiki_dir)

    if index is None:
        if not args.json:
            print("Building search index...", file=sys.stderr)
        index = build_index(wiki_dir)
        save_index(index, wiki_dir)

    if index["doc_count"] == 0:
        if args.json:
            print(json.dumps({"results": [], "total": 0}))
        else:
            print("No articles found in wiki/concepts/.")
        return

    results = search(args.query, index, args.top)

    if args.json:
        print(json.dumps({"results": results, "total": len(results)}, ensure_ascii=False))
    else:
        if not results:
            print(f"No results found for: {args.query}")
            return

        print(f"Found {len(results)} result(s) for: {args.query}\n")
        for i, r in enumerate(results, 1):
            print(f"  {i}. [{r['score']:.4f}] {r['title']}")
            print(f"     {r['path']}")
            if r["summary"]:
                print(f"     {r['summary'][:100]}...")
            print()


if __name__ == "__main__":
    main()
