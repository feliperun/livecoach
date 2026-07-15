---
type: ADR
id: "0032"
title: "Second Brain writing workspace"
status: active
date: 2026-07-15
---

## Context

CueMe's live capture surface was strong, but the idle state and history treated
saved information as recordings to review. A second brain needs equally direct
entry points for writing, journaling and future reading without weakening the
specialized live experience.

## Decision

**Center the product on a unified library and make recording intelligence an
optional enrichment of a Note.**

- Home exposes New Note, Journal and Record as peers and surfaces reusable profiles.
- The library organizes the corpus by Project folders, labels and local hybrid search.
- `MemoryNoteKind` provides stable semantics and icons for written and recorded types.
- Every Note has a primary Markdown tab; written Notes open there directly while
  recorded Notes preserve review/Coach/summary/transcript/action tabs.
- The editor has a spacious serif writing surface and a separate typographic reading
  mode designed for future consumption.
- Appearance follows the system by default and can be pinned to light or dark.
- Generated titles may fill a fallback title, but explicit renames always win.

## Options considered

- **Separate Notes and Meetings products.** Rejected: it recreates the silo the
  product is meant to dissolve.
- **Keep the recorder home and add a hidden editor.** Rejected: information
  architecture would still communicate that writing is secondary.
- **Embed a web editor.** Rejected: inconsistent with the native macOS architecture
  and unnecessary for the Markdown contract.

## Consequences

New primary workflows require deterministic macOS UI tests and stable accessibility
identifiers. Recorded-session navigation remains backward compatible. Visual tokens
must be adaptive rather than assuming dark appearance.
