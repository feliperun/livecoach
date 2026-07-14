---
type: ADR
id: "0014"
title: "Per-channel capture health and self-recovery"
status: active
date: 2026-07-13
---

## Context

A 39-minute real session exposed two independent silent failures: the mic tap
kept producing digital-zero buffers, while macOS stopped `SCStream` after about
four minutes. The app continued to say "live", saved a silent mic track, and
never attempted to recover system audio.

## Decision

**Treat mic and system capture as independently observable state machines.**
`AudioCapture` emits bounded level/state events. Near-zero digital mic input is
detected separately from normal human silence and triggers one AEC-free reopen.
Unexpected `SCStream` termination triggers bounded exponential reconnects.
Persistent failures remain visible and manually retryable in the live header.

## Consequences

- "Live" no longer implies that both channels are healthy; each channel reports
  its own status and level.
- Recovery stays below `SessionCoordinator`; STT and recording resume from the
  same streams when capture returns.
- The UI uses short visual alarms only when action is required.
