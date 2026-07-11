---
type: ADR
id: "0011"
title: "Coach quality lives in the session system prompt: expert panel + playbooks"
status: active
date: 2026-07-11
---

## Context

The coach's usefulness is set almost entirely by the system prompt fixed at
session spawn ([0005](0005-llm-brain-via-claude-cli.md)). The first version had a
generic "friend" persona and only mentioned STAR — it gave safe but shallow cues
and didn't read what a question was actually testing.

## Decision

**Encode real domain expertise in the coach system prompt.** The coach is framed
as a panel of three experts — a **senior recruiter**, an **occupational
psychologist**, and an **outplacement coach** — and is instructed to, each turn:

1. diagnose the question type and its *hidden intent* (what it really tests),
2. pick the right structure from mode-specific **playbooks**, and
3. anchor the answer in real facts from the brief/CV (or offer a fill-in structure).

Playbooks are injected by mode:
- **interview** — behavioral (STAR, lead with the quantified result), motivational
  (growth framing, never bad-mouth), weakness (real + mitigation, no
  "perfectionist"), "tell me about yourself" (present→past→future), salary (don't
  anchor first, deflect to a range), gaps/layoffs (positive narrative), curveballs
  (think out loud), culture-fit, and end-of-interview questions.
- **sales** — SPIN discovery, objection reframing (value / cost of inaction), always
  a dated next step.
- **difficult** — Nonviolent Communication (observation→feeling→need→request),
  de-escalation, empathetic firmness.

Plus delivery psychology (headline first, quantify, mirror language, 2–3 sentences)
and the GUIA line now surfaces the hidden intent ("they test X → do Y"). The
terse card format, role hardening, and CV truth-source guard from earlier ADRs are
unchanged.

## Options considered

- **Expert panel + per-mode playbooks in the prompt** (chosen): biggest quality
  lever, zero runtime cost, fully offline in the prompt.
- **A retrieval step over interview-technique docs**: more content, but adds
  latency and complexity for knowledge that fits in the prompt.
- **Fine-tuned / custom model**: not available through the CLI path and overkill.

## Consequences

- Cue quality now depends on the CV/brief the user provides (garbage in → generic).
- Playbooks are opinionated; they encode a point of view on good interviewing.
- The prompt is longer but fixed at spawn and prompt-cached, so no per-turn cost.
