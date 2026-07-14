---
type: ADR
id: "0020"
title: "Session memory workspace and portable human-readable archive"
status: active
date: 2026-07-14
---

## Context

CueMe originally treated a finished meeting as a read-only JSON entry in a
modal history. Audio lived in a second directory. That made live coaching the
center of the product, but made recorded meetings difficult to revisit, annotate,
back up, search outside the app, or enrich after the call.

## Decision

**Treat every meeting as a durable memory workspace that has the same navigation
live and after the event.**

- History remains visible in a collapsible left rail; selecting a past session
  opens coach tips, summary, transcript/translation, notes, takeaways and generated
  artifacts in the main workspace.
- The live transport becomes a playback transport after the meeting. Notes use a
  timeline offset so they remain seekable.
- Each new session is stored in a date/time + short-id directory under a root the
  user can choose. The directory contains `session.json`, `session.md`, `self.caf`
  and `other.caf` when audio is available.
- JSON remains the application state. Markdown is a mandatory human-readable copy
  rewritten after stop and after every post-session mutation.
- Stored records keep only the portable directory name, never an absolute path.
  Legacy JSON/audio locations remain readable during migration.
- Post-session generation uses the selected existing provider and only the saved
  session context. Generated output is appended as an artifact and persisted in
  both formats.

## Options considered

- Keep the modal history read-only: rejected because it fragments live and replay
  experiences and cannot become a memory assistant.
- Store only Markdown: rejected because round-tripping typed UI state and stable
  identifiers would be fragile.
- Store absolute audio paths in JSON: rejected because exports would not survive a
  moved archive, reinstall or another machine.

## Consequences

- A session directory is independently understandable and easy to back up.
- Notes, tasks and generated content are durable first-class session data.
- Changing the archive root is disabled during capture so one session cannot be
  split across locations.
- The application must keep tolerant decoding and legacy recording fallbacks.
- Provider-backed post-processing can fail independently; the saved recording and
  transcript remain usable without it.
