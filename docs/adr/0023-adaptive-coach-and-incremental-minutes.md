---
type: ADR
id: "0023"
title: "Adaptive coach and incremental meeting minutes"
status: active
date: 2026-07-14
supersedes: "0017"
---

## Context

Long-session telemetry showed that a fixed coach trigger produced many low-value
requests and rapidly replaced cards during open meetings. It also showed that a
rolling transcript window could not produce a durable meeting record. Users need
fast interview help, selective meeting interventions, and an evolving agenda-like
record that remains useful after the call.

## Decision

**Select coaching moments by session semantics, keep suggestions navigable, and
maintain structured meeting minutes incrementally.**

- Interview, sales and difficult-conversation modes prioritize direct questions.
  Meeting mode triggers only for questions, decisions, risks, dependencies,
  ownership or next steps, with a longer cooldown and no speculative partials.
- Recording-only mode is the sole passive mode.
- The model explicitly selected by the user serves both live and manual coaching;
  coach and minutes models can be swapped independently during capture without
  restarting audio, STT or recording.
- A card remains visually stable for at least 12 seconds. Up to 100 useful cards
  are retained and previous/next navigation is always available.
- The minutes lane consumes only turns after its successful cursor and merges them
  into JSON containing one overview paragraph plus stable titled topics. Updates
  are time- and batch-limited; stopping forces a final attempt.
- Transcript corrections preserve the original text and timestamp, update the
  in-memory transcript bus, and teach a persistent custom vocabulary. Deepgram
  sessions receive vocabulary as Nova-3 `keyterm` and `replace` query parameters.
- Full-session event counts and latency samples are aggregated even though the
  recent diagnostic event ring remains bounded.

## Consequences

- Open meetings receive fewer, more actionable interruptions, while interviews
  retain question-level responsiveness.
- A deeper selected model may add latency; users can switch to a faster model live
  when speed matters more than depth.
- Minutes retain earlier context without repeatedly sending the full transcript.
- Learned replacements apply to subsequent Deepgram connections; the visible edit
  history remains auditable in JSON and Markdown.
- Summary JSON is a provider contract and invalid responses leave the last valid
  minutes untouched.
