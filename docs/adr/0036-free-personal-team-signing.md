---
type: ADR
id: "0036"
title: "Free Personal Team signing for auto-update"
status: active
date: 2026-07-24
amends: "0030"
---

## Context

[ADR 0030](0030-stable-release-identity-for-tcc.md) made `release-assets` fail
closed unless **Developer ID** secrets were present, to stop ad-hoc updates from
resetting macOS TCC grants. That guard conflated two different things:

- **ad-hoc** signing (`codesign -s -`) — no Team ID, designated requirement
  keyed on the code hash, so it *does* change every build and break TCC; and
- **no paid Developer ID** — which is not the same problem.

Releases through v0.7.0 auto-updated fine on a **free** Apple account. The
v0.7.0 DMG is signed `Apple Development: … (MUKRM3TH82)` — a Personal Team
certificate with a **stable Team ID**. A stable team gives a stable designated
requirement, so Sparkle updates preserve TCC without any paid identity. The
free path costs only Gatekeeper notarization: the build is unnotarized, so the
first manual install needs a one-time "Open Anyway".

When the Developer ID secret was removed, the ADR 0030 guard forced CI to demand
a certificate it did not have, every release since v1.0.0 shipped with no
assets, and the Sparkle feed 404'd — auto-update died for a reason unrelated to
the paid account. This project is open-source with no revenue and will not carry
a paid Apple Developer Program membership for now.

## Decision

- **Release signing requires a stable Apple identity, not specifically a paid
  Developer ID.** `release-assets` accepts any imported certificate — the free
  Personal Team "Apple Development" cert is the supported default — and derives
  the signing identity and Team ID from it. Ad-hoc release signing stays
  refused.
- **Notarization is optional and Developer-ID-only.** Free Personal Team builds
  ship unnotarized; the packaging run skips notarization instead of failing.
  First-run distribution therefore requires a one-time Gatekeeper bypass, which
  is acceptable for a free open-source tool. Sparkle updates are installed
  in-place under the same team and are not re-gated.
- The Sparkle appcast stays EdDSA-signed (`SPARKLE_PRIVATE_KEY`); that signature
  is what authenticates an update and is independent of Apple signing.

The runtime decisions of ADR 0030 (a live session never requests
ScreenCaptureKit implicitly, microphone-only fallback, recording consumers start
before ScreenCaptureKit) are unaffected and remain in force. This ADR amends
only its release-signing rule.

## Consequences

Auto-update works again on a free Apple account: stable Team ID preserves TCC
across updates, and the appcast is signed. New users perform a one-time "Open
Anyway" on first install because builds are unnotarized. Upgrading to a paid
Developer ID later needs no workflow change — the notarization step activates
automatically when a `Developer ID Application` identity and notary secrets are
present. The Personal Team certificate now lives in a repository secret
(`SIGNING_CERTIFICATE_P12_BASE64`); it is a development-level identity, lower
stakes than a Developer ID and revocable from the Apple Developer account.
