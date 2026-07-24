# Packaging & distributing CueMe

Short version: GitHub CI builds and tests CueMe on `macos-26`. The release-assets
workflow publishes the DMG, checksum, and signed Sparkle appcast for each tag.

## Can GitHub CI build it? Yes.

CueMe uses **macOS 26** frameworks (`SpeechAnalyzer`, `Translation`,
`SpeechTranscriber`). The `quality` workflow uses GitHub's `macos-26` runner to
compile the app and run XCTest with an ad-hoc-signed test host, alongside the
Sentrux gates.

The release workflow requires a **stable Apple signing identity** — not
necessarily a paid Developer ID. The free Personal Team "Apple Development"
certificate has a stable Team ID, which keeps the app's designated requirement
(and its macOS TCC grants for microphone and Screen & System Audio Recording)
constant across Sparkle updates. Ad-hoc signing would reset them on every
update, so the workflow fails closed without a certificate. Sparkle appcasts are
EdDSA-signed with a free key that is independent of Apple. See
[ADR 0036](adr/0036-free-personal-team-signing.md).

Free Personal Team builds ship **unnotarized**: the first manual install needs a
one-time Gatekeeper bypass (**System Settings → Privacy & Security → Open
Anyway**, because macOS 26 removed the old right-click → Open shortcut for
unnotarized apps). Sparkle updates are installed in place under the same team
and are not re-gated. A paid Developer ID unlocks notarization with no workflow
change — the notarize step activates automatically when a `Developer ID
Application` identity and notary secrets are present.

### Required repository secrets

| Secret | Purpose |
| --- | --- |
| `SIGNING_CERTIFICATE_P12_BASE64` | Base64 of the exported signing cert **with its private key** (`.p12`). The free `Apple Development` cert is fine. |
| `SIGNING_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12`. |
| `KEYCHAIN_PASSWORD` | Any value — unlocks the throwaway CI keychain. |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key that signs the appcast (already configured). |
| `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` | Optional; only used when signing with a Developer ID. |

Export the free cert from **Keychain Access → My Certificates → the "Apple
Development: …" entry → right-click → Export** (choose `.p12`, set a password),
then `base64 -i cert.p12 | pbcopy` and paste into `SIGNING_CERTIFICATE_P12_BASE64`.

`release-please` dispatches `release-assets` automatically for every new tag
(its own `release: published` event cannot cascade because it is created with
`GITHUB_TOKEN`), the packaging run verifies the DMG, checksum and signed appcast
before it goes green, and a weekly `release-health` job fails if the latest
appcast feed is unreachable or unsigned. See
[ADR 0035](adr/0035-automated-release-asset-publishing.md). Until the signing
secret is configured the dispatched run fails loudly on each release — that is
the intended signal.

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
