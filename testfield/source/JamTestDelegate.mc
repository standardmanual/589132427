import Toybox.Lang;
import Toybox.WatchUi;

// 터치 화면에서 데이터 필드가 탭을 받는지 확인합니다. 탭하면 다음 페이지로 넘어갑니다.
class JamTestDelegate extends WatchUi.InputDelegate {
    var _view as JamTestView;

    function initialize(view as JamTestView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.onTapped();
        return true;
    }
}
