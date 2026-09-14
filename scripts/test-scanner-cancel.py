#!/usr/bin/env python3
"""Hardware acceptance: interrupt one blank-sheet scan at its first band.

This is deliberately excluded from CTest. Run only with IS-12 installed,
printing stopped, and a disposable blank sheet loaded. Partial data is retained.
"""
import argparse
import json
from pathlib import Path
import signal
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--hardware-blank-sheet', action='store_true', required=True)
parser.add_argument('driver', type=Path)
parser.add_argument('reference', type=Path)
parser.add_argument('capture', type=Path)
parser.add_argument('log', type=Path)
args = parser.parse_args()
cancelled = False
records = []
with args.log.open('x') as output, args.log.with_suffix('.stderr.txt').open('x') as errors:
    process = subprocess.Popen([str(args.driver), 'scan', '--scanner-installed', '--dpi', '90',
                                '--mode', 'gray', '--calibration', str(args.reference), str(args.capture)],
                               stdout=subprocess.PIPE, stderr=errors, text=True)
    for line in process.stdout:
        output.write(line); output.flush()
        record = json.loads(line); records.append(record)
        if (not cancelled and record.get('event') == 'record' and record.get('stage') == 'acquire'
                and record.get('family') == ord('S') and record.get('token') == ord('P')):
            process.send_signal(signal.SIGINT)
            cancelled = True
            print('Sent SIGINT after the first complete grayscale band.', flush=True)
    code = process.wait()
stop = [r for r in records if r.get('event') == 'write' and r.get('stage') == 'stop-acquisition']
result = records[-1]
assert cancelled and code == 1, (cancelled, code)
assert len(stop) == 1 and stop[0]['accepted'] == stop[0]['requested'] == 6 and stop[0]['usb_result'] == 0
assert result.get('event') == 'scan_result' and not result['complete_stream']
assert not (args.capture / 'scan-raw.png').exists()
print(json.dumps(dict(interrupt_sent=True, stop_command_accepted=True, automatic_replay=False,
                     partial_image_not_published=True, capture=str(args.capture), exit_code=code)))
