---
type: ADR
id: "0035"
title: "Automated release-asset publishing and appcast health"
status: active
date: 2026-07-24
---

## Context

[ADR 0030](0030-stable-release-identity-for-tcc.md) made `release-assets` fail
closed when Developer ID secrets are absent, so no ad-hoc build ever ships. That
protects TCC identity but left a silent hole: release-please publishes the
GitHub release with `GITHUB_TOKEN`, and GitHub suppresses token-triggered event
runs to prevent loops. The `release: published` trigger therefore never fired
for release-please tags, so `release-assets` simply never ran. v1.0.0, v1.1.0
and v1.2.0 all shipped with **zero assets**; the Sparkle feed
(`releases/latest/download/appcast.xml`) returned 404 and auto-update was dead
from v1.0.0 onward with no visible failure.

## Decision

- **release-please dispatches packaging explicitly.** When a release is created,
  a follow-up job calls `release-assets` via `workflow_dispatch` — the one event
  type exempt from the `GITHUB_TOKEN` cascade suppression. Every release now
  attempts to package.
- **`release-assets` verifies its own output.** After upload it asserts the
  release carries the DMG, its checksum and an EdDSA-signed `appcast.xml` that
  references the DMG, and fails the run otherwise. A "green" packaging run now
  proves the assets exist.
- **An independent `release-health` watchdog** (weekly + manual) fetches the
  latest appcast and fails if it is unreachable, has no `<enclosure>`, or is
  unsigned — catching a broken feed regardless of why packaging did not produce
  it.

## Consequences

A missing or broken auto-update feed becomes a loud, attributable CI failure
instead of an unnoticed 404. Until the Developer ID / notarization secrets from
ADR 0030 are configured, the dispatched `release-assets` run fails visibly on
every release — which is the intended signal, not a regression. No signing
policy changes: ad-hoc packaging is still refused for public releases.
