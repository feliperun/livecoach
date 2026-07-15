---
type: ADR
id: "0030"
title: "Stable release identity for persistent macOS permissions"
status: active
date: 2026-07-15
---

## Context

The v0.14.0 release-assets workflow published an ad-hoc signed app when its
Developer ID secrets were absent. macOS gave that build a designated
requirement based on its code hash. Updating the app therefore changed its TCC
identity, repeatedly requested Screen & System Audio Recording permission, and
could leave a live session waiting before its recorder had started.

## Decision

- Public release assets require a Developer ID identity and notarization; the
  workflow fails closed instead of publishing an ad-hoc app.
- A live session never requests ScreenCaptureKit permission implicitly. It
  starts microphone-only when the current identity has no grant, while the
  explicit setup flow owns the system request.
- Recording and audio consumers start before ScreenCaptureKit initialization so
  microphone audio remains durable if the optional system channel is delayed or
  unavailable.

## Consequences

Release packaging is unavailable until the signing secrets are configured, but
every distributed update preserves one verifiable TCC identity. Users can still
record their own microphone when system-audio permission is absent, and repair
the optional channel without losing the session.
