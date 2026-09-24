import Toybox.Activity;
import Toybox.Lang;
import Toybox.Position;

// 위치 결정에 쓰는 입력. Activity.Info에서 채우거나(fromInfo), 시험 재생(Replay)이 만듭니다.
class PosInput {
    var distanceToDestination as Float? = null;
    var distanceToNextPoint as Float? = null;
    var offCourseDistance as Float? = null;
    var latQ as Float? = null; // GPS 위도·경도, 1e-5° 단위
    var lonQ as Float? = null;
    var elapsedDistance as Float? = null;

    function initialize() {
    }

    function fromInfo(info as Activity.Info) as PosInput {
        distanceToDestination = toF(info.distanceToDestination);
        distanceToNextPoint = toF(info.distanceToNextPoint);
        offCourseDistance = toF(info.offCourseDistance);
        elapsedDistance = toF(info.elapsedDistance);
        latQ = null;
        lonQ = null;
        var loc = info.currentLocation;
        if (loc != null) {
            var deg = loc.toDegrees();
            latQ = (deg[0] * 1.0e5).toFloat();
            lonQ = (deg[1] * 1.0e5).toFloat();
        }
        return self;
    }

    static function toF(v as Numeric?) as Float? {
        return v == null ? null : v.toFloat();
    }
}

// 코스 위치 결정 (명세 7.5). 결과는 코스 위치 d(m)와 출처, 코스 이탈 여부입니다.
//   1순위 가민 코스 내비게이션: d = L × (1 − distanceToDestination / 가민 코스 총길이)
//         가민 코스 총길이는 지금까지 본 가장 큰 distanceToDestination. 이 값이 저장된 코스 길이와
//         ±2% 안이고 distanceToNextPoint와 다를 때만 씁니다(예전 펌웨어 버그 대비).
//   2순위 GPS 좌표 매칭: 직전 위치 기준 −200 m ~ +1 km 창에서 가장 가까운 선분.
//         처음이거나 30초 넘게 코스를 벗어나 있었으면 코스 전체 탐색.
//   3순위 누적 거리: elapsedDistance (출발점이 코스 시작이라고 가정)
class PositionTracker {
    static const SRC_NONE = 0;
    static const SRC_GARMIN = 1;
    static const SRC_GPS = 2;
    static const SRC_DIST = 3;

    var geo as CourseGeo;
    var length as Float;

    var d as Float = 0.0;          // 코스 위치 (m)
    var source as Number = 0;
    var off as Boolean = false;     // 코스 이탈
    var offDist as Float = 0.0;     // 코스까지 거리 (m)
    var known as Boolean = false;   // 위치를 한 번이라도 정했는지

    var _idx as Float = -1.0;       // GPS 매칭 소수 인덱스
    var _offSince as Number = -1;   // 코스를 벗어나기 시작한 시각 (ms)
    var _matchedAt as Number = 0;   // 마지막으로 코스에 붙은 시각 (ms)
    var _garminMax as Float = 0.0;
    var garminState as String = "-"; // 시험 로그용: 가민 축을 쓰지 않은 이유
    var offThreshold as Float = TrailConfig.OFF_COURSE_M; // 코스 이탈 임계값 (설정 s_off)

    function initialize(g as CourseGeo) {
        geo = g;
        length = g.course.lengthM().toFloat();
    }

    function update(p as PosInput, now as Number) as Void {
        if (useGarmin(p, now)) {
            return;
        }
        if (useGps(p, now)) {
            return;
        }
        var ed = p.elapsedDistance;
        if (ed != null) {
            d = clampD(ed);
            source = SRC_DIST;
            off = false;
            known = true;
        }
    }

    function useGarmin(p as PosInput, now as Number) as Boolean {
        var dtd = p.distanceToDestination;
        if (dtd == null || dtd <= 0.0) {
            garminState = "none";
            return false;
        }
        if (dtd > _garminMax) {
            _garminMax = dtd;
        }
        var dtn = p.distanceToNextPoint;
        if (dtn != null && (dtd - dtn).abs() < 0.5) {
            garminState = "dtd=dtn";
            return false;
        }
        if ((_garminMax - length).abs() > length * 0.02) {
            garminState = "len " + _garminMax.format("%.0f");
            return false;
        }
        garminState = "ok";
        d = clampD(length * (1.0 - dtd / _garminMax));
        source = SRC_GARMIN;
        known = true;
        var oc = p.offCourseDistance;
        offDist = oc == null ? 0.0 : oc;
        off = offDist > offThreshold;
        _idx = d / geo.course.interval; // GPS로 넘어가도 창 탐색을 이어 가도록
        _offSince = -1;
        _matchedAt = now;
        return true;
    }

    function useGps(p as PosInput, now as Number) as Boolean {
        var la = p.latQ;
        var lo = p.lonQ;
        if (la == null || lo == null || !geo.ready) {
            return false;
        }
        var px = geo.toX(lo);
        var py = geo.toY(la);
        var I = geo.course.interval;
        var lost = _offSince >= 0 && now - _offSince > TrailConfig.LOST_FULL_SEARCH_MS;
        var r;
        if (_idx < 0.0 || lost) {
            r = geo.fullSearch(px, py);
        } else {
            var from = (_idx - TrailConfig.WIN_BACK_M / I).toNumber();
            var to = (_idx + TrailConfig.WIN_FWD_M / I).toNumber() + 1;
            var fwdFree = TrailConfig.FWD_FREE_M + TrailConfig.MAX_SPEED * (now - _matchedAt) / 1000.0;
            r = geo.nearest(px, py, from, to, _idx, fwdFree.toFloat());
        }
        offDist = r[1];
        source = SRC_GPS;
        known = true;
        if (offDist > offThreshold) {
            // 코스 이탈: 마지막 매칭 위치를 유지합니다.
            off = true;
            if (_offSince < 0) {
                _offSince = now;
            }
            if (_idx < 0.0) {
                _idx = r[0];
            }
        } else {
            off = false;
            _offSince = -1;
            _idx = r[0];
            _matchedAt = now;
        }
        d = clampD(_idx * I);
        return true;
    }

    function clampD(v as Float) as Float {
        return v < 0.0 ? 0.0 : v > length ? length : v;
    }

    function sourceName() as String {
        return source == SRC_GARMIN ? "가민" : source == SRC_GPS ? "GPS" : source == SRC_DIST ? "거리" : "-";
    }
}
