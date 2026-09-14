#!/usr/bin/env python3
"""Explicit hardware acceptance: one new blank sheet and native USB contention."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if sys.argv[1:] != ['--paper-loaded']:
    raise SystemExit('Usage: test-bw-scan.py --paper-loaded (IS-12 installed; one blank sheet)')
helper = root / 'build/BJC-85 Scanner.app/Contents/Helpers/bjc85-is12'
directory = root / '.state/is12-scan-012'
if directory.exists():
    raise SystemExit('Capture already exists; never replay this acceptance job.')
checked = False
with (root/'docs/protocol/is12-scan-012.jsonl').open('x') as log, (root/'docs/protocol/is12-scan-012.stderr.txt').open('x') as errors:
    process = subprocess.Popen([helper,'scan','--scanner-installed','--dpi','360','--mode','bw',
                                '--calibration',root/'.state/is12-calibration-002/reference.bin',directory],
                               stdout=subprocess.PIPE,stderr=errors,text=True)
    for line in process.stdout:
        log.write(line); log.flush()
        row=json.loads(line)
        if not checked and row.get('event') == 'scan_start':
            probe=subprocess.run([root/'build/bjc85-usb','probe'],capture_output=True,text=True,timeout=10)
            checked=probe.returncode != 0 and 'Another native BJC-85 operation owns USB' in probe.stderr
            result={'case':'native USB probe during actual acquisition','blocked_before_usb':checked,
                    'exit_code':probe.returncode,'message':probe.stderr.strip()}
            (root/'docs/protocol/is12-usb-contention-hardware.jsonl').write_text(json.dumps(result)+'\n')
    code=process.wait()
if code != 0 or not checked:
    raise SystemExit(f'Hardware acceptance failed: scan exit={code}, exclusive ownership={checked}')
print(json.dumps({'case':'full-page 360 dpi black-and-white','capture':str(directory.relative_to(root)),
                  'scan_completed':True,'exclusive_usb_verified':True,'host_threshold':128}))
