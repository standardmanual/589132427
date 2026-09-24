import Toybox.Lang;

module TrailConfig {
    // 코스 서버 주소. 끝에 / 를 붙입니다.
    // 로컬 시뮬레이터용: scripts/sim-app.sh가 pages/ 폴더를 이 주소로 띄웁니다.
    // 시뮬레이터 메뉴 Settings → Use Device HTTPS Requirements를 꺼야 http 응답을 받습니다.
    const BASE_URL = "http://127.0.0.1:8765/";

    // 요청 하나당 최대 시도 횟수와 재시도 간격 (명세 7.2)
    const MAX_TRIES = 3;
    const RETRY_MS = 5000;
    // 응답이 이 시간 안에 오지 않으면 실패로 봅니다.
    const TIMEOUT_MS = 60000;
    // 완료·오류 문구를 보여 주는 시간 (명세 4.3)
    const MESSAGE_MS = 5000;

    // 시험용 로그: 그래프 열 값(scripts/check_profile.py)과 메모리 최고치
    const DEBUG_LOG = true;
}
