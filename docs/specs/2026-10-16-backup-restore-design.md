# Backup & Restore — design

Status: approved 2026-10-16. Plan: `docs/plans/2026-10-16-backup-restore.md`.

## Why

A kiosk's SD card dies (or the tablet is wiped). Today the owner reflashes,
runs setup, and re-enters every server, token, list, calendar, webview,
person and alarm by hand — and Music Assistant, Home Assistant, Plex and DLNA
then see a brand-new device. Backup & Restore makes that recovery one file:
download a backup while the kiosk is healthy, restore it onto the rebuilt
kiosk, and the kiosk comes back as **the same device with the same settings**.

## Goals

- Export every piece of configuration the kiosk owns into one downloadable
  file, from the `:8090` web portal.
- Restore that file onto the same kiosk after a rebuild, so that every
  setting takes effect — including the ones read only at startup — and every
  integration recognises the kiosk as the same device.
- Work on the Pi, on Android, and (minimally) on the Windows dev build.

## Non-goals (this pass)

- **Cloning** a setup onto a second kiosk. A restore keeps the device's
  identity fields; restoring onto a different kiosk will make the two collide
  in HA/Plex/DLNA/MQTT/Sendspin. That is accepted for now and will be designed
  separately.
- **Encryption.** The file is plain JSON and contains every secret. A
  password-protected format is a later pass.
- **On-device UI.** No Backup/Restore buttons on the kiosk screen; the portal
  only. (The Pi has no file picker or downloads folder.)
- Wi-Fi profiles (owned by NetworkManager on the Pi, and you need Wi-Fi to
  reach the portal anyway), the Immich photo cache, captures, timers (not
  persisted), the in-memory portal PIN and session tokens.
- Cross-platform restore of Sendspin secrets (see below).

## Anti-goals

- A restore that half-applies. A rejected file must change nothing.
- A restore that silently loses settings that only apply at startup
  (timezone, Pi rotation, MQTT client id).
- Pretty-printed `hub_config.json` — `scripts/hearth-launch.sh` and
  `scripts/hearth-updater.sh` grep the file and assume Flutter's compact
  `jsonEncode` output.

## What the kiosk persists today (recon, 2026-10-16)

All under `getApplicationSupportDirectory()` (Pi:
`/home/hearth/.local/share/com.hearth.hearth/`, Android: `filesDir`):

| State | Where | In backup? |
|---|---|---|
| `hub_config.json` | `HubConfigNotifier` (`lib/config/hub_config.dart`) | **Yes**, raw, including all secrets and identity fields |
| `alarms.json` | `AlarmService` (`lib/modules/alarm_clock/alarm_service.dart`) | **Yes** |
| Sendspin identity + pairing (Pi/desktop): `sendspin_identity.key` (raw bytes), `sendspin_pairing.json` | `lib/services/sendspin/sendspin_stores.dart` | **Yes**, same platform only |
| Sendspin identity + pairing (Android): `filesDir/sendspin/{identity,pairing_psk,trust.json}` | `SendspinSecrets.kt` (AtomicFile, base64url / `PskRecordCodec`) | **Yes**, same platform only |
| `photo_cache/`, `captures/` | Immich, CaptureService | No |

The Sendspin key matters for "same device": its public half is the Sendspin
`client_id`, and losing it makes Music Assistant see a new player (groups and
player settings in MA are lost). Its own doc comment says it is kept out of
`hub_config.json` so the portal never exposes it; the backup deliberately
overrides that, with a warning in the UI, because the owner accepted a
plaintext backup for this pass.

## Decisions

### Surface

A **Backup & Restore** group in the System plugin's portal HTML
(`lib/plugins/system/system_plugin.dart`, `buildSettingsHtml`), with:

- **Download backup** — saves the file to the browser.
- A one-line warning beside it: the file contains your passwords and tokens;
  store it somewhere safe.
- **Restore from file** — a file input; the browser reads the file and POSTs
  it. Confirm dialog before sending ("This replaces all settings on this
  kiosk and restarts it.").
- A status line for progress and errors.

Routes are plugin routes on the System plugin (`registerHttpRoutes`, served
under `/api/plugin/hearth.system/*`).

**Both routes require a PIN-authenticated portal session (the
`hearth_session` cookie); the Bearer `apiKey` alone is refused** (owner's
decision, 2026-10-16). The `apiKey` is handed to Home Assistant
`rest_command`s per the wiki (`docs/wiki/Notifications.md`,
`docs/wiki/Display-&-Night-Mode.md`), which is why `GET /api/config` redacts
secrets and `_webReadOnlyConfigKeys` protects the identity fields. A
Bearer-reachable backup would leak every secret and the Sendspin key to any
HA automation, and a Bearer-reachable restore would bypass the identity
protection. Today plugin dispatch in `LocalApiServer` is Bearer-only with one
hard-coded exception (`hearth.capture/file`, cookie *or* Bearer); these two
routes need a stricter gate — session required — which the builder adds in
`LocalApiServer` (or as a router-level option). Because the cookie is
`SameSite=Strict` and `OPTIONS` is refused, a cross-site page cannot drive
the restore.

### File format

One JSON object, e.g. `hearth-backup-<device-name>-2026-10-16.json`:

```json
{
  "hearthBackup": 1,
  "createdAt": "2026-10-16T14:02:11Z",
  "hearthVersion": "1.22.0",
  "platform": "linux",
  "config": { "...": "the parsed hub_config.json, verbatim" },
  "alarms": [ "...alarms.json list, verbatim" ],
  "sendspin": { "platform": "linux", "files": { "<name>": "<base64 of file bytes>" } }
}
```

- `hearthBackup` is the format version. A restore rejects a version newer
  than the build understands.
- `hearthVersion` is the app version that made the backup. **A restore
  refuses a backup from a newer Hearth than the running build** (owner's
  decision, 2026-10-16), with "This backup is from Hearth X; update this
  kiosk to X or later first." Reason: `HubConfig.fromJson` drops unknown
  keys and every `HubConfigNotifier.update` rewrites the file from
  `toJson()`, so a newer backup's extra settings would be lost silently on
  the next routine save. Same or older versions restore normally.
- `config` is the file's content as stored (not `HubConfig.toJson()` from
  memory is acceptable too — builder's call — but it must be unredacted; do
  **not** reuse `GET /api/config`, which redacts secrets).
- `sendspin.files` carries each platform's files opaquely (base64 of the
  bytes). Sendspin secrets are restored only when `sendspin.platform` matches
  the restoring kiosk's platform; otherwise they are skipped and the restore
  response says so. Missing files are simply absent (a kiosk that never ran
  Sendspin has none).
- `<device-name>` is a filename-safe form of a configured kiosk name (builder
  picks which field; falling back to `hearth`).

### Restore flow

1. **Validate before touching anything.** It must be an object with a
   supported `hearthBackup` and a `hearthVersion` no newer than the running
   build, and `config` must parse through
   `HubConfig.fromJson` without throwing; `alarms` must parse through
   `Alarm.fromJson`. Any failure → 400 with a readable message, nothing
   written.
2. **Keep the old files.** Copy each file about to be replaced to
   `<name>.pre-restore` (overwriting any earlier one). Manual undo only; no UI.
3. **Write.** `hub_config.json` as compact JSON (the same encoding
   `HubConfigNotifier.update` uses), `alarms.json`, and the Sendspin files
   (Pi/desktop: Dart writes them with `chmod 600` as the stores do; Android:
   a new method on the existing `com.hearth/sendspin` channel writes them
   with AtomicFile in `SendspinSecrets`' directory).
4. **Respond, then restart**, so every setting is read fresh — timezone, Pi
   rotation and the MQTT client id are only read at startup:
   - **Pi:** `sudo -n systemctl restart hearth.service`, as
     `DisplayRotationService.restart()` already does.
   - **Android:** the app restarts its own process (relaunch the activity,
     then exit). Nothing in the app does this today; the builder chooses the
     mechanism and must verify it on the tablet, including that
     `HearthAudioService` comes back.
   - **Windows / other desktop:** no restart; the response tells the user to
     restart Hearth to finish.
5. **Portal:** shows "Restored — restarting…", polls until the server
   answers again, then reloads. The kiosk shows a new PIN after the restart
   (the PIN and sessions are in memory), and the restored `apiKey` replaces
   the bearer token the page held — both are expected.

Older backups need no special code: `HubConfig.fromJson` already migrates
legacy fields on load.

### Body size

`LocalApiServer` caps JSON bodies at 64 KB (`_maxBodySize`). A full backup can
exceed that (webviews, people, calendars, trust records). The restore route
needs a higher cap — a few MB is ample — without raising it for every route.

## Left to the builder

- How the running app version is read and compared (semver, ignoring build
  metadata) for the newer-backup check.
- Route names and the exact HTML/JS, following the Display and People plugins'
  patterns (`hearth.action` in `web_assets.dart` for POSTs).
- Whether the config is captured from the file on disk or from the live
  `HubConfig` (both are unredacted; the file is closer to "verbatim").
- How the restore route reads a large body (a per-route limit, or reading
  `req.raw` itself).
- The Android self-restart mechanism.
- How to avoid racing a concurrent `HubConfigNotifier.update` or alarm save
  between write and restart (e.g. writing through the notifier, or accepting
  the tiny window before the process restarts).

## Testing

- Unit: backup → restore round-trip reproduces `hub_config.json`,
  `alarms.json` and Sendspin files byte-for-byte (Sendspin) / value-for-value
  (config, alarms), using temp directories.
- Unit: rejected inputs (not JSON, wrong shape, newer `hearthBackup`, newer
  `hearthVersion`, unparseable config) write nothing.
- Route: backup and restore refuse a Bearer-only request and accept a PIN
  session.
- Unit: a backup from another platform restores config + alarms and skips
  Sendspin.
- Plugin route tests alongside `test/plugins/system/system_plugin_test.dart`;
  the web parity guard must stay green.
- Hardware: restore on the Pi and on the Apolosign tablet; check MA still
  shows the same Sendspin player, HA the same MQTT device and voice
  satellite, and the timezone/rotation are applied.
