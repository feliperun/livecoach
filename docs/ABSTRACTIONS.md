# Abstractions

> The vocabulary of this codebase: the core types/modules and the contracts
> between them. Read this before adding a new module — reuse an abstraction
> before inventing one.

## Core layers

Data flows one direction, top to bottom; each layer only knows the one below it.

1. **Capture** (`Audio/AudioCapture`) — turns hardware into `AudioChunk`
   (speaker-tagged, timestamped PCM buffers). Two independent sources: mic
   (`AVAudioEngine`, tag `.self`) and system audio (`ScreenCaptureKit`, tag
   `.other`). It also emits `AudioCaptureEvent` level/health signals and owns
   bounded recovery. This is the *only* place that knows about audio hardware.
2. **Understand** (`STT/`, `Audio/MeetingRecorder`) — turns `AudioChunk` into
   meaning or a persisted artifact: `NativeTranscriber` → `TranscriptEvent`
   (on-device `SpeechAnalyzer`), `TranslationPipe` → translated text (on-device
   `Translation`), `MeetingRecorder` → two timestamp-synced `.caf` files.
3. **Bus** (`Bus/TranscriptBus`) — the single actor all `TranscriptEvent`s pass
   through. Fans out to subscribers (coach, summary, UI) and keeps the rolling
   window (`[Turn]`) that lanes read for context. Nothing downstream talks to
   STT directly.
4. **Brain** (`Brain/`) — turns the bus's window into LLM output. A lane holds an
   `any CoachSession`: either a warm `claude -p` process (`ClaudeSession`) or a
   direct DeepSeek HTTP/SSE session (`DeepSeekSession`, keyed, non-thinking) —
   `ClaudeClient.makeCoachSession` picks by the selected `CoachModel`.
   `CoachingLane`/`SummaryLane` wrap a session with a specific prompt
   (`Prompts.swift`) and parsing (`CoachCardParser`), backend-agnostic.
   `TrainingCoordinator` is a sibling brain that *speaks* (via
   `AVSpeechSynthesizer`) instead of coaching.
5. **Orchestration** (`Model/SessionCoordinator`) — the only thing that wires
   layers 1–4 together for a live session: starts capture, routes chunks to STT
   and the recorder, triggers the coach on turn-end, applies echo dedup. Lives
   on `@MainActor`; owns no UI state itself.
6. **State** (`Model/AppModel`) — the single `@Observable` source of truth the
   UI reads. `SessionCoordinator` pushes into it; it never reaches back into the
   coordinator except through the command methods (`start()`, `stop()`, `ask()`).
7. **Persistence** (`Model/SessionRecord` + `SessionStore`, `Audio/MeetingRecording`)
   — snapshots a finished session to disk (JSON + audio files) and reads it back
   for history browsing. Pure data + file I/O, no live-session dependencies.
8. **Views** (`Views/`) — SwiftUI only. Reads `AppModel`/`SessionRecord`, calls
   `AppModel` command methods, never touches `SessionCoordinator` or the audio
   layer directly.

## External systems

| System | Boundary type | Notes |
|---|---|---|
| Microphone | `AVAudioEngine` in `AudioCapture` | Tagged `.self`. |
| System/app audio | `ScreenCaptureKit` in `AudioCapture` | Tagged `.other`; needs Screen & System Audio Recording permission; `excludesCurrentProcessAudio` toggles for training mode self-capture. |
| Speech-to-text | `SpeechAnalyzer`/`SpeechTranscriber` in `NativeTranscriber` | On-device, macOS 26 only. |
| Translation | `Translation` framework via `TranslationPipe` | On-device; `TranslationSession` is non-Sendable, confined via `nonisolated(unsafe)` at the `.translationTask` boundary — don't let it cross actors any other way. |
| Text-to-speech | `AVSpeechSynthesizer` in `TrainingCoordinator` | Speaks the interviewer's questions in training mode. |
| LLM brain (default) | Claude Code CLI (`claude -p`, stream-json) via `ClaudeSession` | No API key — reuses the user's own CLI login. See [ADR 0005](adr/0005-llm-brain-via-claude-cli.md). |
| LLM brain (DeepSeek) | Direct DeepSeek HTTP/SSE via `DeepSeekSession` | Opt-in coach models (`deepseek-v4-pro`/`-flash`); API key in Keychain (`DeepSeekCredential`), non-thinking for latency. See [ADR 0013](adr/0013-deepseek-coach-via-direct-api.md). |
| Word-class tagging | `NaturalLanguage`/`NLTagger` in `Highlighter` | On-device; tiers translated text for fast scanning. |
| Audio playback | Two `AVAudioPlayer`s in `MeetingPlayer` | Synced via a shared `deviceCurrentTime` anchor, not a mixer graph. |
| CV import | `PDFKit` in `BriefEditor` | Extracts text from a pasted/imported résumé. |
| Persistence | `FileManager` + `JSONEncoder`/`Decoder` in `SessionStore`/`BriefStore` | Application Support, non-sandboxed. |
| Packaging | `xcodebuild` + `hdiutil` in `scripts/package.sh` | Local only — see [Getting Started](GETTING-STARTED.md) and [Packaging](PACKAGING.md). |

## Contracts & invariants

- **Speaker is known by capture origin, never inferred from voice.** `.self` =
  mic, `.other` = system audio. No diarization anywhere in the codebase
  ([ADR 0007](adr/0007-speaker-by-origin-and-echo-dedup.md)).
  Partial and final text may still echo across physical channels; confirmed echo
  is removed from both the UI and the rolling `TranscriptBus` context.
- **The coach's only source of truth about the user is the brief + CV.** The
  system prompt explicitly forbids using ambient CLI context; never weaken this
  when editing `Prompts.coachSystem` ([ADR 0008](adr/0008-coach-ux-and-context-safety.md)).
  `Mode.isPassive` (meeting mode) means the coach is never constructed or
  triggered at all — see `SessionCoordinator.buildBrain`/`consumeBusForCoaching`.
- **Coach output is always the 4-line card format or the literal string `NADA`.**
  `CoachCardParser` depends on the exact labels (`GUIA:`/`DIGA:`/`PT:`/`KEY:`); a
  prompt change that alters the format must update the parser in the same commit.
- **Manual coach input has its own lane.** Automatic STT activity cannot cancel a
  manual request. Live requests use the fast tier and coalesce while one provider
  call is in flight; explicit questions bypass debounce and get a deterministic
  local cue ([ADR 0016](adr/0016-observable-non-cancelling-coach-lanes.md),
  [ADR 0017](adr/0017-fast-coach-two-speed.md)).
- **Every `AudioChunk` carries a real capture timestamp**, not append order.
  `MeetingRecorder` depends on this to silence-pad two independent files back
  into wall-clock sync ([ADR 0012](adr/0012-meeting-mode-and-synced-recording.md)) —
  don't default `AudioChunk.ts` away from `Date()` at the capture call site.
  Coach/echo-dedup logic also key off it.
- **Audio replay uses the recorder's clock, not the Start-button clock.**
  `SessionRecord.recordingStartedAt` is persisted with the stop result; legacy
  records fall back to `startedAt`.
- **A session is never silently healthy.** Mic and system channel states are
  independent; digital-zero mic data and an interrupted `SCStream` must be
  surfaced and repaired or remain visibly unavailable ([ADR 0014](adr/0014-per-channel-capture-health.md)).
- **Recordings are located by session id, never by a stored path.**
  `MeetingRecording.directory(for:)` derives the path from the UUID; exported
  session JSON stays portable across machines/reinstalls.
- **`ClaudeSession` always spawns from an isolated empty cwd with hooks
  disabled.** This is the containment boundary against the CLI leaking the
  *user's own* project context into the coach's output.
- **Translation objects never cross actor isolation implicitly.** `TranslationSession`
  (Apple's, non-Sendable) is used only inside the `.translationTask` closure;
  `TranslationPipe` is the Sendable queue on the other side of that boundary.

## Quality & governance

- Structural limits live in `.sentrux/rules.toml`; regression baseline in `.sentrux/baseline.json`.
- Architecture decisions are recorded as [ADRs](adr/README.md) — read them before
  touching audio capture, the CLI session lifecycle, or the coach prompt.

## Adding a new module — checklist

- [ ] Does an existing abstraction already cover this? Reuse it.
- [ ] Inputs/outputs validated at the boundary.
- [ ] Respects the layer direction (§ Core layers) — no upward calls.
- [ ] Unit tests close to the change.
- [ ] `sentrux gate .` shows no degradation.
- [ ] ADR if it introduces a cross-cutting pattern or external dependency.
