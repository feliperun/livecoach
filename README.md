# CueMe

[![quality](https://github.com/feliperun/cueme/actions/workflows/quality.yml/badge.svg)](https://github.com/feliperun/cueme/actions/workflows/quality.yml)
[![release-please](https://github.com/feliperun/cueme/actions/workflows/release-please.yml/badge.svg)](https://github.com/feliperun/cueme/actions/workflows/release-please.yml)
![platform](https://img.shields.io/badge/macOS-26-blue)
![swift](https://img.shields.io/badge/Swift-6-orange)
![license](https://img.shields.io/badge/license-MIT-green)

**🌐 [feliperun.github.io/cueme](https://feliperun.github.io/cueme/)**

<p align="center">
  <img src="docs/assets/demo.gif" alt="CueMe live: the interlocutor's question appears with translation, then the coach card streams in with what to say and the key words" width="620">
</p>
<p align="center">
  <img src="docs/assets/demo.png" alt="CueMe — real-time conversation copilot for macOS" width="900">
</p>

Real-time conversation copilot for macOS — a native SwiftUI app that listens to
both sides of a live conversation, transcribes and translates on the fly,
summarizes what's been said, and gives you contextual coaching as you speak.
Built for **mock interviews**, sales calls, and difficult conversations.

100% native Swift. No webview or virtual audio driver. Claude is keyless by
default; DeepSeek is an explicit, API-keyed option.
The "brain" runs through your local **Claude Code CLI** (your existing
subscription/login), so there's nothing to configure and no key to leak.

> ⚠️ **Ethics/use**: great for practice, mock interviews, and preparing for
> hard conversations. Some real-world settings have rules about live assistance —
> know the context you're in. See [Responsible use](#responsible-use).

---

## What it does

- **Captures both sides natively** — your mic (`AVAudioEngine`) + the other
  person's audio from the system (`ScreenCaptureKit`, e.g. Zoom/Meet). Because
  the two sources are separate, *who spoke* is known by origin — no diarization.
  Acoustic-echo dedup keeps it working even on speakers (no headphones).
- **Live transcription** with speaker labels, in a compact always-on-top window.
- **Line-by-line translation** via Apple's on-device **Translation** framework
  (~100–200ms, no key), with the key words bolded for fast scanning.
- **Rolling summary** of what's been said so far.
- **Contextual coaching** — the "friend beside you": "they asked X → answer like
  this", a ready-to-say phrase in the conversation language + your native
  translation + key vocabulary. Terse and emoji-cued for reading under pressure.
- **Session brief** (mode: interview / sales / difficult / meeting / custom) with
  your full **CV/résumé** (paste or import .pdf/.md/.txt) so hints point at your
  real stories. Plus a manual question box for mid-conversation.
- **Meeting mode** for free-topic conversations — coaching turns off (it doesn't
  fit an open agenda) while transcription, translation, and the rolling summary
  keep running.
- **Session recording**, on by default — the original audio (both sides) is
  recorded in sync with the transcript. Revisit any past session in the
  **history**: a visual waveform player where tapping a transcript line seeks
  and plays the audio from that moment, and the active line highlights live as
  it plays back. Sessions can be copied/exported as JSON.

Example (interview in English, native Portuguese):

```
[Interlocutor] So, why do you want to leave your current company?
  ↳ Então, por que você quer sair da sua empresa atual?

Coach ──────────────────────────────────────────────
GUIA:  Foque em crescimento, não em problemas. Nunca fale mal do empregador atual.
DIGA:  I'm looking for a role with more end-to-end ownership and technical growth.
  ↳    Busco um cargo com mais autonomia ponta a ponta e crescimento técnico.
KEYTERMS: end-to-end ownership · technical growth · scope
```

---

## Requirements

- **macOS 26 (Tahoe)** — uses the new on-device `SpeechAnalyzer` / `SpeechTranscriber`.
- **Xcode 26** (Swift 6.2).
- **Claude Code CLI** installed and logged in — the coaching/translation/summary
  brain shells out to `claude -p`. Verify with:
  ```sh
  claude --version   # should print a version
  claude -p "hi"     # should answer (i.e. you're logged in)
  ```
  Install: https://docs.claude.com/en/docs/claude-code

No Anthropic API key is used — the default coach reuses your Claude CLI login.
DeepSeek V4 is optional and stores its key in the macOS Keychain; when selected,
the coach sends the brief/CV and recent conversation context to that endpoint.

---

## How to run

1. Open the project:
   ```sh
   open CueMe.xcodeproj
   ```
2. In Xcode, select the **CueMe** scheme and press **⌘R**.
3. On first launch, grant permissions when prompted:
   - **Microphone** — required (your side of the conversation).
   - **Screen & System Audio Recording** — optional but needed to hear the
     *other* person's audio (Zoom/Meet/system). Grant it in
     *System Settings → Privacy & Security → Screen & System Audio Recording*,
     then relaunch. Without it, the app runs mic-only.

If Xcode complains about signing, set your team under
*Signing & Capabilities*, or build with signing disabled for local runs.

---

## Full test walkthrough

A complete end-to-end test of all four lanes (transcription, translation,
summary, coaching):

1. **Set the brief** (bottom bar): Mode = *Entrevista*, Conversa = `en-US`,
   Nativo = `pt-BR`, STT = *Nativo (on-device)*.
2. Press **Iniciar**. Approve the mic prompt. The menu-bar mic dot turns on and
   the status reads **Ao vivo**. (First use of a language downloads its on-device
   model — needs network once.)
3. **Coaching (no audio needed):** type a question in the bottom box, e.g.
   *"Why do you want to leave your current company?"*, and press **Perguntar**.
   Within a couple of seconds a coach card appears with GUIA / DIGA / translation
   / KEYTERMS. Send a second question to see the warm session respond faster.
4. **Live transcription + translation:** with a headset/Zoom call running (and
   Screen Recording granted), have the other side speak. Their line appears
   under `[Interlocutor]` with a `↳` translation, and a coach card is generated
   automatically at the end of their turn. Speak yourself to see `[Você]` lines.
5. **Summary:** after ~30s of conversation, the top-right pane fills with up to
   5 bullets and refreshes as things progress.
6. **Silêncio** toggles the coach off (transcription keeps running).

First call to each lane pays a one-time CLI cold start (~5–10s); subsequent
calls reuse a warm `claude` process (~1–2s).

---

## How it works

```
AVAudioEngine (mic) ─────┐
                         ├─▶ AudioConverter (→16k mono) ─▶ NativeTranscriber (SpeechAnalyzer)
ScreenCaptureKit (sys) ──┘                                          │
                                                                    ▼
                                                             TranscriptBus (actor)
                     ┌──────────────────────┬─────────────────────┬─────────────┐
                     ▼                      ▼                     ▼             ▼
        Apple Translation (on-device)   Summary (fast)    Fast Coach (Flash/Sonnet, SwiftUI
        — transcript                    separate lane      DIGA-first streaming)
                     └──────────────────────┴─────────────────────┘
                          provider = isolated Claude CLI or direct DeepSeek SSE
```

- **Two-speed brain.** Live hints use the fast tier (DeepSeek Flash or Sonnet),
  while manual asks keep the selected deep tier. Claude uses isolated `claude -p`
  processes; DeepSeek uses direct SSE HTTP. Separate fast sessions produce summary.
- **Translation is off the LLM** — Apple's on-device `Translation` framework, so
  the coach LLM is never blocked by per-line translation.
- **Speaker by origin.** Mic = `self`, system audio = `other`. No diarization;
  echo dedup + a question heuristic keep it usable in mic-only / speaker setups.
- **Swift Concurrency throughout.** Actors for shared state, `AsyncStream`
  fan-out, cooperative cancellation for the coach (a new turn cancels the old).

### Project layout

```
CueMe/
├── Audio/    AudioCapture (mic + ScreenCaptureKit, echo dedup), AudioConverter,
│             MeetingRecorder (synced dual-file recording), MeetingPlayer,
│             WaveformGenerator
├── STT/      SttProvider, NativeTranscriber (SpeechAnalyzer), TranslationPipe
├── Bus/      TranscriptBus (actor + fan-out + rolling window)
├── Brain/    ClaudeClient (CLI resolver), ClaudeSession (warm process),
│             Summary / Coaching lanes, Prompts
├── Model/    AppModel (@Observable), SessionCoordinator, SessionBrief,
│             SessionRecord (history persistence), Types
└── Views/    RootView, HeaderBar, QuestionBanner, CoachingPane, MeetingPanel,
              Transcript, Summary, BriefEditor, HistoryView,
              WaveformPlayerView, Highlighter (NaturalLanguage), Theme
```

---

## Responsible use

This is a practice and preparation tool. In live, real processes (interviews,
exams, etc.) some organizations prohibit real-time assistance — respect the
rules of the context you're in. The authors provide this for legitimate training
and accessibility use.

## Privacy

- Speech-to-text is **on-device** (`SpeechAnalyzer`) — audio doesn't leave your
  Mac for transcription.
- Translation stays on-device. Coach and summary use the selected provider:
  Claude CLI by default, or DeepSeek when explicitly configured. DeepSeek keys
  live in the macOS Keychain.

## License

MIT — see [LICENSE](LICENSE).
