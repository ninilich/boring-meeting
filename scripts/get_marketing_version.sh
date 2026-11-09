#!/usr/bin/env bash
# Prints MARKETING_VERSION of the BoringMeeting app target from a project.pbxproj
# (path as $1, default: the project in this repo). Works on macOS and Linux.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="${1:-$ROOT_DIR/BoringMeeting.xcodeproj/project.pbxproj}"

awk '
  /isa = XCBuildConfiguration;/ { mv = ""; app = 0 }
  /MARKETING_VERSION = / { v = $0; sub(/.*MARKETING_VERSION = /, "", v); sub(/;.*/, "", v); mv = v }
  /PRODUCT_BUNDLE_IDENTIFIER = org\.ninil\.boringmeeting;/ { app = 1 }
  /^\t\t\};$/ { if (app && mv != "") { print mv; exit } }
' "$PBXPROJ"
