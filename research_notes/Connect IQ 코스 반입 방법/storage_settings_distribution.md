# Connect IQ data field: storage limits, app settings and distribution options for loading course data without rebuilding

Scope: personal Connect IQ (CIQ) data field for fēnix 8 AMOLED that draws a GPX elevation profile. Course data is about 6–30 KB of binary per course, possibly several courses. The question is where that data can live on the watch, how the user picks settings or courses without a PC, and how to install or update without USB sideloading.

Source notes:
- developer.garmin.com, forums.garmin.com, apps.garmin.com and support.garmin.com are egress-blocked from this environment. I verified the official SDK documentation text through a public GitHub mirror, `tkafka/garmin-sdk-docs-for-ai`. It is a markdown conversion of the Garmin SDK docs; the pages say "Generated Dec 11, 2024", so they reflect the SDK 7.x era. The mirror also contains a `repomix-output.md` bundle with the Programmer's Guide (`CoreTopics.md`, `ConnectIQBasics.md`, `FAQ.md`). Mirror: https://github.com/tkafka/garmin-sdk-docs-for-ai
- For each mirrored page I also give the official developer.garmin.com URL. Those URLs are cited for reference only; the wording was checked in the mirror.
- Forum material comes only from search-engine snippets, so it is treated as hearsay unless noted otherwise.
- I read device memory limits from real `compiler.json` device files that people committed to public GitHub repos. These files ship in the SDK's `Devices` folder.

---

## 1. Application.Storage and Application.Properties: size limits, value types, fēnix 8 behavior

### Takeaway
The official limits contradict each other:
- API reference: each Storage value is limited to 32 KB, and the total size is device-dependent.
- Programmer's Guide: keys and values are limited to 8 KB each, with 128 KB total.
- Garmin's own blog: about 100 KB total, with each item under 8 KB.

Storage does not officially accept `ByteArray` values; no documented API level adds it. Binary course data therefore has to be stored another way:
- as an `Array` of Numbers, or
- as a String (for example Base64 via `StringUtil.convertEncodedString`, API 3.0.0+),
- split into several keys, each ≤8 KB to stay safe.

A total of 128 KB (or about 100 KB) is enough for several 6–30 KB courses, if the data is chunked.

### Cited Findings
- Storage module: "Since API Level 2.4.0". `setValue()` value types listed: String, Number, Float, Boolean, Char, Long, Double, BitmapResource (since 3.0.0), AnimationResource (since 3.0.8), ScanResult (since 3.2.0), `null`, plus Array/Dictionary containing those (excluding Bitmap and Animation resources). **ByteArray is not in the list.** — [Storage API doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Storage.md); official: [developer.garmin.com Storage](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html)
- The same page says: "There is a limit on the size of the Object Store that can vary between devices. If you reach this limit, the value will not be saved and an exception will be thrown. Also, values are limited to 32 KB in size." `setValue` throws `Lang.StorageFullException` "if there is not enough remaining space in the Object Store for the given key and value". — [Storage API doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Storage.md)
- The Programmer's Guide (Core Topics, "Persisting Data") conflicts with that: "Information is automatically saved on disk when `Storage.setValue()` is called. Keys and values are limited to 8 KB each, and a total of 128 KB of storage is available." Its list of storable types is Number, Float, Long, Double, Char, String, Boolean, Array, Dictionary; there is no ByteArray. — [Core Topics mirror (repomix-output.md, CoreTopics section)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [Persisting Data](https://developer.garmin.com/connect-iq/core-topics/persisting-data/)
- A Garmin developer blog (older, from the SDK 2.4 era) says: "save up to approximately 100 kB of data with the new Storage API… each item still needs to be lower than 8 kB, so you will need to split long arrays into multiple items". It also says to catch `StorageFullException` and that older devices may have less. — [Garmin Blog: improve your app performance](https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/) (snippet only; page blocked)
- The `Application.PropertyValueType` typedef is: PropertyKeyType (Number/Float/Long/Double/String/Boolean/Char) or `Array<PropertyValueType>` or `Dictionary<…>` or `WatchUi.BitmapResource` or Null. It does not include ByteArray. — [Application module doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application.md)
- Storage from background processes has been allowed since API 3.2.0. On older devices it throws `ObjectStoreAccessException`. When the other process writes, `AppBase.onStorageChanged()` fires. — [Storage API doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Storage.md); [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Legacy object store (`AppBase.getProperty/setProperty`, API 1.0.0): it "is a Dictionary that lives in memory until your app terminates… Because the object store costs against your runtime memory, do not use these methods unless you are running on System 1 devices." — [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- `Application.Properties` (API 2.4.0): values must be predeclared in `<properties>` resources. Reading or writing an undeclared key throws `InvalidKeyException`. Background processes cannot save Properties. Property types are number, long, float, double, boolean, string and array; arrays "cannot be initialized in properties, but defaults can be programmed in app settings". Properties are saved to disk on `AppBase.onStop()`. The docs state no explicit size limit. — [Properties API doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/Properties.md); [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [Properties and App Settings](https://developer.garmin.com/connect-iq/core-topics/properties-and-app-settings/)
- Binary-to-string helpers:
  - `StringUtil.convertEncodedString(String or ByteArray, {:fromRepresentation, :toRepresentation, :encoding})` is API 3.0.0.
  - `REPRESENTATION_STRING_BASE64` is API 3.0.0.
  - `encodeBase64` is API 1.3.0.
  These can turn a Base64 String into a ByteArray at runtime. — [StringUtil doc (mirror, in repomix-output.md)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [StringUtil](https://developer.garmin.com/connect-iq/api-docs/Toybox/StringUtil.html)
- Forum hearsay (snippet): an UnexpectedTypeException message reads "Expected Object/Array/Dictionary/ByteArray, given null", and another reads "Given value cannot be serialized" when storing an unsupported type. — [How to put values in arrays in the watch storage? (forum)](https://forums.garmin.com/developer/connect-iq/f/discussion/266739/how-to-put-values-in-arrays-in-the-watch-storage)
- Forum hearsay (snippet): "System Error calling Storage.setValue()" after recent firmware on Venu 3, FR965 and FR265. That is the same device generation as fēnix 8, so a try/catch around `setValue` is warranted. — [System Error calling Storage.setValue() lastest FW (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/system-error-calling-storage-setvalue-lastest-fw)

### Inferences
- The safe design is to store each course as several Storage keys, for example `"c1_0"`, `"c1_1"`, …, each ≤8 KB serialized. This satisfies both the 8 KB (guide) and 32 KB (API ref) readings. A 30 KB course then needs about 4–5 chunks, and three such courses (about 90 KB) fit under both the 100 KB and 128 KB totals. Several 30 KB courses at once would approach the ceiling.
- Storage cost depends on the data type:
  - Base64 strings add 33% overhead.
  - A Monkey C `Array` of Numbers likely costs several bytes per element in heap and serialized form. I did not find a documented per-element cost.
  - A compact encoding, such as packed 16-bit samples inside a Base64 String or in Numbers that each carry 4 bytes, is advisable.
- ByteArray: no official document says Storage accepts it, even in API 5.x. Assume it is **not** supported and store Strings or Number arrays, unless the fēnix 8 simulator or device test shows otherwise.

### Gaps
- I could not confirm the actual total Storage quota on fēnix 8 (API 5.x/6.x), or whether it is larger than 128 KB on new devices. Garmin says it "can vary between devices" and the device `compiler.json` has no storage field.
- I found no official statement or release note adding ByteArray to Storage value types in SDK 7.x or 8.x. The mirrored docs date from Dec 2024, so a later SDK 8.x change cannot be ruled out. Verify in the current API doc or the simulator.
- The 32 KB vs 8 KB per-value contradiction is unresolved. Whether the limit applies to raw data or serialized size is also unknown.

---

## 2. App settings (Properties) edited in Garmin Connect Mobile or the Connect IQ app: string length; carrying course data in a setting

### Takeaway
The only official length control is an optional `maxLength` attribute on `alphaNumeric` string settings. No platform maximum is documented. According to forum veterans:
- the practical lowest limit across GCM, Garmin Express and the Connect IQ app is about 256 characters per string setting;
- total settings size is about 8 KB;
- some characters (`& \ < >`) are mangled.

Pasting a 6–30 KB course as Base64 (8–40 KB of text) into one setting is therefore not viable. Even split across many settings it would hit the roughly 8 KB total ceiling. Settings are good for selecting a course (an index or a short ID), not for carrying it.

### Cited Findings
- Settings "allow the user to modify app properties using their mobile device. The app settings can be modified in the Connect IQ Store app, the Garmin Connect app, or Garmin Express." — [Core Topics mirror, "Properties and Settings"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [Properties and App Settings](https://developer.garmin.com/connect-iq/core-topics/properties-and-app-settings/)
- `settingConfig` types: `list`, `boolean`, `numeric`, `alphaNumeric`, `phone`, `email`, `url`, `date`, `password`. `maxLength` is "The maximum allowed value length… Only valid for settings whose associated property's type is `string`". On a `<setting>` element (array settings), `maxLength` means "The maximum number of elements allowed in an array setting". — [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Array settings let users build "a variable list (up to a maximum size) of objects", read at runtime as an Array of Dictionaries. This can hold a small list of course names or IDs. — [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- When settings change while the app runs, `AppBase.onSettingsChanged()` is called. — [Core Topics mirror](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum hearsay (snippet): "The lowest maximum is something like 256 characters, and that's based on what's used to set it - GCM, GE, the Connect IQ app, etc. There are some apps that use long strings to define a 'settings string'… the max size of all settings, which is about 8k." Also: "The max length many developers use for their settings is 255". — [Max length of alphaNumeric setting? (forum 217336)](https://forums.garmin.com/developer/connect-iq/f/discussion/217336/max-length-of-alphanumeric-setting)
- Forum bug report (snippet): with an `alphaNumeric` setting, `&` and everything after it is removed on save, `\` is removed, and `<` or `>` clears the whole string. — [alphaNumeric type app setting does not accept <, >, & and \ (GCM iOS forum)](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-mobile-ios/258279/alphanumeric-type-app-setting-does-not-accept-and-characters)
- Precedent for settings used as a data channel: the DIY Data Field (public beta) asks users to "sequentially copy/paste definition lines into Garmin Express/Mobile settings". This is data split across several string settings, consistent with a per-setting length limit. — [DIY Data Field (public beta) store listing (snippet)](https://apps.garmin.com/en-US/apps/470f546f-200f-42ce-bb9c-0f7dc27ec3a5)
- Older forum answer (snippet) on Monkey C strings in general, not settings: there is no limit beyond available app memory. — [Max length of a string (forum 3869)](https://forums.garmin.com/developer/connect-iq/f/discussion/3869/max-length-of-a-string)

### Inferences
- If "256 characters per field and about 8 KB total" holds, a 6 KB binary course becomes about 8 KB of Base64. That already exhausts the whole settings budget and needs more than 30 fields. A 30 KB course is impossible. Settings should carry a course selector (list index or short ID/URL token), and the bytes should arrive another way, for example `Communications.makeWebRequest` from a companion server. That route is outside this note's scope.
- The standard Base64 alphabet (`A–Z a–z 0–9 + / =`) avoids the characters known to break (`& \ < >`). A URL-safe alphabet would also avoid them.

### Gaps
- There is no official Garmin figure for maximum string-setting length or total settings payload per app. The 256-character and 8 KB figures are community statements. The forum page itself could not be opened to read full context or dates.
- I don't know whether the late-2025 Connect IQ Store app redesign changed these limits.

---

## 3. Sideloaded .prg apps: can settings be edited from the phone? The .SET workaround

### Takeaway
No. The phone apps (GCM, the Connect IQ app, and formerly Garmin Express) only show settings for store-installed apps. The documented community workaround:
1. Generate or edit settings in the simulator's App Settings Editor.
2. Take the resulting `.SET` file from the simulator's temp directory.
3. Rename it to match the sideloaded `.PRG` name.
4. Copy it to `GARMIN/APPS/SETTINGS/` on the watch over USB.

That still requires a PC and USB, so it does not remove the PC step.

### Cited Findings
- Official sideload procedure: build with "Monkey C: Build for Device" and "Copy the generated `PRG` files to your device's `GARMIN/APPS` directory". — [Connect IQ Basics mirror, "Side Loading an App"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Official testing tool: "An app settings editor tool is available within the Connect IQ simulator. Go to *File > Edit Persistent Storage > Edit Application.Properties data*… The app settings editor requires you to be authenticated in the SDK Manager as well as an internet connection." — [Core Topics mirror, "Testing App Settings"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum (snippet, marked "[SOLVED]"): "a .SET file with a matching name to your sideload will appear in /GARMIN/Apps/SETTINGS once your PRG is accepted, structured to match the settings defined in your app with all values at their default". The workaround is to copy the `.SET` produced by the simulator, rename it to the PRG name, and copy it to the watch. — [[SOLVED] Settings (Connect IQ app) for sideloaded app – is this possible? (forum 429848)](https://forums.garmin.com/developer/connect-iq/f/discussion/429848/solved-settings-connect-iq-app-for-sideloaded-app---is-this-possible)
- Forum (snippet): "App Settings requires that the app is in the store. It's not possible to set app settings of a side loaded app from GCM or GE." Windows simulator settings path: `C:\Users\[username]\AppData\Local\Temp\GARMIN\APPS\SETTINGS`. — [Settings file for custom not published watchface in .prg format (forum 374864)](https://forums.garmin.com/developer/connect-iq/f/discussion/374864/settings-file-for-custom-not-published-garmin-watchface-app-in-prg-format); [Modifying settings on side loaded app (forum 2121)](https://forums.garmin.com/developer/connect-iq/f/discussion/2121/modifying-settings-on-side-loaded-app); [change settings with side loaded app (forum 269335)](https://forums.garmin.com/developer/connect-iq/f/discussion/269335/change-settings-with-side-loaded-app)
- Forum thread title (content not retrieved): "sideload PRG file; no longer working". This suggests sideload regressions have happened on some firmware. — [forum 367718](https://forums.garmin.com/developer/connect-iq/f/discussion/367718/sideload-prg-file-no-longer-working)

### Inferences
- A sideloaded field can still have settings without a PC if it implements on-device settings through `getSettingsView` (section 5). It can also persist choices in Storage itself.
- Course data could in principle go into the `.SET` file, since it holds property values. But this is USB copying again, and settings-size limits may apply. Not recommended.

### Gaps
- I found no method other than the `.SET` file copy for editing a sideloaded app's settings from a phone.
- The `.SET` binary format is not officially documented.
- I couldn't confirm the macOS or Linux simulator temp path for `.SET` files from a primary source.

---

## 4. Connect IQ Store "beta apps", unlisted or private distribution (2025–2026 status)

### Takeaway
Beta apps still exist officially:
- A beta app uses a separate app UUID and is uploaded with the "Beta App" checkbox.
- It stays in preview or pending state indefinitely and is never reviewed or approved.
- It is visible only to the uploading developer's account.
- It can be updated as often as wanted.
- The docs say beta installs support editing settings in Garmin Connect and Garmin Express.
- Nothing restricts beta apps by app type, so a data field can be a beta app.

Since about Nov 2025, Garmin shut down the web store's install and purchase functions and made the Connect IQ Store mobile app the only install path. Developers now report that installing beta apps is hard: there is no "Install" button, and dashboard links don't open in the phone app. They also report that phone settings for pending or beta apps may not appear. Known workarounds:
- use the download button in the developer dashboard, then sync; or
- email yourself the `apps.garmin.com/apps/<id>` link and open it on the phone.

I found no documented "unlisted" or "private link" mode for normal (non-beta) public apps.

### Cited Findings
- Official "Beta Apps" section, quoted in full:
  > Connect IQ beta apps allows developers to test app settings and Garmin Connect integration in production without releasing the app. Uploading a beta app will let you stage your app in production. To use this feature, you will need to create an alternate app id in your manifest… Beta apps will show up in your uploaded apps, and you can download them to your Garmin device. Once downloaded you can edit app settings in Garmin Connect and Garmin Express and test your developer fields in Garmin Connect. After you upload the beta app, you can update the beta version as many times as you want. When you are ready to release… upload it without checking the "Beta App" checkbox… the app will have a separate store identifier from your final app, and URLs to the beta will not be visible outside of your account.
  
  — [Core Topics mirror, "Beta Apps"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [developer.garmin.com Beta Apps](https://developer.garmin.com/connect-iq/core-topics/beta-apps/)
- The ERA (crash reporting) tool colors beta apps gold, and crashes are viewable. That confirms beta apps are a first-class store state. — [Connect IQ Basics mirror, "Viewing App Settings"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum (snippet): beta apps stay "in 'preview mode' forever and never get approved". The page shows "only visible to your account", and the developer can download immediately. — [Beta testing uploaded app (forum 3643)](https://forums.garmin.com/developer/connect-iq/f/discussion/3643/beta-testing-uploaded-app/55912)
- Garmin announcement, Nov 20, 2025, "Changes to the Connect IQ Store":
  - "the Connect IQ Store mobile app will be the sole source of purchasing, installing or managing apps".
  - apps.garmin.com links still work but redirect users to the mobile app.
  - Developers should bookmark **apps-developer.garmin.com** for uploads.
  
  — [Changes to the Connect IQ Store (Garmin forum announcement)](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/changes-to-the-connect-iq-store); secondary: [the5krunner, 2025-11-22](https://the5krunner.com/2025/11/22/garmin-shuts-down-connect-iq-web-store-mobile-app-mandatory/)
- Developer reports (snippets, 2025–2026):
  - Beta apps now live at apps-developer.garmin.com, but those links "do not open the app in the IQ app as the IQ app manifest only includes the domains apps.garmin.com, apps-test.garmin.com, and apps.garmin.cn". Emailing yourself the `apps.garmin.com/apps/<same-uuid>` link works.
  - For a beta app "it'll stay in pending state, but that's fine as long as you are logged in to the Connect IQ app with the same user you used to upload the app".
  
  — [Installing beta apps is almost impossible now (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/installing-beta-apps-is-almost-impossible-now); [How does one install a beta app? (forum 427577)](https://forums.garmin.com/developer/connect-iq/f/connect-iq-web-store/427577/how-does-one-install-a-beta-app); [Developer dashboard link (forum 427584)](https://forums.garmin.com/developer/connect-iq/f/connect-iq-web-store/427584/developer-dashboard-link); [How can I install my own app from the store? (forum 431618)](https://forums.garmin.com/developer/connect-iq/f/discussion/431618/how-can-i-install-my-own-app-from-the-store)
- Forum (snippet): "Since a recent update to the Connect IQ Web Store, the 'Install' button for Beta apps… has disappeared. Previously… would trigger Garmin Express". The workaround "is to upload to your developer dashboard, then use the download button there to select your device, and it installs on next sync via the Connect IQ mobile app". — [Missing "Install" button for Beta apps (forum 431240)](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/431240/missing-install-button-for-beta-apps-in-connect-iq-web-store); [Installing beta versions? (forum 428418)](https://forums.garmin.com/developer/connect-iq/f/discussion/428418/installing-beta-versions)
- **Conflict:** a developer bug report (snippet) says "Pending/Beta applications that are not officially on the store cannot be referenced or found by GCM… Therefore, changing settings would not be available." This contradicts the official beta-app doc's claim that settings are editable. — [No settings for Pending application in Connect Mobile app (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/no-settings-for-pending-application-in-connect-mobile-app); vs. [Beta Apps doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum (snippet): "if you want to use the Connect IQ phone app to edit app settings, you have to upload the app to the store. If you're only testing or using an app just for yourself, you can mark it as a beta." — [How can I change the settings for a Connect IQ Data Field using the Connect Mobile app? (Epix 2 forum 300865)](https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/epix-2/300865/how-can-i-change-the-settings-for-a-connect-iq-data-field-using-the-connect-mobile-app)
- Real public data fields exist as "(public beta)" products, for example DIY Data Field. These are normal, publicly listed apps with "beta" in the name, not the private Beta App mechanism. — [DIY Data Field (public beta)](https://apps.garmin.com/en-US/apps/470f546f-200f-42ce-bb9c-0f7dc27ec3a5)
- The ERA tool lists "App is hidden" (strikethrough) as an app status. This implies the store lets a developer hide an app, but it does not show the hidden app is still installable by link. — [Connect IQ Basics mirror, ERA "Manage Apps"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum thread title only (content not retrieved): "15MB upload limit for app IQ file?". This hints at a store upload size cap of about 15 MB for `.iq` files. — [forum 212864](https://forums.garmin.com/developer/connect-iq/f/discussion/212864/15mb-upload-limit-for-app-iq-file)

### Inferences
- For a personal-use data field, a beta app is the closest fit: no review, not public, updates without USB. The costs are:
  - installation is now clunky (dashboard download plus sync, or the emailed-link trick);
  - phone settings may or may not appear for beta or pending apps, with conflicting reports.
  
  The design should therefore not depend on phone settings. Pair beta distribution with on-device settings (section 5) and Storage.
- A normal public listing gets settings in GCM or the Connect IQ app reliably, but requires review and public visibility. I found no official unlisted mode.
- Once a beta is installed through the store, later beta uploads should propagate through the phone app's update mechanism. This is unverified; see Gaps.

### Gaps
- There is no primary-source 2026 confirmation of the current beta install flow in the new developer dashboard.
- I don't know whether settings editing for beta apps works in the redesigned Connect IQ Store app.
- I don't know whether beta updates auto-push to the watch.
- I found nothing about a review requirement for beta apps beyond "never gets approved". Beta apps appear to skip review, but Garmin says nothing explicit.
- Hidden or unlisted normal apps: I don't know whether they remain installable by direct link.
- I found no limit on the number of beta apps per developer.

---

## 5. On-device settings for data fields (getSettingsView / Menu2): devices, API level, how the user reaches it

### Takeaway
Since API 3.2.0, a data field (or watch face) can override `AppBase.getSettingsView()` and return a View and Delegate pair, which can be a `Menu2`. The system opens it from the activity menu. The official supported-device list (docs generated Dec 2024) includes:
- watches: fēnix 8 43mm, fēnix 8 47/51mm (AMOLED), fēnix 8 Solar, fēnix 7 family, epix (Gen 2) and epix Pro, Forerunner 965/955/265, Enduro 3;
- Edge bike computers: 530/830/1030/1040/1050/540/840/Explore 2.

Separately, data fields on touch devices can receive `onTap` inside the field, and the fēnix 8 AMOLED has a touchscreen. This could cycle stored courses during an activity without any menu.

### Cited Findings
- "*Since API level 3.2.0* … Watch faces and data fields are not allowed to accept input or push views that would allow on device configuration. If you want to provide an on-device settings user interface for your watch face or data field, you can implement `AppBase.getSettingsView()`… where you return a `WatchUi.View` and `WatchUi.InputDelegate` pair… Watch face configuration is available to the user in the system Watch Face menu. **Data field configuration is available from the activity menu.**" — [Core Topics mirror, "On Device Watch Face and Data Field Settings"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [Properties and App Settings](https://developer.garmin.com/connect-iq/core-topics/properties-and-app-settings/)
- `getSettingsView()`: "This function is only applicable to watch faces and data fields." Since API Level 3.2.0. It returns a View plus an optional BehaviorDelegate, ConfirmationDelegate, InputDelegate, MenuInputDelegate, Picker delegates or WatchFaceDelegate.
  - Supported watches in the list include fēnix 8 43mm, fēnix 8 47mm/51mm, fēnix 8 Solar 47mm/51mm, fēnix 7/7S/7X and Pro, epix (Gen 2), epix Pro 42/47/51, Forerunner 965/955/265/255/165, Enduro/Enduro 3, MARQ, Venu 2/3, vívoactive 4/5 and Instinct 2.
  - Supported Edge devices in the list: 530, 830, 1030/1030 Plus, 1040, 1050, 540, 840 and Explore 2.
  
  — [AppBase API doc (mirror)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/markdown/doc/Toybox/Application/AppBase.md); official: [AppBase](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html)
- Data fields on touch-screen devices: "an input delegate can be used to accept input. Only the `InputDelegate.onTap()` behavior is supported and will be triggered when the user touches a point inside the data field". The delegate is returned as the second element from `getInitialView()`. — [Core Topics mirror, "Data Field"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- User navigation, forum hearsay (snippet): for data fields, users hold UP (MENU) during the activity and select "Connect IQ Fields > [field name]" to open the settings view. In the simulator this is triggered with Settings > Trigger App Settings. — [SDK 3.2: Settings view for datafields shown wrong on simulator (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/sdk-3-2-settings-view-for-datafields-shown-wrong-on-simulator?CommentId=db5901be-c8d8-4a72-abd0-569ffd96f3a9); [fenix7/epix problem with getSettingsView (bug report)](https://forums.garmin.com/developer/connect-iq/i/bug-reports/fenix7-epix-problem-with-getsettingsview)
- Known bugs, forum hearsay:
  - On fēnix 7 and epix 2, pushing Menu2 from `getSettingsView` caused odd behavior. The underlying view kept updating and resources may collide.
  - Using Menu2 (API 3.0) inside `getSettingsView` (API 3.2) crashed some older devices.
  - A report says `getSettingsView` "does not work for Venu 2".
  - In the SDK 3.2 simulator, the data field settings view was not full-screen with multi-field layouts; this worked on a real fēnix 6S Pro.
  
  — [fenix7/epix problem with getSettingsView](https://forums.garmin.com/developer/connect-iq/i/bug-reports/fenix7-epix-problem-with-getsettingsview); [AppBase.getSettingsView does not work for Venu 2](https://forums.garmin.com/developer/connect-iq/i/bug-reports/appbase-getsettingsview-does-not-work-for-venu-2); [getSettingsView bug](https://forums.garmin.com/developer/connect-iq/i/bug-reports/getsettingsview-bug); [SDK 3.2 settings view for datafields](https://forums.garmin.com/developer/connect-iq/i/bug-reports/sdk-3-2-settings-view-for-datafields-shown-wrong-on-simulator?CommentId=db5901be-c8d8-4a72-abd0-569ffd96f3a9)
- Forum (snippet): a CIQ data field can also be configured from the device's "Activities, Apps and More" settings, as well as from the Connect IQ app. — [How to configure Connect IQ data field? (Edge 840 forum)](https://forums.garmin.com/sports-fitness/cycling/f/edge-840-series/330389/how-to-configure-connect-iq-data-field)

### Inferences
- A course-picker Menu2 inside `getSettingsView` can list courses already saved in Storage by name and write the chosen index to Storage or Properties. This removes the need for phone settings entirely. It works the same whether the app is sideloaded, beta or public.
- The docs say only "activity menu" and don't prohibit calling `makeWebRequest` from the settings view. Whether a data field's settings view can do network I/O, for example "download course #N", is unverified and should be tested on the device.
- The device list was generated Dec 2024, so newer products (fēnix 8 Pro, Forerunner 570/970, Edge 550/850, and others) are absent only because they post-date the doc. They very likely support it too; this is inference, not verified.

### Gaps
- There is no official, device-specific button path for fēnix 8 (for example, hold MENU in the activity → Activity Settings → Data Screens → … or a "Connect IQ Fields" entry). The "hold UP → Connect IQ Fields" path comes from forum snippets about fēnix 6 and 7-era devices.
- I don't know whether on Edge the menu appears under the activity profile's data field setup or elsewhere.
- I found no confirmation that fēnix 8 fixed the fēnix 7-era Menu2 issues.

---

## 6. App size limits: .prg or resource size, on-demand resource loading, jsonData limits, number of resources

### Takeaway
The per-app-type memory limit applies to the code and data sections of the PRG, not to resources. Resources, including `jsonData`, live in the PRG and are loaded into the heap only when `loadResource()` is called. A loaded resource then counts fully against the data field's 128 KB heap. I found no official per-resource or per-`jsonData` size limit and no limit on the number of resources.

### Cited Findings
- "JSON data resources can store relatively large amounts of data in your app without having to keep it in memory at all times… declared with the `jsonData` tag… read by the resource compiler, and **loaded on demand at runtime**." Data is loaded with `Application.loadResource(Rez.JsonData.id)`. It can be inline or come from `filename=` (a file containing only JSON). — [Core Topics mirror, "JSON Data"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md); official: [Resources](https://developer.garmin.com/connect-iq/core-topics/resources/)
- `WatchUi.loadResource()` (API 1.0.0) and `Application.loadResource()` (API 3.1.0) "Load a resource from the PRG into memory". "Resources are reference counted just like other Monkey C objects. Loading a resource can be an expensive operation, so do not load resources when handling screen updates." — [Core Topics mirror, "Resources"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Since CIQ 4.0.0, `loadResource` returns `BitmapReference` or `FontReference` for bitmaps and fonts. These are graphics-pool references rather than heap copies; there is no such change for jsonData. — [WatchUi doc (mirror, in repomix-output.md)](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Bitmap resources have a `compress` attribute "to reduce .PRG size". — [Core Topics mirror, Resources/Bitmaps](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum (snippet): "PRG generated exceeds the memory limit" means "the core sections of your PRG (code + data, not resources) are too big". Per `devices.xml`, "watch faces, applications and widgets could be almost 1MB… while data fields could be up to about 128K (131072 bytes)". Older VMs: 2.x watches allow 26 KB for data fields and 1.x allow 16 KB. — [Maximum .PRG file size error (forum 416669)](https://forums.garmin.com/developer/connect-iq/f/discussion/416669/maximum-prg-file-size-error/1955127)
- Forum (snippet, older): "fēnix 5 has a 92 kB memory limit for a watch face, but just 28 kB for a data field". The advice is to keep apps under 128 kB so users can install several. — [Understanding Connect IQ device memory limits (forum 4060)](https://forums.garmin.com/developer/connect-iq/f/discussion/4060/understanding-connect-iq-device-memory-limits); [Storage/Memory Limits (forum 259)](https://forums.garmin.com/developer/connect-iq/f/discussion/259/storage-memory-limits)
- Garmin support FAQ titled "Connect IQ App Limits on a Garmin Device" exists, covering per-device app-count limits. Its content could not be fetched. — [support.garmin.com FAQ](https://support.garmin.com/en-US/?faq=tFmJJnTfs83yuPc8kttAh7)

### Inferences
- Embedding several courses as `jsonData` resources would not cost heap until loaded, but it still requires a rebuild per course set. It only helps for bundling a fixed library.
- A 30 KB course parsed from JSON into Monkey C Arrays of Numbers could expand several times in heap, likely because of per-element object overhead. It could approach the 128 KB data field limit, so compact encodings (packed Numbers or strings) matter.

### Gaps
- There is no official maximum `.prg` or `.iq` size or per-resource size. The 15 MB `.iq` upload cap is only a forum thread title.
- There is no official limit on the number of `jsonData` resources or on the size of one `jsonData` resource.
- The "Connect IQ App Limits" FAQ content (maximum installed data fields or apps) could not be read.

---

## 7. Data field memory limit on fēnix 8, and how Storage reads and writes count against it

### Takeaway
fēnix 8 data fields have a **131,072-byte (128 KB)** memory limit on all variants: 43mm AMOLED, 47/51mm AMOLED and Solar MIP. Background processes get 64 KB. The heap only holds Storage data that the app has loaded with `getValue()`; `Application.Storage` writes go straight to disk. The legacy object store, by contrast, stays in RAM.

### Cited Findings
- fēnix 8 47mm/51mm (tactix/quatix 8 47/51, `displayType` amoled), device `compiler.json` `appTypes`:
  - datafield: 131072
  - watchFace: 131072
  - watchApp: 786432
  - glance: 65536
  - background: 65536
  - audioContentProvider: 524288
  
  Part numbers list `connectIQVersion` "5.1.1" in one copy and "6.0.0" in a newer copy. — [openhab-garmin: fenix847mm/compiler.json](https://github.com/openhab/openhab-garmin/blob/main/.github/ConnectIQ/Devices/fenix847mm/compiler.json); [granbike-face-builder: fenix847mm/compiler.json](https://github.com/mgallesio/granbike-face-builder/blob/master/backend/devices/fenix847mm/compiler.json)
- fēnix 8 43mm (amoled) and fēnix 8 Solar 51mm (mip) have identical `appTypes` limits (datafield 131072). `connectIQVersion` is "6.0.0" in the granbike copy and "5.2.0" in the meshtastic copy of Solar 51mm. — [granbike fenix843mm](https://github.com/mgallesio/granbike-face-builder/blob/master/backend/devices/fenix843mm/compiler.json); [granbike fenix8solar51mm](https://github.com/mgallesio/granbike-face-builder/blob/master/backend/devices/fenix8solar51mm/compiler.json); [meshtastic-garmin-watch fenix8solar51mm](https://github.com/gnortsmralien/meshtastic-garmin-watch/blob/main/.connectiq/Devices/fenix8solar51mm/compiler.json)
- `Application.Storage`: "Information is automatically saved on disk when `Storage.setValue()` is called." Legacy object store: "a Dictionary that lives in memory until your app terminates… costs against your runtime memory". — [Core Topics mirror, Persisting Data](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Since CIQ 2.4.x the heap uses dynamically allocated memory handles, one per unique object. "Reaching the object limit… will cause a runtime error." — [Monkey C guide mirror, "Handles and Heap Allocation"](https://github.com/tkafka/garmin-sdk-docs-for-ai/blob/main/repomix-output.md)
- Forum thread titles (content not retrieved) show serialization memory overhead is a known concern: "Memory Requirements when Storing JSON from Glance" and "Guess of real array size in storage". — [forum 412304](https://forums.garmin.com/developer/connect-iq/f/discussion/412304/memory-requirements-when-storing-json-from-glance/1936906); [forum 331932](https://forums.garmin.com/developer/connect-iq/f/discussion/331932/guess-of-real-array-size-in-storage)

### Inferences
- The 128 KB covers code, globals and all live objects: the loaded course chunk, the decoded profile array, the current view's objects, and any `makeWebRequest` response dictionary while it is being handled. Load only the active course's chunks with `getValue`. Decode them into a compact form and release raw strings, so that peak memory stays well under 128 KB.
- The fēnix 8 connectIQVersion values (5.1.1 → 5.2.0 → 6.0.0) come from successive SDK device-file snapshots. The watch's current API level is therefore firmware-dependent. The memory limits were the same in every snapshot examined.

### Gaps
- I have no official figure for the transient heap cost of `Storage.setValue` or `getValue`, for example whether serialization needs a temporary buffer the size of the value.
- I couldn't retrieve the forum discussions on this.
- There is no information on whether the 128 KB includes the code segment on newer VMs. It does per the "PRG exceeds memory limit" forum explanation, but that is not an official statement.
