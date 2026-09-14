#!/usr/bin/env python3
"""Decode an uncompressed native IS-12 RGB acquisition; never open USB.

The recorded inner stream has its outer USB frames removed by bjc85-is12.
ESC ! e carries a signed BE line advance, not a device error. Negative advances
rewind the logical row position between RGB planes. S/P ends a band; S/E ends
the page. Pixel bytes are preserved without host tonal adjustment; the records
alone do not say whether the device received a correction table before scanning.
"""
import argparse
import json
from pathlib import Path
import struct
import zlib


def decode(data, dpi=90, partial=False, mode='color'):
    if dpi not in (90, 180, 360):
        raise ValueError("Only equal-axis 90/180/360 dpi scans are supported")
    if len(data) > 64 * 1024 * 1024:
        raise ValueError("Capture exceeds the acquisition limit")
    divisor = 360 // dpi
    band_rows = None
    band_end = 0
    if mode not in ('color', 'gray', 'lineart'):
        raise ValueError('Supported modes: color, gray, lineart')
    tokens = b'RGB' if mode == 'color' else b'K'
    position = 0
    width = height = None
    row_bytes = None
    planes = {c: bytearray() for c in tokens}
    pending = {c: bytearray() for c in tokens}
    channel = None
    ended = False
    bands = 0
    padding = 0
    records = 0
    while position + 5 <= len(data):
        if data[position:position+2] not in (b"\x1b!", b"\x1b*"):
            raise ValueError(f"Invalid record prefix at {position}")
        family = data[position+2]
        size = int.from_bytes(data[position+3:position+5], "little")
        if size < 1:
            raise ValueError("Empty inner body")
        end = position + 5 + size
        if end > len(data):
            break
        body = data[position+5:end]
        records += 1
        position = end
        if family == ord('s'):
            if body[0] == ord('C'):
                if len(body) != 9:
                    raise ValueError("Invalid accepted area")
                x, y, physical_width, physical_height = struct.unpack('>4H', body[1:])
                if physical_width % divisor or physical_height % divisor:
                    raise ValueError("Area is not aligned to the configured resolution")
                width, height = physical_width // divisor, physical_height // divisor
                row_bytes = (width+7)//8 if mode == 'lineart' else width
                if not (1 <= width <= 3000 and 1 <= height <= 5000):
                    raise ValueError("Area exceeds decoder bounds")
            continue
        if family == ord('S'):
            token, payload = body[0], body[1:]
            if token in tokens:
                if width is None or ended or band_end >= height:
                    raise ValueError("Image data outside a configured page")
                channel = token
                pending[channel].extend(payload)
                # IS-12 delivers a final whole physical band; the original caller
                # takes only its remaining requested rows (biReadImagePreCalc).
                if len(pending[channel]) + len(planes[channel]) > row_bytes * (height + (band_rows or 512) - 1):
                    raise ValueError("Channel exceeds requested image size")
            elif token == ord('P'):
                if payload or any(pending.values()):
                    raise ValueError("Band ends with uncommitted pixels")
                counts = [len(v) // row_bytes for v in planes.values()]
                if len(set(counts)) != 1 or any(len(v) % row_bytes for v in planes.values()):
                    raise ValueError('Incomplete colour planes at band end')
                count = counts[0] - band_end
                if not 1 <= count <= (band_rows or 512):
                    raise ValueError('Invalid band height')
                band_rows = band_rows or count
                band_end = counts[0]
                bands += 1
            elif token == ord('E'):
                if payload or any(pending.values()):
                    raise ValueError("Page ends with uncommitted pixels")
                ended = True
            else:
                raise ValueError(f"Unsupported image token {token:#x}")
        elif family == ord('e'):
            if len(body) != 2:
                raise ValueError("Invalid line-advance length")
            advance = int.from_bytes(body, 'big', signed=True)
            if advance > 0:
                if channel is None or width is None:
                    raise ValueError("Line advance before pixel channel")
                expected = row_bytes * advance
                if len(pending[channel]) > expected:
                    raise ValueError("Too many pixels for the line advance")
                missing = expected - len(pending[channel])
                if len(planes[channel]) + expected > row_bytes * (height + (band_rows or 512) - 1):
                    raise ValueError("Line advance exceeds page size")
                # Canon's FUN_1000d45f pads omitted trailing pixels/rows with zero.
                planes[channel].extend(pending[channel])
                planes[channel].extend(bytes(missing))
                padding += missing
                pending[channel].clear()
            elif channel is not None and pending[channel]:
                raise ValueError("Nonpositive advance with uncommitted pixels")
        else:
            raise ValueError(f"Unsupported reply family {family:#x}")
    if width is None:
        raise ValueError("Capture lacks an accepted scan area")
    lengths = {chr(c): len(planes[c]) // row_bytes for c in planes}
    complete = (ended and position == len(data) and not any(pending.values()) and
                len(set(lengths.values())) == 1 and
                all(len(v) % row_bytes == 0 and height <= len(v)//row_bytes < height+(band_rows or 512) for v in planes.values()))
    if not partial and not complete:
        raise ValueError(f"Incomplete page: end={ended}, rows={lengths}, expected={height}, trailing={len(data)-position}")
    rows = height if complete else min(lengths.values())
    if rows < 1:
        raise ValueError("No complete RGB rows")
    rgb = bytearray(width * rows * 3)
    if mode == 'lineart':
        for y in range(rows):
            for x in range(width):
                value = 255 if planes[ord('K')][y*row_bytes+x//8] & (128 >> (x%8)) else 0
                offset = (y*width+x)*3
                rgb[offset:offset+3] = bytes([value])*3
    else:
        for i, c in enumerate(b'RGB' if mode == 'color' else b'KKK'):
            rgb[i::3] = planes[c][:width*rows]
    metadata = dict(complete=complete, device_correction='not encoded in image records', tonal_adjustment=False,
                    mode=mode, dpi=dpi, width=width, height=rows, requested_height=height,
                    channel_rows=lengths, bands=bands, band_rows=band_rows, padding_bytes=padding,
                    cropped_final_band_rows=max(0, min(lengths.values())-height),
                    records=records, source_bytes=len(data), parsed_bytes=position)
    return bytes(rgb), metadata


def write_png(destination, rgb, width, height, dpi):
    def chunk(name, payload):
        return struct.pack('>I', len(payload)) + name + payload + struct.pack('>I', zlib.crc32(name + payload))
    scanlines = b''.join(b'\0' + rgb[y*width*3:(y+1)*width*3] for y in range(height))
    per_metre = round(dpi / 0.0254)
    data = b'\x89PNG\r\n\x1a\n'
    data += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    data += chunk(b'pHYs', struct.pack('>IIB', per_metre, per_metre, 1))
    data += chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b'')
    with destination.open('xb') as output:
        output.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('records', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--dpi', type=int, default=90)
    parser.add_argument('--mode', choices=('color', 'gray', 'lineart'), default='color')
    parser.add_argument('--partial', action='store_true')
    parser.add_argument('--rotate180', action='store_true', help='Orient a sheet fed bottom first')
    args = parser.parse_args()
    rgb, metadata = decode(args.records.read_bytes(), args.dpi, args.partial, args.mode)
    if args.rotate180:
        rotated = bytearray(len(rgb))
        for c in range(3):
            rotated[c::3] = rgb[c::3][::-1]
        rgb = bytes(rotated)
    metadata['rotation_degrees'] = 180 if args.rotate180 else 0
    write_png(args.output, rgb, metadata['width'], metadata['height'], args.dpi)
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata))


if __name__ == '__main__':
    main()
