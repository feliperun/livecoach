# CueMe — Product Vision

> The "why", not the "how". Short and opinionated.

## Why this, why now

Live conversations in a second language — job interviews, sales calls, hard
talks — overload you: parse what was just said, translate it in your head, and
compose a strong answer, all in a few seconds. macOS 26 finally makes the pieces
native and cheap: on-device speech (`SpeechAnalyzer`), on-device translation
(`Translation`), and a keyless default brain through the Claude Code CLI. CueMe
stitches them into a copilot that whispers "he asked X →
answer like this" while you keep your attention on the person.

## The problem

Under pressure you lose the thread: you miss the exact question, your foreign
vocabulary evaporates, and your answer comes out long and unfocused. Generic
prep doesn't help in the moment; existing tools are web apps that need audio
drivers, cloud STT, and API keys, and they dump walls of text you can't read
while talking.

## The insight

Capturing the two sides as **separate audio sources** (your mic vs. system
audio) makes "who spoke" free — no diarization. And the assistant should read
like a **friend beside you**: one line of guidance, one ready-to-say phrase,
its translation, a couple of key words. Terse beats thorough when you're live.

## Principles

- **Local-first.** On-device STT and translation; the default LLM runs through
  the user's own Claude Code CLI. A keyed DeepSeek backend is explicit opt-in.
- **Latency is a feature.** Prewarm sessions, keep translation off the LLM,
  scan in two seconds. If it's not fast, it's useless mid-sentence.
- **Truth from the brief only.** Coaching never fabricates the user's history —
  facts come from the session brief and the pasted CV, or it offers a structure
  to fill.
- **Compact and unobtrusive.** A small, always-on-top window that sits beside
  the call, not another thing to manage.

## Shipped (v0.4.0)

The near-term horizon from the original draft is done: a single-window macOS
app that, in a foreign-language mock interview, shows the interviewer's question
with translation on top, an emoji-cued coach card (guidance + phrase +
vocabulary) within ~2s, a rolling summary, and a CV-aware brief — usable on
speakers without headphones. Plus, beyond the original scope: an expert-panel
coach persona with per-scenario playbooks, a voice training mode that practices
*and* exercises the full pipeline end-to-end, a free-topic "meeting" mode with
the coach off, and synced audio recording + a waveform player to revisit any
past session. See the [ADR index](adr/README.md) for how each of these was
decided.

## Next horizon

No fixed roadmap — pick based on real usage. Candidates surfaced during
development but not yet built: editable/custom playbooks, injecting the training
interviewer's text directly as `.other` (skipping TTS→STT round-trip) for
higher-fidelity practice transcripts, and Developer ID notarization for a
Gatekeeper-clean install once distribution beyond personal use matters.

## Shipped reliability horizon (v0.8 development)

Long-session reliability is now a product feature: per-lane watchdog recovery,
STT restart without dropping capture, delayed cross-provider failover, adaptive
coach confidence, reusable profiles, green/amber/red health, permission identity
diagnosis, per-tip feedback, and post-session coverage/P50/P95/recovery reports.
The reliability state machine is exercised by a deterministic virtual 60-minute
soak with injected stalls.

## Non-goals (for now)

- No iOS/Windows/web port — macOS 26 only.
- No cloud STT/translation, no bundled API keys.
- No voice diarization engine — separation is by capture origin, not voiceprint.
- No multi-user/team features — this is a single-user local tool.

## Related docs

- [Architecture](ARCHITECTURE.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md)
