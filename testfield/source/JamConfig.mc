import Toybox.Lang;

// 빌드 전에 이 값만 바꾸면 됩니다.
module JamConfig {
    // 시험 파일 서버 주소. 끝에 / 를 붙입니다.
    // 로컬 시뮬레이터용: scripts/sim-testfield.sh가 pages/ 폴더를 이 주소로 띄웁니다.
    // 시뮬레이터 메뉴 Settings → Use Device HTTPS Requirements를 꺼야 http 응답을 받습니다.
    const BASE_URL = "http://127.0.0.1:8765/";

    // 받아 볼 Base64 텍스트 크기(KB). 서버의 t/b<크기>k.txt 파일과 맞아야 합니다.
    const SIZES_KB = [4, 8, 16, 24, 32, 48];

    // 저장소 총량 시험: 8 KB 값을 최대 몇 개까지 써 볼지 (40개 = 320 KB)
    const FILL_MAX = 40;

    // 응답이 이 시간(ms) 안에 오지 않으면 시간 초과로 기록하고 다음 시험으로 넘어갑니다.
    const TIMEOUT_MS = 60000;
}
