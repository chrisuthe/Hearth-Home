# Android App Launcher Implementation Plan

> **Superseded on hardware:** the split approach below (app top, Hearth bottom via a relaunch trick) failed on the T901; Hearth now stays top/left and the app opens `LAUNCH_ADJACENT` bottom/right. See the spec's "First hardware pass".

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hearth on Android launches chosen installed apps (YouTube, Plex) from tiles, in a split screen (app top, Hearth bottom) or full screen with picture-in-picture, and keeps working and can come forward while the app is in front.

**Architecture:** A config list of apps (`androidApps`) yields one dynamic `HearthModule` per app, as webviews do. A new `com.hearth/apps` method channel lists, iconifies and launches apps and brings Hearth forward. A small `specialUse` foreground service (`AppSessionService`) keeps Hearth's process from being frozen while an app is in front and hosts the floating Hearth button. A Dart `ForegroundSummoner` listens to the same sources the layer-5 overlays wake on and asks native to bring Hearth forward.

**Tech Stack:** Flutter/Dart (Riverpod 2), Kotlin (`FlutterActivity`, `MethodChannel`, `Service`, `WindowManager` overlay).

**Spec:** `docs/specs/2026-10-17-android-app-launcher-design.md`

## Global Constraints

- Android only. Gate Dart with the repo idiom `bool get androidAppsSupported => debugAndroidAppsSupportedOverride ?? (!kIsWeb && Platform.isAndroid);` (`dart:io`, never `defaultTargetPlatform`, which reports Android under `flutter test`). Nothing appears on Linux/Windows/Pi.
- Split is the default layout; per-tablet setting `Split / Full screen`. No per-app override.
- Split puts the app on top and Hearth on the bottom (landscape: app left, Hearth right). If the relaunch trick fails on hardware, ship Android's default instead (Hearth top) — decided.
- Anything that wakes Hearth (notification deck incl. info cards and fired timers, alarm, DLNA cast, Plex cast, Live TV) brings it forward in full-screen mode. After that the app stays in the corner until tapped.
- `SYSTEM_ALERT_WINDOW` ("Display over other apps") is the one required permission; home role optional.
- Swiping onto an app's page never launches it; only a tap does.
- UI colors from `context.hearthColors`, never literals; `debugPrint` not `print`; `prefer_const_*` lints.
- New screens go in `test/portrait/` via `testLayouts`.
- Flutter is at `/c/flutter/bin/flutter` (not on PATH).
- **Commit messages: no `Co-Authored-By`, no mention of Claude/AI.** Conventional style as in `git log` (`feat(android): …`).

## Review Focus

1. **Wake while backgrounded.** All overlays wake via post-frame callbacks, and a backgrounded Flutter app renders no frames, so nothing may depend on frames: the summoner must fire from a bare `ProviderContainer` with no widget pumped (Task 5 test `summons without any frame`).
2. **A sticky notification left on the deck.** The user taps the game back full screen; Hearth must not yank forward again until something *new* arrives (rising-edge rule, Task 5 test `does not re-summon while unchanged`).
3. **App uninstalled after being added.** Tile shows "Not installed", tap does nothing harmful, `launch` returns false (Task 2 test `launch returns false for missing package`, Task 3 test `missing app shows not installed`).
4. **Split chosen on a small screen (sw < 600dp).** The relaunch trick would bring Hearth full screen over the app; native must open the app full screen instead (Task 2 step "small-screen guard", verified in Task 6).
5. **Overlay permission not granted.** Launch still works (full screen); bring-forward and the button silently no-op with a log line; the plugin shows the missing permission (Task 4 test `shows overlay permission missing`).

---

### Task 1: Config model

**Files:**
- Create: `lib/config/android_app_config.dart`
- Modify: `lib/config/hub_config.dart` (field, constructor default, `copyWith`, `toJson`, `fromJson` — follow `webviews`)
- Test: `test/config/android_app_config_test.dart`

**Interfaces:**
- Produces:
  - `class AndroidAppConfig { final String packageName; final String name; const AndroidAppConfig({required this.packageName, required this.name}); String get id => 'app:$packageName'; Map<String, dynamic> toJson(); factory AndroidAppConfig.fromJson(Map<String, dynamic>); }` with value `==`/`hashCode`.
  - `enum AndroidAppLayout { split, fullscreen }` with `toJson() => name` and `static AndroidAppLayout fromJson(String?)` defaulting to `split`.
  - `HubConfig.androidApps` (`List<AndroidAppConfig>`, default `const []`, JSON key `androidApps`) and `HubConfig.androidAppLayout` (`AndroidAppLayout`, default `split`, JSON key `androidAppLayout`).

- [ ] **Step 1: Write failing tests**: `round-trips through json` (two apps + `fullscreen` survive `HubConfig.fromJson(toJson())`); `defaults to split and no apps` (`HubConfig.fromJson({})`); `unknown layout falls back to split` (`'androidAppLayout': 'bogus'`); `id is app:<package>` (`AndroidAppConfig(packageName: 'com.google.android.youtube', name: 'YouTube').id == 'app:com.google.android.youtube'`); `entries without packageName are dropped on load`.
- [ ] **Step 2: Run** `/c/flutter/bin/flutter test test/config/android_app_config_test.dart` — expect FAIL (missing types).
- [ ] **Step 3: Implement** the types and the `HubConfig` wiring.
- [ ] **Step 4: Run** the test file and `/c/flutter/bin/flutter test test/config` — expect PASS.
- [ ] **Step 5: Commit** `feat(android): config for launchable apps and their layout`

---

### Task 2: Native `com.hearth/apps` channel and Dart bridge

**Files:**
- Create: `android/app/src/main/kotlin/com/hearth/hearth/apps/AppsChannel.kt`
- Modify: `android/app/src/main/kotlin/com/hearth/hearth/MainActivity.kt` (construct/dispose like `WifiChannel`; static `resumed` flag set in `onResume`/`onPause`, read by Task 4's service)
- Modify: `android/app/src/main/AndroidManifest.xml` (`SYSTEM_ALERT_WINDOW`; `<queries><intent><action MAIN/><category LAUNCHER/></intent></queries>`)
- Create: `lib/services/android_apps.dart`
- Test: `test/services/android_apps_test.dart`

**Interfaces:**
- Consumes: `AndroidAppLayout` (Task 1).
- Produces (Dart, `lib/services/android_apps.dart`):
  - `bool get androidAppsSupported` + `@visibleForTesting bool? debugAndroidAppsSupportedOverride`.
  - `class InstalledApp { final String packageName; final String label; }`
  - `class AndroidAppsBridge` over `MethodChannel('com.hearth/apps')`:
    - `Future<List<InstalledApp>> listApps()` — method `listApps`, returns `[{packageName, label}]`, sorted by label, Hearth itself excluded.
    - `Future<Uint8List?> icon(String packageName)` — method `icon`, PNG bytes or null.
    - `Future<bool> launch(String packageName, AndroidAppLayout layout)` — method `launch`, args `{packageName, layout: layout.name}`; false if not installed.
    - `Future<bool> overlayGranted()` — method `overlayGranted` (`Settings.canDrawOverlays`).
    - `Future<void> openOverlaySettings()` — method `openOverlaySettings` (`ACTION_MANAGE_OVERLAY_PERMISSION` for Hearth's package).
    - `Future<void> bringToFront()` — method `bringToFront`.
    - Every method catches `PlatformException`/`MissingPluginException`, logs with `debugPrint`, and returns the empty/false value.
  - `final androidAppsBridgeProvider = Provider<AndroidAppsBridge>(...)`.
  - `final androidAppIconProvider = FutureProvider.family<Uint8List?, String>(...)` (cached per package).

Native `launch` behaviour (`AppsChannel.kt`):
- No launch intent for the package → `result.success(false)`.
- `fullscreen`, **or** `split` with `resources.configuration.smallestScreenWidthDp < 600` (**small-screen guard**): start the app's launch intent with `FLAG_ACTIVITY_NEW_TASK`.
- `split` on a large screen (**relaunch trick**): start the app full screen as above, then post (main `Handler`, ~250 ms) `startActivity(Intent(activity, MainActivity::class.java).addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_LAUNCH_ADJACENT))` so Hearth is the adjacent window and lands bottom/right. Keep the alternative (app launched *with* `LAUNCH_ADJACENT` from Hearth, Hearth top) as a second private function so Task 6 can switch with a one-line change.
- Every successful launch also starts `AppSessionService` (Task 4; until Task 4 lands, leave a `// Task 4` call site — do not stub a class).
- `bringToFront`: if `MainActivity.resumed` → no-op; else if `!Settings.canDrawOverlays` → log and no-op; else `startActivity(Intent(context, MainActivity::class.java).addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_REORDER_TO_FRONT))`.
- `icon`: `packageManager.getApplicationIcon(pkg)` → bitmap (handle `AdaptiveIconDrawable` by drawing into a 192px `Bitmap`) → PNG bytes.

- [ ] **Step 1: Write failing Dart tests** using `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`: `listApps parses and returns apps`; `launch sends package and layout name` (asserts args `{'packageName': 'com.plexapp.android', 'layout': 'split'}`); `launch returns false for missing package` (handler returns false); `launch returns false when channel is missing` (no handler → `MissingPluginException`); `overlayGranted false on PlatformException`.
- [ ] **Step 2: Run** `/c/flutter/bin/flutter test test/services/android_apps_test.dart` — expect FAIL.
- [ ] **Step 3: Implement** `lib/services/android_apps.dart`.
- [ ] **Step 4: Run** the test — expect PASS.
- [ ] **Step 5: Implement** `AppsChannel.kt`, the `MainActivity` wiring and the manifest entries.
- [ ] **Step 6: Build** `/c/flutter/bin/flutter build apk --debug` — expect `Built build/app/outputs/flutter-apk/app-debug.apk`.
- [ ] **Step 7: Commit** `feat(android): com.hearth/apps channel to list and launch apps`

---

### Task 3: App modules and tiles

**Files:**
- Create: `lib/modules/android_app/android_app_module.dart`, `lib/modules/android_app/android_app_launch_card.dart`
- Modify: `lib/modules/module_registry.dart` (`modulesForConfig` appends `config.androidApps.map(AndroidAppModule.new)` only when `androidAppsSupported`)
- Modify: `lib/app/hub_shell.dart` (`_openMenuModule`: an `AndroidAppModule` launches via the bridge with `config.androidAppLayout` instead of pushing a route)
- Test: `test/modules/android_app/android_app_module_test.dart`, `test/portrait/module_android_app_portrait_test.dart`

**Interfaces:**
- Consumes: `AndroidAppConfig`, `AndroidAppLayout`, `HubConfig.androidApps/androidAppLayout` (Task 1); `androidAppsSupported`, `debugAndroidAppsSupportedOverride`, `androidAppsBridgeProvider`, `androidAppIconProvider`, `AndroidAppsBridge.launch`, `listApps` (Task 2).
- Produces:
  - `class AndroidAppModule implements HearthModule` — `id` = `config.id`, `name` = `config.name`, `icon` = `Icons.apps`, `defaultOrder` = `200`, `isConfigured` true, `buildScreen` → `AndroidAppLaunchCard(app: config)`, `buildSettingsSection` null, `isCommunity` false.
  - `Future<void> launchAndroidApp(WidgetRef ref, AndroidAppConfig app)` in `android_app_launch_card.dart` — reads layout from config and calls the bridge; shows a toast `'${app.name} is not installed'` via `toastProvider` when `launch` returns false. Used by both the card and `HubShell`.
  - `AndroidAppLaunchCard` — centred app icon (from `androidAppIconProvider`, falling back to `Icons.apps`), name, and an **Open** button. Shows **Not installed** (and disables Open) when the package is absent from `listApps()`. Never launches from `initState`/`isActive`.

- [ ] **Step 1: Write failing tests**: `modules are absent off Android` (override false → no `app:` ids in `modulesForConfig`); `one module per configured app on Android`; `card shows name and Open`; `tapping Open launches with the configured layout` (fake bridge records `(package, layout)`); `becoming active does not launch` (pump with `isActive: true`, fake bridge records no call); `missing app shows not installed` (fake `listApps` lacks the package → text `Not installed`, Open disabled). Portrait: `testLayouts('app launch card', …)` asserting the Open button is inside the canvas.
- [ ] **Step 2: Run** both files — expect FAIL.
- [ ] **Step 3: Implement** module, card, registry and `HubShell` hook.
- [ ] **Step 4: Run** both files plus `/c/flutter/bin/flutter test test/portrait test/modules` — expect PASS.
- [ ] **Step 5: Commit** `feat(android): app tiles that launch installed apps`

---

### Task 4: Apps settings plugin

**Files:**
- Create: `lib/plugins/apps/apps_plugin.dart`
- Modify: `lib/plugins/plugin_registry.dart` (add `AppsPlugin()` after `WebviewPlugin()`)
- Test: `test/plugins/apps/apps_plugin_test.dart`; `test/portrait/settings_portrait_test.dart` if it enumerates plugins

**Interfaces:**
- Consumes: Task 1 types; `androidAppsSupported`, `androidAppsBridgeProvider`, `InstalledApp` (Task 2).
- Produces: `class AppsPlugin extends HearthPlugin` — `id` `hearth.apps`, `name` `Apps`, `icon` `Icons.apps`, `category` `PluginCategory.feature`, `order` `95`, `isVisible` → `androidAppsSupported`, `statusFor` → `needsSetup` when `androidApps` is empty, else `configured`.

Panel content (both surfaces, same order):
1. **Open apps in**: Split / Full screen (writes `androidAppLayout`). Helper text: "Split keeps Hearth on screen beside the app. Full screen shrinks the app into a corner when Hearth needs you."
2. **Permission status**: when `overlayGranted()` is false, a warning row "Allow Hearth to display over other apps so it can come forward during alarms and show its button over the app" with a **Grant** button → `openOverlaySettings()`.
3. **Apps**: every installed launchable app with a checkbox; checking adds `AndroidAppConfig(packageName, name: label)` to `androidApps` **and** adds `'swipe'` to `modulePlacements[id]` if the id has no placement yet; unchecking removes the entry (leave placements alone).

Routes (each handler returns 404 when `!androidAppsSupported`, like `CapturePlugin._gated`):
- `GET apps` → `{installed: [{packageName, label}], selected: [AndroidAppConfig json], layout, overlayGranted}`.
- `POST apps` → body `{selected: [...], layout}`; persists both via `req.updateConfig`, adding default placements as above.

HTML follows the `webview_plugin.dart` pattern (static fragment + `hearth.action`), with `data-config-path="androidApps"` and `data-config-path="androidAppLayout"` for the web parity guard.

- [ ] **Step 1: Write failing tests**: `identity is correct`; `hidden off Android`; `status needs setup with no apps`; `checking an app adds it with a swipe placement`; `shows overlay permission missing` (fake bridge `overlayGranted` false → Grant visible); `GET apps 404s off Android`; `POST apps persists selection and layout`; plus run `test/plugins/web_parity_guard_test.dart`.
- [ ] **Step 2: Run** `/c/flutter/bin/flutter test test/plugins/apps test/plugins/web_parity_guard_test.dart test/plugins/plugin_registry_test.dart` — expect FAIL.
- [ ] **Step 3: Implement** the plugin and registry entry.
- [ ] **Step 4: Run** the same command plus `test/portrait/settings_portrait_test.dart` — expect PASS.
- [ ] **Step 5: Commit** `feat(android): Apps settings to choose apps and how they open`

---

### Task 5: Keeping Hearth alive, floating button, and coming forward

**Files:**
- Create: `android/app/src/main/kotlin/com/hearth/hearth/apps/AppSessionService.kt`
- Modify: `android/app/src/main/AndroidManifest.xml` (service `foregroundServiceType="specialUse"` with `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Keeps the kiosk's alarms and timers running while another app is in front"/>`; `FOREGROUND_SERVICE_SPECIAL_USE`)
- Modify: `AppsChannel.kt` (start the service on launch, replacing the Task 2 call site), `MainActivity.kt` (notify the service on `onResume`/`onPause`; stop it in `cleanUpFlutterEngine` beside `HearthAudioService`)
- Create: `lib/services/foreground_summoner.dart`
- Modify: `lib/main.dart` (eager `container.read(foregroundSummonerProvider)` when `androidAppsSupported`, beside the other eager reads)
- Test: `test/services/foreground_summoner_test.dart`

**Interfaces:**
- Consumes: `AndroidAppsBridge.bringToFront`, `androidAppsBridgeProvider`, `androidAppsSupported` (Task 2); `notificationServiceProvider` (`.notifications`), `alarmServiceProvider` (`.firedAlarm`), `dlnaRendererStateProvider`, `plexPlayerStateProvider` (`.hasMedia`), `plexLiveTvStateProvider` (`.hasMedia || phase == LiveTvPhase.error`) — the exact conditions the five overlays in `HubShell` render on.
- Produces:
  - `class WakeSnapshot { final int notifications; final bool alarm; final bool dlna; final bool plex; final bool liveTv; }`
  - `bool shouldSummon(WakeSnapshot before, WakeSnapshot after)` — true when `after.notifications > before.notifications`, or any of `alarm/dlna/plex/liveTv` goes false→true.
  - `final foregroundSummonerProvider = Provider<void>(...)` — `ref.listen`s the five providers (no widget, no frame), keeps the last snapshot, calls `bringToFront()` when `shouldSummon`. Native decides whether that is a no-op (Hearth resumed, no permission).

Native `AppSessionService`:
- Foreground (`specialUse`) from first launch until Hearth's activity finishes. Notification channel "App session", text "Hearth stays awake while another app is open." *(Plan call: the session never ends early; on a kiosk the persistent notification is acceptable, and detecting when another app's task closes needs permissions Hearth doesn't have.)*
- Owns the floating Hearth button: a `TYPE_APPLICATION_OVERLAY` window (~56dp round, Hearth launcher icon, bottom-start corner, 16dp margin — opposite PiP's default bottom-end) shown only while `MainActivity.resumed` is false and `Settings.canDrawOverlays` is true; tap → same intent as `bringToFront`. Drag is not required.

- [ ] **Step 1: Write failing Dart tests**: `summons when a notification arrives`; `summons when an alarm fires`; `summons when a cast starts` (dlna, plex, liveTv each); `does not re-summon while unchanged` (same count twice → one call); `summons again for a second notification`; `does not summon when a notification is dismissed`; `summons without any frame` (plain `ProviderContainer`, provider overrides with fakes, no `tester.pump`). `shouldSummon` pure-function cases for each rule.
- [ ] **Step 2: Run** `/c/flutter/bin/flutter test test/services/foreground_summoner_test.dart` — expect FAIL.
- [ ] **Step 3: Implement** `foreground_summoner.dart` and the `main.dart` read.
- [ ] **Step 4: Run** the test, then `/c/flutter/bin/flutter test` (whole suite) — expect PASS.
- [ ] **Step 5: Implement** `AppSessionService.kt`, manifest, channel and activity wiring.
- [ ] **Step 6: Build** `/c/flutter/bin/flutter build apk --debug` and `/c/flutter/bin/flutter analyze` — expect a built APK and `No issues found!`.
- [ ] **Step 7: Commit** `feat(android): keep Hearth awake and bring it forward over a launched app`

---

### Task 6: Half-screen canvases

**Files:**
- Modify: `test/portrait/portrait_harness.dart` (add `kSplitPortraitHalfCanvas = Size(720, 640)` — the Apolosign's Hearth half — and `kSplitLandscapeHalfCanvas = Size(550, 690)` — the T901 landscape half — to `kLayoutCanvases` as `'split half 720x640'` and `'split half 550x690'`)
- Modify: whichever surfaces overflow at those sizes

- [ ] **Step 1:** Add the canvases. Run `/c/flutter/bin/flutter test test/portrait` and list the failures.
- [ ] **Step 2:** Fix overflows that need a local layout change (branch on `MediaQuery`/`LayoutBuilder`, never on `displayOrientation`). If a surface needs a redesign rather than a fix, do not redesign it: leave its canvas skipped for that one test with a `// split-half: <reason>` comment and list it in the report.
- [ ] **Step 3:** Run `/c/flutter/bin/flutter test test/portrait` — expect PASS.
- [ ] **Step 4: Commit** `test(portrait): cover Hearth's half of a split screen`

---

### Task 7: Hardware verification and docs (controller, not a subagent)

Run on the Relndoo T901 over adb (Android 15, sw688dp); the Apolosign 21.5" is not connected this session, so its portrait check is listed as outstanding.

- [ ] **Step 1:** Install the debug APK; grant "Display over other apps"; add YouTube in Apps; place it in the swipe row.
- [ ] **Step 2 (design step 0):** Split launch from the card. Record task bounds (`dumpsys activity activities`). Hearth at bottom/right → keep the trick. Otherwise switch to the fallback function (one line in `AppsChannel.kt`), rebuild, re-check, and note "Hearth top" in the spec.
- [ ] **Step 3 (design steps 1, 2, 4):** Timer in Hearth's half during split; full-screen mode, floating button → video to corner; 5+ min backgrounded then a timer and an HA notification each bring Hearth forward with the video still in the corner; swipe across the app page launches nothing. Use voice-satellite-free checks honestly: alarm/chime audio is silent on Android (separate project), so record "came forward" not "rang".
- [ ] **Step 4:** Update `docs/specs/2026-10-13-android-apk-requirements.md` (new "App launcher" row with verified/assumed states) and the design doc's "What was verified" table with results; add the CLAUDE.md Android paragraph a line on the launcher.
- [ ] **Step 5: Commit** `docs(android): record app launcher hardware pass`, push the branch, open the PR.
