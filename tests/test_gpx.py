"""GPX 파싱 시험 (명세 6.1 1단계)."""

import unittest

from trailgrade.gpx import parse_gpx, write_gpx

NS = 'xmlns="http://www.topografix.com/GPX/1/1"'


class GpxTest(unittest.TestCase):
    def test_trkpt_with_namespace_and_name(self):
        text = (f'<gpx {NS}><metadata><name>북한산 둘레</name></metadata><trk><name>트랙</name><trkseg>'
                '<trkpt lat="37.1" lon="127.1"><ele>100</ele></trkpt>'
                '<trkpt lat="37.2" lon="127.2"><ele>110.5</ele></trkpt></trkseg></trk></gpx>')
        t = parse_gpx(text)
        self.assertEqual(t.name, "북한산 둘레")  # 문서에서 처음 나오는 name
        self.assertEqual(t.pts, [(37.1, 127.1, 100.0), (37.2, 127.2, 110.5)])
        self.assertEqual(t.missing, 0)

    def test_missing_elevation_is_counted(self):
        text = (f'<gpx {NS}><trk><trkseg>'
                '<trkpt lat="1" lon="1"><ele>1</ele></trkpt><trkpt lat="2" lon="2"></trkpt>'
                '<trkpt lat="3" lon="3"><ele>x</ele></trkpt><trkpt lat="4" lon="4"><ele>4</ele></trkpt>'
                '<trkpt lat="bad" lon="5"><ele>5</ele></trkpt></trkseg></trk></gpx>')
        t = parse_gpx(text)
        self.assertEqual([p[0] for p in t.pts], [1, 4])
        self.assertEqual(t.missing, 2)
        self.assertIsNone(t.name)

    def test_route_points_when_no_track(self):
        text = (f'<gpx {NS}><rte><rtept lat="1" lon="1"><ele>1</ele></rtept>'
                '<rtept lat="2" lon="2"><ele>2</ele></rtept></rte></gpx>')
        self.assertEqual(len(parse_gpx(text).pts), 2)

    def test_errors(self):
        with self.assertRaises(ValueError):
            parse_gpx("<gpx")
        with self.assertRaises(ValueError):
            parse_gpx(f'<gpx {NS}><trk><trkseg><trkpt lat="1" lon="1"><ele>1</ele></trkpt></trkseg></trk></gpx>')
        with self.assertRaises(ValueError):
            parse_gpx(f'<gpx {NS}><trk><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk></gpx>')

    def test_write_roundtrip(self):
        pts = [(37.1234567, 127.7654321, 512.3), (37.1234667, 127.7654421, 513.0)]
        t = parse_gpx(write_gpx("A & B <코스>", pts))
        self.assertEqual(t.name, "A & B <코스>")
        self.assertEqual(t.pts, pts)


if __name__ == "__main__":
    unittest.main()
