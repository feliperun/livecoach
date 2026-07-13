---
type: ADR
id: "0013"
title: "DeepSeek coach via direct API (opt-in, keyed)"
status: active
date: 2026-07-13
---

## Context

[0005](0005-llm-brain-via-claude-cli.md) runs the coach through the local Claude
Code CLI with no API key — the right default. The product owner also wants
DeepSeek V4 as a live-coach option (Pro for depth, Flash for speed), talking
**directly** to the DeepSeek API rather than proxying through the `claude`
binary. Direct HTTP avoids coupling DeepSeek availability to a Claude Code
install and keeps provider config self-contained. This introduces the first
API-keyed backend, so 0005's "no API key" stance now holds only for the Claude
lanes, not the whole app.

## Decision

**Add a DeepSeek backend that speaks the OpenAI-compatible `/chat/completions`
endpoint directly over HTTP (SSE streaming), behind the same `CoachSession`
abstraction as the CLI.** It is opt-in via the live-coach model picker
(`deepseek-v4-pro` default, `deepseek-v4-flash` for the manual/fast lane).

Latency-first choices for live use:

- **Stateless per turn** — the coach prompt already carries the context window,
  so each request is `system + user` with no accumulated history. Fewer tokens,
  no per-turn serialization; DeepSeek's server-side context cache absorbs the
  repeated system prompt.
- **Persistent `URLSession`** per session reuses the TLS/HTTP2 connection;
  sessions are **prewarmed** on start to pay the handshake before the 1st turn.
- **`thinking: {"type": "disabled"}`** — non-thinking mode, no reasoning tokens
  before the answer, minimizing first-token latency.

The API key lives in the **macOS Keychain** (`CueMe.deepseek`), never in
`brief.json` or the repo, with a `DEEPSEEK_API_KEY` env fallback for
Xcode/terminal runs. The endpoint base URL is user-configurable (defaults to the
official one). Summary and the Claude tiers are unchanged and still keyless.

## Options considered

- **Direct DeepSeek HTTP API** (chosen): true direct call, provider-isolated,
  keys in settings, no dependency on a `claude` install for DeepSeek.
- **`claude` CLI + `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` override**:
  reuses `ClaudeSession` verbatim, but proxies through the CLI (hooks, subagent
  routing, settings) and ties DeepSeek to a Claude Code install — not "direct".
  Rejected.
- **Anthropic-compatible DeepSeek endpoint** (`/anthropic`): viable, but the
  OpenAI-compatible path is the better-documented, more stable surface for a
  minimal SSE client.

## Consequences

- The app now has a keyed network path. The key is Keychain-only; no secret
  touches disk in the clear or the repo. `backendAvailable` is true when either
  the Claude CLI is present **or** DeepSeek is configured.
- DeepSeek being stateless means no prompt-cache-of-history benefit on our side;
  we rely on the vendor's context cache and the bounded coach window instead.
- Coach output parsing is backend-agnostic — the `CoachSession` protocol yields
  text deltas regardless of provider, so `CoachCardParser` is untouched.
- If the key is missing/invalid, the DeepSeek lane fails that turn (surfaced as a
  coach error); the Claude lanes and summary keep working.
