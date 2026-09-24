import Toybox.Lang;
import Toybox.Math;

// 코스 좌표와 GPS 매칭 (명세 7.5 2순위).
//
// 바이너리의 좌표는 이웃 점과의 차이(델타)라서 i번 점을 알려면 앞의 델타를 모두 더해야 합니다.
// 코스 전체를 한 번에 더하면 워치독에 걸리므로(명세 8장), K점마다 절대 좌표를 적어 둔 체크포인트 표를
// 여러 compute()에 나눠 만들고(buildStep), 필요한 구간만 가까운 체크포인트부터 걸어서 읽습니다.
//
// 좌표 평면: 첫 점 기준 등장방형 평면(m). x = (경도 − 경도0) × kx, y = (위도 − 위도0) × ky
// (위도·경도는 1e-5° 정수 단위)
class CourseGeo {
    static const K = 16;                // 체크포인트 간격 (점). 100 km 코스에 312개, 메모리 약 3 KB
    static const BUILD_PER_STEP = 1000; // buildStep 한 번에 읽는 델타 수 (워치독 한도 안)
    static const R_E = 6371008.8;

    var course as TrailCourse;
    var ready as Boolean = false;
    var kx as Float;
    var ky as Float;

    var _cpLat as Array<Number>;
    var _cpLon as Array<Number>;
    var _buildI as Number = 1;
    var _curLat as Number;
    var _curLon as Number;

    function initialize(c as TrailCourse) {
        course = c;
        ky = (1.0e-5 * R_E * Math.PI / 180.0).toFloat();
        kx = (ky * Math.cos(c.lat0 * 1.0e-5 * Math.PI / 180.0)).toFloat();
        var m = (c.n + K - 1) / K;
        _cpLat = new Array<Number>[m];
        _cpLon = new Array<Number>[m];
        _cpLat[0] = c.lat0;
        _cpLon[0] = c.lon0;
        _curLat = c.lat0;
        _curLon = c.lon0;
    }

    // 체크포인트 표를 조금씩 만듭니다. 다 만들면 true.
    function buildStep() as Boolean {
        if (ready) {
            return true;
        }
        var n = course.n;
        var end = _buildI + BUILD_PER_STEP;
        if (end > n) {
            end = n;
        }
        var c = course;
        var o = c.coordOff + 4 * (_buildI - 1);
        for (var i = _buildI; i < end; i++) {
            _curLat += c.s16(o);
            _curLon += c.s16(o + 2);
            o += 4;
            if (i % K == 0) {
                _cpLat[i / K] = _curLat;
                _cpLon[i / K] = _curLon;
            }
        }
        _buildI = end;
        ready = end >= n;
        return ready;
    }

    // i번 점의 절대 좌표 (1e-5° 정수). 가까운 체크포인트부터 최대 K−1개 델타를 더합니다.
    function pointQ(i as Number) as [Number, Number] {
        var c = i / K;
        var lat = _cpLat[c];
        var lon = _cpLon[c];
        var cr = course;
        var o = cr.coordOff + 4 * (c * K);
        for (var j = c * K + 1; j <= i; j++) {
            lat += cr.s16(o);
            lon += cr.s16(o + 2);
            o += 4;
        }
        return [lat, lon];
    }

    function toX(lonQ as Number or Float) as Float {
        return ((lonQ - course.lon0) * kx).toFloat();
    }

    function toY(latQ as Number or Float) as Float {
        return ((latQ - course.lat0) * ky).toFloat();
    }

    // 코스 위치 f(소수 인덱스)의 평면 좌표와 진행 방향 단위 벡터 [x, y, tx, ty]. 시험 재생에 씁니다.
    function posAt(f as Float) as [Float, Float, Float, Float] {
        var n = course.n;
        var i = f.toNumber();
        if (i > n - 2) {
            i = n - 2;
        }
        if (i < 0) {
            i = 0;
        }
        var t = f - i;
        var a = pointQ(i);
        var b = pointQ(i + 1);
        var ax = toX(a[1]);
        var ay = toY(a[0]);
        var dx = toX(b[1]) - ax;
        var dy = toY(b[0]) - ay;
        var L = Math.sqrt(dx * dx + dy * dy).toFloat();
        if (L < 0.001) {
            L = 1.0;
        }
        return [ax + dx * t, ay + dy * t, dx / L, dy / L];
    }

    // 점 lo..hi+1 사이 선분들에 (px, py)를 투영해 가장 가까운 곳을 찾습니다.
    // 반환 [소수 인덱스, 거리(m), 비교값]. from ≥ 0이면 직전 위치 from(소수 인덱스)에서 뒤로 BACK_FREE_M,
    // 앞으로 fwdFree(m)를 넘는 후보에 벌점을 줍니다 (TrailConfig.JUMP_PENALTY).
    function nearest(px as Float, py as Float, lo as Number, hi as Number, from as Float, fwdFree as Float) as [Float, Float, Float] {
        var n = course.n;
        if (lo < 0) {
            lo = 0;
        }
        if (hi > n - 2) {
            hi = n - 2;
        }
        var I = course.interval;
        // lo번 점: 가까운 체크포인트부터 델타를 더합니다. 데이터 필드는 스택이 작아(전체 탐색에서 호출이 깊어짐)
        // pointQ·s16을 부르지 않고 조각 바이트를 여기서 바로 읽습니다.
        var parts = course.parts;
        var P = course.part;
        var c = lo / K;
        var latQ = _cpLat[c];
        var lonQ = _cpLon[c];
        var o = course.coordOff + 4 * (c * K);
        var pp;
        var k;
        var dv;
        for (var j = c * K + 1; j <= lo; j++) {
            pp = parts[o / P];
            k = o % P;
            dv = (pp[k] << 8) | pp[k + 1];
            latQ += dv >= 32768 ? dv - 65536 : dv;
            pp = parts[(o + 2) / P];
            k = (o + 2) % P;
            dv = (pp[k] << 8) | pp[k + 1];
            lonQ += dv >= 32768 ? dv - 65536 : dv;
            o += 4;
        }
        // 좌표 변환을 함수로 부르지 않고 여기서 계산합니다 (매초 도는 반복문이라 호출 비용이 큼).
        var lat0 = course.lat0;
        var lon0 = course.lon0;
        var fx = kx;
        var fy = ky;
        var ax = (lonQ - lon0) * fx;
        var ay = (latQ - lat0) * fy;
        var bestF = lo.toFloat();
        var bestD2 = 1.0e12;
        var bestCost = 1.0e12;
        for (var i = lo; i <= hi; i++) {
            pp = parts[o / P];
            k = o % P;
            dv = (pp[k] << 8) | pp[k + 1];
            latQ += dv >= 32768 ? dv - 65536 : dv;
            pp = parts[(o + 2) / P];
            k = (o + 2) % P;
            dv = (pp[k] << 8) | pp[k + 1];
            lonQ += dv >= 32768 ? dv - 65536 : dv;
            o += 4;
            var bx = (lonQ - lon0) * fx;
            var by = (latQ - lat0) * fy;
            var vx = bx - ax;
            var vy = by - ay;
            var l2 = vx * vx + vy * vy;
            var t = l2 > 0.0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0.0;
            if (t < 0.0) {
                t = 0.0;
            } else if (t > 1.0) {
                t = 1.0;
            }
            var ex = ax + vx * t - px;
            var ey = ay + vy * t - py;
            var d2 = ex * ex + ey * ey;
            var cost = d2;
            if (from >= 0.0) {
                var along = (i + t - from) * I;
                var over = along < 0.0 ? -along - TrailConfig.BACK_FREE_M : along - fwdFree;
                var dist = Math.sqrt(d2) + along.abs() * TrailConfig.ALONG_WEIGHT;
                if (over > 0.0) {
                    dist += over * TrailConfig.JUMP_PENALTY;
                }
                cost = dist * dist;
            }
            if (cost < bestCost) {
                bestCost = cost;
                bestD2 = d2;
                bestF = i + t;
            }
            ax = bx;
            ay = by;
        }
        return [bestF.toFloat(), Math.sqrt(bestD2).toFloat(), bestCost];
    }

    // 코스 전체 탐색: 체크포인트로 후보 3곳을 고른 뒤 각 후보 앞뒤 K점을 자세히 봅니다.
    // 코스 전체 점을 다 보지 않아 워치독에 걸리지 않습니다. 데이터 필드는 스택이 작아 후보는 필드에 둡니다.
    var _cand as Array<Number> = [-1, -1, -1];
    var _candD as Array<Float> = [0.0, 0.0, 0.0];

    function fullSearch(px as Float, py as Float) as [Float, Float, Float] {
        var cand = _cand;
        var cd = _candD;
        for (var k = 0; k < 3; k++) {
            cand[k] = -1;
            cd[k] = 1.0e12;
        }
        for (var c = 0; c < _cpLat.size(); c++) {
            var dx = toX(_cpLon[c]) - px;
            var dy = toY(_cpLat[c]) - py;
            var d = dx * dx + dy * dy;
            if (d < cd[2]) {
                var k = 2;
                while (k > 0 && d < cd[k - 1]) {
                    cand[k] = cand[k - 1];
                    cd[k] = cd[k - 1];
                    k--;
                }
                cand[k] = c;
                cd[k] = d;
            }
        }
        var best = nearest(px, py, cand[0] * K - K, cand[0] * K + K, -1.0, 0.0);
        for (var k = 1; k < 3; k++) {
            if (cand[k] >= 0) {
                var r = nearest(px, py, cand[k] * K - K, cand[k] * K + K, -1.0, 0.0);
                if (r[1] < best[1]) {
                    best = r;
                }
            }
        }
        return best;
    }
}
