---
type: ADR
id: "0022"
title: "Optional Deepgram streaming STT"
status: active
date: 2026-07-14
---

## Context

ADR 0006 made Apple SpeechAnalyzer the sole STT implementation to maximize
privacy and remove account setup. Long-session testing showed that users also
need a cloud option when a local language asset, hardware/software combination,
or recognition quality is not sufficient. The provider protocol already keeps
speaker attribution tied to capture origin, so adding an opt-in implementation
does not require diarization or a different downstream model.

This decision supersedes ADR 0006 while retaining on-device STT and translation
as the defaults.

## Decision

**Offer Deepgram Nova-3 streaming as an explicit STT choice while keeping Apple
SpeechAnalyzer selected by default and Apple Translation always on-device.**

- One authenticated WebSocket is created for each capture origin, preserving
  `.self` and `.other` attribution.
- Audio is downmixed and continuously resampled off the main actor to raw mono
  PCM16 at 16 kHz. A bounded async queue decouples capture from network writes.
- Requests enable interim results, 300 ms endpointing, 1 s utterance end,
  punctuation, smart formatting and repeated Nova-3 `keyterm` parameters.
- Finalized Deepgram segments are accumulated until `speech_final` or
  `UtteranceEnd`, then emitted through the existing `TranscriptEvent` contract.
- The API key is stored in a dedicated macOS Keychain item and is never written
  into the brief, session archive, source tree or logs.
- WebSocket open is awaited with a bounded timeout so authentication/network
  failures abort startup visibly rather than producing a silent session.

## Options considered

- Replace native STT with Deepgram: rejected because local-first privacy and
  offline use remain important defaults.
- Add a Deepgram SDK dependency: rejected because URLSession already provides
  the required WebSocket transport and a package would increase binary/update
  surface for a small protocol.
- Mix both speakers into one cloud stream with diarization: rejected because
  capture origin is more reliable and preserves the existing architecture.
- Send M4A archive audio: rejected because live raw PCM avoids codec/container
  latency and the saved recording should remain a local artifact.

## Consequences

- Users can trade local privacy for a second recognition engine explicitly.
- Deepgram usage has network and account costs; settings disclose exactly what
  leaves the device.
- Capture, recording, translation, summary and coach latency remain independent
  of the network sender.
- The watchdog can recreate the selected provider without changing the rest of
  the session pipeline.
