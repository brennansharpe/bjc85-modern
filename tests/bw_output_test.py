"""Verify one-bit output from complete grayscale data, including threshold edges."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from PIL import Image

root = Path(__file__).resolve().parents[1]
helper = Path(os.environ.get('BJC85_TEST_HELPER',root / 'build-asan/bjc85-is12'))
def record(family, body):
    return b'\x1b!' + family + struct.pack('<H', len(body)) + body

with tempfile.TemporaryDirectory(prefix='is12-bw-output-') as temporary:
    directory = Path(temporary)
    row = [0,1,126,127,128,129,254,255,100]
    values = row + list(reversed(row))
    records = record(b's', b'C' + struct.pack('>4H',0,43,36,8))
    for pixels in (row, list(reversed(row))):
        records += record(b'S', b'K'+bytes(pixels)) + record(b'e', b'\0\1')
    records += record(b'S', b'P') + record(b'S', b'E')
    source = directory / 'threshold-ramp.bin'
    source.write_bytes(records)
    for rotate in (False, True):
        destination = directory / f'ramp-{rotate}.png'
        args=[helper,'image',source,destination,'--dpi','90','--mode','bw']
        if rotate: args += ['--rotate180']
        result=subprocess.run(args,check=True,capture_output=True,text=True)
        info=json.loads(result.stdout)
        assert info['host_threshold'] == 128
        output=Image.open(destination)
        expected=[255 if value >= 128 else 0 for value in values]
        if rotate: expected.reverse()
        assert output.mode == '1' and list(output.convert('L').tobytes()) == expected
    source = Path(os.environ.get('BJC85_BW_CAPTURE', root / '.state/replay-fixtures/gray-360'))
    destination = directory / 'full-page-bw.png'
    subprocess.run([helper,'image',source/'records.bin',destination,'--dpi','360','--mode','bw'],check=True,capture_output=True)
    output=Image.open(destination)
    expected=Image.open(source/'scan-raw.png').point(lambda v: 255 if v >= 128 else 0, mode='1')
    assert output.mode == '1' and output.size == (2880,3888)
    assert output.tobytes() == expected.tobytes()
    incomplete = directory / 'must-not-exist.png'
    failed=subprocess.run([helper,'image',root/'.state/is12-scan-011/records.bin',incomplete,'--dpi','360','--mode','lineart'],capture_output=True)
    assert failed.returncode != 0 and not incomplete.exists()
    print(json.dumps({'case':'native one-bit conversion from complete gray data','threshold':128,
                      'boundary_and_rotation_pixels_correct':True,'full_360dpi_page_pixels_correct':True,
                      'short_hardware_one_bit_capture_rejected':True}))
