#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh
python3 scripts/verify_app.py dist/Grove.app

destination="${GROVE_INSTALL_DIR:-/Applications}"
mkdir -p "$destination"
staging=$(mktemp -d "$destination/.grove-install.XXXXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/Grove.app "$staging/Grove.app"
python3 scripts/verify_app.py "$staging/Grove.app"
if [ -e "$destination/Grove.app" ]; then
  backup="$destination/Grove backup $(date +%Y%m%d-%H%M%S).app"
  if [ -e "$backup" ]; then backup="$destination/Grove backup $(date +%Y%m%d-%H%M%S)-$$.app"; fi
  mv "$destination/Grove.app" "$backup"
  if ! mv "$staging/Grove.app" "$destination/Grove.app"; then
    mv "$backup" "$destination/Grove.app"
    exit 1
  fi
  echo "Previous installation saved at $backup"
else
  mv "$staging/Grove.app" "$destination/Grove.app"
fi
echo "Installed $destination/Grove.app"
open "$destination/Grove.app"
