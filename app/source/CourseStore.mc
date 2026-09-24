import Toybox.Application;
import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;

// 코스 저장소 (명세 7.3). 키 구성:
//   active        활성 코스 ID
//   prev          직전 코스 ID
//   m_<id>        매니페스트 {name, bytes, chunks, len, gain, loss, emin, emax, ok}. ok=1이면 검증까지 끝난 완성 코스
//   c_<id>_<i>    조각. Base64를 풀어 ByteArray로 저장 (SDK 9.2의 Storage.ValueType에 ByteArray 포함,
//                 실기기·시뮬레이터에서 저장 확인). 거부되는 기기에서는 Base64 문자열 그대로 저장합니다.
//   dl            진행 중인 다운로드 {id, next}
module CourseStore {
    const K_ACTIVE = "active";
    const K_PREV = "prev";
    const K_DL = "dl";
    // 매니페스트를 잃은 코스를 지울 때 확인할 최대 조각 수 (100 km 코스가 7조각)
    const MAX_CHUNKS = 64;

    function get(key as String) as Application.Storage.ValueType? {
        try {
            return Application.Storage.getValue(key);
        } catch (e) {
            return null;
        }
    }

    // 저장 공간이 모자라면 false를 돌려줍니다. 다른 예외는 그대로 올립니다.
    function put(key as String, value as Application.Storage.ValueType) as Boolean {
        try {
            Application.Storage.setValue(key, value);
            return true;
        } catch (e instanceof Lang.StorageFullException) {
            return false;
        }
    }

    function remove(key as String) as Void {
        try {
            Application.Storage.deleteValue(key);
        } catch (e) {
        }
    }

    function getString(key as String) as String? {
        var v = get(key);
        return (v instanceof String) ? v as String : null;
    }

    function manifestKey(id as String) as String {
        return "m_" + id;
    }

    function chunkKey(id as String, i as Number) as String {
        return "c_" + id + "_" + i;
    }

    function manifest(id as String) as Dictionary? {
        var v = get(manifestKey(id));
        return (v instanceof Dictionary) ? v as Dictionary : null;
    }

    function isComplete(id as String) as Boolean {
        var m = manifest(id);
        var ok = (m != null) ? m["ok"] : null;
        // emax가 없는 매니페스트는 예전 형식이라 다시 받습니다.
        return ok instanceof Number && ok == 1 && (m as Dictionary)["emax"] instanceof Number;
    }

    // Base64 조각을 풀어 저장합니다. 저장 공간이 모자라면 false.
    function putChunk(id as String, i as Number, piece as ByteArray, base64 as String) as Boolean {
        var key = chunkKey(id, i);
        try {
            return put(key, piece);
        } catch (e instanceof Lang.StorageFullException) {
            return false;
        } catch (e) {
            // ByteArray를 받지 않는 기기: 문자열로 저장
            System.println("store bytearray rejected, fallback to base64: " + e.getErrorMessage());
            return put(key, base64);
        }
    }

    function getChunk(id as String, i as Number) as ByteArray? {
        var v = get(chunkKey(id, i));
        if (v instanceof ByteArray) {
            return v as ByteArray;
        }
        if (v instanceof String) {
            return decodeBase64(v as String);
        }
        return null;
    }

    function decodeBase64(text as String) as ByteArray? {
        try {
            var b = StringUtil.convertEncodedString(text, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            });
            return (b instanceof ByteArray) ? b as ByteArray : null;
        } catch (e) {
            return null;
        }
    }

    // 코스 하나의 매니페스트와 조각을 모두 지웁니다.
    function deleteCourse(id as String?) as Void {
        if (id == null) {
            return;
        }
        var m = manifest(id);
        var n = (m != null && m["chunks"] instanceof Number) ? m["chunks"] as Number : MAX_CHUNKS;
        for (var i = 0; i < n; i++) {
            remove(chunkKey(id, i));
        }
        remove(manifestKey(id));
        System.println("deleted course " + id);
    }

    // 조각을 모아 코스를 복원합니다 (명세 7.4). verify가 true면 SHA-256 앞 10자리를 ID와 비교합니다.
    // 조각은 하나씩 읽어 붙이고 바로 버립니다. 문제가 있으면 null.
    function loadCourse(id as String, verify as Boolean) as TrailCourse? {
        var m = manifest(id);
        if (m == null) {
            return null;
        }
        var chunks = m["chunks"];
        var total = m["bytes"];
        if (!(chunks instanceof Number) || !(total instanceof Number)) {
            return null;
        }
        var hash = verify ? new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 }) : null;
        var bytes = []b;
        for (var i = 0; i < chunks; i++) {
            var piece = getChunk(id, i);
            if (piece == null) {
                System.println("load " + id + ": chunk " + i + " missing");
                return null;
            }
            if (hash != null) {
                hash.update(piece);
            }
            bytes.addAll(piece);
        }
        if (bytes.size() != total) {
            System.println("load " + id + ": size " + bytes.size() + " != " + total);
            return null;
        }
        if (hash != null) {
            var hex = StringUtil.convertEncodedString(hash.digest(), {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
            }) as String;
            var head = (hex.substring(0, 10) as String).toLower();
            if (!head.equals(id)) {
                System.println("load " + id + ": sha256 mismatch " + head);
                return null;
            }
        }
        var name = m["name"];
        var course = new TrailCourse(id, (name instanceof String) ? name as String : id, bytes, m);
        return course.valid ? course : null;
    }

}
