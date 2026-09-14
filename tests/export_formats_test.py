"""Validate native exports with independent image and PDF readers; no USB."""
import json
import os
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageChops
from pypdf import PdfReader

root = Path(__file__).resolve().parents[1]
exporter = Path(os.environ.get('BJC85_TEST_EXPORTER',root / 'build/is12-scan-export'))
output = root / 'tmp/export-verification'
output.mkdir(parents=True, exist_ok=True)
for source_name, dpi in [
    ('scans/2026-09-13/chart-paper-reference-90dpi.png', 90),
    ('scans/2026-09-13/chart-paper-reference-180dpi.png', 180),
    ('.state/is12-scan-010/scan-bilevel.png', 90),
    ('.state/is12-scan-012/scan-upright.png', 360),
]:
    source = root / source_name
    original = Image.open(source)
    for extension in ('png', 'tiff', 'pdf'):
        destination = output / f'{source.stem}-{dpi}.{extension}'
        subprocess.run([exporter, source, destination], check=True)
        if extension == 'pdf':
            reader = PdfReader(destination)
            assert len(reader.pages) == 1
            page = reader.pages[0]
            assert abs(float(page.mediabox.width)-original.width*72/dpi) < .01
            assert abs(float(page.mediabox.height)-original.height*72/dpi) < .01
            images = list(page.images)
            assert len(images) == 1
            exported = images[0].image
        else:
            exported = Image.open(destination)
            assert max(abs(float(value)-dpi) for value in exported.info['dpi']) < .05
            assert exported.mode == original.mode, (extension, original.mode, exported.mode)
        assert exported.size == original.size
        assert ImageChops.difference(original.convert('RGB'), exported.convert('RGB')).getbbox() is None
        print(json.dumps(dict(source=source_name, format=extension, pixels_identical=True,
                              size=exported.size, dpi=dpi, mode=exported.mode)))
