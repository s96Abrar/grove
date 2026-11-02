"""Exercise Grove's actual Swift wrapper and cleanup with a PTY; no agent authentication."""
import errno
import json
import os
import pathlib
import pty
import select
import shlex
import shutil
import subprocess
import tempfile
import time
import uuid

repo = pathlib.Path(__file__).resolve().parents[1]
probe = repo / 'build/checks/terminal-backend-probe'
tmux = shutil.which('tmux') or next((p for p in ['/opt/homebrew/bin/tmux', '/usr/local/bin/tmux'] if os.access(p, os.X_OK)), None)
assert tmux, 'Install tmux with brew install tmux'
root = pathlib.Path(tempfile.mkdtemp(prefix="grove tmux 'quoted' "))
session = 'grove-check-' + str(uuid.uuid4())
sibling = 'grove-check-' + str(uuid.uuid4())
legacy = 'grove-check-' + str(uuid.uuid4())
master = process = None
# This is a fresh PTY, not the parent agent terminal's multiplexer context.
env = {k: v for k, v in os.environ.items() if k not in ['STY', 'TMUX', 'TMUX_PANE', 'TMUX_TMPDIR']}
env.update(TERM='xterm-256color', GROVE_PANE_ID=session, GROVE_WORKTREE_PATH=str(root))

def tmux_run(*args):
    return subprocess.run([tmux, '-L', 'grove', *args], env=env, capture_output=True, text=True)

def attach(name):
    global master, process
    script = subprocess.check_output([str(probe), 'wrapper', name, str(root)], text=True)
    master, slave = pty.openpty()
    process = subprocess.Popen(['/bin/zsh', '-c', script], stdin=slave, stdout=slave, stderr=slave,
                               cwd=root, env=env, start_new_session=True)
    os.close(slave)

def pump(seconds):
    end = time.monotonic() + seconds
    output = bytearray()
    while time.monotonic() < end:
        if select.select([master], [], [], min(.1, max(0, end-time.monotonic())))[0]:
            try:
                data = os.read(master, 65536)
                if not data: break
                output.extend(data)
            except OSError as error:
                if error.errno == errno.EIO: break
                raise
    return output

def send(command):
    os.write(master, (command + '\n').encode())
    pump(.5)

def wait_file(name):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if (root / name).exists(): return root / name
        assert process.poll() is None, 'Attached terminal exited before marker: ' + name
        pump(.1)
    raise AssertionError('Timed out waiting for ' + name)

def disconnect():
    global master, process
    pump(.5)
    process.wait(timeout=5)
    os.close(master); master = None; process = None

try:
    attach(session)
    pump(1)
    send("printf '%s' $$ > identity; printf '%s|%s|%s|%s' \"${STY-}\" \"$TERM\" \"$GROVE_PANE_ID\" \"$GROVE_WORKTREE_PATH\" > environment")
    pid = int(wait_file('identity').read_text())
    context = wait_file('environment').read_text().split('|')
    assert context == ['', 'tmux-256color', session, str(root)], context
    # GNU screen warning's exact installed Gemini predicate is Boolean(STY).
    assert not context[0], 'Gemini GNU screen detector would still trigger'
    assert tmux_run('show-options', '-gv', 'status').stdout.strip() == 'off'
    send("stty -echo -icanon; touch key-ready; dd bs=1 count=1 of=control-byte 2>/dev/null; stty sane")
    wait_file('key-ready')
    os.write(master, b'\x02')
    pump(.5)
    assert wait_file('control-byte').read_bytes() == b'\x02', 'tmux captured Ctrl-B'
    assert tmux_run('detach-client', '-s', '=' + session).returncode == 0
    disconnect(); os.kill(pid, 0)
    attach(session); pump(1)
    send("printf '%s' $$ > reattached")
    assert int(wait_file('reattached').read_text()) == pid, 'Reattach created another shell'
    assert tmux_run('list-sessions', '-F', '#{session_name}').stdout.splitlines().count(session) == 1
    # A second pane must not reuse the first pane's context from the shared server.
    assert tmux_run('detach-client', '-s', '=' + session).returncode == 0
    disconnect()
    env['GROVE_PANE_ID'] = sibling
    attach(sibling); pump(1)
    send("printf '%s' $$ > sibling-pid; printf '%s' \"$GROVE_PANE_ID\" > sibling-context")
    sibling_pid = int(wait_file('sibling-pid').read_text())
    assert wait_file('sibling-context').read_text() == sibling
    subprocess.run([str(probe), 'end', session], check=True, env=env)
    assert tmux_run('has-session', '-t', '=' + session).returncode != 0
    assert tmux_run('has-session', '-t', '=' + sibling).returncode == 0
    os.kill(sibling_pid, 0)
    assert tmux_run('detach-client', '-s', '=' + sibling).returncode == 0
    disconnect()
    # A legacy screen shell reattaches with its original PID; no tmux replacement.
    subprocess.run(['/usr/bin/screen', '-U', '-dmS', legacy, '/bin/zsh', '-f'], env=env, cwd=root, check=True)
    attach(legacy); pump(1)
    send("printf '%s' $$ > legacy-pid")
    legacy_pid = int(wait_file('legacy-pid').read_text())
    assert tmux_run('has-session', '-t', '=' + legacy).returncode != 0
    subprocess.run(['/usr/bin/screen', '-S', legacy, '-X', 'detach'], capture_output=True, check=True)
    disconnect(); os.kill(legacy_pid, 0)
    attach(legacy); pump(1)
    send("printf '%s' $$ > legacy-reattached")
    assert int(wait_file('legacy-reattached').read_text()) == legacy_pid
    subprocess.run([str(probe), 'end', legacy], check=True, env=env)
    disconnect()
    print(json.dumps(dict(result='pass', backend='tmux', tmux_version=subprocess.check_output([tmux, '-V'], text=True).strip(),
                          shell_pid=pid, no_screen_environment=True, ctrl_b_passes=True, same_pid_on_reattach=True,
                          sibling_survives_cleanup=True, separate_pane_context=True, legacy_screen_preserved=True,
                          fixture=str(root)), indent=2))
finally:
    for name in [session, sibling, legacy]:
        subprocess.run([str(probe), 'end', name], env=env, capture_output=True)
    if process is not None:
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.terminate()
    if master is not None: os.close(master)
