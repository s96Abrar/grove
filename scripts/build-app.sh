#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHS="${GROVE_ARCHS:-$(uname -m)}"
MINIMUM=$(python3 -c 'import json; print(json.load(open("release.json"))["minimum_macos"])')
BINARIES=()
for arch in $ARCHS; do
  case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
  # Native SwiftPM keeps build-tool plugins on the host when cross-compiling.
  TRIPLE="$arch-apple-macosx$MINIMUM"
  SCRATCH="$PWD/.build/release-$arch"
  swift build --build-system native --scratch-path "$SCRATCH" --jobs "${GROVE_BUILD_JOBS:-2}" -c release --triple "$TRIPLE" --force-resolved-versions
  BIN_DIR=$(swift build --build-system native --scratch-path "$SCRATCH" -c release --triple "$TRIPLE" --show-bin-path)
  BINARIES+=("$BIN_DIR/Grove")
done
python3 scripts/package_app.py "${BINARIES[@]}"
