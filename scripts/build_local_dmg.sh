#!/usr/bin/env bash
# Builds an unsigned Release build and packages it into dist/ as a DMG with a SHA256 file.
# VERSION (optional) is used in the artifact name; defaults to a local timestamp build.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$ROOT_DIR/build/Build/Products/Release/BoringMeeting.app"

VERSION="${VERSION:-local}"
SHORT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "nogit")"

if [[ "$VERSION" == "local" ]]; then
  ARTIFACT_BASENAME="BoringMeeting-$(date -u +%Y%m%d-%H%M%S)-${SHORT_SHA}"
else
  ARTIFACT_BASENAME="BoringMeeting-${VERSION}"
fi

"$ROOT_DIR/build_app.sh" --mode local-release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build finished but app not found: $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/${ARTIFACT_BASENAME}.dmg" "$DIST_DIR/${ARTIFACT_BASENAME}.sha256"

echo "==> Creating DMG: $DIST_DIR/${ARTIFACT_BASENAME}.dmg"
hdiutil create \
  -volname "BoringMeeting" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/${ARTIFACT_BASENAME}.dmg"

echo "==> Calculating SHA256"
(cd "$DIST_DIR" && shasum -a 256 "${ARTIFACT_BASENAME}.dmg" > "${ARTIFACT_BASENAME}.sha256")

echo "Build artifacts:"
echo "  DMG: $DIST_DIR/${ARTIFACT_BASENAME}.dmg"
echo "  SHA: $DIST_DIR/${ARTIFACT_BASENAME}.sha256"
