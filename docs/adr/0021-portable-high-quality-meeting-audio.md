---
type: ADR
id: "0021"
title: "Portable high-quality meeting audio"
status: active
date: 2026-07-14
---

## Context

The first meeting recorder reused the 16 kHz mono PCM format optimized for local
speech recognition. Persisting that stream as CAF made the recording audibly
thin, consumed roughly twice the storage of compressed speech audio, and tied
the archive to a container with poor interoperability outside Apple software.
The recognition and archive paths have different quality and portability needs.

## Decision

**Record each speaker as mono AAC-LC in an MPEG-4 Audio (`.m4a`) container at
48 kHz and 128 kbps, while keeping STT on its independent 16 kHz PCM path.**

- `MeetingRecorder` receives the original capture stream, converts it directly
  into `self.m4a` and `other.m4a`, and silence-pads them against one shared clock.
- Separate speaker tracks preserve origin-based attribution and synchronized
  playback without diarization or a live mixer.
- `MeetingRecording` resolves `.m4a` first, then the previous `.caf` names in
  both the portable archive and legacy Application Support locations.
- Recording settings are explicit and covered by a test that inspects the
  resulting file's codec, sample rate, channel count and duration.

## Options considered

- Keep 16 kHz linear PCM/CAF: rejected because it is speech-recognition input,
  not a good listening or interchange format.
- Opus in Ogg/WebM: excellent for speech and storage, but not a native
  `AVAudioFile` recording path and less predictable in general-purpose players.
- MP3: broadly playable, but adds a non-native encoding path and lacks the clean
  MP4 metadata/container integration available to AAC.
- One mixed file only: rejected because it discards separate speaker channels;
  a mixed export can be added later as a derived artifact.

## Consequences

- New archives play in mainstream non-Mac software while retaining compact size.
- A two-track hour is approximately 115 MB at the configured aggregate bitrate,
  versus approximately 230 MB for the previous two PCM tracks.
- Encoding happens in the recorder path and does not change transcription
  latency, provider latency or UI work.
- Legacy sessions remain readable; no destructive migration is required.
