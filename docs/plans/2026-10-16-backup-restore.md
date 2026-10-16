# Backup & Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download a full plaintext backup of a kiosk's configuration from the `:8090` portal and restore it onto the same kiosk, which then restarts as the same device.

**Architecture:** A pure-Dart `BackupService` builds and validates the backup document and writes the restored state through `HubConfigNotifier`, a new `AlarmService.replaceAll`, and a `SendspinSecretFiles` port (file-backed on Pi/desktop, method channel on Android). The System plugin exposes `GET backup` / `POST restore`; `LocalApiServer` gates those two paths on the PIN session cookie and gives restore a larger body cap. An `AppRestarter` restarts `hearth.service` on Linux and relaunches the process on Android.

**Tech Stack:** Flutter/Dart, Riverpod, `dart:io` HttpServer, Kotlin (Flutter MethodChannel, AtomicFile).

**Spec:** `docs/specs/2026-10-16-backup-restore-design.md`

## Global Constraints

- Backup and restore routes accept **only** a `hearth_session` cookie; a Bearer `apiKey` alone → 401.
- `hub_config.json` is written via `HubConfigNotifier.update` (compact `jsonEncode`), never pretty-printed.
- Restore rejects `hearthBackup` > 1 and a `hearthVersion` newer than the running build, with exactly: `This backup is from Hearth X; update this kiosk to X or later first.`
- A rejected restore writes nothing.
- Sendspin secrets restore only when `sendspin.platform` equals the running `Platform.operatingSystem`.
- Every replaced file is first copied to `<name>.pre-restore`.
- Restore body cap: 4 MB, restore route only. All other routes keep 64 KB.
- No new third-party dependency.
- `debugPrint`/`Log`, never `print`; `prefer_const_*` lints.

## Review Focus

1. Running version unreadable (`''`, Windows dev) or backup `hearthVersion` empty → the version check is skipped, restore proceeds. Test in Task 1.
2. Backup from a kiosk that never ran Sendspin (`sendspin.files` empty or `sendspin` absent) → restore succeeds, reports `none`, existing Sendspin files untouched. Test in Task 1.
3. `alarms` containing a non-object or an alarm missing fields → 400, nothing written (config included). Test in Task 1.
4. Restored `apiKey` differs from the current one → the restore response must still be delivered (200) before the restart fires. Test in Task 3.
5. Device name with `/`, spaces or quotes → filename is sanitised to `[a-z0-9-]`. Test in Task 1.

---

### Task 1: BackupService core

**Files:**
- Create: `lib/services/backup/backup_service.dart`
- Create: `lib/services/backup/sendspin_secret_files.dart`
- Modify: `lib/modules/alarm_clock/alarm_service.dart` (add `replaceAll`)
- Modify: `lib/services/update_service.dart` (extract `semverIsNewer`; `UpdateInfo.isNewerThan` delegates to it)
- Test: `test/services/backup/backup_service_test.dart`

**Interfaces:**
- Produces:
  - `bool semverIsNewer(String version, String other)` (top-level, `update_service.dart`) — the existing `_parseSemver` comparison; `UpdateInfo.isNewerThan(other)` becomes `semverIsNewer(version, other)` and keeps its "true when other is empty" behaviour.
  - `abstract class SendspinSecretFiles { Future<Map<String, String>> read(); Future<void> write(Map<String, String> files); }` — file name → base64 of the bytes. `write` copies each existing target to `<name>.pre-restore` first and only writes names it is given.
  - `class FileSendspinSecretFiles implements SendspinSecretFiles` — `FileSendspinSecretFiles({Future<String> Function()? directory})`; handles `FileSendspinIdentityStore.fileName` and `FileSendspinPairingStore.fileName`; `chmod 600` after writing on Linux/macOS like `sendspin_stores.dart`.
  - `class BackupRejected implements Exception { final String message; }`
  - `enum SendspinRestore { restored, skipped, none }`
  - `class BackupService` with constructor `BackupService({required HubConfigNotifier config, required AlarmService alarms, required SendspinSecretFiles sendspin, required String platform, required Future<String> Function() installedVersion, Future<String> Function()? directory, DateTime Function()? now})`, `static const formatVersion = 1`, `Future<Map<String, dynamic>> create()`, `String fileName()`, `Future<SendspinRestore> restore(Map<String, dynamic> backup)`.
  - `Future<void> AlarmService.replaceAll(List<Alarm> alarms)` — replaces, awaits the save, keeps ticking, notifies.

- [ ] **Step 1: Write the failing tests** (temp directory for `directory`; `_MemoryConfigNotifier` as in `test/plugins/display/display_plugin_routes_test.dart`, but writing nothing; a fake `SendspinSecretFiles` recording writes; `AlarmService` constructed directly — add an optional `AlarmService({Future<String> Function()? directory})` parameter, defaulting to the app support dir and used by `load`/`_save`, so tests point it at the temp dir)
  - `create() carries config, alarms, sendspin and metadata` — `hearthBackup == 1`, `hearthVersion == '1.22.0'`, `platform == 'linux'`, `config == notifier.current.toJson()` (unredacted: `haToken` present), `alarms` equals `alarms.map((a) => a.toJson())`, `sendspin == {'platform': 'linux', 'files': {...fake files}}`, `createdAt` is ISO-8601 UTC from `now`.
  - `round trip restores config and alarms` — create on one service, restore on a second with different config/alarms → second's `config.current.toJson()` equals the first's; alarms equal; returns `SendspinRestore.restored`; fake received the files.
  - `rejects a newer format` — `hearthBackup: 2` → throws `BackupRejected('This backup needs a newer version of Hearth.')`; a missing/non-int `hearthBackup` → `BackupRejected('This file is not a valid Hearth backup.')`; nothing written (config unchanged, no `.pre-restore` files, fake has no writes).
  - `rejects a newer Hearth` — running `1.21.0`, backup `1.22.0` → `BackupRejected` with message `This backup is from Hearth 1.22.0; update this kiosk to 1.22.0 or later first.`; nothing written.
  - `accepts same and older Hearth` — `1.22.0` onto `1.22.0` and `1.20.3` onto `1.22.0` succeed.
  - `skips the version check when either version is empty` (Review Focus 1).
  - `rejects a missing or non-object config`, `rejects bad alarms` (`alarms: [1]`, `alarms: 'x'`) — `BackupRejected`, nothing written (Review Focus 3).
  - `skips Sendspin from another platform` — backup `sendspin.platform: 'android'` onto `linux` → `SendspinRestore.skipped`, fake untouched, config still restored.
  - `no Sendspin files is none` — `sendspin` absent, and `files: {}` → `SendspinRestore.none`, fake untouched (Review Focus 2).
  - `keeps pre-restore copies` — existing `hub_config.json` and `alarms.json` in the temp dir are copied to `hub_config.json.pre-restore` / `alarms.json.pre-restore` byte-for-byte before restore.
  - `fileName sanitises the device name` — `mqttDeviceName: 'Kitchen / "Hub"'`, now 2026-10-16 → `hearth-backup-kitchen-hub-2026-10-16.json`; empty name → `hearth-backup-hearth-2026-10-16.json` (Review Focus 5).
  - `FileSendspinSecretFiles round-trips bytes` — write `{'sendspin_identity.key': base64(bytes)}` into a temp dir, read back equal; an existing file gets a `.pre-restore` copy; names not in the map are not created.

- [ ] **Step 2: Run to verify failure**
  Run: `/c/flutter/bin/flutter test test/services/backup/backup_service_test.dart`
  Expected: FAIL (missing files/types).

- [ ] **Step 3: Implement**
  - Device name for `fileName`: `config.current.mqttDeviceName`, lower-cased, runs of non-`[a-z0-9]` → `-`, trimmed of `-`; empty → `hearth`.
  - `restore` validates everything first (format, version via `semverIsNewer(backupVersion, running)` only when both non-empty, `HubConfig.fromJson(config)`, `alarms` list → `Alarm.fromJson` each, catching `TypeError`/`FormatException` → `BackupRejected('This file is not a valid Hearth backup.')`), then copies `hub_config.json` / `alarms.json` to `.pre-restore` when present, then `config.update((_) => restored)`, `alarms.replaceAll(list)`, then Sendspin.
  - `create` reads `installedVersion()` once; `config` is `config.current.toJson()`.

- [ ] **Step 4: Run tests**
  Run: `/c/flutter/bin/flutter test test/services/backup/ test/services/update_service_test.dart test/modules/alarm_clock/`
  Expected: PASS.

- [ ] **Step 5: Commit** — `feat(backup): build and validate config backups`

### Task 2: Session-only gate and restore body cap in LocalApiServer

**Files:**
- Modify: `lib/services/local_api_server.dart` (plugin dispatch ~:222-256, `_readJsonBody` ~:354)
- Test: `test/services/local_api_server_plugin_bridge_test.dart`

**Interfaces:**
- Produces: plugin paths `/api/plugin/hearth.system/backup` and `/api/plugin/hearth.system/restore` require `_checkSession` (401 JSON `{'error':'unauthorized'}` otherwise, Bearer ignored). Restore path body cap `4 * 1024 * 1024`.

- [ ] **Step 1: Write the failing tests** (bespoke plugin with `id => 'hearth.system'` registering `GET backup`, `POST restore` that echo `{'bytes': jsonEncode(req.body).length}`; a session obtained via `POST /auth/pin` with `server.webPin` as in `local_api_server_test.dart:125-130`)
  - `backup refuses a bearer-only request` → 401.
  - `backup accepts a PIN session` → 200.
  - `restore accepts a 200 KB body with a session` → 200.
  - `other plugin routes still cap at 64 KB` — 200 KB POST to another bespoke route with Bearer → 413.
- [ ] **Step 2: Run to verify failure** — `/c/flutter/bin/flutter test test/services/local_api_server_plugin_bridge_test.dart` → FAIL.
- [ ] **Step 3: Implement** — a `static const _sessionOnlyPluginPaths = {...}` beside the capture exception; `_readJsonBody(HttpRequest request, {int maxSize = _maxBodySize})`. Comment why: the apiKey is handed to HA `rest_command`s.
- [ ] **Step 4: Run** — same file plus `test/services/local_api_server_test.dart` → PASS.
- [ ] **Step 5: Commit** — `feat(api): gate backup routes on the PIN session`

### Task 3: AppRestarter, System plugin routes and portal UI

**Files:**
- Create: `lib/services/app_restarter.dart`
- Modify: `lib/services/backup/backup_service.dart` (add `backupServiceProvider`)
- Modify: `lib/plugins/system/system_plugin.dart` (`registerHttpRoutes`, `_backupHtml`, class doc)
- Test: `test/plugins/system/system_plugin_routes_test.dart` (new; kept apart from widget tests, per the note in `display_plugin_routes_test.dart`)
- Modify: `test/plugins/system/system_plugin_test.dart` (HTML contains the section)
- Docs: `docs/wiki/The-Web-Portal.md` — a "Backup & Restore" section (what's in the file, that it holds every password, the newer-version rule, the restart and new PIN).

**Interfaces:**
- Consumes: Task 1 `BackupService`, `BackupRejected`, `SendspinRestore`; Task 2 gate.
- Produces:
  - `class AppRestarter { AppRestarter({bool? android, bool? linux, DisplayRotationService? linuxRestart, MethodChannel? channel}); bool get canRestart; Future<bool> restart(); }` — Linux: `DisplayRotationService.restart()`; Android: `invokeMethod<bool>('restartApp')` on `com.hearth/app_update` (Task 4 implements it); otherwise `canRestart == false`, `restart()` returns false.
  - `final appRestarterProvider = Provider<AppRestarter>(...)` (Linux path reads `displayRotationServiceProvider`).
  - `final backupServiceProvider = Provider<BackupService>(...)` — real notifier, `alarmServiceProvider`, `sendspinNative ? AndroidSendspinSecretFiles() : FileSendspinSecretFiles()`, `Platform.operatingSystem`, `readInstalledVersion`.
  - Routes `GET /api/plugin/hearth.system/backup` (200, `Content-Disposition: attachment; filename="<fileName()>"`, JSON indented 2 spaces) and `POST /api/plugin/hearth.system/restore` (400 `{'error': message}` on `BackupRejected`; else 200 `{'status': 'restarting' | 'restartManually', 'sendspin': '<enum name>'}`, then the restart 500 ms after the response closes).

- [ ] **Step 1: Write the failing tests** (override `backupServiceProvider` with a service over a memory notifier + fake Sendspin, `appRestarterProvider` with a fake recording calls; session via PIN)
  - `backup downloads an attachment` — 200, header `content-disposition` contains `attachment; filename="hearth-backup-`, body decodes with `hearthBackup == 1`.
  - `restore rejects an invalid file` — body `{'hearthBackup': 9}` → 400, `error == 'This backup needs a newer version of Hearth.'`; restarter not called.
  - `restore answers before restarting` — a valid backup whose `config.apiKey` differs → 200 `{'status':'restarting','sendspin':'restored'}` received; restarter called exactly once after (Review Focus 4).
  - `restore reports a manual restart where the kiosk cannot restart` — fake `canRestart == false` → `status: 'restartManually'`, restarter not called.
  - `AppRestarter` unit tests: Linux runs `sudo -n systemctl restart hearth.service` via an injected `DisplayRotationService`; Android invokes `restartApp` on a mocked channel; Windows `canRestart == false`.
  - `system_plugin_test`: `buildSettingsHtml` contains `id="backup-download"`, `id="restore-file"` and the text `contains every password and token`.
- [ ] **Step 2: Run to verify failure** — `/c/flutter/bin/flutter test test/plugins/system/ test/services/app_restarter_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Portal HTML, styled like `_updateButtonsHtml`:
  - `<a id="backup-download" href="/api/plugin/hearth.system/backup">Download backup</a>` (button-styled; the session cookie authenticates it).
  - Hint: `The file contains every password and token Hearth uses. Keep it somewhere safe.`
  - `<input type="file" id="restore-file" accept=".json,application/json">` + `Restore` button. On click: `confirm('This replaces all settings on this kiosk and restarts it. Continue?')`, `file.text()`, `fetch(PREFIX + '/restore', {method:'POST', headers:{'Content-Type':'application/json'}, body})` with `credentials: 'same-origin'`. Use the `error` for 400. On `restarting`, show `Restored — restarting…`, wait until a `fetch('/')` fails and then succeeds (poll every 2 s, give up after 120 s with `The kiosk did not come back. Check it and restart Hearth by hand.`), then `location.reload()`. On `restartManually`, show `Restored. Restart Hearth to finish.` Append ` Sendspin pairing was not restored (backup is from another platform).` when `sendspin == 'skipped'`.
- [ ] **Step 4: Run** — `/c/flutter/bin/flutter test test/plugins/ test/services/app_restarter_test.dart` → PASS (web parity guard included).
- [ ] **Step 5: Commit** — `feat(system): back up and restore from the web portal`

### Task 4: Android — Sendspin secrets over the channel and self-restart

**Files:**
- Create: `lib/services/backup/android_sendspin_secret_files.dart` (or in `sendspin_secret_files.dart`)
- Modify: `android/app/src/main/kotlin/com/hearth/hearth/sendspin/SendspinChannel.kt` (`exportSecrets`, `importSecrets`)
- Modify: `android/app/src/main/kotlin/com/hearth/hearth/sendspin/SendspinSecrets.kt` (companion `exportFiles(context): Map<String, String>` / `importFiles(context, Map<String, String>)` over `identity`, `pairing_psk`, `trust.json`, base64 `NO_WRAP`, AtomicFile, `.pre-restore` copy of each replaced file; must not go through the lazy singleton, which mints)
- Create: `android/app/src/main/kotlin/com/hearth/hearth/RestartActivity.kt`
- Modify: `android/app/src/main/kotlin/com/hearth/hearth/AppUpdateChannel.kt` (`restartApp`)
- Modify: `android/app/src/main/AndroidManifest.xml` (`RestartActivity`, `android:process=":restart"`, not exported, translucent no-display theme)
- Docs: `docs/specs/2026-10-13-android-apk-requirements.md` — note backup/restore and that the restart is not yet checked on the tablet.
- Test: `test/services/backup/android_sendspin_secret_files_test.dart`

**Interfaces:**
- Produces: `class AndroidSendspinSecretFiles implements SendspinSecretFiles { AndroidSendspinSecretFiles({MethodChannel? methods}); }` calling `exportSecrets` (returns `Map<String,String>`, null → `{}`) and `importSecrets` (argument the map) on `com.hearth/sendspin`. Native `restartApp` returns `true`, then: start `RestartActivity` with the launch intent as an extra, `Process.killProcess(myPid())`; `RestartActivity.onCreate` starts the launch intent with `NEW_TASK | CLEAR_TASK`, finishes, kills its own process.

- [ ] **Step 1: Write the failing Dart test** — mocked `MethodChannel` via `TestDefaultBinaryMessengerBinding`: `read()` returns the native map; `write(m)` sends `importSecrets` with `m`; a null native reply reads as `{}`.
- [ ] **Step 2: Run** — `/c/flutter/bin/flutter test test/services/backup/android_sendspin_secret_files_test.dart` → FAIL.
- [ ] **Step 3: Implement Dart + Kotlin** as above (Kotlin file I/O on `Dispatchers.IO`, like `pairingInfo`).
- [ ] **Step 4: Verify** — Dart test PASS; `/c/flutter/bin/flutter build apk --debug` succeeds.
- [ ] **Step 5: Commit** — `feat(android): restore Sendspin secrets and relaunch after a restore`

### Task 5: Whole-branch verification

- [ ] `/c/flutter/bin/flutter analyze` — no issues.
- [ ] `/c/flutter/bin/flutter test` — all pass.
- [ ] Desktop smoke: `flutter run -d windows`, open `http://localhost:8090`, enter PIN, download a backup, change a setting, restore → `Restored. Restart Hearth to finish.` and the setting reverted live.
- [ ] Hardware (owner): Pi and Apolosign restore — same Sendspin player in MA, same MQTT device and satellite in HA, timezone/rotation applied, `HearthAudioService` back on Android.
