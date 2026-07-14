#!/usr/bin/env bash
# Empacota o CueMe num .dmg — RODAR NO SEU MAC (macOS 26 + Xcode 26).
# Uso: ./scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
BUILD_DIR="$(mktemp -d)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR" "$STAGE"' EXIT

echo "▸ Building ${CONFIG}…"
xcodebuild -project CueMe.xcodeproj -scheme CueMe -configuration "${CONFIG}" \
  -derivedDataPath "${BUILD_DIR}" -destination 'platform=macOS' \
  build | tail -3

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

echo "✓ $DMG"
codesign -dv "${APP}" 2>&1 | grep -E "Authority|TeamIdentifier" || true
echo
echo "Nota: assinado com Apple Development (dev). Sem notarização, o Gatekeeper"
echo "avisa no 1º open — o usuário abre com botão-direito → Abrir. Para instalação"
echo "limpa, é preciso Developer ID + notarização (ver docs/PACKAGING.md)."
