---
type: ADR
id: "0028"
title: "Evidence-first longitudinal memory with a rebuildable hybrid SQLite index"
status: active
date: 2026-07-15
---

## Context

The portable archive stored complete meeting memories but treated every session
as an isolated document. Lexical in-memory search could not relate paraphrases,
projects, people, decisions or actions across meetings. Extracted claims also
lacked a durable link back to the transcript and audio that supported them.

## Decision

**Keep JSON, Markdown and audio as the canonical portable archive, add stable
evidence and entity identifiers, and maintain a disposable SQLite hybrid-search
projection.**

The projection uses SQLite relational metadata, FTS5/BM25 and the statically
linked `sqlite-vec` 0.1.9 amalgamation. Embeddings are generated locally through
Apple NaturalLanguage sentence embeddings, with a deterministic local subword
fallback. Search merges lexical and vector ranks using reciprocal-rank fusion.

Projects and people have stable UUIDs; sessions link to them by UUID. Decisions,
questions and actions may carry transcript turn IDs, audio offsets, quotes,
confidence and lifecycle metadata. SQLite can always be rebuilt from the archive.

## Options considered

- Replace the archive with SQLite: rejected because it weakens portability.
- Remote embeddings: rejected as the default because search must remain local.
- `sqlite-vss`/Faiss: rejected in favor of the dependency-free successor.
- Vector-only retrieval: rejected because exact identifiers need FTS5.

## Consequences

- Existing archives decode with safe defaults and are indexed lazily.
- `sqlite-vec` is pre-v1, so its schema is isolated and never canonical state.
- Initial indexing consumes local CPU, but no meeting content leaves the Mac.
- Changing the embedding model requires a safe full reindex.
