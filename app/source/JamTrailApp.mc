import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class JamTrailApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new JamTrailView()];
    }

    // 시계 안 설정 메뉴 (명세 5.1): 활동 메뉴의 데이터 필드 설정에서 열립니다.
    function getSettingsView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] or Null {
        return MenuUi.mainMenu();
    }
}
