# Packaging & distributing CueMe

Short version: GitHub CI builds and tests CueMe on `macos-26`. The release-assets
workflow publishes the DMG, checksum, and signed Sparkle appcast for each tag.

## Can GitHub CI build it? Yes.

CueMe uses **macOS 26** frameworks (`SpeechAnalyzer`, `Translation`,
`SpeechTranscriber`). The `quality` workflow uses GitHub's `macos-26` runner to
compile the app and run XCTest with an ad-hoc-signed test host, alongside the
Sentrux gates.

The release workflow requires Developer ID signing/notarization repository
secrets. It fails closed when they are missing: an ad-hoc update changes the
app's designated requirement and invalidates macOS TCC grants for microphone
and Screen & System Audio Recording. Ad-hoc packaging remains available only
for disposable local/CI builds.

## Build a `.dmg` locally

```sh
./scripts/package.sh 0.7.0
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

Without the paid program, use that `.dmg` only for local development. Do not
publish it as a Sparkle update: every ad-hoc build has a different designated
requirement and macOS will invalidate the user's privacy grants.

## Releases

`release-please` opens a release PR and synchronizes `MARKETING_VERSION`. After
the tag exists, `release-assets` packages it and uploads the DMG, checksum, and
appcast. Sparkle reads `releases/latest/download/appcast.xml` and verifies the
update's EdDSA signature.

## First-version checklist

- [x] App icon (Dock, Finder, and the Screen Recording permission dialog)
- [x] About window (version, links, CLI status)
- [x] Category + copyright in Info.plist
- [x] Hardened runtime + mic / network entitlements
- [x] Stable signing (`DEVELOPMENT_TEAM`)
- [ ] Developer ID + notarization secrets — required before the next published update
- [x] Attach the `.dmg`, checksum, and signed appcast to the GitHub Release
