#!/usr/bin/env python3
"""로컬 코스 서버 (시뮬레이터용). pages/ 폴더를 http로 제공하고, 끊김을 흉내 낼 수 있습니다.

  python3 scripts/course_server.py                     # 보통 서버
  python3 scripts/course_server.py --fail-after 3      # 조각 파일을 3개까지만 주고 이후 조각 요청은 503
  python3 scripts/course_server.py --delay 1.5         # 모든 응답을 1.5초 늦춤
  python3 scripts/course_server.py --root /tmp/site    # 다른 폴더 제공

요청마다 한 줄씩 기록합니다.
"""

import argparse
import functools
import re
import sys
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CHUNK = re.compile(r"^/c/[0-9a-f]{10}/\d+\.txt")


class Handler(SimpleHTTPRequestHandler):
    delay = 0.0
    fail_after = None
    served_chunks = 0

    def do_GET(self):
        if self.delay:
            time.sleep(self.delay)
        if CHUNK.match(self.path) and self.fail_after is not None:
            if Handler.served_chunks >= self.fail_after:
                self.send_error(503, "끊김 흉내")
                return
            Handler.served_chunks += 1
        super().do_GET()

    def guess_type(self, path):
        # GitHub Pages와 같은 Content-Type
        if str(path).endswith(".txt"):
            return "text/plain; charset=utf-8"
        if str(path).endswith(".html"):
            return "text/html; charset=utf-8"  # 프로토타입 HTML에는 charset 선언이 없음
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (time.strftime("%H:%M:%S"), fmt % args))
        sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent / "pages"))
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--delay", type=float, default=0.0)
    ap.add_argument("--fail-after", type=int)
    args = ap.parse_args()
    Handler.delay = args.delay
    Handler.fail_after = args.fail_after
    server = ThreadingHTTPServer(("127.0.0.1", args.port), functools.partial(Handler, directory=args.root))
    print(f"serving {args.root} on http://127.0.0.1:{args.port}/", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
