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
   meaning or a persisted artifact: the selected `SttProvider` creates either
   `NativeTranscriber` (on-device `SpeechAnalyzer`) or `DeepgramTranscriber`
   (Nova-3 streaming) → `TranscriptEvent`, `TranslationPipe` → translated text (on-device
   `Translation`), `MeetingRecorder` → two timestamp-synced AAC-LC `.m4a` files.
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
   `SessionPostProcessor` parses durable review/follow-up output for saved sessions.
  `TrainingCoordinator` is a sibling brain that *speaks* (via
  `AVSpeechSynthesizer`) instead of coaching.
   `ContextGlossaryGenerator` is a bounded preflight brain: it turns selected
   local `MeetingContext` documents into cached Deepgram keyterms before capture.
5. **Orchestration** (`Model/SessionCoordinator`) — the only thing that wires
   layers 1–4 together for a live session: starts capture, routes chunks to STT
   and the recorder, triggers the coach on turn-end, applies echo dedup. Lives
   on `@MainActor`; owns no UI state itself.
6. **State** (`Model/AppModel`) — the single `@Observable` source of truth the
   UI reads. `SessionCoordinator` pushes into it; it never reaches back into the
   coordinator except through the command methods (`start()`, `stop()`, `ask()`).
7. **Persistence** (`SessionRecord`, `SessionArchive`/`SessionStore`,
   `Audio/MeetingRecording`) — snapshots a session into one portable directory:
   typed JSON, mandatory human-readable Markdown and synchronized audio. Notes,
   takeaways and generated artifacts rewrite both state representations.
   `SessionOrigin` records whether memory came from live capture, an audio file
   or a Voice Memos share; imported sources never persist their original absolute
   path. Public external handoffs converge on an atomic `ExternalAudioInbox`.
8. **Views** (`Views/`) — SwiftUI only. Reads `AppModel`/`SessionRecord`, calls
   `AppModel` command methods, never touches `SessionCoordinator` or the audio
   layer directly.

## External systems

| System | Boundary type | Notes |
|---|---|---|
| Microphone | `AVAudioEngine` in `AudioCapture` | Tagged `.self`. |
| System/app audio | `ScreenCaptureKit` in `AudioCapture` | Tagged `.other`; needs Screen & System Audio Recording permission; `excludesCurrentProcessAudio` toggles for training mode self-capture. |
| Speech-to-text | `SpeechAnalyzer`/`SpeechTranscriber` in `NativeTranscriber` | On-device, macOS 26 only. |
| Cloud speech-to-text (opt-in) | Deepgram Nova-3 WebSocket in `DeepgramTranscriber` | Separate stream per capture origin; key in Keychain; sends live PCM + keyterms. |
| Translation | `Translation` framework via `TranslationPipe` | On-device; `TranslationSession` is non-Sendable, confined via `nonisolated(unsafe)` at the `.translationTask` boundary — don't let it cross actors any other way. |
| Text-to-speech | `AVSpeechSynthesizer` in `TrainingCoordinator` | Speaks the interviewer's questions in training mode. |
| LLM brain (default) | Claude Code CLI (`claude -p`, stream-json) via `ClaudeSession` | No API key — reuses the user's own CLI login. See [ADR 0005](adr/0005-llm-brain-via-claude-cli.md). |
| LLM brain (DeepSeek) | Direct DeepSeek HTTP/SSE via `DeepSeekSession` | Opt-in coach models (`deepseek-v4-pro`/`-flash`); API key in Keychain (`DeepSeekCredential`), non-thinking for latency. See [ADR 0013](adr/0013-deepseek-coach-via-direct-api.md). |
| Word-class tagging | `NaturalLanguage`/`NLTagger` in `Highlighter` | On-device; tiers translated text for fast scanning. |
| Audio playback | Two `AVAudioPlayer`s in `MeetingPlayer` | Synced via a shared `deviceCurrentTime` anchor, not a mixer graph. |
| Imported audio | `AudioImportService` + `PrerecordedAudioTranscriber` | Read-only source; normalized M4A; native file STT or Deepgram batch. |
| External audio handoff | `CueMeShare` + `ImportMeetingAudioIntent` + `ExternalAudioInbox` | Audio-only Share Extension, Shortcuts, document-open and drop; no private Voice Memos scan. |
| CV import | `PDFKit` in `BriefEditor` | Extracts text from a pasted/imported résumé. |
| Persistence | `FileManager` + `JSONEncoder`/`Decoder` in `SessionStore`/`BriefStore`/`MeetingContextStore` | User-selectable session archive; briefs, reusable contexts and glossary cache in Application Support. |
| Packaging | `xcodebuild` + `hdiutil` in `scripts/package.sh` | Local only — see [Getting Started](GETTING-STARTED.md) and [Packaging](PACKAGING.md). |

## Contracts & invariants

- **Speaker is known by capture origin, never inferred from voice.** `.self` =
  mic, `.other` = system audio. No diarization anywhere in the codebase
  ([ADR 0007](adr/0007-speaker-by-origin-and-echo-dedup.md)).
  Partial and final text may still echo across physical channels; confirmed echo
  is removed from both the UI and the rolling `TranscriptBus` context.
- **STT providers preserve one session per capture origin.** Native and Deepgram
  must emit the same `TranscriptEvent` contract; switching providers cannot
  introduce diarization or merge mic/system audio.
- **The coach's only source of truth is the brief + selected contexts + CV.** The
  system prompt explicitly forbids using ambient CLI context; never weaken this
  when editing `Prompts.coachSystem` ([ADR 0008](adr/0008-coach-ux-and-context-safety.md)).
  Context documents are user-authored and explicit; ambient CLI context remains
  forbidden. `Mode.isPassive` means the coach is never constructed or
  triggered at all — see `SessionCoordinator.buildBrain`/`consumeBusForCoaching`.
- **Coach output is always the 4-line card format or the literal string `NADA`.**
  `CoachCardParser` depends on the exact labels (`GUIA:`/`DIGA:`/`PT:`/`KEY:`); a
  prompt change that alters the format must update the parser in the same commit.
- **Automatic coach cards are opportunities, not a feed.** Recent final turns
  choose a `ConversationStyle`; only high-confidence moments trigger a request.
  The active card changes only through explicit use, dismissal or navigation,
  while newer results wait in the bounded history ([ADR 0025](adr/0025-adaptive-live-experience-and-session-review.md)).
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
- **New recordings use portable, speech-quality AAC-LC.** Each speaker is stored
  separately as mono 48 kHz/128 kbps `.m4a`; STT keeps its independent 16 kHz
  conversion. `MeetingRecording` must continue resolving legacy `.caf` files.
- **Imported audio is passive session memory.** It has an explicit non-live
  `SessionOrigin`, no Coach cards and no Coach workspace. The original source is
  read-only; the archive owns a portable M4A copy ([ADR 0026](adr/0026-imported-audio-and-local-knowledge-search.md)).
- **Voice Memos integration uses public handoff surfaces only.** Share Extension,
  Shortcuts, document-open and drag-and-drop converge on an atomic inbox; no code
  enumerates Apple's private library ([ADR 0027](adr/0027-supported-external-audio-ingress.md)).
- **Knowledge search never calls an external service.** The in-memory index is
  rebuilt from durable `SessionRecord` fields and applies date/type filters
  before lexical scoring. Selecting Deepgram for import affects transcription,
  not search.
- **A session is never silently healthy.** Mic and system channel states are
  independent; digital-zero mic data and an interrupted `SCStream` must be
  surfaced and repaired or remain visibly unavailable ([ADR 0014](adr/0014-per-channel-capture-health.md)).
  `LiveHealthMonitor` also derives recording, STT, Coach and summary status from
  existing runtime state; it does not own or duplicate recovery.
- **Recordings are located by a portable session directory name, never by an
  absolute stored path.** `SessionRecord.archiveFolderName` combines timestamp
  and short UUID; `MeetingRecording` resolves it against the current archive root
  and falls back to the legacy UUID directory.
- **Markdown mirrors durable session state.** Any saved mutation to notes,
  review, takeaways, summary or generated artifacts goes through `SessionStore.save`,
  which rewrites `session.json` and `session.md` together.
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
