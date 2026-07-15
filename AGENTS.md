# AGENTS.md — CueMe

> Quick links: [Architecture](docs/ARCHITECTURE.md) · [Abstractions](docs/ABSTRACTIONS.md) · [Vision](docs/VISION.md) · [Getting Started](docs/GETTING-STARTED.md) · [ADRs](docs/adr/README.md) · [Sentrux](docs/sentrux.md)
>
> *Playbook structure inspired by [tolaria](https://github.com/refactoringhq/tolaria); gate by [Sentrux](https://github.com/sentrux/sentrux).*

Critical guardrails for this repository — read before writing code or opening a PR.

---

## 1. Privacy & secrets (hard rules)

- **Never commit secrets.** Tokens, credentials, and service-account JSON stay in a secret manager or local `.env` (gitignored).
- **Never expose internals to users.** No stack traces, internal URLs, or env var names in user-facing copy.
- **Tests use synthetic data.** Real customer data belongs in manual repros only.

---

## 2. Task workflow

### 2a. Pick up a task

- Read the issue fully, including comments.
- Check `docs/adr/` for relevant architecture decisions before any structural choice.
- For bug fixes: reproduce first, then write a failing regression test when practical, then fix.

### 2b. Implement

- Branch from `main` (worktree when possible); open a focused PR with Conventional Commit titles.
- Commit every 20–30 min: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- **Never `--no-verify`.** If a hook blocks, fix the underlying issue.
- Keep changes scoped — no opportunistic refactors in feature PRs.

### 2c. Before declaring done

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' test
sentrux check .
sentrux gate .
```

---

## 3. Development process

### Commits & PRs

- **Conventional Commits required.** One logical change per commit; one bounded scope per PR.
- Use `feat!:` or a `BREAKING CHANGE:` footer for breaking changes.
- A PR is not ready to merge until CI is green.

### TDD (mandatory for behavior changes)

Red → Green → Refactor → Commit.

- Bug fixes: failing regression test first when testable.
- New logic: unit tests close to the change.
- Exception: pure docs, formatting, or copy tweaks with no code-path change.

**Test quality:** Isolated · Deterministic · Fast · Behavioral. Fix flaky tests first.

### End-to-end tests (mandatory for key features)

Any key feature or user-visible change to a primary workflow must add or update
an XCTest UI scenario in `CueMeUITests`. Unit tests remain mandatory for logic,
but do not replace an E2E regression test. Key workflows include capture,
recording, STT, playback, memory/search/embeddings, persistence, evidence,
projects/people, Coach/AI generation, import/export, privacy and failover.

Before declaring work complete, the agent must run both suites explicitly:

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -skip-testing:CueMeUITests test
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' -only-testing:CueMeUITests test
```

E2E fixtures must be synthetic, deterministic and isolated from the user's
archive, Keychain, network providers and production SQLite database. Use stable
accessibility identifiers; never use sleeps. An exception is allowed only for
docs, formatting or behavior-preserving internal refactors and must be stated in
the PR. See [ADR 0029](docs/adr/0029-key-feature-e2e-regression-gate.md).

### Check suite (runs on every push / PR)

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO           # compile
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' test                                   # XCTest (signed test host)
sentrux check .           # architectural rules (.sentrux/rules.toml)
sentrux gate .            # no structural regression vs baseline
```

CI mirrors this — see `.github/workflows/quality.yml`.

### Code conventions

- **Language:** code, comments, identifiers in **English**.
- **Surgical changes.** Match existing style; don't refactor unrelated code.
- **Validate at boundaries.** Don't bypass schema validation with `any`.

### Code health gate — Sentrux (mandatory)

[Sentrux](https://github.com/sentrux/sentrux) is the structural-quality sensor for this repo. Full reference: [docs/sentrux.md](docs/sentrux.md).

`check` enforces absolute limits (`.sentrux/rules.toml`); `gate` enforces *no regression* vs. the committed baseline (`.sentrux/baseline.json`).

```bash
sentrux check .           # CI-friendly; exits 0 if rules pass, 1 if not
sentrux gate --save .     # snapshot baseline before editing existing files
sentrux gate .            # compare current vs baseline; fails on degradation
```

- **Before a task on existing files**, run `sentrux gate --save .` to capture the baseline.
- **Before committing**, run `sentrux gate .`. Degradation on a touched file → refactor, don't commit.
- **Boy Scout Rule**: every file you touch leaves with an equal-or-better score.
- **Never silence a rule** to pass. The gate is a ratchet — only direction is up.

### ADRs & docs

ADRs live in `docs/adr/`. Create one in the same commit as the code that implements the decision. Never edit an active ADR — supersede it.

**When to create an ADR:** new external dependency, change to a public contract, hosting/secrets strategy change, or a cross-cutting pattern future contributors must follow.

**Not for:** behavior-preserving bug fixes, dependency patch bumps, copy tweaks.

After a structural change, update `docs/ARCHITECTURE.md` and/or `docs/ABSTRACTIONS.md` in the same commit.

### CueMe-specific gotchas (hard-won — don't re-learn these)

- **CI builds on `macos-26`.** The test host is ad-hoc signed in CI with an
  empty development team; `CODE_SIGNING_ALLOWED=NO` is insufficient because a
  hosted XCTest app must still be signed to launch. Keep the local build and
  test commands above as the pre-push fast path (see
  [docs/PACKAGING.md](docs/PACKAGING.md)).
- **`setVoiceProcessingEnabled(true)` on the mic input node wedged the process**
  (unkillable, survived `kill -9`, needed a machine reboot) when enabled without
  a connected duplex render graph. AEC is opt-in and off by default
  ([ADR 0007](docs/adr/0007-speaker-by-origin-and-echo-dedup.md)). If you touch
  `AudioCapture.startMic`, keep the mixer connection + muted output pattern and
  test before ever defaulting it on.
- **`ClaudeSession` runs from an isolated empty cwd with `disableAllHooks`.**
  Without that, the CLI picks up the *user's own* project context (skill names,
  `CLAUDE.md`) and the coach fabricates "experience" from it — this actually
  happened once. Never remove this when touching `Brain/ClaudeSession.swift`
  ([ADR 0005](docs/adr/0005-llm-brain-via-claude-cli.md),
  [ADR 0008](docs/adr/0008-coach-ux-and-context-safety.md)).
- **release-please: `bump-minor-pre-major` and `bump-patch-for-minor-pre-major`
  are mutually exclusive.** Setting both (copy-paste mistake) silently made every
  `feat:` bump the patch version instead of minor (caught before v0.4.0 shipped).
  Only `bump-minor-pre-major: true` belongs in `release-please-config.json`.
- **Destructive/merge actions are gated by an auto-mode safety classifier**,
  independent of this file — self-merging a PR, force-push, changing repo
  permissions via `gh api`, etc. get denied without explicit human sign-off in
  the moment. Expect it; hand off to the user rather than routing around it.
- **No absolute file paths in exported session JSON.** Audio recordings are
  located by session id at read time (`MeetingRecording.directory(for:)`), never
  stored as a literal path — keeps exports portable across machines/reinstalls.

---

## 4. Release-readiness checklist

- [ ] `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` passes locally.
- [ ] `sentrux check .` passes; `sentrux gate .` shows no degradation on touched files.
- [ ] CI is green on the PR.
- [ ] Key user-visible behavior has a deterministic `CueMeUITests` regression and the UI E2E check is green.
- [ ] No secrets, tokens, or internal URLs in the diff.
- [ ] If a structural decision was made: ADR exists and `docs/adr/README.md` index is updated.
- [ ] Conventional Commit title.

---

## 5. Reference

### Layout

```
CueMe/                    App target (see docs/ARCHITECTURE.md for the full breakdown)
  Audio/                  Capture, recording, playback, waveform
  STT/                    On-device speech + translation
  Bus/                    TranscriptBus actor (fan-out + rolling window)
  Brain/                  Claude CLI client/session, prompts, coach/summary lanes
  Model/                  AppModel, SessionCoordinator, SessionBrief/Record, Types
  Views/                  SwiftUI (compact window, history, brief editor, About)
  Assets.xcassets/        App icon, accent color
CueMe.xcodeproj/          Xcode project (synchronized file group — no manual .pbxproj edits for new files)
CueMeTests/               XCTest regressions (provider, parser, clocks, heuristics)
scripts/package.sh        Local Release build → signed .dmg (see docs/PACKAGING.md)
docs/
  adr/                    Architecture decision records (numbered, immutable)
  assets/                 README/landing screenshots, demo GIF, OG banner
  index.html              GitHub Pages landing site (docs/ is the Pages source)
  *.md                    Vision, architecture, abstractions, getting-started, packaging
.sentrux/                 Structural quality gate config + baseline
.github/workflows/        CI (quality.yml = build/tests + Sentrux; release-please.yml = releases)
release-please-config.json, .release-please-manifest.json   Automated versioning
```

### Useful commands

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' test
sentrux check . && sentrux gate .
./scripts/package.sh      # Release build → dist/CueMe-<version>.dmg (run on a Mac; see docs/PACKAGING.md)
```
