#!/usr/bin/env python3
"""Read Codex quota through its local app-server; no model requests or token handling."""
import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time


def find_codex():
    candidates = [os.environ.get('CODEX_BINARY'), shutil.which('codex')]
    for folder in (Path('/Applications'), Path.home() / 'Applications'):
        for app in ('ChatGPT', 'Codex'):
            candidates.append(str(folder / f'{app}.app/Contents/Resources/codex'))
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise RuntimeError('Codex executable not found. Install Codex or set CODEX_BINARY.')


def normalize(result):
    buckets = result.get('rateLimitsByLimitId')
    if not buckets:
        legacy = result.get('rateLimits')
        buckets = {legacy.get('limitId') or 'codex': legacy} if legacy else {}
    windows = []
    for key, bucket in sorted(buckets.items(), key=lambda item: (item[0] != 'codex', item[0])):
        if not isinstance(bucket, dict):
            continue
        for slot in ('primary', 'secondary'):
            window = bucket.get(slot)
            if not window:
                continue
            used = window.get('usedPercent')
            if not isinstance(used, (int, float)):
                continue
            minutes = window.get('windowDurationMins')
            label = {300: '5-hour', 10080: 'Weekly'}.get(minutes)
            if label is None:
                label = f'{minutes} min' if minutes else slot.capitalize()
            windows.append({'id': f'{key}/{slot}', 'bucket': bucket.get('limitName') or key,
                            'label': label, 'used': used, 'remaining': max(0, min(100, 100-used)),
                            'resetsAt': window.get('resetsAt')})
    if not windows:
        raise RuntimeError('No usage windows available. Sign in to Codex with your ChatGPT account.')
    return {'fetchedAt': time.time(), 'windows': windows}


def fetch(timeout=25):
    proc = subprocess.Popen([find_codex(), 'app-server'], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    pending = b''

    def send(message):
        proc.stdin.write((json.dumps(message)+'\n').encode())
        proc.stdin.flush()

    def receive(wanted):
        nonlocal pending
        while True:
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                message = json.loads(line)
                if message.get('id') == wanted:
                    if 'error' in message:
                        raise RuntimeError('Codex could not read usage. Check your sign-in and connection.')
                    return message['result']
                if 'method' in message and 'id' in message:
                    send({'id': message['id'], 'error': {'code': -32601, 'message': 'Unsupported client request'}})
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise RuntimeError('Usage request timed out. Check your connection and Codex sign-in.')
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('Codex app-server closed before returning usage.')
            pending += chunk

    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {
            'name': 'codex_usage_menubar', 'title': 'Codex Usage', 'version': '1.0.0'}}})
        receive(1)
        send({'method': 'initialized', 'params': {}})
        send({'id': 2, 'method': 'account/rateLimits/read'})
        return normalize(receive(2))
    finally:
        selector.close()
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        proc.stdin.close()
        proc.stdout.close()


def main():
    if sys.version_info < (3, 9):
        print(json.dumps({'error': 'Python 3.9 or newer is required. Please update Python.'}))
        return 1
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', type=float, metavar='SECONDS', help='Repeat at this interval (minimum 30 seconds).')
    args = parser.parse_args()
    if args.watch is not None and args.watch < 30:
        parser.error('--watch must be at least 30 seconds')
    while True:
        try:
            print(json.dumps(fetch()), flush=True)
        except Exception as error:
            print(json.dumps({'error': str(error)}), flush=True)
            if args.watch is None:
                return 1
        if args.watch is None:
            return 0
        time.sleep(args.watch)


if __name__ == '__main__':
    sys.exit(main())
