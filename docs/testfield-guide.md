# JAM Trail 시험 필드 사용 안내

본개발 전에 fēnix 8 실기기에서 구조를 결정할 항목을 확인하는 작은 데이터 필드입니다(명세 v3 9장 1단계, 10.1 표).
활동 화면을 열면 시험을 순서대로 한 번 돌리고 결과를 화면과 로그 파일에 남깁니다.

| 위치 | 내용 |
|---|---|
| `testfield/` | 시험 필드 소스 (Monkey C). 앱 이름 "JAM Trail Test" |
| `testfield/source/JamConfig.mc` | 서버 주소, 시험 크기 설정 |
| `pages/t/` | 서버에 올라가는 시험 파일: `ping.txt`, 크기별 Base64 텍스트 `b4k`–`b48k.txt` |
| `.github/workflows/pages.yml` | `pages/` 폴더를 GitHub Pages에 배포 |

> 이 코드는 Garmin 사이트가 막힌 환경에서 작성해 **아직 한 번도 컴파일하지 않았습니다.** 첫 빌드에서 오류가 나면 오류 문구를 그대로 알려 주세요.

---

## 1. 시험 서버 켜기 (한 번만)

1. GitHub에서 저장소 `standardmanual/589132427`의 **Settings → Pages**로 갑니다.
2. **Build and deployment → Source**를 **GitHub Actions**로 바꿉니다.
3. **Actions** 탭 → **Deploy pages** → **Run workflow**를 누릅니다.
4. 1–2분 뒤 폰이나 PC 브라우저에서 아래 주소를 엽니다. `pong`이 보이면 서버 준비가 끝난 것입니다.

```
https://standardmanual.github.io/589132427/t/ping.txt
```

Pages가 꺼져 있을 때 워크플로가 돌면, 배포 단계를 건너뛰고 안내 메시지만 남깁니다.

## 2. 개발 환경 준비 (한 번만, PC)

1. Garmin 개발자 사이트에서 **Connect IQ SDK Manager**를 설치하고, 최신 SDK와 fēnix 8 기기 파일을 내려받습니다.
2. **VS Code**와 **Monkey C** 확장을 설치합니다.
3. VS Code 명령 팔레트에서 **Monkey C: Generate a Developer Key**로 개발자 키를 만듭니다.
   - 키 파일(`.der`)은 저장소 밖에 두세요. 저장소가 공개라서 `.gitignore`로 막아 두었지만, 애초에 저장소 폴더에 두지 않는 편이 안전합니다.

## 3. 빌드

VS Code로 `testfield` 폴더를 열고 명령 팔레트에서 **Monkey C: Build for Device**를 고릅니다.

| 시계 | 기기 선택 |
|---|---|
| fēnix 8 AMOLED 47mm·51mm | `fenix847mm` |
| fēnix 8 AMOLED 43mm | `fenix843mm` |

명령줄로 빌드하려면 이렇게 합니다.

```
monkeyc -d fenix847mm -f testfield/monkey.jungle -o JAMTEST.prg -y <개발자키 경로>/developer_key.der
```

출력 파일 이름은 반드시 `JAMTEST.prg`로 해 주세요. 로그 파일 이름이 이 이름을 따라갑니다.

### 시뮬레이터로 먼저 보기 (선택)
**Monkey C: Run**으로 시뮬레이터에서 띄우면 PC 인터넷으로 요청이 나가서 화면 흐름을 미리 볼 수 있습니다. 메모리와 응답 한도는 실기기와 다르므로 결과 판단은 실기기로 합니다.

## 4. 시계에 설치

1. 시계를 USB로 PC에 연결합니다.
2. `JAMTEST.prg`를 시계의 `GARMIN/APPS/` 폴더에 복사합니다.
3. `GARMIN/APPS/LOGS/` 폴더를 만들고(없으면), 그 안에 빈 파일 `JAMTEST.TXT`를 만듭니다. 이 파일이 있어야 결과가 로그로 남습니다.
4. 시계를 분리합니다.
5. 트레일런 활동 설정 → 데이터 화면 → 새 화면 추가 → 1필드 레이아웃 → Connect IQ 필드 → **JAM Trail Test**를 고릅니다. 메뉴 이름은 펌웨어 언어에 따라 조금 다를 수 있습니다.

## 5. 시험 실행

### 5.1 기본 시험 (필수)
1. 폰을 시계 옆에 두고 블루투스를 켭니다. iPhone이면 **Garmin Connect 앱을 한 번 열어 둡니다**.
2. 시계에서 트레일런 활동을 엽니다. **시작 버튼은 누르지 않습니다.**
3. JAM Trail Test 화면으로 넘깁니다.
4. 맨 위 둘째 줄이 `done`이 될 때까지 기다립니다. 저장소 총량 시험이 1초에 하나씩 쓰기 때문에 1–2분 걸립니다.
5. 화면은 6초마다 다음 페이지로 넘어갑니다. 화면을 탭하면 바로 다음 페이지로 가고 30초 동안 그 페이지에 머뭅니다.
6. 모든 페이지를 사진으로 찍거나, 활동을 저장하지 않고 나온 뒤 `GARMIN/APPS/LOGS/JAMTEST.TXT`를 PC로 가져옵니다.

### 5.2 추가 시험 (가능하면)
| 시험 | 방법 | 보는 것 |
|---|---|---|
| 보존 | 5.1을 마친 뒤 시계를 껐다 켜고 다시 활동을 엽니다 | 첫 줄이 `run#2 prev=N lines`인지 |
| 폰 없음 | 폰 블루투스를 끄고 활동을 엽니다 | `ping`이 `-104` 같은 오류로 끝나고 필드가 멈추지 않는지 |
| 코스 값 | 가민 내비게이션으로 코스를 불러온 뒤 활동을 열고 조금 걷습니다 | 마지막 페이지의 `toDest`, `destName`, `offCourse` 값 |

## 6. 결과 읽는 법

| 결과 줄 | 뜻 | 확인하는 항목 (명세 10.1) |
|---|---|---|
| `start timer=OFF mem 30k/128k` | 시작 전 상태와 메모리. 뒤 숫자가 이 필드가 쓸 수 있는 전체 메모리 | 메모리 한도 |
| `ping 200 len=4 … timer=OFF` | 시작 버튼 전에 웹 요청이 됨. USB 설치로도 됨 | 1번, 2번 |
| `ping -104` | 폰 연결 없음 | 10번 |
| `ping 404` | 서버 주소가 틀렸거나 Pages가 아직 배포되지 않음 | 준비 문제 |
| `ping -1001` | HTTPS 인증서 문제 | 준비 문제 |
| `ping -1002` 또는 `-400` | 서버 응답 형식(text/plain; charset=utf-8)을 받지 못함 | 7번 |
| `b16k 200 len=16384 …` | 16 KB 응답을 받음. 200이 나온 가장 큰 크기가 안전한 응답 한도 | 3번 |
| `b48k -402` / `-403` | 응답이 너무 크거나 메모리 부족. 한도 경계 | 3번 |
| `  store 16k OK` / `FAIL …` | 값 하나로 저장할 수 있는 크기. OK가 나온 가장 큰 크기가 값 한도 | 4번 |
| `  b64 8k -> 6144B +12k` | Base64 복원 성공. 뒤 숫자가 복원 중 늘어난 메모리 | 6번 |
| `bytearray store OK` / `FAIL` | ByteArray를 그대로 저장할 수 있는지 | 5번 |
| `fill stop at 12x8k=96k StorageFull` | 저장소 총량이 대략 96 KB | 4번 |
| `fill 40x8k OK, stopped at 320k` | 320 KB까지 문제없이 저장됨 (더 클 수 있음) | 4번 |
| `peak mem 70k/128k` | 시험 중 가장 많이 쓴 메모리 | 메모리 여유 |
| 맨 위 `tap N` 숫자가 늘어남 | 데이터 필드가 탭을 받음 | 8번 |
| 마지막 페이지 노란 줄 `한글: 오르막 끝 25%` | 한글이 제대로 보이는지, 네모나 빈칸으로 나오는지 | 13번 (한글 표시) |
| 마지막 페이지 `toDest`, `destName` | 코스를 따라갈 때 남은 거리와 목적지 이름 | 9번 |

결과 사진이나 로그 파일을 보내 주시면, 그에 맞춰 조각 크기와 저장 방식을 확정하고 본 앱 개발로 넘어갑니다.
