"""바이너리 포맷(명세 6.4)과 조각(6.5) 시험."""

import base64
import struct
import unittest

from trailgrade.course import build_course, js_round
from trailgrade.encode import (EncodeError, course_id, crc32_hex, decode_binary, encode_binary,
                               make_chunks)

from . import synth


class EncodeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.short = build_course(synth.out_and_back())
        cls.long = build_course(synth.long_course())

    def test_header_and_size(self):
        c = self.long
        b = encode_binary(c)
        self.assertEqual(len(b), 20 + 2 * c.n + 4 * (c.n - 1) + 10 * len(c.segs))
        magic, ver, interval, n, nseg, lat0, lon0, reserved = struct.unpack(">2sBBHHiiI", b[:20])
        self.assertEqual((magic, ver, interval, n, nseg, reserved), (b"TG", 1, 20, c.n, len(c.segs), 0))
        self.assertEqual((lat0, lon0), (js_round(c.lat[0] * 1e5), js_round(c.lon[0] * 1e5)))

    def test_100km_fits_spec_budget(self):
        """명세 6.4·7.3: 100 km 코스 약 29 KB, 6,000자 조각 7개 안팎."""
        b = encode_binary(self.long)
        self.assertLess(len(b), 32 * 1024)
        self.assertLessEqual(len(make_chunks(b, 6000)), 7)

    def test_roundtrip(self):
        for c in (self.short, self.long):
            d = decode_binary(encode_binary(c))
            self.assertEqual(d.n, c.n)
            self.assertEqual(d.ele, [js_round(v * 10) for v in c.ele])
            # 좌표는 각 점을 1e-5°로 반올림한 절대값과 같아야 합니다 (누적 오차 없음)
            self.assertEqual(d.lat, [js_round(v * 1e5) for v in c.lat])
            self.assertEqual(d.lon, [js_round(v * 1e5) for v in c.lon])
            self.assertEqual([(t, s, e) for t, s, e, *_ in d.segs], [(s.type, s.s, s.e) for s in c.segs])
            for (_, _, _, de, avg, mx), s in zip(d.segs, c.segs):
                self.assertEqual(de, js_round(s.d_ele * 10))
                self.assertAlmostEqual(avg / 2, s.avg, delta=0.25)
                self.assertAlmostEqual(mx / 2, s.max, delta=0.25)

    def test_chunks_decode_independently(self):
        b = encode_binary(self.long)
        chunks = make_chunks(b, 6000)
        self.assertTrue(all(len(ch) == 6000 for ch in chunks[:-1]))
        joined = b"".join(base64.b64decode(ch) for ch in chunks)  # 조각마다 따로 풀어 이어 붙임
        self.assertEqual(joined, b)
        for i, ch in enumerate(chunks[:-1]):
            self.assertEqual(len(base64.b64decode(ch)), 4500, i)

    def test_chunk_size_must_be_multiple_of_4(self):
        with self.assertRaises(EncodeError):
            make_chunks(b"abc", 6001)

    def test_id_and_crc(self):
        b1 = encode_binary(self.short)
        b2 = encode_binary(build_course(synth.out_and_back(), min_climb=10))
        self.assertEqual(course_id(b1), course_id(encode_binary(self.short)))
        self.assertEqual(len(course_id(b1)), 10)
        self.assertNotEqual(course_id(b1), course_id(b2))
        self.assertRegex(crc32_hex(b1), r"^[0-9a-f]{8}$")

    def test_negative_elevation_is_clamped_with_warning(self):
        pts = [(la, lo, e - 1000) for la, lo, e in synth.out_and_back()]
        warnings = []
        d = decode_binary(encode_binary(build_course(pts), warnings))
        self.assertEqual(min(d.ele), 0)
        self.assertTrue(any("고도" in w for w in warnings))


if __name__ == "__main__":
    unittest.main()
