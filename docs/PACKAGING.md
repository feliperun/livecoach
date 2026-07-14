# Packaging & distributing CueMe

Short version: GitHub CI can build and test CueMe on `macos-26`, while release
packaging and signing still happen on your Mac.

## Can GitHub CI build it? Yes.

CueMe uses **macOS 26** frameworks (`SpeechAnalyzer`, `Translation`,
`SpeechTranscriber`). The `quality` workflow uses GitHub's `macos-26` runner to
compile the app and run XCTest with an ad-hoc-signed test host, alongside the
Sentrux gates.

The release workflow does not yet package, Developer ID-sign, notarize, or
attach the `.dmg`; those distribution steps remain local/manual.

## Build a `.dmg` locally

```sh
./scripts/package.sh
# → dist/CueMe-<version>.dmg
```

It builds Release, stages `CueMe.app` next to an `/Applications` symlink, and
makes a compressed `.dmg`.

## Signing & Gatekeeper

The project uses **automatic signing** with your **Apple Development** identity
(Personal Team). That's fine for running it yourself, but:

- A `.dmg` signed only with a *development* cert is **not notarized**, so on
  another Mac Gatekeeper blocks the first launch. Workaround for users:
  **right-click → Open** (once).
- For a clean, double-click install you need a **Developer ID Application**
  certificate (paid Apple Developer Program, US$99/yr) and **notarization**:

  ```sh
  # after building a Developer ID-signed .app:
  xcrun notarytool submit dist/CueMe-<v>.dmg \
    --apple-id you@example.com --team-id C8D46BZNT3 --password <app-specific-pw> \
    --wait
  xcrun stapler staple dist/CueMe-<v>.dmg
  ```

Without the paid program, ship the `.dmg` as-is and document the right-click-Open
step — normal for early open-source macOS apps.

## Releases

`release-please` already opens a release PR and, when merged, cuts a **tag +
GitHub Release** with the changelog. Attach the `.dmg` from `./scripts/package.sh`
to that Release (drag-and-drop in the GitHub UI, or `gh release upload <tag>
dist/CueMe-<v>.dmg`).

## First-version checklist

- [x] App icon (Dock, Finder, and the Screen Recording permission dialog)
- [x] About window (version, links, CLI status)
- [x] Category + copyright in Info.plist
- [x] Hardened runtime + mic / network entitlements
- [x] Stable signing (`DEVELOPMENT_TEAM`)
- [ ] Developer ID + notarization (needs the paid program) — optional for OSS
- [ ] Attach the `.dmg` to the GitHub Release
