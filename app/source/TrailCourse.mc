import Toybox.Lang;

// 복원한 코스 바이너리 (명세 6.4). 헤더 20 B, 고도 N × u16 (0.1 m), 좌표 (N−1) × (i16, i16) 델타,
// 구간 레코드 × 10 B. 빅엔디언.
//
// 받은 조각(ByteArray)을 하나로 합치지 않고 조각 배열 그대로 둡니다. addAll로 합치면 늘어날 때마다 새 배열을
// 만들어 순간적으로 코스 크기의 두 배가 필요해, 100 km 코스(30.5 KB)에서 메모리가 모자랐습니다.
// 모든 값은 짝수 위치의 2바이트(구간 레코드의 1바이트 값 포함)이고 조각 크기도 짝수라 값이 두 조각에
// 걸치지 않습니다. 그래서 위치 o는 조각 o / part의 o % part번째 바이트입니다.
class TrailCourse {
    static const HEADER = 20;
    static const SEG_SIZE = 10;
    static const FLAT = 0;
    static const UP = 1;
    static const DOWN = 2;

    var id as String;
    var name as String;
    var parts as Array<ByteArray>;
    var part as Number = 1;    // 조각 크기 (마지막 조각만 더 작을 수 있음)
    var size as Number = 0;    // 전체 바이트 수
    var valid as Boolean = false;

    var interval as Number = 0;
    var n as Number = 0;
    var segCount as Number = 0;
    var lat0 as Number = 0;
    var lon0 as Number = 0;
    var coordOff as Number = 0;
    var segOff as Number = 0;
    var upCount as Number = 0;
    var downCount as Number = 0;
    var segNo as Array<Number> = []; // 유형별 번호 (오르막 1, 2, …). 평지는 0
    // 코스 전체 값 (매니페스트, 변환기가 계산). 시계에서 전체를 훑으면 워치독에 걸립니다.
    var gainM as Number = 0;
    var lossM as Number = 0;
    var eleMinDm as Number = 0; // 0.1 m
    var eleMaxDm as Number = 0;

    function initialize(courseId as String, courseName as String, pieces as Array<ByteArray>, manifest as Dictionary) {
        id = courseId;
        name = courseName;
        parts = pieces;
        part = pieces[0].size();
        for (var i = 0; i < pieces.size(); i++) {
            size += pieces[i].size();
        }
        parse();
        var keys = ["gain", "loss", "emin", "emax"];
        for (var k = 0; k < keys.size(); k++) {
            if (!(manifest[keys[k]] instanceof Number)) {
                valid = false;
                return;
            }
        }
        gainM = manifest["gain"] as Number;
        lossM = manifest["loss"] as Number;
        eleMinDm = manifest["emin"] as Number;
        eleMaxDm = manifest["emax"] as Number;
    }

    function parse() as Void {
        if (size < HEADER || part % 2 != 0 || u8(0) != 0x54 || u8(1) != 0x47 || u8(2) != 1) {
            return;
        }
        interval = u8(3);
        n = u16(4);
        segCount = u16(6);
        lat0 = (u16(8) << 16) | u16(10);   // 32비트 부호 있는 정수 (Number도 32비트라 그대로 맞음)
        lon0 = (u16(12) << 16) | u16(14);
        coordOff = HEADER + 2 * n;
        segOff = coordOff + 4 * (n - 1);
        if (interval == 0 || n < 2 || size != segOff + SEG_SIZE * segCount) {
            return;
        }
        segNo = new Array<Number>[segCount];
        for (var s = 0; s < segCount; s++) {
            var t = segType(s);
            if (t == UP) {
                upCount++;
                segNo[s] = upCount;
            } else if (t == DOWN) {
                downCount++;
                segNo[s] = downCount;
            } else {
                segNo[s] = 0;
            }
        }
        valid = true;
    }

    function u8(o as Number) as Number {
        return parts[o / part][o % part];
    }

    // 빅엔디언 u16. decodeNumber는 호출마다 옵션 Dictionary를 만들어 반복문에서 느리므로 바이트를 직접 읽습니다.
    // o는 짝수라 두 바이트가 같은 조각에 있습니다.
    function u16(o as Number) as Number {
        var p = parts[o / part];
        var k = o % part;
        return (p[k] << 8) | p[k + 1];
    }

    function s16(o as Number) as Number {
        var v = u16(o);
        return v >= 32768 ? v - 65536 : v;
    }

    function lengthM() as Number {
        return (n - 1) * interval;
    }

    // i번 포인트의 평활화 고도 (m)
    function ele(i as Number) as Float {
        return u16(HEADER + 2 * i) / 10.0;
    }

    function segType(s as Number) as Number {
        return u8(segOff + SEG_SIZE * s);
    }

    function segStart(s as Number) as Number {
        return u16(segOff + SEG_SIZE * s + 2);
    }

    function segEnd(s as Number) as Number {
        return u16(segOff + SEG_SIZE * s + 4);
    }

    // 구간 레코드의 나머지 값 (명세 6.4)
    function segDEle(s as Number) as Float {
        return s16(segOff + SEG_SIZE * s + 6) / 10.0;
    }

    // 평균 경사(%). 레코드의 평균 경사는 0.5% 단위라 표시할 때 반올림이 어긋나므로(10.66% → 10.5 → "10"),
    // 0.1 m 단위로 저장된 순 고도 변화를 길이로 나눠 계산합니다 (명세 4.4 평균 경사의 정의와 같음).
    function segAvg(s as Number) as Float {
        return segDEle(s) / (segEndD(s) - segStartD(s)) * 100.0;
    }

    function segStartD(s as Number) as Number {
        return segStart(s) * interval;
    }

    function segEndD(s as Number) as Number {
        return segEnd(s) * interval;
    }

    // ------------------------------------------------------------ 코스 계산 (프로토타입과 같은 규칙)

    // 코스 위치 d(m)의 평활화 고도. 이웃 두 점 사이를 선형 보간합니다.
    // 매초 여러 번 불리므로 ele()를 거치지 않습니다 (호출 깊이와 비용을 줄임).
    function eleAt(d as Float) as Float {
        var f = d / interval;
        var i = f.toNumber();
        if (f <= 0.0) {
            i = 0;
            f = 0.0;
        } else if (i >= n - 1) {
            i = n - 2;
            f = (n - 1).toFloat();
        }
        var o = HEADER + 2 * i;
        var e0 = u16(o);
        var e1 = u16(o + 2);
        return (e0 + (e1 - e0) * (f - i)) / 10.0;
    }

    // 현재 경사(%): 앞뒤 합쳐 w(m) 구간의 평균 경사. 코스 양 끝에서는 구간을 코스 안으로 자릅니다 (명세 4.4).
    function gradeAt(d as Float, w as Float) as Float {
        var L = lengthM().toFloat();
        var a = d - w / 2.0;
        var b = d + w / 2.0;
        if (a < 0.0) {
            a = 0.0;
        }
        if (b > L) {
            b = L;
        }
        if (b - a < 1.0) {
            return 0.0;
        }
        return (eleAt(b) - eleAt(a)) / (b - a) * 100.0;
    }

    // 소수 인덱스 idx가 속한 구간 번호 (구간 시작 인덱스로 이진 탐색)
    function segOf(idx as Float) as Number {
        var lo = 0;
        var hi = segCount - 1;
        while (lo < hi) {
            var mid = (lo + hi + 1) / 2;
            if (segStart(mid) <= idx) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    // s 뒤의 첫 오르막·내리막 구간. 없으면 −1
    function nextNonFlat(s as Number) as Number {
        for (var j = s + 1; j < segCount; j++) {
            if (segType(j) != FLAT) {
                return j;
            }
        }
        return -1;
    }

    // 앞쪽 최대 경사(%): d부터 구간 끝까지 100 m 창 경사의 최댓값. 내리막은 절대값 (명세 4.4)
    function maxAhead(d as Float, s as Number) as Float {
        var I = interval;
        var k = (100.0 / I + 0.5).toNumber();
        if (k < 1) {
            k = 1;
        }
        var sgn = segType(s) == DOWN ? -1.0 : 1.0;
        var e = segEnd(s);
        var i0 = (d / I).toNumber();
        if (i0 < segStart(s)) {
            i0 = segStart(s);
        }
        if (e - i0 <= k) {
            var dd = segEndD(s) - d;
            if (dd < 1.0) {
                dd = 1.0;
            }
            var v = sgn * (ele(e) - eleAt(d)) / dd * 100.0;
            return v > 0.0 ? v : 0.0;
        }
        var best = 0.0;
        for (var i = i0; i <= e - k; i++) {
            var v = sgn * (ele(i + k) - ele(i)) / (k * I);
            if (v > best) {
                best = v;
            }
        }
        return best * 100.0;
    }

    // d부터 구간 끝까지 오르는(up) 또는 내리는 변화만 더한 값(m). 반대 방향 변화는 빼지 않습니다 (명세 4.4)
    // 32비트 실수 오차가 쌓이지 않도록 온전한 스텝은 0.1 m 정수로 더하고, d가 걸친 첫 스텝만 실수로 계산합니다.
    function remainClimb(d as Float, s as Number, up as Boolean) as Float {
        var e = segEnd(s);
        var i = (d / interval).toNumber() + 1;
        if (i > e) {
            return 0.0;
        }
        var first = ele(i) - eleAt(d);
        var part = up ? first : -first;
        var sum = 0;
        var o = HEADER + 2 * i;
        var prev = u16(o);
        for (i = i + 1; i <= e; i++) {
            o += 2;
            var v = u16(o);
            var diff = up ? v - prev : prev - v;
            if (diff > 0) {
                sum += diff;
            }
            prev = v;
        }
        return (part > 0.0 ? part : 0.0) + sum / 10.0;
    }

    // [a, b] 구간의 최저·최고 고도. 결과는 out[0], out[1]에 씁니다 (매초 새 배열을 만들지 않음).
    function rangeMinMax(a as Float, b as Float, out as Array<Float>) as Void {
        var mn = eleAt(a);
        var mx = mn;
        var e = eleAt(b);
        if (e < mn) {
            mn = e;
        } else if (e > mx) {
            mx = e;
        }
        var i = (a / interval).toNumber() + 1;
        var end = b / interval;
        for (; i < end; i++) {
            var v = u16(HEADER + 2 * i) / 10.0;
            if (v < mn) {
                mn = v;
            } else if (v > mx) {
                mx = v;
            }
        }
        out[0] = mn;
        out[1] = mx;
    }
}
