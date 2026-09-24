import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;

// 코스 다운로드 (명세 7.2)
//   1. current.txt?t=<now>로 서버의 현재 코스 ID를 받습니다.
//   2. 이미 완성된 코스면 끝냅니다 (활성 코스가 아니면 활성으로 바꿉니다).
//   3. c/<id>/m.txt로 조각 수와 바이트 수를 받습니다.
//   4. 조각을 0번부터 차례로 받아 받는 즉시 저장합니다. 끊겼으면 dl에 남은 번호부터 이어받습니다.
//   5. 모두 받으면 복원해 크기와 SHA-256(코스 ID)을 확인하고, 맞을 때만 active를 바꿉니다.
//   6. 활성 코스와 직전 코스만 남기고 지웁니다.
//
// 요청은 한 번에 하나만 보내고, 항상 tick()(= compute())에서 시작합니다. 콜백은 결과만 기록합니다.
// 데이터 필드에서는 Timer를 쓸 수 없고, 콜백에서 바로 다음 요청을 보내면 즉시 실패가 연쇄로
// 이어져 스택이 넘칠 수 있기 때문입니다.
class CourseSync {
    const ST_IDLE = 0;
    const ST_CURRENT = 1;
    const ST_MANIFEST = 2;
    const ST_CHUNK = 3;
    const ST_VERIFY = 4;
    const ST_DONE = 5;
    const ST_FAILED = 6;

    var state as Number = 0;

    var _id as String? = null;
    var _chunks as Number = 0;
    var _next as Number = 0;
    var _name as String = "";

    var _waiting as Boolean = false;
    var _sentAt as Number = 0;
    var _reqNo as Number = 0;
    var _tries as Number = 0;
    var _retryAt as Number = 0;

    var _respReady as Boolean = false;
    var _respCode as Number = 0;
    var _respData as String? = null;

    var _loaded as TrailCourse? = null;
    var _message as String? = null;
    var _messageTail as String = "";
    var _messageUntil as Number = 0;

    function initialize() {
    }

    function start() as Void {
        state = ST_CURRENT;
        _tries = 0;
        _retryAt = 0;
        log("sync start");
    }

    // 새 코스를 적용했으면 한 번만 돌려줍니다.
    function takeLoaded() as TrailCourse? {
        var c = _loaded;
        _loaded = null;
        return c;
    }

    function isDownloading() as Boolean {
        return state == ST_MANIFEST || state == ST_CHUNK || state == ST_VERIFY;
    }

    // 시작 전(IDLE)도 확인 중으로 봅니다. 첫 compute() 전에 "코스 없음"이 잠깐 보이지 않게 합니다.
    function isChecking() as Boolean {
        return state == ST_IDLE || state == ST_CURRENT;
    }

    // "3/7" 형식의 진행 상황. 지금 받고 있는 조각 번호 / 전체
    function progressText() as String {
        if (_chunks <= 0) {
            return "";
        }
        var cur = _next + 1;
        if (cur > _chunks) {
            cur = _chunks;
        }
        return cur + "/" + _chunks;
    }

    // 표시할 문구. 폭이 모자라면 앞부분만 줄이고 messageTail()은 그대로 붙입니다.
    function message(now as Number) as String? {
        return (_message != null && now < _messageUntil) ? _message : null;
    }

    function messageTail() as String {
        return _messageTail;
    }

    // ------------------------------------------------------------------ tick

    function tick(now as Number) as Void {
        if (state == ST_IDLE || state == ST_DONE || state == ST_FAILED) {
            return;
        }
        if (_respReady) {
            // 응답 처리 뒤 같은 tick에서 바로 다음 요청을 보냅니다 (조각당 약 1초).
            _respReady = false;
            _waiting = false;
            handleResponse(now);
            if (state == ST_DONE || state == ST_FAILED) {
                return;
            }
        }
        if (_waiting) {
            if (now - _sentAt > TrailConfig.TIMEOUT_MS) {
                _waiting = false;
                _reqNo++; // 늦게 온 응답은 무시
                failTry(Communications.NETWORK_REQUEST_TIMED_OUT, now);
            }
            return;
        }
        if (now < _retryAt) {
            return;
        }
        if (state == ST_CURRENT) {
            send("current.txt", { "t" => Time.now().value() }, now);
        } else if (state == ST_MANIFEST) {
            send("c/" + _id + "/m.txt", null, now);
        } else if (state == ST_CHUNK) {
            send("c/" + _id + "/" + _next + ".txt", null, now);
        } else if (state == ST_VERIFY) {
            verify(now);
        }
    }

    function send(path as String, params as Dictionary<Object, Object>?, now as Number) as Void {
        _reqNo++;
        _waiting = true;
        _sentAt = now;
        log("GET " + path);
        try {
            Communications.makeWebRequest(TrailConfig.BASE_URL + path, params, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN,
                :context => _reqNo
            }, method(:onResponse));
        } catch (e) {
            // 즉시 실패해도 여기서 다시 부르지 않고 다음 tick에서 재시도합니다.
            _waiting = false;
            log("request throw " + e.getErrorMessage());
            failTry(-1, now);
        }
    }

    function onResponse(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null, context as Object) as Void {
        if (!_waiting || !(context instanceof Number) || (context as Number) != _reqNo) {
            return;
        }
        _respCode = code;
        _respData = (data instanceof String) ? data as String : null;
        _respReady = true;
    }

    function handleResponse(now as Number) as Void {
        var data = _respData;
        _respData = null;
        if (_respCode != 200 || data == null) {
            log("response " + _respCode);
            failTry(_respCode, now);
            return;
        }
        _tries = 0;
        if (state == ST_CURRENT) {
            onCurrent(data, now);
        } else if (state == ST_MANIFEST) {
            onManifest(data, now);
        } else if (state == ST_CHUNK) {
            onChunk(data, now);
        }
    }

    function failTry(code as Number, now as Number) as Void {
        _tries++;
        if (_tries >= TrailConfig.MAX_TRIES) {
            log("give up after " + _tries + " tries, code " + code);
            fail(errorText(code), now);
            _messageTail = " (" + code + ")"; // 폭이 모자라도 오류 코드는 남깁니다
        } else {
            _retryAt = now + TrailConfig.RETRY_MS;
        }
    }

    function fail(text as String, now as Number) as Void {
        state = ST_FAILED;
        setMessage(text, now);
    }

    // ------------------------------------------------------------- steps

    function onCurrent(text as String, now as Number) as Void {
        var id = trim(text);
        if (!isCourseId(id)) {
            fail("서버 코스 ID 오류", now);
            return;
        }
        _id = id;
        var active = CourseStore.getString(CourseStore.K_ACTIVE);
        log("server current " + id + ", active " + active);
        if (CourseStore.isComplete(id)) {
            if (!id.equals(active)) {
                // 저장해 둔 다른 코스로 바뀜: 다시 받지 않고 활성 코스만 바꿉니다.
                var c = CourseStore.loadCourse(id, false);
                if (c != null) {
                    activate(c, now);
                    return;
                }
                CourseStore.deleteCourse(id);
            } else {
                state = ST_DONE;
                return;
            }
        }
        state = ST_MANIFEST;
    }

    function onManifest(text as String, now as Number) as Void {
        var m = parseManifest(text);
        var id = _id as String;
        var chunks = m["chunks"];
        var bytes = m["bytes"];
        if (!"1".equals(m["v"] as String?) || !id.equals(m["id"] as String?) || !(chunks instanceof Number) || !(bytes instanceof Number)
                || chunks <= 0 || chunks > CourseStore.MAX_CHUNKS || bytes <= 0) {
            fail("매니페스트 오류", now);
            return;
        }
        var name = m["name"];
        _name = (name instanceof String) ? name as String : id;
        _chunks = chunks as Number;
        var stored = { "name" => _name, "bytes" => bytes, "chunks" => _chunks } as Dictionary<String, Application.Storage.ValueType>;
        var keys = ["len", "gain", "loss", "emin", "emax"];
        for (var k = 0; k < keys.size(); k++) {
            var v = m[keys[k]];
            if (!(v instanceof Number)) {
                fail("매니페스트 오류", now);
                return;
            }
            stored[keys[k]] = v;
        }
        CourseStore.put(CourseStore.manifestKey(id), stored);

        // 같은 코스를 받다 끊겼으면 이어받고, 다른 코스를 받다 말았으면 그 조각을 지웁니다.
        _next = 0;
        var dl = CourseStore.get(CourseStore.K_DL);
        if (dl instanceof Dictionary) {
            var dlId = dl["id"];
            var dlNext = dl["next"];
            if (id.equals(dlId) && dlNext instanceof Number && dlNext <= _chunks) {
                _next = dlNext as Number;
                log("resume " + id + " from chunk " + _next);
            } else if (dlId instanceof String && !isKept(dlId)) {
                CourseStore.deleteCourse(dlId as String);
            }
        }
        saveProgress();
        state = _next >= _chunks ? ST_VERIFY : ST_CHUNK;
    }

    function onChunk(text as String, now as Number) as Void {
        var id = _id as String;
        var piece = CourseStore.decodeBase64(text);
        if (piece == null || piece.size() == 0) {
            failTry(-2000, now);
            return;
        }
        var ok = CourseStore.putChunk(id, _next, piece, text);
        if (!ok) {
            // 저장 공간 부족: 직전 코스를 지우고 한 번 더 시도합니다.
            var prev = CourseStore.getString(CourseStore.K_PREV);
            if (prev != null && !prev.equals(id)) {
                CourseStore.deleteCourse(prev);
                CourseStore.remove(CourseStore.K_PREV);
                ok = CourseStore.putChunk(id, _next, piece, text);
            }
        }
        if (!ok) {
            fail("저장 공간 부족", now);
            return;
        }
        log("stored chunk " + (_next + 1) + "/" + _chunks + " (" + piece.size() + " B) mem " + (System.getSystemStats().usedMemory / 1024) + "k");
        _next++;
        saveProgress();
        if (_next >= _chunks) {
            state = ST_VERIFY;
        }
    }

    function verify(now as Number) as Void {
        var id = _id as String;
        var c = CourseStore.loadCourse(id, true);
        if (c == null) {
            CourseStore.deleteCourse(id);
            CourseStore.remove(CourseStore.K_DL);
            fail("코스 검증 실패", now);
            return;
        }
        var m = CourseStore.manifest(id) as Dictionary;
        m["ok"] = 1;
        CourseStore.put(CourseStore.manifestKey(id), m);
        CourseStore.remove(CourseStore.K_DL);
        log("verified " + id + " (" + c.data.size() + " B, sha256 ok) mem " + (System.getSystemStats().usedMemory / 1024) + "k");
        activate(c, now);
    }

    // c를 활성 코스로 만들고, 활성·직전 코스 말고는 지웁니다.
    function activate(c as TrailCourse, now as Number) as Void {
        var oldActive = CourseStore.getString(CourseStore.K_ACTIVE);
        var oldPrev = CourseStore.getString(CourseStore.K_PREV);
        if (oldActive != null && !oldActive.equals(c.id)) {
            if (oldPrev != null && !oldPrev.equals(c.id) && !oldPrev.equals(oldActive)) {
                CourseStore.deleteCourse(oldPrev);
            }
            CourseStore.put(CourseStore.K_PREV, oldActive);
        } else if (oldPrev != null && oldPrev.equals(c.id)) {
            CourseStore.remove(CourseStore.K_PREV);
        }
        CourseStore.put(CourseStore.K_ACTIVE, c.id);
        _loaded = c;
        state = ST_DONE;
        setMessage("새 코스 적용: " + c.name, now);
        _messageTail = " " + (c.lengthM() / 1000.0).format("%.1f") + " km";
        log("active " + c.id + ", prev " + CourseStore.getString(CourseStore.K_PREV));
    }

    // ------------------------------------------------------------- helpers

    function isKept(id as String) as Boolean {
        return id.equals(CourseStore.getString(CourseStore.K_ACTIVE)) || id.equals(CourseStore.getString(CourseStore.K_PREV));
    }

    function saveProgress() as Void {
        CourseStore.put(CourseStore.K_DL, { "id" => _id, "next" => _next } as Dictionary<String, Application.Storage.ValueType>);
    }

    function setMessage(text as String, now as Number) as Void {
        _message = text;
        _messageTail = "";
        _messageUntil = now + TrailConfig.MESSAGE_MS;
        log("message: " + text);
    }

    function errorText(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            return "폰 연결 없음";
        } else if (code == Communications.NETWORK_RESPONSE_TOO_LARGE) {
            return "응답이 너무 큼";
        } else if (code == Communications.NETWORK_RESPONSE_OUT_OF_MEMORY) {
            return "메모리 부족";
        } else if (code == Communications.SECURE_CONNECTION_REQUIRED) {
            return "HTTPS 오류";
        } else if (code == Communications.NETWORK_REQUEST_TIMED_OUT || code == Communications.BLE_HOST_TIMEOUT) {
            return "응답 없음";
        } else if (code == 404) {
            return "파일 없음";
        }
        return "받기 오류";
    }

    // "key=value" 줄들을 읽습니다. 숫자 값은 Number로 바꿉니다 (v는 문자열 그대로).
    function parseManifest(text as String) as Dictionary {
        var out = {};
        var rest = text;
        while (rest.length() > 0) {
            var nl = rest.find("\n");
            var line = nl == null ? rest : rest.substring(0, nl) as String;
            rest = nl == null ? "" : rest.substring(nl + 1, rest.length()) as String;
            var eq = line.find("=");
            if (eq == null) {
                continue;
            }
            var key = line.substring(0, eq) as String;
            var val = trim(line.substring(eq + 1, line.length()) as String);
            if (key.equals("bytes") || key.equals("chunks") || key.equals("len") || key.equals("gain")
                    || key.equals("loss") || key.equals("emin") || key.equals("emax")) {
                out[key] = val.toNumber();
            } else {
                out[key] = val;
            }
        }
        return out;
    }

    function trim(s as String) as String {
        var chars = s.toCharArray();
        var a = 0;
        var b = chars.size();
        while (a < b && isSpace(chars[a])) {
            a++;
        }
        while (b > a && isSpace(chars[b - 1])) {
            b--;
        }
        return s.substring(a, b) as String;
    }

    function isSpace(c as Char) as Boolean {
        return c == ' ' || c == '\n' || c == '\r' || c == '\t';
    }

    function isCourseId(s as String) as Boolean {
        if (s.length() != 10) {
            return false;
        }
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
                return false;
            }
        }
        return true;
    }

    function log(text as String) as Void {
        System.println(text);
    }
}
