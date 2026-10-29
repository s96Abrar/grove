#!/bin/bash
# Only called in an isolated CI runner. Never changes the login/default keychain.
set -euo pipefail
: "${RUNNER_TEMP:?This helper is for an isolated CI runner}"
if [ "${1:-}" = "cleanup" ]; then
  if [ -n "${GROVE_SIGNING_KEYCHAIN:-}" ] && [ -f "$GROVE_SIGNING_KEYCHAIN" ]; then
    security delete-keychain "$GROVE_SIGNING_KEYCHAIN"
  fi
  python3 - <<'PY'
import os, pathlib
for name in ['GROVE_NOTARY_KEY_PATH', 'GROVE_CERTIFICATE_PATH']:
    if os.environ.get(name): pathlib.Path(os.environ[name]).unlink(missing_ok=True)
PY
  exit 0
fi
: "${APPLE_CERTIFICATE_P12_BASE64:?Missing signing certificate}"
: "${APPLE_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${APPLE_API_KEY_P8:?Missing notarization API key}"
: "${GROVE_SIGNING_IDENTITY:?Missing certificate SHA-1}"
KEYCHAIN="$RUNNER_TEMP/grove-signing.keychain-db"
CERTIFICATE="$RUNNER_TEMP/grove-signing.p12"
API_KEY="$RUNNER_TEMP/grove-notary.p8"
KEYCHAIN_PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
# Register cleanup paths before importing anything, so an always() cleanup can recover a partial setup.
{
  echo "GROVE_SIGNING_KEYCHAIN=$KEYCHAIN"
  echo "GROVE_NOTARY_KEY_PATH=$API_KEY"
  echo "GROVE_CERTIFICATE_PATH=$CERTIFICATE"
} >> "$GITHUB_ENV"
export GROVE_CERTIFICATE_PATH="$CERTIFICATE" GROVE_NOTARY_KEY_PATH="$API_KEY"
python3 - <<'PY'
import base64, os
for name, data in [('GROVE_CERTIFICATE_PATH', base64.b64decode(os.environ['APPLE_CERTIFICATE_P12_BASE64'], validate=True)),
                   ('GROVE_NOTARY_KEY_PATH', os.environ['APPLE_API_KEY_P8'].encode())]:
    fd=os.open(os.environ[name], os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd,'wb') as out: out.write(data)
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 7200 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
