import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// 워치 화면 (명세 4장). 프로토타입 drawWatch·drawProfile·windowBase·viewRange와 같은 규칙입니다.
// 좌표와 글자 크기는 모두 화면 지름 S에 대한 비율이고, 글자 y는 기준선입니다.
//
// 계산과 그리기를 나눕니다 (명세 7.7). 워치독(호출 한 번의 실행 한도)은 compute와 onUpdate에 따로 걸리므로
//   prepare()  compute()에서: 그래프 범위·축척, 열 높이·색, 모든 수치와 문자열
//   draw()     onUpdate()에서: 글자 폭 재기와 그리기만
//
// 그래프는 1 px 열 단위로 그립니다. 열마다 그 거리의 고도를 보간하고, 색은 열이 속한 20 m 스텝의
// 60 m 창 경사로 정합니다(명세 3.3). 스텝이 바뀔 때만 고도·색을 다시 읽습니다.
// 지나온 부분은 반투명 검정을 덮는 대신 절반 밝기 색으로 그립니다.
class WatchScreen {
    // 경사 색 3단계 (명세 3.3): 0–10, 10–20, 20% 이상. 오르막 초록·노랑·빨강, 내리막 초록·하늘·보라
    static const EDGES = [10, 20];
    static const BINS = 3;
    static const COLORS = [0x00df3f, 0xfefc00, 0xe00041, 0x00e074, 0x38c5ff, 0x8600ee];
    static const C_GRAY = 6;   // 색상 끔
    static const C_OUT = 7;    // 강조 범위 밖
    static const C_DIM = 16;   // 더하면 지나온 부분
    static const UP_ID = 0xfe6a00;
    static const DN_ID = 0x1888ff;
    static const OUT_FILL = 0x242424;
    static const OUT_LINE = 0x4a4a4a;
    static const IN_LINE = 0xe8e8e8;
    static const GRAY_FILL = 0x6a6a6a;
    static const WARN = 0xfab219;
    static const MARKER = 0xff1f1f;
    // 글자 크기 (화면 지름 S에 대한 비율). 가장 작은 글자는 시계 기본 메뉴 글자와 같은 크기입니다:
    // 시뮬레이터에서 같은 한글 문장의 폭을 재 보니 기본 메뉴 글꼴은 벡터 글꼴 36 px(454 px 화면, 0.08S)과 같았습니다.
    // 처음 라벨은 20 px, 실기기 사진에서 "여전히 너무 작다"고 해서 모든 글자를 이 크기 이상으로 맞췄습니다.
    static const FS_MIN = 0.08;        // 가장 작은 글자: 라벨, 단위, 가로 범위, 상태 문구
    static const FS_CHIP = 0.085;      // 모드 표시
    static const FS_SIDE_VALUE = 0.10; // 평균·최대 값
    static const FS_BIG = 0.16;        // 현재 경사 큰 숫자
    static const FS_VALUE = 0.10;      // 하단 값
    static const GRAY_LABEL = 0xc4c4c4;

    // 세로 배치 (글자 기준선의 화면 지름 대비 위치, 원 안에 들어가는지 확인한 값)
    static const Y_CHIP = 0.135;
    static const Y_SIDE_LABEL = 0.215;
    static const Y_SIDE_VALUE = 0.31;
    static const Y_BIG = 0.30;
    static const GRAPH_TOP = 0.335;
    static const GRAPH_H = 0.29;
    static const Y_SPAN = 0.705;
    static const Y_VALUE = 0.805;
    static const Y_LABEL = 0.895;
    static const X_SIDE_L = 0.23;
    static const X_SIDE_R = 0.77;
    static const X_COL_L = 0.335;
    static const X_COL_R = 0.665;
    static const NONE = -9999;
    static const COL_NONE = 255;

    var fonts as Fonts;
    var s as Number = 0;
    var u as Float = 1.0;

    // 설정 (8단계에서 시계 안 메뉴로). 명세 5.2 기본값
    var exag as Number = 3;
    var widthM as Number = 2000;      // 0이면 구간 맞춤
    var gradeWin as Float = 100.0;
    var colorOn as Boolean = true;

    // 그래프 영역 (명세 4.1)
    var bx as Number = 0;
    var by as Number = 0;
    var bw as Number = 0;
    var bh as Number = 0;
    var head as Number = 0;
    var base as Number = 0;

    // ---- prepare()가 채우는 값. 데이터 필드는 스택이 작아 지역 변수 대신 필드에 둡니다.
    var ready as Boolean = false;
    var _type as Number = 0;
    var _known as Boolean = false;
    var _off as Boolean = false;
    var _chip as String = "";
    var _g as Float = 0.0;
    var _num as String = "";
    var _sides as Boolean = false;
    var _sL2 as String = "";
    var _sR2 as String = "";
    var _fixed as Boolean = true;
    var _r0 as Float = 0.0;
    var _r1 as Float = 0.0;
    var _xo as Float = 0.0;
    var _kx as Float = 1.0;
    var _ky as Float = 1.0;
    var _vb as Float = 0.0;
    var _c0 as Float = 0.0;
    var _c1 as Float = 0.0;
    var _ahMn as Float = 0.0;
    var _ahMx as Float = 0.0;
    // 열 버퍼는 메모리를 아끼려고 바이트 배열에 둡니다 (숫자 배열은 칸마다 약 5 바이트).
    //   _colY: 윤곽 높이를 그래프 영역 위 끝(by)에서 잰 값. 0이면 영역 위로 넘침, bh+1이면 바닥 아래, COL_NONE이면 코스 밖
    //   _colC: 색 번호
    var _colY as ByteArray = []b;
    var _colC as ByteArray = []b;
    var _mm as Array<Float> = [0.0, 0.0];
    var _endD as Float = 0.0;
    var _endColor as Number = 0;
    var _endX as Number = NONE;
    var _endY as Number = 0;
    var _mX as Number = NONE;
    var _mY as Number = 0;
    var _above as Float = 0.0;
    var _below as Float = 0.0;
    var _span as String = "";
    var _vL as String = "";
    var _uL as String = "";
    var _lL as String = "";
    var _vR as String = "";
    var _uR as String = "";
    var _lR as String = "";
    var diagA as String? = null;   // 진단 표시 두 줄 (JamTrailView가 채움)
    var diagB as String? = null;

    function initialize(size as Number) {
        fonts = new Fonts();
        s = size;
        u = size / 454.0 * 1.3;
        bx = (0.07 * s + 0.5).toNumber();
        by = (GRAPH_TOP * s + 0.5).toNumber();
        bw = (0.86 * s + 0.5).toNumber();
        bh = (GRAPH_H * s + 0.5).toNumber();
        head = (0.036 * s + 0.5).toNumber();
        base = by + bh;
        _colY = new [bw]b;
        _colC = new [bw]b;
    }

    // =============================================================== 계산 (compute)

    // d: 코스 위치(m), seg: 화면 모드 구간(히스테리시스 적용), known: 위치를 정했는지
    function prepare(c as TrailCourse, d as Float, seg as Number, known as Boolean, off as Boolean, offDist as Float) as Void {
        _type = c.segType(seg);
        var next = _type == TrailCourse.FLAT ? c.nextNonFlat(seg) : -1;
        _known = known;
        _off = off;

        // 모드 표시
        if (!known) {
            _chip = "위치 찾는 중";
        } else if (off) {
            _chip = "이탈 " + fmt0(offDist) + " m";
        } else if (_type == TrailCourse.UP) {
            _chip = "오르막 " + c.segNo[seg] + "/" + c.upCount;
        } else if (_type == TrailCourse.DOWN) {
            _chip = "내리막 " + c.segNo[seg] + "/" + c.downCount;
        } else {
            _chip = "평지";
        }

        // 현재 경사와 양옆 열
        _g = c.gradeAt(d, gradeWin);
        var gr = Math.round(_g).toNumber();
        _num = (gr > 0 ? "+" : gr < 0 ? "−" : "") + gr.abs();
        _sides = _type != TrailCourse.FLAT;
        if (_sides) {
            _sL2 = fmt0(c.segAvg(seg).abs()) + "%";
            _sR2 = fmt0(c.maxAhead(d, seg)) + "%";
        }

        // 그래프
        setupGraph(c, d, seg, next);
        buildColumns(c, d, known);
        _endX = NONE;
        if (_endD >= _r0 && _endD <= _r1) {
            var ey = Y(c.eleAt(_endD));
            if (ey >= by - 1 && ey <= base + 1) {
                _endX = X(_endD);
                _endY = ey;
            }
        }
        _mX = NONE;
        if (known && d >= _r0 - 1.0 && d <= _r1 + 1.0) {
            var md = d < _r0 ? _r0 : d > _r1 ? _r1 : d;
            _mX = X(md);
            _mY = Y(c.eleAt(md));
        }
        // 화면 밖으로 잘린 앞쪽 고도 (windowBase가 구한 앞쪽 최저·최고)
        _above = 0.0;
        _below = 0.0;
        if (_fixed && known) {
            _above = _ahMx - (_vb + (bh - head) / _ky);
            _below = _vb - _ahMn;
        }
        if (_fixed) {
            _span = widthM >= 1000 ? (widthM / 1000) + " km" : widthM + " m";
        } else {
            var sp = _r1 - _r0;
            _span = "구간 " + (sp >= 1000.0 ? (sp / 1000.0).format("%.1f") + " km" : (Math.round(sp / 10.0) * 10).toNumber() + " m");
        }

        prepareBottom(c, d, seg, next);
        ready = true;
    }

    // 강조 범위와 끝 점(프로토타입 viewRange), 가로·세로 축척과 세로 위치
    function setupGraph(c as TrailCourse, d as Float, seg as Number, next as Number) as Void {
        var L = c.lengthM().toFloat();
        var ph = (bh - head).toFloat();
        _c0 = c.segStartD(seg).toFloat();
        _c1 = c.segEndD(seg).toFloat();
        _endD = _c1;
        _endColor = _type == TrailCourse.DOWN ? DN_ID : UP_ID;
        if (_type == TrailCourse.FLAT) {
            if (next >= 0) {
                _c1 = c.segEndD(next).toFloat();
                _endD = c.segStartD(next).toFloat();
                var nUp = c.segType(next) == TrailCourse.UP;
                _endColor = nUp ? UP_ID : DN_ID;
            } else {
                _endColor = IN_LINE;
            }
        } else {
        }

        _fixed = widthM > 0;
        if (_fixed) {
            // 가로 범위 고정: 현재 위치를 왼쪽 25%에 두고 앞쪽 75%. 축척은 모든 화면에서 같습니다.
            var Dw = widthM.toFloat();
            var w0 = d - 0.25 * Dw;
            _kx = bw / Dw;
            _ky = _kx * exag;
            _r0 = w0 < 0.0 ? 0.0 : w0;
            _r1 = w0 + Dw > L ? L : w0 + Dw;
            _vb = windowBase(c, d, ph / _ky);
            _xo = bx + (_r0 - w0) * _kx;
            _c0 = _r0;
            _c1 = _r1;
        } else {
            // 구간 맞춤: 현재 구간 + 여백, 가로·세로 비율을 고정한 채 함께 축소, 가운데·바닥 맞춤
            var pad = (_c1 - _c0) * 0.07;
            if (pad < 60.0) {
                pad = 60.0;
            }
            _r0 = _c0 - pad < 0.0 ? 0.0 : _c0 - pad;
            _r1 = _c1 + pad > L ? L : _c1 + pad;
            c.rangeMinMax(_r0, _r1, _mm);
            var spanE = _mm[1] - _mm[0];
            if (spanE < 2.0) {
                spanE = 2.0;
            }
            var spanD = _r1 - _r0 < 1.0 ? 1.0 : _r1 - _r0;
            _kx = bw / spanD;
            if (ph / (spanE * exag) < _kx) {
                _kx = ph / (spanE * exag);
            }
            _ky = _kx * exag;
            _vb = _mm[0];
            _xo = bx + (bw - spanD * _kx) / 2.0;
        }
    }

    // 가로 범위 고정 모드의 세로 위치 (명세 3.2, 프로토타입 windowBase).
    // 다 들어가면 바닥 맞춤, 넘치면 앞쪽을 우선해 현재 위치가 늘 화면 안에 있게 합니다.
    // 앞쪽 최저·최고(_ahMn, _ahMx)는 잘린 고도 표시에도 씁니다.
    function windowBase(c as TrailCourse, d as Float, V as Float) as Float {
        c.rangeMinMax(_r0, _r1, _mm);
        var allMn = _mm[0];
        if (_mm[1] - allMn <= V) {
            _ahMn = allMn;
            _ahMx = allMn; // 다 들어가므로 잘린 고도 없음
            return allMn;
        }
        c.rangeMinMax(d, _r1, _mm);
        _ahMn = _mm[0];
        _ahMx = _mm[1];
        if (_ahMx - _ahMn <= V) {
            return clampF(allMn, _ahMx - V, _ahMn);
        }
        var re = c.eleAt(d);
        var climbing = c.eleAt(_r1) >= re;
        return clampF(re - (climbing ? 0.25 : 0.75) * V, _ahMn, _ahMx - V);
    }

    // 열 계산: 윤곽 높이와 색 번호 (0–5 경사 색, C_GRAY 색상 끔, C_OUT 강조 밖, +C_DIM 지나온 부분)
    function buildColumns(c as TrailCourse, d as Float, known as Boolean) as Void {
        var I = c.interval;
        var n = c.n;
        var H = TrailCourse.HEADER;
        var lastQ = -1;
        var e0 = 0.0;
        var e1 = 0.0;
        var ci = 0;
        for (var x = 0; x < bw; x++) {
            var dx = _r0 + (bx + x + 0.5 - _xo) / _kx;
            if (dx < _r0 || dx > _r1) {
                _colY[x] = COL_NONE;
                continue;
            }
            var f = dx / I;
            var q = f.toNumber();
            if (q > n - 2) {
                q = n - 2;
            }
            if (q != lastQ) {
                lastQ = q;
                var o = H + 2 * q;
                e0 = c.u16(o) / 10.0;
                e1 = c.u16(o + 2) / 10.0;
                var dm = (q + 0.5) * I;
                ci = (dm < _c0 || dm > _c1) ? C_OUT : colorOn ? colorIndex(stepGrade(c, q, dm)) : C_GRAY;
            }
            var yy = (bh - (e0 + (e1 - e0) * (f - q) - _vb) * _ky + 0.5).toNumber();
            _colY[x] = yy < 0 ? 0 : yy > bh ? bh + 1 : yy;
            _colC[x] = (known && dx <= d) ? ci + C_DIM : ci;
        }
    }

    // q번 스텝 가운데(dm)의 60 m 창 경사. 20 m 간격이면 창이 격자점 q−1, q+2와 딱 맞아 두 점만 읽습니다.
    function stepGrade(c as TrailCourse, q as Number, dm as Float) as Float {
        if (c.interval != 20) {
            return c.gradeAt(dm, 60.0);
        }
        var a = q > 0 ? q - 1 : 0;
        var z = q + 2 < c.n - 1 ? q + 2 : c.n - 1;
        return (c.u16(TrailCourse.HEADER + 2 * z) - c.u16(TrailCourse.HEADER + 2 * a)) / ((z - a) * 20.0) * 10.0;
    }

    // 아래쪽 두 칸 (명세 4.2). 글자가 커져 라벨은 폭 안에 들어가는 짧은 말로 줄였습니다.
    function prepareBottom(c as TrailCourse, d as Float, seg as Number, next as Number) as Void {
        var remD = c.segEndD(seg) - d;
        if (remD < 0.0) {
            remD = 0.0;
        }
        if (_type == TrailCourse.UP || _type == TrailCourse.DOWN) {
            var up = _type == TrailCourse.UP;
            _vL = (up ? "+" : "−") + fmt0(c.remainClimb(d, seg, up));
            _uL = "m";
            _lL = up ? "남은 상승" : "남은 하강";
            _vR = km(remD);
            _uR = "km";
            _lR = "남은 거리";
        } else if (next >= 0) {
            var nUp = c.segType(next) == TrailCourse.UP;
            var toNext = c.segStartD(next) - d;
            _vL = km(toNext < 0.0 ? 0.0 : toNext);
            _uL = "km";
            _lL = nUp ? "오르막" : "내리막";
            _vR = (nUp ? "+" : "−") + fmt0(c.segDEle(next).abs());
            _uR = "m";
            _lR = nUp ? "상승" : "하강";
        } else {
            var toEnd = c.lengthM() - d;
            _vL = km(toEnd < 0.0 ? 0.0 : toEnd);
            _uL = "km";
            _lL = "도착까지";
            _vR = fmtInt(c.eleAt(d));
            _uR = "m";
            _lR = "현재 고도";
        }
    }

    // =============================================================== 그리기 (onUpdate)

    // status: 가로 범위 자리에 대신 띄울 상태 문구(명세 4.3), 없으면 null
    function draw(dc as Graphics.Dc, status as String?, statusTail as String) as Void {
        if (!ready) {
            return;
        }
        drawModeChip(dc);
        drawGrade(dc);
        paintColumns(dc);
        drawEdgeMarks(dc);
        drawEndPoint(dc);
        if (_mX != NONE) {
            drawMarker(dc, _mX, _mY, _off);
        }
        if (status != null) {
            statusLine(dc, status, statusTail, 0xe0e0e0);
        } else {
            dc.setColor(GRAY_LABEL, Graphics.COLOR_TRANSPARENT);
            text(dc, s / 2, (Y_SPAN * s).toNumber(), fonts.kr(FS_MIN * s), _span, Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawBottom(dc);
        drawDiag(dc);
    }

    // 진단 표시(설정): 그래프 위쪽에 검은 배경으로 두 줄
    function drawDiag(dc as Graphics.Dc) as Void {
        var a = diagA;
        var b = diagB;
        if (a == null) {
            return;
        }
        var f = fonts.kr(FS_MIN * s);
        var lh = Graphics.getFontHeight(f);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, by, bw, b == null ? lh : 2 * lh);
        dc.setColor(0xffd060, Graphics.COLOR_TRANSPARENT);
        dc.drawText(bx + 4, by, f, fit(dc, f, a, "", bw - 8), Graphics.TEXT_JUSTIFY_LEFT);
        if (b != null) {
            dc.drawText(bx + 4, by + lh, f, fit(dc, f, b, "", bw - 8), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // 상태 문구 (명세 4.3): 가로 범위 자리에 띄웁니다. 원 안에 들어가도록 앞부분만 줄이고 tail은 남깁니다.
    function statusLine(dc as Graphics.Dc, msg as String, tail as String, color as Number) as Void {
        var f = fonts.kr(FS_MIN * s);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        text(dc, s / 2, (Y_SPAN * s).toNumber(), f, fit(dc, f, msg, tail, (0.88 * s).toNumber()), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // 모드 표시. 코스 이탈 중에는 주황 원 아이콘과 함께 이탈 거리
    function drawModeChip(dc as Graphics.Dc) as Void {
        var px = FS_CHIP * s;
        var f = fonts.kr(px);
        var y = (Y_CHIP * s).toNumber();
        var tw = dc.getTextWidthInPixels(_chip, f);
        var gw = _off ? (px * 0.7).toNumber() : 0;
        var gap = _off ? (px * 0.25).toNumber() : 0;
        var x = s / 2 - (gw + gap + tw) / 2;
        if (_off) {
            var gy = (y - px * 0.36).toNumber();
            dc.setColor(WARN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + gw / 2, gy, (gw * 0.55).toNumber());
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            text(dc, x + gw / 2, gy + (px * 0.3).toNumber(), fonts.num(px * 0.8), "!", Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(0xf0f0f0, Graphics.COLOR_TRANSPARENT);
        text(dc, x + gw + gap, y, f, _chip, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // 현재 경사 큰 숫자와 경사 색 막대, 양옆 열(평균, 최대). 양옆 열은 큰 숫자와 같은 높이 띠 안에 둡니다.
    function drawGrade(dc as Graphics.Dc) as Void {
        var bigPx = FS_BIG * s;
        var pctPx = 0.07 * s;
        var gapN = 0.008 * s;
        var yb = (Y_BIG * s).toNumber();
        var lo = 0.0;
        var hi = s.toFloat();
        var fL = fonts.kr(FS_MIN * s);
        var fV = fonts.num(FS_SIDE_VALUE * s);
        var cxL = (X_SIDE_L * s).toNumber();
        var cxR = (X_SIDE_R * s).toNumber();
        if (_sides) {
            lo = cxL + max2(dc.getTextWidthInPixels("평균", fL), dc.getTextWidthInPixels(_sL2, fV)) / 2.0 + 0.02 * s;
            hi = cxR - max2(dc.getTextWidthInPixels("최대", fL), dc.getTextWidthInPixels(_sR2, fV)) / 2.0 - 0.02 * s;
        }
        var fBig = fonts.num(bigPx);
        var fPct = fonts.num(pctPx);
        var nw = dc.getTextWidthInPixels(_num, fBig).toFloat();
        var pw = dc.getTextWidthInPixels("%", fPct).toFloat();
        var tot = nw + gapN + pw;
        if (_sides && tot > hi - lo) {
            // 두 열 사이에 들어가도록 숫자와 %를 같은 비율로 줄입니다.
            // 글꼴 크기는 4 px 단위로 묶어 크기마다 글꼴이 새로 생기지 않게 합니다.
            var k = (hi - lo) / tot;
            fBig = fonts.num(((bigPx * k) / 4).toNumber() * 4);
            fPct = fonts.num(((pctPx * k) / 2).toNumber() * 2);
            gapN *= k;
            nw = dc.getTextWidthInPixels(_num, fBig).toFloat();
            pw = dc.getTextWidthInPixels("%", fPct).toFloat();
            tot = nw + gapN + pw;
        }
        var x0 = ((_sides ? (lo + hi) / 2.0 : s / 2.0) - tot / 2.0).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        text(dc, x0, yb, fBig, _num, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(GRAY_LABEL, Graphics.COLOR_TRANSPARENT);
        text(dc, (x0 + nw + gapN).toNumber(), yb, fPct, "%", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(colorOn ? COLORS[colorIndex(_g)] : 0x8c8c8c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x0, (yb + 0.014 * s).toNumber(), tot.toNumber(), (0.012 * s + 0.5).toNumber(), (0.005 * s).toNumber());
        if (_sides) {
            var ly1 = (Y_SIDE_LABEL * s).toNumber();
            var ly2 = (Y_SIDE_VALUE * s).toNumber();
            dc.setColor(GRAY_LABEL, Graphics.COLOR_TRANSPARENT);
            text(dc, cxL, ly1, fL, "평균", Graphics.TEXT_JUSTIFY_CENTER);
            text(dc, cxR, ly1, fL, "최대", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xf2f2f2, Graphics.COLOR_TRANSPARENT);
            text(dc, cxL, ly2, fV, _sL2, Graphics.TEXT_JUSTIFY_CENTER);
            text(dc, cxR, ly2, fV, _sR2, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // 채움(그래프 영역 위로 넘치는 부분은 잘라냄), 윤곽선, 기준선
    function paintColumns(dc as Graphics.Dc) as Void {
        var last = -1;
        for (var x = 0; x < bw; x++) {
            var v = _colY[x];
            if (v == COL_NONE || v > bh) {
                continue;
            }
            var y = by + v;
            var cc = _colC[x];
            if (cc != last) {
                dc.setColor(fillColor(cc), Graphics.COLOR_TRANSPARENT);
                last = cc;
            }
            dc.drawLine(bx + x, y, bx + x, base);
        }
        dc.setPenWidth(u > 1.15 ? 2 : 1);
        last = -1;
        for (var x = 1; x < bw; x++) {
            var ya = _colY[x - 1];
            var yb = _colY[x];
            if (ya == COL_NONE || yb == COL_NONE) {
                continue;
            }
            var cc = _colC[x];
            var lc = (cc % C_DIM == C_OUT) ? OUT_LINE : IN_LINE;
            if (cc >= C_DIM) {
                lc = dim(lc);
            }
            if (lc != last) {
                dc.setColor(lc, Graphics.COLOR_TRANSPARENT);
                last = lc;
            }
            dc.drawLine(bx + x - 1, by + (ya > bh ? bh : ya), bx + x, by + (yb > bh ? bh : yb));
        }
        dc.setPenWidth(1);
        dc.setColor(0x2c2c2c, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(bx, base + 1, bw, u > 1.0 ? u.toNumber() : 1);
    }

    // 화면 밖으로 잘린 앞쪽 고도: 오른쪽 가장자리의 삼각형 (위로 잘리면 ▲ 위쪽, 아래로 잘리면 ▼ 아래쪽).
    // 글자(예: "+38 m")는 36 px 이상으로 그리면 그래프를 너무 가려 삼각형만 남겼습니다.
    function drawEdgeMarks(dc as Graphics.Dc) as Void {
        var w = (8 * u).toNumber();
        var h = (10 * u).toNumber();
        var x = bx + bw - w - 2;
        dc.setColor(0xf0f0f0, Graphics.COLOR_TRANSPARENT);
        if (_above >= 1.0) {
            var y = by + 2;
            dc.fillPolygon([[x, y + h], [x + w, y], [x + 2 * w, y + h]]);
        }
        if (_below >= 1.0) {
            var y = base - 2;
            dc.fillPolygon([[x, y - h], [x + w, y], [x + 2 * w, y - h]]);
        }
    }

    // 구간 끝(또는 다음 구간 시작, 도착) 점. 글자 레이블은 뺐습니다(모드 표시와 색으로 알 수 있음).
    function drawEndPoint(dc as Graphics.Dc) as Void {
        if (_endX == NONE) {
            return;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_endX, _endY, (7.5 * u).toNumber());
        dc.setColor(_endColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_endX, _endY, (5.5 * u).toNumber());
    }

    // 현재 위치: 꼭짓점이 프로파일에 닿는 아래 방향 붉은 삼각형. 코스 이탈 중에는 주황 테두리만
    function drawMarker(dc as Graphics.Dc, px as Number, py as Number, off as Boolean) as Void {
        var hw = 9 * u;
        var h = 12 * u;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[px, py + 2], [px - hw - 2.5, py - h - 1.5], [px + hw + 2.5, py - h - 1.5]]);
        if (off) {
            dc.setColor(WARN, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(px, py, (px - hw).toNumber(), (py - h).toNumber());
            dc.drawLine((px - hw).toNumber(), (py - h).toNumber(), (px + hw).toNumber(), (py - h).toNumber());
            dc.drawLine((px + hw).toNumber(), (py - h).toNumber(), px, py);
            dc.setPenWidth(1);
        } else {
            dc.setColor(MARKER, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[px, py], [px - hw, py - h], [px + hw, py - h]]);
        }
    }

    // 아래쪽 두 칸과 구분선
    function drawBottom(dc as Graphics.Dc) as Void {
        value(dc, (X_COL_L * s).toNumber(), _vL, _uL, _lL);
        value(dc, (X_COL_R * s).toNumber(), _vR, _uR, _lR);
        dc.setColor(0x303030, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(s / 2, (0.735 * s).toNumber(), 1, (0.16 * s).toNumber());
    }

    // 하단 값 한 칸: 값(0.10S) + 단위(0.08S), 그 아래 레이블(0.08S). 가운데 cx
    function value(dc as Graphics.Dc, cx as Number, v as String, unit as String, label as String) as Void {
        var fv = fonts.num(FS_VALUE * s);
        var fu = fonts.kr(FS_MIN * s);
        var w1 = dc.getTextWidthInPixels(v, fv);
        var w2 = dc.getTextWidthInPixels(unit, fu);
        var gap = (0.012 * s).toNumber();
        var x = cx - (w1 + gap + w2) / 2;
        var vy = (Y_VALUE * s).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        text(dc, x, vy, fv, v, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(GRAY_LABEL, Graphics.COLOR_TRANSPARENT);
        text(dc, x + w1 + gap, vy, fu, unit, Graphics.TEXT_JUSTIFY_LEFT);
        text(dc, cx, (Y_LABEL * s).toNumber(), fu, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // =============================================================== 도움 함수

    // maxW를 넘으면 msg 끝을 잘라 "…"을 붙입니다. tail은 줄이지 않습니다.
    function fit(dc as Graphics.Dc, f as Graphics.FontType, msg as String, tail as String, maxW as Number) as String {
        var t = msg + tail;
        if (dc.getTextWidthInPixels(t, f) <= maxW) {
            return t;
        }
        var n = msg.length();
        while (n > 1) {
            n--;
            t = msg.substring(0, n) + "…" + tail;
            if (dc.getTextWidthInPixels(t, f) <= maxW) {
                break;
            }
        }
        return t;
    }

    // 폭을 넘으면 가운데에 가장 가까운 띄어쓰기에서 두 줄로 나눕니다. y는 첫 줄 기준선
    function wrapped(dc as Graphics.Dc, x as Number, y as Number, f as Graphics.FontType, t as String, maxW as Number) as Void {
        if (dc.getTextWidthInPixels(t, f) <= maxW) {
            text(dc, x, y, f, t, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var chars = t.toCharArray();
        var mid = chars.size() / 2;
        var cut = -1;
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ' && (cut < 0 || (i - mid).abs() < (cut - mid).abs())) {
                cut = i;
            }
        }
        if (cut < 0) {
            text(dc, x, y, f, fit(dc, f, t, "", maxW), Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        text(dc, x, y, f, t.substring(0, cut) as String, Graphics.TEXT_JUSTIFY_CENTER);
        text(dc, x, y + Graphics.getFontHeight(f), f, t.substring(cut + 1, chars.size()) as String, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // 기준선 y에 글자를 씁니다 (drawText의 y는 글자 위쪽이라 글꼴 ascent만큼 올립니다).
    function text(dc as Graphics.Dc, x as Number, yBase as Number, f as Graphics.FontType, t as String, just as Number) as Void {
        dc.drawText(x, yBase - Graphics.getFontAscent(f), f, t, just);
    }

    function X(d as Float) as Number {
        return (_xo + (d - _r0) * _kx + 0.5).toNumber();
    }

    function Y(e as Float) as Number {
        return (base - (e - _vb) * _ky + 0.5).toNumber();
    }

    function fillColor(cc as Number) as Number {
        var k = cc % C_DIM;
        var col = k < 2 * BINS ? COLORS[k] : k == C_GRAY ? GRAY_FILL : OUT_FILL;
        return cc >= C_DIM ? dim(col) : col;
    }

    // 지나온 부분: 검정 50%를 덮은 것과 같은 밝기
    static function dim(col as Number) as Number {
        return (col >> 1) & 0x7f7f7f;
    }

    // 경사 색 번호: 0–2 오르막(0 이상), 3–5 내리막
    static function colorIndex(g as Float) as Number {
        var a = g < 0 ? -g : g;
        var i = 0;
        while (i < EDGES.size() && a >= EDGES[i]) {
            i++;
        }
        return g >= 0 ? i : i + BINS;
    }

    static function clampF(v as Float, a as Float, b as Float) as Float {
        return v < a ? a : v > b ? b : v;
    }

    static function max2(a as Number, b as Number) as Number {
        return a > b ? a : b;
    }

    // 정수로 반올림한 문자열. format("%.0f")는 .5를 짝수 쪽으로 반올림해 프로토타입(toFixed)과 어긋날 수 있습니다.
    static function fmt0(v as Float) as String {
        return Math.round(v).toNumber().toString();
    }

    static function km(m as Float or Number) as String {
        return (m / 1000.0).format("%.2f");
    }

    // 천 단위 쉼표를 넣은 정수 (프로토타입 fmtInt)
    static function fmtInt(v as Float or Number) as String {
        var n = Math.round(v).toNumber();
        var neg = n < 0;
        n = n.abs();
        var str = "";
        while (n >= 1000) {
            var r = n % 1000;
            str = "," + (r < 10 ? "00" : r < 100 ? "0" : "") + r + str;
            n = n / 1000;
        }
        str = n + str;
        return neg ? "−" + str : str;
    }
}
