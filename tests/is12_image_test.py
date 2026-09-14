"""Image-record contract checks, including RGB-plane rewinds and truncated input."""
import runpy
from pathlib import Path
import struct
import unittest

decode = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/decode-is12-scan.py'))['decode']


def record(family, body):
    return b'\x1b!' + family + struct.pack('<H', len(body)) + body


def capture():
    data = record(b's', b'C' + struct.pack('>4H', 0, 43, 8, 8))
    for channel, values in [(b'R', (1, 2, 3, 4)), (b'G', (5, 6, 7, 8)), (b'B', (9, 10, 11, 12))]:
        for y in range(2):
            data += record(b'S', channel + bytes(values[y*2:y*2+2]))
            data += record(b'e', b'\0\1')
        if channel != b'B':
            data += record(b'e', b'\xff\xfe')
    return data + record(b'S', b'P') + record(b'S', b'E')


class ImageTests(unittest.TestCase):
    def test_bilevel_msb_order_white_polarity_and_padding_bits(self):
        data = record(b's', b'C' + struct.pack('>4H', 0, 43, 40, 4))
        data += record(b'S', b'K' + bytes([0b10100101, 0b10111111]))
        data += record(b'e', b'\0\1') + record(b'S', b'E')
        rgb, info = decode(data, mode='lineart')
        expected = [255,0,255,0,0,255,0,255,255,0]
        self.assertEqual(rgb, bytes(v for pixel in expected for v in [pixel]*3))
        self.assertEqual(info['channel_rows'], {'K': 1})

    def test_grayscale_is_one_channel_with_unchanged_values(self):
        data = record(b's', b'C' + struct.pack('>4H', 0, 43, 8, 4))
        data += record(b'S', b'K' + bytes([10, 200]))
        data += record(b'e', b'\0\1') + record(b'S', b'E')
        rgb, info = decode(data, mode='gray')
        self.assertEqual(rgb, bytes([10,10,10,200,200,200]))
        self.assertEqual(info['channel_rows'], {'K': 1})
        with self.assertRaises(ValueError):
            decode(data, mode='color')

    def test_reconstruct_planes_and_rewinds(self):
        rgb, info = decode(capture())
        self.assertEqual(rgb, bytes([1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12]))
        self.assertTrue(info['complete'])
        self.assertEqual(info['padding_bytes'], 0)

    def test_truncation_is_not_a_complete_page(self):
        data = capture()
        for removed in (1, 3, 6, 13):
            with self.assertRaises(ValueError):
                decode(data[:-removed])
        _, info = decode(data[:-1], partial=True)
        self.assertFalse(info['complete'])

    def test_unrecognized_encoding_and_trailing_corruption(self):
        with self.assertRaises(ValueError):
            decode(capture().replace(b'\x1b!S\x03\0R', b'\x1b!S\x03\0r', 1))
        with self.assertRaises(ValueError):
            decode(capture() + b'garbage')

    def test_no_oversized_line_advance(self):
        with self.assertRaises(ValueError):
            decode(capture().replace(b'\x1b!e\x02\0\0\1', b'\x1b!e\x02\0\x7f\xff', 1))


if __name__ == '__main__':
    unittest.main()
