# Connect IQ data field: downloading a course over the phone link (background service vs. foreground web requests) and practical limits

Source notes (read first):
- developer.garmin.com and forums.garmin.com could not be fetched from this environment (egress blocked). Official API reference text was read from a GitHub mirror of the Garmin SDK HTML docs converted to Markdown: [tkafka/garmin-sdk-docs-for-ai](https://github.com/tkafka/garmin-sdk-docs-for-ai). The mirror's SDK version is not stated, but its "Supported Devices" lists include fēnix 8 43mm / 47mm / 51mm / Solar, so it is a recent SDK (2024 or later). Its README says the docs were "gutted to only keep parts relevant for watchface development", but the Background, Communications, Storage, AppBase and ServiceDelegate pages were present. Citations below link the official URL and note "(via mirror)".
- Forum content comes only from search-engine snippets. The snippets paraphrase posts and cannot be checked against the full thread, so every forum item is labeled "forum (snippet)" and treated as hearsay unless an official doc confirms it.
- Device memory numbers come from the SDK `compiler.json` device files that projects copied onto GitHub. That is primary data, but the copies have no dates.

---

## Q1. Can a data field call Communications.makeWebRequest in the foreground, or only from a background ServiceDelegate?

### Takeaway
Since API 5.0.0 (Connect IQ System 7), data fields can call parts of the Communications module, including makeWebRequest, in the foreground (main process). The fēnix 8 runs API 5.x or later, so it qualifies. Before API 5.0.0, data fields had to use a background ServiceDelegate. This matters a lot for the design: on a fēnix 8 the field can download directly while the activity is open, with no 5-minute temporal-event wait and no ~8 KB Background.exit limit.

### Cited Findings
- The official Communications module page says: "This module was made available to foreground data fields with API 5.0.0". Its App Types list includes "Background" and "Data Field", and it needs the `Communications` permission. — [Toybox.Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md); official: [developer.garmin.com Communications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
- Garmin's "Welcome to System 7" announcement (snippet): "In the past, data fields did not support the Communications module directly, instead requiring a background ServiceDelegate. In API 5.0.0, data fields can use select Communications APIs within the main application." The snippet does not say which "select" APIs are included. — [Welcome to System 7, Garmin forums (snippet)](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/welcome-to-system-7)
- Third-party coverage of CIQ 7 describes the same change: data fields can talk to cloud services directly, and BLE bonding ("Just Works") was added. — [the5krunner, CIQ 7 deep dive](https://the5krunner.com/2023/12/20/garmin-to-introduce-ble-bonding-and-more-in-ciq-7/); [Notebookcheck, System 7](https://www.notebookcheck.net/Garmin-Connect-IQ-System-7-arrives-with-new-features.785586.0.html)
- Real-world proof: the open-source **Breadcrumb** data field (`type="datafield"`, `minApiLevel="5.0.0"`, targets `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`) calls `Communications.makeWebRequest` and `makeImageRequest` from foreground code. Its manifest declares the `Communications`, `DataFieldAlert` and `Positioning` permissions and does not declare `Background`. — [breadcrumb-garmin manifest.xml](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/manifest.xml); [breadcrumb-garmin source/WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)
- Breadcrumb source comments report two further limits:
  - `Toybox.Timer` is not available to data fields ("Error: Permission Required ; Details: Module 'Toybox.Timer' not available to 'Data Field'"), so the next queued request has to be started from `compute()`.
  - Handling errors inline, such as when `BLE_CONNECTION_UNAVAILABLE` comes back synchronously, caused stack overflows, so the author keeps a request queue with an outstanding count.
  — [breadcrumb-garmin WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)
- Older and pre-API-5 forum advice (snippets) says the proper way for a data field to make web requests is a background temporal event with a 5-minute minimum. The thread "Early makeWebRequest in a data field?" talks about "devices running modern SDKs (after API level 3.3)" and does not mention the API 5 foreground option in the snippet. — [Early makeWebRequest in a data field? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/427067/early-makewebrequest-in-a-data-field); [How can I run a webRequest on demand ("now") from a datafield? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/323518/how-can-i-run-a-webrequest-on-demand-now-from-a-datafield)

### Inferences
- For a fēnix 8-only personal field (`minApiLevel` 5.0.0 or higher), foreground makeWebRequest is the simpler route. The download can start right after the activity is opened and the field is loaded, the full data field memory is available (128 KB on fēnix 8; see Q4), there is no 8 KB exit limit, and requests can be chained from the response callback.
- A background service is still worth considering, but only as a way to prefetch the course before the activity starts (see Q3 for when it runs), and only with small chunks.
- Because Timer is not available, a foreground chain should start the next request from the callback itself or from `compute()` (called about once per second).

### Gaps
- I could not read the exact list of "select Communications APIs" allowed for foreground data fields. makeWebRequest is confirmed by the module note and by Breadcrumb's use. Whether `makeImageRequest`, `transmit` or `registerForPhoneAppMessages` are allowed was not checked in official text; Breadcrumb uses makeImageRequest and transmit, which suggests they work.
- I did not verify whether foreground makeWebRequest works before the activity timer is started, i.e. in the pre-start "GPS searching" screen. See Q3.

---

## Q2. Background temporal events: minimum interval, use by data fields, immediate first trigger, chaining requests, and the time limit of a background run

### Takeaway
- **Minimum interval:** 5 minutes between temporal events.
- **Immediate first run:** a Moment in the past fires immediately, but only if the last temporal event was at least 5 minutes ago. The documented exemption that clears the 5-minute rule on app startup applies to watch apps and widgets, not data fields.
- **Time limit:** a background run is killed after 30 seconds.
- **Chaining:** several web requests can be chained inside one run by starting the next from the previous callback. Only the delegate function itself is guaranteed to complete.

### Cited Findings
- `registerForTemporalEvent(time as Moment or Duration)` (API 2.3.0), per the official docs:
  - "If a temporal event is scheduled for a time in the past, the event will trigger immediately."
  - "Temporal events cannot be set to occur less than 5 minutes after the last temporal event occurred. For watch-apps and widgets the 5 minute restriction is cleared on application startup if the event was specified using a Moment."
  - "Only one temporal event may be registered at a time. Calling registerForTemporalEvent will overwrite any previously registered temporal events."
  - It throws `InvalidBackgroundTimeException` if the event "Occurs less than five minutes after the last background event occurred" or "Has a duration of less than five minutes".
  — [Toybox.Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md); official: [Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
- The official `getLastTemporalEventTime()` example (API 2.3.0) is the documented "as soon as allowed" pattern. If `lastTime != null` it registers `lastTime.add(FIVE_MINUTES)` (comment: "Events scheduled for a time in the past trigger immediately"); otherwise it calls `registerForTemporalEvent(Time.now())`. Per the docs, the function may return null "if no previous temporal background event has occurred or if the device app or widget has been started since the event was last triggered". — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)
- `getTemporalEventRegisteredTime()` (API 3.0.0) returns the registered Moment or Duration, or null. `deleteTemporalEvent()` removes the event. — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)
- Official `AppBase.getServiceDelegate()` text: "The background task will be automatically terminated after 30 seconds if it is not exited by these methods" (`Background.exit()` or `System.exit()`). — [AppBase (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md); official: [AppBase](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html)
- Official `System.ServiceDelegate` text: "A callback function within the delegate can be used to initiate other system events (e.g. Communications), but only the delegate function is guaranteed to complete. The Background process may be shut down at any time to handle higher priority processes." The official example starts makeWebRequest in `onTemporalEvent()` and calls `Background.exit()` in the response callback. — [ServiceDelegate (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/System/ServiceDelegate.md); official: [ServiceDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/System/ServiceDelegate.html)
- Bug report (snippet): when the BLE link returns an error such as `BLE_HOST_TIMEOUT`, "the background process terminates after 30 seconds without sending any data or error message back to the application process". — [Background process exits before makeWebRequest times out (snippet)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/background-process-exits-before-makewebrequest-times-out)
- Forum (snippet), "Early makeWebRequest in a data field?":
  - Scheduling immediately fails with the exception "Background event period cannot be less than 5 minutes".
  - Another user says the background request can run immediately at app start "as long as you haven't run the app recently", by calling `Background.registerForTemporalEvent()` with `Time.now()` in the app's `initialize()`.
  - Another snippet: "call registerForTemporalEvent with a Duration, not a Moment. If the event hasn't run in the last 5 minutes, it should run immediately."
  — [Early makeWebRequest in a data field? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/427067/early-makewebrequest-in-a-data-field)
- Forum (snippet): "If you haven't used Background.registerForTemporalEvent in the last 5 minutes, you can call it with 0 and it will be executed immediately". Also: "The background app runs before the foreground app when you run the app". — [How can I run a webRequest on demand ("now") from a datafield? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/323518/how-can-i-run-a-webrequest-on-demand-now-from-a-datafield)
- Forum (snippet, old forum): "You can have 3 outstanding makeWebRequests at the same time", with past issues when running 3 on Android. The recommended pattern is to chain: request 1, then request 2 inside its callback. — [Can a watchface make several webrequests (old forum, snippet)](https://forums.garmin.com/forum/developers/connect-iq/1303819-can-a-watchface-make-several-webrequests); example repo: [aronsommer/WebRequestMultiple-Widget](https://github.com/aronsommer/WebRequestMultiple-Widget)
- Official error codes: `BLE_QUEUE_FULL = -101` ("Too many requests have been made"). `cancelAllRequests()` exists because "The number of active requests running in parallel is limited". — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- A thread titled "DataField Temporal webrequest returns -101" exists. Its content was not retrievable. — [forum 330654](https://forums.garmin.com/developer/connect-iq/f/discussion/330654/datafield-temporal-webrequest-returns--101)

### Inferences
- The forum reports conflict on the surface. The official wording suggests they reconcile like this:
  - A **Moment** in the past, including `Time.now()`, fires at once only if at least 5 minutes have passed since the last temporal event.
  - A **Duration** under 5 minutes is always rejected, which is likely the "period cannot be less than 5 minutes" message.
  - For data fields, the startup exemption does not apply. If the user restarts the activity within 5 minutes of the last background run, registering `Time.now()` would throw or would need to be clamped to `lastTime + 5 min`.
  - The safe pattern is the doc's `getLastTemporalEventTime()` example, wrapped in try/catch.
- Chaining 2–4 sequential requests in one 30-second run is plausible over a healthy BLE link. Each round trip through Garmin Connect Mobile typically takes seconds (not measured here), and there is no guarantee the run completes. Every chunk should be persisted as soon as it arrives (see Q5) so a killed run loses at most one chunk.

### Gaps
- There is no official per-request or per-run request-count limit beyond "limited"; the "3 outstanding" figure is old forum hearsay.
- I did not measure BLE round-trip latency through Garmin Connect Mobile for 5–10 KB responses on a fēnix 8.

---

## Q3. When does a data field's background service actually run: only during the activity, only after the timer starts, or also on the watch face?

### Takeaway
The data field's own code (foreground) runs only while an activity that has the field in one of its data screens is open. By forum accounts, a temporal event registered by a data field keeps firing in the background on its schedule, even after the activity ends, the field is removed, or the watch reboots, until the app deletes it. Garmin docs do not state the data-field-specific scheduling rules.

### Cited Findings
- Official Background overview: background events allow "an application to update its data even when the application is not active." — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)
- Forum (snippet): "A datafield should only execute if it's included in a layout of the currently running activity". There are known bugs where a CIQ field ran while not in the current activity; for example, users reported Stryd Zones recording developer fields in activities that did not include it. — [Does my datafield run in the background only if an activity is using it? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/403750/does-my-datafield-run-in-the-background-only-if-an-activity-is-using-it)
- Forum (snippet): "Once started, if you have it set to run the temporal event say every 5 minutes, it will keep running every 5 minutes until you delete the temporal event, so it can run long after the activity is stopped/saved." — [same thread 403750 (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/403750/does-my-datafield-run-in-the-background-only-if-an-activity-is-using-it)
- Forum (snippet), "Background Process Termination?":
  - A background process started from a data field "runs independent of the execution of the actual data field", even when "you remove the data field or switch to another ride profile that doesn't include the data field, or even reboot the device".
  - Recommended cleanup: delete the temporal event in `onStop()`. There is a catch: `onStop` also runs when the background process exits, so the code must check which process it is in. `onStop` may not be called for data fields on some devices, and `onReset` (on SAVE) was suggested instead.
  - "A background service runs for at most 30 seconds at a time."
  — [Background Process Termination? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/330437/background-process-termination)
- Forum (snippet): "A Data Field runs from when you start an activity until you exit the activity... If you don't have a background service, it stops running when you exit the activity." — [search-result summary drawing on forum threads 7496/330437 (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/7496/simpledatafield)
- Official `Background.exit()`: data "will either be passed immediately to the active application if it is running, or will be saved and passed to the application the next time it runs". `AppBase.onBackgroundData()`: if the main app is not active, the data is delivered "after the onStart() method completes" on the next launch. — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md); [AppBase (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md)

### Inferences
- **Registration timing:** a data field's app is created when an activity profile containing it is opened, before the timer starts. The field can therefore register the temporal event, or with API 5 make a foreground request, as soon as the activity screen opens, in the "GPS searching / ready" state. This is consistent with "runs from when you start an activity" but not confirmed for pre-timer states, so verify on device.
- **Prefetch option:** because the temporal event outlives the activity, a periodic event (say every 15–60 minutes) could prefetch a new course while the watch sits on the watch face. The next activity would then find it in Storage (from API 3.2 or later) or through `onBackgroundData` after `onStart`. This costs battery and BLE traffic for a field that is not in use, and depends on the forum-reported behavior above.
- **Download during the activity:** for a course needed right away, the foreground API 5 request made when the activity opens is more predictable than waiting up to 5 minutes or more for a background slot.

### Gaps
- I found no official Garmin statement on whether a data field's temporal event fires while the watch is idle on the watch face. The claim that it does rests on forum posts; test on a fēnix 8.
- I found no source on whether foreground `compute()` or web requests run before the timer starts on fēnix 8 firmware. My inference is yes, since `compute()` runs while the activity is open, but it is unverified.
- Behavior when several CIQ apps' background services compete (for example a watch face with its own background) was not researched. A thread titled "Background Services Conflict" exists but its content was not retrieved. — [forum 192213](https://forums.garmin.com/developer/connect-iq/f/discussion/192213/background-services-conflict)

---

## Q4. Background and data field memory limits (device-specific), response size vs memory, and error codes -402 / -403 / -102

### Takeaway
- **Memory per process:** fēnix 8 (AMOLED 43/47/51 mm and Solar) allows 64 KB for the background process and 128 KB for a data field. fēnix 7, epix 2 and FR965 also allow 64 KB for background but 256 KB for data fields. fēnix 6 Pro allowed only 32 KB for background.
- **Response size vs memory:** the response is parsed in the receiving process's memory. JSON grows by a large factor when it becomes a Dictionary, which causes -403. `HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN` avoids the parse.
- **No documented maximum:** Garmin publishes no maximum response size. Forum reports put the -402 threshold around 32–44 KB of JSON, varying by device.

### Cited Findings
- SDK device file for **fēnix 8 47mm / 51mm** (`fenix847mm`: 454×454 AMOLED, family `round-454x454`), `appTypes` memoryLimit values:

  | App type | Bytes | KB |
  |---|---|---|
  | background | 65536 | 64 |
  | datafield | 131072 | 128 |
  | glance | 65536 | 64 |
  | watchFace | 131072 | 128 |
  | watchApp | 786432 | 768 |
  | audioContentProvider | 524288 | 512 |

  The openhab copy lists `connectIQVersion` "5.1.1" (firmware 1331); a separate copy lists "6.0.0". — [openhab-garmin fenix847mm/compiler.json](https://github.com/openhab/openhab-garmin/blob/HEAD/.github/ConnectIQ/Devices/fenix847mm/compiler.json); [granbike-face-builder devices/fenix847mm/compiler.json](https://github.com/mgallesio/granbike-face-builder/blob/HEAD/backend/devices/fenix847mm/compiler.json)
- Background and data field memoryLimit by device, from `compiler.json` copies in [mgallesio/granbike-face-builder backend/devices](https://github.com/mgallesio/granbike-face-builder/tree/HEAD/backend/devices) (copy dates unknown):

  | Device | Display | background | datafield | connectIQVersion |
  |---|---|---|---|---|
  | fēnix 8 43mm | AMOLED 416×416 | 64 KB | 128 KB | 6.0.0 |
  | fēnix 8 47/51mm | AMOLED 454×454 | 64 KB | 128 KB | 6.0.0 |
  | fēnix 8 Solar 47mm | MIP 260×260 | 64 KB | 128 KB | 6.0.0 |
  | fēnix 8 Solar 51mm | MIP | 64 KB | 128 KB | 6.0.0 |
  | Forerunner 970 | | 64 KB | 128 KB | 6.0.0 |
  | fēnix 7 | MIP 260×260 | 64 KB | 256 KB | 5.2.0 |
  | fēnix 7 Pro | | 64 KB | 256 KB | 5.2.0 |
  | epix (Gen 2) | | 64 KB | 256 KB | 5.2.0 |
  | epix Pro (Gen 2) 47mm | | 64 KB | 256 KB | 5.2.0 |
  | FR965 | AMOLED 454×454 | 64 KB | 256 KB | 5.2.0 |
  | FR955 | | 64 KB | 256 KB | 5.2.0 |
  | Venu 3 | | 64 KB | 256 KB | 5.2.0 |
  | fēnix 6 Pro | | 32 KB | 128 KB | 3.4.x |

  The same device files also list watchFace 128 KB for fēnix 6 Pro and watchApp 1280 KB for fēnix 6 Pro.
- Forum (snippet), "Device Memory Limits": "Modern watches including the Fenix 8 have much more memory for data fields - 128 KB or 256 KB", and the limits can be read from `compiler.json` / `simulator.json`. — [Device Memory Limits (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits)
- Official error codes, with the API level each was added:

  | Code | Name | API level | Description |
  |---|---|---|---|
  | -102 | `BLE_REQUEST_TOO_LARGE` | 1.0.0 | "Serialized input data for the request was too large" (the outgoing request) |
  | -402 | `NETWORK_RESPONSE_TOO_LARGE` | 1.0.0 | "Serialized response was too large" |
  | -403 | `NETWORK_RESPONSE_OUT_OF_MEMORY` | 3.0.0 | "Ran out of memory processing network response" |
  | -104 | `BLE_CONNECTION_UNAVAILABLE` | | |
  | -2 | `BLE_HOST_TIMEOUT` | | |
  | -300 | `NETWORK_REQUEST_TIMED_OUT` | | |
  | -1000 | `STORAGE_FULL` | | |
  | -1001 | `SECURE_CONNECTION_REQUIRED` | 2.3.0 | |
  | -1002 | `UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE` | 2.4.1 | |

  — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Official `HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN = 5` (API 3.0.0): "Content type string must be \"text/plain\"". JSON = 0 requires "application/json". If `:responseType` is not given, the server's Content-Type header decides the format, and unknown types cause an error. — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Forum (snippet), "Understanding -402 Response Limit": -402 is undocumented and differs between simulator and device. Some users hit -402 at about 32 KB of JSON; others handled up to about 44 KB; it varies by watch model. — [Understanding -402 Response Limit for makeWebRequest? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest)
- Forum (snippets) on -403:
  - With JSON, "you can't really use the number of bytes in the response, as it will be converted into a ciq dictionary... If you're seeing a -403, it ran out of memory doing this conversion."
  - A 5 KB JSON response raised memory use by about 20 KB once it became a dictionary.
  - In a background context, JSON worked at about 400 bytes and failed at about 600 bytes. This is old and was on a device with a very small background allowance.
  - "If you change the request to expect 'text/plain'... it will succeed", leaving unparsed text to handle manually.
  — [makeWebRequest error -403 despite enough free memory](https://forums.garmin.com/developer/connect-iq/f/discussion/289418/makewebrequest-error--403-despite-enough-free-memory); [Memory usage in makewebrequest](https://forums.garmin.com/developer/connect-iq/f/discussion/163995/memory-usage-in-makewebrequest); [-403 Error in makeWebRequest callback / BG / WF](https://forums.garmin.com/developer/connect-iq/f/discussion/208544/-403-error-in-makewebrequest-callback-bg-wf); [makeWebRequest returns '-403' when low free memory (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/makewebrequest-returns--403-when-low-free-memory). All snippets; which thread holds which quote was not verifiable.
- **Outdated:** an old forum snippet says the background max in the SDK's Devices.xml "doesn't exceed 32k for code and data". This is superseded for modern devices (64 KB per the `compiler.json` files above) but still true for older ones such as fēnix 6 Pro. — [same -403 thread cluster (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/6574/communications-makewebrequest-returns-response-code--403)

### Inferences
- The background limit (64 KB on fēnix 8) covers background code, globals, the response buffer and the parsed object. A 30 KB binary course becomes about 40 KB as Base64, and that response alone would likely fail with -403 or -402 in the background. Chunks of about 4–6 KB of Base64 text (3–4.5 KB binary) are a safe range for the background path. They also have to stay under the ~8 KB exit limit (Q5).
- In the foreground data field (128 KB on fēnix 8), the budget is shared with the field's own code, the drawing buffers and the decoded profile. Chunks of about 8–16 KB of `text/plain` are a reasonable starting point. A single 40 KB response is risky given the 32–44 KB -402 reports.
- Prefer `text/plain` with Base64, or plain decimal/CSV text, over JSON arrays. JSON arrays of numbers are parsed into Arrays of Number objects with large per-element overhead (about 4× per the 5 KB → 20 KB report).
- A notable difference: the fēnix 8 has half the data field memory of the fēnix 7 / epix 2 / FR965 (128 KB vs 256 KB).

### Gaps
- Garmin documents no maximum response size, and no measured -402 threshold exists for fēnix 8 specifically.
- The per-object memory overhead of Monkey C Strings and Arrays on API 5 VMs was not researched.

---

## Q5. Background.exit(data) size limit, writing Application.Storage directly from the background, and known issues

### Takeaway
- **Exit limit:** `Background.exit()` payloads are limited to about 8 KB including serialization overhead; larger payloads throw `ExitDataSizeLimitException`.
- **Storage from background:** since Connect IQ 3.2.0 the background process can write `Application.Storage` directly. The fēnix 8 is 5.x or later, so it can. The foreground gets `onStorageChanged()` if it is running.
- **Value limit:** each Storage value is limited to 32 KB.
- **ByteArray:** not in the documented persistable types. Store Base64 Strings, or Arrays of Numbers, split into several keys.

### Cited Findings
- Official `Background.exit(backgroundData)` (API 2.3.0):
  - Allowed types: String, Number, Float, Boolean, Char, Long, Double, Array, Dictionary (and null).
  - It throws `ExitDataSizeLimitException` when "the data provided exceeds the data size limit (approximately 8 KB). If this exception is caught, the process will not exit and should attempt to call Background.exit() again with less data."
  - "Passing null will not override previous data values not yet consumed by the parent application's AppBase.onBackgroundData() method."
  — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)
- `Background.getBackgroundData()`: data "is reset to null once data has been delivered to the main process". — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md)
- Forum (snippet): the ~8 KB limit concerns what is passed to `Background.exit()`, not the download size. "The documentation doesn't mention overhead associated with the serialization format, but there is overhead, and it counts against the limit." — [Data too large for Background process (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/7550/data-too-large-for-background-process)
- Official `Storage.setValue()` (API 2.4.0) throws `ObjectStoreAccessException` "if called from a background process on device that does not have ConnectIQ 3.2.0 support. Data can always be passed to the foreground process from a background process with Background.exit()". The same note is on `deleteValue`/`clearValues`. It also says: "There is a limit on the size of the Object Store that can vary between devices... Also, values are limited to 32 KB in size", and it throws `StorageFullException` when the store is full. — [Application.Storage (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/Storage.md); official: [Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
- Storage value types per the official docs:
  - Allowed: String, Number, Float, Boolean, Char, Long, Double, BitmapResource (3.0.0 or later), AnimationResource (3.0.8 or later), ScanResult (3.2.0 or later), null, and Arrays or Dictionaries of these.
  - `Application.PropertyValueType` is defined as PropertyKeyType | Array | Dictionary | BitmapResource | Null.
  - ByteArray is not listed.
  — [Storage (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/Storage.md); [Application (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application.md)
- Official `AppBase.onStorageChanged()` (API 3.2.0): "Called when Application storage is changed by the other running instance, of the app i.e Background Process while the CIQ app is running or vice-versa... Use this function to reload storage data." — [AppBase (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md)
- Official: "Background processes cannot save Application Properties" (with the same 3.2.0 caveat). — [Application.Properties (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/Properties.md)
- Known issues (forum snippets):
  - fēnix 5-series could not write Storage from the background while fēnix 6 and FR245 could. This is old.
  - There is a reported conflict or race between makeWebRequest and `Storage.setValue` called from `onUpdate` on a watch face. One developer fixed crashes by writing only in the main-view context on older devices.
  - Separate bug reports of `Storage.setValue` system errors on some firmware exist.
  — [F5 can't save to Storage from Background (snippet)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/f5-can-t-save-to-storage-from-background-while-f6-and-others-can); [Conflict/race between makeWebRequest and Storage.setValue (snippet)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/conflict-race-between-makewebrequest-and-storage-setvalue-called-from-onupdate-on-a-watchface); [System Error calling Storage.setValue() latest FW (title only)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/system-error-calling-storage-setvalue-lastest-fw)
- Found in code search, not inspected: open-source data field apps that combine `getServiceDelegate`, `registerForTemporalEvent` and `Storage.setValue` include `oliyh/leadout` (leadout-datafield) and `Artificial-Pancreas/garminWatch` (iAPSGarminDataField). — [oliyh/leadout](https://github.com/oliyh/leadout/blob/HEAD/datafield/leadout-datafield/source/leadout-datafieldApp.mc); [Artificial-Pancreas/garminWatch](https://github.com/Artificial-Pancreas/garminWatch/blob/HEAD/iAPSGarminDataField/source/iAPSDataFieldApp.mc)

### Inferences
- For the background path on fēnix 8, have the background write each chunk to its own Storage key, for example `"crs_<id>_<n>"` holding a Base64 String of 32 KB or less and in practice much smaller for memory reasons. Then call `Background.exit()` with only a small status Dictionary such as `{id, n, total}`. This bypasses the 8 KB exit limit and survives the activity closing.
- The foreground reloads in `onBackgroundData` or `onStorageChanged`.
- Converting the Base64 back to bytes in the foreground (e.g. `StringUtil.convertEncodedString`) is an inference; I did not verify it or its data field availability here.
- To avoid races, only one side should write a given key. For example, the background writes the chunk keys and the foreground writes only a "consumed/assembled" key.

### Gaps
- There is no documented total Object Store size for fēnix 8; the docs only say it "can vary between devices".
- I could not confirm whether ByteArray values are accepted by Storage on API 5.x despite not being listed.
- No fēnix 8-specific reports of background Storage write problems were found.

---

## Q6. Does the watch need Garmin Connect Mobile running and connected? iOS vs Android; Wi-Fi and LTE

### Takeaway
makeWebRequest from a data field (foreground or background) is proxied by the phone's Garmin Connect app over BLE. Wi-Fi is effectively not used for these requests; it is used only in the sync context. On iOS the request fails with -104 unless Garmin Connect has been opened recently or is allowed to refresh in the background. Android requires HTTPS with a valid certificate.

### Cited Findings
- Official makeWebRequest note: "This method can be used when connected to WiFi or a mobile device over Bluetooth." — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Contradicted in practice:
  - Forum (snippet): "Generally, WiFi is not connected on watches, and doesn't even attempt to connect WiFi when a makeWebRequest is done. You need to use BLE to your phone." Wi-Fi is brought up only when a sync is started (`SyncDelegate` / `startSync`, CIQ 3.1 or later).
  - Breadcrumb data field source comment: "even though docs say that this could be sent over wifi it seems it never is, and requires the bluetooth connection... I tried several ways to force wifi, including calls to checkWifiConnection - which does connect wifi but the request still seems to go through the bluetooth bridge".
  — [Confirming WiFi Connectivity before makeWebRequest (snippet)](https://forums.garmin.com/developer/connect-iq/f/app-ideas/338561/confirming-wifi-connectivity-before-makewebrequest); [Communications.makeWebRequest thread (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/270271/communications-makewebrequest); [breadcrumb-garmin WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)
- Forum (snippet), iOS: developers get `-104 BLE_CONNECTION_UNAVAILABLE` "unless Garmin Connect is open on the iOS device or has been opened recently", because iOS stops Garmin Connect relaying in the background when unused. Suggested mitigations: enable Background App Refresh for Garmin Connect and turn Low Power Mode off. — [makeWebRequest on iOS needs Garmin Connect open on the phone (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/343216/makewebrequest-on-ios-needs-garmin-connect-open-on-the-phone)
- Forum (snippet): on iOS plain HTTP works; "on Android, HTTPS is required and the server needs to have a valid certificate". The official error `SECURE_CONNECTION_REQUIRED = -1001` (API 2.3.0) exists for this. — [How to do a HTTP (not HTTPS) web request? (snippet)](https://forums.garmin.com/developer/connect-iq/f/discussion/370945/how-to-do-a-http-not-https-web-request); [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Official error meanings relevant to phone-proxy failures: `BLE_CONNECTION_UNAVAILABLE -104` ("No BLE connection is available"), `BLE_HOST_TIMEOUT -2`, `BLE_SERVER_TIMEOUT -3`, `NETWORK_REQUEST_TIMED_OUT -300`, `REQUEST_CONNECTION_DROPPED -1004`. — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Bug report (snippet): the VenuSQ disconnects from the phone after multiple makeWebRequest calls, showing firmware-specific BLE fragility. — [VenuSQ Disconnects from Phone after multiple makeWebRequest calls (title/snippet)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/venusq-disconnects-from-phone-after-multiple-makewebrequest-calls)

### Inferences
- Host the course on HTTPS with a valid certificate, which works on both platforms.
- Tell iPhone users to open Garmin Connect shortly before starting the activity. With the foreground API 5 approach, the download happens right when the activity opens, which also suits this.
- The base fēnix 8 has no LTE. The fēnix 8 Pro (`fenix8pro47mm`) has LTE/inReach, but I found no evidence that CIQ makeWebRequest uses LTE.

### Gaps
- I found no official Garmin statement on whether CIQ web requests can use the watch's own Wi-Fi outside sync, or LTE on fēnix 8 Pro.
- I found no fēnix 8-specific data on iOS -104 frequency.

---

## Q7. Practical patterns for moving larger payloads in chunks across runs; real GitHub examples

### Takeaway
I found no public project that downloads a multi-chunk binary payload across several 5-minute background runs; that pattern would have to be built from the documented primitives. The closest real examples are:
- **Breadcrumb:** an API 5 data field for fēnix 8 that does foreground web and image requests through a queue, and loads routes (with an elevation overview) through a companion phone app.
- **Background-service data fields:** several use the standard temporal event → makeWebRequest → Background.exit/Storage pattern for small payloads.

### Cited Findings
- **Breadcrumb data field** ([pauljohnston2025/breadcrumb-garmin](https://github.com/pauljohnston2025/breadcrumb-garmin)):
  - It is a datafield with `minApiLevel` 5.0.0 that supports fēnix 8.
  - It keeps a request queue that drops duplicate pending requests by hash and tracks outstanding requests, success and error counts, and the last result.
  - It has no Timer, so the next request is triggered from `compute()`.
  - Its README describes "Elevation Overview: Shows an elevation profile of the route" and "Routing (companion app required): Users can import routes from Google Maps or GPX files using the companion app."
  - The README also notes "those devices (<3.2.0 api) do not support phone app messages for datafields", so on API 3.2 or later, data fields can receive phone-app messages.
  - Sister projects (`breadcrumb-garmin-light-weight`, `breadcrumb-garmin-ultra-light`, `breadcrumb-garmin-app`) exist because data field memory is tight: "the app has larger memory limits than a datafield".
  — [breadcrumb-garmin readme.md](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/readme.md); [WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc); companion app: [breadcrumb-mobile](https://github.com/pauljohnston2025/breadcrumb-mobile)
- Other data fields using `Background.registerForTemporalEvent` or background delegates, found by GitHub code search (not inspected in depth):
  - [bkfeinberg/distanceWandered](https://github.com/bkfeinberg/distanceWandered)
  - [oliyh/leadout](https://github.com/oliyh/leadout)
  - [Artificial-Pancreas/garminWatch (iAPSGarminDataField)](https://github.com/Artificial-Pancreas/garminWatch)
  - JoopVerdoorn "Datarun premium" variants (e.g. [DR5c0](https://github.com/JoopVerdoorn/DR5c0))
  — GitHub code search results
- Chained multi-request sample (widget): [aronsommer/WebRequestMultiple-Widget](https://github.com/aronsommer/WebRequestMultiple-Widget)
- Official: the `:context` option of makeWebRequest passes a user object to a 3-argument callback. This is useful for tagging which chunk index a response belongs to. — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Official: the Communications module also defines `HTTP_RESPONSE_CONTENT_TYPE_GPX = 2` / `FIT = 3` (API 2.2.0), where "the system will attempt to download and parse a FIT or GPX file and store the contained data in the device". — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)

### Inferences
Suggested chunk protocol, synthesized from the documented limits (not taken from any existing project):
1. `GET /course/manifest` returns `text/plain` like `id=abc123;n=5;crc=...`.
2. `GET /course/abc123/<i>` returns roughly 6 KB of Base64 `text/plain`.
3. Tag each request with `:context => i`.
4. Store each chunk under its own Storage key.
5. Record `nextIndex` in Storage so a killed background run or a closed activity resumes where it stopped.
6. Validate with a CRC or length before swapping in the new course.

Rough timing:
- **Foreground (API 5):** chunks can be chained back-to-back. A 30 KB course (about 40 KB Base64, 4–7 chunks) should take seconds to tens of seconds over BLE. This is an estimate, not measured.
- **Background:** with 1–2 chunks per 30-second run and 5-minute spacing, 100 km could take about 10–35 minutes.

On the GPX/FIT response types: they suggest a system-course import path, but these appear aimed at device apps with PersistedContent. I did not verify availability to data fields, and a field could not read the result as its own data anyway.

### Gaps
- I found no open-source data field that assembles a multi-part download across background runs.
- There is no measured end-to-end throughput for fēnix 8 over Garmin Connect Mobile.

---

## Q8. Can the data field show progress ("course downloading 2/4") and use the data once complete, in the same activity?

### Takeaway
Yes. With foreground API 5 requests, the data field's own callback updates its state and the next `onUpdate()` draws the progress and then the profile. With a background service, `Background.exit()` data reaches the running field immediately through `onBackgroundData()`, and Storage writes trigger `onStorageChanged()`, so progress and the finished course can also appear mid-activity. The catch is that background chunks arrive at most one run per 5 minutes.

### Cited Findings
- Official: `Background.exit()` data "will either be passed immediately to the active application if it is running, or will be saved and passed to the application the next time it runs". `AppBase.onBackgroundData()`: "If the main application is active when this occurs, the data will be passed directly to the application's onBackgroundData() method." — [Background (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Background.md); [AppBase (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md)
- Official: `onStorageChanged()` (API 3.2.0) fires in the foreground when the background process changes storage "while the CIQ app is running". — [AppBase (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Application/AppBase.md)
- Official: the makeWebRequest `:fileDownloadProgressCallback` (CIQ 3.2.0) is "only supported for media file download progress". There is no byte-level progress for normal requests, so progress has to be counted per chunk. — [Communications (via mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/HEAD/markdown/doc/Toybox/Communications.md)
- Real example: Breadcrumb's data field tracks `_successCount`, `_errorCount` and `_lastResult` for its web requests, and its UI can show request state. — [breadcrumb-garmin WebRequest.mc](https://github.com/pauljohnston2025/breadcrumb-garmin/blob/HEAD/source/WebRequest.mc)

### Inferences
- **Progress display:** a status line such as "Course 2/4" or "Error -104", driven by per-chunk callbacks, is straightforward.
- **Error display:** show the last error code so users can tell -104 (phone not connected) from -402/-403 (chunk too big).
- **Assembly:** build the elevation profile only after all chunks pass validation, and keep the previous course until then.
- **Memory spike:** decoding Base64 chunks into a compact profile inside a 128 KB data field needs care. Decode chunk by chunk into the final structure rather than joining one 40 KB string first.

### Gaps
- I did not verify whether `onBackgroundData` / `onStorageChanged` are delivered while the activity is in the pre-start (timer not started) state on fēnix 8 firmware.
- Other gaps not covered above:
  - I did not research fēnix 8 limits on how many CIQ data fields an activity can use. Threads exist: [IQ field limit for activities – fēnix 8](https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-8-series/382022/iq-field-limit-for-activites); [Garmin support: Connect IQ App Limits](https://support.garmin.com/en-US/?faq=tFmJJnTfs83yuPc8kttAh7).
  - The "16 MB additional storage" in CIQ 8 mentioned in one search snippet (Notebookcheck) was not verified, and I did not check whether it applies to data fields. — [Notebookcheck CIQ 8 (snippet)](https://www.notebookcheck.com/Garmin-Connect-IQ-8-startet-mit-Verbesserungen-fuer-Zifferblaetter-Benachrichtigungen-und-Apps-in-den-Beta-Test.944481.0.html)
