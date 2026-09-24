import Toybox.Lang;

module TrailConfig {
    // 코스 서버 주소. 끝에 / 를 붙입니다. 빌드 설정(jungle)으로 고릅니다.
    //   실기기·스토어 (monkey.jungle): 이 저장소의 GitHub Pages. pages.yml이 gpx/의 GPX를 변환해 배포합니다.
    //   시뮬레이터 (sim·replay·tour.jungle): scripts/course_server.py가 pages/ 폴더를 띄우는 로컬 주소.
    //     시뮬레이터 메뉴 Settings → Use Device HTTPS Requirements를 꺼야 http 응답을 받습니다.
    (:pages_server) const BASE_URL = "https://standardmanual.github.io/589132427/";
    (:local_server) const BASE_URL = "http://127.0.0.1:8765/";

    // 요청 하나당 최대 시도 횟수와 재시도 간격 (명세 7.2)
    const MAX_TRIES = 3;
    const RETRY_MS = 5000;
    // 응답이 이 시간 안에 오지 않으면 실패로 봅니다.
    const TIMEOUT_MS = 60000;
    // 완료·오류 문구를 보여 주는 시간 (명세 4.3)
    const MESSAGE_MS = 5000;

    // 위치 결정 (명세 7.5)
    const OFF_COURSE_M = 50.0;             // 코스 이탈 임계값 (설정 s_off, 8단계에서 메뉴로)
    const LOST_FULL_SEARCH_MS = 30000;     // 이만큼 이탈해 있으면 다음 매칭은 코스 전체 탐색
    const WIN_BACK_M = 200.0;              // GPS 창 탐색 범위: 직전 위치 뒤
    const WIN_FWD_M = 1000.0;              //                   직전 위치 앞
    // 창 안의 후보가 직전 위치에서 너무 멀면(뒤로 BACK_FREE_M, 앞으로 달릴 수 있는 거리 넘게) 넘은 거리 ×
    // JUMP_PENALTY만큼 멀게 칩니다. 왕복 구간에서 가는 길과 되돌아오는 길(몇 m 차이)이 나란할 때
    // 다른 쪽 길로 튀지 않게 합니다. 앞으로 달릴 수 있는 거리 = FWD_FREE_M + MAX_SPEED × 직전 매칭 뒤 시간.
    const BACK_FREE_M = 20.0;
    const FWD_FREE_M = 50.0;
    const MAX_SPEED = 6.0;       // m/s
    const JUMP_PENALTY = 0.2;
    // 모든 후보에 직전 위치에서 떨어진 거리 × ALONG_WEIGHT를 더합니다. 반환점처럼 두 길이 몇 m 안에서
    // 나란해 거리만으로 구분이 안 될 때 직전 위치에 가까운 쪽을 고르게 합니다.
    const ALONG_WEIGHT = 0.05;

    // 시험용 로그 (메모리 최고치, 계산 시간, 설정 반영). 실기기 빌드에서는 끕니다.
    (:log_off) const DEBUG_LOG = false;
    (:log_on) const DEBUG_LOG = true;
    // 시험 재생: 실제 활동 값 대신 가상 러너로 위치 결정을 시험합니다 (scripts/check_position.py).
    // 빌드 설정으로 고릅니다: 기본(monkey.jungle)은 끄고, scripts/sim-app.sh --replay(replay.jungle)는 켭니다.
    (:replay_off) const DEBUG_REPLAY = false;
    (:replay_on) const DEBUG_REPLAY = true;
    // 화면 둘러보기: 정해 둔 코스 위치(TOUR_M)에 6초씩 머뭅니다. 프로토타입과 화면을 나란히 비교할 때 씁니다
    // (tour.jungle, scripts/sim-app.sh --tour). 샘플 코스 기준 위치입니다.
    (:tour_off) const DEBUG_TOUR = false;
    (:tour_on) const DEBUG_TOUR = true;
    const TOUR_M = [800.0, 2500.0, 5600.0, 7500.0, 9800.0, 12200.0, 13400.0, 17000.0, 19400.0, 21200.0];
    const TOUR_HOLD = 6;
    const TOUR_WIDTHS = [2000, 10000, 0]; // 한 바퀴마다 가로 범위를 바꿉니다 (0은 구간 맞춤)
}
