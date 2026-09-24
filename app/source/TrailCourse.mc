import Toybox.Lang;

// 복원한 코스 바이너리 (명세 6.4). 데이터는 ByteArray 하나에 두고 필요할 때 읽습니다.
//   헤더 20 B, 고도 N × u16 (0.1 m), 좌표 (N−1) × (i16, i16) 델타, 구간 레코드 × 10 B. 빅엔디언.
class TrailCourse {
    const HEADER = 20;
    const SEG_SIZE = 10;
    const FLAT = 0;
    const UP = 1;
    const DOWN = 2;

    var id as String;
    var name as String;
    var data as ByteArray;
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

    function initialize(courseId as String, courseName as String, bytes as ByteArray) {
        id = courseId;
        name = courseName;
        data = bytes;
        parse();
    }

    function parse() as Void {
        var b = data;
        if (b.size() < HEADER || b[0] != 0x54 || b[1] != 0x47 || b[2] != 1) {
            return;
        }
        interval = b[3];
        n = u16(4);
        segCount = u16(6);
        lat0 = b.decodeNumber(Lang.NUMBER_FORMAT_SINT32, { :offset => 8, :endianness => Lang.ENDIAN_BIG }) as Number;
        lon0 = b.decodeNumber(Lang.NUMBER_FORMAT_SINT32, { :offset => 12, :endianness => Lang.ENDIAN_BIG }) as Number;
        coordOff = HEADER + 2 * n;
        segOff = coordOff + 4 * (n - 1);
        if (interval == 0 || n < 2 || b.size() != segOff + SEG_SIZE * segCount) {
            return;
        }
        for (var s = 0; s < segCount; s++) {
            var t = segType(s);
            if (t == UP) {
                upCount++;
            } else if (t == DOWN) {
                downCount++;
            }
        }
        valid = true;
    }

    function u16(offset as Number) as Number {
        return data.decodeNumber(Lang.NUMBER_FORMAT_UINT16, { :offset => offset, :endianness => Lang.ENDIAN_BIG }) as Number;
    }

    function lengthM() as Number {
        return (n - 1) * interval;
    }

    // i번 포인트의 평활화 고도 (m)
    function ele(i as Number) as Float {
        return u16(HEADER + 2 * i) / 10.0;
    }

    function segType(s as Number) as Number {
        return data[segOff + SEG_SIZE * s];
    }

    function segStart(s as Number) as Number {
        return u16(segOff + SEG_SIZE * s + 2);
    }

    function segEnd(s as Number) as Number {
        return u16(segOff + SEG_SIZE * s + 4);
    }
}
