# Phone companion app route for pushing course data into a Connect IQ DATA FIELD (fēnix 8 AMOLED), and alternatives

Scope: can a small Android or iOS app built on the Connect IQ Mobile SDK send a preprocessed GPX elevation profile (~6 KB for 20 km, ~30 KB for 100 km, binary) to a personal data field? The note covers feasibility, limits and effort, and gives a short comparison with web downloads.

Legend used below:
- **[V]** means verified from a primary artifact. That is the official API doc, SDK binaries or headers, Garmin's own GitHub repos, Maven Central, or the source code of a working open-source project.
- **[H]** means forum or blog hearsay, usually only seen as a search-engine snippet, because forums.garmin.com and developer.garmin.com are blocked from this environment.
- **[I]** means my own inference.

Research date: 2026-09-24.

Method note: I could not browse the official API reference HTML live, because developer.garmin.com is blocked. I read a local copy of the official Toybox API docs; its footer says "Generated Dec 11, 2024". I cite the canonical developer.garmin.com URL for each page, but anything added to the docs after Dec 2024 would not appear in these notes. I read the Garmin mobile SDK repos by `git clone`. I downloaded the Android AAR from Maven Central and disassembled it with `javap`.

---

## Q1. Connect IQ Mobile SDK (Android/iOS): 2025–2026 status, how sending works, size limits, throughput, dependency on Garmin Connect Mobile (GCM), reliability

### Takeaway
Both SDKs are alive and still receiving updates:
- Android `com.garmin.connectiq:ciq-companion-app-sdk` 2.4.0 was released 2026-03-25.
- The iOS `ConnectIQ.xcframework` was last updated 2026-01-15.

The phone sends data with `sendMessage(device, app, object, listener)`, which serializes Java/ObjC objects into Monkey C types; `byte[]` becomes a Monkey C `ByteArray`. The Android SDK has a hard-coded 16,384-byte serialized-payload check that returns `FAILURE_MESSAGE_TOO_LARGE`, so a 30 KB course has to be sent in at least 2–3 chunks. The Android SDK routes everything through the Garmin Connect Mobile app (GCM). The iOS SDK talks BLE directly but still needs GCM installed to discover devices. Reliability reports on the forums are numerous. I found no trustworthy throughput figure.

### Cited Findings

**SDK status and versions**
- [V] Android SDK versions on Maven Central, with publish dates: 2.0.1 (2023-04-12), 2.0.2 (2023-04-26), 2.0.3 (2023-08-18), 2.2.0 (2025-01-15), 2.3.0 (2025-08-11), 2.4.0 (2026-03-25). Metadata was last updated 2026-03-27. — [Maven Central directory listing](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/)
- [V] Commit history of Garmin's Android sample repo (`garmin/connectiq-android-sdk`):
  - "Update the Comm example to use the version 2.4.0 of the companion app SDK" (2026-04-01)
  - "Add ability to retrieve the product part number of the paired devices" (2025-08-12)
  - "Update SDK for compatibility with Android 14" (2023-08-23)
  - Source: [garmin/connectiq-android-sdk](https://github.com/garmin/connectiq-android-sdk)
- [V] Housekeeping note: the README of that repo still shows `ciq-companion-app-sdk:2.2.0` in its Gradle snippet. It is stale compared with the sample itself. — [README](https://github.com/garmin/connectiq-android-sdk/blob/main/README.md)
- [V] Commit history of the iOS SDK repo (`garmin/connectiq-companion-app-sdk-ios`):
  - "Add support to mark messages sent from the companion app to the device as transient" (2025-01-17)
  - "Add ability to retrieve the product part number" (2025-08-11)
  - "Add several improvement features and miscellaneous bug fixes" (2026-01-15)
  - "Add support for UniversalLinks" (2024-10-11)
  - "Fix issues observed with iOS17" (2023-10-09)
  - It ships as a Swift Package with a binary `ConnectIQ.xcframework`.
  - Source: [garmin/connectiq-companion-app-sdk-ios](https://github.com/garmin/connectiq-companion-app-sdk-ios)
- [V] The bundled iOS guide is titled "Connect IQ Mobile SDK … Version 1.8.0". — [iOS SDK documentation folder](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)

**How sending works (Android)**
- [V] Public API of the Android SDK 2.4.0 AAR, from `javap` of `com.garmin.android.connectiq.ConnectIQ`:
  - `getInstance(Context, IQConnectType)` with `IQConnectType` = `WIRELESS` or `TETHERED`
  - `initialize(...)`, `getConnectedDevices()`, `getKnownDevices()`
  - `getApplicationInfo(appId, device, listener)`
  - `openApplication(device, app, listener)`
  - `sendMessage(device, app, Object, IQSendMessageListener)`, plus an overload with an extra `boolean` (transient)
  - `registerForAppEvents(...)` for watch-to-phone messages
  - `getDevicePartNumber(...)`
  - `registerAppToUseBinderService(...)`
  - Source: [AAR 2.4.0 on Maven Central](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)
- [V] Android `IQMessageStatus` values: `SUCCESS`, `FAILURE_UNKNOWN`, `FAILURE_INVALID_FORMAT`, `FAILURE_MESSAGE_TOO_LARGE`, `FAILURE_UNSUPPORTED_TYPE`, `FAILURE_DURING_TRANSFER`, `FAILURE_INVALID_DEVICE`, `FAILURE_DEVICE_NOT_CONNECTED`. — [same AAR](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)

**Message size limit (Android)**
- [V] The private `ConnectIQ.sendMessage(IQDevice, IQApp, byte[] serialized, listener, boolean)` compares the serialized length to `sipush 16384`. If the length is larger and a listener is set, it calls `onMessageStatus(..., FAILURE_MESSAGE_TOO_LARGE)`. The public `sendMessage` first runs `Serializer.serialize(Object)`, so the limit applies to the serialized Monkey C encoding, not to the raw data. — [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)
- [V] Bytecode oddity: after reporting `FAILURE_MESSAGE_TOO_LARGE`, the method has no `return`. It falls through to `sendMessageProtocol(...)` anyway. Do not rely on oversize messages being rejected cleanly; chunk below 16 KB. — [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)

**Serialization (Android)**
- [V] The Android serializer (`com.garmin.monkeybrains.serialization.MonkeyType`) maps Java types to Monkey C types:
  - `Integer` → Int
  - `Long` → Int or Long
  - `Float`/`Double` → Float/Double
  - `String`, `Character`, `Boolean`
  - `List` → Array, but a `List<Byte>` → `MonkeyByteArray`
  - `Map` → Dictionary
  - `byte[]` → `MonkeyByteArray` (type tag `BYTEARRAY = 20`)
  - Other tags: `INT=1, FLOAT=2, STRING=3, ARRAY=5, BOOLEAN=9, HASH=11, LONG=14, DOUBLE=15, CHAR=19`
  - Source: [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)

**GCM dependency (Android)**
- [V] The Android SDK talks to GCM:
  - `GCM_PACKAGE_NAME = "com.garmin.android.apps.connectmobile"`
  - `MIN_GCM_VERSION = 10617`
  - The AAR manifest declares `<queries><package android:name="com.garmin.android.apps.connectmobile"/>` and exports an `IQGarminBindingService`.
  - `IQSdkErrorStatus` includes `GCM_NOT_INSTALLED` and `GCM_UPGRADE_NEEDED`.
  - `minSdkVersion` is 21.
  - Source: [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)
- [V] Garmin's Android sample uses `ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS)` for real devices. `TETHERED` is the ADB/simulator mode. — [Comm Android MainActivity.kt](https://github.com/garmin/connectiq-android-sdk)
- [V] A real companion app states: "The garmin connect app must be installed to send routes to your device or configure the device settings." — [breadcrumb-mobile manual.md](https://github.com/pauljohnston2025/breadcrumb-mobile)

**iOS SDK**
- [V] iOS architecture, quoting the iOS guide: "Unlike the Mobile SDK for Android, apps created with the Mobile SDK for iOS are standalone apps and do not directly rely on GCM app to communicate with a wearable device. They do, however, require GCM to initially discover Connect IQ-compatible devices … or to install Monkey C applications." Device selection works by launching GCM through a URL scheme (`gcm-ciq`) or Universal Links. — [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)
- [V] The iOS app can opt into background BLE by enabling "Uses Bluetooth LE accessories", and can use Bluetooth state restoration. — [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)
- [V] iOS sending API: `sendMessage:toApp:progress:completion:`, with a progress block `(uint32_t sent, uint32_t total)`. The overload `...isTransient:` was added so that "not to overwhelm the device's message queue".
  - Valid types: `NSString`, `NSNumber`, `NSArray`, `NSDictionary`, `NSNull`. `NSData` is not listed, so there is no documented byte-array path on iOS.
  - Guide text: "it is more desirable to send occasional large messages than it is to frequently send many tiny messages."
  - Source: [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)
- [V] iOS `IQSendMessageResult` values: `Success`, `Failure_Unknown`, `Failure_InternalError`, `Failure_DeviceNotAvailable`, `Failure_AppNotFound`, `Failure_DeviceIsBusy`, `Failure_UnsupportedType`, `Failure_InsufficientMemory`, `Failure_Timeout`, `Failure_MaxRetries`, `Failure_PromptNotDisplayed`, `Failure_AppAlreadyRunning`. There is no explicit "message too large" code. — [IQConstants.h in ConnectIQ.xcframework](https://github.com/garmin/connectiq-companion-app-sdk-ios)

**Watch-side reception**
- [V] Watch side, from the `Communications` doc: `registerForPhoneAppMessages(callback)` has existed since API 1.4.0. "If there are messages waiting for the app when this function is called, the callback will immediately be called once for each waiting message", so there is a device-side mailbox and queue. `transmit()` sends watch-to-phone data. — [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [H] One developer reports phone messages "slightly more than 1K bytes"; the context was unclear. — [Garmin forum bug report, Android sendMessage SUCCESS and FAILURE_UNKNOWN](https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk---connectiq-sendmessage-return-with-success-and-failure_unknown)

**Throughput**
- [H] The only Connect IQ-specific figure I found is a snippet from an old forum thread (≈2017, fēnix 3 era) mentioning about 2.8 kB/s and ~20 s to load images over BLE. Theoretical numbers in the same thread are 250 kbps for the nRF51422. — [Forum: BLE data transfer rate and max heap size](https://forums.garmin.com/developer/connect-iq/f/discussion/6387/ble-data-transfer-rate-and-max-heap-size)
- [H] Generic BLE numbers are about 2.7 kB/s one-way on iPhone with default parameters. This is not Garmin-specific. — [Punch Through: Maximizing BLE throughput](https://punchthrough.com/maximizing-ble-throughput-on-ios-and-android/)
- [V] A French open-source Garmin companion project quotes "~1–10 kB/s via the Garmin Connect proxy". Its own notes say the figure was not measured on real hardware, so treat it as a guess. — [zomboky/garmin-app CorridorTransferManager.kt](https://github.com/zomboky/garmin-app)
- [V] The Breadcrumb author found in testing that the route "Coordinates Point Limit should not exceed ~400 to ensure the full route can be sent to the watch over bluetooth". Watch memory and CPU (watchdog) also constrain this. — [breadcrumb-mobile manual.md](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [V] The same companion code waits up to 5 min and 10 s for query replies: "some devices can take up to 5 minutes for a response if they are old and using temporal events". — [breadcrumb-mobile Connection.kt](https://github.com/pauljohnston2025/breadcrumb-mobile)

**Reliability issues**
- [V] First-hand developer note in the Breadcrumb companion code, citing Garmin forum threads about Android 11 / SDK 30: "On my samsung galaxy tab a I could not get this to ever send, then it started working fine… It could list devices, and gets device status updates, just sends would never work; even calls to connectIQ.getApplicationInfo returned nothing." — [breadcrumb-mobile Connection.kt](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [H] Bug report "GCM 5.27.3 (Android) accepts Communications.transmit messages from watch app but never delivers them to the companion app", covering 2025–2026 builds:
  - Reproduced with store-installed and sideloaded builds, and with Garmin's own Comm sample.
  - `registerAppToUseBinderService` succeeds, but GCM never binds `IQGarminBindingService`, and `getApplicationInfo` responses stop.
  - The reported direction is watch-to-phone, not phone-to-watch.
  - Source: [Garmin forum bug report](https://forums.garmin.com/developer/connect-iq/i/bug-reports/gcm-5-27-3-android-accepts-communications-transmit-messages-from-watch-app-but-never-delivers-them-to-the-companion-app)
- [H] Report that `sendMessage` gives SUCCESS and FAILURE_UNKNOWN for the same message. — [Garmin forum bug report](https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk---connectiq-sendmessage-return-with-success-and-failure_unknown)
- [H] Report "Android connectiq send message broken". — [Garmin forum bug report](https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-connectiq-send-message-broken)
- [H] Edge 540 data-field developer: messages from the companion app were logged as "Sent" but lost on the device, while the simulator's "Phone App Message" worked. The developer asked whether data fields can be updated from a companion app at all. — [Forum: Update data field from companion app](https://forums.garmin.com/developer/connect-iq/f/discussion/372069/update-data-field-from-companion-app)
- [H] On iOS, the app UUID must be written with dashes (e.g. `a3421fee-d289-…`), otherwise communication fails. — [Forum: App communication with watch (2025/26)](https://forums.garmin.com/developer/connect-iq/f/discussion/440779/app-communication-with-watch)

### Inferences
- [I] Size budget:
  - A 20 km course (~6 KB) fits in one Android message.
  - A 100 km course (~30 KB) needs at least 2 messages of 15 KB or less, or 3 of about 10 KB for margin. The receiver must reassemble them, which needs a sequence number and total count in each chunk, and should acknowledge with `transmit()`.
- [I] Encoding choice: on Android, send the preprocessed binary as `byte[]` so it becomes a Monkey C `ByteArray`. Overhead is then about 1 byte per byte plus a small header, compared with roughly 5 bytes per number for an Array of Ints/Floats. The 5-byte figure assumes a 1-byte type tag plus a 4-byte value; I did not verify the element encoding byte by byte.
- [I] On iOS there is no documented `NSData` → `ByteArray` path. Plan to send an array of `NSNumber` (larger), or a Base64 `NSString`, which the watch decodes with `StringUtil.convertEncodedString`. Either way the per-message size must be tuned empirically, because iOS has no documented numeric limit.
- [I] Throughput is not the bottleneck for 6–30 KB. Even at a pessimistic ~1–3 kB/s, the transfer takes about 10–30 s. The real risks are:
  - GCM or bridge reliability
  - the watch app's memory while the message is materialized
  - message-queue behaviour

### Gaps
- I found no official, current (2025–2026) Garmin figure for:
  - the maximum inbound message size on the watch
  - the iOS maximum
  - phone-to-watch throughput
  The developer.garmin.com "Mobile SDK for Android/iOS" pages could not be fetched.
- I could not read the 2.3.0 or 2.4.0 release notes, so I do not know exactly what changed in 2025–2026. Only commit titles are known.

---

## Q2. Can a DATA FIELD on fēnix 8 receive phone-app messages? Foreground or background, API levels, behaviour when the activity is not open, getting data into Storage

### Takeaway
Yes. On fēnix 8, and on any device at API level 5.0.0 or higher, the `Communications` module is available to foreground data fields. A data field can call `Communications.registerForPhoneAppMessages()` directly in the foreground while the activity is open. The shipping, open-source Breadcrumb data field (minApiLevel 5.0.0, fēnix 8 43/47 mm in its product list) receives whole routes this way.

A background path also exists for API 3.2.0 and higher:
- `Background.registerForPhoneAppMessageEvent()` plus `ServiceDelegate.onPhoneAppMessage()`.
- The background process can write `Application.Storage` directly on CIQ 3.2+ devices, with values limited to 32 KB each.
- Otherwise it can hand data over with `Background.exit()`, which is limited to about 8 KB.

### Cited Findings
- [V] Quote from the Communications module overview: "This module was made available to foreground data fields with API 5.0.0". Listed App Types: Watch App, Audio Content Provider, Background, Data Field, Widget. The module requires the `Communications` permission. — [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [V] `Communications.registerForPhoneAppMessages(method)`:
  - since API Level 1.4.0
  - the callback receives a `PhoneAppMessage` whose payload is `msg.data`
  - waiting messages are delivered immediately on registration
  - Source: [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [V] `Background.registerForPhoneAppMessageEvent()`:
  - "Registers the application to receive an event whenever a phone app message is received."
  - Since API Level 3.2.0.
  - The supported-device list includes "fēnix® 8 43mm", "fēnix® 8 47mm / 51mm", "fēnix® 8 Solar 47mm/51mm", "fēnix® E".
  - Companions: `getPhoneAppMessageEventRegistered()` (3.2.0) and `deletePhoneAppMessageEvent()`.
  - Source: [Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [V] `System.ServiceDelegate.onPhoneAppMessage(msg as Communications.PhoneAppMessage)`, "The callback method that is triggered when a phone app message arrives for this app", since API 3.2.0. — [Toybox.System.ServiceDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ServiceDelegate.html)
- [V] Background module overview: background events let "an application to update its data even when the application is not active". Module since API 2.3.0. — [Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [V] `Background.exit(backgroundData)`:
  - Data "will either be passed immediately to the active application if it is running, or will be saved and passed to the application the next time it runs" via `AppBase.onBackgroundData()`.
  - Throws `ExitDataSizeLimitException` when data "exceeds the data size limit (approximately 8 KB)".
  - Source: [Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [V] `Application.Storage.setValue/getValue/deleteValue`:
  - since API 2.4.0
  - throws `ObjectStoreAccessException` "if called from a background process on device that does not have ConnectIQ 3.2.0 support", which implies background writes are allowed on CIQ 3.2 and later
  - "values are limited to 32 KB in size"
  - the total Object Store size "can vary between devices"; `StorageFullException` is thrown when it is full
  - Source: [Toybox.Application.Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
- [V] "Background processes cannot save Application Properties". — [Toybox.Application.Properties](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Properties.html)
- [V] Working foreground example, `pauljohnston2025/breadcrumb-garmin`:
  - `manifest.xml` declares `type="datafield" … minApiLevel="5.0.0"` and the `Communications` and `Positioning` permissions, with no `Background` permission.
  - The product list includes `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`, `fenixe`.
  - `BreadcrumbApp.onStart()` does `if (Communications has :registerForPhoneAppMessages) { Communications.registerForPhoneAppMessages(method(:onPhone)); }`.
  - `onPhone()` parses route messages of the form `[type, name, [x,y,z,…floats], [directions]]` and writes the route to storage.
  - Latest commit: 2026-08-19.
  - Source: [breadcrumb-garmin source/BreadcrumbApp.mc + manifest.xml](https://github.com/pauljohnston2025/breadcrumb-garmin)
- [V] Working background example, `breadcrumb-garmin-ultra-light`:
  - data field with `minApiLevel="2.4.0"`
  - uses `Background.registerForPhoneAppMessageEvent()`
  - `ServiceDelegate.onPhoneAppMessage()` buffers messages into `Background.exit(oldData)`, keeping at most 3; on `ExitDataSizeLimitException` it falls back to exiting with only the last message
  - `onBackgroundData()` in the foreground consumes them
  - On older devices it falls back to a 5-minute temporal event that calls `Communications.registerForPhoneAppMessages` inside the background process. The author notes this "seems to only work on some devices (tested on ven2s)".
  - Source: [breadcrumb-garmin-ultra-light source/BreadcrumbApp.mc](https://github.com/pauljohnston2025/breadcrumb-garmin-ultra-light)
- [V] Breadcrumb readme: "Some older devices will not support all of the features (eg. routes/ device settings) This is a garmin limitation as those devices (<3.2.0 api) do not support phone app messages for datafields." — [breadcrumb-garmin readme.md](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md)
- [V] Other data fields that use the background phone-message pattern:
  - `buessow/garmin` GlucoseDataField: `Background.registerForPhoneAppMessageEvent()` in `getInitialView`
  - `Artificial-Pancreas/garminWatch` iAPSGarminDataField
  - `elnjensen/LoopGraphDatafield`
  - Sources: [buessow/garmin](https://github.com/buessow/garmin), [Artificial-Pancreas/garminWatch](https://github.com/Artificial-Pancreas/garminWatch), [elnjensen/LoopGraphDatafield](https://github.com/elnjensen/LoopGraphDatafield)
- [H] Forum answer: without a background service, a data field "stops running when you exit the activity". — [Forum: Does my datafield run in the background only if an activity is using it?](https://forums.garmin.com/developer/connect-iq/f/discussion/403750/does-my-datafield-run-in-the-background-only-if-an-activity-is-using-it)
- [H] Forum thread on passing data from background `onPhoneAppMessage` to the foreground. Its points: Properties cannot be set in the background; developers use `Background.exit()`. — [Forum: How can I pass data from background process' onPhoneAppMessage to foreground?](https://forums.garmin.com/developer/connect-iq/f/discussion/269180/how-can-i-pass-data-from-background-process-onphoneappmessage-to-foreground)

### Inferences
- [I] Simplest design for a fēnix 8 only: a foreground receiver. Register in `onStart()`, accept chunks, write each chunk (a ByteArray of 16 KB or less) to `Storage` under keys like `crs_0`, `crs_1`, and so on, then parse. This requires the user to be in an activity with the data field on a visible page, or at least loaded in the activity. Messages sent while the data field is not running should queue in the mailbox and be delivered on the next registration; the doc's "messages waiting … will immediately be called" suggests this. How long queued messages persist is not documented.
- [I] Doing the upload before the activity, e.g. the evening before, needs the background path. Add the `Background` permission, call `Background.registerForPhoneAppMessageEvent()`, and in `onPhoneAppMessage` write chunks straight into `Storage`, which is allowed on CIQ 3.2+ including fēnix 8. `Background.exit()` is only a tiny signal, since its limit is about 8 KB. Whether a data field's background service is woken by a phone message when no activity has loaded that data field is not confirmed by any source I could reach. The forum hearsay about data fields not running outside activities makes this uncertain, so test it on the device.
- [I] Background-process memory for data fields is much smaller than foreground memory (see the device JSON/memory research by other researchers). A 15 KB chunk plus deserialization overhead in the background may be tight. Chunk sizes of 4–8 KB are the safer default for the background path.

### Gaps
- I found no source confirming whether, on fēnix 8, `onPhoneAppMessage` in a data field's background service fires when the data field is not part of a running activity.
- I found no source on the retention time or capacity of the device-side phone-message mailbox.
- I found no official statement of the per-message RAM limit for data-field background processes on fēnix 8.

---

## Q3. Can the phone app open or trigger the watch app? Can data fields be targeted?

### Takeaway
The Mobile SDK has `openApplication` (Android) and `openAppRequest:` (iOS). These show a prompt on the watch asking whether to open an app. That is meaningful only for device apps and widgets. A developer reports it does nothing for data fields. Messages can be addressed to a data field's app UUID like any other app, and delivery works (Breadcrumb does this), but the data field must be running (foreground) or registered for the background phone-message event. `Background.requestApplicationWake()` is documented as widget or device-app only.

### Cited Findings
- [V] iOS: "A companion app can request that a CIQ app be opened on the target device. When doing so a prompt will be displayed to the user on the Garmin device… `openAppRequest:`". The result codes include `Failure_PromptNotDisplayed` and `Failure_AppAlreadyRunning`. — [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)
- [V] Android: `openApplication(IQDevice, IQApp, IQOpenApplicationListener)` with `IQOpenApplicationStatus` = `PROMPT_SHOWN_ON_DEVICE`, `PROMPT_NOT_SHOWN_ON_DEVICE`, `APP_IS_NOT_INSTALLED`, `APP_IS_ALREADY_RUNNING`, `UNKNOWN_FAILURE`. — [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)
- [V] First-hand developer comment in a data-field companion app: "does not seem to work with data fields — get PROMPT_SHOWN_ON_DEVICE if we do not have an activity open (but not running), but no prompt is shown; get PROMPT_NOT_SHOWN_ON_DEVICE is the activity is open". Also: "we get a log saying PROMPT_SHOWN_ON_DEVICE, but i do [not] see anything". — [breadcrumb-mobile Connection.kt](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [V] `Background.requestApplicationWake(message)`: "This request is only valid for widget or device app background tasks, and will be ignored by watch face apps". The message is limited to 255 bytes. — [Toybox.Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- [V] Breadcrumb's companion lets the user pick the target app and data field by UUID ("You must set the connect iq app you wish to talk to (this is the app/datafield installed on the watch)"). Its "Auto/All" mode sends to all detected Breadcrumb apps and data fields. — [breadcrumb-mobile manual.md](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [V] iOS guide: `IQApp` is created with `appWithUUID:device:`, and `getAppStatus` reports `isInstalled` and `version`. — [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)

### Inferences
- [I] For a data field, the phone cannot launch it remotely. The workflow must be one of these:
  - (a) the user starts the activity with the data field on screen, then presses "Send" on the phone
  - (b) rely on the background phone-message event, whose behaviour outside an activity is unconfirmed (see Q2)
  - (c) rely on the mailbox queueing messages until the data field next registers
- [I] A hybrid is possible: bundle a tiny device app or widget in a separate project to receive and persist the course. However, Connect IQ apps cannot share `Storage` with each other; there is an open forum request to "Allow shared storage between apps". A separate app therefore cannot hand data to the data field. The receiver must be the data field itself. — see [Forum: Allow shared storage between apps](https://forums.garmin.com/developer/connect-iq/i/bug-reports/allow-shared-storage-between-apps?pifragment-706=4)

### Gaps
- There is no official Garmin statement on `openApplication` behaviour for data fields; the only source is a developer comment.

---

## Q4. Effort and distribution for personal use: publishing, Garmin approval, sideloading

### Takeaway
The phone app does not need to be published:
- On Android, sideloading a self-built APK is enough. Breadcrumb distributes its companion as an APK on GitHub releases.
- On iOS, the app can be installed from Xcode with a free Apple ID, but the free provisioning profile expires every 7 days. A paid Apple Developer membership gives roughly 1-year profiles and TestFlight.

No Garmin approval step for the companion app itself was found. The download is governed by the SDK license agreement. The larger uncertainty is the watch side. Several forum reports say a data field sideloaded over USB may not be reachable from a companion app ("the mobile module is not installed on the phone"). The practical workaround is to upload the data field as a private beta app on the Connect IQ developer dashboard and install it through the Connect IQ phone app. That flow itself has had bugs in 2025–2026.

### Cited Findings
- [V] Breadcrumb's Android companion: "Install the latest apk from the release page or build from source using android studio/gradle". It is Android-only; the author invites iOS contributions. — [breadcrumb-mobile README](https://github.com/pauljohnston2025/breadcrumb-mobile) and [breadcrumb-garmin readme](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md)
- [V] SDK license: both Garmin repos state that downloading the SDK means accepting Garmin's License Agreement. I saw no mention of an approval or registration step for companion apps. — [garmin/connectiq-companion-app-sdk-ios README](https://github.com/garmin/connectiq-companion-app-sdk-ios), [garmin/connectiq-android-sdk README](https://github.com/garmin/connectiq-android-sdk/blob/main/README.md)
- [V] The Android SDK is a plain Maven Central artifact (`com.garmin.connectiq:ciq-companion-app-sdk`), usable from Gradle with no Garmin account. The iOS SDK is a public GitHub Swift Package with a binary xcframework. — [Maven Central](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/), [iOS SDK repo](https://github.com/garmin/connectiq-companion-app-sdk-ios)
- [H] Apple free provisioning ("Personal Team") profiles last 7 days, so apps must be reinstalled weekly. Paid membership profiles last about a year. — [Apple Developer Forums thread 69248](https://developer.apple.com/forums/thread/69248); [myByways: limitations of free Apple developer account](https://mybyways.com/blog/new-limitations-imposed-on-free-apple-developer-account/)
- [H] Feb 2026 forum thread "Best workflow for developing/testing Connect IQ app with mobile companion?": "when you sideload the app via USB, the mobile module is not installed on the phone, so the communication path doesn't exist". The thread asks whether one must always install via Beta or the Store. — [Forum thread 430465](https://forums.garmin.com/developer/connect-iq/f/discussion/430465/best-workflow-for-developing-testing-connect-iq-app-with-mobile-companion)
- [H] A 2025/26 thread on an iOS companion (FR245M, SDK 9.2.0) makes the same point about the missing mobile module for sideloaded apps. — [Forum thread 440779](https://forums.garmin.com/developer/connect-iq/f/discussion/440779/app-communication-with-watch)
- [H] Contradicting or nuancing report: the GCM 5.27.3 bug report says its failure was "reproduced with both store-installed and sideloaded builds". That implies the reporter at least attempted sideloaded builds with a companion. — [Forum bug report](https://forums.garmin.com/developer/connect-iq/i/bug-reports/gcm-5-27-3-android-accepts-communications-transmit-messages-from-watch-app-but-never-delivers-them-to-the-companion-app)
- [H] An older thread (id 226330, around 2020) asks whether an iOS app can talk to a sideloaded CIQ app. The answer was not visible in the snippets. — [Forum: IOS App and SideLoaded ConnectIQ](https://forums.garmin.com/developer/connect-iq/f/discussion/226330/ios-app-and-sideloaded-connectiq)
- [H] Beta apps:
  - Upload to the developer dashboard (now apps-developer.garmin.com) and install through the Connect IQ mobile app while logged in as the same user; the app "will forever stay in pending state, but that's fine".
  - The dashboard and Garmin Express no longer install apps directly.
  - Links from the new dashboard domain do not deep-link into the IQ app; emailing the link to yourself is the workaround.
  - Bug report title: "Installing beta apps is almost impossible now".
  - "sideloading apps for testing disables settings changes via the Connect IQ phone app"
  - Sources: [Forum: How does one install a beta app?](https://forums.garmin.com/developer/connect-iq/f/connect-iq-web-store/427577/how-does-one-install-a-beta-app); [Forum bug: Installing beta apps is almost impossible now](https://forums.garmin.com/developer/connect-iq/i/bug-reports/installing-beta-apps-is-almost-impossible-now); [Garmin doc: Beta Apps](https://developer.garmin.com/connect-iq/core-topics/beta-apps/)
- [V] Breadcrumb's own development note: for simulator testing, "Must port forward both adb and the tile server for the simulator to be able to fetch tiles from the companion app" (TETHERED/ADB mode). — [breadcrumb-garmin readme](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md)

### Inferences
- [I] Effort estimate for a minimal Android-only companion:
  - one Activity: pick a GPX with the Storage Access Framework, parse and preprocess it in Kotlin (downsample and quantize elevation to bytes), chunk it into `byte[]` of 12 KB or less, then call `sendMessage` with an ack or retry loop
  - the watch side registers `registerForPhoneAppMessages` and reassembles into `Storage`
  - total roughly 300–600 lines of Kotlin plus 100–200 lines of Monkey C
  - realistic calendar effort is 1–3 days, most of it spent debugging GCM and device-pairing quirks rather than writing code
- [I] Adding iOS doubles the effort: Swift/ObjC, the GCM URL-scheme device-selection dance, and weekly re-signing unless the user pays $99/yr.
- [I] Biggest distribution risk: the watch data field probably has to be installed through the Connect IQ Store as a private beta, not USB-sideloaded, for the phone to see it (hearsay, not confirmed). That undermines the "no rebuild per course" benefit only slightly, since the data field is built once, but it adds a Garmin developer-dashboard dependency.

### Gaps
- There is no authoritative Garmin statement on whether USB-sideloaded apps can receive Mobile SDK messages on Android versus iOS in 2026. The developer.garmin.com FAQ "How Do I Use the Connect IQ Mobile SDK" and the "Communicating with Mobile Apps" page could not be fetched.
- I did not find whether a private beta app has any visibility or approval constraints beyond "pending".

---

## Q5. Open-source examples: companion apps sending data to Connect IQ apps, especially routes and tracks

### Takeaway
The best match is Breadcrumb by pauljohnston2025. It is an open-source Connect IQ data field for route and breadcrumb navigation, with an elevation overview, that supports fēnix 8. Its open-source Android companion (Kotlin/Compose) imports GPX, Komoot and Google Maps routes, simplifies them, and sends them by `sendMessage`. It also serves map tiles to the watch over a localhost HTTP server. Several diabetes (CGM) projects are mature examples of phone-to-data-field messaging.

### Cited Findings
- [V] **pauljohnston2025/breadcrumb-garmin** (data field, API 5.0+, fēnix 8 supported, active in 2026). Features:
  - "Elevation Overview: Shows an elevation profile of the route"
  - "Routing (companion app required): Users can import routes from Google Maps or GPX files using the companion app"
  - Offline map tiles "via Bluetooth transfer"
  - Store listings: "Breadcrumb Trail Navigation"
  - Source: [GitHub](https://github.com/pauljohnston2025/breadcrumb-garmin); [Connect IQ Store listing](https://apps.garmin.com/apps/40e128d2-db98-41d1-b5a9-624a725e6e68)
- [V] **pauljohnston2025/breadcrumb-mobile**: Android companion in Kotlin Multiplatform/Compose, using `ConnectIQ.sendMessage` with `IQSendMessageListener`. It builds the payload as `[type, …payload]` Lists. GPX simplification options: Douglas-Peucker, Reumann-Witkam, Visvalingam-Whyatt, a coordinate-point cap (~400 recommended) and a turn-point cap. Last commit 2026-08-07. — [GitHub](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [V] **pauljohnston2025/breadcrumb-garmin-ultra-light** and **-light-weight**: variants for older, low-memory devices that use background phone messages. — [ultra-light](https://github.com/pauljohnston2025/breadcrumb-garmin-ultra-light), [light-weight](https://github.com/pauljohnston2025/breadcrumb-garmin-light-weight)
- [V] **garmin/connectiq-android-sdk** ("Comm Android" sample, Kotlin, updated to SDK 2.4.0 on 2026-04-01) and **garmin/connectiq-companion-app-example-ios** (the official iOS example). — [Android](https://github.com/garmin/connectiq-android-sdk), [iOS](https://github.com/garmin/connectiq-companion-app-example-ios)
- [V] **MatyasKriz/ios-connect-iq-comms**: two-way iOS ↔ Connect IQ example. — [GitHub](https://github.com/MatyasKriz/ios-connect-iq-comms)
- [V] **cjsmith/react-native-connect-iq-mobile-sdk**: React Native wrapper that exposes `IQMessageStatus` including `FAILURE_MESSAGE_TOO_LARGE`. — [GitHub](https://github.com/cjsmith/react-native-connect-iq-mobile-sdk)
- [V] **nightscout/AndroidAPS** Garmin plugin: uses a local HTTP port, `LocalHttpPort` default 28891, plus a ConnectIQ device client with tests covering `FAILURE_MESSAGE_TOO_LARGE`. — [GitHub](https://github.com/nightscout/AndroidAPS)
- [V] **j-kaltes/Juggluco**: CGM app with a Garmin status mapping of all `IQMessageStatus` codes. — [GitHub](https://github.com/j-kaltes/Juggluco)
- [V] **buessow/garmin**, **Artificial-Pancreas/garminWatch**, **elnjensen/LoopGraphDatafield**: data fields receiving phone messages by the background event. — [buessow/garmin](https://github.com/buessow/garmin), [Artificial-Pancreas/garminWatch](https://github.com/Artificial-Pancreas/garminWatch), [LoopGraphDatafield](https://github.com/elnjensen/LoopGraphDatafield)
- [V] **grigorye/Handsfree**, **RomanDrechsel/garmin-list-iq**, **cspotcode/garmin-audio-share**: device apps and ACP apps using `Background.registerForPhoneAppMessageEvent`. — [Handsfree](https://github.com/grigorye/Handsfree), [garmin-list-iq](https://github.com/RomanDrechsel/garmin-list-iq), [garmin-audio-share](https://github.com/cspotcode/garmin-audio-share)
- [V] **MNThomson/orgmaps**: patch set adding "Turn-by-turn navigation on watch" (Garmin) to an Organic Maps fork. — [GitHub](https://github.com/MNThomson/orgmaps)
- [V] **zomboky/garmin-app**: Android companion "CorridorTransferManager" that sends map corridors by `sendMessage`. It is a prototype; its throughput numbers are unmeasured. — [GitHub](https://github.com/zomboky/garmin-app)

### Inferences
- [I] Breadcrumb is effectively a reference implementation of the proposed architecture: GPX on the phone, preprocessing, then `sendMessage` to a data field, then storage on the watch. Its code gives protocol framing, error handling and GCM workarounds that can be copied. Its GPL/other license must be checked before reuse; I did not read `LICENSE.txt`.

### Gaps
- I found no open-source iOS companion that sends routes to a data field. Breadcrumb explicitly lacks iOS.

---

## Q6. Simpler alternatives without a companion app (polling a URL, app settings, OAuth, newer Garmin features)

### Takeaway
The main alternative is for the data field itself to download from a URL with `Communications.makeWebRequest`. On fēnix 8 this is allowed in the foreground data field (API 5.0.0 and higher) and in background services. Traffic goes through the phone's Garmin Connect app over BLE, or over Wi-Fi where the device supports it.

Other options are weaker:
- App settings (Properties) are editable from the Garmin Connect / Connect IQ phone app, but are meant for small values. Hearsay reports even about 40-character strings causing trouble because of the total settings payload.
- `makeOAuthRequest` only obtains OAuth tokens through GCM. It is not a data channel, but it would enable authenticated downloads.
- A hybrid used by Breadcrumb and AndroidAPS runs a local HTTP server inside an Android companion app. The watch fetches `http://127.0.0.1:port` through `makeWebRequest`. This avoids the 16 KB message limit and mailbox semantics, but it is Android-only in practice and has historically been fragile.

I found no newer Garmin feature (2025–2026) for syncing arbitrary data into Connect IQ apps.

### Cited Findings
- [V] `makeWebRequest(url, params, options, callback)`:
  - since API 1.3.0
  - "This method can be used when connected to WiFi or a mobile device over Bluetooth"
  - options include `:responseType`, `:maxBandwidth` and `:fileDownloadProgressCallback` (media only, CIQ 3.2.0+)
  - Source: [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [V] Communications is available to foreground data fields from API 5.0.0 (see Q2). — [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [H] Data fields on older devices can only web-request from a background temporal event, and that event cannot run more often than every 5 minutes. On newer devices (API 3.3+ or 5.0+) it can be done in the foreground. Thread dated December 2025. — [Forum: Early makeWebRequest in a data field?](https://forums.garmin.com/developer/connect-iq/f/discussion/427067/early-makewebrequest-in-a-data-field)
- [V] `makeOAuthRequest(...)`: "Request an OAuth sign-in through Garmin Connect Mobile". Results come back through `registerForOAuthMessages`. Garmin's own example then uses the token with `makeWebRequest`. — [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [V] Localhost pattern:
  - The Breadcrumb data field fetches tiles from its companion at `const COMPANION_APP_TILE_URL = "http://127.0.0.1:8080"`.
  - AndroidAPS exposes `LocalHttpPort` 28891 for its Garmin apps.
  - Sources: [breadcrumb-garmin source/Settings.mc](https://github.com/pauljohnston2025/breadcrumb-garmin), [AndroidAPS GarminIntKey.kt](https://github.com/nightscout/AndroidAPS)
- [H] Localhost fragility:
  - GCM Android 4.20 raised `targetSdkVersion` to 28, which made Android enforce HTTPS and broke `http://localhost` for a while.
  - Separately, `HTTP_RESPONSE_CONTENT_TYPE_FIT` from 127.0.0.1 fails on Android GCM while JSON works.
  - Sources: [Forum: Breakage of makeWebRequest from http://localhost](https://forums.garmin.com/developer/connect-iq/f/discussion/167402/breakage-of-makewebrequest-from-http-localhost); [Forum bug: GCM Android unable to handle FIT on 127.0.0.1](https://forums.garmin.com/developer/connect-iq/i/bug-reports/garmin-connect-mobile-on-android-unable-to-handle-makewebrequest-comm-http_response_content_type_fit-on-127-0-01-localhost)
- [H] Settings size: "Property value with a long string 40 characters cannot be saved". Snippets attribute the problem to the total settings payload size rather than a per-string cap. — [Forum thread 298660](https://forums.garmin.com/developer/connect-iq/f/discussion/298660/property-value-with-a-long-string-40-characters-cannot-be-saved)
- [V] `Storage` values are capped at 32 KB each (see Q2). Properties cannot be written from the background. — [Toybox.Application.Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html), [Toybox.Application.Properties](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Properties.html)
- [V] Breadcrumb's readme notes that all settings can be configured "directly on the watch or through Connect IQ settings" without the companion. Routes, however, need the companion: "the routes can be edited [in the companion] (unlike on the Garmin connect settings)". — [breadcrumb-garmin readme](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/master/readme.md), [breadcrumb-mobile manual.md](https://github.com/pauljohnston2025/breadcrumb-mobile)
- [V] Connect IQ System 8 (SDK 8.x, 2025) headline features are extended code space, sensor pairing and a notifications API. None concerns syncing data into apps. — [the5krunner: Connect IQ 8](https://the5krunner.com/2025/01/07/connect-iq-8-what-we-know-so-far-about-system-8/); [Forum: Connect IQ SDK 8.2 Now Available](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/connect-iq-sdk-8-2-now-available)

### Inferences
- [I] A settings-string hack does not fit 6–30 KB of Base64 (8–40 KB of text): the settings pipeline is designed for small values and hearsay shows trouble at tiny sizes. The practical app-settings use is to pass a URL or course ID, which the data field then fetches with `makeWebRequest`. This "settings holds the pointer, web holds the payload" pattern needs no companion app.
- [I] OAuth is unnecessary unless the course host requires sign-in. A private unguessable URL (a static file on GitHub Pages or an S3 or Cloudflare bucket), or a small serverless endpoint that converts GPX to JSON, is simpler.

### Gaps
- I found no authoritative maximum length for a String property edited in Garmin Connect settings, and no maximum total settings size.
- I could not verify iOS GCM behaviour for `http://127.0.0.1` requests.

---

## Q7. Short comparison: companion-app route vs web-download route (for this project)

### Takeaway
For a single fēnix 8 AMOLED user, the web-download route (`makeWebRequest` from the data field, with the URL in settings or fixed) is less effort and more robust than building a companion app:
- no phone app to build or sign
- no 16 KB message chunking
- no mailbox or launch semantics

The companion route earns its keep only if these matter:
- offline file picking on the phone, with no internet at the trailhead
- no server at all
- very large payloads combined with interactive UX

Breadcrumb shows that the companion route works on fēnix 8 for exactly this use case, route plus elevation.

### Cited Findings
- [V] Companion route facts:
  - Android message cap is 16,384 bytes serialized, so a 30 KB course needs chunking. — [AAR 2.4.0](https://repo1.maven.org/maven2/com/garmin/connectiq/ciq-companion-app-sdk/2.4.0/ciq-companion-app-sdk-2.4.0.aar)
  - GCM is required on Android and needed for discovery on iOS. — [iOS SDK guide](https://github.com/garmin/connectiq-companion-app-sdk-ios/tree/main/documentation)
  - The data field cannot be launched remotely. — [breadcrumb-mobile Connection.kt](https://github.com/pauljohnston2025/breadcrumb-mobile)
  - Proven on fēnix 8 by Breadcrumb. — [breadcrumb-garmin](https://github.com/pauljohnston2025/breadcrumb-garmin)
- [V] Web route facts: `makeWebRequest` works over the phone's BLE link or Wi-Fi, and is allowed in foreground data fields from API 5.0.0. — [Toybox.Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- [H] Forum reports of lost companion messages and GCM delivery bugs in 2025–2026. — [GCM 5.27.3 bug](https://forums.garmin.com/developer/connect-iq/i/bug-reports/gcm-5-27-3-android-accepts-communications-transmit-messages-from-watch-app-but-never-delivers-them-to-the-companion-app); [Update data field from companion app](https://forums.garmin.com/developer/connect-iq/f/discussion/372069/update-data-field-from-companion-app)

### Inferences
[I] Comparison matrix, my judgement:

| Criterion | Companion app (Mobile SDK) | Web download (`makeWebRequest`) |
|---|---|---|
| Build effort | Android: 1–3 days; iOS extra, with 7-day re-signing or $99/yr | Data field code plus a static host or tiny endpoint: ~0.5–1 day |
| Phone requirements | Custom app + GCM | GCM only (already installed) |
| Internet needed at transfer time | No (BLE only) | Yes (phone data or Wi-Fi) |
| Size handling | Chunk to ≤16 KB (Android); reassemble on watch | Watch response size limits apply; see web-download research |
| Triggering | User must have the activity open, or rely on the background event (unconfirmed for data fields) | Data field fetches on its own schedule, e.g. at activity start or when the URL in settings changes |
| Sideload vs store | Hearsay says a store or private-beta install may be needed for phone comms | USB sideload is fine for web requests; settings editing via the phone is disabled for sideloaded apps (hearsay) |
| Reliability history | Multiple GCM/SDK message bugs 2020–2026 | GCM web-proxy issues exist too, but the path is more widely used |

- [I] Recommendation for the report writer to weigh: prototype the web route first. Keep the companion route as the fallback when the requirement is "no internet or no server". If chosen, build Android only and copy Breadcrumb's framing, sending a `byte[]` chunk of 12 KB or less with a header of seq/total/courseId.

### Gaps
- There is no measured end-to-end timing for either route on a fēnix 8 with a 30 KB payload. This needs a hands-on test.
