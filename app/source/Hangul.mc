import Toybox.Lang;

// 한글 자모를 완성형 음절로 합칩니다 (유니코드 NFC 중 한글 부분).
// 맥에서 올린 파일 이름은 자모가 분리된 형태(NFD)로 저장되는 일이 많은데, 시계 글꼴은 분리된 자모를
// 합쳐서 그리지 못해 글자가 깨집니다. 변환기도 이름을 NFC로 바꾸지만, 예전에 받아 둔 코스 이름도
// 화면에 그릴 때 한 번 더 합칩니다.
//   초성 U+1100–1112, 중성 U+1161–1175, 종성 U+11A8–11C2 → 음절 U+AC00 + ((초×21 + 중)×28 + 종)
module Hangul {
    function compose(s as String) as String {
        var chars = s.toCharArray();
        var n = chars.size();
        var needs = false;
        for (var i = 0; i < n; i++) {
            var c = chars[i].toNumber();
            if (c >= 0x1100 && c <= 0x11FF) {
                needs = true;
                break;
            }
        }
        if (!needs) {
            return s;
        }
        var out = "";
        var i = 0;
        while (i < n) {
            var c = chars[i].toNumber();
            if (c >= 0x1100 && c <= 0x1112 && i + 1 < n) {
                var v = chars[i + 1].toNumber();
                if (v >= 0x1161 && v <= 0x1175) {
                    var syl = 0xAC00 + ((c - 0x1100) * 21 + (v - 0x1161)) * 28;
                    i += 2;
                    if (i < n) {
                        var t = chars[i].toNumber();
                        if (t >= 0x11A8 && t <= 0x11C2) {
                            syl += t - 0x11A7;
                            i++;
                        }
                    }
                    out += syl.toChar().toString();
                    continue;
                }
            }
            out += chars[i].toString();
            i++;
        }
        return out;
    }
}
