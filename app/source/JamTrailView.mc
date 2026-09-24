import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// JAM Trail 데이터 필드.
//   코스 받기·저장·복원과 상태 표시 (명세 4.3, 7.2–7.4)
//   위치 결정 (명세 7.5, PositionTracker). 시험 재생 빌드에서는 가상 러너(Replay)
//   화면 모드 결정 (명세 7.6): 새 구간으로 30 m 들어간 뒤 전환, 두 구간 이상 건너뛰면 즉시
//   워치 화면 (명세 4장, WatchScreen)
//   시계 안 설정 (명세 5장, Settings·SettingsMenu): 바뀌면 다음 compute()에서 반영
class JamTrailView extends WatchUi.DataField {
    const HYST_M = 30.0;

    var _sync as CourseSync;
    var _course as TrailCourse? = null;
    var _geo as CourseGeo? = null;
    var _tracker as PositionTracker? = null;
    var _replay as Replay? = null;
    var _input as PosInput = new PosInput();
    var _screen as WatchScreen? = null;
    var _dispSeg as Number = -1;
    var _started as Boolean = false;
    var _peakMem as Number = 0;
    var _appliedVersion as Number = -1;
    var _appliedCourse as String? = null;
    var _indexing as Boolean = false;
    var _released as Boolean = false;
    var _indexTried as Boolean = false;
    var _tourTick as Number = 0;
    var _tourWidth as Number = -1;
    var _maxDrawMs as Number = 0;
    var _maxPrepMs as Number = 0;

    function initialize() {
        DataField.initialize();
        _sync = new CourseSync();
    }

    function compute(info as Activity.Info) as Void {
        var now = System.getTimer();
        if (!_started) {
            _started = true;
            // 같은 앱 ID로 먼저 설치했던 시험 필드가 남긴 값을 지웁니다.
            CourseStore.remove("jt_runs");
            CourseStore.remove("jt_last");
            // 폰 없이도 저장된 코스로 바로 그립니다.
            var active = CourseStore.getString(CourseStore.K_ACTIVE);
            if (active != null) {
                _course = CourseStore.loadCourse(active, false);
                System.println(_course != null
                    ? "loaded stored course " + active + " (" + (_course as TrailCourse).size + " B) mem " + (System.getSystemStats().usedMemory / 1024) + "k"
                    : "stored course " + active + " could not be loaded");
            } else {
                System.println("no stored course");
            }
            _appliedCourse = Settings.course();
            _sync.start(_appliedCourse);
        }
        applySettings();
        if (_sync.needsRoom()) {
            releaseCourse();
            _sync.roomGiven = true;
        }
        _sync.tick(now);
        updateIndex();
        var c = _sync.takeLoaded();
        if (c == null && _course == null && _released && _sync.isIdle()) {
            // 새 코스를 불러오지 못함(검증 실패 등): 내려놓았던 활성 코스를 다시 불러옵니다.
            _released = false;
            var active = CourseStore.getString(CourseStore.K_ACTIVE);
            if (active != null) {
                c = CourseStore.loadCourse(active, false);
                System.println("reloaded active course " + active + (c != null ? "" : " FAILED"));
            }
        }
        if (c != null) {
            _released = false;
            _course = c;
            _geo = null;
            _dispSeg = -1;
            if (_screen != null) {
                (_screen as WatchScreen).ready = false;
            }
        }
        updatePosition(info, now);
        prepareScreen();
        trackMemory("compute");
    }

    // 새 코스를 불러오기 전에 지금 코스와 거기 딸린 좌표 표·화면 계산을 내려놓습니다 (CourseSync.needsRoom).
    // 그동안 화면은 가운데에 받는 중 문구만 보여 줍니다.
    function releaseCourse() as Void {
        if (_course != null) {
            _released = true;
        }
        _course = null;
        _geo = null;
        _tracker = null;
        _replay = null;
        _dispSeg = -1;
        if (_screen != null) {
            (_screen as WatchScreen).ready = false;
        }
        if (TrailConfig.DEBUG_LOG) {
            System.println("released course for loading, mem " + (System.getSystemStats().usedMemory / 1024) + "k");
        }
    }

    // 설정이 바뀌었으면 화면·위치 판정·코스 선택에 반영합니다.
    function applySettings() as Void {
        var ver = Settings.version();
        if (ver == _appliedVersion) {
            return;
        }
        _appliedVersion = ver;
        var screen = _screen;
        if (screen != null) {
            screen.exag = Settings.get(Settings.EXAG);
            screen.widthM = Settings.get(Settings.WIDTH);
            screen.gradeWin = Settings.get(Settings.GWIN).toFloat();
            screen.colorOn = Settings.get(Settings.COLOR) == 1;
        }
        var t = _tracker;
        if (t != null) {
            t.offThreshold = Settings.get(Settings.OFF).toFloat();
        }
        var c = Settings.course();
        if ((c == null) != (_appliedCourse == null) || (c != null && !c.equals(_appliedCourse))) {
            _appliedCourse = c;
            _sync.start(c); // 고른 코스(또는 서버 현재 코스)로 다시 맞춥니다
        }
        if (TrailConfig.DEBUG_LOG) {
            System.println("settings v" + _appliedVersion + ": exag " + Settings.get(Settings.EXAG) + ", width " + Settings.get(Settings.WIDTH)
                + ", gwin " + Settings.get(Settings.GWIN) + ", off " + Settings.get(Settings.OFF) + ", color " + Settings.get(Settings.COLOR)
                + ", course " + c);
        }
    }

    // 코스 목록(index.txt): 메뉴에서 새로고침을 누르면, 또는 한 번도 받은 적이 없으면 코스 받기가 끝난 뒤 받습니다.
    function updateIndex() as Void {
        if (_indexing) {
            if (_sync.isIdle()) {
                _indexing = false;
                Settings.setRefresh(false);
            }
            return;
        }
        if (!_sync.isIdle()) {
            return;
        }
        var want = Settings.refreshRequested() || (!_indexTried && CourseStore.get(CourseIndex.KEY) == null);
        if (want) {
            _indexTried = true;
            _indexing = true;
            _sync.fetchIndex();
        }
    }

    // 화면 계산은 compute에서 합니다 (명세 7.7). 화면 크기는 첫 onUpdate에서 알게 됩니다.
    function prepareScreen() as Void {
        var screen = _screen;
        var course = _course;
        if (screen == null || course == null) {
            return;
        }
        if (_tourWidth >= 0) {
            screen.widthM = _tourWidth;
        }
        var t = _tracker;
        var known = t != null && t.known;
        var t0 = System.getTimer();
        screen.prepare(course, known ? (t as PositionTracker).d : 0.0, _dispSeg >= 0 ? _dispSeg : 0, known,
            known && (t as PositionTracker).off, known ? (t as PositionTracker).offDist : 0.0);
        var ms = System.getTimer() - t0;
        if (TrailConfig.DEBUG_LOG && ms > _maxPrepMs) {
            _maxPrepMs = ms;
            System.println("prepare max " + ms + " ms (w=" + screen.widthM + ")");
        }
    }

    function updatePosition(info as Activity.Info, now as Number) as Void {
        var course = _course;
        if (course == null) {
            return;
        }
        var geo = _geo;
        if (geo == null) {
            geo = new CourseGeo(course);
            _geo = geo;
            _tracker = new PositionTracker(geo);
            (_tracker as PositionTracker).offThreshold = Settings.get(Settings.OFF).toFloat();
            _replay = null;
        }
        if (!geo.ready) {
            if (!geo.buildStep()) {
                return; // 체크포인트 표를 만드는 중 (100 km 코스는 5번에 나눠 만듦)
            }
            if (TrailConfig.DEBUG_LOG) {
                System.println("geo ready (" + course.n + " points) mem " + (System.getSystemStats().usedMemory / 1024) + "k");
            }
        }
        if (TrailConfig.DEBUG_TOUR) {
            // 정해 둔 위치에 6초씩 머뭅니다. 위치가 바뀔 때는 모드를 바로 바꿉니다.
            var tt = _tracker as PositionTracker;
            var k = (_tourTick / TrailConfig.TOUR_HOLD) % TrailConfig.TOUR_M.size();
            if (_tourTick % TrailConfig.TOUR_HOLD == 0) {
                tt.d = TrailConfig.TOUR_M[k] < tt.length ? TrailConfig.TOUR_M[k] : tt.length;
                tt.known = true;
                _dispSeg = -1;
                var pass = _tourTick / TrailConfig.TOUR_HOLD / TrailConfig.TOUR_M.size();
                _tourWidth = TrailConfig.TOUR_WIDTHS[pass % TrailConfig.TOUR_WIDTHS.size()];
                System.println("POSE " + k + " d=" + tt.d.format("%.0f") + " w=" + _tourWidth);
            }
            _tourTick++;
        } else if (TrailConfig.DEBUG_REPLAY) {
            if (_replay == null) {
                _replay = new Replay(geo);
            }
            var r = _replay as Replay;
            var before = r.tracker;
            r.tick();
            if (r.tracker != before) {
                _dispSeg = -1; // 새 시나리오
            }
            _tracker = r.tracker;
        } else {
            (_tracker as PositionTracker).update(_input.fromInfo(info), now);
        }
        var t = _tracker as PositionTracker;
        if (t.known) {
            updateMode(course, t.d / course.interval);
        }
    }

    // 화면 모드 구간 (명세 7.6, 프로토타입 updateDisp)
    function updateMode(c as TrailCourse, idx as Float) as Void {
        var seg = c.segOf(idx);
        if (_dispSeg < 0 || (seg - _dispSeg).abs() > 1) {
            _dispSeg = seg;
        } else if (seg != _dispSeg) {
            var into = seg > _dispSeg ? (idx - c.segStart(seg)) * c.interval : (c.segEnd(seg) - idx) * c.interval;
            if (into < HYST_M) {
                return;
            }
            _dispSeg = seg;
        } else {
            return;
        }
        if (TrailConfig.DEBUG_REPLAY) {
            System.println("MODE seg=" + _dispSeg + " type=" + c.segType(_dispSeg) + " d=" + (idx * c.interval).format("%.1f"));
        }
    }

    // 메모리 최고치가 1 KB 넘게 오를 때마다 기록합니다.
    function trackMemory(where as String) as Void {
        var used = System.getSystemStats().usedMemory;
        if (used > _peakMem + 1024) {
            _peakMem = used;
            if (TrailConfig.DEBUG_LOG) {
                System.println("mem peak " + (used / 1024) + "k/" + (System.getSystemStats().totalMemory / 1024) + "k at " + where);
            }
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var s = dc.getWidth();
        var now = System.getTimer();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var screen = _screen;
        if (screen == null || screen.s != s) {
            screen = new WatchScreen(s);
            _screen = screen;
            _appliedVersion = -1; // 새 화면에 설정 적용
            applySettings();
        }

        var course = _course;
        if (course == null) {
            if (_sync.isDownloading()) {
                center(dc, screen, "코스 받는 중 " + _sync.progressText(), null);
            } else if (_sync.isChecking()) {
                center(dc, screen, "코스 확인 중", null);
            } else {
                center(dc, screen, "코스 없음", "폰 연결 후 활동을 다시 여세요");
            }
            var err = _sync.message(now);
            if (err != null) {
                screen.statusLine(dc, err, _sync.messageTail(), WatchScreen.WARN);
            }
            return;
        }

        if (!screen.ready) {
            prepareScreen(); // 첫 화면: 아직 compute가 계산하지 못함
        }
        var status = null;
        var tail = "";
        if (_sync.isDownloading()) {
            status = "새 코스 받는 중 " + _sync.progressText();
        } else {
            status = _sync.message(now);
            if (status != null) {
                tail = _sync.messageTail();
            }
        }
        if (status == null && Settings.get(Settings.DIAG) == 1) {
            status = diagLine();
        }
        var t0 = System.getTimer();
        screen.draw(dc, status, tail);
        var ms = System.getTimer() - t0;
        if (TrailConfig.DEBUG_LOG && ms > _maxDrawMs) {
            _maxDrawMs = ms;
            System.println("draw max " + ms + " ms (w=" + screen.widthM + ")");
        }
        trackMemory("draw");
    }

    // 진단 표시 (설정 "진단 표시" 켬): 마지막 줄에 위치 출처와 코스 위치, 가민 남은 거리와 목적지 이름,
    // 가민 축을 쓰지 않은 이유, 남은 메모리. 실기기에서는 로그를 볼 수 없어 사진으로 확인합니다.
    function diagLine() as String {
        var t = _tracker;
        var free = (System.getSystemStats().freeMemory / 1024) + "K";
        if (t == null) {
            return "위치 없음 · " + free;
        }
        var dtd = t.lastDtd;
        var line = t.sourceName() + " " + (t.d / 1000.0).format("%.2f") + " · dtd " + (dtd == null ? "-" : dtd.format("%.0f"));
        var gs = t.garminState;
        if (!gs.equals("ok") && !gs.equals("none") && !gs.equals("-")) {
            line += " (" + gs + ")";
        }
        var dest = t.lastDest;
        if (dest != null) {
            line += " · " + dest;
        }
        return line + " · " + free;
    }

    // 코스가 없을 때 가운데 문구 (명세 4.3)
    function center(dc as Graphics.Dc, screen as WatchScreen, line1 as String, line2 as String?) as Void {
        var s = screen.s;
        var f1 = screen.fonts.kr(0.06 * s);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        screen.text(dc, s / 2, (0.5 * s).toNumber(), f1, line1, Graphics.TEXT_JUSTIFY_CENTER);
        if (line2 != null) {
            var f2 = screen.fonts.kr(0.04 * s);
            dc.setColor(0x9a9a9a, Graphics.COLOR_TRANSPARENT);
            screen.wrapped(dc, s / 2, (0.58 * s).toNumber(), f2, line2, (0.80 * s).toNumber());
        }
    }
}
