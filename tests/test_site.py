"""코스 서버 파일(명세 6.6)과 명령줄 시험."""

import base64
import io
import tempfile
import unittest
import zlib
from contextlib import redirect_stdout
from pathlib import Path

from trailgrade.cli import main
from trailgrade.encode import decode_binary
from trailgrade.gpx import write_gpx
from trailgrade.site import INDEX_MAX, Built, update_index

from . import synth


def read_manifest(p: Path) -> dict:
    return dict(line.split("=", 1) for line in p.read_text(encoding="utf-8").splitlines())


class SiteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.site = self.tmp / "site"
        self.cfg = self.tmp / "none.toml"
        self.cfg.write_text("[build]\n", encoding="utf-8")

    def build(self, *args):
        with redirect_stdout(io.StringIO()) as out:
            code = main(["build", *map(str, args), "--out", str(self.site), "--config", str(self.cfg)])
        return code, out.getvalue()

    def test_build_writes_manifest_chunks_and_current(self):
        gpx = self.tmp / "wangbok.gpx"
        gpx.write_text(write_gpx("왕복\t코스", synth.out_and_back()), encoding="utf-8")
        code, out = self.build(gpx)
        self.assertEqual(code, 0, out)
        cid = (self.site / "current.txt").read_text(encoding="ascii")
        self.assertRegex(cid, r"^[0-9a-f]{10}$")
        m = read_manifest(self.site / "c" / cid / "m.txt")
        self.assertEqual((m["v"], m["id"], m["name"]), ("1", cid, "왕복 코스"))
        chunks = [(self.site / "c" / cid / f"{i}.txt").read_text(encoding="ascii") for i in range(int(m["chunks"]))]
        self.assertFalse(any("\n" in ch for ch in chunks))
        b = b"".join(base64.b64decode(ch) for ch in chunks)
        self.assertEqual(len(b), int(m["bytes"]))
        self.assertEqual(f"{zlib.crc32(b):08x}", m["crc32"])
        d = decode_binary(b)
        self.assertEqual(d.interval, 20)
        self.assertEqual((int(m["emin"]), int(m["emax"])), (min(d.ele), max(d.ele)))
        self.assertEqual(int(m["gain"]), round(sum(max(0, b - a) for a, b in zip(d.ele, d.ele[1:])) / 10))
        self.assertTrue((self.site / "c" / cid / "preview.png").read_bytes().startswith(b"\x89PNG"))
        row = (self.site / "index.txt").read_text(encoding="utf-8").splitlines()[0].split("\t")
        self.assertEqual(row[0], cid)
        self.assertEqual(row[1], "왕복 코스")
        self.assertEqual(int(row[2]), int(m["len"]))
        self.assertEqual(row[4], m["chunks"])

    def test_last_file_becomes_current_and_rebuild_is_stable(self):
        a, b = self.tmp / "a.gpx", self.tmp / "b.gpx"
        a.write_text(write_gpx("A", synth.out_and_back()), encoding="utf-8")
        b.write_text(write_gpx("B", synth.long_course(km=12)), encoding="utf-8")
        self.assertEqual(self.build(a, b)[0], 0)
        ids = [r.split("\t")[0] for r in (self.site / "index.txt").read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(ids), 2)
        self.assertEqual((self.site / "current.txt").read_text(), ids[0])
        self.build(a)  # 같은 코스를 다시 올리면 맨 앞으로 옮겨지고 중복되지 않음
        ids2 = [r.split("\t")[0] for r in (self.site / "index.txt").read_text(encoding="utf-8").splitlines()]
        self.assertEqual(ids2, [ids[1], ids[0]])

    def test_dry_run_and_bad_file(self):
        bad = self.tmp / "bad.gpx"
        bad.write_text("<gpx", encoding="utf-8")
        code, _ = self.build(bad, "--dry-run")
        self.assertEqual(code, 1)
        self.assertFalse(self.site.exists())

    def test_index_is_capped(self):
        for i in range(INDEX_MAX + 5):
            update_index(self.site, Built(f"{i:010x}", f"c{i}", 1, 1, "0", 1, 1))
        rows = (self.site / "index.txt").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(rows), INDEX_MAX)
        self.assertTrue(rows[0].startswith(f"{INDEX_MAX + 4:010x}"))


if __name__ == "__main__":
    unittest.main()
