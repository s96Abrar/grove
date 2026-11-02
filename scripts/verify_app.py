#!/usr/bin/env python3
"""Verify the packaged product rather than trusting the build exit status."""
import argparse
import json
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('app', nargs='?', default='dist/Grove.app')
parser.add_argument('--release', action='store_true')
args = parser.parse_args()
app = pathlib.Path(args.app).resolve(strict=True)
root = pathlib.Path(__file__).resolve().parents[1]
config = json.loads((root / 'release.json').read_text())
info = plistlib.loads((app / 'Contents' / 'Info.plist').read_bytes())
for key, expected in [('CFBundleShortVersionString', config['version']), ('CFBundleVersion', str(config['build'])),
                      ('CFBundleIdentifier', config['bundle_identifier']), ('CFBundleIconFile', 'AppIcon')]:
    if info.get(key) != expected: raise SystemExit(f'Wrong {key}: {info.get(key)}')
for relative in ['Contents/MacOS/Grove', 'Contents/Resources/AppIcon.icns', 'Contents/Resources/LICENSE',
                 'Contents/Resources/tmux.conf', 'Contents/Resources/Notices/SwiftTerm-LICENSE.txt', 'Contents/Resources/BuildInfo.json']:
    if not (app / relative).is_file(): raise SystemExit('Missing bundle file: ' + relative)
subprocess.run(['/usr/bin/plutil', '-lint', str(app / 'Contents' / 'Info.plist')], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
signature = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(app)], capture_output=True, text=True, check=True).stderr
if 'runtime' not in signature: raise SystemExit('Hardened runtime is missing')
architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(app / 'Contents' / 'MacOS' / 'Grove')], text=True).split()
build = json.loads((app / 'Contents' / 'Resources' / 'BuildInfo.json').read_text())
if set(architectures) != set(build['architectures']): raise SystemExit('Build manifest architecture mismatch')
if args.release:
    if build['signing'] != 'adhoc':
        raise SystemExit('The accepted release policy uses ad-hoc signatures')
    if set(architectures) != {'arm64', 'x86_64'}: raise SystemExit('Tagged releases require both supported architectures')
    if build['dirty']: raise SystemExit('Tagged releases require a clean source checkout')
print(json.dumps(dict(result='pass', version=info['CFBundleShortVersionString'], architectures=architectures, release=args.release)))
