import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// 시계 안 설정 메뉴 (명세 5.1). 활동 메뉴의 데이터 필드 설정에서 열립니다(AppBase.getSettingsView).
// 기본 Menu2는 시스템 글꼴이라 시계 언어가 영어면 한글이 나오지 않을 수 있어, CustomMenu로 직접 그리고
// 화면과 같은 벡터 글꼴(NanumGothicBold)을 씁니다.
//
// 첫 화면: 세로 배율, 그래프 가로 범위, 현재 경사 평균 구간, 코스 이탈 임계값, 경사 색상, 코스, 코스 목록 새로고침
// 항목을 고르면 선택지 메뉴가 열리고, 고르면 저장한 뒤 첫 화면으로 돌아옵니다.
module MenuUi {
    const ID_COURSE = 100;
    const ID_REFRESH = 101;

    // 글자 크기와 줄 높이 (화면 지름 S에 대한 비율). 가장 작은 글자(보조 줄)는 시계 기본 메뉴 글자와 같은
    // 36 px(454 px 화면 기준 0.08S)입니다. 시뮬레이터에서 같은 한글 문장의 폭을 재서 맞췄습니다
    // (처음 0.052 / 0.04, 다음 0.072 / 0.058이 실기기에서 모두 작았음).
    const FONT_MAIN = 0.09;
    const FONT_SUB = 0.08;
    const FONT_TITLE = 0.08;
    const ROW_H = 0.21;
    // 글자는 왼쪽 정렬입니다. 줄 그림 영역(dc)은 화면 왼쪽 세로선 바로 오른쪽에서 시작합니다(454 px 화면에서
    // 390×95, 시작점 약 x=64–77). 그래서 글자는 그 영역의 왼쪽 끝 가까이(화면 기준 약 0.19S)에 둡니다.
    const X_TEXT = 0.02;
    const X_RIGHT_MARGIN = 0.09;
    const X_TITLE = 0.22;     // 제목은 전체 화면 폭 기준이라 항목 글자(줄 영역 시작점 + X_TEXT)와 맞춥니다
    const GREEN = 0x00df3f;   // 지금 고른 값

    var _fonts as Fonts? = null;

    function fonts() as Fonts {
        if (_fonts == null) {
            _fonts = new Fonts();
        }
        return _fonts as Fonts;
    }

    function screen() as Number {
        return System.getDeviceSettings().screenWidth;
    }

    // 왼쪽 정렬로 한두 줄을 그립니다. 폭을 넘으면 끝을 줄입니다.
    // 선택(포커스)한 줄의 파란 그라데이션 배경은 기본 메뉴가 그려 넓은 자리를 차지해서, 줄 영역을 검게 덮고
    // 글자를 밝게 하는 것으로 대신합니다. 지금 고른 값은 글자를 초록으로 그립니다.
    function drawTwoLines(dc as Graphics.Dc, main as String, sub as String?, focused as Boolean, mark as Boolean) as Void {
        var s = screen();
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, h);
        var f1 = fonts().kr(FONT_MAIN * s);
        var f2 = fonts().kr(FONT_SUB * s);
        var h1 = Graphics.getFontHeight(f1);
        var h2 = sub == null ? 0 : Graphics.getFontHeight(f2);
        var y = (h - h1 - h2) / 2;
        var x = (X_TEXT * s).toNumber();
        var maxW = w - x - (X_RIGHT_MARGIN * s).toNumber();
        dc.setColor(mark ? GREEN : focused ? Graphics.COLOR_WHITE : 0xd0d0d0, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f1, fit(dc, f1, main, maxW), Graphics.TEXT_JUSTIFY_LEFT);
        if (sub != null) {
            dc.setColor(mark ? 0x66e08a : focused ? 0xe0e0e0 : 0xb0b0b0, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + h1, f2, fit(dc, f2, sub, maxW), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function fit(dc as Graphics.Dc, f as Graphics.FontType, t as String, maxW as Number) as String {
        if (dc.getTextWidthInPixels(t, f) <= maxW) {
            return t;
        }
        var n = t.length();
        var r = t;
        while (n > 1) {
            n--;
            r = t.substring(0, n) + "…";
            if (dc.getTextWidthInPixels(r, f) <= maxW) {
                break;
            }
        }
        return r;
    }

    function newMenu(title as String) as WatchUi.CustomMenu {
        var s = screen();
        return new WatchUi.CustomMenu((ROW_H * s).toNumber(), Graphics.COLOR_BLACK, {
            :title => new MenuTitle(title),
            :titleItemHeight => (0.22 * s).toNumber()
        });
    }

    // 설정 첫 화면
    function mainMenu() as [WatchUi.Views, WatchUi.InputDelegates] {
        var m = newMenu("JAM Trail 설정");
        for (var k = 0; k < Settings.KEYS.size(); k++) {
            m.addItem(new SettingRow(k));
        }
        m.addItem(new SettingRow(ID_COURSE));
        m.addItem(new SettingRow(ID_REFRESH));
        return [m, new SettingsDelegate()];
    }

    // 설정 하나의 선택지
    function optionMenu(k as Number) as WatchUi.CustomMenu {
        var key = Settings.KEYS[k];
        var m = newMenu(Settings.NAMES[k]);
        var values = Settings.VALUES[k] as Array<Number>;
        var labels = Settings.LABELS[k] as Array<String>;
        for (var i = 0; i < values.size(); i++) {
            m.addItem(new OptionRow(key, values[i], labels[i], null));
        }
        return m;
    }

    // 코스 선택: 서버 현재 코스 따르기, 저장된 코스(활성·직전), 서버 목록(index.txt)의 다른 코스
    function courseMenu() as WatchUi.CustomMenu {
        var m = newMenu("코스");
        m.addItem(new OptionRow(Settings.COURSE, "", "서버 현재 코스 따르기", "새 코스가 올라오면 받음"));
        var seen = [] as Array<String>;
        var stored = [CourseStore.getString(CourseStore.K_ACTIVE), CourseStore.getString(CourseStore.K_PREV)];
        for (var i = 0; i < stored.size(); i++) {
            var id = stored[i];
            if (id == null || seen.indexOf(id) >= 0) {
                continue;
            }
            var man = CourseStore.manifest(id);
            if (man == null) {
                continue;
            }
            var name = man["name"];
            var len = man["len"];
            m.addItem(new OptionRow(Settings.COURSE, id, (name instanceof String) ? Hangul.compose(name) : id,
                ((len instanceof Number) ? (len / 1000.0).format("%.1f") + " km · " : "") + (i == 0 ? "지금 코스" : "저장됨")));
            seen.add(id);
        }
        var rows = CourseIndex.rows();
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i];
            if (seen.indexOf(r[0]) >= 0) {
                continue;
            }
            m.addItem(new OptionRow(Settings.COURSE, r[0], r[1], r[2] + " · 고르면 받음"));
            seen.add(r[0]);
        }
        return m;
    }
}

// 메뉴 제목
class MenuTitle extends WatchUi.Drawable {
    var _text as String;

    function initialize(text as String) {
        Drawable.initialize({});
        _text = text;
    }

    function draw(dc as Graphics.Dc) as Void {
        var s = MenuUi.screen();
        var f = MenuUi.fonts().kr(MenuUi.FONT_TITLE * s);
        dc.setColor(0xc4c4c4, Graphics.COLOR_TRANSPARENT);
        dc.drawText((MenuUi.X_TITLE * s).toNumber(), dc.getHeight() - Graphics.getFontHeight(f) - 4, f, _text, Graphics.TEXT_JUSTIFY_LEFT);
    }
}

// 첫 화면의 한 줄: 설정 이름과 지금 값
class SettingRow extends WatchUi.CustomMenuItem {
    var k as Number;

    function initialize(id as Number) {
        CustomMenuItem.initialize(id, {});
        k = id;
    }

    function draw(dc as Graphics.Dc) as Void {
        var main;
        var sub;
        if (k == MenuUi.ID_COURSE) {
            main = "코스";
            var id = Settings.course();
            if (id == null) {
                sub = "서버 현재 코스 따르기";
            } else {
                var man = CourseStore.manifest(id);
                var name = man != null ? man["name"] : null;
                sub = (name instanceof String) ? Hangul.compose(name) : CourseIndex.nameOf(id);
            }
        } else if (k == MenuUi.ID_REFRESH) {
            main = "코스 목록 새로고침";
            var n = CourseIndex.rows().size();
            sub = Settings.refreshRequested() ? "받는 중…" : n > 0 ? "서버 코스 " + n + "개" : "목록 없음";
        } else {
            main = Settings.NAMES[k];
            sub = Settings.label(Settings.KEYS[k]);
        }
        MenuUi.drawTwoLines(dc, main, sub, isFocused(), false);
    }
}

// 선택지 한 줄. value는 설정 값(Number) 또는 코스 ID(String, ""는 서버 따르기)
class OptionRow extends WatchUi.CustomMenuItem {
    var key as String;
    var value as Number or String;
    var label as String;
    var sub as String?;

    function initialize(k as String, v as Number or String, l as String, s as String?) {
        CustomMenuItem.initialize(v, {});
        key = k;
        value = v;
        label = l;
        sub = s;
    }

    function isCurrent() as Boolean {
        if (value instanceof String) {
            var c = Settings.course();
            return c == null ? (value as String).length() == 0 : c.equals(value);
        }
        return Settings.get(key) == value;
    }

    function draw(dc as Graphics.Dc) as Void {
        MenuUi.drawTwoLines(dc, label, sub, isFocused(), isCurrent());
    }
}

class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Number;
        if (id == MenuUi.ID_COURSE) {
            WatchUi.pushView(MenuUi.courseMenu(), new OptionDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == MenuUi.ID_REFRESH) {
            // 데이터 필드가 다음 compute()에서 index.txt를 받습니다.
            Settings.setRefresh(true);
            WatchUi.requestUpdate();
        } else {
            WatchUi.pushView(MenuUi.optionMenu(id), new OptionDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

class OptionDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var row = item as OptionRow;
        if (row.value instanceof String) {
            var v = row.value as String;
            Settings.setCourse(v.length() == 0 ? null : v);
        } else {
            Settings.set(row.key, row.value as Number);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
