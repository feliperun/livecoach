# Changelog

## [0.9.0](https://github.com/feliperun/cueme/compare/v0.8.0...v0.9.0) (2026-07-14)


### Features

* add adaptive meeting intelligence ([9a47cf3](https://github.com/feliperun/cueme/commit/9a47cf31c2a333bf797ae3de138e484f2eef97d8))
* add Deepgram streaming transcription ([108a8b2](https://github.com/feliperun/cueme/commit/108a8b20e8edd547fa5776f6be62993b709c7bf3))
* add meeting memory workspace ([382f313](https://github.com/feliperun/cueme/commit/382f31307bb06ba735a2074225483881bd1322de))
* add reusable meeting contexts ([d7b8c6f](https://github.com/feliperun/cueme/commit/d7b8c6f669ceb0cdc47ffc56b2394effc4339d01))
* improve audio quality and polish workspace ([4b76b24](https://github.com/feliperun/cueme/commit/4b76b24124e61828014f132bd2f48b9bc6b49e11))
* ship meeting memory and intelligent transcription ([1cfd72a](https://github.com/feliperun/cueme/commit/1cfd72a8de57cbc316b633683d01f6f701856b11))

## [0.8.0](https://github.com/feliperun/cueme/compare/v0.7.1...v0.8.0) (2026-07-14)


### Features

* add long-call recovery and provider failover ([826d86d](https://github.com/feliperun/cueme/commit/826d86d648976655bb810d085e67be50a624051f))

## [0.7.1](https://github.com/feliperun/cueme/compare/v0.7.0...v0.7.1) (2026-07-14)


### Bug Fixes

* make release assets workflow dispatchable ([04d2a74](https://github.com/feliperun/cueme/commit/04d2a7481caffa516250bc3675aff9961f1b9b30))

## [0.7.0](https://github.com/feliperun/cueme/compare/v0.6.0...v0.7.0) (2026-07-14)


### Features

* ship glanceable resilient live coaching ([cc29116](https://github.com/feliperun/cueme/commit/cc29116c633603277246e90730799d8a15061ed9))

## [0.6.0](https://github.com/feliperun/cueme/compare/v0.5.0...v0.6.0) (2026-07-14)


### Features

* ship reliable fast live coaching ([1014084](https://github.com/feliperun/cueme/commit/10140844262c07af01bf2182a82e4a6c392a7583))

## [0.5.0](https://github.com/feliperun/cueme/compare/v0.4.0...v0.5.0) (2026-07-13)


### Features

* DeepSeek V4 coach (Pro/Flash) + new-session UX ([78408a9](https://github.com/feliperun/cueme/commit/78408a9cf5b52a69b944eb0173bb092f0af24002))
* DeepSeek V4 coach via direct API (Pro/Flash) ([7ef902c](https://github.com/feliperun/cueme/commit/7ef902cfb9163f8547c1730b1634a13aaf5356d4))
* persist coach model + "New session" one-click restart ([2cc7580](https://github.com/feliperun/cueme/commit/2cc75802cad24c299d99cd36dab420d500b1eec2))

## [0.4.0](https://github.com/feliperun/cueme/compare/v0.3.0...v0.4.0) (2026-07-13)


### Features

* app icon, About window, and packaging tooling ([65e706b](https://github.com/feliperun/cueme/commit/65e706b4684dd5d921caca75bf2bf29ede487e21))
* command-center visual theme + context-leak guard for the coach ([0e9daf3](https://github.com/feliperun/cueme/commit/0e9daf340062b81dc6036a5722944ee322e7a208))
* compact-first redesign — friend-style hints, CV-aware coach, echo dedup ([b4a2746](https://github.com/feliperun/cueme/commit/b4a274684d6c583a859abf99761cb976a0a3f6df))
* expert coach — three-specialist persona + per-mode playbooks ([4c24463](https://github.com/feliperun/cueme/commit/4c2446310ee7dfaf7745277b4c625448e6dad757))
* export/copy a session as JSON ([65008c0](https://github.com/feliperun/cueme/commit/65008c0122a250686751488746fd692a33e22ad0))
* faster, easier-to-read coach card ([9ea7ca0](https://github.com/feliperun/cueme/commit/9ea7ca0067d775198caa998bf8910d905892039c))
* global ⌥Space show/hide hotkey + menu bar controls ([3921391](https://github.com/feliperun/cueme/commit/3921391089f5bf7ac1379ffbb696779dde9d0c7a))
* harden coach role, succinct emoji cards, AEC, model picker, bigger UI ([a31c1e1](https://github.com/feliperun/cueme/commit/a31c1e1517357d3e12b35380e1b1ab3767ee4d6d))
* initial LiveCopilot — native macOS real-time conversation copilot ([fbf99e9](https://github.com/feliperun/cueme/commit/fbf99e9808268a99e75bcf5c4eada5d34065a78e))
* meeting mode — synced audio recording + waveform playback ([3c24aec](https://github.com/feliperun/cueme/commit/3c24aec653d7052f899faf0544f5b82ec02c4c2e))
* on-device translation highlighting (NaturalLanguage), tiered not bold ([dd69c8a](https://github.com/feliperun/cueme/commit/dd69c8a1701272db17cde560fd4d822b0e1a6797))
* opt-in acoustic echo cancellation + default coach to Sonnet ([1612f02](https://github.com/feliperun/cueme/commit/1612f02571dc9d3f4fa01e33262ed525eaacf184))
* session history — browse past training and live sessions ([caff74c](https://github.com/feliperun/cueme/commit/caff74c2077c144db4975de43ce0f35041e1135e))
* training mode — adaptive voice interviewer + e2e test harness ([cdc4f2e](https://github.com/feliperun/cueme/commit/cdc4f2eff7c26cb6e2eb4b6daf6db477371b30b0))
* training-mode toggle in the header ([be0351d](https://github.com/feliperun/cueme/commit/be0351d8490b108fd310ec4f80a8ade4dc85a7c9))


### Bug Fixes

* remove conflicting bump-patch-for-minor-pre-major from release-please ([5a0eb8b](https://github.com/feliperun/cueme/commit/5a0eb8b3f15db4b6758b42e975d24f5931e29b6a))


### Performance Improvements

* native on-device translation + session prewarm for realtime latency ([10bd433](https://github.com/feliperun/cueme/commit/10bd433eaeabaa84e857f30573e07512ee1249c8))
