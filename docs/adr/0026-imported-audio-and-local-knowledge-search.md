---
type: ADR
id: "0026"
title: "Imported audio sessions and local knowledge search"
status: active
date: 2026-07-14
---

## Context

Useful meeting memory also exists outside CueMe: exported calls, audio files and
Apple Voice Memos. These recordings need the same replay, transcript, notes,
minutes and actions as a captured session, but live coaching has no meaning
after the conversation. As the archive grows, chronological browsing alone is
not enough to retrieve a past decision or topic.

## Decision

**Treat imported audio as a first-class passive session and maintain a local,
pre-normalized knowledge index over every durable session field.**

- `SessionOrigin` distinguishes live capture, imported files and Voice Memos.
  Imported sessions use recording mode, never contain Coach cards and hide the
  Coach workspace tab.
- `AudioImportService` copies existing AAC/M4A or converts other supported audio
  to portable AAC/M4A inside the normal date-stamped session directory. The
  source file is never modified and no absolute source path is persisted.
- The selected STT provider also applies to imports. Native STT analyzes the
  file on-device and preserves SpeechAnalyzer audio ranges. Deepgram uses the
  pre-recorded endpoint with Nova-3 utterances and the current glossary, plus
  the latest batch diarization model for two visible speaker lanes.
- After transcription, the existing post-processing lane generates the meeting
  overview, topics, decisions, open questions and actions. Notes, corrections,
  playback and later generations use the same `SessionRecord` workflow.
- Voice Memos integration is best-effort and read-only. CueMe scans known Apple
  recording directories without reading or mutating the private database. If
  macOS denies access or Apple changes the private layout, the supported path is
  selecting an exported M4A through the normal file picker.
- `SessionKnowledgeIndex` stores normalized weighted fields in memory and is
  rebuilt when history changes. Search covers titles, goals, topics, overview,
  decisions, questions, actions, notes, transcript and generated artifacts;
  date and type filters are applied before scoring.

## Consequences

- Imported recordings behave like normal session memory while remaining clearly
  identified and free of retrospective coaching noise.
- Native import stays local. Choosing Deepgram explicitly uploads the copied
  audio to its pre-recorded API and can produce better speaker separation.
- Voice Memos access cannot be guaranteed because Apple exposes no supported
  app-level import contract; file selection remains the stable fallback.
- Search is instant for a typical local archive and requires no external vector
  database. It is lexical rather than semantic, but diacritic-insensitive,
  weighted and comprehensive across durable content.
- More than two diarized speakers are folded into the two speaker lanes until
  the core participant model supports arbitrary speaker identifiers.
