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
                                                          Translation   Summary    Coaching       AppModel
                                                          (on-device,   (haiku,    (sonnet/opus,  (@Observable,
                                                           TranslationPipe) ~30s)   streaming,      MainActor)
                                                                                    warm+prewarmed)     │
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
  `ScreenCaptureKit`, tagged by origin, echo-dedup aware, opt-in AEC),
  `AudioConverter`, `MeetingRecorder` (writes two timestamp-synced `.caf` files
  for later playback), `MeetingPlayer` (two `AVAudioPlayer`s synced via
  `deviceCurrentTime`), `WaveformGenerator` (background amplitude envelope for
  the player UI).
- **STT/** — `NativeTranscriber` (`SpeechAnalyzer`/`SpeechTranscriber`, on-device),
  `TranslationPipe` (feeds Apple `Translation` from the `.translationTask`).
- **Bus/** — `TranscriptBus` actor: fan-out `AsyncStream` + rolling window.
- **Brain/** — `ClaudeClient` (locates the `claude` CLI), `ClaudeSession`
  (a long-lived `claude -p` streaming-json process, prewarmed, isolated cwd +
  hooks disabled), `DeepSeekSession` (direct DeepSeek HTTP/SSE, stateless,
  non-thinking; keyed via `DeepSeekCredential` in the Keychain, see
  [ADR 0013](adr/0013-deepseek-coach-via-direct-api.md)) — both behind the
  `CoachSession` protocol, `Summary` and `Coaching` lanes, `Prompts` (expert-panel
  coach persona + per-mode playbooks, see [ADR 0011](adr/0011-expert-coach-persona-and-playbooks.md)).
- **Model/** — `AppModel` (state + commands), `SessionCoordinator` (wires
  capture → STT → bus → lanes → UI, echo dedup, coach triggering, recording,
  training), `TrainingCoordinator` (voice interviewer for practice/e2e testing),
  `HotkeyManager` (global ⌥Space show/hide), `SessionBrief` (+ `BriefStore`),
  `SessionRecord` (+ `SessionStore`, history persistence), `Types`.
- **Views/** — compact SwiftUI: `HeaderBar`, `QuestionBanner`, `CoachingPane`,
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
id at read time). Deleting a session removes both the JSON and its recording.

## Runtime & hosting

Native macOS 26 app (Apple Silicon). No backend. The LLM runs through the user's
local **Claude Code CLI** (`claude -p`), reusing their existing login — no API
key. STT and translation are on-device.

## Observability & quality

- Build gate: `xcodebuild … build` (macOS 26 SDK), **local only** — GitHub's CI
  runners lack the macOS 26 SDK, so `.github/workflows/quality.yml` runs Sentrux
  alone. See [Getting Started](GETTING-STARTED.md).
- Structural health gated by [Sentrux](sentrux.md).
- Logging via `OSLog` (`subsystem: "CueMe"`).
- Releases: `release-please` (Conventional Commits → versioned CHANGELOG + GitHub
  Release on merge); `.dmg` built and attached manually via `scripts/package.sh`
  (see [Packaging](PACKAGING.md)).

## Security model

- No secrets stored by the app; the CLI holds the user's Claude auth.
- STT audio never leaves the device; translation is on-device.
- Coaching/summary text is sent to Anthropic through the user's own CLI session.
  CLI sessions run from an isolated empty cwd and the coach prompt walls off any
  ambient context so no local project/CV data leaks in unintentionally.
- Recorded audio (`.caf` files) never leaves the device — it's written locally
  and only read back by `MeetingPlayer` for in-app playback.
- Permissions: Microphone (required) and Screen & System Audio Recording
  (optional, for the other party). Non-sandboxed dev build; hardened runtime on;
  stable `DEVELOPMENT_TEAM` signing so TCC grants persist across builds.

## Related docs

- [Vision](VISION.md) · [Abstractions](ABSTRACTIONS.md) · [ADRs](adr/README.md) · [Sentrux](sentrux.md)
