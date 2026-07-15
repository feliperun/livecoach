---
type: ADR
id: "0031"
title: "File-first Memory Note corpus"
status: active
date: 2026-07-15
supersedes: ["0020"]
---

## Context

The pre-1.0 product treated a completed meeting snapshot as its primary durable
object. JSON was authoritative and Markdown was regenerated as an export. That
worked for a recorder, but not for a personal knowledge system whose content must
remain useful, editable and portable without the application.

## Decision

**Use `MemoryNote` as the single durable base entity and make a normal filesystem
tree the canonical personal corpus.**

- A Project is a folder with `project.md` frontmatter.
- A Note is a folder inside a Project or `_Inbox`.
- `note.md` frontmatter/body owns title, kind, labels, Project identity and written
  content.
- Recordings and attachments live inside the Note folder.
- `session.json` is a structured sidecar for lossless transcript, Coach, minutes,
  evidence and diagnostics state.
- SQLite/FTS5/sqlite-vec are disposable derived indexes.
- Reads merge canonical Markdown over the sidecar; external edits are reloaded.
- Existing archives migrate idempotently into the new tree. `session.md` continues
  as a compatibility export, and `SessionRecord` remains a source alias.

## Options considered

- **Keep JSON authoritative and add a richer export.** Rejected: ownership still
  depends on CueMe and external Markdown edits remain lossy.
- **Move all content into SQLite.** Rejected: excellent query substrate, poor
  sovereign document format and vulnerable to schema/application lock-in.
- **Use one Markdown file per Note without a folder.** Rejected: audio and arbitrary
  attachments then require fragile global naming or absolute references.

## Consequences

Filesystem moves and external edits become product inputs, not corruption.
Project/Note paths must stay relative and traversal-safe. Every new durable field
needs an explicit canonical or sidecar home plus a round-trip test. Indexes can be
rebuilt; deleting them must never delete knowledge.
