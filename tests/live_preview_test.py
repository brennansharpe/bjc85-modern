"""Compare streamed preview bytes with independent decoding of real captures."""
import json
import os
from pathlib import Path
import runpy
import struct
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
executable = root / (sys.argv[1] if len(sys.argv) > 1 else 'build-asan/is12-preview-replay')
decode = runpy.run_path(str(root / 'scripts/decode-is12-scan.py'))['decode']
cases = [
    ('.state/is12-scan-004', 90, 'color'),
    ('.state/is12-scan-006', 180, 'color'),
    (os.environ.get('BJC85_COLOR_360_CAPTURE', '.state/replay-fixtures/color-360'), 360, 'color'),
    ('.state/is12-scan-008', 90, 'gray'),
    ('.state/is12-scan-010', 90, 'lineart'),
    ('.state/is12-scan-012', 360, 'bw'),
]

def replay(records, output, dpi, mode):
    result = subprocess.run([executable, records, output, str(dpi), mode], capture_output=True, text=True)
    events = [json.loads(line) for line in result.stdout.splitlines()]
    return result.returncode, events, (output / 'live-preview.rgb').read_bytes()

with tempfile.TemporaryDirectory(prefix='is12-live-preview-') as temporary:
    temporary = Path(temporary)
    for index, (path, dpi, mode) in enumerate(cases):
        output = temporary / str(index); output.mkdir()
        source = root / path / 'records.bin'
        code, events, pixels = replay(source, output, dpi, mode)
        assert code == 0, (code, path)
        full, info = decode(source.read_bytes(), dpi=dpi, mode='gray' if mode == 'bw' else mode)
        if mode == 'bw':
            full = bytes(255 if value >= 128 else 0 for value in full)
        width, height = info['width'], info['height']
        # Preview selects the first pixel of each dpi/90 block, preserving band timing.
        step = dpi // 90
        expected = b''.join(full[(y * width + x)*3:(y * width + x)*3+3]
                            for y in range(0,height,step) for x in range(0,width,step))
        assert pixels == expected
        rows = [e['rows'] for e in events]
        assert len(rows) > 10 and rows == sorted(set(rows))
        assert rows[0] < events[0]['height'] and rows[-1] == events[-1]['height']
        assert all(e['event'] == 'scan_preview' for e in events)
        print(json.dumps({'capture':path, 'mode':mode, 'dpi':dpi, 'frames':len(events),
                          'preview_size':[events[-1]['width'],events[-1]['height']], 'pixels_match':True}))

    # A partial colour plane must not leak uninitialized G/B data into a preview.
    def record(family, token, payload=b''):
        body = payload if family == 'e' else token.encode() + payload
        return b'\x1b!' + family.encode() + struct.pack('<H', len(body)) + body
    area = record('s','C', bytes([0,0,0,0,0,8,0,16]))  # 2 x 4 at 90 dpi
    def plane(token, value):
        return record('S',token,bytes([value])*4) + record('e','',b'\x00\x02')
    for label, data, rows in [
        ('only-red', area + plane('R',10), 0),
        ('all-planes-no-band', area + plane('R',10) + plane('G',20) + plane('B',30), 0),
        ('one-band-cancelled', area + plane('R',10) + plane('G',20) + plane('B',30) + record('S','P'), 2),
        ('short-page', area + plane('R',10) + plane('G',20) + plane('B',30) + record('S','P') + record('S','E'), 2),
    ]:
        output = temporary / label; output.mkdir()
        source = output / 'records.bin'; source.write_bytes(data)
        code, events, pixels = replay(source, output, 90, 'color')
        assert code == 1 and len(pixels) == rows * 2 * 3
        assert len(events) == (1 if rows else 0)
        if rows: assert pixels == bytes([10,20,30]) * 4
    print(json.dumps({'incomplete_colour_planes_hidden':True, 'partial_capture_retained':True,
                      'short_page_not_marked_complete':True}))
