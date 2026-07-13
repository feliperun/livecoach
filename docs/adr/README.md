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
| [0006](0006-on-device-stt-and-translation.md) | On-device STT & translation; LLM for coaching | active |
| [0007](0007-speaker-by-origin-and-echo-dedup.md) | Speaker by capture origin, with echo dedup | active |
| [0008](0008-coach-ux-and-context-safety.md) | Coach UX: terse, CV-grounded, leak-guarded | active |
| [0009](0009-training-mode-voice-interviewer.md) | Training mode: voice interviewer + e2e harness | active |
| [0010](0010-on-device-translation-highlighting.md) | On-device translation highlighting (tiered) | active |
| [0011](0011-expert-coach-persona-and-playbooks.md) | Expert coach persona + per-mode playbooks | active |
| [0012](0012-meeting-mode-and-synced-recording.md) | Meeting mode + timestamp-synced audio recording | active |
| [0013](0013-deepseek-coach-via-direct-api.md) | DeepSeek coach via direct API (opt-in, keyed) | active |
