"""코스 전처리: 누적 거리, 재샘플, 평활화, 양자화, 구간 분할과 통계 (명세 6.1–6.3).

프로토타입(prototype/trail-grade-field.html)의 buildCourse, zigzag, findPlateaus, trimPiece,
mergeSame, maxWin, segment를 계산 순서까지 그대로 옮겼습니다. 같은 입력이면 같은 결과가 나와야
하므로, 반올림은 JavaScript Math.round와 같은 js_round를 쓰고 연산 순서도 바꾸지 않습니다.
tests/test_parity.py가 Node로 프로토타입 코드를 직접 돌려 결과를 비교합니다.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

R_E = 6371008.8
RAD = math.pi / 180
FLAT_GRADE = 0.02
PLATEAU_LEN = 500

FLAT, UP, DOWN = "FLAT", "UP", "DOWN"


def js_round(x: float) -> int:
    """JavaScript Math.round: .5는 항상 +∞ 쪽으로 올립니다 (Python round와 다름)."""
    return math.floor(x + 0.5)


def clamp(v, a, b):
    return a if v < a else b if v > b else v


def haversine(la1, lo1, la2, lo2):
    d_la = (la2 - la1) * RAD
    d_lo = (lo2 - lo1) * RAD
    a = (math.sin(d_la / 2) * math.sin(d_la / 2)
         + math.cos(la1 * RAD) * math.cos(la2 * RAD) * math.sin(d_lo / 2) * math.sin(d_lo / 2))
    return 2 * R_E * math.asin(min(1, math.sqrt(a)))


def moving_avg(a, w):
    """중심 이동 평균. 양 끝은 창을 대칭으로 줄입니다."""
    n = len(a)
    h = w // 2
    pre = [0.0] * (n + 1)
    for i in range(n):
        pre[i + 1] = pre[i] + a[i]
    out = [0.0] * n
    for i in range(n):
        hh = min(h, i, n - 1 - i)
        out[i] = (pre[i + hh + 1] - pre[i - hh]) / (2 * hh + 1)
    return out


@dataclass
class Segment:
    type: str
    s: int
    e: int
    start_d: float = 0.0
    end_d: float = 0.0
    len: float = 0.0
    d_ele: float = 0.0
    gain: float = 0.0
    loss: float = 0.0
    avg: float = 0.0
    max: float = 0.0
    hi: float = 0.0
    lo: float = 0.0
    no: int = 0


@dataclass
class Course:
    interval: int
    n: int
    total: float
    lat: list
    lon: list
    raw_ele: list
    ele: list
    asc: list
    desc: list
    segs: list = field(default_factory=list)
    up_total: int = 0
    down_total: int = 0

    @property
    def gain(self) -> float:
        return self.asc[-1]

    @property
    def loss(self) -> float:
        return self.desc[-1]


def build_course(pts, interval=20, smooth=100, min_climb=20) -> Course:
    """pts: (lat, lon, ele) 목록. 원본 GPX 포인트 순서 그대로."""
    if len(pts) < 2:
        raise ValueError("포인트가 2개 이상 필요합니다.")
    I = interval
    n = len(pts)
    cum = [0.0] * n
    for i in range(1, n):
        cum[i] = cum[i - 1] + haversine(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1])
    N = max(3, math.floor(cum[n - 1] / I) + 1)
    lat = [0.0] * N
    lon = [0.0] * N
    raw_ele = [0.0] * N
    j = 0
    for k in range(N):
        d = min(k * I, cum[n - 1])
        while j < n - 2 and cum[j + 1] < d:
            j += 1
        sp = cum[j + 1] - cum[j]
        t = clamp((d - cum[j]) / sp, 0, 1) if sp > 0 else 0
        A, B = pts[j], pts[j + 1]
        lat[k] = A[0] + (B[0] - A[0]) * t
        lon[k] = A[1] + (B[1] - A[1]) * t
        raw_ele[k] = A[2] + (B[2] - A[2]) * t
    w = max(1, js_round(smooth / I))
    if w % 2 == 0:
        w += 1
    sm = moving_avg(raw_ele, w)
    ele = [js_round(v * 10) / 10 for v in sm]
    asc = [0.0] * N
    desc = [0.0] * N
    for k in range(1, N):
        dd = ele[k] - ele[k - 1]
        asc[k] = asc[k - 1] + max(0, dd)
        desc[k] = desc[k - 1] + max(0, -dd)
    c = Course(interval=I, n=N, total=(N - 1) * I, lat=lat, lon=lon,
               raw_ele=raw_ele, ele=ele, asc=asc, desc=desc)
    segment(c, min_climb)
    return c


def zigzag(e, T):
    """히스테리시스 T로 꺾임점 인덱스를 찾습니다. 첫 점과 마지막 점을 포함합니다."""
    n = len(e)
    turns = [0]
    direction = 0
    hi = lo = cand = 0
    for i in range(1, n):
        if direction == 0:
            if e[i] > e[hi]:
                hi = i
            if e[i] < e[lo]:
                lo = i
            if e[hi] - e[lo] >= T:
                if hi > lo:
                    if lo > 0:
                        turns.append(lo)
                    direction = 1
                    cand = hi
                else:
                    if hi > 0:
                        turns.append(hi)
                    direction = -1
                    cand = lo
        elif direction == 1:
            if e[i] >= e[cand]:
                cand = i
            elif e[cand] - e[i] >= T:
                turns.append(cand)
                direction = -1
                cand = i
        else:
            if e[i] <= e[cand]:
                cand = i
            elif e[i] - e[cand] >= T:
                turns.append(cand)
                direction = 1
                cand = i
    if direction != 0 and cand > turns[-1] and cand < n - 1:
        turns.append(cand)
    if turns[-1] != n - 1:
        turns.append(n - 1)
    return turns


def find_plateaus(e, a, b, max_r, min_pts, I):
    """[a, b] 안에서 고도 폭이 max_r 이내로 min_pts 이상 이어지는 범위를 찾습니다."""
    out = []
    k = max(2, js_round(100 / I))
    i = a
    while i < b:
        lo = hi = e[i]
        j = i
        while j < b:
            v = e[j + 1]
            nl = min(lo, v)
            nh = max(hi, v)
            if nh - nl > max_r:
                break
            lo, hi = nl, nh
            j += 1
        if j - i >= min_pts:
            s, t = i, j
            while t - k >= s and abs(e[t] - e[t - k]) / (k * I) >= FLAT_GRADE:
                t -= 1
            while s + k <= t and abs(e[s + k] - e[s]) / (k * I) >= FLAT_GRADE:
                s += 1
            if t - s >= min_pts:
                out.append((s, t))
                i = t
                continue
        i += 1
    return out


def trim_piece(e, a, b, typ, I, T):
    """UP/DOWN 조각의 앞뒤에서 진행 방향 100 m 경사가 2% 미만인 부분을 평지로 떼어 냅니다."""
    sgn = 1 if typ == UP else -1
    k = max(2, js_round(100 / I))
    s, t = a, b
    while s + k <= b and sgn * (e[s + k] - e[s]) / (k * I) < FLAT_GRADE:
        s += 1
    while t - k >= s and sgn * (e[t] - e[t - k]) / (k * I) < FLAT_GRADE:
        t -= 1
    if t - s < 1:
        return [Segment(FLAT, a, b)]
    out = []
    if s > a:
        out.append(Segment(FLAT, a, s))
    out.append(Segment(typ if sgn * (e[t] - e[s]) >= T * 0.5 else FLAT, s, t))
    if t < b:
        out.append(Segment(FLAT, t, b))
    return out


def merge_same(arr):
    out = []
    for p in arr:
        if p.e <= p.s:
            continue
        if out and out[-1].type == p.type:
            out[-1].e = p.e
        else:
            out.append(Segment(p.type, p.s, p.e))
    return out


def max_win(e, a, b, sgn, I):
    """[a, b]에서 100 m 창 경사(%)의 최댓값. 진행 방향 부호 sgn."""
    k = max(1, js_round(100 / I))
    if b - a <= k:
        return sgn * (e[b] - e[a]) / ((b - a) * I) * 100
    best = -math.inf
    for i in range(a, b - k + 1):
        v = sgn * (e[i + k] - e[i]) / (k * I)
        if v > best:
            best = v
    return best * 100


def segment(c: Course, T: float):
    """구간 분할(명세 6.2)과 통계(6.3). 결과를 c.segs에 넣고 돌려줍니다."""
    e = c.ele
    I = c.interval
    turns = zigzag(e, T)
    pieces = []
    for q in range(len(turns) - 1):
        a, b = turns[q], turns[q + 1]
        if b <= a:
            continue
        d_e = e[b] - e[a]
        length = (b - a) * I
        if abs(d_e) >= T - 1e-6 and abs(d_e) / length >= FLAT_GRADE:
            typ = UP if d_e > 0 else DOWN
        else:
            typ = FLAT
        if typ == FLAT:
            pieces.append(Segment(typ, a, b))
            continue
        cur = a
        for ps, pe in find_plateaus(e, a, b, T * 0.75, js_round(PLATEAU_LEN / I), I):
            if ps > cur:
                pieces.extend(trim_piece(e, cur, ps, typ, I, T))
            pieces.append(Segment(FLAT, ps, pe))
            cur = pe
        if b > cur:
            pieces.extend(trim_piece(e, cur, b, typ, I, T))

    segs = merge_same(pieces)
    i = 0
    while i < len(segs):
        s = segs[i]
        min_len = 150 if s.type == FLAT else 100
        if (s.e - s.s) * I < min_len and len(segs) > 1:
            if i > 0:
                segs[i - 1].e = s.e
            else:
                segs[i + 1].s = s.s
            del segs[i]
            i -= 1
        i += 1
    segs = merge_same(segs)

    up = dn = 0
    for s in segs:
        s.start_d = s.s * I
        s.end_d = s.e * I
        s.len = s.end_d - s.start_d
        s.d_ele = e[s.e] - e[s.s]
        s.gain = c.asc[s.e] - c.asc[s.s]
        s.loss = c.desc[s.e] - c.desc[s.s]
        s.avg = s.d_ele / s.len * 100
        if s.type == UP:
            s.max = max_win(e, s.s, s.e, 1, I)
        elif s.type == DOWN:
            s.max = max_win(e, s.s, s.e, -1, I)
        else:
            s.max = max(max_win(e, s.s, s.e, 1, I), max_win(e, s.s, s.e, -1, I))
        span = e[s.s:s.e + 1]
        s.hi = max(span)
        s.lo = min(span)
        if s.type == UP:
            up += 1
            s.no = up
        elif s.type == DOWN:
            dn += 1
            s.no = dn
    c.segs = segs
    c.up_total = up
    c.down_total = dn
    return segs
