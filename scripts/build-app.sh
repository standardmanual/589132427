#!/bin/zsh
# 실기기·스토어용 JAM Trail 패키지(bin/JAMTRAIL.iq)를 만듭니다 (monkey.jungle: GitHub Pages 서버, 시험 로그 끔).
# .iq는 압축을 풀지 말고 그대로 apps-developer.garmin.com에 올립니다.
# 스토어 앱은 처음 올린 개발자 키로만 업데이트할 수 있으므로 항상 같은 키(jamtrail_developer_key.der)를 씁니다.
set -e
ROOT=${0:A:h:h}
SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/"connectiq-sdk-mac-* | sort -V | tail -1)
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$SDK/bin:$PATH"
KEY="$ROOT/jamtrail_developer_key.der"
[[ -f $KEY ]] || { echo "개발자 키가 없습니다: $KEY" >&2; exit 1; }
mkdir -p "$ROOT/bin"
for d in fenix843mm fenix847mm; do
  monkeyc -f "$ROOT/app/monkey.jungle" -d "$d" -y "$KEY" -o "$ROOT/bin/JAMTRAIL-release-$d.prg" -r -w
done
monkeyc -e -r -f "$ROOT/app/monkey.jungle" -y "$KEY" -o "$ROOT/bin/JAMTRAIL.iq" -w
ls -la "$ROOT/bin/JAMTRAIL.iq"
