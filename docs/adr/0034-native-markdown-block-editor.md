---
type: ADR
id: "0034"
title: "Native visual blocks with canonical Markdown"
status: active
date: 2026-07-15
---

## Context

ADR 0032 made writing a primary CueMe workflow, but a raw Markdown text area and
a separate reading mode still ask the user to think about syntax. Notion-like
editing is more direct: each paragraph is a block, formatting is visible while
typing, `/` inserts structure, and Enter creates the next thought. CueMe must
offer that experience without introducing a proprietary document tree or making
a web editor the source of truth.

Tolaria demonstrates the interaction model with a block editor that serializes a
Markdown-safe subset. CueMe needs the same product contract while preserving its
native Swift architecture, MIT codebase and file-first storage.

## Decision

**Render canonical Markdown as native visual blocks and serialize every edit
back to Markdown immediately.**

- `MarkdownBlockDocument` is a transient projection of the Note body. It parses
  headings, paragraphs, quotes, lists, checklists, fenced code and dividers, and
  serializes those blocks back to Markdown.
- `MarkdownBlockEditor` uses SwiftUI and AppKit text views. There is no WebView,
  ProseMirror state or persisted block database.
- `/` opens a searchable command palette. Enter splits a block, Backspace merges
  or resets it, and drag handles reorder blocks.
- Bold, italic, strike, inline code and links are rendered as attributed text;
  their Markdown delimiters stay hidden in visual mode.
- A source toggle exposes the exact Markdown for interoperability and recovery.
- Autosave writes through `AppModel`/`SessionStore`; `note.md` remains the only
  canonical user-authored representation and SQLite remains a derived index.
- The block grammar must be covered by unit round-trip tests and key authoring
  paths by deterministic macOS UI tests.

## Options considered

- **Embed BlockNote or another web editor.** Rejected: it adds a browser runtime,
  a second editing architecture and licensing/supply-chain surface to a native app.
- **Persist a JSON block graph beside Markdown.** Rejected: dual sources of truth
  would drift and make the user's files less sovereign.
- **Keep raw Markdown plus preview.** Rejected: syntax-first editing is too much
  friction for the product's primary writing experience.

## Consequences

The visual grammar deliberately supports a portable Markdown subset. Unknown or
advanced syntax remains editable in source mode. New block kinds must define a
lossless Markdown representation before gaining UI. The transient document is
reparsed when external Markdown changes, so filesystem edits remain authoritative.
