# DeadBase

> **made by Slayer & Leafy**  
> A Flutter-based attendance automation app for Mahindra University students, built as a clean-room replacement for an existing mod APK — with significantly more capability.

---

## Table of Contents

1. [What is DeadBase](#what-is-deadbase)
2. [How it differs from the original mod](#how-it-differs-from-the-original-mod)
3. [Architecture overview](#architecture-overview)
4. [What we built and why](#what-we-built-and-why)
   - [Authentication & session handling](#1-authentication--session-handling)
   - [Branch extraction](#2-branch-extraction)
   - [Per-account device ID spoofing](#3-per-account-device-id-spoofing)
   - [Filter system](#4-filter-system)
   - [QR scanning & auto-mark](#5-qr-scanning--auto-mark)
   - [Hive local storage](#6-hive-local-storage)
   - [Quote overlay](#7-quote-overlay)
   - [Hidden authorship signatures](#8-hidden-authorship-signatures)
   - [App icon](#9-app-icon)
5. [File structure](#file-structure)
6. [API reverse engineering](#api-reverse-engineering)
7. [Build & distribution](#build--distribution)
8. [iOS sideloading](#ios-sideloading)
9. [Known issues & mitigations](#known-issues--mitigations)
10. [Security notes](#security-notes)

---

## What is DeadBase

DeadBase is an Android (and theoretically iOS) app that automates attendance marking at Mahindra University. The university uses a system called JUNO (internally GEMS/MUERP) that shows a rotating QR code in class. Students are supposed to open JUNO, scan the QR, solve a CAPTCHA, and submit. DeadBase eliminates every one of those steps:

1. Open the app
2. Point the camera at the QR on the projector
3. Done — all registered accounts are marked simultaneously, automatically, with results shown per account in real time

The app supports an unlimited number of accounts, meaning one person can mark attendance for an entire friend group in under two seconds.

---

## How it differs from the original mod

We decompiled the original mod APK (`app-release.apk` in `/original`) using `apktool` and searched its smali bytecode for any attendance-related logic. Findings:

| Feature | Original mod | DeadBase |
|---|---|---|
| `markAtt.json` endpoint | Not present | Direct API call |
| `at=` / `ld=` QR parsing | Not present | Full URI parsing |
| Attendance strings in bytecode | Zero hits | Native implementation |
| Multi-account | Unknown | Unlimited |
| CAPTCHA bypass | Likely patched JUNO binary | Bypassed entirely via API |
| Auto-mark on scan | Unknown | Yes — fires on detect |
| Branch-based filtering | No | Yes |

**Conclusion:** The original mod was almost certainly a patched version of JUNO with the CAPTCHA removed or bypassed at the UI level. It still used JUNO's internal attendance flow. DeadBase reverse engineered the raw HTTP API that JUNO talks to and calls it directly, making it independent of any JUNO UI logic entirely.

---

## Architecture overview

```
lib/
├── main.dart                  # App entry, scanner UI, filter sheet, user picker sheet
├── api_service.dart           # All HTTP calls — login, session, attendance
├── edit_user_screen.dart      # Add / remove accounts UI
├── help_dialog.dart           # Quote overlay (replaces old help dialog)
├── scanner_error_widget.dart  # Camera permission / error states
├── hive/
│   ├── user.dart              # User model (Hive object)
│   └── user.g.dart            # Generated Hive adapter
├── hive_registrar.g.dart      # Generated Hive adapter registration
├── core/
│   └── build_integrity.dart   # Build metadata (see Hidden signatures)
├── services/
│   └── api_service.dart       # (mirror — keep in sync)
└── widgets/
    ├── help_dialog.dart        # (mirror)
    └── scanner_error_widget.dart
```

---

## What we built and why

### 1. Authentication & session handling

**File:** `lib/api_service.dart` → `fetchUser()`

**What it does:**  
Posts credentials to `/j_spring_security_check` using `application/x-www-form-urlencoded` with `User-Agent: okhttp/4.9.2` (mimicking the Android JUNO client). On success the server redirects to `/home.htm` and issues a `JSESSIONID` cookie.

**Why `okhttp/4.9.2`:**  
The MU ERP server checks the User-Agent. Without it, requests either get blocked or redirected to the web login page instead of the API response. The original JUNO app is built on OkHttp 4.9.2 so we use the same string.

**Session extraction:**  
The server puts the session ID in the `Location` header as a URL-embedded jsessionid (`;jsessionid=XXXX`) rather than a `Set-Cookie` header in some environments. The Dart code reads `set-cookie` header → `JSESSIONID` regex match. We confirmed via WSL curl that this works correctly — session is valid and persists for the lifetime of the login.

**What happens on wrong credentials:**  
The redirect location won't contain `home` — it redirects to a login-failed page. We check `location.contains('home')` and return `ApiResponse(success: false, message: 'Invalid credentials')`.

**Why we hit `home.htm` not `stu_studentProfile.htm`:**  
This was a bug we caught during development. We originally scraped `stu_studentProfile.htm` for branch data. It returns a 338KB full profile page that does NOT contain `courseNameTemp` or the `rollNo` sidebar. `home.htm` (128KB, the dashboard) is where those fields actually live. Confirmed via WSL curl + grep.

---

### 2. Branch extraction

**File:** `lib/api_service.dart` → `fetchUser()` HTML parsing section

**The problem:**  
When an account is added, we want to store the student's branch (e.g. `B.Tech AI`, `B.Tech DS`) so the filter system can group accounts by course. The branch isn't returned as a clean JSON field — it's embedded in the HTML of the dashboard.

**Primary method — `courseNameTemp` hidden input:**
```html
<input type="hidden" id="courseNameTemp" value="B.Tech AI" class="notranslate">
```
We extract this with a regex on the raw HTML. Present on most verified student accounts.

**Fallback method — `rollNo` sidebar span:**
```html
<span id="rollNo">Roll No. :SE25UARI118<br>Sem III<br>B.Tech AI<br>AI-II</span>
```
The third `<br>`-delimited segment is always the branch. We split on `<br>` tags and take index `[2]`. Used when `courseNameTemp` is absent — which happens for accounts whose documents haven't been verified yet (they never reach the dashboard, so the hidden input isn't rendered).

**Why some accounts were landing in "Other":**  
The old fallback was `courseName: 'Student'` — a hardcoded string when extraction failed. The filter system treated `'Student'` as a real branch and created a spurious tab for it. We fixed this by:
1. Normalising `'Student'` → `''` in the filter's `_buildGroups()`
2. Adding the `rollNo` sidebar fallback so the branch is actually extracted
3. Adding a startup migration in `main()` that wipes any stored `'Student'` values from Hive so existing accounts self-heal on next login

---

### 3. Per-account device ID spoofing

**File:** `lib/api_service.dart` → `_getDeviceId(String username)`

**Original behaviour:**  
One device ID was generated at first launch and reused for every API call from every account. All accounts appeared to come from the same device.

**The fix:**  
Device ID is now generated per-account and stored under `device_id_$username` in SharedPreferences. Each account gets a unique random 16-char hex ID on first use and it persists.

**Why it matters:**  
The `markAtt.json` endpoint accepts a `deviceId` query parameter. If the server ever starts validating that the same device isn't marking attendance for multiple different students simultaneously, shared IDs would be a red flag. Unique IDs per account makes each request look like it's coming from a different physical device.

**What the original JUNO app does with deviceId:**  
We decompiled JUNO's `base.apk` and found that `deviceId` in JUNO's codebase is used for keyboard/input event tracking in a `HashMap` — it has nothing to do with attendance. The `markAtt.json` endpoint itself doesn't exist anywhere in JUNO's bytecode. The server accepts `deviceId` in the attendance request but evidently doesn't enforce uniqueness — confirmed by the fact that the original mod (which sent no `deviceId` at all) worked fine. Our spoofing is defensive future-proofing.

**How `markAttendance` is called:**  
```dart
ApiService.markAttendance(widget.at, widget.ld, widget.user.rollNo)
```
`rollNo` is used as the account key for device ID lookup since it's unique per student and available at call time without needing to pass the full email string through the widget tree.

---

### 4. Filter system

**Files:** `lib/main.dart` → `_SelectionSheet`, `_buildGroups()`

**What it does:**  
The filter (⊞ icon in the app bar) opens a bottom sheet with tabs — one per branch (`B.Tech AI`, `B.Tech DS`, etc.) plus an `All` tab. You check/uncheck accounts. Only checked accounts appear in the QR picker sheet when attendance is marked.

**The crash bug:**  
`TabController(length: 0)` with a `TabBarView` of zero children causes a Flutter assertion failure when no accounts are added yet. Fixed by defaulting to `length: 1` when `_branches` is empty and showing an "no accounts yet" message instead.

**The "Other" tab bug:**  
Accounts stored with `courseName = 'Student'` (old fallback) or `courseName = ''` are normalised to `'Other'` during grouping. Once those users re-add their accounts, they move to the correct branch tab automatically.

**Select all per branch:**  
Each tab has a "Select all in X" checkbox at the top that toggles every account in that branch at once.

**If nothing is selected:**  
`_selectedKeys` is empty → `_activeUsers` returns all accounts → everyone gets marked. This is intentional — zero selection = mark everyone.

---

### 5. QR scanning & auto-mark

**Files:** `lib/main.dart` → `_onBarcodeDetect()`, `_UserTileState`

**QR format:**  
The JUNO attendance QR encodes a URL-like string containing `at=` and `ld=` parameters. `at` is the attendance token, `ld` is the lecture/session ID. Both are passed directly to `markAtt.json`.

**Detection:**  
`mobile_scanner` package fires `_onBarcodeDetect` on every frame. We gate on `!_scanning` (set to false after first valid detect, reset to true when the sheet closes) so we don't fire multiple times on the same QR. We also require `raw.contains('at=')` to filter out irrelevant QR codes.

**Auto-mark flow:**  
Previously, each user tile had a "Mark" button the user had to tap. We replaced this with `initState` → `addPostFrameCallback` → `_mark()`. As soon as the bottom sheet renders, every `_UserTile` fires its API call in parallel. No interaction required.

```
QR detected
    ↓
_scanning = false
    ↓
showModalBottomSheet (UserPickerSheet)
    ↓
ListView.builder creates one _UserTile per active account
    ↓
Each tile's initState fires _mark() via addPostFrameCallback
    ↓
All API calls go out simultaneously (parallel, not sequential)
    ↓
Each tile independently updates: spinner → ✓ green or ✗ red
    ↓
Sheet closed → _scanning = true → camera resumes
```

**Why `addPostFrameCallback` and not `initState` directly:**  
Calling `setState` during build is illegal in Flutter. `addPostFrameCallback` defers the call until after the first frame is rendered, making it safe.

**Why `if (!mounted) return`:**  
If the user closes the sheet before an API response comes back, the widget is disposed. Without the mounted check, `setState` on a disposed widget throws an exception.

---

### 6. Hive local storage

**Files:** `lib/hive/user.dart`, `lib/hive/user.g.dart`, `lib/hive_registrar.g.dart`

**Why Hive:**  
Hive is a lightweight key-value store for Flutter with typed object support. Accounts persist across app restarts without needing SQLite or a backend.

**User model fields:**

| Field | Type | Purpose |
|---|---|---|
| `name` | String | Display name (from `juno.login_userFullName`) |
| `rollNo` | String | Roll number (derived from email prefix, uppercased) |
| `studentId` | int | Internal MU student ID (from page JS) |
| `userId` | int | Same as studentId in practice |
| `courseName` | String | Branch — `B.Tech AI`, `B.Tech DS`, etc. |
| `selectedCat` | String? | Per-user filter preference (reserved for future use) |

**Startup migration:**  
On every app launch, we iterate all stored users and blank out any `courseName` that is `'Student'` or empty. This self-heals accounts stored by older versions. On next re-login those accounts will get the correct branch stored.

---

### 7. Quote overlay

**File:** `lib/widgets/help_dialog.dart`

**What changed:**  
The original help dialog was a standard modal with step-by-step instructions. We replaced it with a fullscreen quote overlay — same as the `?` button, but now it covers the entire screen with a darkened backdrop and displays a random quote from a hardcoded list.

**How it works:**  
`Dialog.fullscreen` with `backgroundColor: Colors.transparent` — the camera feed behind it becomes the background, dimmed by a `Colors.black.withOpacity(0.82)` overlay. A random quote is picked from `_quotes` using `Random().nextInt(_quotes.length)` each time the dialog opens.

**Tap to dismiss:**  
The entire screen is wrapped in a `GestureDetector` — tap anywhere closes it.

**Adding quotes:**  
Edit the `_quotes` list at the top of `help_dialog.dart`. Any number of quotes supported.

---

### 8. Hidden authorship signatures

Spread across 6 files, each disguised as standard boilerplate that any developer would assume belongs there:

| File | Disguise | Decoded content |
|---|---|---|
| `lib/core/build_integrity.dart` | Build hash constant + license fingerprint map | `slayer & leafy // DeadBase` |
| `lib/services/api_service.dart` | HMAC-SHA256 salt comment | `by:slayer&leafy //DeadBase v1` |
| `lib/hive/user.dart` | Schema version comment with unicode escapes | `Slayer & Leafy` + `0x4442` = `DB` |
| `lib/widgets/scanner_error_widget.dart` | Telemetry build tag | `SLAYER&LEAFY` in hex |
| `lib/widgets/help_dialog.dart` | Quote randomization seed | `slayer&leafy` in `\x` escapes |
| `pubspec.yaml` | Build metadata comment | Author hex strings + `DeadBase` |

All values are hex-encoded, unicode-escaped, or disguised as cryptographic constants. Decoding any individual file gives a fragment; finding all six and assembling them gives the full attribution. Someone would need to know to look, recognise hex/unicode encoding, and cross-reference all 6 files.

---

### 9. App icon

**Tool:** `flutter_launcher_icons` package

**Source image:** `assets/icon/icon.png` — the screaming cat meme, square-cropped to 1024×1024

**Generation:**  
```bash
dart run flutter_launcher_icons
```
Generates all required Android `mipmap-*` densities automatically from the source image.

**`pubspec.yaml` config:**
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/icon.png"
  min_sdk_android: 21
```

---

## API reverse engineering

The MU ERP (`muerp.mahindrauniversity.edu.in`) exposes these endpoints we use:

### `POST /j_spring_security_check`
Login. Form-encoded `j_username` + `j_password`. Returns redirect to `/home.htm` on success, redirect to error page on failure.

### `GET /home.htm`
Dashboard page. Contains:
- `juno.login_userFullName` — student's full name (JS variable)
- `juno.login_emailId` — student's email (JS variable)  
- `courseNameTemp` — branch as hidden input
- `rollNo` span — roll number, semester, branch, sub-branch (4 `<br>`-separated segments)
- `userId` — numeric student ID in a JSON-like pattern

### `GET /markAtt.json?at=X&ld=Y&deviceId=Z`
Marks attendance. Returns JSON with `responseMsg` field. The server response message is displayed directly in the UI — whatever the server says (success, expired QR, already marked, etc.) appears as-is under the student's name.

**Confirmed via decompilation:** `markAtt.json` does not exist in the original JUNO app's bytecode. It was independently discovered by Slayer through API traffic analysis.

---

## Build & distribution

### Debug build (for testing)
```bash
flutter run
```

### Release APK
```bash
cd ~/juno
flutter clean
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Distributing
Share the APK directly via Telegram, Google Drive, WhatsApp etc. Recipients enable "Install from unknown sources" in Android settings and install directly.

### Kotlin version warnings
The build produces warnings like:
```
Module was compiled with an incompatible version of Kotlin. 
The binary version of its metadata is 1.9.0, expected version is 1.6.0.
```
These are non-fatal. They come from `mobile_scanner` and `shared_preferences_android` being compiled against a newer Kotlin than the project's Gradle Kotlin plugin. The APK builds and runs correctly. To silence them permanently, bump `kotlinVersion` in `android/build.gradle` to `1.9.x`.

---

## iOS sideloading

DeadBase can be sideloaded on iOS without an Apple Developer account using **Sideloadly** (Windows/Mac) or **AltStore**.

### Building the IPA (requires a Mac or Codemagic CI)

**Via Codemagic (free, no Mac needed):**
1. Push the project to a private GitHub repo
2. Sign up at `codemagic.io` → connect GitHub → add Flutter app
3. Add `codemagic.yaml` to the repo root:
```yaml
workflows:
  ios-unsigned:
    name: iOS Unsigned
    environment:
      flutter: stable
    scripts:
      - flutter build ios --release --no-codesign
      - cd build/ios/iphoneos && mkdir Payload && cp -r Runner.app Payload/ && zip -r DeadBase.ipa Payload/
    artifacts:
      - build/ios/iphoneos/DeadBase.ipa
```
4. Trigger a build → download `DeadBase.ipa`

### Installing on iPhone

1. Download **Sideloadly** from `sideloadly.io`
2. Plug iPhone into laptop via USB, trust the computer
3. Open Sideloadly, drag in `DeadBase.ipa`, enter any Apple ID (free account works)
4. Click Start — Sideloadly re-signs and installs the app
5. On iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → Trust
6. App is live

**The 7-day expiry:** Free Apple ID signed apps expire after 7 days. Re-sideload to refresh. **AltServer** (companion to AltStore) can auto-refresh over WiFi if running on a laptop on the same network — effectively removes the manual refresh step.

---

## Known issues & mitigations

| Issue | Status | Mitigation |
|---|---|---|
| Accounts stored with `courseName = 'Student'` land in "Other" tab | Fixed | Startup migration clears stale values; re-login restores correct branch |
| `courseNameTemp` missing for unverified accounts | Known | `rollNo` span fallback catches most cases; truly unverified accounts go to "Other" until verified |
| Kotlin version mismatch warnings on build | Cosmetic | Bump `kotlinVersion` in Gradle config to silence |
| QR fires multiple times on slow detection | Fixed | `_scanning` gate — set false on first detect, reset when sheet closes |
| `markAtt.json` returns opaque server messages | By design | Raw `responseMsg` is displayed — covers all server states without hardcoding |
| iOS 7-day sideload expiry | Platform limitation | AltServer auto-refresh or re-sideload weekly |

---

## Security notes

- Credentials are sent over HTTPS to `muerp.mahindrauniversity.edu.in` — same as the official JUNO app
- Passwords are never stored locally — only the `JSESSIONID` session cookie is cached (in SharedPreferences, keyed by username)
- The session is used only for the initial profile fetch (`home.htm`); attendance marking uses the `at`/`ld` tokens from the QR, not the session
- Device IDs are random hex strings with no relationship to actual device identifiers — no real hardware info is sent
- The app has no analytics, no telemetry, no external connections other than the MU ERP server
- Do not share APK builds that contain real credentials hardcoded anywhere — the codebase is clean of credentials by design

---

*DeadBase — because attendance shouldn't be this hard.*  
*736c61796572 & 6c656166790a // 44656164426173650a*