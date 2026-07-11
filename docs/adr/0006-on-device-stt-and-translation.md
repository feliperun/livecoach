---
type: ADR
id: "0006"
title: "On-device STT and translation; the LLM is reserved for coaching"
status: active
date: 2026-07-10
---

## Context

Transcription and line-by-line translation are on the critical path — they must
be realtime. Early builds translated the transcript with a Haiku CLI lane, which
competed with the coach for the same CLI resource and lagged badly as speech
flowed (translations arrived seconds late or never).

## Decision

**Do speech-to-text and translation entirely on-device, and reserve the LLM for
coaching and summary.**

- STT: `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26), on-device, per source.
- Translation: Apple's `Translation` framework via `.translationTask`, ~100–200ms,
  no key. Wired through a Sendable `TranslationPipe`; the non-Sendable
  `TranslationSession` stays in its region (used behind a `sending`/nonisolated
  boundary), results hop back to the main actor.

## Options considered

- **Apple on-device Translation** (chosen): native, private, no key, fast; frees
  the coach LLM entirely.
- **Google Translate (free endpoint or API)**: fast too, but external, and the
  key/endpoint is either paid or unofficial — against the local-first principle.
- **LLM (Haiku) translation lane**: highest quality/idiom, but competed with the
  coach and could not keep up with live speech — removed.

## Consequences

- Transcription audio never leaves the device; translation is on-device.
- First use of a language pair downloads its model once (needs network, may
  prompt).
- The transcript loses LLM-authored keyword bolding; the translator marks key
  words instead where supported, and the coach card carries the vocabulary.
- The LLM lanes (coach/summary) no longer contend with per-line translation.
