# Getting Started

## Prerequisites

- **macOS 26 (Tahoe)** — `SpeechAnalyzer`/`SpeechTranscriber` and the
  `Translation` framework don't exist on older SDKs.
- **Xcode 26** (Swift 6.2 toolchain).
- **Claude Code CLI**, installed and logged in — the default coach and summary
  shell out to `claude -p`. No Anthropic API key is needed.
  ```bash
  claude --version   # prints a version if installed
  claude -p "hi"     # answers if you're logged in
  ```
  Install: https://docs.claude.com/en/docs/claude-code
- [Sentrux CLI](sentrux.md#install) for the structural quality gate.
- An **Apple Development signing identity** (free personal team is enough) —
  Xcode → Settings → Accounts → add your Apple ID, then set the CueMe target's
  Team under Signing & Capabilities once. Without a stable team, the app
  re-signs ad-hoc on every build and macOS treats it as a new app each time,
  so TCC permissions (mic, Screen Recording) never stick.

## Quick start

```bash
git clone https://github.com/feliperun/cueme.git
open cueme/CueMe.xcodeproj
# Select the CueMe scheme, ⌘R.
```

No package manager or SDK dependency is required — the project uses native
frameworks. DeepSeek and Deepgram are optional; their API keys are stored as
separate Keychain items when selected. First launch prompts for Microphone (required) and, if you want the
other side of the conversation, Screen & System Audio Recording (optional).

## Daily commands

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' test # signed host required
sentrux check .           # architectural rules
sentrux gate .            # no structural regression
```

GitHub CI repeats the build and XCTest suite on a `macos-26` runner, then runs
the Sentrux structural gates. Keep the local checks as the fast feedback path
before pushing. See [AGENTS.md § CueMe-specific gotchas](../AGENTS.md#3b-cueme-specific-gotchas-hard-won--dont-re-learn-these).

Run only the end-to-end macOS UI suite with:

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test
```

The first local run may require macOS authorization for Xcode UI automation.
The app uses deterministic fixtures and a temporary SQLite database in this
mode, so the user's CueMe archive is not modified.

The opt-in Deepgram live smoke test uses a synthetic PCM16 WAVE file and an
environment-provided key:

```bash
DEEPGRAM_API_KEY=... node scripts/test-deepgram-live.mjs /path/to/test.wav
```

## Packaging a build

```bash
./scripts/package.sh      # Release build → dist/CueMe-<version>.dmg
```

Details on signing/notarization trade-offs: [Packaging](PACKAGING.md).

## Worktree workflow

```bash
# Create a worktree for a task (keeps main clean):
git worktree add ../CueMe-<task> -b <dev>/<issue>-<slug>
```

## Documentation map

- [Vision](VISION.md) — why this exists, current horizon
- [Architecture](ARCHITECTURE.md) — current-state structure
- [Abstractions](ABSTRACTIONS.md) — the vocabulary, layer contracts
- [ADRs](adr/README.md) — decision history (read before any structural change)
- [Sentrux](sentrux.md) — the quality gate
- [Packaging](PACKAGING.md) — building/signing/releasing a `.dmg`
- [AGENTS.md](../AGENTS.md) — the contributor/agent playbook (read this first)

## First contribution checklist

- [ ] Read [AGENTS.md](../AGENTS.md), especially the CueMe-specific gotchas.
- [ ] Confirm `claude -p "hi"` answers (brain works) before testing coach features.
- [ ] Run the local `xcodebuild` and Sentrux check suite; confirm it's green.
- [ ] `sentrux gate --save .` before touching existing files.
- [ ] Skim the [ADR index](adr/README.md) for the area you're touching.
