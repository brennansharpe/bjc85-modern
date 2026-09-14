"""Nonblank, asymmetric RGB target. No hardware, third-party artwork or scans."""
import struct, zlib, sys
from pathlib import Path
w, h = (int(v) for v in sys.argv[2:4]) if len(sys.argv) > 2 else (2880, 3888)
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        r, g, b = x*255//w, y*255//h, (x+y)*255//(w+h)
        if x < w//8 and y < h//8: r,g,b=220,30,40
        elif x > w*7//8 and y < h//5: r,g,b=20,170,70
        elif x < w//5 and y > h*7//8: r,g,b=30,70,220
        elif x > w*4//5 and y > h*4//5: r,g,b=240,190,20
        elif x%71 < 2 or y%113 < 2: r,g,b=10,10,10
        rows.extend((r,g,b))
def chunk(t,b): return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
p=Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True)
p.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'pHYs',struct.pack('>IIB',14173,14173,1))+chunk(b'IDAT',zlib.compress(rows,6))+chunk(b'IEND',b''))
print(p, w, h)
