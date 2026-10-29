"""Exercise real version/tag/dirty-checkout gates without signing or network calls."""
import importlib.util
import pathlib
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
    git('-c', 'user.name=Release Check', '-c', 'user.email=check@example.test', 'commit', '--allow-empty', '-m', 'baseline')
    git('tag', 'v0.3.0')
    release.validate_tag('v0.3.0', '0.3.0', repo)
    for tag in ['v0.2.0', 'main', 'v0.3.0;echo unsafe', 'v00.3.0']:
        rejected(lambda: release.validate_tag(tag, '0.3.0', repo))
    (repo / 'dirty').write_text('not committed')
    rejected(lambda: release.validate_tag('v0.3.0', '0.3.0', repo))
    rejected(lambda: release.signing_environment({}))
    rejected(lambda: release.signing_environment({'GROVE_SIGNING_IDENTITY': '-'}))
    rejected(lambda: release.signing_environment({'GROVE_SIGNING_IDENTITY': 'A'*40}))
print('PASS: matching immutable tag, version mismatch, dirty checkout, missing signing/notary gates')
