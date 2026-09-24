"""검증용 코스 전체 프로파일 PNG (명세 6.1 10단계). 표준 라이브러리만 씁니다.

프로토타입의 전체 개요 그래프(drawOverviewBase)와 같은 구성입니다.
- 맨 위 띠: 구간 유형 (주황 오르막, 파랑 내리막, 회색 평지)
- 채움: 평활화 고도, 경사 색 (명세 3.3)
- 회색 선: 재샘플 원본 고도, 흰 선: 평활화 고도
- 가는 세로선: 구간 경계, 옅은 가로·세로선: 고도 눈금과 km 눈금
글자는 넣지 않습니다. 눈금 간격은 CLI가 함께 출력합니다.
"""

from __future__ import annotations

import math
import struct
import zlib

from .course import DOWN, UP, Course

# 경사 색 3단계 (명세 3.3): 0–10, 10–20, 20% 이상
EDGES = [10, 20]
UP_COLORS = ["#00df3f", "#fefc00", "#e00041"]
DN_COLORS = ["#00e074", "#38c5ff", "#8600ee"]
UP_ID, DN_ID, FLAT_ID = "#fe6a00", "#1888ff", "#3d3d3d"


def _rgb(h: str) -> tuple:
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


def grade_color(g: float) -> tuple:
    a = abs(g)
    i = next((k for k, edge in enumerate(EDGES) if a < edge), len(EDGES))
    return _rgb((UP_COLORS if g >= 0 else DN_COLORS)[i])


def nice_step(raw: float) -> float:
    p = 10 ** math.floor(math.log10(raw))
    f = raw / p
    return (1 if f < 1.5 else 2 if f < 3.5 else 5 if f < 7.5 else 10) * p


class Canvas:
    def __init__(self, w: int, h: int, bg=(0, 0, 0)):
        self.w, self.h = w, h
        self.px = bytearray(bytes(bg) * (w * h))

    def set(self, x: int, y: int, c: tuple, alpha: float = 1.0):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 3
            if alpha >= 1:
                self.px[i:i + 3] = bytes(c)
            else:
                for k in range(3):
                    self.px[i + k] = round(self.px[i + k] * (1 - alpha) + c[k] * alpha)

    def rect(self, x0: int, y0: int, x1: int, y1: int, c: tuple):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.set(x, y, c)

    def polyline(self, pts, c: tuple, alpha: float = 1.0):
        """(x, y) 실수 좌표를 잇는 1 px 선. 인접 열 사이는 세로로 메워 끊기지 않게 합니다."""
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0))))
            for s in range(steps + 1):
                t = s / steps
                self.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), c, alpha)

    def png(self) -> bytes:
        raw = b"".join(b"\x00" + bytes(self.px[y * self.w * 3:(y + 1) * self.w * 3]) for y in range(self.h))

        def chunk(tag: bytes, data: bytes) -> bytes:
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        return (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


def render_preview(c: Course, width: int = 1200, height: int = 360) -> tuple[bytes, dict]:
    """PNG 바이트와 눈금 정보(고도 눈금 m, 거리 눈금 km, 고도 범위)를 돌려줍니다."""
    cv = Canvas(width, height)
    pad_l, pad_r, pad_t, pad_b = 16, 16, 30, 16
    pw, ph = width - pad_l - pad_r, height - pad_t - pad_b
    mn = min(min(c.ele), min(c.raw_ele))
    mx = max(max(c.ele), max(c.raw_ele))
    ys = nice_step(max(10, (mx - mn) / 4))
    y_min = math.floor(mn / ys) * ys
    y_max = math.ceil(mx / ys) * ys
    if y_max == y_min:
        y_max += ys
    I = c.interval

    def X(d):
        return pad_l + d / c.total * pw

    def Y(e):
        return pad_t + ph - (e - y_min) / (y_max - y_min) * ph

    grid = (29, 29, 29)
    v = y_min
    while v <= y_max + 0.1:
        cv.rect(pad_l, round(Y(v)), pad_l + pw, round(Y(v)) + 1, grid)
        v += ys
    xs = nice_step(c.total / 1000 / 7)
    k = 0.0
    while k <= c.total / 1000 + 1e-9:
        x = round(X(k * 1000))
        cv.rect(x, pad_t, x + 1, pad_t + ph, grid)
        k += xs

    # 경사 색 채움: 열마다 그 지점의 경사(프로토타입 개요와 같은 창)로 칠합니다.
    n = c.n
    for x in range(pad_l, pad_l + pw):
        d = (x - pad_l + 0.5) / pw * c.total
        q = min(n - 2, int(d / I))
        a, b = max(0, q - 1), min(n - 1, q + 2)
        g = (c.ele[b] - c.ele[a]) / ((b - a) * I) * 100
        f = d / I - q
        e = c.ele[q] + (c.ele[q + 1] - c.ele[q]) * f
        cv.rect(x, round(Y(e)), x + 1, pad_t + ph, grade_color(g))

    cv.polyline([(X(i * I), Y(c.raw_ele[i])) for i in range(n)], (150, 150, 150), 0.75)
    cv.polyline([(X(i * I), Y(c.ele[i])) for i in range(n)], (237, 237, 237))

    for i, s in enumerate(c.segs):
        x1, x2 = round(X(s.start_d)), round(X(s.end_d))
        col = _rgb(UP_ID if s.type == UP else DN_ID if s.type == DOWN else FLAT_ID)
        cv.rect(x1 + (1 if i else 0), 8, max(x1 + 2, x2), 18, col)
        if i:
            cv.rect(x1, 22, x1 + 1, pad_t + ph, (60, 60, 60))

    return cv.png(), {"ele_step_m": ys, "ele_min_m": y_min, "ele_max_m": y_max, "km_step": xs}
