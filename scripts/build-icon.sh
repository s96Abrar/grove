#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_DIR="${1:-build/AppIcon.iconset}"
mkdir -p "$ICON_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICON_DIR/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICON_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_DIR" -o "${2:-build/AppIcon.icns}"
