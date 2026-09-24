#!/bin/zsh
# 본 데이터 필드(app/)를 빌드해 Connect IQ 시뮬레이터에서 실행합니다.
# 사용법: scripts/sim-app.sh [--reset] [--replay] [기기 id]   (기본 fenix847mm, 43mm는 fenix843mm)
#   --reset   실행 전에 시뮬레이터에 저장된 이 앱의 Storage를 지웁니다 (코스 없는 첫 실행 시험)
#   --replay  시험 재생 빌드: 가상 러너로 위치 결정을 시험합니다. 약 10분 뒤 RP_DONE이 찍히면
#             python3 scripts/check_position.py로 결과를 봅니다.
#   --tour    화면 둘러보기 빌드: 정해 둔 코스 위치(TrailConfig.TOUR_M)에 6초씩 머뭅니다.
# 코스 서버는 따로 띄워 둡니다: python3 scripts/course_server.py (끊김 시험 옵션은 --help)
# 로그는 bin/app-sim.log에도 남습니다.
set -e
ROOT=${0:A:h:h}
RESET=0
JUNGLE=monkey.jungle
while [[ $1 == --* ]]; do
  case $1 in
    --reset) RESET=1 ;;
    --replay) JUNGLE=replay.jungle ;;
    --tour) JUNGLE=tour.jungle ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
  shift
done
DEVICE=${1:-fenix847mm}
SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"connectiq-sdk-mac-* | sort -V | tail -1)
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$SDK/bin:$PATH"

KEY="$ROOT/jamtrail_developer_key.der"
[[ -f $KEY ]] || KEY="$HOME/Library/Application Support/Garmin/ConnectIQ/developer_key.der"

mkdir -p "$ROOT/bin"
monkeyc -f "$ROOT/app/$JUNGLE" -d "$DEVICE" -y "$KEY" -o "$ROOT/bin/JAMTRAIL-$DEVICE.prg" -w

if (( RESET )); then
  DATA="${TMPDIR%/}/com.garmin.connectiq/GARMIN/APPS/DATA"
  rm -f "$DATA/JAMTRAIL-${(U)DEVICE}.DAT" "$DATA/JAMTRAIL-${(U)DEVICE}.IDX"
  echo "Storage 초기화: JAMTRAIL-${(U)DEVICE}"
fi

pgrep -f ConnectIQ.app/Contents/MacOS/simulator >/dev/null || { connectiq & sleep 5; }

monkeydo "$ROOT/bin/JAMTRAIL-$DEVICE.prg" "$DEVICE" | tee "$ROOT/bin/app-sim.log"
