#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -m)" in
  arm64) ARCH=arm64; SHA=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
  x86_64) ARCH=amd64; SHA=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
  *) echo "Workflow linting supports macOS arm64/x86_64" >&2; exit 1 ;;
esac
TOOLS="$PWD/build/tools/actionlint-1.7.12-$ARCH"
mkdir -p "$TOOLS"
if [ ! -x "$TOOLS/actionlint" ]; then
  ARCHIVE="$TOOLS/actionlint.tar.gz"
  curl --fail --location --silent --show-error "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_darwin_${ARCH}.tar.gz" -o "$ARCHIVE"
  printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c -
  tar -xzf "$ARCHIVE" -C "$TOOLS" actionlint
fi
"$TOOLS/actionlint" -shellcheck= -pyflakes= .github/workflows/*.yml
