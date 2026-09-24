"""시험용 가상 코스. 난수 씨앗을 고정해 항상 같은 코스를 만듭니다."""

from __future__ import annotations

import math
import random

LAT0, LON0 = 37.60, 127.00
M_LAT = 111320.0


def _to_latlon(xs, ys):
    m_lon = M_LAT * math.cos(LAT0 * math.pi / 180)
    return [(LAT0 + y / M_LAT, LON0 + x / m_lon) for x, y in zip(xs, ys)]


def out_and_back(step: float = 10.0) -> list:
    """약 5 km 왕복: 2.5 km 동안 300 m 오르고 4 m 옆 길로 되돌아 내려옵니다. 중간에 짧은 평지."""
    rnd = random.Random(7)
    half = int(2500 / step)
    xs, ys, es = [0.0], [0.0], [120.0]
    h = 0.3
    for i in range(1, half + 1):
        h += (rnd.random() - 0.5) * 0.15
        xs.append(xs[-1] + math.cos(h) * step)
        ys.append(ys[-1] + math.sin(h) * step)
        d = i * step
        rise = 0.0 if 900 <= d < 1500 else 300 / 1900 * step  # 900–1500 m는 평지
        es.append(es[-1] + rise + (rnd.random() - 0.5) * 0.8)
    for i in range(half - 1, -1, -1):
        k0, k1 = max(0, i - 1), min(half, i + 1)
        tx, ty = xs[k1] - xs[k0], ys[k1] - ys[k0]
        L = math.hypot(tx, ty) or 1
        xs.append(xs[i] - ty / L * 4)
        ys.append(ys[i] + tx / L * 4)
        es.append(es[i] + (rnd.random() - 0.5) * 1.5)
    return [(la, lo, e) for (la, lo), e in zip(_to_latlon(xs, ys), es)]


def long_course(km: float = 100.0, step: float = 10.0) -> list:
    """약 100 km 산악 코스: 여러 봉우리와 긴 평지, 잡음이 섞인 고도."""
    rnd = random.Random(20260925)
    n = int(km * 1000 / step) + 1
    xs, ys, es = [], [], []
    x = y = 0.0
    h = 0.0
    for i in range(n):
        if i:
            h += (rnd.random() - 0.5) * 0.12
            x += math.cos(h) * step
            y += math.sin(h) * step
        d = i * step
        e = (800 + 380 * math.sin(d / 7000) + 220 * math.sin(d / 2300 + 1.3)
             + 90 * math.sin(d / 800 + 0.4) + (rnd.random() - 0.5) * 3)
        xs.append(x)
        ys.append(y)
        es.append(e)
    return [(la, lo, e) for (la, lo), e in zip(_to_latlon(xs, ys), es)]
