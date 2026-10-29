"""Exercise real version/tag/dirty-checkout gates without signing or network calls."""
import importlib.util
import pathlib
import json
import os
import sys
from unittest.mock import patch
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('grove_release', root / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

def rejected(call):
    try: call()
    except (ValueError, subprocess.CalledProcessError): return
    raise AssertionError('Unsafe release input was accepted')

with tempfile.TemporaryDirectory(prefix='grove-release-policy-') as directory:
    repo = pathlib.Path(directory)
    def git(*args):
        subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
    git('init', '-b', 'main')
    (repo / 'release.json').write_text(json.dumps({'version':'0.3.0'}))
    git('add', 'release.json')
    git('-c', 'user.name=Release Check', '-c', 'user.email=check@example.test', 'commit', '--allow-empty', '-m', 'baseline')
    git('tag', 'v0.3.0')
    release.validate_tag('v0.3.0', '0.3.0', repo)
    for tag in ['v0.2.0', 'main', 'v0.3.0;echo unsafe', 'v00.3.0']:
        rejected(lambda: release.validate_tag(tag, '0.3.0', repo))
    no_apple = {key: value for key,value in os.environ.items() if not key.startswith(('APPLE_', 'GROVE_SIGNING_', 'GROVE_NOTARY_'))}
    with patch.object(release, 'ROOT', repo), patch.object(sys, 'argv', ['release.py','--mode','tagged','--tag','v0.3.0','--preflight-only']), patch.dict(os.environ, no_apple, clear=True):
        release.main()
    (repo / 'dirty').write_text('not committed')
    rejected(lambda: release.validate_tag('v0.3.0', '0.3.0', repo))
print('PASS: tagged preflight without Apple credentials, version mismatch and dirty checkout rejection')
