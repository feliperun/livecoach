---
type: ADR
id: "0005"
title: "LLM brain via the Claude Code CLI, not the API"
status: active
date: 2026-07-10
---

## Context

The coach and summary need a capable LLM. The obvious path is the Anthropic API
with an `ANTHROPIC_API_KEY`, but that means a paid key to provision, store, and
risk leaking — and the user already has a Claude Code subscription/login on the
machine.

## Decision

**Run the LLM through the local Claude Code CLI (`claude -p`), reusing the
user's existing login — no API key.** Each lane keeps one long-lived process in
streaming-json mode (`--input-format stream-json --output-format stream-json
--include-partial-messages`), so the CLI cold start is paid once and later turns
are just inference. Sessions are **prewarmed** on session start, their system
prompt (brief + CV) and model are fixed at spawn, and they run from an isolated
empty cwd with `--settings '{"disableAllHooks":true}'`.

## Options considered

- **Claude Code CLI, warm streaming-json sessions** (chosen): zero API key, zero
  incremental cost on the user's plan, streaming tokens for the coach.
- **Anthropic API directly**: lower per-turn latency and true parallelism, but
  requires an API key to manage and pay for — rejected by the product owner.
- **One-shot `claude -p` per turn**: simplest, but pays cold start (~5–10s) on
  every call — too slow for a live coach.

## Consequences

- Latency is bounded by the CLI: warm turns ~1.5–3s; Opus generation is slower
  than Sonnet, so the live-coach model is user-selectable (Opus default).
- Auth, rate limits, and availability follow the user's Claude Code login.
- Turns within a session accumulate history; prompt caching keeps that cheap.
- The isolated cwd + `disableAllHooks` prevent the user's own Claude environment
  (project `CLAUDE.md`, hooks) from leaking into prompts (see [0008](0008-coach-ux-and-context-safety.md)).
