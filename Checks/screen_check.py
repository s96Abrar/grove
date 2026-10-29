"""Exercise the same PTY + screen backend Grove uses, confined to a fresh session."""
import errno
import os
import pathlib
import pty
import select
import signal
import subprocess
import tempfile
import time
import uuid

session = 'grove-check-' + str(uuid.uuid4())
root = pathlib.Path(tempfile.mkdtemp(prefix='grove-screen-check-'))
marker = root / 'identity'
master = slave = process = None

def attach():
    global master, slave, process
    master, slave = pty.openpty()
    env = dict(os.environ, TERM='xterm-256color')
    listed = subprocess.run(['/usr/bin/screen', '-list', session], capture_output=True)
    # macOS screen can return nonzero even when a matching session is listed.
    if ('.' + session).encode() not in listed.stdout:
        subprocess.run(['/usr/bin/screen', '-U', '-dmS', session, '-h', '10000', '/bin/zsh', '-f'], cwd=root, env=env, check=True)
    process = subprocess.Popen(['/usr/bin/screen', '-U', '-D', '-r', session], stdin=slave, stdout=slave, stderr=slave,
                               cwd=root, env=env, start_new_session=True)
    os.close(slave)
    slave = None

def pump(seconds):
    end = time.monotonic() + seconds
    data = bytearray()
    while time.monotonic() < end:
        if select.select([master], [], [], min(.1, max(0, end-time.monotonic())))[0]:
            try:
                chunk = os.read(master, 65536)
                if not chunk: break
                data.extend(chunk)
            except OSError as error:
                if error.errno == errno.EIO: break
                raise
    return bytes(data)

try:
    attach()
    pump(1)
    os.write(master, (f'printf "%s" $$ > {marker}\n').encode())
    pump(1)
    assert marker.exists(), 'PTY input did not reach interactive shell'
    pid = marker.read_text()
    detached = subprocess.run(['/usr/bin/screen', '-S', session, '-X', 'detach'], capture_output=True)
    assert detached.returncode == 0, detached.stderr
    pump(.5)
    process.wait(timeout=5)
    os.close(master)
    master = None
    os.kill(int(pid), 0)
    attach()
    pump(1)
    os.write(master, (f'printf "%s" $$ > {root / "reattached"}\n').encode())
    pump(1)
    assert (root / 'reattached').read_text() == pid, 'Reattach started a different shell'
    print('PASS: interactive PTY input, daemon survives detach, reattach preserves shell PID')
    print('Fixture:', root)
finally:
    subprocess.run(['/usr/bin/screen', '-S', session, '-X', 'quit'], capture_output=True)
    if process is not None:
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.terminate()
    if master is not None: os.close(master)
