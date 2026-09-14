#!/usr/bin/env python3
"""Read-only PE32 inspection for the preserved Canon interoperability corpus."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


class PE:
    def __init__(self, filename):
        self.filename = Path(filename)
        self.data = self.filename.read_bytes()
        if self.data[:2] != b'MZ':
            raise ValueError('Not an MZ executable')
        header = self.u32(0x3c)
        if self.data[header:header+4] != b'PE\0\0':
            raise ValueError('Not a PE file')
        count = self.u16(header+6)
        optional_size = self.u16(header+20)
        optional = header+24
        if self.u16(optional) != 0x10b:
            raise ValueError('Only PE32 is supported')
        self.base = self.u32(optional+28)
        self.headers_size = self.u32(optional+60)
        self.export_rva = self.u32(optional+96)
        self.import_rva = self.u32(optional+104)
        self.sections = []
        for i in range(count):
            offset = optional+optional_size+i*40
            name, virtual_size, rva, size, raw = struct.unpack_from('<8sIIII', self.data, offset)
            if raw+size > len(self.data):
                raise ValueError('Section extends beyond file')
            self.sections.append(dict(name=name.rstrip(b'\0').decode('ascii'),
                                      virtual_size=virtual_size, rva=rva, size=size, raw=raw))

    def u16(self, offset):
        return struct.unpack_from('<H', self.data, offset)[0]

    def u32(self, offset):
        return struct.unpack_from('<I', self.data, offset)[0]

    def offset(self, rva, size=1):
        if 0 <= rva and rva+size <= min(self.headers_size, len(self.data)):
            return rva
        for section in self.sections:
            relative = rva-section['rva']
            if 0 <= relative and relative+size <= section['size']:
                return section['raw']+relative
        raise ValueError(f'RVA 0x{rva:x} + {size} is not backed by file bytes')

    def read(self, va, length):
        offset = self.offset(va-self.base, length)
        return self.data[offset:offset+length]

    def string(self, rva):
        offset = self.offset(rva)
        end = self.data.find(b'\0', offset, min(offset+4096, len(self.data)))
        if end < 0:
            raise ValueError('Unterminated string')
        self.offset(rva, end-offset+1)
        return self.data[offset:end].decode('ascii', errors='backslashreplace')

    def imports(self):
        if not self.import_rva:
            return []
        result = []
        for i in range(1024):
            offset = self.offset(self.import_rva+20*i, 20)
            lookup, _, _, name, iat = struct.unpack_from('<IIIII', self.data, offset)
            if not any((lookup, name, iat)):
                return result
            for j in range(65536):
                entry = self.u32(self.offset((lookup or iat)+j*4, 4))
                if not entry:
                    break
                symbol = f'ordinal:{entry & 0xffff}' if entry & 0x80000000 else self.string(entry+2)
                result.append(dict(dll=self.string(name), name=symbol, iat_va=hex(self.base+iat+j*4)))
            else:
                raise ValueError('Unterminated import thunk array')
        raise ValueError('Unterminated import descriptors')

    def exports(self):
        if not self.export_rva:
            return []
        offset = self.offset(self.export_rva, 40)
        ordinal_base, count, names, functions, strings, ordinals = struct.unpack_from('<IIIIII', self.data, offset+16)
        result = []
        for i in range(names):
            ordinal = self.u16(self.offset(ordinals+i*2, 2))
            if ordinal >= count:
                raise ValueError('Export ordinal out of range')
            name = self.string(self.u32(self.offset(strings+i*4, 4)))
            rva = self.u32(self.offset(functions+ordinal*4, 4))
            result.append(dict(name=name, ordinal=ordinal_base+ordinal, va=hex(self.base+rva)))
        return result

    def strings(self, pattern):
        result = []
        for section in self.sections:
            if section['name'] == '.text':
                continue
            data = self.data[section['raw']:section['raw']+section['size']]
            for match in re.finditer(rb'[ -~]{4,}', data):
                value = match.group().decode('ascii')
                if re.search(pattern, value, re.I):
                    result.append(dict(va=hex(self.base+section['rva']+match.start()), text=value))
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file')
    parser.add_argument('action', choices=['imports', 'exports', 'strings', 'dump'])
    parser.add_argument('--pattern', default='.')
    parser.add_argument('--address', type=lambda s: int(s, 0))
    parser.add_argument('--length', type=lambda s: int(s, 0), default=64)
    args = parser.parse_args()
    pe = PE(args.file)
    if args.action == 'dump':
        if args.address is None or not 1 <= args.length <= 65536:
            parser.error('dump needs an address and a length from 1 to 65536')
        data = pe.read(args.address, args.length)
        for i in range(0, len(data), 16):
            chunk = data[i:i+16]
            printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
            print(f'{args.address+i:08x}: {chunk.hex(" "):47} {printable}')
    else:
        value = pe.strings(args.pattern) if args.action == 'strings' else getattr(pe, args.action)()
        print(json.dumps(dict(file=str(pe.filename), sha256=hashlib.sha256(pe.data).hexdigest(), result=value), indent=2))
