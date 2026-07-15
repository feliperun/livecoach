---
type: ADR
id: "0027"
title: "Supported external audio ingress"
status: active
date: 2026-07-15
---

## Context

Apple does not expose a public API or AppleScript dictionary for enumerating the
Voice Memos library. Scanning its private container is brittle, can fail behind
privacy controls and gives the UI an integration it cannot reliably deliver.
At the same time, Voice Memos exposes each recording through the standard macOS
Share menu, and meeting audio also arrives from Finder, Shortcuts and other apps.

## Decision

**Accept external audio only through public macOS handoff surfaces and converge
every surface on one atomic inbox.**

- `CueMeShare` is a Share Extension restricted to `public.audio`. It copies the
  selected recording into a shared App Group inbox, wakes CueMe and returns
  immediately; transcription remains in the main app.
- `ImportMeetingAudioIntent` exposes the same operation to Shortcuts and accepts
  the previous action's audio output.
- Finder document-open and SwiftUI drag-and-drop also feed the inbox/import
  pipeline. The regular file picker remains available.
- Inbox writes use a temporary file plus atomic rename. Imported files are only
  removed after CueMe has archived and accepted them successfully.
- The original display name is preserved in the queued filename, but neither
  the source path nor a Voice Memos private-library path is persisted.
- CueMe does not scan or mutate private Voice Memos directories or databases.

## Consequences

- Voice Memos users can choose **Share → CueMe** without granting CueMe broad
  access to Apple's private recording storage.
- A user can build a Shortcut or Finder/Quick Action around CueMe without a
  special Voice Memos API.
- The Share Extension and main app must be signed with the same team and App
  Group entitlement. Development and distributed builds therefore need stable
  signing identities; unsigned builds can compile and test but cannot exercise
  the cross-process inbox.
- Imported recordings retain the passive-session behavior defined in ADR 0026:
  transcript, minutes, notes and actions are generated, but live Coach is not.

