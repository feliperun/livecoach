# Architecture

> Current-state summary. ADRs in [adr/](adr/README.md) hold the history and the
> *why*; this file reflects only **active** decisions. Update it in the same
> commit as any structural change.

## High-level flow

```
AVAudioEngine (mic, .self) ─────┐                                        ┌─▶ NativeTranscriber (SpeechAnalyzer)
                                ├─▶ SttProvider (→16k mono PCM16) ────────┤
ScreenCaptureKit (system, .other)┘        │                               └─▶ DeepgramTranscriber (Nova-3 WebSocket)
Share / Shortcuts / files / drop ─▶ ExternalAudioInbox ─┴─▶ AudioImportService ─▶ Native file STT / Deepgram batch
                                           ▼                                   ▼
                                    MeetingRecorder                     TranscriptBus (actor)
                                  (synced dual .m4a files,     ┌────────────┬────────────┬────────────┐
                                   opt-out, on by default)     ▼            ▼            ▼            ▼
                                                          Translation   Minutes      Coach        AppModel
                                                          (on-device,   (incremental, (adaptive,  (@Observable,
                                                           TranslationPipe) separate) selected)   MainActor)
                                                                                                        ▼
                                              TrainingCoordinator ──speaks (TTS)──▶ (captured back as .other)
                                              (voice interviewer, opt-in)
                                                                                                        │
                                                                                                        ▼
                                                                                                  SwiftUI (compact)
                                                                                                        │
                                                                                          on stop() ────┘
                                                                                                        ▼
                                                               MemoryNote → SessionStore → Project/Note folders
                                                                    │        ├─ note.md (canonical)
                                                                    │        ├─ session.json (structured sidecar)
                                                                    │        └─ audio + attachments
                                                                    ▼
                                              SemanticMemoryIndex (SQLite FTS5 + sqlite-vec, rebuildable)
                                                                    │
                                                                    ▼
                                      SessionSidebar / MemoryNoteEditor / SessionWorkspaceView
```

Single Swift process with Sparkle and vendored sqlite-vec as the only runtime
dependencies. Audio callbacks stay
minimal and hand buffers to the async world via `AsyncStream`; shared state
lives in actors; the UI reads an `@Observable` `AppModel` on the main actor.

## Components

- **Audio/** — `AudioCapture` (mic via `AVAudioEngine` + system via
  `ScreenCaptureKit`, tagged by origin, per-channel level/health events,
  digital-silence detection and bounded system-stream recovery, opt-in AEC),
  `AudioConverter`, `MeetingRecorder` (writes two timestamp-synced AAC-LC `.m4a`
  files at 48 kHz/128 kbps for later playback), `MeetingPlayer` (two
  `AVAudioPlayer`s synced via
  `deviceCurrentTime`), `WaveformGenerator` (background amplitude envelope for
  the player UI), `AudioImportService` (read-only source import and portable
  AAC/M4A normalization), and `ExternalAudioDropReceiver` (copies promised
  drag-and-drop files before their temporary representation expires).
- **STT/** — provider abstraction with `NativeTranscriber`
  (`SpeechAnalyzer`/`SpeechTranscriber`, default and on-device) or opt-in
  `DeepgramTranscriber` (Nova-3 WebSocket, continuous mono PCM16 resampling,
  endpointed partial/final assembly and Keychain credential), plus
  `PrerecordedAudioTranscriber` (native file ranges or Deepgram batch utterances
  with diarization), plus
  `TranslationPipe` (feeds Apple `Translation` from the `.translationTask`).
- **Bus/** — `TranscriptBus` actor: fan-out `AsyncStream`, durable turn context,
  incremental cursors and correction updates.
- **Brain/** — `ClaudeClient` (locates the `claude` CLI), `ClaudeSession`
  (a long-lived `claude -p` streaming-json process, prewarmed, isolated cwd +
  hooks/user settings/tools/MCP disabled), `DeepSeekSession` (direct DeepSeek HTTP/SSE, stateless,
  non-thinking; keyed via `DeepSeekCredential` in the Keychain, see
  [ADR 0013](adr/0013-deepseek-coach-via-direct-api.md)) — both behind the
  `CoachSession` protocol, `Summary` and `Coaching` lanes, `SessionPostProcessor`
  (structured session review, follow-ups and questions), `Prompts` (expert-panel
  coach persona + per-mode playbooks, see [ADR 0011](adr/0011-expert-coach-persona-and-playbooks.md)).
- **Context preflight** — reusable `MeetingContext` documents are selected per
  profile/session; `ContextGlossaryGenerator` asks the chosen LLM for bounded
  Nova-3 keyterms before capture, reusing a content-addressed local cache when
  inputs are unchanged ([ADR 0024](adr/0024-reusable-contexts-and-preflight-glossary.md)).
- **Model/** — `AppModel` (state + commands), `SessionCoordinator` (wires
  capture → STT → bus → lanes → UI, partial/final echo dedup, independently
  swappable coach/minutes models, detected conversation styles, high-confidence
  semantic triggers, user-controlled navigable cards, incremental structured
  minutes, latest-pending coalescing, independent capture/STT
  watchdog recovery, provider failover, latency telemetry, recording and training),
  `TrainingCoordinator` (voice interviewer for practice/e2e testing),
  `HotkeyManager` (global ⌥Space show/hide), `SessionBrief` (+ `BriefStore`),
  reusable `BriefProfile`s, `MemoryNote` (the base entity for written and recorded
  experiences; `SessionRecord` is a migration alias), `NoteDocument` (canonical
  Markdown/frontmatter), `MarkdownBlockDocument` (transient visual block projection),
  `ProjectWorkspaceStore` (Project folders and `project.md`),
  `SessionArchive`/`SessionStore` (recursive file-first persistence and migration),
  `ExternalAudioInbox` (atomic App Group handoff shared with the audio-only
  Share Extension), `ImportMeetingAudioIntent` (Shortcuts ingress),
  `SessionKnowledgeIndex` (lexical fallback), `SemanticMemoryIndex` (rebuildable
  SQLite projection with FTS5/BM25 and sqlite-vec),
  `RelevantMemoryContextBuilder` (bounded opt-in Coach snapshot), evidence-linked decisions
  and actions, and stable `KnowledgeProject`/`KnowledgePerson` entities,
  `LiveHealthMonitor`/`SessionIntegrityReport` metadata-only health policies, `Types`.
- **Views/** — glance-first SwiftUI: `HeaderBar` with live channel meters,
  compact `QuestionBanner`, user-controlled `CoachingPane`, compact live health,
  `MeetingPanel` (passive-mode status when the coach is off), `TranscriptPane`,
  `SummaryPane`, `BriefEditor`, `SessionSidebar`, `MemoryNoteEditor`,
  `MarkdownBlockEditor`/`MarkdownBlockTextView`, `SessionWorkspaceView`
  (+ `WaveformPlayerView` and the live transport),
  `AboutView`, `Theme`, and `Highlighter` (on-device `NaturalLanguage` tiering of
  translated lines).

## Session modes

`Mode`: `interview` / `sales` / `difficult` / `meeting` / `recording` / `custom`.
Recent final turns refine the live conversation style to interview, one-on-one,
technical, sales or open meeting. Automatic coaching is limited to
high-confidence opportunities; `recording` is the sole live-passive mode. See
[ADR 0025](adr/0025-adaptive-live-experience-and-session-review.md).

`trainingMode` is an orthogonal toggle (any non-passive mode): a
`TrainingCoordinator` session plays the interviewer, speaking questions via
`AVSpeechSynthesizer` that get captured back through the app's own
`ScreenCaptureKit` stream (`excludesCurrentProcessAudio = false`) — so it's a
real exercise of the full capture→STT→translate→coach path, not a mock
([ADR 0009](adr/0009-training-mode-voice-interviewer.md)).

## Persistence & history

The canonical corpus is a normal filesystem tree under the user-selected root:

```text
<root>/
├── _Inbox/
│   └── <note-date-id>/
│       ├── note.md
│       ├── session.json
│       └── attachments/
└── <project-slug-id>/
    ├── project.md
    └── <note-date-id>/
        ├── note.md
        ├── session.json
        ├── self.m4a
        ├── other.m4a
        └── attachments/
```

`note.md` frontmatter and its delimited user body are canonical for title, type,
labels, Project relationship and written content. `project.md` is canonical
Project metadata. `session.json` remains a structured sidecar for transcripts,
Coach cards, evidence, minutes and other lossless machine state; `session.md` is
written only as a pre-1.0 compatibility mirror. `SessionStore` recursively loads
the tree, merges canonical Markdown fields over the sidecar, and idempotently
migrates top-level legacy sessions into `_Inbox` or their Project folder. Reopening
the app reloads filesystem edits.

On `stop()`, `MeetingRecorder` has already written synchronized `self.m4a` and
`other.m4a` beside the Note. The sidecar stores only portable relative folder
identity, never an absolute path. `SessionSidebar` keeps the complete library,
Project and label filters visible; `MemoryNoteEditor` provides native visual block
editing with an exact Markdown source mode;
`SessionWorkspaceView` preserves the same coach/summary/transcript navigation
after the event, plus timeline notes,
takeaways, editable timestamped notes, named participants, auditable transcript
corrections, editable decisions/open questions/follow-up, integrity diagnostics
and persisted post-session generation. `recordingStartedAt` anchors
transcript seeking to the audio clock. Legacy `.caf` and Application Support
JSON/audio are still discovered and played back during migration. Deleting a session removes
its complete directory and any legacy counterpart.

Audio arriving through the file picker, document-open, drag-and-drop, Shortcuts
or **Voice Memos → Share → CueMe** creates a passive imported record in the same
archive. Public handoffs converge on an atomic shared inbox; CueMe never scans
Apple's private Voice Memos library. The selected STT provider transcribes the
recording before the normal review lane extracts minutes and actions. The
sidebar's local hybrid index searches timestamped transcript, topic, decision,
action, question, note and artifact chunks with date and session-type filters.
Files remain canonical while SQLite is rebuildable; evidence links
seek back to supporting audio, and sessions join project/person timelines
([ADR 0026](adr/0026-imported-audio-and-local-knowledge-search.md),
[ADR 0027](adr/0027-supported-external-audio-ingress.md),
[ADR 0028](adr/0028-evidence-first-longitudinal-semantic-memory.md)).

## Runtime & hosting

Native macOS 26 app (Apple Silicon). No app-owned backend. The default LLM runs
through the user's local **Claude Code CLI** (`claude -p`); an opt-in DeepSeek
coach calls its configured API directly. STT is on-device by default; selecting
Deepgram sends the two live PCM streams
to Nova-3. Translation remains on-device in either configuration.

## Observability & quality

- Build/test gate: `xcodebuild … test` on GitHub's `macos-26` runner, using an
  ad-hoc-signed test host. The same build and XCTest gates run locally before
  push. See [Getting Started](GETTING-STARTED.md).
- Structural health gated by [Sentrux](sentrux.md).
- XCTest target covers provider fallback, coach parsing, recording-clock
  compatibility, transcript heuristics, per-channel silence detection, provider
  failover and a deterministic virtual 60-minute soak.
- `CueMeUITests` launches the real macOS app with isolated meeting fixtures and
  a temporary sqlite-vec database. It exercises semantic history search,
  evidence-backed review navigation, Project timelines, capture/recording/Coach,
  the home/profile surface, visual block and Markdown-source authoring, rename/labels, generated titles
  and theme selection through the UI without modifying the user's archive.
- Logging via `OSLog` (`subsystem: "CueMe"`).
- Releases: `release-please` (Conventional Commits → versioned CHANGELOG + GitHub
  Release on merge); `.dmg` built and attached manually via `scripts/package.sh`
  (see [Packaging](PACKAGING.md)).

## Security model

- Claude auth stays in the CLI. Optional DeepSeek and Deepgram keys are stored
  as separate macOS Keychain items.
- Native STT audio never leaves the device. When Deepgram is explicitly selected,
  live 16 kHz PCM and configured keyterms are sent over authenticated TLS
  WebSockets; translation stays on-device.
- Coaching/summary text is sent to the selected provider: Anthropic through the
  user's isolated CLI session or DeepSeek through direct HTTPS. CLI sessions run
  from an empty cwd and the coach prompt walls off ambient context.
- Selected reusable contexts are local at rest. Their content is sent only to
  the explicitly selected LLM for glossary generation and to the configured
  coach/minutes provider as an explicit session truth source.
- When **Use relevant memory in Coach** is enabled, local hybrid search selects
  at most five user-owned Notes and creates a 12,000-character session snapshot.
  That text is sent to the selected Coach provider as grounded personal memory;
  disabling the toggle sends none of it. The provider never receives the SQLite
  database or automatic access to the filesystem.
- Recorded audio (`.m4a`, with legacy `.caf` playback) is never uploaded as an
  archive — it is written locally and only read back by `MeetingPlayer` for
  in-app playback.
- Permissions: Microphone (required) and Screen & System Audio Recording
  (optional, for the other party). Non-sandboxed dev build; hardened runtime on;
  stable `DEVELOPMENT_TEAM` signing so TCC grants persist across builds. The
  Share Extension uses the same signing team and App Group as the main app.

## Related docs

- [Vision](VISION.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md) · [Sentrux](sentrux.md)
