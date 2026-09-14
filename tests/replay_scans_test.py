"""Replay real completed captures under ASAN and compare independent pixels."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
from PIL import Image

root = Path(__file__).resolve().parents[1]
decode = runpy.run_path(str(root / 'scripts/decode-is12-scan.py'))['decode']
cases = [
    ('.state/is12-scan-001', 90, 'color'),
    ('.state/is12-scan-002', 90, 'color'),
    ('.state/is12-scan-004', 90, 'color'),
    ('.state/is12-scan-006', 180, 'color'),
    ('.state/scanner-app/scan-00000000-0000-4000-8000-00000000000F', 360, 'color'),
    ('.state/is12-scan-008', 90, 'gray'),
    ('.state/is12-scan-010', 90, 'lineart'),
]
if (root / '.state/is12-scan-012/scan-raw.png').exists():
    cases.append(('.state/is12-scan-012',360,'bw'))
for job in sorted((root / '.state/escl-jobs').iterdir()):
    marker = job / 'acquisition-started.json'
    capture = job / 'capture'
    if marker.exists() and (capture / 'scan-raw.png').exists():
        settings = json.loads(marker.read_text())
        cases.append((str(capture.relative_to(root)), settings['dpi'], settings['mode']))
with tempfile.TemporaryDirectory(prefix='is12-replay-') as output:
    for index, (path, dpi, mode) in enumerate(cases):
        records = root / path / 'records.bin'
        destination = Path(output) / f'{index}.png'
        subprocess.run([Path(os.environ.get('BJC85_TEST_HELPER',root / 'build-asan/bjc85-is12')), 'image', records, destination,
                        '--dpi', str(dpi), '--mode', mode], check=True, capture_output=True)
        independent, info = decode(records.read_bytes(), dpi=dpi, mode='gray' if mode == 'bw' else mode)
        if mode == 'bw':
            independent=bytes(255 if value >= 128 else 0 for value in independent)
        native = Image.open(destination)
        if path == '.state/is12-scan-002':
            original = Image.open(root / 'scans/2026-09-13/page-2-uncalibrated.png').transpose(Image.Transpose.ROTATE_180)
        else:
            original = Image.open(root / path / 'scan-raw.png')
        assert native.mode == {'color':'RGB', 'gray':'L', 'lineart':'1', 'bw':'1'}[mode]
        assert native.convert('RGB').tobytes() == independent == original.convert('RGB').tobytes()
        print(json.dumps({'capture':path, 'dpi':dpi, 'mode':mode,
                          'native_png_mode':native.mode, 'size':native.size, 'pixels_identical':True,
                          'bands':info['bands'], 'band_rows':info['band_rows'], 'rows':info['channel_rows']}))
