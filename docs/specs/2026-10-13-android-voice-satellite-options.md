# Android Voice Satellite — Options and Recommendation

**Date:** 2026-10-13
**Status:** Decision record, since revised: see [Decision update](#decision-update). Nothing here is implemented. No candidate was installed; the tablet's microphone was measured afterwards.
**Goal:** Decide how an Android Hearth tablet gets a voice satellite, by comparing four options against upstream source, and name the follow-up work.

Extends the "Voice satellite" row and follow-up #12 of `2026-10-13-android-apk-requirements.md`.

## How to read this

Every claim about an upstream project carries one of two labels:

- **verified** — read in the upstream source at the commit listed under [Sources read](#sources-read). The file is named inline.
- **assumed** — reasoned from that source, from Android platform documentation, or from a README, and not settled by code we read. Treat as a hypothesis.

No option was installed or exercised. Anything that depends on a real device is **assumed** and collected under [Open questions](#open-questions--needs-hardware).

## Sources read

| Short name | Repository | Commit | Committed |
|---|---|---|---|
| Ava | `brownard/Ava` | `2c76f51` (tag `v0.6.2`) | 2026-06-15 |
| VACA integration | `msp1974/ViewAssist_Companion_App` | `da1dbad` (tag `v0.13.5`) | 2026-10-10 |
| VACA app | `msp1974/ViewAssistCompanionApp` | `3c9517c` | 2026-10-10 |
| LVA | `OHF-Voice/linux-voice-assistant` | `b49fd8d` | 2026-09-29 |
| HA core | `home-assistant/core` (`components/esphome`, `components/assist_satellite`) | `0cc219c` | 2026-10-14 |
| aioesphomeapi | `esphome/aioesphomeapi` (46.10.0) | `49219c8` | 2026-10-11 |
| HA companion | `home-assistant/android` | `9b2b06a` | 2026-10-13 |

Paths below are relative to each repository root. Ava's `A/` stands for `app/src/main/java/com/example/ava/`.

## What Hearth needs from a satellite

Hearth never touches the microphone. `lib/services/voice_assistant_service.dart` mirrors one HA `assist_satellite.*` entity to drive the voice pill, and mutes through a sibling `switch` on the same HA device. Three things in that file decide how well an option fits:

1. **State.** It reacts to the entity states `idle`, `listening`, `processing`, `responding`. Those are exactly HA's `AssistSatelliteState` values (**verified**, HA core `assist_satellite/entity.py:40-53`), so any option that yields a real `assist_satellite` entity drives the pill unchanged.
2. **Mute.** `_resolveMuteEntity` takes the first `switch.` entity on the satellite's HA device whose entity ID contains `mute`.
3. **Which satellite is ours.** `_autoDetectByMac` looks for a registry entry with platform `esphome` and unique_id `<mac>-assist_satellite`, comparing lower-cased. `_readPiMacAddress` supplies the MAC from `/sys/class/net`, Linux only. Otherwise `config.voiceAssistantEntityId` pins an entity by hand, and failing that the first available satellite wins.

How HA builds that unique_id matters for point 3. The esphome integration creates the satellite entity whenever the device reports non-zero voice-assistant feature flags (**verified**, HA core `esphome/assist_satellite.py:138-141`), and its unique_id is the device-reported MAC string, unmodified, plus the entity key: `f"{device_info.mac_address}-{self.entity_description.key}"` with key `assist_satellite` (**verified**, `esphome/entity.py:672-674`, `esphome/assist_satellite.py:149-151`). So Hearth can match any ESPHome-protocol satellite if it can learn the MAC string that satellite reports. It does not have to be a hardware MAC.

HA accepts a plaintext, passwordless ESPHome device (**verified**: Noise is used only when the config entry holds a key, aioesphomeapi `connection.py:617-619`, HA core `esphome/__init__.py:101`), and discovers it from an `_esphomelib._tcp.local.` record with a mandatory `mac` TXT entry (**verified**, HA core `esphome/manifest.json:24`, `esphome/config_flow.py:343-351`).

## The baseline: LVA on the Pi

The parity target, all **verified** in LVA unless marked:

- Plaintext ESPHome API, no password, no encryption (`linux_voice_assistant/api_server.py:11`, `satellite.py:713`).
- Feature flags `VOICE_ASSISTANT | API_AUDIO | ANNOUNCE | START_CONVERSATION | TIMERS` (`satellite.py:86-96`).
- Reports the default-route interface's MAC from `getmac` and exits if there is none (`__main__.py:301-304`).
- Entities: a media player, a `Mute` switch (object_id `mute`), a `Thinking Sound` switch, wake/stop-word sensitivity numbers, mic gain, mic volume and a noise-suppression select (`satellite.py:113-314`).
- Announce with pre-announce sound, start-conversation and continue-conversation (`satellite.py:604-605`, `694-704`, `1016`).
- Timers: ring on `TIMER_FINISHED`, looped until the stop word or a wake word (`satellite.py:652-674`, `880-896`).
- Wake word: microWakeWord and openWakeWord; `okay_nabu` and `stop` are bundled; two active wake words; HA can push external microWakeWord models (`__main__.py:18-19`, `satellite.py:770`, `789-793`).
- No echo cancellation of its own. The docs delegate it to PulseAudio or PipeWire `module-echo-cancel` (`docs/enabling_aec.md:9-46`).
- 5,083 lines of Python in the package, about 4,300 without the LED/button peripheral API. This is the size reference for an in-app implementation.

## Comparison

| Axis | 1. Ava (companion app) | 2. In-app satellite | 3. VACA | 4. LVA under Termux |
|---|---|---|---|---|
| Transport to HA | ESPHome native API, plaintext, port 6053, core `esphome` integration (**verified**) | Same, by construction | Wyoming plus custom events, port 10800, needs the `vaca` custom integration (**verified**) | Same as the Pi, if it runs (**assumed**) |
| `assist_satellite` entity | Yes, from the feature flags (**verified** flags; HA creating the entity **assumed** until run) | Yes | Yes, subclass of HA's Wyoming satellite (**verified**) | Yes (**assumed**) |
| Voice pill unchanged | Yes | Yes | Yes (**assumed**: states come from the Wyoming base class, which we did not read) | Yes |
| Mute toggle unchanged | Yes: switch `Mute Microphone` (**verified** name; resulting entity ID **assumed**) | Yes, if the switch is named with `mute` | Yes: switch key `mute` (**verified**), but HA-side state is optimistic with no device feedback (**verified**) | Yes: switch `Mute` |
| Self-identification | Random MAC, persisted in Ava's private storage, also published in its mDNS TXT record (**verified**). Hearth reads the TXT record. | Hearth generates and stores the MAC itself; no lookup needed | unique_id is `<config entry id>-assist_satellite`, platform `vaca` (**verified**). MAC match can never work; pin by hand. | `getmac` must return a MAC or LVA exits (**verified**); Android withholds it (**assumed**) |
| Assistant role | Not declared, not needed (**verified**) | Optional; not needed | Not declared (**verified**) | Not possible |
| Wake word | microWakeWord on LiteRT, on device; `okay_nabu` is the default; 9 models plus user models; `stop` (**verified**) | microWakeWord via reused code; `okay_nabu` | openWakeWord and microWakeWord on device; `okay_nabu` and `stop` bundled (**verified**) | As the Pi (**assumed**) |
| Announce / start / continue conversation | All three (**verified**) | To be built | Announce and start-conversation (**verified**); continue-conversation is a device setting we could not trace (**assumed**) | As the Pi |
| Timers | Yes, ring until stop word or wake word (**verified**) | To be built | Yes, through the Wyoming handler (**verified**) | As the Pi |
| Echo handling | None of its own; selectable audio source and `MODE_IN_COMMUNICATION` (**verified**) | Ours to choose | App-side AGC and spectral noise suppression; no AEC found (**verified**) | PulseAudio module (**assumed**) |
| Start at boot | No boot receiver; `autoStart` only fires when its activity is opened (**verified**) | Hearth is the HOME app; starts with it | Boot receiver launches its own activity (**verified**) | Termux:Boot (**assumed**) |
| Fights Hearth for the screen | No: a foreground service plus a settings activity (**verified**) | No | Yes: declares `category.HOME`, shows over the lock screen, drives brightness and a WebView (**verified**) | No |
| Lock task / device owner | Second package to allow-list so its settings activity can open; its service running under lock task is **assumed** | Nothing extra | Second package that is itself a HOME activity and ships a device-admin receiver (**verified**) | Three extra packages |
| Doze | Holds a partial wake lock and a Wi-Fi lock; requests no battery exemption (**verified**). Not in play while Hearth keeps the screen on (**assumed**). | Same exposure as the rest of Hearth | Foreground service; keeps the screen on by default (**verified** defaults in the integration) | Termux wake lock (**assumed**) |
| Audio focus against Hearth media | Requests transient may-duck focus for speech and never yields its own (**verified**). Hearth requests no focus today, so media_kit ducking is **assumed** not to happen. | One process owns both; ducking is ours to write | Separate music, voice and alarm players with a `ducking_volume` setting (**verified** in the integration); interaction with Hearth **assumed** as Ava | None; mpv ducks only its own players (**verified** for LVA) |
| Install and update | Second APK from GitHub releases, updated by hand | One APK | Second APK plus a HACS integration, version-locked to each other (**verified**) | Termux, Termux:API, Termux:Boot, a Python build chain |
| Licence | Apache-2.0 (**verified**) | Hearth is MIT; reused code stays Apache-2.0 | Apache-2.0, both repos (**verified**) | Apache-2.0 |
| Maintenance risk | One maintainer, self-described experimental, last commit 2026-06-15, 9 releases between 2025-12-14 and 2026-06-15 (**verified** via the GitHub API) | Ours forever | One maintainer, active, 5 releases between 2026-08-29 and 2026-10-10, coupled to HA Wyoming internals (**verified**) | Unsupported platform |
| Hearth-side work | Small | Large | Small, but the result is not usable | None, but the result is not usable |

## 1. Ava

An Android app that is, in effect, LVA for Android: an ESPHome-protocol device server, a microWakeWord detector and a Media3 player inside one foreground service.

**Protocol and features** — all **verified**:

- Feature flags are identical to LVA's: `VOICE_ASSISTANT | API_AUDIO | TIMERS | ANNOUNCE | START_CONVERSATION` (`A/services/DeviceBuilder.kt:48-56`).
- Plaintext only. The frame codec rejects the encrypted indicator ("Only plain text is supported for now", `esphomeproto/.../AsynchronousCodedChannel.kt:44`). There is no password handling. This is the same exposure LVA has on the Pi.
- One client at a time: a new connection closes the previous one (`A/server/Server.kt:90`).
- Handles the announce request including pre-announce media and `start_conversation`, continue-conversation, all four timer events, and the wake-word configuration messages with two active wake words (`A/esphome/voiceassistant/VoiceAssistant.kt:111-176`, `288-290`).
- Entity states are pushed when HA sends `SubscribeHomeAssistantStatesRequest` (`A/esphome/EspHomeDevice.kt:153`). HA sends it on connect (**verified**, HA core `esphome/manager.py:788`).
- Gaps against LVA: external wake words pushed from HA are ignored, and there is no thinking-sound switch and no sensitivity or mic-gain entities. Ava adds an `Enable Wake Sound` and a `Repeat Timer Sound` switch instead (`DeviceBuilder.kt:63-92`).

**Identity** — the part that decides Hearth's work:

- Ava reports `name` and `mac_address` and nothing else: no friendly name, model or manufacturer (**verified**, `DeviceBuilder.kt:48-56`).
- The MAC is six random bytes, formatted upper-case with colons, generated on first service start and stored in `voice_satellite_settings.json` in Ava's private DataStore. The source comment says why: the real MAC "is discouraged/not available" on Android (**verified**, `A/settings/VoiceSatelliteSettings.kt:17-23`, `84-87`; `A/utils/NetworkUtils.kt:14-21`).
- It survives reboots and app updates. Clearing Ava's data or reinstalling produces a new MAC (**verified** from the code path). HA then refuses the device at the old address and raises a `device_conflict` repair when the name is unchanged (**verified**, HA core `esphome/manager.py:668-716`).
- The same string is published as the `mac` TXT record of an `_esphomelib._tcp` service registered through Android `NsdManager` (**verified**, `A/nsd/VoiceSatelliteNsd.kt:15-22`).
- The device name defaults to `Android Voice Assistant` and is editable in the app (**verified**, `VoiceSatelliteSettings.kt:27`).

So the replacement for `_readPiMacAddress()` is: browse `_esphomelib._tcp`, keep the record whose address is one of the tablet's own, read its `mac` TXT value, and feed that to the existing `<mac>-assist_satellite` match. `bonsoir` is already in the build. Hearth already lower-cases both sides, so Ava's upper-case form matches. Whether Android's NSD returns the device's own registrations to a browser on the same device is **assumed**; the fallback is the existing manual pin, which works today.

**Mute.** The switch is named `Mute Microphone`, object_id `mute_microphone`, and it is the only one of Ava's three switches with `mute` in its name (**verified**, `DeviceBuilder.kt:74-79`). It stops capture outright (**verified**, `A/esphome/voiceassistant/VoiceInput.kt:105-106`). That the HA entity ID ends up containing `mute` follows from HA's naming rules (**assumed**).

**Android behaviour** — all **verified** in `app/src/main/AndroidManifest.xml` unless marked:

- One non-exported foreground service, type `microphone|mediaPlayback`. Permissions: `RECORD_AUDIO`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, `MODIFY_AUDIO_SETTINGS`, `WAKE_LOCK`.
- **No boot receiver and no `RECEIVE_BOOT_COMPLETED`.** The `autoStart` setting defaults to off and only runs when Ava's `MainActivity` is opened with permissions granted (`A/ui/services/ServiceViewModel.kt:73-81`). After a reboot something has to open that activity. This is the largest practical gap.
- Holds a partial wake lock and a Wi-Fi lock for the life of the service (`A/wakelocks/WifiWakeLock.kt:22-37`). No battery-optimisation exemption is requested.
- No `VoiceInteractionService`, no assistant intent filters.
- `applicationId` is the placeholder `com.example.ava`; minSdk 26, targetSdk 36 (`app/build.gradle.kts:12-18`). Hearth's minSdk is 29, so every tablet Hearth supports can run it.
- Audio out is Media3 ExoPlayer. Speech uses `USAGE_ASSISTANT` and requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` at wake, so other apps are asked to duck; Ava's own focus listener is empty, so it never yields (`A/services/DeviceBuilder.kt:116-126`, `A/esphome/android/mediaplayer/AudioFocusRegistration.kt:20-24`). Whether libmpv inside Hearth honours that duck request is **assumed** not to, since nothing in Hearth requests audio focus today.
- Capture is `AudioRecord` at 16 kHz mono from `VOICE_RECOGNITION` by default, with the source user-selectable (`A/esphome/android/microphone/AudioRecordMicrophone.kt:17-21`).
- A Tasker plugin exposes "wake satellite", "stop ringing" and an activity condition. It exposes no mute control and no raw state, so it is no substitute for the HA entity (`A/tasker/`, `docs/TASKER.md`).

**Kiosk fit.** Ava never takes the screen on its own. Under lock task it needs its package allow-listed so its activity can be opened for setup; a running foreground service of another package is **assumed** to keep running under lock task. Doze does not apply while Hearth keeps the screen on.

**Hearth-side work:**

| Task | Size |
|---|---|
| mDNS self-match: find the local `_esphomelib._tcp` record, read `mac`, feed the existing matcher; keep the manual pin as fallback | Small |
| Boot start: either a boot receiver contributed upstream to Ava, or Hearth opens Ava's activity at startup and returns to the front. Needs a `<queries>` entry for the package. | Small, hardware-dependent |
| Voice plugin: an Android setup note in both the on-device panel and the `:8090` portal (install Ava, set its name, enable autostart) | Small |
| Add the Ava package to the lock-task allow-list when follow-up #13 lands | Trivial |
| Hardware trial of everything marked **assumed** in this section | Small |

## 2. In-app satellite

An ESPHome native-API voice-assistant server inside the Hearth APK. Nothing exists; this section sizes it.

**What has to exist:**

| Piece | Notes | Size |
|---|---|---|
| Protocol server | Plaintext framing, hello / ping / disconnect, device info, entity listing and state, and the eleven voice-assistant messages (ids 89-92, 106, 115, 119-123; **verified**, aioesphomeapi `api.proto:2173-2341`). HA blocks up to 5 s on the configuration request and up to 5 min on announce-finished (**verified**, HA core `esphome/assist_satellite.py:116-117`, `310-313`, `515`), so both replies are mandatory once `ANNOUNCE` is advertised. | Medium-large |
| Pipeline state machine | Wake, stream, the ten pipeline events LVA acts on, continue-conversation, announce, timers | Medium |
| Wake word | microWakeWord needs a native feature frontend and a TFLite runtime, built per ABI with the NDK | Medium |
| Capture | `RECORD_AUDIO`, a runtime permission prompt, and a `microphone` foreground service if listening must survive Hearth leaving the foreground | Medium |
| Playback | TTS and announcements by URL, timer ring, wake sound, with audio focus | Medium |
| Discovery | `_esphomelib._tcp` with a `mac` TXT record through `bonsoir` | Small |
| Settings | Wake word choice, sensitivity, audio source, in both plugin surfaces | Small-medium |

Taken together this is several tasks and comparable in scope to the Sendspin port (follow-up #10), with a longer tail: we would own protocol drift. The proto already notes that the feature flags in device info are "Superseded by DeviceCapabilitiesResponse.voice_assistant as of API 1.15" (**verified**, aioesphomeapi `api.proto:314-315`). HA at the commit we read still takes them from device info, and LVA and Ava both report API 1.10, so the change is not live yet, but it is the kind of upkeep this option signs us up for.

**Reuse.** The realistic build is Kotlin, lifted from Apache-2.0 code, with a thin platform channel to Dart:

- Ava's `:esphomeproto` module is a pure-JVM library holding `api.proto`, the plaintext codec and the message table, with no Android dependency (**verified**, `esphomeproto/build.gradle.kts`). Its message table is maintained by hand (**verified**, `MessageParsers.kt:145-148`).
- Ava's `:microfeatures` module is a self-contained JNI library for the wake-word frontend (**verified**).
- Ava's device behaviour lives in `:app`, written against interfaces with JVM unit tests, but it is not a separable module: its core files import Media3 and Ava's own settings types (**verified**, `A/esphome/voiceassistant/VoicePipeline.kt:3-4`, `VoiceInput.kt:5`). Lifting it means a fork we keep in sync.
- The HA companion ships a second, independent microWakeWord implementation on TFLite Micro as its own Gradle module, also Apache-2.0, with `okay_nabu` bundled (**verified**, `microwakeword/src/main/cpp/CMakeLists.txt`, `app/src/main/assets/wakeword/`).

Apache-2.0 code can ship inside MIT-licensed Hearth provided the licence text, notices and file headers are kept (**assumed**; not legal advice). A pure-Dart rewrite of the protocol is possible but reuses nothing and still needs native code for the wake word.

**What it buys over a companion app:**

- One install and one update path.
- Start at boot for free, since Hearth is the HOME app.
- Self-identification with no lookup: Hearth picks the MAC.
- State straight from the pipeline, without the HA round trip the pill uses today.
- One process owning audio, so ducking media_kit and a future Android Sendspin is a function call, and an echo reference is available if we ever do AEC.

## 3. View Assist Companion App

Two repositories: an HA custom integration and an Android app. The README of the first does not link the second; we found the app source by listing the author's repositories.

**HA side** — all **verified** in `custom_components/vaca/`:

- Transport is Wyoming with custom event types. HA connects out to the tablet; discovery is `_vaca._tcp.local.` (`manifest.json:8-30`, `client.py:9`, `custom.py:30-36`). The app's default port is 10800 (app `settings/Settings.kt:416`).
- The satellite entity subclasses HA's `WyomingAssistSatellite` and supports announce and start-conversation (`assist_satellite.py:22`, `68-79`).
- unique_id is `<config entry id>-assist_satellite`: `satellite_id = entry.entry_id` (`__init__.py:91-92`, `entity.py:21`). Hearth's auto-detect filters on platform `esphome`, so it never matches. Removing and re-adding the integration changes the identity.
- A `mute` switch exists on the same device (`switch.py:150-153`), so Hearth's mute lookup resolves. Its state is restored and optimistic, pushed to the app as a setting with no confirmation back (`switch.py:78-106`), so the toggle can drift from the device.
- It creates about forty further entities across eight platforms, most of them for the display: `screen_on`, `screen_brightness`, `screen_always_on`, `screen_saver`, `dark_mode`, `zoom_level`, a browser path sensor (`switch.py:37-62`, `number.py:40-62`, `sensor.py:46-62`). Each switch re-pushes its stored value to the tablet when HA starts.
- It does not hard-require the View Assist integration; it looks one up optionally to pick a dashboard (`custom.py:140-163`). It does tell the tablet HA's URL and dashboard (`assist_satellite.py:149-158`).
- Minimum HA 2025.11.0 (`hacs.json`), and it pins the app version it accepts: `MIN_APK_VERSION = "0.13.5"` (`const.py:4`).

**App side** — all **verified** in the app repository:

- `MainActivity` declares `category.HOME` alongside `LAUNCHER`, with `showWhenLocked` (`app/src/main/AndroidManifest.xml`). It is a rival home app.
- Permissions include `DISABLE_KEYGUARD`, `TURN_SCREEN_ON`, `WRITE_SETTINGS`, `CAMERA`, `QUERY_ALL_PACKAGES` and `REQUEST_INSTALL_PACKAGES`; it ships a device-admin receiver.
- The boot receiver starts `MainActivity`, not the service (`broadcasts/BootUpReceiver.kt`), and the service is only ever started from that activity (`MainActivity.kt:558`). When the OS restarts the service after a crash it relaunches the activity (`service/ForegroundService.kt:76-80`).
- We found no headless or audio-only setting in either repository.
- Wake word: `okay_nabu` and `stop` ship as microWakeWord models, `ok_nabu` as openWakeWord (`app/src/main/assets/`).

**Verdict: ruled out.** It yields the entity and the mute switch, so the pill would work, but the app is built to own the display, and Hearth is the display. It also adds a custom integration that is coupled to HA's Wyoming internals: the repository carries copies of HA modules "to fix issue in 2026.9.0 where the models were moved" (**verified**, `models.py:3-4`).

## 4. LVA under Termux

**Verified** in LVA:

- Supported platforms are `linux/amd64` and `linux/aarch64` (`README.md:34`, `.github/workflows/docker-build-release.yml:60`). Android, Termux and bionic are not mentioned anywhere in the repository.
- Microphone capture goes through the `soundcard` library and requires a PulseAudio connection (`__main__.py:15`, `docs/install_audioserver.md:3`).
- Playback needs system libmpv (`Dockerfile:24`).
- Part of the wake-word stack compiles from source (`Dockerfile:23`).
- It exits at startup when `getmac` returns no MAC for the default-route interface (`__main__.py:301-304`).

**Assumed**, from Android platform behaviour:

- Termux can run a PulseAudio daemon with an OpenSL ES source for the microphone, but that path is community-maintained, and capture from a background Termux session is subject to the same foreground-service rules as any app.
- The Python wheels LVA depends on are published for glibc Linux, not bionic, so `numpy`, the wake-word packages and `webrtc-noise-gain` would build from source on the tablet.
- Android restricts interface MAC addresses for apps, so the `getmac` call is likely to fail or return a placeholder, which is fatal.
- Android 12+ kills long-running child processes of apps (the phantom process limit), which is how Termux runs everything.

**Verdict: ruled out.** Every layer LVA stands on is either missing or unsupported, and the result would be three sideloaded apps plus a build chain to reproduce what Ava already is.

## The Android assistant role

This is an axis, not a requirement. The reference holder is the HA companion app, which is the known third-party implementation.

**What the companion does** — all **verified** in `home-assistant/android`:

- It holds the role through a `VoiceInteractionService` with `supportsAssist` and `supportsLaunchVoiceAssistFromKeyguard` (`app/src/main/res/xml/voice_interaction_service.xml`, `app/src/main/AndroidManifest.xml:589-619`), and checks it with `RoleManager.ROLE_ASSISTANT` (`settings/assist/DefaultAssistantManager.kt:64-67`).
- Its own summary of what the role provides: "Assistant button presses", "Lock screen assistant gestures", "Voice commands from Bluetooth devices" (`assist/service/AssistVoiceInteractionService.kt:42-54`).
- Wake word runs inside that service as a `microphone` foreground service, using microWakeWord with `okay_nabu` bundled (`AssistVoiceInteractionService.kt:251-261`, `app/src/main/assets/wakeword/`).
- Wake word is tied to the role: the settings screen switches it off whenever the app is not the default assistant (`settings/assist/AssistSettingsViewModel.kt:56-61`).
- Capture uses the ordinary `AudioSource.MIC` through `AudioRecord` (`common/.../util/VoiceAudioRecorder.kt:39`). There is no hotword-detector API in the app.
- The app source contains no reference to `assist_satellite`. A detected wake word opens the app's own Assist session UI.

**What that means for a wall kiosk:**

- The role's concrete benefits are entry points: the assist gesture, the lock-screen launch, a Bluetooth headset button. A wall tablet that Hearth holds in the foreground uses none of them.
- A role-held `VoiceInteractionService` is kept bound by the system, which is a stronger keep-alive than a foreground service. On a kiosk that keeps its screen on and its app foreground, a `microphone` foreground service is **assumed** to be enough.
- The role does not unlock the low-power DSP hotword path. The always-on hotword APIs are gated on signature or privileged permissions that sideloaded apps cannot hold (**assumed**, from Android platform documentation). The companion's own implementation is consistent with that: it burns CPU on `AudioSource.MIC` like everyone else.
- The role does give microphone priority. Android 10+ lets the assistant-role holder capture concurrently with an ordinary app (**assumed**, from `developer.android.com/media/platform/sharing-audio-input`, which the companion cites at `AssistVoiceInteractionService.kt:240`). For an option that does not hold the role, the stock assistant keeps it, and its hotword may contend for the microphone.

**Per option:**

| Option | Can hold the role | Stock assistant |
|---|---|---|
| Ava | No, as shipped (**verified**: no service or filter declared) | Still the role holder. Set the default assistant to "None" or disable the package on a kiosk (**assumed**). |
| In-app | Yes, if we add a `VoiceInteractionService`; the user must grant it in system settings. Nothing in the design needs it. | Displaced only if we take the role; otherwise as Ava. |
| VACA | No (**verified**) | As Ava |
| Termux | No | As Ava |
| HA companion (reference) | Yes (**verified**) | Displaced when the user selects it |

The companion as a satellite, for completeness: it would give wake word and the role, but no `assist_satellite` entity in its own source (**verified**), so the voice pill, the mute toggle and the ducker would all need new plumbing, and a detected wake word would raise its Assist UI over Hearth. That is why it is not a candidate.

## Decision update

Later the same day we chose the runner-up: **the in-app satellite**. Its design is `2026-10-13-android-native-voice-satellite-design.md`. The comparison above stands; the recommendation and follow-up tasks below are kept as the record of the first call and are superseded.

What changed:

- **Boot start has no clean answer for Ava.** Its service is not exported and only its activity starts it (**verified** above). Android 14+ wants the app visible when a `microphone` foreground service starts, and Android 15 blocks starting one from `BOOT_COMPLETED` (**assumed**, from platform documentation), so even an upstream boot receiver would not do. This is the concern behind the first flip condition below, reached by reasoning from the platform rules and not by the hardware trial that condition names.
- **We want voice timers in Hearth's timer UI.** Home Assistant delivers timer events to the satellite device (**verified**, HA core `esphome/assist_satellite.py:291-299`, `643-659`) and we found no entity exposing them (**assumed**), so a companion app would need a fork of Ava and a cross-app hand-off.
- **The tablet's own speaker stays in its microphone.** Recordings on the Apolosign tablet show one vendor-processed microphone channel that takes the same path for every `AudioSource`, a test signal's echo about 38 dB above the noise floor despite the vendor echo canceller being on, and no attachable platform echo canceller (**verified**; details and limits in the design spec). Voice has to mute what Hearth is playing at the moment of wake, which needs one process to own both. This is the third flip condition, met before Sendspin lands.

Two open questions below are now partly answered for this tablet: the `AudioSource` makes no difference, and echo cancellation cannot be relied on. Wake-word accuracy is still untested.

## Original recommendation (superseded)

**Use Ava as a companion app.**

- It is the same protocol, the same HA integration, the same feature flags and the same default wake word as the Pi's LVA, so Hearth's voice pill and mute toggle work without changing `VoiceAssistantService`'s state or mute logic.
- The one thing Hearth cannot do today, recognising its own satellite, has a small answer that Ava's source already supports: the `mac` TXT record.
- It does not compete for the screen and does not need the assistant role.
- The Hearth-side work is four small tasks. The in-app alternative is several medium ones plus permanent protocol upkeep.

What we accept: a second APK updated by hand, a single maintainer on a project that calls itself experimental and has been quiet for four months, an unauthenticated port 6053 (the same as the Pi), no echo cancellation, and a boot-start gap we have to close ourselves.

**Runner-up: the in-app satellite**, built in Kotlin on Ava's `:esphomeproto` and `:microfeatures` modules. We switch to it if any of these holds:

- The hardware trial shows Ava's service cannot be started reliably at boot, or does not survive alongside Hearth under lock task.
- Ava stops tracking the protocol: HA drops the device-info feature flags in favour of API 1.15 capabilities and Ava does not follow.
- Sendspin lands on Android and voice has to duck or echo-cancel against audio that Hearth itself is playing, which needs one process to own both.

Starting with Ava costs nothing toward that switch: the mDNS self-match is discarded, and everything else in Hearth stays.

## Follow-up tasks (superseded)

Replaced by the phases in the design spec. Kept for the record. In order; each was its own task.

1. **Hardware trial of Ava** (small) — install `v0.6.2` on the Apolosign tablet, pair it with HA, pin the entity by hand in Hearth. Confirms the items under [Open questions](#open-questions--needs-hardware) and gates the rest.
2. **mDNS self-match** (small) — replace the Linux-only MAC source on Android with a browse of `_esphomelib._tcp` for the tablet's own address; unit-test the TXT-to-unique_id path; keep the manual pin.
3. **Boot start** (small) — prefer a boot receiver contributed upstream to Ava; otherwise open Ava's activity from Hearth at startup and return to the front. Add the `<queries>` entry.
4. **Voice plugin guidance on Android** (small) — setup steps in the on-device panel and the portal; hide nothing that works.
5. **Kiosk provisioning** (trivial, rides on follow-up #13 of the requirements spec) — allow-list the Ava package under lock task; set the default assistant to none.
6. **Audio focus in Hearth** (small-medium, optional) — have media_kit playback respond to a duck request so Ava's replies are audible over video. Becomes necessary with Android Sendspin.

## Open questions / needs hardware

None of these can be settled without a tablet. All are **assumed** above.

- Does HA discover Ava, create `assist_satellite.<name>` and a `switch.<name>_mute_microphone`, and report all four states during a conversation?
- Does Android NSD return Ava's own `_esphomelib._tcp` registration to a `bonsoir` browse running on the same device, with the `mac` TXT record intact?
- Can Hearth, as the HOME app, open Ava's activity at boot and get back to the front without user input on Android 10 through 16? Does Ava's service then keep running for days?
- Does Ava's foreground service keep running under lock task when only its package is allow-listed?
- Wake-word accuracy for `okay_nabu` on the tablet's microphone at room distance, and false triggers from the tablet's own speaker with no echo cancellation. Which `AudioSource` works best on the RK3576 board?
- Does the stock assistant's hotword, if present on the tablet, take the microphone from Ava? Is it gone once the default assistant is set to none?
- Does video playing through libmpv duck or pause when Ava requests transient focus?
- Timer ring and announcement volume relative to Hearth's media, since Ava sets player volume rather than the system stream.
- Does Android Auto Backup restore Ava's settings file, and with it the MAC, after a reinstall? (`allowBackup` is on with unmodified sample rules; **verified** in the manifest, behaviour **assumed**.)
