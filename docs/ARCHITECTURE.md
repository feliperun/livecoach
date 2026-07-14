# Architecture

> Current-state summary. ADRs in [adr/](adr/README.md) hold the history and the
> *why*; this file reflects only **active** decisions. Update it in the same
> commit as any structural change.

## High-level flow

```
AVAudioEngine (mic, .self) ─────┐
                                ├─▶ AudioConverter (→16k mono PCM16) ─▶ NativeTranscriber (SpeechAnalyzer)
ScreenCaptureKit (system, .other)┘        │                                    │
                                           ▼                                   ▼
                                    MeetingRecorder                     TranscriptBus (actor)
                                  (synced dual .caf files,     ┌────────────┬────────────┬────────────┐
                                   opt-out, on by default)     ▼            ▼            ▼            ▼
                                                          Translation   Summary    Fast Coach     AppModel
                                                          (on-device,   (fast,     (Flash/Sonnet, (@Observable,
                                                           TranslationPipe) separate) DIGA-first) MainActor)
                                                                                                        ▼
                                              TrainingCoordinator ──speaks (TTS)──▶ (captured back as .other)
                                              (voice interviewer, opt-in)
                                                                                                        │
                                                                                                        ▼
                                                                                                  SwiftUI (compact)
                                                                                                        │
                                                                                          on stop() ────┘
                                                                                                        ▼
                                                                              SessionRecord → SessionStore (JSON + audio)
                                                                                        │
                                                                                        ▼
                                                                    HistoryView / WaveformPlayerView (browse + replay)
```

Single Swift process, zero third-party dependencies. Audio callbacks stay
minimal and hand buffers to the async world via `AsyncStream`; shared state
lives in actors; the UI reads an `@Observable` `AppModel` on the main actor.

## Components

- **Audio/** — `AudioCapture` (mic via `AVAudioEngine` + system via
  `ScreenCaptureKit`, tagged by origin, per-channel level/health events,
  digital-silence detection and bounded system-stream recovery, opt-in AEC),
  `AudioConverter`, `MeetingRecorder` (writes two timestamp-synced `.caf` files
  for later playback), `MeetingPlayer` (two `AVAudioPlayer`s synced via
  `deviceCurrentTime`), `WaveformGenerator` (background amplitude envelope for
  the player UI).
- **STT/** — `NativeTranscriber` (`SpeechAnalyzer`/`SpeechTranscriber`, on-device),
  `TranslationPipe` (feeds Apple `Translation` from the `.translationTask`).
- **Bus/** — `TranscriptBus` actor: fan-out `AsyncStream` + rolling window.
- **Brain/** — `ClaudeClient` (locates the `claude` CLI), `ClaudeSession`
  (a long-lived `claude -p` streaming-json process, prewarmed, isolated cwd +
  hooks/user settings/tools/MCP disabled), `DeepSeekSession` (direct DeepSeek HTTP/SSE, stateless,
  non-thinking; keyed via `DeepSeekCredential` in the Keychain, see
  [ADR 0013](adr/0013-deepseek-coach-via-direct-api.md)) — both behind the
  `CoachSession` protocol, `Summary` and `Coaching` lanes, `Prompts` (expert-panel
  coach persona + per-mode playbooks, see [ADR 0011](adr/0011-expert-coach-persona-and-playbooks.md)).
- **Model/** — `AppModel` (state + commands), `SessionCoordinator` (wires
  capture → STT → bus → lanes → UI, partial/final echo dedup, two-speed
  manual/live coach queues with urgent-question bypass, instant local cues,
  latest-pending coalescing, adaptive confidence gating, independent capture/STT
  watchdog recovery, provider failover, latency telemetry, recording and training),
  `TrainingCoordinator` (voice interviewer for practice/e2e testing),
  `HotkeyManager` (global ⌥Space show/hide), `SessionBrief` (+ `BriefStore`),
  reusable `BriefProfile`s, `SessionRecord` (+ `SessionStore`, history persistence),
  metadata-only runtime health/report policies, `Types`.
- **Views/** — glance-first SwiftUI: `HeaderBar` with live channel meters,
  compact `QuestionBanner`, latest-only `CoachingPane`,
  `MeetingPanel` (passive-mode status when the coach is off), `TranscriptPane`,
  `SummaryPane`, `BriefEditor`, `HistoryView` (+ `WaveformPlayerView`),
  `AboutView`, `Theme`, and `Highlighter` (on-device `NaturalLanguage` tiering of
  translated lines).

## Session modes

`Mode`: `interview` / `sales` / `difficult` / `meeting` / `custom`. All but
`meeting` get a coach persona + playbook ([ADR 0011](adr/0011-expert-coach-persona-and-playbooks.md)).
`meeting` is **passive** (`Mode.isPassive`) — free-topic conversations where
coaching doesn't apply: the coach session is never built or triggered, but
transcription/translation/summary/recording keep running
([ADR 0012](adr/0012-meeting-mode-and-synced-recording.md)).

`trainingMode` is an orthogonal toggle (any non-passive mode): a
`TrainingCoordinator` session plays the interviewer, speaking questions via
`AVSpeechSynthesizer` that get captured back through the app's own
`ScreenCaptureKit` stream (`excludesCurrentProcessAudio = false`) — so it's a
real exercise of the full capture→STT→translate→coach path, not a mock
([ADR 0009](adr/0009-training-mode-voice-interviewer.md)).

## Persistence & history

Every session is snapshotted on `stop()` to `Application Support/CueMe/`:
`sessions/<id>.json` (transcript, coach cards, summary, brief snapshot) via
`SessionStore`, and — if recording was on (default) — `recordings/<id>/{self,other}.caf`
via `MeetingRecorder`. `HistoryView` lists/browses past sessions; a session can
be copied/exported as JSON (no absolute paths embedded — audio is relocated by
id at read time). `recordingStartedAt` anchors transcript seeking to the audio
clock rather than the earlier UI-start clock. Deleting a session removes both
the JSON and its recording.

## Runtime & hosting

Native macOS 26 app (Apple Silicon). No app-owned backend. The default LLM runs
through the user's local **Claude Code CLI** (`claude -p`); an opt-in DeepSeek
coach calls its configured API directly. STT and translation are on-device.

## Observability & quality

- Build/test gate: `xcodebuild … test` on GitHub's `macos-26` runner, using an
  ad-hoc-signed test host. The same build and XCTest gates run locally before
  push. See [Getting Started](GETTING-STARTED.md).
- Structural health gated by [Sentrux](sentrux.md).
- XCTest target covers provider fallback, coach parsing, recording-clock
  compatibility, transcript heuristics, per-channel silence detection, provider
  failover and a deterministic virtual 60-minute soak.
- Logging via `OSLog` (`subsystem: "CueMe"`).
- Releases: `release-please` (Conventional Commits → versioned CHANGELOG + GitHub
  Release on merge); `.dmg` built and attached manually via `scripts/package.sh`
  (see [Packaging](PACKAGING.md)).

## Security model

- Claude auth stays in the CLI. An optional DeepSeek key is stored in Keychain.
- STT audio never leaves the device; translation is on-device.
- Coaching/summary text is sent to the selected provider: Anthropic through the
  user's isolated CLI session or DeepSeek through direct HTTPS. CLI sessions run
  from an empty cwd and the coach prompt walls off ambient context.
- Recorded audio (`.caf` files) never leaves the device — it's written locally
  and only read back by `MeetingPlayer` for in-app playback.
- Permissions: Microphone (required) and Screen & System Audio Recording
  (optional, for the other party). Non-sandboxed dev build; hardened runtime on;
  stable `DEVELOPMENT_TEAM` signing so TCC grants persist across builds.

## Related docs

- [Vision](VISION.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md) · [Sentrux](sentrux.md)
