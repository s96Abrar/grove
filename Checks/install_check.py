"""Run the real installer in a disposable project; never install or launch a user app."""
import hashlib
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
source_app = repo / 'dist/Grove.app'
assert source_app.is_dir(), 'Build dist/Grove.app before checking installation'

with tempfile.TemporaryDirectory(prefix="grove install 'quoted' ") as temporary:
    root = pathlib.Path(temporary)
    project, tools, destination = root / 'project', root / 'tools', root / 'Applications with spaces'
    (project / 'scripts').mkdir(parents=True)
    tools.mkdir()
    (project / 'dist').mkdir()
    for name in ['install.sh', 'verify_app.py']:
        shutil.copy2(repo / 'scripts' / name, project / 'scripts' / name)
    shutil.copy2(repo / 'release.json', project / 'release.json')
    # Build behavior is verified elsewhere; supply a real signed app to the installer.
    (project / 'scripts/build-app.sh').write_text('#!/bin/bash\nset -euo pipefail\n/usr/bin/ditto ' + shlex.quote(str(source_app)) + ' dist/Grove.app\n')
    (tools / 'open').write_text('''#!/usr/bin/env python3
import os, pathlib, sys
with pathlib.Path(os.environ['GROVE_INSTALL_OPEN_LOG']).open('a') as log:
    log.write(sys.argv[1] + '\\n')
''')
    (tools / 'mv').write_text('''#!/usr/bin/env python3
import os, pathlib, sys
source = pathlib.Path(sys.argv[1])
if os.environ.get('GROVE_INSTALL_FAIL_REPLACE') == '1' and source.parent.name.startswith('.grove-install.'):
    sys.exit(42)
os.execv('/bin/mv', ['/bin/mv', *sys.argv[1:]])
''')
    for name in ['open', 'mv']: (tools / name).chmod(0o755)
    log = root / 'open-dispatch.log'
    env = dict(os.environ, PATH=str(tools) + ':' + os.environ.get('PATH', '/usr/bin:/bin'),
               GROVE_INSTALL_DIR=str(destination), GROVE_INSTALL_OPEN_LOG=str(log))
    installer = ['bash', str(project / 'scripts/install.sh')]

    def install(environment=env, expected=0):
        result = subprocess.run(installer, env=environment, capture_output=True, text=True)
        assert result.returncode == expected, result.stdout + result.stderr

    def digest(path): return hashlib.sha256(path.read_bytes()).digest()

    target = destination / 'Grove.app'
    executable = pathlib.Path('Contents/MacOS/Grove')
    install()
    assert digest(target / executable) == digest(source_app / executable)
    assert log.read_text().splitlines() == [str(target)]
    (target / 'old-install-marker').write_text('keep my previous installation')
    install()
    backups = list(destination.glob('Grove backup *.app'))
    assert len(backups) == 1 and (backups[0] / 'old-install-marker').read_text() == 'keep my previous installation'
    assert not (target / 'old-install-marker').exists()
    assert digest(target / executable) == digest(source_app / executable)
    (target / 'rollback-marker').write_text('restore me on failure')
    install(dict(env, GROVE_INSTALL_FAIL_REPLACE='1'), expected=1)
    assert (target / 'rollback-marker').read_text() == 'restore me on failure'
    assert digest(target / executable) == digest(source_app / executable)
    assert log.read_text().splitlines() == [str(target), str(target)], 'Failed install must not launch'
    assert not list(destination.glob('.grove-install.*')), 'Staging directories were not cleaned'
    assert (backups[0] / 'old-install-marker').exists(), 'Earlier backup was lost'
    print('PASS: signed-app install, quoted paths, previous-install backup, replacement-failure rollback, staging cleanup, launch dispatch')
