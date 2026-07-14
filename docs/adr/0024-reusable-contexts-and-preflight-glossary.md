---
type: ADR
id: "0024"
title: "Reusable contexts and cached preflight glossary"
status: active
date: 2026-07-14
supersedes: "0008"
---

## Context

A single CV and free-form brief are not enough for recurring meetings across
different products, customers, projects and companies. Deepgram Nova-3 accepts
keyterm prompting, but manually maintaining a useful session-specific list is
slow and error-prone. Generating it after audio capture starts loses the words
most likely to appear in the opening minutes.

## Decision

**Add a local library of reusable, multi-select contexts and derive the
Deepgram glossary before capture starts with an explicitly selected LLM.**

- Context documents are stored locally in Application Support and profiles save
  their selected context IDs and glossary model.
- The selected contexts are explicit truth sources for coach, training and
  minutes prompts, alongside the brief and optional CV. Ambient CLI context
  remains forbidden.
- When Deepgram is selected, `Start` generates the glossary before opening its
  WebSockets. A manual “Generate now” action allows preparation ahead of time.
- The result is cached by a SHA-256 signature over the selected model, contexts,
  brief, language, CV and manual terms. An unchanged setup starts immediately.
- Generated, manual and learned terms share one boundary policy: at most 100
  terms and an estimated 500-token aggregate budget. The Deepgram request
  sanitizes again at the network boundary.
- Generation failure never blocks recording. The session starts with the manual
  vocabulary and the compact failure state remains visible in settings.

## Options considered

- Generate after capture starts: rejected because the opening transcript would
  use a generic model and network work would compete with session startup.
- One global glossary: retained as a manual fallback, but rejected as the sole
  mechanism because unrelated terms reduce recognition precision.
- Persist generated terms permanently in the global vocabulary: rejected because
  customer/project vocabulary should not leak into unrelated future sessions.

## Consequences

- Starting a changed Deepgram setup may take one LLM round trip; pre-generation
  and signature caching remove that cost from recurring sessions.
- Selecting a context discloses its text to the chosen LLM provider when a
  glossary is generated and when coach/minutes use it; the UI states this.
- The app owns “learning” and cache persistence. Deepgram receives only bounded
  keyterms and replacement rules and does not retain CueMe context configuration.
