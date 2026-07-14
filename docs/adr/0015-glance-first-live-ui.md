---
type: ADR
id: "0015"
title: "Glance-first live coaching UI"
status: active
date: 2026-07-13
---

## Context

During eye-contact video calls, reading several labels, translations, cards and
controls competes directly with listening and speaking. The original UI exposed
too much history and text in the primary visual path.

## Decision

**Optimize the live surface for one glance and one next action.** Show only the
latest coach card, constrain its action to five words and ready phrase to twelve,
and hide native meaning and vocabulary from the live surface. Show the translated
question as one line. Starting a session collapses transcript/summary; starting to
speak dismisses the active card without deleting it from history. Move secondary
controls into an overflow menu; keep only channel health, silence and stop live.

## Consequences

- Transcript, summary, history and settings remain available but leave the
  attention-critical path.
- Prompt constraints and presentation form one contract and need joint tests.
- Capture failures may interrupt the minimal surface because correctness is more
  important than visual silence.
