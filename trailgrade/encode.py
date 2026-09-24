"""바이너리 인코딩(명세 6.4)과 전송용 조각(6.5).

바이트 순서는 빅엔디언입니다. decode_binary는 시계 쪽 복원 코드의 기준 구현이자 시험용입니다.

헤더 20 B : "TG", 버전 u8, 간격 u8, 포인트 수 u16, 구간 수 u16, 첫 점 위도 i32, 경도 i32 (1e-5°), 예약 u32
본문      : 고도 N × u16 (0.1 m) / 좌표 (N−1) × (위도 i16, 경도 i16) 델타 (1e-5°) / 구간 레코드 × 10 B
구간 레코드: 유형 u8, 플래그 u8, 시작 u16, 끝 u16, 순 고도 변화 i16 (0.1 m), 평균 경사 i8, 최대 경사 u8 (0.5%)
"""

from __future__ import annotations

import base64
import hashlib
import struct
import zlib
from dataclasses import dataclass

from .course import DOWN, FLAT, UP, Course, js_round

MAGIC = b"TG"
VERSION = 1
HEADER = struct.Struct(">2sBBHHiiI")
SEG = struct.Struct(">BBHHhbB")
TYPE_CODE = {FLAT: 0, UP: 1, DOWN: 2}
CODE_TYPE = {v: k for k, v in TYPE_CODE.items()}


class EncodeError(ValueError):
    pass


def _clamp_int(v: int, lo: int, hi: int, warn: list, what: str) -> int:
    if v < lo or v > hi:
        warn.append(f"{what} 값 {v}이(가) 범위 {lo}–{hi}를 벗어나 잘랐습니다.")
        return lo if v < lo else hi
    return v


def encode_binary(c: Course, warnings: list | None = None) -> bytes:
    warn = warnings if warnings is not None else []
    if not 1 <= c.interval <= 255:
        raise EncodeError(f"재샘플 간격은 1–255 m여야 합니다: {c.interval}")
    if c.n > 0xFFFF:
        raise EncodeError(f"포인트 수가 65,535개를 넘습니다: {c.n}. 간격을 늘리세요.")

    qlat = [js_round(v * 1e5) for v in c.lat]
    qlon = [js_round(v * 1e5) for v in c.lon]
    out = bytearray(HEADER.pack(MAGIC, VERSION, c.interval, c.n, len(c.segs), qlat[0], qlon[0], 0))

    low = 0
    for v in c.ele:
        q = js_round(v * 10)
        if q < 0 or q > 0xFFFF:
            low += 1
            q = 0 if q < 0 else 0xFFFF
        out += struct.pack(">H", q)
    if low:
        warn.append(f"고도 0–6,553.5 m 범위를 벗어난 포인트 {low}개를 잘랐습니다.")

    for k in range(1, c.n):
        dla, dlo = qlat[k] - qlat[k - 1], qlon[k] - qlon[k - 1]
        if not (-32768 <= dla <= 32767 and -32768 <= dlo <= 32767):
            raise EncodeError(f"{k}번 포인트의 좌표 변화가 int16 범위를 넘습니다. 원본 GPX에 튀는 점이 있는지 확인하세요.")
        out += struct.pack(">hh", dla, dlo)

    for s in c.segs:
        out += SEG.pack(
            TYPE_CODE[s.type], 0, s.s, s.e,
            _clamp_int(js_round(s.d_ele * 10), -32768, 32767, warn, "순 고도 변화"),
            _clamp_int(js_round(s.avg * 2), -128, 127, warn, "평균 경사"),
            _clamp_int(js_round(s.max * 2), 0, 255, warn, "최대 경사"),
        )

    expected = 20 + 2 * c.n + 4 * (c.n - 1) + 10 * len(c.segs)
    assert len(out) == expected, (len(out), expected)
    return bytes(out)


@dataclass
class Decoded:
    interval: int
    n: int
    lat: list  # 1e-5° 정수
    lon: list
    ele: list  # 0.1 m 정수
    segs: list  # (유형, 시작, 끝, 순 고도 변화 0.1 m, 평균 0.5%, 최대 0.5%)


def decode_binary(b: bytes) -> Decoded:
    magic, ver, interval, n, nseg, lat0, lon0, _ = HEADER.unpack_from(b, 0)
    if magic != MAGIC or ver != VERSION:
        raise ValueError("코스 바이너리 형식이 아닙니다.")
    off = HEADER.size
    ele = list(struct.unpack_from(f">{n}H", b, off))
    off += 2 * n
    lat, lon = [lat0], [lon0]
    deltas = struct.unpack_from(f">{2 * (n - 1)}h", b, off)
    off += 4 * (n - 1)
    for k in range(n - 1):
        lat.append(lat[-1] + deltas[2 * k])
        lon.append(lon[-1] + deltas[2 * k + 1])
    segs = []
    for _ in range(nseg):
        t, _flags, s, e, de, avg, mx = SEG.unpack_from(b, off)
        segs.append((CODE_TYPE[t], s, e, de, avg, mx))
        off += SEG.size
    if off != len(b):
        raise ValueError(f"바이너리 길이가 맞지 않습니다: {off} != {len(b)}")
    return Decoded(interval, n, lat, lon, ele, segs)


def course_id(b: bytes) -> str:
    """내용이 같으면 같은 ID. 조각 주소가 바뀌지 않아 캐시 문제가 없습니다."""
    return hashlib.sha256(b).hexdigest()[:10]


def crc32_hex(b: bytes) -> str:
    return f"{zlib.crc32(b) & 0xFFFFFFFF:08x}"


def make_chunks(b: bytes, chunk_chars: int) -> list[str]:
    """Base64 텍스트를 chunk_chars 글자씩 나눕니다.

    8의 배수여야 합니다. 4의 배수면 조각마다 따로 풀 수 있고, 8의 배수면 풀린 조각의 바이트 수가 짝수라
    시계가 조각을 합치지 않고 읽을 때 2바이트 값이 두 조각에 걸치지 않습니다(app/source/TrailCourse.mc).
    """
    if chunk_chars <= 0 or chunk_chars % 8:
        raise EncodeError(f"조각 크기는 8의 배수인 양수여야 합니다: {chunk_chars}")
    text = base64.b64encode(b).decode("ascii")
    return [text[i:i + chunk_chars] for i in range(0, len(text), chunk_chars)]
