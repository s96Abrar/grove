"""Launch the actual .app twice, verifying its PTY shell survives app termination."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

app = pathlib.Path(__file__).resolve().parents[1] / 'dist' / 'Grove.app'
root = pathlib.Path(tempfile.mkdtemp(prefix='grove-app-relaunch-'))
env = dict(os.environ, GROVE_VERIFY_PATH=str(root))
tmux = shutil.which('tmux') or next((p for p in ['/opt/homebrew/bin/tmux', '/usr/local/bin/tmux'] if os.access(p, os.X_OK)), None)
assert tmux, 'Install tmux with brew install tmux'
env = {k: v for k, v in env.items() if k not in ['STY', 'TMUX', 'TMUX_PANE', 'TMUX_TMPDIR']}
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
    listed = subprocess.run([tmux, '-L', 'grove', 'list-sessions', '-F', '#{session_name}'], env=env, capture_output=True, text=True, check=True)
    assert listed.stdout.splitlines().count('grove-' + pane) == 1, 'Duplicate session created'
    assert (root / 'screen-env').read_text() == '', 'Gemini GNU screen warning would trigger'
    assert (root / 'tmux-env').read_text(), 'Persistent shell did not run in tmux'
    result = dict(result='pass', first_app_pid=first_app, second_app_pid=process.pid,
                  shell_pid=first_shell, fixture=str(root), stable_layout=True,
                  startup_command_reran=False, matching_tmux_sessions=1, no_gnu_screen_context=True,
                  limits=['Application termination used SIGTERM, not a menu action.',
                          'No screenshot, visual TUI, agent authentication or scrollback rendering assertion.'])
    evidence = app.parents[1] / 'docs' / 'evidence' / 'grove-app-relaunch.json'
    evidence.parent.mkdir(parents=True, exist_ok=True)
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
                    subprocess.run([tmux, '-L', 'grove', 'kill-session', '-t', '=grove-' + pane['id']], env=env, capture_output=True)
