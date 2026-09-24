import Toybox.Lang;

// 빌드 전에 이 값만 바꾸면 됩니다.
module JamConfig {
    // 시험 파일을 올린 GitHub Pages 주소. 끝에 / 를 붙입니다.
    // 이 저장소(standardmanual/589132427)의 pages/ 폴더가 여기에 배포됩니다.
    // 시뮬레이터에서는 scripts/sim-testfield.sh가 복사본을 로컬 서버 주소로 바꿔 빌드합니다.
    const BASE_URL = "https://standardmanual.github.io/589132427/";

    // 받아 볼 Base64 텍스트 크기(KB). 서버의 t/b<크기>k.txt 파일과 맞아야 합니다.
    const SIZES_KB = [4, 8, 16, 24, 32, 48];

    // 저장소 총량 시험: 8 KB 값을 최대 몇 개까지 써 볼지 (40개 = 320 KB)
    const FILL_MAX = 40;

    // 응답이 이 시간(ms) 안에 오지 않으면 시간 초과로 기록하고 다음 시험으로 넘어갑니다.
    const TIMEOUT_MS = 60000;
}
