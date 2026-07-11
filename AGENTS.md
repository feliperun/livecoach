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

### Check suite (runs on every push / PR)

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO            # types + tests
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

---

## 4. Release-readiness checklist

- [ ] `xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` passes locally.
- [ ] `sentrux check .` passes; `sentrux gate .` shows no degradation on touched files.
- [ ] CI is green on the PR.
- [ ] No secrets, tokens, or internal URLs in the diff.
- [ ] If a structural decision was made: ADR exists and `docs/adr/README.md` index is updated.
- [ ] Conventional Commit title.

---

## 5. Reference

### Layout

```
src/                      Source
docs/
  adr/                    Architecture decision records
  *.md                    Vision, architecture, abstractions, getting-started
.sentrux/                 Structural quality gate config + baseline
.github/workflows/        CI
```

### Useful commands

```bash
xcodebuild -project CueMe.xcodeproj -scheme CueMe -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
sentrux check . && sentrux gate .
```
