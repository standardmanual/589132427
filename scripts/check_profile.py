#!/usr/bin/env python3
"""시계가 그린 코스 전체 그래프(5단계)를 Python 계산과 비교합니다.

시뮬레이터 로그(bin/app-sim.log)의 PROFILE 줄(열마다 윤곽 높이와 색 번호)을 읽고, 같은 코스를
코스 서버 폴더(pages/)에서 풀어 app/source/CourseProfile.mc와 같은 규칙으로 다시 계산합니다.
시계는 32비트 실수를 쓰므로 높이는 1 px, 색은 경사가 구간 경계(5·10·15·20·30%)에 아주 가까운 열만 차이를 허용합니다.

  python3 scripts/check_profile.py [--log bin/app-sim.log] [--site pages] [--png bin/profile-watch.png]

--png를 주면 시계가 기록한 열 값 그대로 그래프를 그려 저장합니다(미리보기 PNG와 나란히 보는 용도).
"""

import argparse
import base64
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from trailgrade.encode import decode_binary  # noqa: E402
from trailgrade.preview import DN_COLORS, EDGES, UP_COLORS, Canvas, _rgb, nice_step  # noqa: E402


def read_log(path: Path):
    head = ys = cs = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("PROFILE "):
            head = dict(kv.split("=", 1) for kv in line.split()[1:])
        elif line.startswith("PROFILE_Y"):
            ys = [int(v) for v in line.split()[1:]]
        elif line.startswith("PROFILE_C"):
            cs = [int(v) for v in line.split()[1:]]
    if not (head and ys and cs):
        raise SystemExit("로그에 PROFILE 줄이 없습니다. TrailConfig.DEBUG_LOG를 켜고 시뮬레이터에서 실행하세요.")
    return head, ys, cs


def load_course(site: Path, cid: str):
    m = dict(line.split("=", 1) for line in (site / "c" / cid / "m.txt").read_text(encoding="utf-8").splitlines())
    b = b"".join(base64.b64decode((site / "c" / cid / f"{i}.txt").read_text()) for i in range(int(m["chunks"])))
    return m, decode_binary(b)


def color_index(g: float) -> int:
    a = abs(g)
    i = next((k for k, e in enumerate(EDGES) if a < e), len(EDGES))
    return i if g >= 0 else i + 6


def expected(d, m, s: int):
    """CourseProfile.build와 같은 계산 (배정밀도)."""
    x0 = int(s * 0.07 + 0.5)
    w = int(s * 0.93 + 0.5) - x0
    top, base = int(s * 0.336 + 0.5), int(s * 0.67 + 0.5)
    ele = [v / 10 for v in d.ele]
    n, I = d.n, d.interval
    total = (n - 1) * I
    lo, hi = int(m["emin"]) / 10, int(m["emax"]) / 10
    ys = nice_step(max(10.0, (hi - lo) / 4))
    y_min, y_max = math.floor(lo / ys) * ys, math.ceil(hi / ys) * ys
    if y_max == y_min:
        y_max += ys
    out_y, out_c, grades = [], [], []
    for x in range(w):
        dd = (x + 0.5) / w * total
        q = min(n - 2, int(dd / I))
        f = dd / I - q
        e = ele[q] + (ele[q + 1] - ele[q]) * f
        a, b = max(0, q - 1), min(n - 1, q + 2)
        g = (ele[b] - ele[a]) / ((b - a) * I) * 100
        out_y.append(int(top + (1 - (e - y_min) / (y_max - y_min)) * (base - top) + 0.5))
        out_c.append(color_index(g))
        grades.append(g)
    return {"x0": x0, "w": w, "top": top, "base": base, "ymin": y_min, "ymax": y_max}, out_y, out_c, grades


def render(ys, cs, top, base, path: Path):
    """시계 화면의 그래프 영역(top–base)만 잘라 그립니다."""
    w = len(ys)
    pad = 10
    oy = top - pad
    cv = Canvas(w + 2 * pad, base - top + 2 * pad)
    colors = [_rgb(h) for h in UP_COLORS + DN_COLORS]
    for x, (y, c) in enumerate(zip(ys, cs)):
        cv.rect(pad + x, y - oy, pad + x + 1, base - oy, colors[c])
    cv.polyline([(pad + x, y - oy) for x, y in enumerate(ys)], (232, 232, 232))
    path.write_bytes(cv.png())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log", default="bin/app-sim.log", type=Path)
    ap.add_argument("--site", default="pages", type=Path)
    ap.add_argument("--png", type=Path)
    args = ap.parse_args()

    head, ys, cs = read_log(args.log)
    m, d = load_course(args.site, head["id"])
    geo, ey, ec, grades = expected(d, m, int(head["s"]))
    print(f"코스 {head['id']} {m['name']}: 화면 {head['s']} px, 열 {len(ys)}개, 고도 축 {geo['ymin']:g}–{geo['ymax']:g} m")

    ok = True
    for key in ("x0", "w", "top", "base"):
        if int(head[key]) != geo[key]:
            print(f"  위치 {key}: 시계 {head[key]}, 계산 {geo[key]}")
            ok = False
    if abs(float(head["ymin"]) - geo["ymin"]) > 1e-3 or abs(float(head["ymax"]) - geo["ymax"]) > 1e-3:
        print(f"  고도 축: 시계 {head['ymin']}–{head['ymax']}, 계산 {geo['ymin']}–{geo['ymax']}")
        ok = False
    dy = [abs(a - b) for a, b in zip(ys, ey)]
    bad_y = [i for i, v in enumerate(dy) if v > 1]
    near = lambda g: min(abs(abs(g) - e) for e in EDGES) < 0.01  # noqa: E731
    bad_c = [i for i, (a, b) in enumerate(zip(cs, ec)) if a != b and not near(grades[i])]
    edge_c = sum(1 for a, b, g in zip(cs, ec, grades) if a != b and near(g))
    print(f"  높이: 같음 {dy.count(0)}열, 1 px 차이 {dy.count(1)}열, 그 이상 {len(bad_y)}열")
    print(f"  색: 다름 {len(bad_c)}열" + (f" (경계 경사라 허용 {edge_c}열)" if edge_c else ""))
    if bad_y or bad_c:
        ok = False
        for i in (bad_y + bad_c)[:10]:
            print(f"    열 {i}: 높이 {ys[i]} / {ey[i]}, 색 {cs[i]} / {ec[i]}, 경사 {grades[i]:.3f}%")
    if args.png:
        render(ys, cs, geo["top"], geo["base"], args.png)
        print(f"  시계 열 값으로 그린 그림: {args.png}")
    print("일치" if ok else "불일치")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
