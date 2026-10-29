"""Launch the actual .app twice, verifying its PTY shell survives app termination."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

app = pathlib.Path(__file__).resolve().parents[1] / 'dist' / 'Grove.app'
root = pathlib.Path(tempfile.mkdtemp(prefix='grove-app-relaunch-'))
env = dict(os.environ, GROVE_VERIFY_PATH=str(root))
process = None
state = None

def wait_for(path, predicate=lambda p: p.exists()):
    end = time.monotonic() + 20
    while time.monotonic() < end:
        if process.poll() is not None:
            raise AssertionError('Grove exited before verification: ' + str(process.returncode))
        if predicate(path): return
        time.sleep(.1)
    raise AssertionError('Timed out waiting for ' + str(path))

try:
    process = subprocess.Popen([str(app / 'Contents' / 'MacOS' / 'Grove')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for(root / 'shell-pid')
    wait_for(root / 'grove-runtime.json')
    first_app = process.pid
    first_shell = int((root / 'shell-pid').read_text())
    marker_time = (root / 'shell-pid').stat().st_mtime_ns
    state = json.loads((root / 'grove-test-state.json').read_text())
    process.terminate()
    process.wait(timeout=10)
    os.kill(first_shell, 0)
    process = subprocess.Popen([str(app / 'Contents' / 'MacOS' / 'Grove')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for(root / 'grove-runtime.json', lambda p: p.exists() and json.loads(p.read_text())['pid'] == process.pid)
    time.sleep(2)
    assert process.poll() is None, 'Relaunched app exited'
    assert int((root / 'shell-pid').read_text()) == first_shell, 'Relaunch started a different shell'
    assert (root / 'shell-pid').stat().st_mtime_ns == marker_time, 'Startup command reran'
    os.kill(first_shell, 0)
    second_state = json.loads((root / 'grove-test-state.json').read_text())
    assert state['tabs'] == second_state['tabs'], 'Layout IDs changed'
    pane = next(iter(state['tabs'].values()))[0]['panes'][0]['id']
    listed = subprocess.run(['/usr/bin/screen', '-list', 'grove-' + pane], capture_output=True)
    assert listed.stdout.count(('.grove-' + pane).encode()) == 1, 'Duplicate session created'
    result = dict(result='pass', first_app_pid=first_app, second_app_pid=process.pid,
                  shell_pid=first_shell, fixture=str(root), stable_layout=True,
                  startup_command_reran=False, matching_screen_sessions=1,
                  limits=['Application termination used SIGTERM, not a menu action.',
                          'No screenshot, visual TUI, agent authentication or scrollback rendering assertion.'])
    evidence = app.parents[1] / 'docs' / 'evidence' / 'grove-app-relaunch.json'
    evidence.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    if state:
        for tabs in state['tabs'].values():
            for tab in tabs:
                for pane in tab['panes']:
                    subprocess.run(['/usr/bin/screen', '-S', 'grove-' + pane['id'], '-X', 'quit'], capture_output=True)
