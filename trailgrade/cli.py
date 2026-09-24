"""명령줄: python -m trailgrade build <GPX 파일 또는 폴더>... [옵션]"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tomllib
import unicodedata
from pathlib import Path

from .course import DOWN, FLAT, UP, build_course
from .encode import EncodeError, course_id, crc32_hex, encode_binary, make_chunks
from .gpx import parse_gpx
from .preview import render_preview
from .site import update_index, write_course

DEFAULTS = {"interval": 20, "smooth": 100, "min_climb": 20, "chunk_chars": 6000, "out": "pages"}


def load_config(path: Path | None) -> dict:
    cfg = dict(DEFAULTS)
    p = path or Path("trailgrade.toml")
    if p.exists():
        with p.open("rb") as f:
            cfg.update(tomllib.load(f).get("build", {}))
    elif path is not None:
        raise SystemExit(f"설정 파일이 없습니다: {path}")
    return cfg


def git_time(f: Path) -> int:
    """파일을 마지막으로 커밋한 시각. 커밋되지 않았으면 0

    한글 파일 이름은 macOS 파일 시스템과 git에 저장된 유니코드 정규화(NFC/NFD)가 다를 수 있어 둘 다 찾아봅니다.
    """
    for form in ("NFC", "NFD"):
        try:
            # macOS git은 경로를 NFC로 바꿔 찾는 설정(core.precomposeunicode)이 켜져 있어 NFD 이름을 못 찾으므로 끕니다.
            out = subprocess.run(["git", "-c", "core.precomposeunicode=false", "log", "-1", "--format=%ct", "--",
                                  unicodedata.normalize(form, str(f))],
                                 capture_output=True, text=True, check=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            return 0
        if out.isdigit():
            return int(out)
    return 0


def collect_gpx(inputs: list[str], order: str = "mtime") -> list[Path]:
    """폴더는 안의 .gpx를 추가된 순서로 넣습니다. 마지막 파일이 현재 코스가 됩니다.

    order="mtime"은 파일 수정 시각, "git"은 마지막 커밋 시각 순입니다. GitHub Actions에서는 체크아웃한
    파일의 수정 시각이 모두 같아 git 순서를 씁니다 (.github/workflows/pages.yml).
    """
    key = (lambda f: (git_time(f), f.name)) if order == "git" else (lambda f: (f.stat().st_mtime, f.name))
    files = []
    for s in inputs:
        p = Path(s)
        if p.is_dir():
            files += sorted(p.glob("*.gpx"), key=key)
        elif p.exists():
            files.append(p)
        else:
            raise SystemExit(f"파일을 찾을 수 없습니다: {s}")
    if not files:
        raise SystemExit("변환할 GPX 파일이 없습니다.")
    return files


def seg_name(s) -> str:
    return f"오르막 {s.no}" if s.type == UP else f"내리막 {s.no}" if s.type == DOWN else "평지"


def signed(v: float, fmt: str) -> str:
    return ("+" if v >= 0 else "−") + format(abs(v), fmt)


def pad(text: str, width: int) -> str:
    """한글처럼 두 칸을 차지하는 글자를 세어 왼쪽 정렬합니다."""
    cells = sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)
    return text + " " * max(0, width - cells)


def print_table(c):
    print(f"  {'#':>3}  {pad('구간', 9)} {'시작':>7}    {'길이':>7}  {'고도 변화':>7}  {'평균':>5}   {'최대':>4}")
    for i, s in enumerate(c.segs, 1):
        print(f"  {i:>3}  {pad(seg_name(s), 9)} {s.start_d / 1000:>6.2f} km {s.len / 1000:>6.2f} km "
              f"{signed(round(s.d_ele), 'd'):>7} m {signed(s.avg, '.1f'):>6}% {s.max:>5.1f}%")


def build_one(path: Path, cfg: dict, site: Path, make_current: bool, preview: bool, dry_run: bool) -> None:
    trk = parse_gpx(path.read_bytes())
    name = trk.name or path.stem
    c = build_course(trk.pts, cfg["interval"], cfg["smooth"], cfg["min_climb"])
    warnings: list[str] = []
    binary = encode_binary(c, warnings)
    cid, crc = course_id(binary), crc32_hex(binary)
    chunks = make_chunks(binary, cfg["chunk_chars"])
    cnt = {t: sum(1 for s in c.segs if s.type == t) for t in (UP, DOWN, FLAT)}

    print(f"{path.name} → {name}")
    print(f"  원본 포인트 {len(trk.pts):,}개" + (f" (고도 없는 {trk.missing}개 제외)" if trk.missing else ""))
    print(f"  길이 {c.total / 1000:.2f} km · 누적 상승 +{round(c.gain):,} m / 하강 −{round(c.loss):,} m"
          f" · {c.n:,}점 ({c.interval} m 간격)")
    print(f"  구간 {len(c.segs)}개: 오르막 {cnt[UP]} · 내리막 {cnt[DOWN]} · 평지 {cnt[FLAT]}")
    print(f"  바이너리 {len(binary):,} B → Base64 {sum(map(len, chunks)):,}자, 조각 {len(chunks)}개"
          f" · ID {cid} · CRC {crc}")
    for w in warnings:
        print(f"  경고: {w}")
    print_table(c)

    if dry_run:
        return
    png = None
    if preview:
        png, ticks = render_preview(c)
        print(f"  미리보기: 고도 눈금 {ticks['ele_step_m']:g} m ({ticks['ele_min_m']:g}–{ticks['ele_max_m']:g} m),"
              f" 거리 눈금 {ticks['km_step']:g} km")
    built = write_course(site, c, name, cid, crc, len(binary), chunks, png)
    update_index(site, built, make_current)
    print(f"  저장: {site / 'c' / cid}" + (" (현재 코스로 지정)" if make_current else ""))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m trailgrade", description="JAM Trail 코스 변환기")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="GPX를 코스 서버 파일로 변환")
    b.add_argument("inputs", nargs="+", help="GPX 파일 또는 GPX가 든 폴더")
    b.add_argument("--out", help="코스 서버 폴더 (기본: 설정의 out)")
    b.add_argument("--interval", type=int, help="재샘플 간격 m")
    b.add_argument("--smooth", type=int, help="이동 평균 창 m")
    b.add_argument("--min-climb", type=float, help="구간 분할 히스테리시스 m")
    b.add_argument("--chunk-chars", type=int, help="Base64 조각 크기 (4의 배수)")
    b.add_argument("--config", type=Path, help="설정 파일 (기본: ./trailgrade.toml)")
    b.add_argument("--no-current", action="store_true", help="current.txt를 바꾸지 않음")
    b.add_argument("--no-preview", action="store_true", help="preview.png를 만들지 않음")
    b.add_argument("--dry-run", action="store_true", help="파일을 쓰지 않고 결과만 출력")
    b.add_argument("--order", choices=["mtime", "git"], default="mtime",
                   help="폴더 안 GPX 순서: 수정 시각(mtime) 또는 마지막 커밋 시각(git). 마지막이 현재 코스")
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    for key in ("interval", "smooth", "min_climb", "chunk_chars", "out"):
        v = getattr(args, key)
        if v is not None:
            cfg[key] = v
    site = Path(cfg["out"])
    files = collect_gpx(args.inputs, args.order)
    failed = 0
    for i, f in enumerate(files):
        try:
            build_one(f, cfg, site, make_current=not args.no_current and i == len(files) - 1,
                      preview=not args.no_preview, dry_run=args.dry_run)
        except (ValueError, EncodeError) as e:
            failed += 1
            print(f"{f.name}: 변환 실패 — {e}", file=sys.stderr)
    return 1 if failed else 0
