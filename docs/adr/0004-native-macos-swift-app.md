---
type: ADR
id: "0004"
title: "Native macOS 26 Swift app (no webview, no virtual audio driver)"
status: active
date: 2026-07-10
---

## Context

CueMe went through two earlier shapes before this one: a browser app using the
Web Speech API (v0.1), and a Rust core behind a Tauri shell (v0.2). Both needed
a virtual audio device (BlackHole / Aggregate Device) to capture the other
party, carried an FFI or IPC boundary, and fought the platform for low-latency
audio and native text rendering.

## Decision

**Build CueMe as a single native macOS 26 SwiftUI process.** Capture system
audio with `ScreenCaptureKit` (no virtual driver), the mic with `AVAudioEngine`,
and run everything — audio, STT, orchestration, UI — in one Swift process with
Swift Concurrency. Target macOS 26 to use the new on-device speech/translation
frameworks.

## Options considered

- **Native Swift, macOS 26** (chosen): ScreenCaptureKit removes the virtual
  audio driver; two capture sources make speaker attribution free; one process
  means no IPC/FFI serialization; SwiftUI gives native rendering and signing.
- **Browser + Web Speech API**: zero install but no system-audio capture, weak
  control over latency, cloud-only STT.
- **Rust core + Tauri**: reuses a Rust ecosystem but adds an FFI boundary and
  still needs a virtual audio device on macOS.

## Consequences

- CueMe is **Apple-only** and requires **macOS 26** — accepted for a personal
  tool.
- No third-party audio drivers to install; capture is a TCC permission prompt.
- Supersedes the browser (v0.1) and Rust+Tauri (v0.2) designs.
