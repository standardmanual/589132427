import Toybox.Application;
import Toybox.Lang;

// 시계 안 설정 (명세 5장). 값은 Application.Storage에 저장하고, 폰 설정(Properties)에는 기대지 않습니다.
// 설정 화면(SettingsMenu)이 데이터 필드와 같은 앱 인스턴스에서 돈다는 보장이 없어(시뮬레이터에서는 설정 화면이
// 열린 동안 데이터 필드가 멈춤), 변경 번호와 목록 새로고침 요청도 Storage에 둡니다. 데이터 필드는 compute()마다
// 변경 번호(s_ver)를 읽어 바뀌었으면 반영합니다.
module Settings {
    // 저장 키 (명세 5.2)
    const EXAG = "s_exag";
    const WIDTH = "s_width";
    const GWIN = "s_gwin";
    const OFF = "s_off";
    const COLOR = "s_color";
    const DIAG = "s_diag";     // 진단 표시: 실기기 시험용 (마지막 줄에 위치 출처, 가민 남은 거리, 메모리)
    const COURSE = "s_course"; // "" 이면 서버 현재 코스 따르기, 아니면 코스 ID

    const KEYS = [EXAG, WIDTH, GWIN, OFF, COLOR, DIAG];
    const NAMES = ["세로 배율", "그래프 가로 범위", "현재 경사 평균 구간", "코스 이탈 임계값", "경사 색상", "진단 표시"];
    const VALUES = [
        [2, 3, 4],
        [500, 1000, 2000, 5000, 10000, 0],
        [100, 200, 400],
        [30, 50, 100],
        [1, 0],
        [0, 1]
    ];
    const LABELS = [
        ["2×", "3×", "4×"],
        ["500 m", "1 km", "2 km", "5 km", "10 km", "구간 맞춤"],
        ["100 m", "200 m", "400 m"],
        ["30 m", "50 m", "100 m"],
        ["켬", "끔"],
        ["끔", "켬"]
    ];
    const DEFAULTS = [3, 2000, 100, 50, 1, 0];

    const VER = "s_ver";          // 설정이 바뀔 때마다 1씩 오르는 변경 번호
    const REFRESH = "s_refresh";  // 1이면 코스 목록 새로고침 요청

    function indexOf(key as String) as Number {
        for (var i = 0; i < KEYS.size(); i++) {
            if (KEYS[i].equals(key)) {
                return i;
            }
        }
        return -1;
    }

    // 저장된 값. 없거나 선택지에 없는 값이면 기본값
    function get(key as String) as Number {
        var k = indexOf(key);
        var v = CourseStore.get(key);
        if (v instanceof Number && (VALUES[k] as Array).indexOf(v) >= 0) {
            return v as Number;
        }
        return DEFAULTS[k];
    }

    function set(key as String, value as Number) as Void {
        CourseStore.put(key, value);
        bump();
    }

    function version() as Number {
        var v = CourseStore.get(VER);
        return (v instanceof Number) ? v as Number : 0;
    }

    function bump() as Void {
        CourseStore.put(VER, version() + 1);
    }

    function refreshRequested() as Boolean {
        return CourseStore.get(REFRESH) == 1;
    }

    function setRefresh(on as Boolean) as Void {
        CourseStore.put(REFRESH, on ? 1 : 0);
    }

    function label(key as String) as String {
        var k = indexOf(key);
        var i = (VALUES[k] as Array).indexOf(get(key));
        return (LABELS[k] as Array<String>)[i];
    }

    // 코스 선택: null이면 서버 현재 코스 따르기
    function course() as String? {
        var v = CourseStore.getString(COURSE);
        return (v == null || v.length() == 0) ? null : v;
    }

    function setCourse(id as String?) as Void {
        CourseStore.put(COURSE, id == null ? "" : id);
        bump();
    }
}
