"""Python 변환기와 프로토타입(JavaScript)이 같은 결과를 내는지 비교합니다 (명세 6장 요구사항).

프로토타입 HTML에서 함수를 꺼내 Node로 실행합니다(tests/proto_ref.mjs). Node가 없으면 건너뜁니다.
"""

import json
import shutil
import subprocess
import unittest
from pathlib import Path

from trailgrade.course import build_course
from trailgrade.gpx import parse_gpx, write_gpx

from . import synth

REF = Path(__file__).with_name("proto_ref.mjs")
NODE = shutil.which("node")


def run_ref(payload: dict) -> dict:
    res = subprocess.run([NODE, str(REF)], input=json.dumps(payload), capture_output=True, text=True, check=True)
    return json.loads(res.stdout)


@unittest.skipUnless(NODE, "node가 없어 프로토타입 비교를 건너뜁니다")
class ParityTest(unittest.TestCase):
    maxDiff = None

    def assert_same(self, pts, ref, interval, smooth, min_climb):
        c = build_course(pts, interval, smooth, min_climb)
        self.assertEqual(c.n, ref["N"])
        self.assertEqual(c.ele, ref["ele"])
        self.assertEqual([(s.type, s.s, s.e, s.no) for s in c.segs],
                         [(s["type"], s["s"], s["e"], s["no"]) for s in ref["segs"]])
        for s, r in zip(c.segs, ref["segs"]):
            for mine, theirs in [(s.len, "len"), (s.d_ele, "dEle"), (s.gain, "gain"), (s.loss, "loss"),
                                 (s.avg, "avg"), (s.max, "max"), (s.hi, "hi"), (s.lo, "lo")]:
                self.assertAlmostEqual(mine, r[theirs], places=9, msg=theirs)
        return c

    def test_sample_course(self):
        """프로토타입 샘플 코스: 명세 6.2의 13개 구간(오르막 4, 내리막 3, 평지 6)."""
        base = run_ref({"sample": True})
        pts = [tuple(p) for p in base["pts"]]
        c = self.assert_same(pts, base, 20, 100, 20)
        kinds = [s.type for s in c.segs]
        self.assertEqual((len(kinds), kinds.count("UP"), kinds.count("DOWN"), kinds.count("FLAT")), (13, 4, 3, 6))
        for interval, smooth, min_climb in [(10, 100, 20), (20, 60, 10), (20, 200, 40), (30, 100, 20)]:
            with self.subTest(interval=interval, smooth=smooth, min_climb=min_climb):
                ref = run_ref({"sample": True, "interval": interval, "smooth": smooth, "minClimb": min_climb})
                self.assert_same(pts, ref, interval, smooth, min_climb)

    def check_gpx_course(self, name, pts, params):
        trk = parse_gpx(write_gpx(name, pts))
        for interval, smooth, min_climb in params:
            with self.subTest(course=name, interval=interval, smooth=smooth, min_climb=min_climb):
                ref = run_ref({"pts": trk.pts, "interval": interval, "smooth": smooth, "minClimb": min_climb})
                self.assert_same(trk.pts, ref, interval, smooth, min_climb)

    def test_out_and_back(self):
        self.check_gpx_course("왕복", synth.out_and_back(), [(20, 100, 20), (10, 100, 10), (20, 200, 40)])

    def test_long_course(self):
        self.check_gpx_course("100 km", synth.long_course(), [(20, 100, 20)])


if __name__ == "__main__":
    unittest.main()
