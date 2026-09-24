import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class JamTestApp extends Application.AppBase {
    var _view as JamTestView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new JamTestView();
        _view = view;
        return [view, new JamTestDelegate(view)];
    }

    // 폰(Connect IQ 앱)에서 설정을 바꾸면 불립니다.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
    }
}
