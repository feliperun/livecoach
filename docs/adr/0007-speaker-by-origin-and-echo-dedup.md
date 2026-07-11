---
type: ADR
id: "0007"
title: "Speaker attribution by capture origin, with echo dedup for speakers"
status: active
date: 2026-07-10
---

## Context

The coach must know *who* spoke — "the interviewer asked X" vs. "you answered Y".
Voice diarization is complex and error-prone. But CueMe captures two separate
audio sources: the mic (the user) and system audio (the other party).

## Decision

**Attribute the speaker by capture origin, not by voice.** Mic = `self`, system
audio = `other`; each source runs its own transcriber. No diarization.

For the common **speaker (no-headphones)** setup, the other party's voice leaves
the speakers and re-enters the mic, producing false `self` lines. Handle it with
**echo dedup**: recent finals from each side are compared by word-containment
similarity, and a mic line that duplicates a recent system line is dropped. When
system capture is unavailable (permission denied), a **question heuristic**
triggers the coach on question-shaped mic utterances with an "uncertain speaker"
prompt, so CueMe still helps in mic-only mode.

## Options considered

- **Origin-based + echo dedup** (chosen): perfect attribution when both sources
  are captured; degrades gracefully on speakers and mic-only.
- **Voice diarization (e.g. FluidAudio)**: needed only if mixing to one stream;
  heavier and less reliable than free origin-based attribution.
- **Acoustic echo cancellation via `setVoiceProcessingEnabled`**: tried; it
  wedged the audio unit and required a duplex render graph — reverted, revisit
  later with a correct graph. Echo dedup covers the gap for now.

## Consequences

- Requires **Screen & System Audio Recording** permission to capture `other`;
  the UI surfaces capture status and a fix shortcut.
- Headphones give the cleanest separation; speakers rely on echo dedup.
- Attribution quality is what lets the coach say "he asked" vs. "you said".
