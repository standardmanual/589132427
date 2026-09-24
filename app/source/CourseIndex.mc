import Toybox.Lang;

// 서버 코스 목록 index.txt (명세 6.6): 한 줄에 <id>\t<이름>\t<길이 m>\t<누적 상승 m>\t<조각 수>, 최신순 최대 20개.
// CourseSync가 받아 Storage의 "idx"에 문자열 그대로 저장하고, 설정 메뉴가 읽습니다.
module CourseIndex {
    const KEY = "idx";

    // [[id, 이름, "21.6 km · +851 m"], ...]
    function rows() as Array<[String, String, String]> {
        var out = [] as Array<[String, String, String]>;
        var text = CourseStore.getString(KEY);
        if (text == null) {
            return out;
        }
        var rest = text;
        while (rest.length() > 0) {
            var nl = rest.find("\n");
            var line = nl == null ? rest : rest.substring(0, nl) as String;
            rest = nl == null ? "" : rest.substring(nl + 1, rest.length()) as String;
            var f = split(line);
            if (f.size() >= 4 && f[0].length() == 10) {
                var len = f[2].toNumber();
                var gain = f[3].toNumber();
                out.add([f[0], Hangul.compose(f[1]),
                    (len != null ? (len / 1000.0).format("%.1f") + " km" : "") + (gain != null ? " · +" + gain + " m" : "")]);
            }
        }
        return out;
    }

    function nameOf(id as String) as String {
        var r = rows();
        for (var i = 0; i < r.size(); i++) {
            if (r[i][0].equals(id)) {
                return r[i][1];
            }
        }
        return id;
    }

    function split(line as String) as Array<String> {
        var out = [] as Array<String>;
        var rest = line;
        while (true) {
            var t = rest.find("\t");
            if (t == null) {
                out.add(rest);
                return out;
            }
            out.add(rest.substring(0, t) as String);
            rest = rest.substring(t + 1, rest.length()) as String;
        }
        return out;
    }
}
