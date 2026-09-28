# JAM Trail — Connect IQ store listing (English)

Text to paste into the Connect IQ developer portal (apps-developer.garmin.com). Update the "What's new" text for each upload and keep the app version in `app/manifest.xml` in step.

Registered as a standalone app (app ID `5b518199-141d-48a0-8b47-a7e994c7484a`, starting at v1.0.0) since 2026-09-28.
Use "Register New App" only for the very first upload; every version after that must go through that same app's
"Upload New Version" — re-registering with this manifest will fail with "The manifest app ID is already in use".

## App name

JAM Trail

## Short description (one line)

Trail-running data field that shows the terrain ahead at one fixed scale, so a 10% climb and a 25% climb never look alike by accident.

## Description (store character-limit version, 2867/3000 chars)

JAM Trail is a full-screen data field for trail running on the Garmin fenix 8 (43/47/51 mm AMOLED). It draws the elevation profile around your position at one fixed scale everywhere on the course, so the slope you see on the watch matches the slope you feel underfoot.

Why: standard climb graphs (like ClimbPro) stretch every climb to fill the screen, so a gentle 5% hill and a brutal 25% wall look almost identical. JAM Trail never rescales a single climb. Every segment uses the same vertical exaggeration, so a steeper line always means a steeper trail.

WHAT YOU SEE
- Elevation profile around your position, with your position marked. Choose a fixed window (500 m to 10 km) or fit the whole current climb or descent to the screen.
- Current grade in percent as a large, colour-coded number, averaged over 100 m (200 or 400 m also available).
- Grade colours in three bands (0-10%, 10-20%, 20%+), separate colour families for uphill and downhill.
- Automatic climb / descent / flat mode. On a climb or descent: average grade, steepest grade still ahead, remaining ascent/descent, and distance left. On flat ground: distance to the next climb or descent and how much it gains or loses.
- A marker where the current climb or descent ends, or the next one begins.
- Off-course warning with distance from the route.
- Large text throughout: nothing on screen is smaller than the watch's own menu text.

HOW IT WORKS
1. Convert a GPX course into a compact file and publish it to a web address (a converter and hosting setup are part of the open project).
2. Open a trail-running activity at home with your phone nearby. The data field downloads the course through Garmin Connect and stores it on the watch, so it works with no phone connection once you're running.
3. Your position is determined, in order of preference, from Garmin's own course navigation (if you loaded the same GPX as a Garmin course), GPS matching against the stored course, or elapsed distance.

SETTINGS (watch data field settings menu)
- Vertical exaggeration: 2x, 3x, 4x
- Graph range: 500 m to 10 km, or fit to segment
- Current-grade window: 100, 200, 400 m
- Off-course threshold: 30, 50, 100 m
- Grade colours on/off
- Course: follow the server's current course, or pick a stored one
- Delete stored courses (with confirmation) to force a fresh download

GOOD TO KNOW
- Independent, personal-use beta. The course server address is built in and currently points to the author's own server.
- On-screen labels are in Korean.
- First download needs a connected phone with Garmin Connect open; after that the watch works fully offline.
- Works best with the same GPX also loaded as a Garmin course for navigation, but runs on GPS matching alone otherwise.

Requests only the Communications permission, used solely to download course files over a web request relayed through your paired phone.

## Description (full, for reference — same content, more spacing)

JAM Trail is a full-screen data field for trail running on the Garmin fēnix 8 (43 mm, 47 mm and 51 mm AMOLED). It shows the elevation profile around you at the same horizontal and vertical scale everywhere, so the slope you see on the watch matches the slope you feel under your feet.

Why: the standard climb graphs stretch every climb to fill the screen, so a gentle 5% hill and a steep 25% wall can look almost the same. JAM Trail never rescales a single climb. Every segment uses the same vertical exaggeration (2x, 3x or 4x, default 3x), and the current grade is printed as a big number in percent.

What you see
- Elevation profile around your position, with your position marked on it. The view is a fixed window (500 m, 1 km, 2 km, 5 km or 10 km; 2 km by default) or the whole current climb or descent.
- Grade colours in three bands (0-10%, 10-20%, 20% and above), with different colour families for uphill and downhill, so direction and steepness are readable at a glance.
- Current grade in %, averaged over the 100 m around you (200 m or 400 m also available).
- Automatic climb / descent / flat mode. On a climb or descent you get the average grade of the segment, the maximum grade still ahead, the ascent or descent left and the distance left. On flat ground you get the distance to the next climb or descent and how much it gains or loses.
- A dot on the profile marks the end of the current climb or descent, or the start of the next one.
- Off-course warning with the distance from the course.
- Large text everywhere; nothing on the screen is smaller than the watch's own menu text.

How it works
1. Convert your GPX course to a compact file and publish it to a web address (a small converter and a GitHub Pages template are part of the project).
2. Open a trail-running activity at home with your phone nearby. The data field downloads the course through the Garmin Connect app and stores it on the watch. It is then available with no phone connection, so you can run offline in the mountains.
3. While you run, the position on the course comes from Garmin's course navigation if you are following the same GPX as a Garmin course (most accurate), otherwise from GPS matching against the stored course, otherwise from elapsed distance.

Settings (on the watch, in the data field settings menu)
- Vertical scale: 2x, 3x, 4x
- Graph range: 500 m, 1 km, 2 km, 5 km, 10 km, or fit to the segment
- Current-grade averaging distance: 100 m, 200 m, 400 m
- Off-course threshold: 30 m, 50 m, 100 m
- Grade colours: on / off
- Course: follow the course published on the server, or pick a stored one
- Delete stored courses (with a confirmation step) to force a fresh download
- Diagnostics line for testing (off by default)

Good to know
- This is a personal beta. The course server address is built into the app, so it currently loads courses from the author's server.
- The screen text is in Korean.
- Courses are downloaded through the phone connection, so the first download needs a connected phone with the Garmin Connect app open.
- Best used together with the same GPX loaded as a Garmin course for navigation; the data field works without it, using GPS matching.

## What's new

Version 1.0.0 (first release under this app registration)
- Initial public listing. Includes everything from the earlier beta test build: fixed-scale elevation profile, three-band grade colours, automatic climb/descent/flat mode, off-course warning, GPX course download and offline storage, and a full settings menu (vertical scale, graph range, grade-averaging window, off-course threshold, grade colours, course selection, delete stored courses).

## What's new (history from the earlier beta test build, same app)

Version 1.3.0
- Added "Delete stored courses" to the settings menu, with a confirmation step, to force a fresh download.

Version 1.2.0
- Bigger text: nothing on the data field or in the settings menu is smaller than the watch's default menu text.
- New layout for the data field: mode label, current grade with average and maximum grade beside it, profile, remaining ascent/descent and distance.
- Settings menu is left-aligned with larger text.
- Three grade colour bands instead of six.

## Permissions justification

Communications: downloads the course file over a web request through the paired phone. Nothing else is sent: each request contains only the path of a course file and a timestamp.

## Supported devices

Garmin fēnix 8 AMOLED, 43 mm and 47 mm / 51 mm (Connect IQ API level 5.0 or later).

## Tags / keywords

trail running, ultra, elevation profile, grade, slope, climb, GPX course, data field, fēnix 8

## Support text

JAM Trail is a personal project in beta. Please report problems with a photo of the screen and what you were doing.
