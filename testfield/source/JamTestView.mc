import Toybox.Activity;
import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// JAM Trail 시험 필드
//
// 활동 화면이 열리면 아래 시험을 순서대로 한 번 실행하고 결과를 화면과 로그에 남깁니다.
//   1. ping: 첫 웹 요청이 되는가, 그때 타이머 상태는 무엇인가 (시작 버튼 전 요청 가능 여부)
//   2. b4k … b48k: text/plain 응답을 크기별로 받는다 (응답 한도 -402/-403 경계)
//      받은 값마다 Storage에 한 번 써 본다 (값 하나의 크기 한도)
//      8 KB와 32 KB는 Base64 → ByteArray 복원도 해 본다 (복원 가능 여부와 메모리 증가)
//   3. ByteArray를 Storage에 쓸 수 있는가
//   4. 8 KB 값을 가득 찰 때까지 써서 Storage 총량을 잰다 (1초에 하나씩, 끝나면 모두 지움)
//   5. 결과를 Storage에 저장한다 (다음 실행에서 남아 있는지로 보존 여부 확인)
// 마지막 페이지에는 가민 코스 내비게이션 값과 한글 표시 시험을 계속 보여 줍니다.
//
// 웹 요청은 한 번에 하나만 보내고, 다음 요청은 콜백이 아니라 compute()에서 시작합니다.
// (데이터 필드에서는 Timer를 쓸 수 없고, 콜백 안에서 바로 다음 요청을 보내면
//  즉시 실패하는 경우 콜백이 연쇄로 불려 스택이 넘칠 수 있습니다.)

class JamTestView extends WatchUi.DataField {
    // 단계: 0 ping, 1..N 크기 시험, N+1 ByteArray, N+2 총량, N+3 마무리, N+4 완료
    var _step as Number = 0;
    var _waiting as Boolean = false;
    var _waitSince as Number = 0;
    var _curLabel as String = "";
    var _reqTimer as String = "";
    var _reqId as Number = 0;

    var _started as Boolean = false;
    var _runNo as Number = 0;
    var _lines as Array<String> = [];
    var _navLines as Array<String> = [];

    var _fillData as String? = null;
    var _fillIdx as Number = 0;

    var _peakUsed as Number = 0;
    var _totalMem as Number = 0;

    var _memo as String = "?";

    var _tapCount as Number = 0;
    var _page as Number = 0;
    var _lockUntil as Number = 0;

    function initialize() {
        DataField.initialize();
    }

    // ---------------------------------------------------------------- compute

    function compute(info as Activity.Info) as Void {
        trackMemory();
        if (!_started) {
            _started = true;
            onFirstCompute(info);
        }
        updateNav(info);

        if (_waiting) {
            if (System.getTimer() - _waitSince > JamConfig.TIMEOUT_MS) {
                addLine(_curLabel + " TIMEOUT");
                _waiting = false;
                _step++;
            }
            return;
        }
        runStep();
    }

    // 폰(Connect IQ 앱) 설정에서 바꾼 값을 읽습니다. 베타 앱에서 폰 설정이 되는지 확인용.
    function loadSettings() as Void {
        try {
            var v = Application.Properties.getValue("memo");
            _memo = (v == null) ? "null" : v.toString();
        } catch (e) {
            _memo = "ERR " + errName(e);
        }
    }

    function onFirstCompute(info as Activity.Info) as Void {
        loadSettings();
        // 실행 횟수와 이전 결과 확인 (보존 시험)
        var prevCount = -1;
        try {
            var runs = Application.Storage.getValue("jt_runs");
            _runNo = (runs instanceof Number) ? (runs as Number) + 1 : 1;
            Application.Storage.setValue("jt_runs", _runNo);
            var prev = Application.Storage.getValue("jt_last");
            if (prev instanceof Array) {
                prevCount = (prev as Array).size();
            }
        } catch (e) {
            addLine("storage read FAIL " + e.getErrorMessage());
        }
        // 지난번 총량 시험이 중간에 끊겼을 때 남은 값 정리
        cleanupFill(JamConfig.FILL_MAX);

        var stats = System.getSystemStats();
        _totalMem = stats.totalMemory;
        addLine("run#" + _runNo + " prev=" + (prevCount < 0 ? "none" : prevCount.toString() + " lines"));
        addLine("start timer=" + timerName(info.timerState) + " mem " + kb(stats.usedMemory) + "/" + kb(_totalMem));
    }

    function runStep() as Void {
        var sizes = JamConfig.SIZES_KB;
        var n = sizes.size();
        if (_step == 0) {
            startRequest("ping", "t/ping.txt", { "t" => Time.now().value() });
        } else if (_step <= n) {
            var k = sizes[_step - 1];
            startRequest("b" + k + "k", "t/b" + k + "k.txt", null);
        } else if (_step == n + 1) {
            testByteArray();
            _step++;
        } else if (_step == n + 2) {
            fillStep();
        } else if (_step == n + 3) {
            finish();
            _step++;
        }
    }

    // ------------------------------------------------------------ web request

    function startRequest(label as String, path as String, params as Dictionary?) as Void {
        _curLabel = label;
        _reqId++;
        _reqTimer = timerNow();
        _waiting = true;
        _waitSince = System.getTimer();
        try {
            Communications.makeWebRequest(
                JamConfig.BASE_URL + path,
                params,
                {
                    :method => Communications.HTTP_REQUEST_METHOD_GET,
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN,
                    :context => _reqId
                },
                method(:onResponse)
            );
        } catch (e) {
            addLine(label + " THROW " + e.getErrorMessage());
            _waiting = false;
            _step++;
        }
    }

    // 요청이 즉시 실패하면 makeWebRequest 안에서 바로 불릴 수도 있습니다.
    // 여기서는 다음 요청을 보내지 않고 상태만 바꿉니다.
    // 시간 초과 뒤 늦게 도착한 응답은 요청 번호로 걸러 냅니다.
    function onResponse(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null, context as Object) as Void {
        if (!_waiting || !(context instanceof Number) || (context as Number) != _reqId) {
            return;
        }
        _waiting = false;
        trackMemory();
        var secs = (System.getTimer() - _waitSince) / 1000.0;
        var len = 0;
        var str = null;
        if (data instanceof String) {
            str = data as String;
            len = str.length();
        }
        var line = _curLabel + " " + code + " len=" + len + " " + secs.format("%.1f") + "s";
        if (_step == 0) {
            line += " timer=" + _reqTimer;
        }
        line += " mem=" + kb(System.getSystemStats().usedMemory);
        addLine(line);

        if (code == 200 && str != null && _step >= 1) {
            testStoreValue(str);
            var k = JamConfig.SIZES_KB[_step - 1];
            if (k == 8 || k == 32) {
                testDecode(str);
            }
            if (k == 8) {
                _fillData = str;
            }
        }
        _step++;
    }

    // ---------------------------------------------------------------- storage

    // 받은 문자열을 값 하나로 저장해 보고 바로 지웁니다.
    function testStoreValue(str as String) as Void {
        var size = kb(str.length());
        try {
            Application.Storage.setValue("jt_v", str);
            var back = Application.Storage.getValue("jt_v");
            var ok = (back instanceof String) && (back as String).length() == str.length();
            addLine("  store " + size + " " + (ok ? "OK" : "MISMATCH"));
        } catch (e) {
            addLine("  store " + size + " FAIL " + errName(e));
        }
        try {
            Application.Storage.deleteValue("jt_v");
        } catch (e2) {
        }
    }

    // Base64 문자열을 ByteArray로 복원하고 메모리 증가량을 봅니다.
    function testDecode(str as String) as Void {
        var before = System.getSystemStats().usedMemory;
        try {
            var bytes = StringUtil.convertEncodedString(str, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            });
            var after = System.getSystemStats().usedMemory;
            trackMemory();
            var n = (bytes instanceof ByteArray) ? (bytes as ByteArray).size() : -1;
            addLine("  b64 " + kb(str.length()) + " -> " + n + "B +" + kb(after - before));
            bytes = null;
        } catch (e) {
            addLine("  b64 FAIL " + errName(e));
        }
    }

    // ByteArray를 그대로 저장할 수 있는지 봅니다. 문서의 허용 타입 목록에는 없습니다.
    function testByteArray() as Void {
        try {
            var ba = [1, 2, 3, 250]b;
            Application.Storage.setValue("jt_ba", untyped(ba));
            var back = untyped(Application.Storage.getValue("jt_ba"));
            if (back instanceof ByteArray) {
                addLine("bytearray store OK size=" + (back as ByteArray).size());
            } else {
                addLine("bytearray store: read back as other type");
            }
        } catch (e) {
            addLine("bytearray store FAIL " + errName(e));
        }
        try {
            Application.Storage.deleteValue("jt_ba");
        } catch (e2) {
        }
    }

    // 8 KB 값을 1초에 하나씩 써서 가득 차는 지점을 찾습니다.
    function fillStep() as Void {
        if (_fillData == null) {
            addLine("fill SKIP (no 8k data)");
            _step++;
            return;
        }
        if (_fillIdx >= JamConfig.FILL_MAX) {
            addLine("fill " + _fillIdx + "x8k OK, stopped at " + (_fillIdx * 8) + "k");
            cleanupFill(_fillIdx);
            _step++;
            return;
        }
        try {
            Application.Storage.setValue("jt_f" + _fillIdx, _fillData as String);
            _fillIdx++;
        } catch (e) {
            addLine("fill stop at " + _fillIdx + "x8k=" + (_fillIdx * 8) + "k " + errName(e));
            cleanupFill(_fillIdx + 1);
            _step++;
        }
    }

    function cleanupFill(count as Number) as Void {
        for (var i = 0; i < count; i++) {
            try {
                Application.Storage.deleteValue("jt_f" + i);
            } catch (e) {
            }
        }
        _fillData = null;
    }

    function finish() as Void {
        addLine("peak mem " + kb(_peakUsed) + "/" + kb(_totalMem));
        addLine("DONE run#" + _runNo);
        try {
            Application.Storage.setValue("jt_last", _lines);
        } catch (e) {
            addLine("save FAIL " + errName(e));
        }
    }

    // ------------------------------------------------------------- nav values

    function updateNav(info as Activity.Info) as Void {
        _navLines = [
            "phone memo " + _memo,
            "timer " + timerName(info.timerState),
            "toDest " + num(info.distanceToDestination),
            "toNext " + num(info.distanceToNextPoint),
            "destName " + text(info.nameOfDestination),
            "nextName " + text(info.nameOfNextPoint),
            "elevDest " + num(info.elevationAtDestination),
            "offCourse " + num(info.offCourseDistance),
            "elapsed " + num(info.elapsedDistance)
        ];
    }

    // ------------------------------------------------------------------ draw

    function onTapped() as Void {
        _tapCount++;
        _page = (_page + 1) % pageCount();
        _lockUntil = System.getTimer() + 30000;
    }

    function pageCount() as Number {
        return (_lines.size() + 9) / 10 + 1;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var pages = pageCount();
        var page = _page;
        if (System.getTimer() > _lockUntil) {
            page = (System.getTimer() / 6000) % pages;
            _page = page;
        }
        page = page % pages;

        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var y = (h * 0.14).toNumber();

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        var status = _waiting ? "wait " + _curLabel : (_step > JamConfig.SIZES_KB.size() + 3 ? "done" : "step " + _step);
        dc.drawText(w / 2, y, font, "JAM Trail Test " + (page + 1) + "/" + pages + "  tap " + _tapCount, Graphics.TEXT_JUSTIFY_CENTER);
        y += lh;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, font, status, Graphics.TEXT_JUSTIFY_CENTER);
        y += lh + 4;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (page < pages - 1) {
            var from = page * 10;
            var to = from + 10;
            if (to > _lines.size()) {
                to = _lines.size();
            }
            for (var i = from; i < to; i++) {
                dc.drawText(w / 2, y, font, _lines[i], Graphics.TEXT_JUSTIFY_CENTER);
                y += lh;
            }
        } else {
            for (var j = 0; j < _navLines.size(); j++) {
                dc.drawText(w / 2, y, font, _navLines[j], Graphics.TEXT_JUSTIFY_CENTER);
                y += lh;
            }
            // 한글 표시 시험: 본 앱은 한글 레이블을 씁니다
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + 4, Graphics.FONT_SMALL, "한글: 오르막 끝 25%", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --------------------------------------------------------------- helpers

    function addLine(line as String) as Void {
        _lines.add(line);
        System.println(line);
    }

    function trackMemory() as Void {
        var used = System.getSystemStats().usedMemory;
        if (used > _peakUsed) {
            _peakUsed = used;
        }
    }

    function timerNow() as String {
        var info = Activity.getActivityInfo();
        return info == null ? "null" : timerName(info.timerState);
    }

    function timerName(ts as Number?) as String {
        if (ts == null) {
            return "null";
        }
        if (ts == Activity.TIMER_STATE_OFF) {
            return "OFF";
        }
        if (ts == Activity.TIMER_STATE_STOPPED) {
            return "STOPPED";
        }
        if (ts == Activity.TIMER_STATE_PAUSED) {
            return "PAUSED";
        }
        if (ts == Activity.TIMER_STATE_ON) {
            return "ON";
        }
        return ts.toString();
    }

    function kb(bytes as Number) as String {
        return (bytes / 1024).toString() + "k";
    }

    function num(v as Numeric?) as String {
        return v == null ? "null" : v.toFloat().format("%.1f");
    }

    function text(v as String?) as String {
        return v == null ? "null" : "\"" + v + "\"";
    }

    function errName(e as Exception) as String {
        if (e instanceof Lang.StorageFullException) {
            return "StorageFull";
        }
        var msg = e.getErrorMessage();
        return msg == null ? "error" : msg;
    }

    // 타입 검사를 피해 ByteArray를 저장 함수에 넘기기 위한 함수입니다 (시험 전용).
    function untyped(v) {
        return v;
    }
}
