---
type: ADR
id: "0009"
title: "Training mode: a voice interviewer that doubles as the e2e test harness"
status: active
date: 2026-07-11
---

## Context

CueMe needs a repeatable way to exercise the full pipeline (system-audio capture
→ STT → translation → coach) and a way to practice solo. Manually driving another
app (e.g. ChatGPT voice) works for realism but is not automatable or repeatable,
and OpenAI's Advanced Voice has no API.

## Decision

**Ship a built-in Training Mode: an interviewer Claude CLI session that reads the
brief + CV, generates one question at a time, speaks it with the native
`AVSpeechSynthesizer`, and adapts to the user's spoken answers.**

The interviewer's speech goes out the system output and is captured by CueMe's own
`ScreenCaptureKit` stream as `other`, so it flows through the real STT → translation
→ coach path — a genuine end-to-end exercise. The user's mic answers (`self`) are
debounced and fed back to the interviewer session for the next question.

Key mechanism: in training mode, `SCStreamConfiguration.excludesCurrentProcessAudio`
is set to **false** so CueMe captures its own TTS; normally it is true.

## Options considered

- **Native TTS interviewer (self-captured)** (chosen): no key, repeatable,
  adaptive, tests the whole pipeline; Apple TTS voice is clear enough for STT.
- **Inject interviewer text directly as `other`**: cleaner text, but skips the
  SCK→STT path — not an e2e test.
- **ChatGPT Advanced Voice**: best conversational realism, but manual only (no
  API) — kept as a documented alternative, not automated.
- **OpenAI Realtime API interviewer**: scriptable voice, but needs an OpenAI key
  and a separate build — rejected (local-first, no keys).

## Consequences

- Training mode toggles `excludesCurrentProcessAudio` off; echo dedup + a
  "speaking" guard keep the TTS from being mis-attributed as the user's answer.
- STT runs on synthetic speech, so the coach reacts to the transcribed question;
  acceptable, and it validates the audio path. Direct injection can be added
  later if STT quality on TTS proves insufficient.
- Interviewer role adapts by mode (interview / sales / difficult / custom).
