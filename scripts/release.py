#!/usr/bin/env python3
"""Build local or tagged ad-hoc-signed archives under the accepted release policy."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()

def validate_tag(tag, version, root=ROOT):
    if not re.fullmatch(r'v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)', tag or '') or tag != 'v' + version:
        raise ValueError('Release tag must exactly match v' + version)
    if run('git', '-C', str(root), 'status', '--porcelain'):
        raise ValueError('Tagged releases require a clean Git checkout')
    head = run('git', '-C', str(root), 'rev-parse', 'HEAD')
    tagged = run('git', '-C', str(root), 'rev-parse', '--verify', 'refs/tags/' + tag + '^{commit}')
    if head != tagged:
        raise ValueError('Release tag does not point to HEAD')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['local', 'tagged'], default='local')
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME', ''))
    parser.add_argument('--preflight-only', action='store_true')
    args = parser.parse_args()
    config = json.loads((ROOT / 'release.json').read_text())
    env = dict(os.environ)
    tagged = args.mode == 'tagged'
    if tagged:
        validate_tag(args.tag, config['version'], ROOT)
        env['GROVE_ARCHS'] = 'arm64 x86_64'
    if args.preflight_only:
        print('Preflight passed: ' + args.mode)
        return
    subprocess.run(['bash', str(ROOT / 'scripts/build-app.sh')], cwd=ROOT, env=env, check=True)
    app = ROOT / 'dist/Grove.app'
    verify = ['python3', str(ROOT / 'scripts/verify_app.py'), str(app)] + (['--release'] if tagged else [])
    subprocess.run(verify, check=True)
    build = json.loads((app / 'Contents/Resources/BuildInfo.json').read_text())
    architecture = 'universal' if set(build['architectures']) == {'arm64', 'x86_64'} else '-'.join(build['architectures'])
    channel = '' if tagged else '-local'
    folder = ROOT / 'dist/releases' / (config['version'] + channel)
    folder.mkdir(parents=True, exist_ok=False)
    archive = folder / f"Grove-{config['version']}-macos-{architecture}{channel}.zip"
    try:
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(archive)], check=True)
        # Round-trip the actual delivery archive; a valid source bundle is not sufficient.
        with tempfile.TemporaryDirectory(prefix='grove-install-check-') as check:
            subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), check], check=True)
            subprocess.run(['python3', str(ROOT / 'scripts/verify_app.py'), str(pathlib.Path(check) / 'Grove.app')] + (['--release'] if tagged else []), check=True)
        sha256 = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(archive.read_bytes()).hexdigest()
        (folder / 'SHA256SUMS').write_text(sha256 + '  ' + archive.name + '\n')
        manifest = dict(build, distribution='tagged-adhoc' if tagged else 'local-adhoc', notarized=False,
                        tag=args.tag if tagged else None, archive=archive.name, sha256=sha256)
        (folder / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    except BaseException:
        # An incomplete archive must never be mistaken for a release.
        archive.unlink(missing_ok=True)
        raise
    print(folder)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit('Release stopped: ' + str(error))
