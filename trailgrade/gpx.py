"""GPX 파싱 (명세 6.1 1단계). 프로토타입 parseGPX와 같은 규칙을 씁니다.

- trkpt를 쓰고, 없으면 rtept를 씁니다.
- lat, lon이 숫자가 아닌 포인트는 건너뜁니다.
- ele가 없는 포인트는 빼고 개수를 missing으로 보고합니다.
- 코스 이름은 문서에서 처음 나오는 <name>입니다.
"""

from __future__ import annotations

import math
import xml.etree.ElementTree as ET
from dataclasses import dataclass


@dataclass
class GpxTrack:
    name: str | None
    pts: list  # (lat, lon, ele)
    missing: int


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _num(s) -> float:
    try:
        v = float(s)
    except (TypeError, ValueError):
        return math.nan
    return v


def parse_gpx(text: str | bytes) -> GpxTrack:
    try:
        root = ET.fromstring(text)
    except ET.ParseError as e:
        raise ValueError(f"GPX 파일을 읽을 수 없습니다. XML 형식이 올바른지 확인하세요. ({e})") from None

    elements = list(root.iter())
    nodes = [el for el in elements if _local(el.tag) == "trkpt"]
    if not nodes:
        nodes = [el for el in elements if _local(el.tag) == "rtept"]
    if len(nodes) < 2:
        raise ValueError("trkpt 또는 rtept 포인트가 2개 이상 있어야 합니다.")

    pts = []
    missing = 0
    for nd in nodes:
        la = _num(nd.get("lat"))
        lo = _num(nd.get("lon"))
        if not (math.isfinite(la) and math.isfinite(lo)):
            continue
        ele_el = next((ch for ch in nd if _local(ch.tag) == "ele"), None)
        ev = _num(ele_el.text) if ele_el is not None else math.nan
        if not math.isfinite(ev):
            missing += 1
            continue
        pts.append((la, lo, ev))
    if len(pts) < 2:
        raise ValueError("고도(ele) 값이 있는 포인트가 부족합니다. 고도가 들어 있는 GPX를 사용하세요.")

    name_el = next((el for el in elements if _local(el.tag) == "name"), None)
    name = name_el.text.strip() if name_el is not None and name_el.text and name_el.text.strip() else None
    return GpxTrack(name=name, pts=pts, missing=missing)


def write_gpx(name: str, pts) -> str:
    """시험용 GPX 문자열을 만듭니다 (위도·경도 소수 7자리, 고도 소수 1자리)."""
    rows = "\n".join(
        f'      <trkpt lat="{la:.7f}" lon="{lo:.7f}"><ele>{el:.1f}</ele></trkpt>' for la, lo, el in pts)
    safe = name.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<gpx version="1.1" creator="trailgrade" xmlns="http://www.topografix.com/GPX/1/1">\n'
            f'  <trk>\n    <name>{safe}</name>\n    <trkseg>\n{rows}\n    </trkseg>\n  </trk>\n</gpx>\n')
