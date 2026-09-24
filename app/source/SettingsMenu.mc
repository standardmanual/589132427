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

    // 가운데 정렬로 한두 줄을 그립니다. 폭을 넘으면 끝을 줄입니다.
    function drawTwoLines(dc as Graphics.Dc, main as String, sub as String?, focused as Boolean, mark as Boolean) as Void {
        var s = screen();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var f1 = fonts().kr(0.052 * s);
        var f2 = fonts().kr(0.04 * s);
        var h1 = Graphics.getFontHeight(f1);
        var h2 = sub == null ? 0 : Graphics.getFontHeight(f2);
        var y = (h - h1 - h2) / 2;
        var maxW = (w * 0.78).toNumber();
        if (mark) {
            // 지금 고른 값: 초록 점
            dc.setColor(0x00df3f, Graphics.COLOR_TRANSPARENT);
            var tw = dc.getTextWidthInPixels(main, f1);
            dc.fillCircle(w / 2 - (tw < maxW ? tw : maxW) / 2 - (0.03 * s).toNumber(), y + h1 / 2, (0.012 * s).toNumber() + 1);
        }
        dc.setColor(focused ? Graphics.COLOR_WHITE : 0xc8c8c8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, f1, fit(dc, f1, main, maxW), Graphics.TEXT_JUSTIFY_CENTER);
        if (sub != null) {
            dc.setColor(focused ? 0xb0b0b0 : 0x808080, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y + h1, f2, fit(dc, f2, sub, maxW), Graphics.TEXT_JUSTIFY_CENTER);
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
        return new WatchUi.CustomMenu((0.19 * s).toNumber(), Graphics.COLOR_BLACK, {
            :title => new MenuTitle(title),
            :titleItemHeight => (0.2 * s).toNumber()
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
            m.addItem(new OptionRow(Settings.COURSE, id, (name instanceof String) ? name : id,
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
        var f = MenuUi.fonts().kr(0.05 * s);
        dc.setColor(0x9a9a9a, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() - Graphics.getFontHeight(f) - 4, f, _text, Graphics.TEXT_JUSTIFY_CENTER);
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
                sub = (name instanceof String) ? name : CourseIndex.nameOf(id);
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
