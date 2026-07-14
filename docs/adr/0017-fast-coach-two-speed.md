---
type: ADR
id: "0017"
title: "Two-speed Fast Coach with an instant local cue"
status: active
date: 2026-07-13
---

## Context

The model selected as “deep” was also serving the live lane. Together with STT
finalization, a fixed 700 ms debounce, a long context window and GUIA-first output,
the first speakable phrase arrived too late for natural eye-contact conversations.
The manual lane felt faster because it happened to use Flash.

## Decision

Use a two-speed brain:

- live coaching always uses the fast provider tier (DeepSeek Flash or Sonnet);
- manual asks keep the selected tier (DeepSeek Pro/Flash or Opus/Sonnet);
- explicit questions bypass the 700 ms debounce;
- a deterministic local classifier immediately shows a tiny playbook cue such as
  `STAR`, `3 passos` or `Resultado + número`, without inventing an answer;
- model output starts with `DIGA`, and the prompt carries only the last six turns;
- summary starts earlier and uses a separate fast session from the selected provider;
- logs measure provider first-token, queue, first-phrase and total latency.

The local cue and remote card share an id. A `NADA`, invalid output or provider error
replaces the cue with an empty frame so it cannot become stale. Once the user starts
speaking, the active card is dismissed and late stream updates cannot reactivate it.

## Consequences

- The live hint becomes useful before a remote token arrives, while the final phrase
  remains model-generated and grounded in the brief/CV.
- Deep models no longer slow the attention-critical lane; they remain available when
  the user explicitly asks for depth.
- Six turns trade some distant context for substantially less input and lower latency.
- Product telemetry can distinguish queue/provider/parser latency in future tests.
