---
type: ADR
id: "0016"
title: "Observable, non-cancelling coach lanes"
status: active
date: 2026-07-13
---

## Context

Native STT can finalize several fragments during one human turn. Cancelling the
current LLM task for every fragment left empty placeholders, starved useful
responses, and allowed automatic traffic to cancel questions typed by the user.
Provider and summary errors were logged or swallowed, so the live UI looked busy
even when no useful output could arrive.

## Decision

Non-question live requests debounce before dispatch and coalesce to only the newest
pending request while a provider call is in flight. Explicit questions bypass the
debounce and receive an immediate local playbook cue. Dispatched requests are never
cancelled. Manual requests use an independent queue and therefore have priority over
automatic STT traffic.

Empty or unstructured model output never becomes a final card. Empty summary
responses preserve the last valid summary. Provider failures are exposed as short
UI states with full details in help text/logs. Claude CLI sessions run text-only,
without user settings, tools, skills, plugins, MCP servers, or session persistence.

## Options considered

- Cancel every previous request: lowest staleness, but cancellation does not stop
  an already-running CLI turn and starves the UI under continuous speech.
- Queue every STT final: preserves every request but creates stale advice and cost.
- Latest-pending coalescing with a separate manual lane (chosen): bounded work,
  manual reliability, and useful live output.

## Consequences

- A card can refer to the previous completed turn while one newer request waits,
  but the coach always makes progress.
- Automatic request volume stays bounded to one active plus one pending request.
- Backend failures are visible instead of masquerading as an infinite spinner.
- The Claude CLI login is reused without importing ambient project configuration.
