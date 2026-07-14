# Launch copy for CueMe

Ready-to-paste posts for launching CueMe in the community. Tweak the voice to
fit you; keep the honesty (it's a personal tool, macOS-26 only, Claude keyless by default).

---

## Show HN

**Title:** Show HN: CueMe – a real-time conversation copilot for macOS (on-device, keyless default)

**Body:**

CueMe is a native macOS app that listens to both sides of a live conversation,
transcribes and translates it on the fly, and coaches you on what to say next —
built for mock interviews, sales calls, and difficult conversations.

A few things I wanted that existing tools didn't do:

- **Both sides captured natively.** Your mic via AVAudioEngine + the other
  person's audio via ScreenCaptureKit. Because the two sources are separate,
  "who spoke" is known by origin — no diarization needed. No virtual audio driver.
- **On-device and keyless.** Speech-to-text is Apple's SpeechAnalyzer and
  translation is the on-device Translation framework (~100–200ms). The LLM
  "brain" runs through the local Claude Code CLI, reusing your existing login —
  so the default path has no API key to provision. DeepSeek is optional and keyed.
- **A coach that reads like a friend.** Under pressure you can't read paragraphs,
  so the cue is terse: one line of guidance in your language, a ready-to-say
  phrase in theirs, and the key vocabulary. It's grounded only in a brief + your
  pasted CV, and hardened so it never fabricates experience or breaks character.
- **A training mode that doubles as an e2e test.** A built-in interviewer reads
  your CV, asks questions out loud (native TTS), and adapts to your spoken
  answers — the TTS is captured by the app's own ScreenCaptureKit stream, so it
  exercises the whole capture → STT → translate → coach path.

It's 100% native Swift (SwiftUI + Swift Concurrency), macOS 26 only, MIT licensed.
Repo, GIF, and a short write-up of the architecture (ADRs included) here:

https://github.com/feliperun/cueme

Happy to talk about the design trade-offs — the CLI-as-brain choice, speaker-by-
origin, echo dedup for speaker setups, or why translation moved off the LLM.

**Note on use:** it's great for practice and prep. Some real, live processes have
rules about assistance — know the context you're in.

---

## X / Twitter thread

**1/**
I built CueMe — a real-time conversation copilot for macOS.

It hears both sides of a call, translates live, and whispers what to say next.
On-device speech. Claude keyless by default.

🧵 how it works ↓
https://github.com/feliperun/cueme

**2/**
It captures your mic + the other person's system audio as two separate streams.

So "who spoke" is free — mic = you, system = them. No diarization, no virtual
audio driver. Just ScreenCaptureKit + AVAudioEngine.

**3/**
Speech + translation run on-device (SpeechAnalyzer + Apple's Translation
framework, ~100–200ms).

The default coaching brain runs through your local Claude Code CLI — no API key
to manage. DeepSeek is an explicit keyed option. Warm sessions keep cues fast.

**4/**
The coach reads like a friend beside you:
🎯 one-line guidance (your language)
🗣️ a ready phrase (their language)
🔑 the key words

Grounded in your CV. Hardened so it never makes up experience.

**5/**
Bonus: a training mode where a built-in voice interviewer reads your CV and
grills you out loud, adapting to your answers — and it runs through the real
pipeline, so it's also an end-to-end test.

100% native Swift, macOS 26, MIT. ⭐ https://github.com/feliperun/cueme

---

## Reddit (r/macapps or r/MacOS)

**Title:** [OSS] CueMe — a real-time conversation copilot for macOS (on-device, keyless default)

**Body:**

I made a native macOS app that listens to both sides of a live conversation and
coaches you in real time — transcribes, translates, and shows a terse cue of what
to say next. Built for mock interviews and prepping hard conversations.

Highlights:
- Captures your mic + the other side's system audio (ScreenCaptureKit) — speaker
  known by origin, no diarization, no virtual audio driver.
- On-device speech + translation (macOS 26 frameworks). Claude CLI is the
  keyless default; DeepSeek is optional.
- Terse, emoji-cued coaching grounded in a brief + your CV.
- A voice "training mode": an interviewer reads your CV and asks questions aloud,
  adapting to your answers.

100% native Swift, MIT licensed. Feedback very welcome — especially on the UX of
reading cues under pressure.

Repo: https://github.com/feliperun/cueme

(It's a practice/prep tool — please respect the rules of any real process you're in.)
