---
type: ADR
id: "0029"
title: "Key-feature E2E regression gate"
status: active
date: 2026-07-15
---

## Context

Unit tests validate parsers, models and infrastructure but do not prove that a
user can complete a workflow through the macOS application. The first semantic
memory UI tests exposed incorrect accessibility assumptions and ambiguous source
controls that compilation and model tests could not detect. Calling Training
Mode an E2E exercise also did not make it an automated regression gate.

## Decision

**Every key feature or user-visible primary-workflow change must add or update a
deterministic XCTest UI scenario, and the UI suite is a required CI check.**

`CueMeTests` owns unit and integration coverage. `CueMeUITests` launches the real
application and validates observable behavior through stable accessibility
identifiers. Fixtures are synthetic and isolate the archive, SQLite projection,
Keychain, updater and network providers. Tests wait on observable predicates and
must not use fixed sleeps. Training Mode remains an operational pipeline exercise,
not a substitute for automated XCTest UI coverage.

Exceptions are limited to documentation, formatting and demonstrably
behavior-preserving internal refactors, and must be justified in the PR.

## Options considered

- Unit tests only: rejected because view wiring and end-user flows remain untested.
- Agent instructions without CI: rejected because guidance is not enforceable.
- Full real-provider E2E on every PR: rejected as slow, costly and nondeterministic.

## Consequences

- Primary workflows have both close-to-code tests and user-level regression tests.
- Accessibility identifiers become a stable testing contract.
- CI spends additional macOS minutes but reports unit and UI failures separately.
- Live audio/provider smoke tests remain opt-in and complement the deterministic gate.
