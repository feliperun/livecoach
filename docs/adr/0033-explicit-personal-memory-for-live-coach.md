---
type: ADR
id: "0033"
title: "Explicit personal memory for the live Coach"
status: active
date: 2026-07-15
---

## Context

The Coach was grounded in the brief, selected contexts and CV to avoid fabrication
or ambient Claude CLI leakage. The file-first corpus now contains additional real
experiences that can help a person recall relevant examples during an interview or
conversation. Sending the entire corpus would be unnecessary and unsafe.

## Decision

**Allow personal Memory Notes as a bounded, explicit Coach truth source.**

- The user controls a persistent “Use relevant memory in Coach” toggle.
- Before a live session, the local hybrid SQLite/sqlite-vec index ranks Notes from
  the session goal, details and key terms.
- At most five Notes and 12,000 characters become an immutable session snapshot.
- The prompt labels the snapshot as user memory, treats it as data rather than
  instruction, and continues to forbid ambient CLI context.
- Disabling the toggle sends no Note content. Recording-only mode still constructs
  no Coach at all.

## Options considered

- **Send the complete corpus.** Rejected for privacy, latency, cost and distraction.
- **Use only manual contexts.** Safe but misses the product's longitudinal memory
  promise and requires repeated curation.
- **Let the CLI search the filesystem.** Rejected because it breaks containment and
  allows unrelated project instructions to enter the Coach.

## Consequences

The snapshot is derived, never persisted as canonical Note content, and is rebuilt
for each session. Provider privacy copy must say that selected Note text is sent when
enabled. Retrieval and prompt grounding require unit tests; the toggle requires an
E2E regression when its primary UI changes.
