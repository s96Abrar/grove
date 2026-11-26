#!/usr/bin/env python3
"""Measure Grove's launch and idle performance on this Mac.

Launches the built app (dist/Grove.app by default) several times in an
isolated test workspace and reports:

  time_to_terminal_ms  process start -> first terminal pane has run its
                       shell command (window up, PTY and tmux session
                       started, login shell finished starting)
  rss_mb               resident memory a few seconds after that
  idle_cpu_pct         average CPU over a quiet sampling window
  bundle_mb / executable_mb  size on disk

Uses the same GROVE_VERIFY_PATH test mode as Checks/app_relaunch_check.py,
so your real workspace, preferences and tmux sessions are not touched.
Needs macOS, tmux and a built app (`make build`). No network access.

  python3 scripts/perf.py                  # 5 runs, table
  python3 scripts/perf.py --runs 10 --json perf.json --markdown perf.md
"""
import argparse
import json
import os
import pathlib
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def cpu_seconds(pid):
    """Cumulative CPU time of a process from ps (formats M:SS.ss or H:MM:SS)."""
    out = subprocess.run(['/bin/ps', '-o', 'time=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
    if not out:
        raise RuntimeError('process exited')
    days, _, clock = out.rpartition('-')
    parts = [float(p) for p in clock.split(':')]
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + part
    return seconds + (int(days) * 86400 if days else 0)


def rss_mb(pid):
    out = subprocess.run(['/bin/ps', '-o', 'rss=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
    if not out:
        raise RuntimeError('process exited')
    return int(out) / 1024


def size_mb(path):
    if path.is_file():
        return path.stat().st_size / 1_048_576
    return sum(p.stat().st_size for p in path.rglob('*') if p.is_file() and not p.is_symlink()) / 1_048_576


def one_run(app, tmux, settle, sample, timeout):
    workspace = pathlib.Path(tempfile.mkdtemp(prefix='grove-perf-'))
    env = {k: v for k, v in os.environ.items() if k not in ('STY', 'TMUX', 'TMUX_PANE', 'TMUX_TMPDIR')}
    env['GROVE_VERIFY_PATH'] = str(workspace)
    marker = workspace / 'shell-pid'
    process = subprocess.Popen([str(app / 'Contents' / 'MacOS' / 'Grove')], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    started = time.monotonic()
    try:
        while not marker.exists():
            if process.poll() is not None:
                raise RuntimeError(f'Grove exited during launch (status {process.returncode})')
            if time.monotonic() - started > timeout:
                raise RuntimeError(f'No interactive terminal within {timeout:.0f} s')
            time.sleep(0.01)
        ready_ms = (time.monotonic() - started) * 1000
        time.sleep(settle)
        memory = rss_mb(process.pid)
        cpu_before, wall_before = cpu_seconds(process.pid), time.monotonic()
        time.sleep(sample)
        cpu_after, wall_after = cpu_seconds(process.pid), time.monotonic()
        idle_cpu = 100 * (cpu_after - cpu_before) / (wall_after - wall_before)
        return dict(time_to_terminal_ms=ready_ms, rss_mb=memory, idle_cpu_pct=idle_cpu)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
        state = workspace / 'grove-test-state.json'
        if state.exists():
            for tabs in json.loads(state.read_text()).get('tabs', {}).values():
                for tab in tabs:
                    for pane in tab['panes']:
                        subprocess.run([tmux, '-L', 'grove', 'kill-session', '-t', '=grove-' + pane['id']],
                                       env=env, capture_output=True)
        shutil.rmtree(workspace, ignore_errors=True)


def summarize(values):
    return dict(median=statistics.median(values), min=min(values), max=max(values))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist' / 'Grove.app', help='app bundle to measure')
    parser.add_argument('--runs', type=int, default=5, help='launches to measure (default 5)')
    parser.add_argument('--warmup', type=int, default=1, help='unrecorded launches first, to fill disk caches (default 1)')
    parser.add_argument('--settle', type=float, default=5, help='seconds to wait after the terminal is ready (default 5)')
    parser.add_argument('--sample', type=float, default=10, help='seconds of idle CPU sampling (default 10)')
    parser.add_argument('--timeout', type=float, default=60, help='seconds to wait for the terminal (default 60)')
    parser.add_argument('--json', type=pathlib.Path, help='also write results as JSON')
    parser.add_argument('--markdown', type=pathlib.Path, help='also write (append) a Markdown table, e.g. $GITHUB_STEP_SUMMARY')
    args = parser.parse_args()

    if platform.system() != 'Darwin':
        sys.exit('Grove is a macOS app; run this on a Mac.')
    executable = args.app / 'Contents' / 'MacOS' / 'Grove'
    if not executable.exists():
        sys.exit(f'No app at {args.app}. Build it first with `make build`.')
    tmux = shutil.which('tmux') or next((p for p in ['/opt/homebrew/bin/tmux', '/usr/local/bin/tmux'] if os.access(p, os.X_OK)), None)
    if not tmux:
        sys.exit('tmux is required: brew install tmux')

    for index in range(args.warmup):
        print(f'warm-up {index + 1}/{args.warmup}…', file=sys.stderr)
        one_run(args.app, tmux, 1, 1, args.timeout)
    runs = []
    for index in range(args.runs):
        print(f'run {index + 1}/{args.runs}…', file=sys.stderr)
        runs.append(one_run(args.app, tmux, args.settle, args.sample, args.timeout))

    info = json.loads((ROOT / 'release.json').read_text()) if (ROOT / 'release.json').exists() else {}
    commit = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    host = dict(
        machine=platform.machine(),
        macos=platform.mac_ver()[0],
        cpu=subprocess.run(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string'], capture_output=True, text=True).stdout.strip(),
        memory_gb=round(int(subprocess.run(['/usr/sbin/sysctl', '-n', 'hw.memsize'], capture_output=True, text=True).stdout.strip() or 0) / 2**30),
    )
    result = dict(
        version=info.get('version'), commit=commit or None, host=host, runs=len(runs),
        time_to_terminal_ms=summarize([r['time_to_terminal_ms'] for r in runs]),
        rss_mb=summarize([r['rss_mb'] for r in runs]),
        idle_cpu_pct=summarize([r['idle_cpu_pct'] for r in runs]),
        bundle_mb=size_mb(args.app), executable_mb=size_mb(executable),
        raw=runs,
    )

    rows = [
        ('Launch to interactive terminal', 'time_to_terminal_ms', '{:.0f} ms'),
        ('Memory (RSS) at idle', 'rss_mb', '{:.0f} MB'),
        ('CPU at idle', 'idle_cpu_pct', '{:.1f} %'),
    ]
    lines = [
        f"### Grove {result['version'] or ''} performance ({result['commit'] or 'local build'})",
        '',
        f"{host['cpu'] or host['machine']}, {host['memory_gb']} GB, macOS {host['macos']}; median of {len(runs)} runs (min–max).",
        '',
        '| Metric | Median | Range |',
        '|---|---|---|',
    ]
    for label, key, fmt in rows:
        stats = result[key]
        lines.append(f"| {label} | {fmt.format(stats['median'])} | {fmt.format(stats['min'])} – {fmt.format(stats['max'])} |")
    lines.append(f"| App bundle size | {result['bundle_mb']:.1f} MB | |")
    lines.append(f"| Executable size | {result['executable_mb']:.1f} MB | |")
    table = '\n'.join(lines) + '\n'

    print(table)
    if args.json:
        args.json.write_text(json.dumps(result, indent=2) + '\n')
    if args.markdown:
        with args.markdown.open('a') as handle:
            handle.write(table + '\n')


if __name__ == '__main__':
    main()
