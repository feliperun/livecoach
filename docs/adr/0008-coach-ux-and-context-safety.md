---
type: ADR
id: "0008"
title: "Coach UX: terse friend-style cards, CV-grounded, context-leak guarded"
status: active
date: 2026-07-10
---

## Context

The user reads the coach mid-sentence, under pressure, in a small window. Early
versions dumped multi-paragraph answers that were impossible to scan in time.
Worse, two safety problems surfaced in testing:

1. The CLI, running in the user's environment, pulled ambient context (project
   skill names) into a hint and **fabricated "experience"** the user never had.
2. Given imperative speech like *"tell me about..."*, the model **broke
   character** and replied as a chat participant ("I'm Claude, an AI…").

## Decision

**Make the coach a terse "friend beside you" and wall off its truth source.**

- Output format is a small card: `GUIA` (one line of guidance, native language,
  emoji-cued) · `DIGA` (a ready phrase in the conversation language) · `PT` (its
  native translation) · `KEY` (2–4 key terms) — or `NADA`. Rendered big-and-
  scannable, newest card as the hero.
- Facts about the user come **only** from the session brief and an optional
  pasted/imported **CV**; the prompt forbids using any ambient context and
  forbids inventing companies/projects/numbers — offer a structure to fill
  instead.
- The role is hardened: the coach is never a participant, never breaks character,
  never claims to be an AI; every output is the card or `NADA`. The translator is
  likewise a hardened engine (`<fala>` delimiters) that never answers.

## Options considered

- **Terse card + hard role/truth guard** (chosen): scannable under pressure and
  safe against fabrication and character breaks.
- **Free-form coaching prose**: richer, but unreadable live and prone to
  rambling.
- **Model-generated formatting/emojis only**: inconsistent; UI supplies the
  structure instead.

## Consequences

- CLI sessions also run from an isolated empty cwd with hooks disabled (see
  [0005](0005-llm-brain-via-claude-cli.md)) as defense-in-depth for the leak.
- Coaching quality scales with the CV the user provides.
- The manual question box reuses the same hardened prompt (Sonnet); the live
  coach uses the selected model (Opus default).
