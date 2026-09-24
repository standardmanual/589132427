"""코스 서버 파일 쓰기 (명세 6.6).

site/
  current.txt          현재 코스 ID 한 줄 (줄바꿈 없음)
  index.txt            코스 목록, 최신순 최대 20개: <id>\\t<이름>\\t<길이 m>\\t<누적 상승 m>\\t<조각 수>
  c/<id>/m.txt         매니페스트 key=value 줄: v, id, name, bytes, chunks, crc32, len, gain, loss, emin, emax
                       gain·loss는 누적 상승·하강(m), emin·emax는 최저·최고 고도(0.1 m 정수).
                       시계가 코스 전체를 한 번에 훑으면 워치독(실행 시간 한도)에 걸려 변환기가 미리 계산합니다.
  c/<id>/<i>.txt       Base64 조각 (줄바꿈 없음)
  c/<id>/preview.png   검증용 프로파일 그림
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass
from pathlib import Path

from .course import Course, js_round

INDEX_MAX = 20


@dataclass
class Built:
    id: str
    name: str
    bytes: int
    chunks: int
    crc32: str
    length_m: int
    gain_m: int


def clean_name(name: str) -> str:
    """탭·줄바꿈은 목록 형식을 깨므로 공백으로 바꾸고, 한글 자모를 완성형(NFC)으로 합칩니다.

    맥에서 올린 파일 이름은 자모가 분리된(NFD) 형태로 저장돼, 그대로 두면 시계 글꼴이 글자를 합쳐 그리지 못합니다.
    """
    return " ".join(unicodedata.normalize("NFC", name).replace("\t", " ").split()) or "코스"


def write_course(site: Path, c: Course, name: str, cid: str, crc: str, nbytes: int,
                 chunks: list[str], preview_png: bytes | None) -> Built:
    d = site / "c" / cid
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.txt"):
        old.unlink()
    for i, text in enumerate(chunks):
        (d / f"{i}.txt").write_text(text, encoding="ascii")
    built = Built(cid, clean_name(name), nbytes, len(chunks), crc, js_round(c.total), js_round(c.gain))
    manifest = {
        "v": 1, "id": cid, "name": built.name, "bytes": nbytes,
        "chunks": len(chunks), "crc32": crc, "len": built.length_m,
        "gain": built.gain_m, "loss": js_round(c.loss),
        "emin": js_round(min(c.ele) * 10), "emax": js_round(max(c.ele) * 10),
    }
    (d / "m.txt").write_text("".join(f"{k}={v}\n" for k, v in manifest.items()), encoding="utf-8")
    if preview_png is not None:
        (d / "preview.png").write_bytes(preview_png)
    return built


def read_index(site: Path) -> list[list[str]]:
    p = site / "index.txt"
    if not p.exists():
        return []
    return [line.split("\t") for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]


def update_index(site: Path, built: Built, make_current: bool = True) -> list[list[str]]:
    """새 코스를 목록 맨 앞에 넣고(같은 ID는 옮김) 최대 20개로 자릅니다."""
    rows = [r for r in read_index(site) if r[0] != built.id]
    rows.insert(0, [built.id, built.name, str(built.length_m), str(built.gain_m), str(built.chunks)])
    rows = rows[:INDEX_MAX]
    site.mkdir(parents=True, exist_ok=True)
    (site / "index.txt").write_text("".join("\t".join(r) + "\n" for r in rows), encoding="utf-8")
    if make_current:
        (site / "current.txt").write_text(built.id, encoding="ascii")
    return rows
