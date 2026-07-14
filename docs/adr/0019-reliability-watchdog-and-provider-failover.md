---
type: ADR
id: "0019"
title: "Runtime watchdog, provider failover, and post-session quality"
status: active
date: 2026-07-14
---

## Context

Long calls exposed failure modes that a successful preflight could not predict:
an audio source could stop producing buffers, STT could stop finalizing while
audio remained healthy, a recorder write could fail, or the selected LLM could
miss the latency budget. A live user cannot diagnose any of these while making
eye contact, and detailed status text would add cognitive load.

## Decision

**Treat every live lane as independently observable and recoverable.**

- A metadata-only watchdog checks audio-buffer progress, recent voice versus STT
  finals, and recorder frame growth every two seconds.
- Capture and STT are restarted per source; a healthy lane is never torn down to
  repair another lane. Recovery is rate-limited.
- The preferred coach provider gets four seconds to emit its first token. Before
  any primary output, failure or latency starts an available secondary provider.
- The live UI reduces health to green/amber/red. Detailed recovery and error
  events are persisted only in the session report.
- Coach triggers use a confidence score so indirect prompts can qualify while
  uncertain self-channel statements remain quiet.
- Profiles, per-card feedback, latency percentiles, coverage, and a recovery
  timeline close the loop after a session without uploading transcript or audio.
- A virtual 60-minute soak test verifies steady progress and injects capture and
  recorder stalls deterministically.

## Options considered

- Restart the entire session on any failure: simple, but loses context and
  interrupts healthy audio lanes.
- Show raw logs live: useful to developers, harmful during a conversation.
- Always race both LLM providers: fastest, but doubles cost and sends every turn
  twice even when the primary is healthy.

## Consequences

- Most transient failures recover without user action or a wall of status text.
- Failover is best-effort and only exists when both providers are configured.
- A provider that fails after already streaming visible output is not replaced,
  avoiding mixed or duplicated answers.
- Diagnostics remain metadata-only and capped; no conversation content is added
  to telemetry.
