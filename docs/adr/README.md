# Architecture Decision Records

Architecture Decision Records (ADRs) for **CueMe**.

## Format

Each ADR is markdown with YAML frontmatter:

```markdown
---
type: ADR
id: "0001"
title: "Short decision title"
status: proposed        # proposed | active | superseded | retired
date: YYYY-MM-DD
superseded_by: "0007"  # only if status: superseded
---

## Context
...

## Decision
**What was decided.**

## Options considered
...

## Consequences
...
```

### Status lifecycle

```
proposed → active → superseded
                 ↘ retired
```

## Rules

- One decision per file.
- Files named `NNNN-short-title.md` (monotonic numbering).
- Once `active`, never edit — supersede instead.
- [../ARCHITECTURE.md](../ARCHITECTURE.md) reflects active decisions only.

## Index

| ID | Title | Status |
|----|-------|--------|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | active |
| [0002](0002-root-managed-ai-guidance.md) | Root-managed AI guidance files | active |
| [0003](0003-sentrux-structural-quality-gates.md) | Sentrux structural quality gates | active |
| [0004](0004-native-macos-swift-app.md) | Native macOS 26 Swift app (no webview/driver) | active |
| [0005](0005-llm-brain-via-claude-cli.md) | LLM brain via the Claude Code CLI, not the API | active |
| [0006](0006-on-device-stt-and-translation.md) | On-device STT & translation; LLM for coaching | superseded by 0022 |
| [0007](0007-speaker-by-origin-and-echo-dedup.md) | Speaker by capture origin, with echo dedup | active |
| [0008](0008-coach-ux-and-context-safety.md) | Coach UX: terse, CV-grounded, leak-guarded | superseded by 0024 |
| [0009](0009-training-mode-voice-interviewer.md) | Training mode: voice interviewer + e2e harness | active |
| [0010](0010-on-device-translation-highlighting.md) | On-device translation highlighting (tiered) | active |
| [0011](0011-expert-coach-persona-and-playbooks.md) | Expert coach persona + per-mode playbooks | active |
| [0012](0012-meeting-mode-and-synced-recording.md) | Meeting mode + timestamp-synced audio recording | active |
| [0013](0013-deepseek-coach-via-direct-api.md) | DeepSeek coach via direct API (opt-in, keyed) | active |
| [0014](0014-per-channel-capture-health.md) | Per-channel capture health and self-recovery | active |
| [0015](0015-glance-first-live-ui.md) | Glance-first live coaching UI | active |
| [0016](0016-observable-non-cancelling-coach-lanes.md) | Observable, non-cancelling coach lanes | active |
| [0017](0017-fast-coach-two-speed.md) | Two-speed Fast Coach with an instant local cue | superseded by 0023 |
| [0018](0018-glanceable-runtime-and-signed-updates.md) | Glanceable runtime and signed updates | active |
| [0019](0019-reliability-watchdog-and-provider-failover.md) | Runtime watchdog, provider failover, and post-session quality | active |
| [0020](0020-session-memory-workspace-and-portable-archive.md) | Session memory workspace and portable human-readable archive | superseded by 0031 |
| [0021](0021-portable-high-quality-meeting-audio.md) | Portable high-quality meeting audio | active |
| [0022](0022-optional-deepgram-streaming-stt.md) | Optional Deepgram streaming STT | active |
| [0023](0023-adaptive-coach-and-incremental-minutes.md) | Adaptive coach and incremental meeting minutes | superseded by 0025 |
| [0024](0024-reusable-contexts-and-preflight-glossary.md) | Reusable contexts and cached preflight glossary | active |
| [0025](0025-adaptive-live-experience-and-session-review.md) | Adaptive live experience and durable session review | active |
| [0026](0026-imported-audio-and-local-knowledge-search.md) | Imported audio sessions and local knowledge search | active |
| [0027](0027-supported-external-audio-ingress.md) | Supported external audio ingress | active |
| [0028](0028-evidence-first-longitudinal-semantic-memory.md) | Evidence-first longitudinal memory with hybrid SQLite search | active |
| [0029](0029-key-feature-e2e-regression-gate.md) | Key-feature E2E regression gate | active |
| [0030](0030-stable-release-identity-for-tcc.md) | Stable release identity for persistent macOS permissions | active |
| [0031](0031-file-first-memory-note-corpus.md) | File-first Memory Note corpus | active |
| [0032](0032-second-brain-writing-workspace.md) | Second Brain writing workspace | active |
| [0033](0033-explicit-personal-memory-for-live-coach.md) | Explicit personal memory for the live Coach | active |
