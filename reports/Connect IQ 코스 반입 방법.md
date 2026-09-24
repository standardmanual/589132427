# 데이터 필드가 코스를 직접 내려받게 하라

fēnix 8 AMOLED용 개인 고도 프로파일 필드에 앱을 다시 빌드하지 않고 코스를 넣는 가장 현실적인 구조는 이렇다. **활동 화면이 열려 있는 동안 데이터 필드가 직접 `Communications.makeWebRequest`로 개인 HTTPS 주소에서 코스를 조각(청크) 단위로 받고, 받은 조각을 곧바로 `Application.Storage`에 저장한다.** API 5.0.0(Connect IQ System 7)부터 Communications 모듈을 포그라운드 데이터 필드에서도 쓸 수 있다. SDK 기기 파일상 fēnix 8의 API 레벨은 5.1.1–6.0.0이다. 따라서 5분 간격, 30초 수명, 약 8 KB 전달 한도에 묶인 백그라운드 서비스를 거칠 필요가 없고, 오픈소스 데이터 필드 Breadcrumb이 fēnix 8에서 이 방식을 이미 쓰고 있다. 다른 경로는 역할이 제한된다. 앱 설정 문자열은 실무 한도가 필드당 약 256자, 설정 전체 약 8 KB(포럼 전언)여서 6–30 KB 코스를 실을 수 없으므로 코스 선택용 ID나 URL을 담는 데만 쓴다. 시계에 불러온 네이티브 코스는 `Activity.Info`의 스칼라 값 10개(`distanceToDestination` 등)만 내놓고, 궤적·고도 프로파일·ClimbPro 정보는 2025년 8월 문서 기준으로 어떤 API로도 읽을 수 없다. 폰 컴패니언 앱은 Breadcrumb·climbBrooo가 실제로 쓰는 검증된 대안이지만 Android SDK 기준 메시지당 직렬화 16,384바이트 한도가 있다. 앱을 직접 만들어야 하므로, 폰에 인터넷이 없는 곳에서 코스를 보내야 할 때만 그 비용을 치를 가치가 있다. 구조를 확정하기 전에 실기기에서 확인할 핵심은 네 가지다. 타이머 시작 전 화면에서 포그라운드 요청이 동작하는지, USB 사이드로드 설치에서도 웹 요청이 되는지, 응답 크기 한계(-402/-403)가 어디인지, Storage 총량이 얼마이고 ByteArray를 저장할 수 있는지다.

> **근거 표기 방식.** **[검증]**은 1차 자료로 확인한 내용이다. 1차 자료는 가민 SDK API 문서의 GitHub 미러(tkafka 판 2024-12-11 생성, ztuskes 판 2025-08-11 생성), GitHub에 올라온 SDK 기기 파일(`compiler.json`) 사본, 가민의 GitHub·Maven Central 산출물, 실제로 동작하는 오픈소스 코드를 말한다. **[포럼]**은 forums.garmin.com·블로그 글을 검색 스니펫으로만 본 전언이며 전문과 날짜는 확인하지 못했다. **[추론]**은 연구 노트나 이 보고서의 판단이다. developer.garmin.com, forums.garmin.com, apps.garmin.com은 조사 환경에서 직접 열리지 않았다. 그래서 developer.garmin.com 링크는 공식 주소를 가리키되 문구는 미러로 확인했다. 2025년 8월 이후 SDK에서 추가된 API는 확인하지 못했다.

## (1) API 5.0부터 데이터 필드는 백그라운드 없이 웹 요청을 보낸다

### 포그라운드 요청: 활동 화면이 열리면 곧바로 이어받기

Communications 모듈 문서에는 **"This module was made available to foreground data fields with API 5.0.0"**라고 적혀 있다. 대상 앱 유형에는 Data Field와 Background가 함께 있고, `Communications` 권한이 필요하다 **[검증]** ([Toybox.Communications, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)). 가민의 System 7 발표도 "API 5.0.0에서 데이터 필드는 메인 애플리케이션 안에서 일부(select) Communications API를 쓸 수 있다"고 밝혔다. 다만 '일부'에 무엇이 들어가는지는 스니펫에 나오지 않는다 **[포럼]** ([Welcome to System 7](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/welcome-to-system-7)). fēnix 8의 기기 파일은 스냅샷에 따라 `connectIQVersion`을 5.1.1, 5.2.0, 6.0.0으로 기록하므로 모두 이 조건을 넘는다 **[검증]** ([openhab fenix847mm/compiler.json](https://github.com/openhab/openhab-garmin/blob/HEAD/.github/ConnectIQ/Devices/fenix847mm/compiler.json); [granbike 기기 파일 모음](https://github.com/mgallesio/granbike-face-builder/tree/HEAD/backend/devices)). 실제 선례는 Breadcrumb이다. 매니페스트는 `type="datafield"`, `minApiLevel="5.0.0"`으로 `fenix843mm`·`fenix847mm`·`fenix8solar47mm`·`fenix8solar51mm`·`fenix8pro47mm`를 대상으로 한다. `Background` 권한 없이 포그라운드 코드에서 `makeWebRequest`와 `makeImageRequest`를 호출한다 **[검증]** ([breadcrumb-garmin manifest.xml](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/manifest.xml); [WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)).

Breadcrumb 소스 주석에는 구현자가 미리 알아야 할 함정 두 가지가 남아 있다. 첫째, **데이터 필드에서는 `Toybox.Timer`를 쓸 수 없다**("Module 'Toybox.Timer' not available to 'Data Field'"). 그래서 다음 요청은 응답 콜백이나 약 1초마다 불리는 `compute()`에서 시작해야 한다. 둘째, `BLE_CONNECTION_UNAVAILABLE`(-104) 같은 오류가 동기적으로 돌아올 때 그 자리에서 재시도하면 스택 오버플로가 난다. 작성자는 이를 피하려고 요청 대기열과 미처리 건수를 따로 관리한다 **[검증: 오픈소스 코드 주석]** ([WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)). 동시 요청 수는 공식 문서에 "제한된다"고만 나오고, 넘치면 `BLE_QUEUE_FULL`(-101)이 돌아온다 **[검증]**. "동시 3건까지"라는 수치는 오래된 포럼 발언이다 **[포럼]** ([Can a watchface make several webrequests](https://forums.garmin.com/forum/developers/connect-iq/1303819-can-a-watchface-make-several-webrequests)). 따라서 요청은 한 번에 하나씩 순차로 잇는다. `:context` 옵션에 청크 번호를 담으면 3인자 콜백에서 그 번호를 돌려받을 수 있다 **[검증]** ([Communications, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)).

응답 크기에는 공식 최대치가 없다. 병목은 형식이다. JSON 응답은 받는 쪽 프로세스 메모리 안에서 Dictionary·Array로 파싱된다. 5 KB JSON이 파싱 뒤 약 20 KB를 차지했다는 보고가 있고, 이렇게 메모리가 모자라면 `NETWORK_RESPONSE_OUT_OF_MEMORY`(-403, API 3.0.0)가 난다 **[포럼]** ([-403 despite enough free memory](https://forums.garmin.com/developer/connect-iq/f/discussion/289418/makewebrequest-error--403-despite-enough-free-memory); [Memory usage in makewebrequest](https://forums.garmin.com/developer/connect-iq/f/discussion/163995/memory-usage-in-makewebrequest)). 응답 자체가 너무 크면 `NETWORK_RESPONSE_TOO_LARGE`(-402)가 난다. 기준은 문서에 없고, JSON 약 32 KB에서 걸렸다는 사람과 약 44 KB까지 받았다는 사람이 있으며 기종마다 다르다 **[포럼]** ([Understanding -402 Response Limit](https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest)). `:responseType`을 **`HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN`(값 5, API 3.0.0)**으로 지정하면 파싱 없이 문자열 하나로 받는다. 이때 서버의 Content-Type은 "text/plain"이어야 한다 **[검증]** ([Communications, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)). 이 프로젝트에서 신경 쓸 오류 코드를 정리하면 아래와 같다.

| 코드 | 이름 (API 레벨) | 이 프로젝트에서의 의미 |
|---|---|---|
| -104 | `BLE_CONNECTION_UNAVAILABLE` | 폰 연결 없음. iOS에서 Garmin Connect가 잠들었을 때 흔함 |
| -101 | `BLE_QUEUE_FULL` | 동시 요청 과다. 순차 연쇄로 회피 |
| -2 / -300 | `BLE_HOST_TIMEOUT` / `NETWORK_REQUEST_TIMED_OUT` | 전송 경로 시간 초과. 재시도 대상 |
| -402 | `NETWORK_RESPONSE_TOO_LARGE` (1.0.0) | 청크가 너무 큼. 청크 크기 축소 |
| -403 | `NETWORK_RESPONSE_OUT_OF_MEMORY` (3.0.0) | 응답 처리 중 메모리 부족. text/plain 사용, 청크 축소 |
| -1000 | `STORAGE_FULL` | 저장 공간 부족 |
| -1001 | `SECURE_CONNECTION_REQUIRED` (2.3.0) | Android에서 HTTP 사용 또는 유효하지 않은 인증서 |
| -1002 | `UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE` (2.4.1) | 서버 Content-Type과 `:responseType` 불일치 |

출처: [Communications 오류 코드, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md) **[검증]**

### 백그라운드 서비스: 5분 간격, 30초 수명, 64 KB, 8 KB 전달 한도

백그라운드 경로는 제약이 네 겹이다. `Background.registerForTemporalEvent()`(API 2.3.0)는 **직전 temporal event로부터 5분 안에 다시 실행되게 예약할 수 없다**. 5분 미만의 Duration도 거부되고 `InvalidBackgroundTimeException`이 난다. 과거 시각의 Moment는 즉시 실행되지만, 앱을 시작할 때 5분 제한을 풀어 주는 예외는 워치 앱과 위젯에만 적용되고 데이터 필드에는 적용되지 않는다. 예약은 한 번에 하나만 둘 수 있다 **[검증]** ([Toybox.Background, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)). 공식 예제의 안전한 패턴은 `getLastTemporalEventTime()`이 null이 아니면 `lastTime.add(5분)`, null이면 `Time.now()`로 예약하는 것이다. 포럼에서 "즉시 된다"와 "5분 미만이라 예외가 난다"는 말이 엇갈리는 것도 이 규칙으로 설명된다 **[추론]**. 백그라운드 작업은 `Background.exit()`나 `System.exit()`로 끝내지 않으면 **30초 뒤 강제 종료된다**. 콜백에서 이어 시작한 통신은 끝까지 간다는 보장이 없고 "delegate 함수만 완료가 보장된다" **[검증]** ([AppBase, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md); [ServiceDelegate, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/System/ServiceDelegate.md)). BLE 쪽에서 `BLE_HOST_TIMEOUT`이 나면 백그라운드 프로세스가 오류를 돌려주지 않은 채 30초 만에 끝난다는 버그 보고도 있다 **[포럼]** ([Background process exits before makeWebRequest times out](https://forums.garmin.com/developer/connect-iq/i/bug-reports/background-process-exits-before-makewebrequest-times-out)).

메모리와 전달 한도도 좁다. fēnix 8의 백그라운드 프로세스 한도는 **65,536바이트(64 KB)**다 **[검증]** ([openhab fenix847mm/compiler.json](https://github.com/openhab/openhab-garmin/blob/HEAD/.github/ConnectIQ/Devices/fenix847mm/compiler.json)). 가민 FAQ 스니펫에 있는 "데이터 필드의 백그라운드는 16 KB까지 작아질 수 있다"는 말은 구형 기기 이야기로, fēnix 8에는 기기 파일 값이 우선한다 **[포럼 vs 검증]** ([FAQ: background service](https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-a-connect-iq-background-service/)). `Background.exit(data)`는 직렬화 오버헤드를 포함해 **약 8 KB**를 넘으면 `ExitDataSizeLimitException`을 던진다. 이 한도는 우회할 수 있다. CIQ 3.2.0 이상 기기에서는 백그라운드가 `Application.Storage`에 직접 쓸 수 있고, 포그라운드는 `AppBase.onStorageChanged()`(API 3.2.0)로 변경을 통보받는다. `Application.Properties`는 백그라운드에서 쓸 수 없다 **[검증]** ([Background, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md); [Storage, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Storage.md); [Properties, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/Properties.md)).

백그라운드가 **언제** 도는지는 공식 문서에 없고 포럼 전언뿐이다. 데이터 필드의 포그라운드 코드는 그 필드가 레이아웃에 들어 있는 활동이 열려 있을 때만 돈다. 반면 데이터 필드가 등록한 temporal event는 활동이 끝나거나, 필드를 빼거나, 시계를 재부팅해도 앱이 지울 때까지 계속 실행된다 **[포럼]** ([Does my datafield run in the background only if an activity is using it?](https://forums.garmin.com/developer/connect-iq/f/discussion/403750/does-my-datafield-run-in-the-background-only-if-an-activity-is-using-it); [Background Process Termination?](https://forums.garmin.com/developer/connect-iq/f/discussion/330437/background-process-termination)). 정리 코드는 `onStop()`에 두되, `onStop()`은 백그라운드 프로세스가 끝날 때도 불리므로 어느 프로세스인지 확인해야 한다. 일부 기기에서는 `onStop()`이 불리지 않아 `onReset()`을 쓰라는 조언도 있다 **[포럼]**. 이런 성질 때문에 백그라운드는 활동 전에 코스를 미리 받아 두는 보조 수단으로 쓸 만하다. 다만 한 번 실행할 때 1–2개 청크, 실행 간격 5분이면 100 km 코스를 받는 데 10–35분이 걸린다 **[추론]**.

### 모든 요청은 폰의 Garmin Connect 앱을 거친다

공식 문서는 `makeWebRequest`가 "WiFi 또는 Bluetooth로 연결된 모바일 기기"로 동작한다고 쓴다 **[검증]**. 실제로는 요청이 폰의 Garmin Connect 앱(GCM)을 BLE로 거친다. 시계는 동기화(`SyncDelegate`) 때만 Wi-Fi를 켠다는 포럼 답변이 있고 **[포럼]** ([Confirming WiFi Connectivity before makeWebRequest](https://forums.garmin.com/developer/connect-iq/f/app-ideas/338561/confirming-wifi-connectivity-before-makewebrequest)), Breadcrumb 작성자도 `checkWifiConnection`으로 Wi-Fi를 연결해 봤지만 요청은 여전히 블루투스 브리지로 갔다고 코드에 적었다 **[검증: 코드 주석]** ([WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)). 플랫폼마다 조건이 다르다. **iOS에서는 Garmin Connect를 최근에 열지 않았으면 -104가 난다.** 대책으로 백그라운드 앱 새로 고침 허용과 저전력 모드 해제가 거론된다 **[포럼]** ([makeWebRequest on iOS needs Garmin Connect open](https://forums.garmin.com/developer/connect-iq/f/discussion/343216/makewebrequest-on-ios-needs-garmin-connect-open-on-the-phone)). **Android에서는 유효한 인증서의 HTTPS가 필요하다** **[포럼]** ([How to do a HTTP (not HTTPS) web request?](https://forums.garmin.com/developer/connect-iq/f/discussion/370945/how-to-do-a-http-not-https-web-request)). fēnix 8 Pro의 LTE가 CIQ 요청에 쓰인다는 근거는 찾지 못했다. 트레일러너에게 이 제약이 가장 실제적이다. 전송 순간에 폰에 인터넷이 있어야 하므로 신호가 없는 들머리에서는 받을 수 없다. **집에서 미리 받아 Storage에 넣어 두는 운용**이 기본이 되어야 한다 **[추론]**.

## (2) 128 KB 힙과 8 KB 저장 단위가 데이터 형식을 결정한다

fēnix 8의 기기 파일에 따르면 **데이터 필드 메모리 한도는 131,072바이트(128 KB)**이고, 43 mm·47/51 mm AMOLED와 Solar MIP 모두 같다. 같은 파일에서 fēnix 7·epix 2·FR965는 256 KB이므로, **fēnix 8 데이터 필드는 이전 세대의 절반**이다 **[검증]**.

| 기기 | 데이터 필드 | 백그라운드 | 워치 앱 | 출처 |
|---|---|---|---|---|
| fēnix 8 43 mm (AMOLED 416×416) | 128 KB | 64 KB | — | [granbike 기기 파일](https://github.com/mgallesio/granbike-face-builder/tree/HEAD/backend/devices) |
| fēnix 8 47/51 mm (AMOLED 454×454) | 128 KB | 64 KB | 768 KB | [openhab fenix847mm](https://github.com/openhab/openhab-garmin/blob/HEAD/.github/ConnectIQ/Devices/fenix847mm/compiler.json) |
| fēnix 7 / epix 2 / FR965 | 256 KB | 64 KB | — | [granbike 기기 파일](https://github.com/mgallesio/granbike-face-builder/tree/HEAD/backend/devices) |
| fēnix 6 Pro | 128 KB | 32 KB | 1280 KB | 같은 곳 |

이 128 KB 안에 코드, 전역 변수, 그리기 객체, 처리 중인 웹 응답, 디코딩한 프로파일이 모두 들어간다. PRG의 코드·데이터 영역이 이 한도에 포함되고 리소스는 `loadResource()`로 불러올 때만 힙에 올라온다는 설명은 포럼에서 나왔다 **[포럼]** ([Maximum .PRG file size error](https://forums.garmin.com/developer/connect-iq/f/discussion/416669/maximum-prg-file-size-error/1955127)). `jsonData` 리소스는 필요할 때 불러오므로 힙 부담은 없지만 코스가 바뀔 때마다 다시 빌드해야 하므로 이 프로젝트의 요구에 맞지 않는다 **[검증+추론]** ([Core Topics, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)).

Storage 한도는 공식 문서끼리 어긋난다. API 레퍼런스는 **"values are limited to 32 KB in size"**라고 하고 전체 용량은 "기기마다 다르다"고만 한다. 가득 차면 `StorageFullException`이 난다 **[검증]** ([Storage, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Storage.md)). 반면 프로그래머 가이드의 "Persisting Data"는 **키와 값이 각각 8 KB, 전체 128 KB**라고 쓴다 **[검증]** ([Core Topics, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)). SDK 2.4 시절 가민 블로그는 전체 약 100 KB에 항목당 8 KB 미만이라고 했다 **[포럼급: 스니펫]** ([Garmin Blog: improve your app performance](https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/)). 문서에 적힌 `setValue` 허용 타입은 String, Number, Float, Boolean, Char, Long, Double, BitmapResource(3.0.0+), AnimationResource(3.0.8+), ScanResult(3.2.0+), null, 그리고 이들로 된 Array·Dictionary다. **ByteArray는 목록에 없다** **[검증]**. 그러므로 바이너리 코스는 Base64 문자열로 저장한다. 불러온 뒤 `StringUtil.convertEncodedString`(API 3.0.0, `REPRESENTATION_STRING_BASE64` 3.0.0)으로 ByteArray로 되돌리는 방식이 문서상 가능하다 **[검증: API 존재]**. 다만 이 함수를 데이터 필드에서 쓸 수 있는지와 디코딩 중 메모리가 얼마나 치솟는지는 확인하지 못했다 **[추론]**.

실제 용량을 계산하면 이렇다. 30 KB 바이너리는 Base64로 약 40 KB가 되어 8 KB 키 5개 이상에 나눠 담아야 한다. 이런 코스 세 개는 약 120 KB로 128 KB 한도에 거의 닿고 100 KB 설에서는 이미 넘친다. 따라서 **Storage에는 활성 코스 하나와 예비 한두 개만 두는 설계**가 안전하다 **[추론]**. 최신 기기에서는 `Storage.setValue()`가 System Error를 냈다는 버그 보고(Venu 3, FR965, FR265)가 있으니 모든 쓰기를 try/catch로 감싼다 **[포럼]** ([System Error calling Storage.setValue()](https://forums.garmin.com/developer/connect-iq/i/bug-reports/system-error-calling-storage-setvalue-lastest-fw)). CIQ 8에서 "추가 저장 공간 16 MB"가 생겼다는 스니펫도 있지만, 사실인지와 데이터 필드에 적용되는지는 확인하지 못했다 **[포럼, 미검증]** ([Notebookcheck CIQ 8](https://www.notebookcheck.com/Garmin-Connect-IQ-8-startet-mit-Verbesserungen-fuer-Zifferblaetter-Benachrichtigungen-und-Apps-in-den-Beta-Test.944481.0.html)).

## (3)·(4) 설정은 코스를 고르는 데 쓰고, 싣는 데는 쓰지 못한다

### 폰 설정은 스토어·베타 설치에서만 열리고, 그마저 불확실하다

앱 설정은 Connect IQ Store 앱, Garmin Connect 앱, Garmin Express에서 편집한다. 문자열 설정(`alphaNumeric`)에는 선택 속성 `maxLength`가 있고, 실행 중에 설정이 바뀌면 `AppBase.onSettingsChanged()`가 불린다 **[검증]** ([Core Topics, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)). 플랫폼 차원의 최대 길이는 문서에 없다. 포럼 고참들은 편집 도구에 따라 **문자열 하나에 약 256자, 설정 전체에 약 8 KB**가 실무 한계라고 말한다 **[포럼]** ([Max length of alphaNumeric setting?](https://forums.garmin.com/developer/connect-iq/f/discussion/217336/max-length-of-alphanumeric-setting)). iOS GCM에서는 `&` 뒤가 잘리고 `\`가 사라지며 `<`·`>`가 들어가면 문자열 전체가 지워진다는 보고도 있다 **[포럼]** ([alphaNumeric does not accept <, >, & and \](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-ios/258279/alphanumeric-type-app-setting-does-not-accept-and-characters)). 6 KB 코스만 해도 Base64로 약 8 KB라 설정 예산 전체를 다 쓴다. DIY Data Field처럼 여러 설정 칸에 정의 줄을 나눠 붙여 넣는 선례가 있기는 하지만 **[포럼: 스토어 스니펫]** ([DIY Data Field](https://apps.garmin.com/en-US/apps/470f546f-200f-42ce-bb9c-0f7dc27ec3a5)), 30 KB 코스는 이 방식으로도 불가능하다. 설정은 **코스 ID나 URL 같은 포인터**를 담는 데만 쓴다 **[추론]**.

설치 방식에 따라 폰 설정이 열리는지가 갈린다. **USB로 사이드로드한 `.prg`는 폰에서 설정을 편집할 수 없다.** 시뮬레이터가 만든 `.SET` 파일을 PRG 이름에 맞게 바꿔 `GARMIN/APPS/SETTINGS/`에 복사하는 우회로가 있지만 이것도 PC와 USB가 필요하다 **[포럼]** ([[SOLVED] Settings for sideloaded app](https://forums.garmin.com/developer/connect-iq/f/discussion/429848/solved-settings-connect-iq-app-for-sideloaded-app---is-this-possible); [Settings file for custom not published watchface](https://forums.garmin.com/developer/connect-iq/f/discussion/374864/settings-file-for-custom-not-published-garmin-watchface-app-in-prg-format)). 공식 대안은 **베타 앱**이다. 별도 앱 UUID로 "Beta App" 체크박스를 켜고 업로드하면 심사 없이 올린 계정에만 보인다. 몇 번이든 갱신할 수 있고, 문서는 "Garmin Connect와 Garmin Express에서 앱 설정을 편집할 수 있다"고 쓴다. 앱 유형 제한이 없으니 데이터 필드도 베타로 올릴 수 있다 **[검증]** ([Beta Apps, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); [공식 주소](https://developer.garmin.com/connect-iq/core-topics/beta-apps/)).

하지만 2025–2026년 현실은 문서보다 험하다. 가민은 **2025년 11월 20일 Connect IQ Store 모바일 앱을 구매·설치·관리의 유일한 경로로 바꿨고**, 개발자 업로드 주소를 apps-developer.garmin.com으로 옮겼다 **[포럼: 공지 스니펫 + 2차 보도]** ([Changes to the Connect IQ Store](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/changes-to-the-connect-iq-store); [the5krunner 2025-11-22](https://the5krunner.com/2025/11/22/garmin-shuts-down-connect-iq-web-store-mobile-app-mandatory/)). 그 뒤로 베타 앱의 "Install" 버튼이 사라졌다는 보고가 나왔다. 우회책은 두 가지다. 개발자 대시보드의 다운로드 버튼으로 기기를 고른 뒤 동기화하거나, `apps.garmin.com/apps/<uuid>` 링크를 자기 메일로 보내 폰에서 연다 **[포럼]** ([Installing beta apps is almost impossible now](https://forums.garmin.com/developer/connect-iq/i/bug-reports/installing-beta-apps-is-almost-impossible-now); [Missing "Install" button for Beta apps](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/431240/missing-install-button-for-beta-apps-in-connect-iq-web-store); [How does one install a beta app?](https://forums.garmin.com/developer/connect-iq/f/connect-iq-web-store/427577/how-does-one-install-a-beta-app)). 설정이 열리는지도 전언이 엇갈린다. 개인용이면 베타로 올려 폰 설정을 쓰라는 답이 있는가 하면 **[포럼]** ([epix 2 포럼](https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/epix-2/300865/how-can-i-change-the-settings-for-a-connect-iq-data-field-using-the-connect-mobile-app)), "스토어에 정식으로 없는 Pending/Beta 앱은 GCM이 찾지 못해 설정을 바꿀 수 없다"는 버그 보고도 있다 **[포럼]** ([No settings for Pending application](https://forums.garmin.com/developer/connect-iq/i/bug-reports/no-settings-for-pending-application-in-connect-mobile-app)). 결론적으로 **폰 설정에 기대지 않는 설계**가 안전하다 **[추론]**.

### 시계 안 설정 메뉴: getSettingsView와 onTap

API 3.2.0부터 데이터 필드와 워치페이스는 `AppBase.getSettingsView()`를 재정의해 View와 InputDelegate 쌍을 돌려줄 수 있다. `Menu2`도 가능하다. 문서는 **"Data field configuration is available from the activity menu"**라고 명시한다. 지원 기기 목록(2024-12 생성)에는 fēnix 8 43 mm, 47/51 mm, Solar가 모두 들어 있다 **[검증]** ([AppBase, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md); [Core Topics, 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)). 이 경로는 사이드로드든 베타든 스토어든 똑같이 동작하므로 폰 설정의 불확실성을 피하는 핵심 수단이다. 사용자는 활동 중에 UP(MENU)을 길게 눌러 "Connect IQ 필드 → 필드 이름"으로 들어간다고 하지만, 이는 fēnix 6·7 시절의 포럼 설명이고 fēnix 8의 정확한 메뉴 경로는 확인하지 못했다 **[포럼]** ([SDK 3.2 settings view for datafields](https://forums.garmin.com/developer/connect-iq/i/bug-reports/sdk-3-2-settings-view-for-datafields-shown-wrong-on-simulator?CommentId=db5901be-c8d8-4a72-abd0-569ffd96f3a9)). fēnix 7·epix 2에서는 설정 뷰에서 Menu2를 띄우면 뒤쪽 뷰가 계속 갱신되는 이상 동작이 보고됐다 **[포럼]** ([fenix7/epix problem with getSettingsView](https://forums.garmin.com/developer/connect-iq/i/bug-reports/fenix7-epix-problem-with-getsettingsview)). 설정 뷰 안에서 `makeWebRequest`를 호출해도 되는지는 문서가 막지도 허용하지도 않으므로 실기기에서 확인해야 한다 **[추론]**. 터치 기종에서는 데이터 필드가 `InputDelegate.onTap()`만 받을 수 있다. 활동 중에 필드를 두드려 저장된 코스를 바꾸거나 세로 배율을 바꾸는 가벼운 조작에 쓸 수 있다 **[검증]** ([Core Topics "Data Field", 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)).

## (5) 시계가 따라가는 코스는 남은 거리만 알려주고 윤곽은 숨긴다

`Activity.Info`의 내비게이션 관련 멤버는 모두 **API 2.1.0**부터 있는 nullable 스칼라 10개다. 2024년 12월 미러와 2025년 8월 미러 모두 같은 타입이고, fēnix 8(43 mm, 47/51 mm, Solar)이 지원 목록에 있다 **[검증]** ([Activity/Info, 2024-12 미러](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Activity/Info.md); [Activity/Info, 2025-08 미러](https://github.com/ztuskes/garmin-documentation-mcp-server/blob/main/docs/Toybox/Activity/Info.html)).

| 멤버 | 타입 | 문서상 의미 / 비고 |
|---|---|---|
| `distanceToDestination` | Float? | 목적지까지 거리(m). 프로파일 위치 축으로 가장 유용 |
| `distanceToNextPoint` | Float? | 다음 지점까지 거리(m). "다음 지점"은 코스 포인트·회전 지점으로 보임 |
| `elevationAtDestination` | **Number?** | 목적지 고도(m). 이것만 정수형 |
| `elevationAtNextPoint` | Float? | 다음 지점 고도(m). 드문드문한 표본일 뿐 연속 프로파일 아님 |
| `nameOfDestination` | String? | "목적지 이름". 코스 이름인지는 미확인 |
| `nameOfNextPoint` | String? | 다음 지점 이름. 구형 펌웨어에서 항상 null 보고 |
| `offCourseDistance` | Float? | 현재 코스의 가장 가까운 점까지 거리(m) |
| `bearing` / `bearingFromStart` | Float? | 목적지 방향 / 출발 시점의 목적 방향(라디안) |
| `track` | Float? | GPS 진행 방향(라디안). 코스 궤적 아님 |

코스의 궤적, 고도 프로파일, ClimbPro 오르막, 총거리를 주는 API는 **2025년 8월 문서 기준으로 없다**. 그 미러의 `Activity.Info` 멤버 50개 가운데 API 5.1 이상에서 추가된 것은 없고, Toybox 모듈 목록에 Navigation이나 Course 모듈도 없다 **[검증]** ([Toybox 모듈 목록, 2025-08 미러](https://github.com/ztuskes/garmin-documentation-mcp-server/tree/main/docs/Toybox)). `PersistedContent`(API 2.2.0, `getCourses()`, `getAppCourses()` 3.0.0)는 코스마다 `getName()`, `getId()`, `toIntent()`, `remove()`만 제공하고, 앱 유형에 **Data Field가 없다** **[검증]** ([PersistedContent, 2025-08 미러](https://github.com/ztuskes/garmin-documentation-mcp-server/blob/main/docs/Toybox/PersistedContent.html)). `WatchUi.MapTrackView`(API 3.0.0)는 데이터 필드에서 쓸 수 있지만 지도를 그려 줄 뿐 코스 데이터는 주지 않는다 **[검증]** ([MapTrackView](https://github.com/ztuskes/garmin-documentation-mcp-server/blob/main/docs/Toybox/WatchUi/MapTrackView.html)). 포럼 답변도 같다. "데이터 필드에서는 다가올 고도를 그릴 방법이 없다. 지도는 가능하지만 고도는 안 된다" **[포럼]** ([Access course data from data field](https://forums.garmin.com/developer/connect-iq/f/discussion/303652/access-course-data-from-data-field)). 2025년 8월 이후 SDK에서 이것이 바뀌었는지는 확인하지 못했다.

그래도 네이티브 코스는 쓸모가 있다. 오픈소스 climbBrooo는 같은 GPX를 네이티브 코스로 따라가면서 자기 프로파일에서의 위치를 **`routeTotalLen − distanceToDestination`**으로 구한다. 코드 주석은 이 값이 단순 누적 거리보다 정확한 축이라고 설명한다 **[검증: 오픈소스 코드]** ([climbBrooo ClimbProView.mc](https://github.com/SvenvanDalen/climbBrooo/blob/main/garmin/source/ClimbProView.mc)). 오래된 버그 보고에는 `distanceToDestination`이 코스 끝이 아니라 다음 지점까지의 거리를 돌려줬다는 사례가 있고, fēnix 6에서도 재현됐다는 사용자 증언이 있다 **[포럼]** ([distanceToDestination bug report](https://forums.garmin.com/developer/connect-iq/i/bug-reports/activityinfo-distancetodestination-seemingly-incorrect-reflects-distance-to-next-point-not-distance-to-end-of-course)). 그래서 climbBrooo는 "길이 게이트"를 둔다. 이번 달리기에서 본 가장 큰 `distanceToDestination`이 저장된 경로 길이에서 허용 오차 안으로 들어올 때만 네이티브 축을 믿고, 아니면 누적 거리로 돌아간다 **[검증]** ([climbBrooo ClimbData.mc](https://github.com/SvenvanDalen/climbBrooo/blob/main/garmin/source/ClimbData.mc)). 이 방식은 코스 자동 선택에도 쓸 수 있다. `nameOfDestination`이 fēnix 8에서 코스 이름을 돌려준다면 그 값을 키로 저장된 프로파일을 고르면 된다. 이 동작을 확인한 자료는 없으므로, 최대 `distanceToDestination`을 저장된 길이와 ±1–2% 범위에서 맞춰 보는 방식을 대체 수단으로 두는 것이 합리적이다 **[추론]**.

## (6) 기존 앱은 예외 없이 자기 경로 사본을 따로 들여온다

다가올 고도 프로파일이나 오르막을 보여 주는 앱 가운데 네이티브 코스 궤적을 읽는 것은 하나도 없다. 모두 자기 사본을 들여오며, 경로는 세 가지다. 로그인한 워치 앱이 벤더 서버에서 받거나(komoot, dynamicWatch), Android 컴패니언이 폰 메시지로 데이터 필드에 밀어 넣거나(Breadcrumb, climbBrooo), 자체 백엔드를 `makeWebRequest`로 부른다(tribly).

| 앱·프로젝트 | 형태 | 경로 반입 방식 | 이 프로젝트와의 관련성 |
|---|---|---|---|
| komoot | 워치 앱(자체 내비) | 계정 로그인 후 계획한 투어를 앱이 다운로드. 경사 색 프로파일, 오르막 카드(2026 기능) | 기능은 가장 가깝지만 데이터 필드가 아님 ([komoot 2026 릴리스](https://support.komoot.com/hc/en-us/articles/10621431252250-All-komoot-Feature-Releases-2026)) **[포럼: 스니펫]** |
| Garmin Connect Courses API | CIQ 아님 | Strava·Komoot 경로가 네이티브 .FIT 코스로 동기화 | 네이티브 코스를 따라가며 `distanceToDestination`을 얻는 짝 ([DC Rainmaker 2020](https://www.dcrainmaker.com/2020/05/garmin-launches-devices.html)) **[포럼: 스니펫]** |
| Trailforks | 워치 앱 | 계정 경로를 .FIT로 받아 네이티브 내비에 넘김 | 프로파일을 그리지 않음 ([trailforks.com/garmin](https://www.trailforks.com/garmin/)) **[포럼: 스니펫]** |
| dynamicWatch mapField | 데이터 필드 | dynamic.watch 계정 경로를 필드가 자체 보관 | 데이터 필드 + 자기 사본의 상용 선례 ([mapField](https://apps.garmin.com/en-US/apps/8a8ccf60-2c97-443a-9daf-abd3608f2b10)) **[포럼: 스니펫]** |
| **Breadcrumb** | 데이터 필드, API 5.0+, fēnix 8 지원, 오픈소스 | Android 컴패니언이 GPX를 단순화해 `sendMessage`로 전송. 타일은 `http://127.0.0.1:8080`에서 `makeWebRequest` | "Elevation Overview" 기능을 갖춘 가장 가까운 참조 구현 ([readme](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md)) **[검증]** |
| **climbBrooo** | 데이터 필드 3종 + 워치 앱, `minApiLevel="3.2.0"` | Android 앱이 경로를 분석해 폰 메시지로 전송, `Storage.setValue("active_payload", msg)`. Onboard 변형은 `CHUNK_POINTS = 250`, `MAX_POINTS = 6000`으로 나눠 저장 | 자기 프로파일 + 네이티브 `distanceToDestination` 결합의 유일한 선례 ([README](https://github.com/SvenvanDalen/climbBrooo); [RawRouteStore.mc](https://github.com/SvenvanDalen/climbBrooo/blob/main/garmin-onboard/source/RawRouteStore.mc)) **[검증]** |
| tribly | 웹 + 워치 앱 | `ApiClient.mc`에서 자체 백엔드로 `makeWebRequest` | 웹 다운로드 방식의 오픈소스 예 ([tribly](https://github.com/glandais/tribly)) **[검증]** |

두 가지 공백이 눈에 띈다. **여러 청크를 여러 번의 백그라운드 실행에 걸쳐 받아 조립하는 공개 데이터 필드는 찾지 못했다.** GitHub에서 `makeWebRequest`와 elevation/route를 함께 쓰는 `.mc` 코드를 검색해도 Breadcrumb 두 저장소와 tribly만 나왔다 **[검증: 코드 검색]**. 그래서 이 프로젝트의 웹 다운로드 프로토콜은 문서에 나온 기본 기능을 조합해 직접 설계해야 한다. 또 Breadcrumb은 데이터 필드가 메모리 부족으로 죽을 때를 대비해 경량판을 따로 두고, 워치 앱판은 "데이터 필드보다 메모리 한도가 크다"는 이유로 기능이 더 많다 **[검증]** ([breadcrumb-garmin readme](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md)). 128 KB 한도가 실제로 발목을 잡는다는 방증이다. 별도 워치 앱을 다운로드 담당으로 두는 절충안도 막혀 있다. climbBrooo README가 "네 워치 앱은 저장소가 분리되어 있어" 선택을 폰으로 중계한다고 밝혔고 **[검증]**, 앱 간 공유 저장소는 포럼의 기능 요청으로만 남아 있다 **[포럼]** ([Allow shared storage between apps](https://forums.garmin.com/developer/connect-iq/i/bug-reports/allow-shared-storage-between-apps?pifragment-706=4)). **코스를 받는 주체는 데이터 필드 자신이어야 한다.**

## (7) 폰 컴패니언은 검증된 경로지만 오프라인 전송이 필요할 때만 값을 한다

Mobile SDK는 살아 있다. Android `com.garmin.connectiq:ciq-companion-app-sdk`는 **2.4.0이 2026-03-25에** Maven Central에 올라왔고, iOS `ConnectIQ.xcframework`는 2026-01-15에 갱신됐다 **[검증]** ([Maven Central](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/); [iOS SDK 저장소](https://github.com/garmin/connectiq-companion-app-sdk-ios)). 노트 작성자가 Android AAR을 `javap`로 역어셈블한 결과는 이렇다. 공개 메서드는 `sendMessage(device, app, Object, IQSendMessageListener)`이고, 내부에서 **직렬화된 길이를 16,384바이트와 비교해 넘으면 `FAILURE_MESSAGE_TOO_LARGE`를 알린다.** 그런데 그 뒤에 `return`이 없어 전송이 그대로 진행되므로 초과 메시지가 깔끔하게 거부된다고 믿으면 안 된다. `byte[]`는 Monkey C `ByteArray`(타입 태그 20)로 직렬화된다 **[검증]** ([AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)). Android SDK는 모든 통신을 GCM(`MIN_GCM_VERSION = 10617`)에 의존한다. iOS SDK는 BLE로 직접 통신하지만 기기 탐색에는 GCM이 필요하다. iOS의 전송 가능 타입은 `NSString`, `NSNumber`, `NSArray`, `NSDictionary`, `NSNull`뿐이라 바이너리는 Base64 문자열로 보내야 한다 **[검증]** ([iOS SDK 가이드](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)).

시계 쪽 수신에는 두 경로가 있다. fēnix 8에서는 데이터 필드가 포그라운드에서 `Communications.registerForPhoneAppMessages()`(API 1.4.0)를 직접 호출한다. 등록할 때 기다리던 메시지가 있으면 "메시지마다 콜백이 즉시 한 번씩" 불리므로 기기 쪽에 우편함이 있는 셈이다 **[검증]**. 백그라운드로는 `Background.registerForPhoneAppMessageEvent()`와 `ServiceDelegate.onPhoneAppMessage()`(둘 다 API 3.2.0)가 있다 **[검증]** ([Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html); [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)). Breadcrumb은 포그라운드 경로로, 경량판(`breadcrumb-garmin-ultra-light`)은 백그라운드 경로로 실제 동작한다 **[검증]** ([breadcrumb-garmin](https://github.com/pauljohnston2025/breadcrumb-garmin); [ultra-light](https://github.com/pauljohnston2025/breadcrumb-garmin-ultra-light)). 폰에서 데이터 필드를 원격으로 띄울 수는 없다. Breadcrumb 컴패니언 코드 주석에 따르면 `openApplication`은 데이터 필드에 대해 `PROMPT_SHOWN_ON_DEVICE`를 돌려주지만 실제로는 아무것도 뜨지 않는다 **[검증: 코드 주석]** ([breadcrumb-mobile](https://github.com/pauljohnston2025/breadcrumb-mobile)). 그러므로 사용자가 먼저 활동을 열고 폰에서 "보내기"를 눌러야 한다.

위험은 신뢰성과 배포에 몰려 있다. "보냄"으로 기록된 메시지가 Edge 540 데이터 필드에 도착하지 않았다는 보고, GCM 5.27.3(Android)에서 메시지가 전달되지 않는다는 보고 등 2020–2026년의 전송 버그가 이어진다 **[포럼]** ([Update data field from companion app](https://forums.garmin.com/developer/connect-iq/f/discussion/372069/update-data-field-from-companion-app); [GCM 5.27.3 bug](https://forums.garmin.com/developer/connect-iq/i/bug-reports/gcm-5-27-3-android-accepts-communications-transmit-messages-from-watch-app-but-never-delivers-them-to-the-companion-app)). 2026년 2월 스레드에는 **USB로 사이드로드한 앱은 폰에 "모바일 모듈"이 설치되지 않아 통신 경로가 없다**는 말이 있다. 그렇다면 워치 쪽은 비공개 베타로 설치해야 한다 **[포럼]** ([Best workflow for developing/testing with mobile companion](https://forums.garmin.com/developer/connect-iq/f/discussion/430465/best-workflow-for-developing-testing-connect-iq-app-with-mobile-companion)). 반대로 GCM 5.27.3 보고자는 사이드로드 빌드로도 재현했다고 적어 이 전언과 어긋난다. Android 컴패니언은 APK 사이드로드로 충분하다. iOS는 무료 Apple ID 서명이 7일마다 만료되므로 연 $99 멤버십이 사실상 필요하다 **[포럼]** ([Apple Developer Forums](https://developer.apple.com/forums/thread/69248)). 노트는 Android 최소 구현에 1–3일이 걸리고 대부분이 GCM·페어링 문제 해결에 쓰인다고 추정했고, iOS까지 하면 두 배다 **[추론]**. 속도는 문제가 아니다. 오래된 포럼 수치 약 2.8 kB/s만으로도 30 KB는 십수 초에 끝난다 **[포럼]** ([BLE data transfer rate](https://forums.garmin.com/developer/connect-iq/f/discussion/6387/ble-data-transfer-rate-and-max-heap-size)).

| 기준 | 폰 컴패니언 (Mobile SDK) | 필드 자체 웹 다운로드 |
|---|---|---|
| 만들 것 | 폰 앱(Android 1–3일, iOS는 추가 + 서명 비용) + 수신 코드 | 수신 코드 + 정적 HTTPS 파일 (0.5–1일) **[추론]** |
| 전송 시 인터넷 | 불필요(BLE만) | 필요(폰 데이터 또는 Wi-Fi) |
| 크기 처리 | 메시지당 16 KB 이하로 쪼개 조립 | 응답당 수 KB로 쪼개 조립 |
| 시작 조건 | 활동을 연 뒤 폰에서 전송(원격 실행 불가) | 필드가 스스로 요청 |
| 설치 방식 | 사이드로드로는 통신 불가 전언 → 베타 필요 가능성 | 사이드로드로 가능할 것으로 봄 **[추론, 미검증]** |
| 선례 | Breadcrumb, climbBrooo(fēnix 8·FR255) | tribly(워치 앱), Breadcrumb 타일 요청 |

Breadcrumb의 절충안도 있다. Android 컴패니언 안에 로컬 HTTP 서버를 띄우고 시계가 `http://127.0.0.1:포트`를 `makeWebRequest`로 부르는 방식으로, 16 KB 메시지 한도와 우편함 동작을 피한다 **[검증]**. 다만 GCM 4.20이 `targetSdkVersion`을 올렸을 때 localhost HTTP가 한동안 깨졌다는 이력이 있고, iOS에서는 확인되지 않았다 **[포럼]** ([Breakage of makeWebRequest from http://localhost](https://forums.garmin.com/developer/connect-iq/f/discussion/167402/breakage-of-makewebrequest-from-http-localhost)).

## 권고 구조: 필드가 직접 받고, 무엇을 받을지는 서버와 시계가 정한다

권고안의 뼈대는 **"포인터와 페이로드의 분리"**다. 어떤 코스를 쓸지는 짧은 포인터로 정하고, 코스 바이트는 데이터 필드가 HTTPS에서 조각으로 받아 Storage에 쌓는다. 앞 절들의 제약은 모두 이 구조 안에서 풀린다. 설정 칸 크기 문제는 포인터만 두면 사라진다. 네이티브 코스를 읽을 수 없는 문제는 자기 사본을 가져오면 해결된다. 128 KB 힙과 8 KB 저장 단위 문제는 작은 청크를 순차로 받아 곧바로 저장하면 된다. 폰 설정의 불확실성은 시계 안 메뉴로 피한다. 구현 에이전트가 따를 구성은 아래와 같다.

| 구성 요소 | 권고 | 근거 |
|---|---|---|
| 매니페스트 | `type="datafield"`, `minApiLevel="5.0.0"`, 제품 `fenix843mm`·`fenix847mm`(필요하면 Solar·Pro 추가), 권한 `Communications`. 위치로 코스를 맞출 때만 `Positioning`, 선취득을 할 때만 `Background` | Breadcrumb 매니페스트 **[검증]** |
| 호스팅 | 유효한 인증서의 HTTPS 정적 파일(GitHub Pages, Cloudflare 등). `index.txt`(코스 ID·이름·길이 목록), `current.txt`(활성 코스 ID), `<id>/m.txt`(청크 수·바이트 수·CRC), `<id>/<i>.txt`(Base64 청크) | Android HTTPS 요구 **[포럼]**, 파일 구성은 **[추론]** |
| 응답 형식 | `:responseType => HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN`, 서버 Content-Type `text/plain` | **[검증]** |
| 청크 크기 | Base64 텍스트 약 6 KB(바이너리 약 4.5 KB)에서 시작하고 서버 쪽 값으로 조정할 수 있게 둔다. 30 KB 코스는 요청 7회 | 8 KB 저장 단위, 64 KB 백그라운드, -402 보고치(32–44 KB)를 모두 여유 있게 만족 **[추론]** |
| 전송 제어 | 요청은 한 번에 하나. `:context => i`로 청크 번호를 받고, 다음 요청은 콜백 또는 `compute()`에서 시작한다. 동기 오류가 나도 그 자리에서 재귀 재시도하지 않고 대기열에 넣는다 | Breadcrumb 주석 **[검증]** |
| 저장 | 청크가 올 때마다 `Storage.setValue("c_<id>_<i>", data)`를 try/catch로 감싸 쓰고, `next` 인덱스를 기록해 끊겨도 이어받는다. 전부 받아 길이·CRC가 맞을 때만 `active`를 새 ID로 바꾸고, 그 전까지는 이전 코스를 유지한다 | **[추론]** |
| 복원·그리기 | 활성 코스의 청크를 하나씩 `getValue` → `StringUtil.convertEncodedString`으로 ByteArray 복원 → 최종 프로파일 구조에 이어 붙이고 원문 문자열은 버린다. 40 KB 문자열을 한 번에 합치지 않는다 | **[추론]**, 데이터 필드 가용성은 미검증 |
| 코스 선택 | 기본은 서버의 `current.txt`(폰 브라우저나 GitHub 앱으로 바꿀 수 있음). 보조로 `getSettingsView()`의 Menu2에서 캐시한 `index.txt` 목록을 골라 Storage `sel`에 기록. 베타 설치에서 폰 설정이 열리면 `alphaNumeric` 설정에 코스 ID를 둘 수 있음 | **[검증: API]** + **[추론]** |
| 위치 축 | 같은 GPX를 Garmin Connect 코스로도 동기화해 따라갈 때는 `총길이 − distanceToDestination`에 climbBrooo식 길이 게이트를 건다. 그렇지 않으면 `elapsedDistance`를 쓴다 | climbBrooo **[검증]** |
| 상태 표시 | "코스 3/7", 마지막 오류 코드(-104, -402, -403, -1001)를 필드 구석에 표시 | **[추론]** |
| 배포 | 개발과 일상 사용은 USB 사이드로드로 시작한다. 폰 설정이나 필드 자체의 무선 갱신이 필요해지면 비공개 베타로 옮긴다 | **[포럼]** + **[추론]** |

트레일러닝 운용은 이렇게 된다. 전날 집에서 GPX를 바이너리로 변환해 호스트에 올리고 `current.txt`를 바꾼다. 같은 GPX를 Garmin Connect 코스로도 보낸다. 시계에서 트레일런 활동을 열어 필드가 "코스 7/7 ✓"를 띄울 때까지 기다린 뒤, iPhone이면 Garmin Connect를 앞에 띄워 둔 채로, 저장하지 않고 나온다. Storage는 `setValue` 때 디스크에 바로 기록되므로 **[검증]**, 신호 없는 들머리에서도 필드는 저장된 코스를 그린다. GPX→바이너리 변환은 PC 스크립트로 남겨도 "앱 재빌드 없음"이라는 요구는 충족된다. 폰만으로 올리고 싶다면 변환을 서버리스 함수나 저장소 자동화로 옮기면 된다 **[추론]**.

다른 선택지도 따져 봤다. **백그라운드만 쓰는 설계**는 활동을 열지 않고도 받을 수 있다는 장점이 있다. 그러나 5분 간격 때문에 100 km 코스에 수십 분이 걸리고, 데이터 필드의 temporal event가 활동 밖에서 도는지는 포럼 전언뿐이며, 지우지 않으면 배터리를 계속 쓴다. 그래서 2단계 선택 기능으로 미룬다. 이때도 청크는 백그라운드에서 Storage에 직접 쓰고 `Background.exit()`에는 `{id, n, total}` 같은 작은 상태만 넘긴다. **컴패니언 앱**은 "들머리에서 인터넷 없이 코스를 바꿔야 한다"는 요구가 생길 때의 3단계다. Android만 만들고, Breadcrumb의 메시지 구조를 본떠 `byte[]` 12 KB 이하 청크에 seq/total/courseId 헤더를 붙인다. **`HTTP_RESPONSE_CONTENT_TYPE_GPX`(2)/`FIT`(3)로 네이티브 코스를 만드는 경로**(API 2.2.0)는 데이터 필드가 그 결과를 읽을 수 없어 이 문제의 답이 아니다 **[검증]**. **코스를 `jsonData` 리소스로 넣는 방식**은 재빌드를 전제하므로 제외한다.

## 실기기에서 먼저 확인할 열두 가지

앞의 네 항목은 구조 자체를 결정하므로 코드를 본격적으로 쓰기 전에 작은 시험 필드로 확인한다. 나머지는 구현하면서 확인해도 된다.

| # | 확인 항목 | 시험 방법 | 실패 시 대안 |
|---|---|---|---|
| 1 | 포그라운드 `makeWebRequest`가 **타이머 시작 전**(GPS 탐색·준비 화면)에도 동작하는가 | 활동을 열자마자 요청하고 응답 코드를 필드에 표시 | 타이머 시작 뒤 받기, 또는 백그라운드 선취득 |
| 2 | **USB 사이드로드** `.prg`에서도 웹 요청이 되는가 | 같은 시험 필드를 사이드로드로 설치 | 비공개 베타로 설치 |
| 3 | text/plain 응답의 **-402/-403 경계** | 4·8·16·24·32 KB 응답을 차례로 요청 | 청크 크기를 경계의 절반 이하로 |
| 4 | Storage **값 한도(8 vs 32 KB)와 총량** | 8·16·32 KB 문자열 쓰기, `StorageFullException`이 날 때까지 채우기 | 청크·보관 코스 수 조정 |
| 5 | Storage가 API 5.x에서 **ByteArray**를 받는가 | 시뮬레이터와 실기기에서 `setValue(ByteArray)` | 받으면 Base64 단계 생략, 안 받으면 현행 유지 |
| 6 | `StringUtil.convertEncodedString`(Base64→ByteArray)을 데이터 필드에서 쓸 수 있는가와 **복원 중 메모리 피크** | 40 KB 분량 복원을 청크 단위로 수행 | 서버에서 숫자 텍스트 형식으로 받아 직접 파싱 |
| 7 | fēnix 8의 **설정 뷰 진입 경로**, Menu2 정상 동작, 설정 뷰에서의 요청 가능 여부, 필드 `onTap` 동작 | 활동 메뉴에서 필드 설정 열기 | `current.txt` 포인터만 사용 |
| 8 | 네이티브 코스를 따라갈 때 `distanceToDestination`이 코스 잔여 거리인가(`distanceToNextPoint`와 다른가), `nameOfDestination`이 코스 이름인가 | [ShowAllInfos](https://github.com/hansiglaser/ConnectIQ)류 필드로 두 값을 기록 | 길이 게이트 또는 `elapsedDistance` |
| 9 | iOS/Android에서 **-104 빈도**와 GCM 백그라운드 설정의 영향 | 폰 잠금·앱 전환 상태에서 반복 시험 | 전송 전 GCM 열기 안내, 재시도 |
| 10 | 받은 코스가 활동 종료·재부팅 뒤에도 남고, 폰 없이 다음 활동에서 불러와지는가 | 비행기 모드 폰으로 새 활동 시작 | — (실패하면 설계 재검토) |
| 11 | (선취득 시) 데이터 필드의 temporal event가 **워치페이스 상태에서** 도는가, `deleteTemporalEvent()`로 멈추는가 | 활동 종료 후 Storage 변화 관찰 | 포그라운드 전용 유지 |
| 12 | (베타 배포 시) 2025-11 이후 설치 흐름으로 설치되는가, 폰에 설정이 보이는가, 갱신이 자동으로 오는가 | 대시보드 다운로드 + 동기화, 메일 링크 | 사이드로드 + 시계 내 메뉴 |

## 결론

이번 조사로 병목이 어디 있는지가 드러났다. "데이터 필드가 인터넷에서 데이터를 받을 수 있는가"는 API 5.0 이후 fēnix 8에서 더 이상 문제가 아니다. 남은 제약은 셋이다. 첫째, fēnix 8에서 절반으로 줄어든 128 KB 힙과 8 KB 단위 저장이 데이터 형식과 청크 크기를 정한다. 둘째, 모든 전송이 폰의 Garmin Connect와 폰의 인터넷에 기대므로 들머리가 아니라 집에서 받는 운용이 필요하다. 셋째, 2025년 11월 스토어 개편 이후 베타 설치와 폰 설정의 동작이 불확실하다. 셋 다 API 설계가 아니라 **실측과 운용으로 푸는 문제**이고, 위 표의 1–4번은 요청·저장만 하는 작은 시험 필드 하나로 확인할 수 있다. 시험 필드에서 이 네 가지가 통과하면 나머지는 Breadcrumb과 climbBrooo가 이미 밟은 길을 따라가면 된다.

설계에서 가장 오래 쓸 결정은 네이티브 코스와 자기 사본을 **경쟁시키지 말고 결합하는 것**이다. 가민은 궤적을 끝내 열지 않았지만 `distanceToDestination` 하나로 위치 축은 내준다. 따라서 같은 GPX를 네이티브 코스와 필드용 프로파일로 동시에 쓰는 구성에서는 길 안내와 ClimbPro는 시계가 맡고, 고정 배율의 고도 프로파일만 이 필드가 맡는다. 이렇게 역할을 나누면 필드가 들고 다녀야 할 데이터는 좌표 없이 거리-고도 표본만으로 줄어든다. 코스당 6–30 KB라는 현재 예산을 더 줄일 여지도 여기서 나온다 **[추론]**.
