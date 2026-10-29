#!/usr/bin/env python3
"""Stage, validate and atomically replace the local app bundle; never alter credentials."""
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def command(*args):
    return subprocess.check_output(args, text=True).strip()

def main():
    config = json.loads((ROOT / 'release.json').read_text())
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', config['version']):
        raise SystemExit('release.json must contain a numeric semantic version')
    if not isinstance(config['build'], int) or config['build'] < 1:
        raise SystemExit('Build number must be a positive integer')
    identity = os.environ.get('GROVE_SIGNING_IDENTITY', '-')
    if identity != '-' and not re.fullmatch(r'[A-Fa-f0-9]{40}', identity):
        raise SystemExit('GROVE_SIGNING_IDENTITY must be a certificate SHA-1, not a display name')
    sources = [pathlib.Path(p).resolve(strict=True) for p in sys.argv[1:]]
    if not sources:
        raise SystemExit('Provide at least one compiled Grove executable')
    destination = ROOT / 'dist' / 'Grove.app'
    destination.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.grove-package-', dir=destination.parent) as folder:
        staging = pathlib.Path(folder)
        app = staging / 'Grove.app'
        contents = app / 'Contents'
        executable = contents / 'MacOS' / 'Grove'
        resources = contents / 'Resources'
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        if len(sources) == 1:
            shutil.copyfile(sources[0], executable)
        else:
            subprocess.run(['/usr/bin/lipo', '-create', *map(str, sources), '-output', str(executable)], check=True)
        executable.chmod(0o755)
        shutil.copytree(ROOT / 'Notices', resources / 'Notices')
        shutil.copyfile(ROOT / 'LICENSE', resources / 'LICENSE')
        shutil.copyfile(ROOT / 'scripts' / 'grove', resources / 'grove')
        (resources / 'grove').chmod(0o755)
        subprocess.run(['bash', str(ROOT / 'scripts' / 'build-icon.sh'), str(staging / 'AppIcon.iconset'), str(resources / 'AppIcon.icns')], check=True)
        info = dict(CFBundleExecutable='Grove', CFBundleIdentifier=config['bundle_identifier'],
                    CFBundleName='Grove', CFBundleDisplayName='Grove', CFBundlePackageType='APPL',
                    CFBundleShortVersionString=config['version'], CFBundleVersion=str(config['build']),
                    CFBundleIconFile='AppIcon', LSMinimumSystemVersion=config['minimum_macos'],
                    LSApplicationCategoryType='public.app-category.developer-tools', NSHighResolutionCapable=True,
                    CFBundleURLTypes=[dict(CFBundleURLName=config['bundle_identifier'], CFBundleURLSchemes=['grove'])],
                    NSHumanReadableCopyright='Copyright © 2026 Grove contributors. MIT License.')
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        commit = command('git', '-C', str(ROOT), 'rev-parse', 'HEAD')
        dirty = bool(command('git', '-C', str(ROOT), 'status', '--porcelain'))
        build = dict(version=config['version'], build=config['build'], commit=commit, dirty=dirty,
                     architectures=command('/usr/bin/lipo', '-archs', str(executable)).split(),
                     swift=command('swift', '--version'), signing='adhoc' if identity == '-' else 'developer-id')
        (resources / 'BuildInfo.json').write_text(json.dumps(build, indent=2) + '\n')
        signature = ['/usr/bin/codesign', '--force', '--options', 'runtime', '--sign', identity]
        if identity != '-':
            signature.append('--timestamp')
            if os.environ.get('GROVE_SIGNING_KEYCHAIN'):
                signature += ['--keychain', os.environ['GROVE_SIGNING_KEYCHAIN']]
        subprocess.run(signature + [str(app)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        previous = staging / 'Previous.app'
        if destination.exists(): destination.rename(previous)
        try:
            app.rename(destination)
        except BaseException:
            if previous.exists(): previous.rename(destination)
            raise
    print(destination)

if __name__ == '__main__':
    main()
