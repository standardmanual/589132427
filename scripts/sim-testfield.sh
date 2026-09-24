#!/bin/zsh
# 시험 필드를 로컬에서 빌드하고, pages/ 폴더를 로컬 서버로 띄운 뒤 Connect IQ 시뮬레이터에서 실행합니다.
# 사용법: scripts/sim-testfield.sh [기기 id]   (기본 fenix847mm, 43mm는 fenix843mm)
# 결과 로그는 bin/sim.log에도 남습니다.
set -e
ROOT=${0:A:h:h}
DEVICE=${1:-fenix847mm}
PORT=8765
SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"connectiq-sdk-mac-* | sort -V | tail -1)
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$SDK/bin:$PATH"

KEY="$ROOT/jamtrail_developer_key.der"
[[ -f $KEY ]] || KEY="$HOME/Library/Application Support/Garmin/ConnectIQ/developer_key.der"

mkdir -p "$ROOT/bin"
monkeyc -f "$ROOT/testfield/monkey.jungle" -d "$DEVICE" -y "$KEY" -o "$ROOT/bin/JAMTEST-$DEVICE.prg" -w

# 로컬 서버: 이미 떠 있으면 그대로 씁니다.
if ! curl -fs "http://127.0.0.1:$PORT/t/ping.txt" >/dev/null; then
  (cd "$ROOT/pages" && python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1 &)
  sleep 1
fi

# 시뮬레이터가 없으면 띄웁니다.
pgrep -f ConnectIQ.app/Contents/MacOS/simulator >/dev/null || { connectiq & sleep 5; }

monkeydo "$ROOT/bin/JAMTEST-$DEVICE.prg" "$DEVICE" | tee "$ROOT/bin/sim.log"
