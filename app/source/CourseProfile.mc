import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// 코스 전체 정적 그래프 (명세 9장 5단계). 변환기의 미리보기 PNG(trailgrade/preview.py)와 같은 규칙으로 그립니다.
//   - 가로: 코스 전체를 그래프 폭에 맞춤. 열(1 px)마다 열 중앙 거리의 고도를 보간합니다.
//   - 세로: 코스 최저·최고 고도를 눈금 단위(nice step)로 넓힌 범위를 그래프 높이에 맞춤.
//   - 색: 열 위치 포인트 q의 앞뒤 창 [q−1, q+2]의 경사로 경사 색 구간(명세 3.3)을 고릅니다.
//   - 맨 위 띠: 구간 유형 (주황 오르막, 파랑 내리막, 회색 평지), 가는 세로선: 구간 경계.
// 열마다 높이와 색을 한 번만 계산해 두고(build), 그릴 때는 캐시만 씁니다(draw).
// scripts/check_profile.py가 로그의 열 값을 Python 계산과 비교합니다.
class CourseProfile {
    static const EDGES = [5, 10, 15, 20, 30];
    // 0–5 인덱스 오르막, 6–11 내리막
    static const COLORS = [
        0x00df3f, 0xfefc00, 0xffb63f, 0xfe6a00, 0xe00041, 0xdd00de,
        0x00e074, 0x48fff8, 0x38c5ff, 0x1888ff, 0x8600ee, 0xea41ff
    ];
    static const UP_ID = 0xfe6a00;
    static const DN_ID = 0x1888ff;
    static const FLAT_ID = 0x3d3d3d;

    var x0 as Number = 0;
    var width as Number = 0;
    var bandTop as Number = 0;
    var bandH as Number = 0;
    var top as Number = 0;
    var base as Number = 0;
    var yMin as Float = 0.0;
    var yMax as Float = 0.0;
    var colY as Array<Number> = [];
    var colC as ByteArray = []b;
    var segX as Array<Number> = [];
    var segT as ByteArray = []b;

    // s: 화면 지름(px). 그래프 영역은 명세 4.1의 x 0.07S–0.93S, y 0.30S–0.67S.
    function initialize(c as TrailCourse, s as Number) {
        x0 = (s * 0.07 + 0.5).toNumber();
        width = (s * 0.93 + 0.5).toNumber() - x0;
        bandTop = (s * 0.30 + 0.5).toNumber();
        bandH = (s * 0.012 + 0.5).toNumber();
        if (bandH < 3) {
            bandH = 3;
        }
        top = (s * 0.336 + 0.5).toNumber(); // 위쪽 0.036S는 띠와 여백 (나중에 현재 위치 삼각형 자리)
        base = (s * 0.67 + 0.5).toNumber();
        build(c);
    }

    function build(c as TrailCourse) as Void {
        var n = c.n;
        var I = c.interval;
        var total = c.lengthM().toFloat();

        // 최저·최고 고도는 매니페스트 값을 씁니다. 5,000점을 한 번에 훑으면 워치독에 걸립니다(명세 8장).
        var mn = c.eleMinDm;
        var mx = c.eleMaxDm;
        var lo = mn / 10.0;
        var hi = mx / 10.0;
        var span = (hi - lo) / 4.0;
        var ys = niceStep(span > 10.0 ? span : 10.0);
        yMin = Math.floor(lo / ys) * ys;
        yMax = Math.ceil(hi / ys) * ys;
        if (yMax == yMin) {
            yMax += ys;
        }

        colY = new Array<Number>[width];
        colC = new [width]b;
        var h = (base - top).toFloat();
        for (var x = 0; x < width; x++) {
            var d = (x + 0.5) / width * total;
            var q = (d / I).toNumber();
            if (q > n - 2) {
                q = n - 2;
            }
            var f = d / I - q;
            var e0 = c.ele(q);
            var e = e0 + (c.ele(q + 1) - e0) * f;
            var a = q > 0 ? q - 1 : 0;
            var b = q + 2 < n - 1 ? q + 2 : n - 1;
            var g = (c.ele(b) - c.ele(a)) / ((b - a) * I) * 100.0;
            colY[x] = (top + (1.0 - (e - yMin) / (yMax - yMin)) * h + 0.5).toNumber();
            colC[x] = colorIndex(g);
        }

        segX = new Array<Number>[c.segCount + 1];
        segT = new [c.segCount]b;
        for (var s = 0; s < c.segCount; s++) {
            segX[s] = xOf(c.segStart(s) * I, total);
            segT[s] = c.segType(s);
        }
        segX[c.segCount] = xOf(total, total);
    }

    function xOf(d as Number or Float, total as Float) as Number {
        return (x0 + d / total * width + 0.5).toNumber();
    }

    static function colorIndex(g as Float) as Number {
        var a = g < 0 ? -g : g;
        var i = 0;
        while (i < EDGES.size() && a >= EDGES[i]) {
            i++;
        }
        return g >= 0 ? i : i + 6;
    }

    static function niceStep(raw as Float) as Float {
        var p = Math.pow(10, Math.floor(Math.log(raw, 10))).toFloat();
        var f = raw / p;
        var m = f < 1.5 ? 1 : f < 3.5 ? 2 : f < 7.5 ? 5 : 10;
        return m * p;
    }

    function draw(dc as Graphics.Dc) as Void {
        // 경사 색 채움: 같은 색이 이어지는 동안 색을 바꾸지 않습니다.
        var last = -1;
        for (var x = 0; x < width; x++) {
            var ci = colC[x];
            if (ci != last) {
                dc.setColor(COLORS[ci], Graphics.COLOR_TRANSPARENT);
                last = ci;
            }
            dc.drawLine(x0 + x, colY[x], x0 + x, base);
        }
        // 윤곽선
        dc.setColor(0xe8e8e8, Graphics.COLOR_TRANSPARENT);
        for (var x = 1; x < width; x++) {
            dc.drawLine(x0 + x - 1, colY[x - 1], x0 + x, colY[x]);
        }
        // 기준선
        dc.setColor(0x2c2c2c, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x0, base, x0 + width, base);
        // 구간 유형 띠와 경계
        for (var s = 0; s < segT.size(); s++) {
            var t = segT[s];
            dc.setColor(t == TrailCourse.UP ? UP_ID : t == TrailCourse.DOWN ? DN_ID : FLAT_ID, Graphics.COLOR_TRANSPARENT);
            var xa = segX[s] + (s > 0 ? 1 : 0);
            var w = segX[s + 1] - xa;
            dc.fillRectangle(xa, bandTop, w > 1 ? w : 1, bandH);
            if (s > 0) {
                dc.setColor(0x3c3c3c, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(segX[s], bandTop + bandH + 2, segX[s], base);
            }
        }
    }

    // 시험용: 열 값을 한 줄로 기록합니다 (scripts/check_profile.py가 읽음).
    function logColumns(c as TrailCourse, s as Number) as Void {
        System.println("PROFILE id=" + c.id + " s=" + s + " x0=" + x0 + " w=" + width + " top=" + top + " base=" + base
            + " ymin=" + yMin + " ymax=" + yMax);
        var line = "PROFILE_Y";
        for (var x = 0; x < width; x++) {
            line += " " + colY[x];
        }
        System.println(line);
        line = "PROFILE_C";
        for (var x = 0; x < width; x++) {
            line += " " + colC[x];
        }
        System.println(line);
    }
}
