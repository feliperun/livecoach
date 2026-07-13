---
type: ADR
id: "0012"
title: "Meeting mode (coach off) + timestamp-synced dual-file audio recording"
status: active
date: 2026-07-13
---

## Context

CueMe's coach is built around known scenario types (interview/sales/difficult)
with playbooks ([0011](0011-expert-coach-persona-and-playbooks.md)). A free-topic
work meeting doesn't fit any playbook, and coaching would be noise, not help. But
the transcription/translation pipeline is still valuable there — plus users want
to **re-listen to the original audio** aligned with the transcript afterward,
which no prior mode supported (nothing was recorded to disk).

## Decision

**Add a `meeting` mode that is "passive"** (`Mode.isPassive`): the coach session
is never created and never triggered (`consumeBusForCoaching` and the mic-only
question heuristic both skip it), while transcription, translation, and the
rolling summary keep running — a meeting still benefits from live notes.

**Add opt-out audio recording, on by default, for any mode.** A `MeetingRecorder`
actor writes the two capture sources — mic (`self`) and system audio (`other`) —
to **two separate 16 kHz mono `.caf` files**, keyed by the session id under
`Application Support/CueMe/recordings/<id>/`. Each `AudioChunk` carries its
capture timestamp; the recorder pads each file with silence up to the frame
position implied by `chunkTs - recordingStart`, so both files stay aligned to the
same wall clock even though the two sources arrive independently and don't
always speak at the same time. This was verified with a synthetic dual-tone
harness: a file with silence 2–5s and speech 5–6s decoded with RMS exactly
matching the ingested pattern.

Playback uses `MeetingPlayer`, which drives two `AVAudioPlayer`s with
`play(atTime:)` anchored to a shared `deviceCurrentTime` — they start in sync
without needing a custom mixing engine. `WaveformGenerator` reads both files in a
background task and merges them into a single amplitude envelope for one visual
waveform; `WaveformPlayerView` renders it as tappable bars with a playhead. In the
session history detail, the transcript line whose timestamp is closest to
(and before) the current playback position highlights automatically, and tapping
a line seeks + plays audio from that point.

## Options considered

- **Passive mode + dual-file synced recording** (chosen): reuses the existing
  speaker-by-origin split (no new capture code), keeps both voices intelligible
  and independently seekable, and needs no realtime audio mixing engine.
- **Suppress coach only by silence-mode / manual toggle**: less discoverable;
  a dedicated mode makes "no coaching here" the obvious default for free topics.
  `Mode.isPassive` is deliberately a mode property so future passive modes need
  no per-callsite special-casing.
- **Single mixed-down mono recording (sum both sources)**: simpler format, but
  sequential concatenation without true sample-level mixing would desync
  overlapping speech; correct mixing needs a real-time render graph, which is
  exactly what wedged the process when AEC was tried ([0007](0007-speaker-by-origin-and-echo-dedup.md)).
  Two independently-aligned files sidestep that risk entirely.
- **AVAudioEngine multi-node playback for perfect sample sync**: more precise
  but a lot more moving parts (offline render, node graph, seeking); two
  `AVAudioPlayer`s synced via `deviceCurrentTime` is simple, robust, and precise
  enough for voice.

## Consequences

- Recording is **on by default** (opt-out toggle in the brief) per product
  requirement; every mode can be recorded, not just meetings.
- Storage: 16 kHz mono Int16 is small for voice (~1.9 MB/min per file) but is not
  lossless hi-fi audio — acceptable for a conversation-review use case.
- No absolute file paths are stored in `SessionRecord`/exported JSON — audio
  location is derived from the session id at read time, keeping exports portable
  and avoiding a stale-path failure mode across app reinstalls.
- Deleting a session from history also deletes its recording directory.
- The non-sandboxed app writes under its own Application Support container — no
  new entitlement needed.
