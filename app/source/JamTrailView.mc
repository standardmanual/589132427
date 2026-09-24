import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// JAM Trail 데이터 필드.
// 4단계: 코스 받기·저장·복원과 상태 표시(명세 4.3). 그래프(5단계 이후)가 들어갈 자리에는
// 지금은 복원한 코스 요약을 보여 줍니다.
class JamTrailView extends WatchUi.DataField {
    var _sync as CourseSync;
    var _course as TrailCourse? = null;
    var _started as Boolean = false;

    function initialize() {
        DataField.initialize();
        _sync = new CourseSync();
    }

    function compute(info as Activity.Info) as Void {
        var now = System.getTimer();
        if (!_started) {
            _started = true;
            // 폰 없이도 저장된 코스로 바로 그립니다.
            var active = CourseStore.getString(CourseStore.K_ACTIVE);
            if (active != null) {
                _course = CourseStore.loadCourse(active, false);
                System.println(_course != null
                    ? "loaded stored course " + active + " (" + (_course as TrailCourse).data.size() + " B) mem " + (System.getSystemStats().usedMemory / 1024) + "k"
                    : "stored course " + active + " could not be loaded");
            } else {
                System.println("no stored course");
            }
            _sync.start();
        }
        _sync.tick(now);
        var c = _sync.takeLoaded();
        if (c != null) {
            _course = c;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var s = dc.getWidth();
        var now = System.getTimer();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var course = _course;
        if (course == null) {
            if (_sync.isDownloading()) {
                center(dc, s, "코스 받는 중 " + _sync.progressText(), null);
            } else if (_sync.isChecking()) {
                center(dc, s, "코스 확인 중", null);
            } else {
                center(dc, s, "코스 없음", "폰 연결 후 활동을 다시 여세요");
            }
            var err = _sync.message(now);
            if (err != null) {
                bottomLine(dc, s, err, _sync.messageTail(), Graphics.COLOR_ORANGE);
            }
            return;
        }

        drawCourseSummary(dc, s, course);

        var msg = _sync.message(now);
        if (_sync.isDownloading()) {
            bottomLine(dc, s, "새 코스 받는 중 " + _sync.progressText(), "", Graphics.COLOR_LT_GRAY);
        } else if (msg != null) {
            bottomLine(dc, s, msg, _sync.messageTail(), Graphics.COLOR_LT_GRAY);
        }
    }

    // 5단계에서 그래프로 바뀔 임시 화면: 복원한 코스가 맞는지 확인하는 용도입니다.
    function drawCourseSummary(dc as Graphics.Dc, s as Number, c as TrailCourse) as Void {
        var cx = s / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawFit(dc, cx, (s * 0.30).toNumber(), Graphics.FONT_SMALL, c.name, "", (s * 0.80).toNumber());
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var lh = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = (s * 0.42).toNumber();
        var lines = [
            (c.lengthM() / 1000.0).format("%.2f") + " km · " + c.n + "점",
            "오르막 " + c.upCount + " · 내리막 " + c.downCount + " · 구간 " + c.segCount,
            "시작 " + c.ele(0).format("%.0f") + " m · 끝 " + c.ele(c.n - 1).format("%.0f") + " m",
            "ID " + c.id
        ];
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }
    }

    function center(dc as Graphics.Dc, s as Number, line1 as String, line2 as String?) as Void {
        var cx = s / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, s / 2, Graphics.FONT_SMALL, line1, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        if (line2 != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            drawWrapped(dc, cx, s / 2 + dc.getFontHeight(Graphics.FONT_SMALL) / 2 + 4, Graphics.FONT_XTINY, line2, (s * 0.80).toNumber());
        }
    }

    // 폭을 넘으면 가운데에 가장 가까운 띄어쓰기에서 두 줄로 나눕니다.
    function drawWrapped(dc as Graphics.Dc, x as Number, y as Number, font as Graphics.FontType, text as String, maxW as Number) as Void {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var chars = text.toCharArray();
        var mid = chars.size() / 2;
        var cut = -1;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ' && (cut < 0 || (i - mid).abs() < (cut - mid).abs())) {
                cut = i;
            }
        }
        if (cut < 0) {
            drawFit(dc, x, y, font, text, "", maxW);
            return;
        }
        drawFit(dc, x, y, font, text.substring(0, cut) as String, "", maxW);
        drawFit(dc, x, y + dc.getFontHeight(font), font, text.substring(cut + 1, chars.size()) as String, "", maxW);
    }

    // 마지막 줄 자리(y 0.892S, 명세 4.1). 원 안에 들어가도록 폭을 줄입니다.
    // 글자 높이 범위(0.86–0.89S)에서 원의 폭이 약 0.64S입니다.
    function bottomLine(dc as Graphics.Dc, s as Number, text as String, tail as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var font = Graphics.FONT_XTINY;
        var baseline = (s * 0.892).toNumber();
        var top = baseline - Graphics.getFontAscent(font);
        drawFit(dc, s / 2, top, font, text, tail, (s * 0.64).toNumber());
    }

    // maxW를 넘으면 text의 끝을 잘라 "…"을 붙입니다. tail은 줄이지 않고 항상 붙입니다.
    function drawFit(dc as Graphics.Dc, x as Number, y as Number, font as Graphics.FontType, text as String, tail as String, maxW as Number) as Void {
        var t = text + tail;
        if (dc.getTextWidthInPixels(t, font) > maxW) {
            var chars = text.toCharArray();
            var n = chars.size();
            while (n > 1) {
                n--;
                t = text.substring(0, n) + "…" + tail;
                if (dc.getTextWidthInPixels(t, font) <= maxW) {
                    break;
                }
            }
        }
        dc.drawText(x, y, font, t, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
