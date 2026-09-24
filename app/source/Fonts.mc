import Toybox.Graphics;
import Toybox.Lang;

// 화면 글꼴. 명세 4.1의 글자 크기(화면 지름 S에 대한 비율)를 맞추려고 기기의 벡터(크기 조절) 글꼴을 씁니다.
//   글자(한글 포함): NanumGothicBold  — 시계 언어 설정과 관계없이 한글이 나옵니다.
//   숫자: RobotoCondensedBold          — 프로토타입의 좁은 숫자 글꼴(Barlow Condensed) 대신
// fēnix 8은 이 글꼴을 모든 언어 글꼴 세트에 갖고 있습니다(기기 파일 simulator.json의 system_ttf).
// 벡터 글꼴을 쓸 수 없는 기기에서는 높이가 가장 가까운 시스템 글꼴로 대신합니다.
// 같은 크기는 한 번만 만들고 다시 씁니다.
class Fonts {
    static const KR_FACE = ["NanumGothicBold", "RobotoMedium"];
    static const NUM_FACE = ["RobotoCondensedBold", "BionicBold", "RobotoMedium"];
    static const SYSTEM = [
        Graphics.FONT_XTINY, Graphics.FONT_TINY, Graphics.FONT_SMALL, Graphics.FONT_MEDIUM, Graphics.FONT_LARGE,
        Graphics.FONT_NUMBER_MILD, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_THAI_HOT
    ];

    var _keys as Array<Number> = [];
    var _fonts as Array<Graphics.FontType> = [];

    function initialize() {
    }

    // 글자용. px는 글자 크기(픽셀)
    function kr(px as Float or Number) as Graphics.FontType {
        return get(px.toNumber(), false);
    }

    // 숫자용
    function num(px as Float or Number) as Graphics.FontType {
        return get(px.toNumber(), true);
    }

    function get(px as Number, isNum as Boolean) as Graphics.FontType {
        if (px < 8) {
            px = 8;
        }
        var key = isNum ? px + 10000 : px;
        for (var i = 0; i < _keys.size(); i++) {
            if (_keys[i] == key) {
                return _fonts[i];
            }
        }
        var f = null;
        if (Graphics has :getVectorFont) {
            f = Graphics.getVectorFont({ :face => isNum ? NUM_FACE : KR_FACE, :size => px });
        }
        if (f == null) {
            f = nearestSystem(px, isNum);
        }
        _keys.add(key);
        _fonts.add(f as Graphics.FontType);
        return f as Graphics.FontType;
    }

    // 벡터 글꼴이 없을 때: 글자 높이가 px에 가장 가까운 시스템 글꼴 (숫자 전용 글꼴은 숫자에만)
    function nearestSystem(px as Number, isNum as Boolean) as Graphics.FontType {
        var best = SYSTEM[0];
        var bestD = 100000;
        var limit = isNum ? SYSTEM.size() : 5;
        for (var i = 0; i < limit; i++) {
            var d = (Graphics.getFontHeight(SYSTEM[i]) - px * 1.2).abs().toNumber();
            if (d < bestD) {
                bestD = d;
                best = SYSTEM[i];
            }
        }
        return best;
    }
}
