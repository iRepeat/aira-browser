#!/usr/bin/env python3
"""Bounded, tag-only HiLog capture. Does not clear logs, change device logging, or inspect screens."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import tempfile
import time

PREFIX = '[DEBUG-sync-perf-a31f]'
DEFAULT_HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=240)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 600:
        parser.error('--seconds must be 1..600')
    hdc = os.environ.get('HDC_BIN', DEFAULT_HDC)
    target = os.environ.get('HDC_TARGET', '')
    if not target:
        result = subprocess.run([hdc, 'list', 'targets'], capture_output=True, text=True, check=True)
        targets = [line.strip() for line in result.stdout.splitlines()
                   if line.strip() and line.strip() != '[Empty]']
        if len(targets) != 1:
            parser.error('Connect one phone or select it with HDC_TARGET.')
        target = targets[0]
    output = args.output or Path(tempfile.gettempdir()) / f'aira-sync-diagnostics-{int(time.time())}.log'
    output = output.expanduser().resolve()
    # Do not overwrite an earlier reproduction, or save captures in the source tree.
    repo = Path(__file__).resolve().parent.parent
    if output == repo or repo in output.parents:
        parser.error('--output must be outside the repository (default: temporary directory).')
    count = 0
    pending = b''
    with output.open('x', encoding='utf-8') as log:
        os.chmod(output, 0o600)
        process = subprocess.Popen([hdc, '-t', target, 'shell', 'hilog', '-T', 'SyncJankProbe', '-v', 'epoch'],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + args.seconds
        print(f'READY: {output}\nReproduce cold-start automatic sync, then manual sync. Capture ends in {args.seconds}s.', flush=True)
        try:
            while time.monotonic() < deadline and count < 20000:
                if not selector.select(timeout=min(1, max(0, deadline - time.monotonic()))):
                    if process.poll() is not None:
                        break
                    continue
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    break
                pending += chunk
                lines = pending.split(b'\n')
                pending = lines.pop()[-65536:]
                for raw in lines:
                    line = raw.decode('utf-8', errors='replace')
                    if PREFIX not in line:
                        continue
                    try:
                        record = json.loads(line.split(PREFIX, 1)[1].strip())
                    except (ValueError, IndexError):
                        continue
                    # Retain the app timestamp/run identifier; drop device/HiLog prefix metadata.
                    log.write(PREFIX + ' ' + json.dumps(record, ensure_ascii=False) + '\n')
                    count += 1
                log.flush()
        except KeyboardInterrupt:
            pass
        finally:
            selector.close()
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    print(f'Saved {count} diagnostic events: {output}', flush=True)
    if not count:
        print('No diagnostic events: verify the diagnostic build is installed and open the app once.')
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
