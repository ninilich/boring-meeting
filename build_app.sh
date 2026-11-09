#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/BoringMeeting.xcodeproj"
SCHEME="BoringMeeting"
MODE="local-release"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build"

print_help() {
  cat <<'EOF'
Usage: ./build_app.sh [--mode local-release|dev|release]

Modes:
  local-release  Release build without code signing (default)
  dev            Debug build without code signing
  release        Release build with normal signing settings
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode|-m)
      if [[ $# -lt 2 ]]; then
        echo "Error: --mode requires a value (local-release|dev|release)." >&2
        exit 1
      fi
      MODE="$2"
      shift 2
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      print_help >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  local-release)
    CONFIGURATION="Release"
    ;;
  dev)
    CONFIGURATION="Debug"
    ;;
  release)
    CONFIGURATION="Release"
    ;;
  *)
    echo "Error: unsupported mode '$MODE'. Use local-release, dev, or release." >&2
    exit 1
    ;;
esac

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/BoringMeeting.app"

printf "\n▶ Building %s (%s)\n" "$SCHEME" "$CONFIGURATION"
printf "Project: %s\n" "$PROJECT_PATH"
printf "DerivedData: %s\n\n" "$DERIVED_DATA_PATH"
printf "Mode: %s\n\n" "$MODE"

XCODEBUILD_CMD=(
  xcodebuild
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  clean build
)

if [[ "$MODE" == "dev" || "$MODE" == "local-release" ]]; then
  XCODEBUILD_CMD+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
  )
fi

"${XCODEBUILD_CMD[@]}"

if [[ -d "$APP_PATH" ]]; then
  printf "\n✅ Build succeeded.\n"
  printf "App path: %s\n" "$APP_PATH"
else
  printf "\n❌ Build finished but app not found at expected path:\n%s\n" "$APP_PATH" >&2
  exit 1
fi
