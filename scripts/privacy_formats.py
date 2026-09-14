"""Bounded container inspection. No extraction to disk or image-pixel text scan."""
import bz2
import gzip
import io
import lzma
import tarfile
import zipfile
import zlib

MAX_BYTES = 16 * 1024 * 1024
MAX_EXPANDED = 32 * 1024 * 1024
MAX_MEMBERS = 128
MAX_DEPTH = 2


def png(data):
    findings, metadata = set(), []
    expanded = 0
    i, ended, seen_header, seen_pixels = 8, False, False, False
    while i < len(data):
        if i + 12 > len(data):
            findings.add('truncated-png'); break
        length = int.from_bytes(data[i:i+4], 'big')
        kind = data[i+4:i+8]
        end = i + 12 + length
        if end > len(data):
            findings.add('truncated-png'); break
        payload = data[i+8:end-4]
        if zlib.crc32(kind + payload) & 0xffffffff != int.from_bytes(data[end-4:end], 'big'):
            findings.add('invalid-png-crc')
        if not seen_header:
            if kind != b'IHDR' or length != 13:
                findings.add('invalid-png-header')
            seen_header = True
        if kind == b'IDAT':
            seen_pixels = True
        elif kind == b'IEND':
            ended = True
            if length or not seen_pixels:
                findings.add('invalid-png-ending')
            if end != len(data):
                findings.add('image-trailing-data'); metadata.append(data[end:])
            break
        elif kind in (b'tEXt', b'zTXt', b'iTXt', b'eXIf', b'iCCP'):
            findings.add('image-metadata'); metadata.append(payload)
            try:
                if kind in (b'zTXt', b'iCCP'):
                    _, compressed = payload.split(b'\0', 1)
                    if not compressed or compressed[0] != 0: raise ValueError()
                    decoded = expand_zlib(compressed[1:], MAX_EXPANDED - expanded)
                    expanded += len(decoded)
                    metadata.append(decoded)
                elif kind == b'iTXt':
                    _, rest = payload.split(b'\0', 1)
                    flag, method = rest[:2]
                    _, _, text = rest[2:].split(b'\0', 2)
                    if flag not in (0, 1) or method != 0: raise ValueError()
                    decoded = expand_zlib(text, MAX_EXPANDED - expanded) if flag else text
                    expanded += len(decoded)
                    if expanded > MAX_EXPANDED: raise LimitError()
                    metadata.append(decoded)
            except (ValueError, zlib.error, LimitError):
                findings.add('metadata-inspection-failed')
        elif kind not in (b'IHDR', b'PLTE', b'tRNS', b'pHYs', b'gAMA', b'cHRM', b'sRGB', b'sBIT', b'bKGD'):
            findings.add('unsupported-png-chunk'); metadata.append(payload)
        i = end
    if not ended: findings.add('truncated-png')
    return findings, metadata


def jpeg(data):
    findings, metadata = set(), []
    i, in_scan, ended, saw_scan = 2, False, False, False
    while i < len(data):
        if in_scan:
            marker_start = data.find(b'\xff', i)
            if marker_start < 0: break
            i = marker_start
        elif data[i] != 255:
            findings.add('invalid-jpeg'); break
        while i < len(data) and data[i] == 255: i += 1
        if i == len(data): break
        marker = data[i]; i += 1
        if in_scan and (marker == 0 or 0xd0 <= marker <= 0xd7): continue
        in_scan = False
        if marker == 0xd9:
            ended = True
            if i != len(data):
                findings.add('image-trailing-data'); metadata.append(data[i:])
            break
        if marker in (0xd8, 0x00) or i + 2 > len(data):
            findings.add('invalid-jpeg'); break
        if marker == 0x01: continue
        length = int.from_bytes(data[i:i+2], 'big')
        if length < 2 or i + length > len(data):
            findings.add('truncated-jpeg'); break
        payload = data[i+2:i+length]
        if 0xe1 <= marker <= 0xef or marker == 0xfe:
            findings.add('image-metadata'); metadata.append(payload)
        elif marker == 0xe0:
            # Only a plain JFIF header with no embedded thumbnail is routine.
            if len(payload) != 14 or not payload.startswith(b'JFIF\0') or payload[-2:] != b'\0\0':
                findings.add('image-metadata'); metadata.append(payload)
        if marker == 0xda:
            saw_scan = True; in_scan = True
        i += length
    if not ended or not saw_scan: findings.add('truncated-jpeg')
    return findings, metadata


class LimitError(ValueError):
    pass


def expand_zlib(data, limit=MAX_EXPANDED):
    decoder = zlib.decompressobj()
    out = decoder.decompress(data, limit + 1)
    if len(out) > limit or decoder.unconsumed_tail: raise LimitError()
    if not decoder.eof or decoder.unused_data: raise ValueError()
    return out


def archive(data, inspect_child, depth, budget=None):
    """Return None for a non-archive, otherwise findings for all bounded members."""
    kind = ('zip' if data.startswith((b'PK\x03\x04', b'PK\x05\x06', b'PK\x07\x08')) else
            'gzip' if data.startswith(b'\x1f\x8b') else
            'bzip2' if data.startswith(b'BZh') else
            'xz' if data.startswith(b'\xfd7zXZ\0') else
            'tar' if len(data) > 262 and data[257:262] == b'ustar' else None)
    if kind is None: return None
    if depth >= MAX_DEPTH: return {'archive-depth-limit'}
    found, total = set(), 0
    if budget is None: budget = {"bytes": MAX_EXPANDED, "members": MAX_MEMBERS}
    def child(payload, name=''):
        nonlocal total
        total += len(payload)
        budget["bytes"] -= len(payload)
        budget["members"] -= 1
        if budget["bytes"] < 0 or budget["members"] < 0: raise LimitError()
        if total > MAX_EXPANDED: raise LimitError()
        if name: found.update(inspect_child(name.encode(), depth + 1))
        found.update(inspect_child(payload, depth + 1))
    try:
        if kind == 'zip':
            eocd = data.rfind(b'PK\x05\x06')
            if eocd < 0 or eocd + 22 > len(data): raise ValueError()
            if int.from_bytes(data[eocd+10:eocd+12], 'little') > MAX_MEMBERS: raise LimitError()
            comment_end = eocd + 22 + int.from_bytes(data[eocd+20:eocd+22], 'little')
            if comment_end != len(data): found.add('archive-trailing-data')
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                if z.comment: child(z.comment)
                members = z.infolist()
                if len(members) > MAX_MEMBERS: raise LimitError()
                for item in members:
                    if item.comment: child(item.comment)
                    if item.extra:
                        found.add('archive-metadata'); child(item.extra)
                    if item.is_dir(): continue
                    if item.file_size > MAX_BYTES or total + item.file_size > MAX_EXPANDED: raise LimitError()
                    if item.flag_bits & 1:
                        found.add('encrypted-archive-uninspected'); continue
                    with z.open(item) as stream: payload = stream.read(MAX_BYTES + 1)
                    if len(payload) > MAX_BYTES: raise LimitError()
                    child(payload, item.filename)
        elif kind == 'tar':
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as tar:
                count = 0
                for item in tar:
                    count += 1
                    if count > MAX_MEMBERS: raise LimitError()
                    for value in (item.uname, item.gname, *item.pax_headers.values()):
                        if value: child(str(value).encode())
                    if item.isdir(): continue
                    if not item.isfile():
                        found.add('unsupported-archive-member'); continue
                    if item.size > MAX_BYTES or total + item.size > MAX_EXPANDED: raise LimitError()
                    with tar.extractfile(item) as stream: payload = stream.read(MAX_BYTES + 1)
                    if len(payload) > MAX_BYTES: raise LimitError()
                    child(payload, item.name)
        elif kind == 'gzip':
            if len(data) < 10 or data[3] & 0xe0: raise ValueError()
            offset, flags = 10, data[3]
            if flags & 4:
                if offset + 2 > len(data): raise ValueError()
                size = int.from_bytes(data[offset:offset+2], 'little'); offset += 2
                if offset + size > len(data): raise ValueError()
                found.add('archive-metadata'); child(data[offset:offset+size]); offset += size
            for flag in (8, 16):
                if flags & flag:
                    end = data.find(b'\0', offset)
                    if end < 0: raise ValueError()
                    child(data[offset:end]); offset = end + 1
            with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream: payload = stream.read(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES: raise LimitError()
            child(payload)
        else:
            decoder = bz2.BZ2Decompressor() if kind == 'bzip2' else lzma.LZMADecompressor(memlimit=64*1024*1024)
            payload = decoder.decompress(data, max_length=MAX_BYTES + 1)
            if len(payload) > MAX_BYTES or not decoder.eof: raise LimitError()
            if decoder.unused_data: found.add('archive-trailing-data')
            child(payload)
    except LimitError:
        found.add('archive-inspection-limit')
    except (ValueError, OSError, RuntimeError, EOFError, zipfile.BadZipFile, tarfile.TarError, lzma.LZMAError):
        found.add('archive-inspection-failed')
    return found
