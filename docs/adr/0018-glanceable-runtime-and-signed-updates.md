---
type: ADR
id: "0018"
title: "Glanceable runtime and signed updates"
status: active
date: 2026-07-14
---

## Context

Video conversations leave little attention for a dense second interface. The
coach must remain useful when STT finalization or the provider is slow, and
failures must be diagnosable after the call. Releases also allowed the binary
version and Git tag to diverge.

## Decision

- Detect stable actionable STT partials and start coaching speculatively; the
  matching final turn is coalesced instead of issuing a duplicate request.
- Keep a deterministic visual response structure visible after 1.8 seconds
  while the provider continues refining the answer.
- Schedule summaries from final-turn events and attempt a final summary during
  teardown.
- Offer a floating Camera Rail with one phrase or a few visual steps and a
  10-second MIC/CALL/COACH preflight.
- Persist metadata-only diagnostics. Never include transcript text, prompts,
  credentials, or audio in diagnostic events.
- Use Sparkle 2 with EdDSA-signed appcasts. Release Please updates the Xcode
  marketing version; release-assets builds and publishes each tagged DMG.

## Consequences

The live UI stays glanceable and has an offline-safe response scaffold. Session
history can explain failures without exposing call content. Sparkle adds an
external dependency and its private key must remain in repository secrets.
Public distribution still requires Developer ID and Apple notarization.
