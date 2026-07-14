#!/usr/bin/env bash
# Empacota o CueMe num .dmg — RODAR NO SEU MAC (macOS 26 + Xcode 26).
# Uso: ./scripts/package.sh [versão]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
VERSION="${1:-}"
BUILD_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
PACKAGE_DIR="${CUEME_PACKAGE_DIR:-$PWD/.build/SourcePackages}"
trap 'rm -rf "$BUILD_DIR" "$STAGE"' EXIT

echo "▸ Building ${CONFIG}${VERSION:+ v${VERSION}}…"
BUILD_ARGS=(
  -project CueMe.xcodeproj -scheme CueMe -configuration "${CONFIG}"
  -derivedDataPath "${BUILD_DIR}" -destination 'platform=macOS'
  -clonedSourcePackagesDirPath "${PACKAGE_DIR}"
  -packageAuthorizationProvider netrc
)
if [ -n "${VERSION}" ]; then BUILD_ARGS+=("MARKETING_VERSION=${VERSION}"); fi
if [ "${CUEME_ADHOC_SIGN:-0}" = "1" ]; then
  BUILD_ARGS+=(DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES)
elif [ -n "${CUEME_SIGNING_IDENTITY:-}" ]; then
  BUILD_ARGS+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=${CUEME_SIGNING_IDENTITY}"
    "DEVELOPMENT_TEAM=${CUEME_DEVELOPMENT_TEAM:?CUEME_DEVELOPMENT_TEAM is required}"
  )
fi
xcodebuild "${BUILD_ARGS[@]}" build | tail -3

APP="${BUILD_DIR}/Build/Products/${CONFIG}/CueMe.app"
[ -d "${APP}" ] || { echo "✗ CueMe.app não encontrado"; exit 1; }

VER="$(defaults read "${APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0.0)"
mkdir -p dist
DMG="dist/CueMe-$VER.dmg"

echo "▸ Staging + .dmg ($DMG)…"
cp -R "${APP}" "${STAGE}/CueMe.app"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "CueMe" -srcfolder "${STAGE}" -ov -format ULFO "${DMG}" >/dev/null

if [ "${CUEME_ADHOC_SIGN:-0}" = "1" ]; then
  codesign --force --sign - "${DMG}"
else
  DMG_IDENTITY="${CUEME_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -1)}"
  [ -n "${DMG_IDENTITY}" ] || { echo "✗ No signing identity found"; exit 1; }
  if [[ "${DMG_IDENTITY}" == "Developer ID Application"* ]]; then
    codesign --force --timestamp --sign "${DMG_IDENTITY}" "${DMG}"
  else
    codesign --force --timestamp=none --sign "${DMG_IDENTITY}" "${DMG}"
  fi
fi

if [ -n "${CUEME_NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing…"
  xcrun notarytool submit "${DMG}" --keychain-profile "${CUEME_NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG}"
fi

shasum -a 256 "${DMG}" > "${DMG}.sha256"

echo "✓ $DMG"
echo "✓ ${DMG}.sha256"
codesign -dv "${APP}" 2>&1 | grep -E "Authority|TeamIdentifier" || true
if [ -z "${CUEME_NOTARY_PROFILE:-}" ]; then
  echo
  echo "Nota: build não notarizado (ver docs/PACKAGING.md)."
fi
