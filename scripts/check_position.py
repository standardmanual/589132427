#!/usr/bin/env python3
"""시험 재생(app/source/Replay.mc)의 위치 결정 결과를 확인합니다 (명세 9장 6단계).

시뮬레이터 로그의 RP 줄(가상 러너의 실제 위치 t와 계산한 위치 d)을 시나리오별로 모아 봅니다.
  - 위치 출처: gps·dtdbug·lenbad는 GPS(2), garmin은 가민(1)이어야 합니다.
  - 오차 |d − t|: 코스 이탈 구간을 뺀 나머지의 중앙값·95%·최댓값
  - 뒤로 튐: 이탈 구간 밖에서 d가 30 m 넘게 줄어든 횟수
  - 코스 이탈 판정: 이탈 구간에서 이탈로 본 비율, 이탈 구간 밖에서 잘못 이탈로 본 횟수
  - 왕복 구간(샘플 코스 12.2–13.7 km 부근)의 최대 오차
GEO 줄(시계가 복원한 절대 좌표)은 코스 서버 폴더의 바이너리를 Python으로 풀어 비교합니다.
MODE 줄(화면 모드 전환, 명세 7.6)은 이웃 구간으로 넘어갈 때 새 구간으로 30 m 이상 들어간 뒤에 바뀌었는지 봅니다.

  python3 scripts/check_position.py [--log bin/app-sim.log] [--site pages]
"""

import argparse
import base64
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from trailgrade.encode import decode_binary  # noqa: E402

EXPECT_SRC = {"gps": 2, "garmin": 1, "dtdbug": 2, "lenbad": 2}
LIMITS = {"p95": 25.0, "max": 60.0, "back": 0, "regress": 60.0}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log", default="bin/app-sim.log", type=Path)
    ap.add_argument("--site", default="pages", type=Path)
    args = ap.parse_args()

    rows = defaultdict(list)
    modes = defaultdict(list)
    scenario = None
    geo = []
    course_id = None
    for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("RP_START "):
            scenario = line.split()[1]
        elif line.startswith("MODE ") and scenario:
            kv = dict(p.split("=", 1) for p in line.split()[1:])
            modes[scenario].append((int(kv["seg"]), float(kv["d"])))
        elif line.startswith("RP "):
            head, gs = line.split(" gs=", 1)  # 가민 상태(gs)에는 띄어쓰기가 들어갈 수 있음
            parts = head.split()
            kv = dict(p.split("=", 1) for p in parts[2:])
            kv["gs"] = gs
            rows[parts[1]].append(kv)
        elif line.startswith("GEO "):
            geo.append([int(v) for v in line.split()[1:]])
        elif line.startswith("loaded stored course "):
            course_id = line.split()[3]
        elif line.startswith("active "):
            course_id = line.split()[1].rstrip(",")
    if not rows:
        raise SystemExit("로그에 RP 줄이 없습니다. TrailConfig.DEBUG_REPLAY를 켜고 실행하세요.")

    ok = True
    if course_id and geo:
        m = dict(x.split("=", 1) for x in (args.site / "c" / course_id / "m.txt").read_text(encoding="utf-8").splitlines())
        b = b"".join(base64.b64decode((args.site / "c" / course_id / f"{i}.txt").read_text()) for i in range(int(m["chunks"])))
        d = decode_binary(b)
        bad = [(i, la, lo, d.lat[i], d.lon[i]) for i, la, lo in geo if (la, lo) != (d.lat[i], d.lon[i])]
        print(f"코스 {course_id} {m['name']}: 좌표 복원 {len(geo) - len(bad)}/{len(geo)}점 일치")
        if bad:
            ok = False
            for row in bad:
                print("  불일치", row)

    for name, rs in rows.items():
        t = [float(r["t"]) for r in rs]
        dd = [float(r["d"]) for r in rs]
        ex = [r["ex"] == "1" for r in rs]
        off = [r["off"] == "1" for r in rs]
        src = [int(r["src"]) for r in rs]
        err = [abs(a - b) for a, b, e in zip(dd, t, ex) if not e]
        back = sum(1 for i in range(1, len(dd)) if not ex[i] and not ex[i - 1] and dd[i] < dd[i - 1] - 30)
        # 조금씩 뒤로 가는 경우도 잡기 위해, 이탈 구간 밖에서 그때까지의 최댓값보다 얼마나 뒤로 갔는지 봅니다.
        regress, top = 0.0, 0.0
        for a, e in zip(dd, ex):
            if e:
                continue
            regress = max(regress, top - a)
            top = max(top, a)
        n_ex = sum(ex)
        hit = sum(1 for e, o in zip(ex, off) if e and o)
        false_off = sum(1 for e, o in zip(ex, off) if not e and o)
        want = EXPECT_SRC.get(name)
        src_ok = sum(1 for s in src if s == want)
        spur = [abs(a - b) for a, b, e in zip(dd, t, ex) if 12000 <= b <= 14000 and not e]
        p95 = sorted(err)[int(len(err) * 0.95) - 1] if err else 0.0
        print(f"[{name}] 표본 {len(rs)}개, {t[0]:.0f}–{t[-1]:.0f} m")
        print(f"  출처 기대값({want}) {src_ok}/{len(src)}" + ("" if src_ok == len(src) else f", 그 외 {sorted(set(src))}, 가민 상태 {rs[-1]['gs']}"))
        print(f"  오차 중앙값 {statistics.median(err):.1f} m, 95% {p95:.1f} m, 최대 {max(err):.1f} m,"
              f" 뒤로 튐(30 m 넘게) {back}회, 최대 후퇴 {regress:.0f} m")
        if n_ex:
            # 이탈 경로가 코스의 다른 부분 가까이를 지나면 30초 뒤 전체 탐색이 그쪽에 붙을 수 있어 참고로만 봅니다.
            print(f"  코스 이탈 구간 {n_ex}개 중 이탈 판정 {hit}개(참고), 구간 밖 잘못된 이탈 {false_off}개")
        elif false_off:
            print(f"  잘못된 이탈 판정 {false_off}개")
        if spur:
            print(f"  12–14 km(왕복 구간) 최대 오차 {max(spur):.1f} m")
        # 이탈에서 돌아온 직후 몇 개는 다시 붙는 중이라 최댓값 판정에서 봐 줍니다.
        if src_ok != len(src) or p95 > LIMITS["p95"] or back > LIMITS["back"] or regress > LIMITS["regress"] or false_off:
            ok = False
        if max(err) > LIMITS["max"]:
            worst = max(range(len(rs)), key=lambda i: -1 if ex[i] else abs(dd[i] - t[i]))
            print(f"  최대 오차 위치: t={t[worst]:.0f} d={dd[worst]:.0f} (이탈 구간 끝 {max((tt for tt, e in zip(t, ex) if e), default=0):.0f} m)")
            ok = False
    # 화면 모드 전환 (gps 시나리오: 코스 전체를 지나감)
    if course_id and modes.get("gps"):
        segs = [(t, st * d.interval, en * d.interval) for t, st, en, *_ in d.segs]
        ms = modes["gps"]
        early = []
        for (a, _), (b, dd) in zip(ms, ms[1:]):
            if abs(b - a) == 1:
                into = dd - segs[b][1] if b > a else segs[b][2] - dd
                if into < 30 - 1e-6:
                    early.append((a, b, dd, into))
        visited = sorted({sg for sg, _ in ms})
        print(f"[모드] gps 시나리오 전환 {len(ms) - 1}회, 거친 구간 {len(visited)}/{len(segs)}개, 30 m 전에 바뀐 전환 {len(early)}회")
        for a, b, dd, into in early[:5]:
            print(f"  구간 {a}→{b} d={dd:.0f} m (새 구간으로 {into:.0f} m)")
        if early or len(visited) != len(segs):
            ok = False
    print("통과" if ok else "확인 필요")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
