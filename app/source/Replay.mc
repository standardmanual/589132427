import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// 시험 재생 (TrailConfig.DEBUG_REPLAY가 true일 때만 씁니다).
// 코스를 따라 가상 러너를 움직이며 위치 입력을 만들어 PositionTracker에 넣고, 실제 위치와 계산한 위치를
// 로그로 남깁니다. scripts/check_position.py가 로그를 읽어 오차와 뒤로 튐, 코스 이탈 판정을 확인합니다.
//
// 시나리오 (차례로 실행)
//   gps      가민 내비게이션 없음. GPS 잡음(축마다 약 3 m 무작위 걸음), 코스 23–26% 구간에서 옆으로 85 m 이탈
//   garmin   가민 코스 총길이가 저장 코스보다 1% 긴 상태로 distanceToDestination 제공 (GPS도 함께)
//   dtdbug   distanceToDestination이 distanceToNextPoint와 같음 (예전 펌웨어 버그) → GPS로 넘어가야 함
//   lenbad   가민 코스 총길이가 저장 코스의 90% (다른 코스를 따라감) → GPS로 넘어가야 함
// 러너 속도는 3 m/s로 보고 시각도 가상으로 흘려, 30초 넘게 이탈했을 때의 전체 탐색까지 확인합니다.
class Replay {
    static const NAMES = ["gps", "garmin", "dtdbug", "lenbad"];
    static const STEP_M = 20.0;
    static const PER_TICK = 4; // 한 번의 compute에 넣는 표본 수 (워치독 한도 안)
    static const SPEED = 3.0;
    static const SHORT_M = 3000.0; // dtdbug, lenbad는 앞부분만

    var geo as CourseGeo;
    var tracker as PositionTracker;
    var scenario as Number = 0;
    var done as Boolean = false;

    var _truth as Float = 0.0;
    var _seed as Number = 12345;
    var _nx as Float = 0.0;
    var _ny as Float = 0.0;
    var _input as PosInput;

    function initialize(g as CourseGeo) {
        geo = g;
        tracker = new PositionTracker(g);
        _input = new PosInput();
        logGeo();
        System.println("RP_START " + NAMES[0]);
    }

    // 좌표 복원 확인용: 몇 점의 절대 좌표를 남깁니다 (Python 복원과 비교).
    function logGeo() as Void {
        var n = geo.course.n;
        var idx = [0, 1, n / 3, (2 * n) / 3, n - 1];
        for (var k = 0; k < idx.size(); k++) {
            var q = geo.pointQ(idx[k]);
            System.println("GEO " + idx[k] + " " + q[0] + " " + q[1]);
        }
    }

    function rand() as Float {
        _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
        return _seed / 2147483648.0;
    }

    function tick() as Void {
        if (done) {
            return;
        }
        var L = tracker.length;
        var name = NAMES[scenario];
        var limit = (scenario >= 2 && SHORT_M < L) ? SHORT_M : L;
        for (var k = 0; k < PER_TICK; k++) {
            if (_truth > limit) {
                nextScenario();
                return;
            }
            makeInput(name, L);
            // 데이터 필드는 스택이 작아 tracker.update는 여기서 부릅니다 (호출 깊이를 줄임).
            tracker.update(_input, (_truth / SPEED * 1000.0).toNumber());
            System.println("RP " + name + " t=" + _truth.format("%.0f") + " d=" + tracker.d.format("%.1f")
                + " src=" + tracker.source + " off=" + (tracker.off ? 1 : 0) + " od=" + tracker.offDist.format("%.1f")
                + " ex=" + (_excursion ? 1 : 0) + " gs=" + tracker.garminState);
            _truth += STEP_M;
        }
    }

    var _excursion as Boolean = false;

    function makeInput(name as String, L as Float) as Void {
        // GPS 잡음과 이탈
        _nx = _nx * 0.85 + (rand() - 0.5) * 6.0;
        _ny = _ny * 0.85 + (rand() - 0.5) * 6.0;
        _excursion = name.equals("gps") && _truth > L * 0.23 && _truth < L * 0.26;
        var lateral = _excursion ? 85.0 : 0.0;
        var p = geo.posAt(_truth / geo.course.interval);
        var gx = p[0] + _nx - p[3] * lateral;
        var gy = p[1] + _ny + p[2] * lateral;
        var inp = _input;
        inp.latQ = gy / geo.ky + geo.course.lat0;
        inp.lonQ = gx / geo.kx + geo.course.lon0;
        inp.elapsedDistance = _truth;
        inp.distanceToDestination = null;
        inp.distanceToNextPoint = null;
        inp.offCourseDistance = null;
        if (!name.equals("gps")) {
            var G = name.equals("lenbad") ? L * 0.9 : L * 1.01;
            var dtd = G * (1.0 - _truth / L) + (rand() - 0.5) * 4.0;
            if (dtd < 1.0) {
                dtd = 1.0;
            }
            inp.distanceToDestination = dtd;
            inp.distanceToNextPoint = name.equals("dtdbug") ? dtd : dtd * 0.3;
            inp.offCourseDistance = 3.0;
        }
    }

    function nextScenario() as Void {
        scenario++;
        if (scenario >= NAMES.size()) {
            done = true;
            System.println("RP_DONE");
            return;
        }
        tracker = new PositionTracker(geo);
        _truth = 0.0;
        _nx = 0.0;
        _ny = 0.0;
        System.println("RP_START " + NAMES[scenario]);
    }
}
