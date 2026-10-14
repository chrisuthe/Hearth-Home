# Android Native Voice Satellite — Design

**Date:** 2026-10-13
**Status:** Design. Nothing here is implemented. The hardware facts were measured on one tablet.
**Goal:** Specify a voice satellite that runs inside the Hearth APK on Android, including how it shares audio with a native Sendspin player, and break the work into tasks.

Builds on `2026-10-13-android-voice-satellite-options.md`, which compared four options and first recommended Ava as a companion app. This document replaces that recommendation with the options spec's runner-up, for the reasons under [Why native](#why-native).

## How to read this

- **verified** — read in source at the commit under [Sources read](#sources-read), or measured on the tablet named under [What we measured](#what-we-measured). The file or the measurement is named inline.
- **assumed** — reasoned from that source or from Android platform documentation, and not settled by code we read or a test we ran.

Ava's `A/` stands for `app/src/main/java/com/example/ava/`. SendspinDroid's `S/` stands for `android/app/src/main/java/com/sendspindroid/`.

## Sources read

| Short name | Repository | Commit | Committed |
|---|---|---|---|
| Ava | `brownard/Ava` | `2c76f51` (tag `v0.6.2`) | 2026-06-15 |
| SendspinDroid | `chrisuthe/SendspinDroid` | `3af5666` (`2.0.0-Beta20`) | 2026-10-11 |
| HA core, aioesphomeapi | as listed in the options spec | | |

Tablet: Apolosign Calendar, product `DigitalSignageFA2169T`, Rockchip RK3576, Android 16 (API 36), production build, no root (read with `getprop`).

## Why native

Three things settled it after the options spec was written. The first was already in that spec; what is new is the conclusion that it has no clean fix.

1. **Ava cannot be started without showing its activity.** Its service is `exported="false"` and is only started from `MainActivity` (**verified**, Ava `app/src/main/AndroidManifest.xml`, `A/ui/services/ServiceViewModel.kt:73-81`). Android 14+ requires the app to be visible when a `microphone` foreground service starts, and Android 15 blocks starting one from `BOOT_COMPLETED` (**assumed**, from platform documentation), so an upstream boot receiver would not fix it. Hearth is always visible, so a service inside Hearth has no such problem.
2. **We want voice timers in Hearth's own timer UI.** Home Assistant delivers timer events to the satellite device through a per-device handler (**verified**, HA core `esphome/assist_satellite.py:291-299`, `643-659`), and we found no entity that exposes them (**assumed**). With a companion app that means a cross-app hand-off and a fork of Ava to add it.
3. **The tablet's own speaker stays in its microphone.** The vendor echo canceller is switched on, and a loud residual still reaches apps. See the next section. Voice therefore has to control what Hearth is playing at the moment of wake, and one process has to own both.

The cost is the one the options spec named: we own the protocol upkeep.

## What we measured

Measured on 2026-10-13 with a throwaway recording app (twelve 4-second `AudioRecord` captures, eight of them while playing 300–3000 Hz chirps through the speaker) and by reading the vendor audio configuration over `adb`. All **verified** on the tablet above and on nothing else.

| Fact | Evidence |
|---|---|
| Apps receive one processed channel. A stereo capture has bit-identical left and right. | Recorded WAVs |
| The audio HAL opens the capture device with 6 channels at 48 kHz and runs Rockchip's voice library (`SKV`) on every stream, whatever the requested source. | HAL log: `in->Channels : 6`, `rkaudio_preprocess_init` on all twelve captures |
| `MIC`, `VOICE_RECOGNITION`, `VOICE_COMMUNICATION` and `UNPROCESSED` take the same path. There is no raw one. | Same HAL path on all four, and the same level on all eight captures under playback (−29.6 to −30.6 dBFS); `PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED` is false |
| 16 kHz mono works. The HAL refuses a mono mask, opens stereo, resamples 48 kHz to 16 kHz, and the framework downmixes. | HAL log: `channel is not support`, `create resampler ... 48000 => 16000` |
| Quiet-room floor is about −67 dBFS with vendor gain control and noise reduction active. | Two of the four quiet captures (−67.9 and −67.4 dBFS). The other two were louder (−46.1 and −36.7 dBFS, peaks to −11.6) for a reason we did not identify: room sound or the vendor gain control. |
| Speaker echo arrives at about −30 dBFS RMS over a capture (−26 to −33 dBFS second by second), peaking near −11 dBFS, on every source, with media volume at 80 of 100 and the test signal at 0.3 of full scale. | Recorded WAVs |
| The vendor library has echo cancellation, beamforming, noise reduction and gain control switched on. | `rkaudio_effect_preprocess.json`; the HAL's config dump in the log |
| The platform echo canceller, noise suppressor and gain control cannot be attached. | `isAvailable()` is false for `AcousticEchoCanceler`, `NoiseSuppressor` and `AutomaticGainControl`; `create()` returned null for the first two (the third was not tried) |
| Android cannot report the microphone count or geometry. | `getActiveMicrophones()` returns one entry with no position; HAL logs `actual_mic_count =0` |
| The ambient light sensor does not follow room lighting. Its last 50 events, from 11:30 to 16:03, are all 10 or 160 lux. It then logged nothing until at least 19:28, a span that includes the room lights being switched off and on by the person in the room. | `dumpsys sensorservice` at 19:20 and 19:28; no events on `lightsensor-level` during 210 s of watching |

Limits of these measurements:

- We had no unprocessed capture to compare against, so the amount of echo the vendor library removes is unknown. What is known is that the residual of this test signal sits roughly 38 dB above the noise floor.
- The test signal was chirps, not speech. Nobody spoke a known phrase at a known distance. Wake-word accuracy, with or without playback, is untested.
- The six raw channels are most likely four microphones plus two speaker-reference channels: the vendor library logs `num_ref_channel = 2` and "This AEC version is used for 4 microphones!". We did not confirm it on the hardware, so the split is **assumed**.
- One tablet. Other Android tablets are **assumed** to differ, some with working platform effects; the design must not depend on this one's quirks.

**Consequences for the design:** the choice of `AudioSource` is irrelevant on this device, we do not rely on echo cancellation and silence playback instead, and the light sensor is not used for anything.

## Goals

- A wake word on the tablet starts an Assist conversation with the same Home Assistant behaviour as the Pi: the `assist_satellite` entity, announcements, start and continue conversation, timers, mute.
- `VoiceAssistantService`, the voice pill and the Voice plugin's mic toggle keep working through the HA entity, unchanged in logic.
- Voice timers appear in Hearth's timer UI and ring through Hearth's alert overlay.
- Hearth's own playback goes quiet the instant the wake word fires.
- One APK, started with Hearth, no assistant role.

## Non-goals

- Replacing LVA on the Pi. The Pi keeps its separate service.
- The Android assistant role, a `VoiceInteractionService`, or lock-screen entry points. The options spec covers why a kiosk does not need them.
- Software echo cancellation in the first version. It is a later phase with its own open question.
- External wake-word models pushed from Home Assistant. Ava applies HA's choice among its own models (**verified**, `A/esphome/voiceassistant/VoiceAssistant.kt:124-136`) but has no handling for external ones, and neither will we at first.

## Architecture

```
Dart isolate                         Android process (Kotlin)
────────────                         ────────────────────────
VoiceAssistantService  ◄── HA websocket (assist_satellite state, mute switch)
VoiceSatelliteBridge   ◄── com.hearth/voice ──►  HearthAudioService  (foreground: microphone|mediaPlayback)
TimerService                                        ├─ Satellite core      ESPHome server :6053, pipeline, entities
Voice plugin                                        ├─ Wake word           microWakeWord, 16 kHz mono
media_kit players      ◄── duck request ────────    ├─ Voice output        TTS, announcements, tones
                                                    ├─ AudioCoordinator    who is quiet, and when
                                                    └─ Sendspin player     (later; see Sendspin)
```

- **`HearthAudioService`** is one foreground service in the Hearth APK. It is thin glue: lifecycle, the notification, the platform channel, and the `AudioCoordinator`. Dart starts it after `HubConfig` loads and passes it the voice configuration. It persists nothing: when Home Assistant changes a setting through an entity, the service applies it and reports it to Dart, which writes `HubConfig`.
- **Satellite core** is Ava's device code, lifted as a library.
- **`AudioCoordinator`** is the new piece. It is the single place that decides which outputs are muted or ducked for each satellite state. Native outputs are silenced directly; Dart-owned players (media_kit) are told over the channel.
- **The HA entity stays the source of truth for the pill.** Home Assistant discovers the satellite like any ESPHome device, and `VoiceAssistantService` mirrors the entity exactly as it does for LVA. The platform channel carries only what HA cannot: identity, timers, duck requests and health.

## Code reuse and packaging

What we take from Ava, all Apache-2.0 (**verified**, `LICENSE.md`):

| Piece | Where it is in Ava | State |
|---|---|---|
| Protocol: `api.proto`, plaintext codec, message table | `:esphomeproto`, a pure-JVM library (**verified**, `esphomeproto/build.gradle.kts`) | Use as is |
| Wake-word feature frontend | `:microfeatures`, an Android library with a CMake build over TensorFlow's microfrontend (**verified**, `microfeatures/src/main/cpp/CMakeLists.txt`) | Use as is |
| Device server, pipeline, entities, wake-word detector, mDNS registration | `A/esphome/`, `A/server/`, `A/wakewords/`, `A/nsd/`: 2,453 lines of Kotlin (**verified** by count) | Lives in `:app`; needs extracting |
| Wake-word models | `app/src/main/assets/wakeWords/` (nine, `okay_nabu` among them) and `stopWords/stop.tflite` (**verified**) | Bundle `okay_nabu`, `hey_jarvis`, `stop` only. See Licences below |

The extraction turned out to be a pure move. The four packages reach the rest of Ava through three small helpers only (`SettingState`, `BufferUtils`, `AsyncUtils`) and import no Hilt, DataStore or Compose; those live in Ava's settings stores, its service and `DeviceBuilder`, which stay in `:app` (**verified** by doing it: `chrisuthe/Ava-hearth` pull request 1, 80 renames, the same 47 unit tests passing before and after). The library keeps Media3 for playback, LiteRT for inference and Timber for logging. What Hearth still has to write is its own equivalent of `DeviceBuilder`, wiring the device from Hearth's configuration.

**Packaging.** Fork Ava, move the four packages above into a new `:satellite` library module in the fork, and leave `:esphomeproto` and `:microfeatures` untouched so upstream merges stay cheap. Hearth pins the fork by tag as a git submodule under `android/third_party/` and includes its three modules from `android/settings.gradle.kts`. The fork carries an `UPSTREAM_PIN`, gets a third `check_fork` entry in `scripts/check-upstream-drift.sh`, and its tag never automerges, like the other forks.

The alternative is to copy the code into `android/` directly. It is simpler on day one and loses the upstream diff. We chose the fork; see [Decisions](#decisions).

### Licences

Hearth is MIT. Shipping Apache-2.0 code inside it is allowed; the APK carries both licences and Hearth's own code stays MIT. This is our reading of the licence terms, not legal advice.

| What ships | Licence | Source checked |
|---|---|---|
| Ava's Kotlin (`:satellite`) | Apache-2.0 | `LICENSE.md` (**verified**) |
| TensorFlow microfrontend (C, `:microfeatures`) | Apache-2.0 | File headers (**verified**) |
| KissFFT (`:microfeatures`) | BSD-3 | `kissfft/kiss_fft.c` header (**verified**) |
| `api.proto` (`:esphomeproto`) | MIT. ESPHome's licence is GPLv3 for C/C++ files only and MIT for everything else | `esphome/home-assistant-voice-pe` `LICENSE`, the ESPHome licence (**verified**) |
| LiteRT, Media3, Timber; protobuf | Apache-2.0; BSD-3 | Publisher licences (**assumed**, not opened) |
| `okay_nabu`, `hey_jarvis` models | Apache-2.0 | `esphome/micro-wake-word-models`, which holds both (**verified**) |
| `stop` model | Apache-2.0 | Byte-identical to release `stop-20241016.2` of the Apache-2.0 `kahrendt/microWakeWord` (**verified**, `2026-10-14-third-party-notices-design.md`) |
| Wake, timer and error sounds | CC-BY 4.0, Clayton Charles Tapp | `assets/sounds/LICENSE.md` in Ava (**verified**) |

What follows from the table:

- **`hey_luna` is not bundled.** It comes from `adamlonsdale/microwakeword-custom-words`, which has no licence, so we have no right to redistribute it (**verified**, no licence on the repo). Ava's other models (`alexa`, `hey_mycroft`, `hey_home_assistant`, `okay_computer`, `choo_choo_homie`, `hey_peppa_pig`) are Apache-2.0 in the same models repo, but we ship only the three above. Hearth's build therefore lists model files one by one rather than taking Ava's whole assets folder.
- **The APK carries the licence texts and credits** for everything in the table: `assets/licenses/`, shown under Settings → System → Open-source licences (`2026-10-14-third-party-notices-design.md`).
- **The fork must state what it changed.** Apache-2.0 §4(b) asks for a notice on modified files. The fork's `UPSTREAM_PIN` describes the move; `chrisuthe/Ava-hearth` pull request 2 adds a README section listing the moved files.
- **No use of the Ava name as Hearth's.** Apache-2.0 grants no trademark rights.

## Protocol surface

We advertise what Ava and LVA advertise, so Home Assistant sees the same device class on both platforms.

- Plaintext ESPHome native API on port 6053, API version 1.10, one client at a time (**verified** as Ava's behaviour, `A/esphome/EspHomeDevice.kt:138-139`, `A/server/Server.kt:90`).
- Feature flags `VOICE_ASSISTANT | API_AUDIO | TIMERS | ANNOUNCE | START_CONVERSATION` (**verified**, `A/services/DeviceBuilder.kt:51-55`).
- Device info adds what Ava leaves out: a friendly name from a new `voiceSatelliteName` setting (default: the hostname, which the MQTT client id already uses), manufacturer `Hearth`, model from `Build.MODEL`, and Hearth's version as the firmware version.

Entities:

| Entity | Type | Notes |
|---|---|---|
| Media Player | media player | Ava's; plays a URL from HA, volume and mute |
| Mute Microphone | switch | Ava's name. Hearth's mute lookup needs `mute` in the entity ID. |
| Enable Wake Sound | switch | Ava's |
| Repeat Timer Sound | switch | Dropped. The ring always repeats until Hearth's alert overlay, the stop word or a wake word ends it. |

Home Assistant adds the `assist_satellite` entity itself from the feature flags (**verified**, HA core `esphome/assist_satellite.py:138-141`).

Moving Hearth's MQTT entities (Current Screen, Now Playing, Timer, Next Alarm, Volume) onto this device would put everything under one HA device with no broker. It is listed as a later phase, not part of the first version.

**Security.** Port 6053 is unauthenticated and unencrypted, exactly as on the Pi. Home Assistant supports Noise encryption per device; Ava's codec rejects it ("Only plain text is supported for now", `esphomeproto/.../AsynchronousCodedChannel.kt:44`). Adding it is possible later and is not planned.

## Identity and discovery

- Hearth generates six random bytes once, formats them as a MAC, and stores the string in `hub_config.json` as `voiceSatelliteMac`. Storing it in Hearth's config, not in the service, means a config backup or restore keeps the HA device identity.
- The service reports that string as `mac_address` and publishes it as the `mac` TXT record of an `_esphomelib._tcp` service through `NsdManager`, as Ava does (**verified**, `A/nsd/VoiceSatelliteNsd.kt:15-22`). Home Assistant requires that record for discovery (**verified**, HA core `esphome/config_flow.py:343-351`).
- HA's unique_id for the satellite is `<mac>-assist_satellite` (**verified**, HA core `esphome/entity.py:672-674`). `VoiceAssistantService._autoDetectByMac` already matches that. The only Dart change is the MAC source: `_readPiMacAddress()` on Linux, `config.voiceSatelliteMac` on Android. No mDNS browse is needed.
- Clearing Hearth's data creates a new MAC and HA raises a device conflict for the old one (**verified** as HA's behaviour, `esphome/manager.py:668-716`). Restoring a config backup restores the MAC; the Voice plugin shows it for reference.

## Capture and wake word

- `AudioRecord`, 16 kHz, mono, 16-bit. The source defaults to `VOICE_RECOGNITION` and is a setting, because it matters on other tablets even though it does nothing on this one.
- When the platform echo canceller and noise suppressor are available, attach them. On the Apolosign they are not, and the code must treat that as normal.
- Detector: Ava's `MicroWakeWordDetector` on LiteRT with the `:microfeatures` frontend (**verified**, `A/wakewords/microwakeword/`). Up to two active wake words, plus the `stop` model.
- Default wake word `okay_nabu`, matching the Pi.
- Mute stops capture outright, as in Ava (**verified**, `A/esphome/voiceassistant/VoiceInput.kt:105-106`), and the notification and the Voice plugin both show it.

## Echo and ducking

This is the part Ava does not solve and the reason for one process.

Ava ducks only its own media player, to 50%, and asks other apps to duck through audio focus (**verified**, `A/esphome/voiceassistant/VoiceOutput.kt:63`, `124-135`). On the Pi, `VoiceDucker` drops Sendspin to 20% when the HA entity leaves `idle`, which is one HA round trip after the wake word (`lib/services/voice_ducker.dart`).

On Android the `AudioCoordinator` acts on the detector, not on HA:

| Satellite state | Sendspin (native) | media_kit video and audio | Voice output |
|---|---|---|---|
| Idle | Normal | Normal | Silent |
| Wake word fired, wake sound playing | Muted at once | Duck requested | Wake sound |
| Listening | Muted | Ducked | Silent |
| Processing | Muted | Ducked | Silent |
| Responding (TTS or announcement) | Muted | Ducked | Speech |
| Timer ringing | Muted | Ducked | Ring, with silence in every cycle |
| Back to idle | Restored | Restored | Silent |

Rules:

- **Mute, not duck, for Sendspin.** With no echo cancellation, music at 20% is still in the microphone while the user is speaking. SendspinDroid's mute is a gain of zero that keeps draining in sync, so restoring is instant and in time (**verified**, `S/sendspin/SyncAudioPlayer.kt:686-707`). The mute is local and is not reported to the server, for the reason `voice_ducker.dart` already gives: other rooms must not dim.
- **media_kit is asked, not forced.** The coordinator sends a duck request over the channel and Dart lowers the players it owns. This is the only output with a round trip, and it is in-process.
- **The ring leaves gaps.** A timer ring has to be stopped by voice, so the tone asset has at least one second of silence per cycle for the stop word to land in. Whether that is enough is an open question; the on-screen dismiss is always available.
- **Wake word during playback is not solved.** At 80% media volume our test signal, itself at 0.3 of full scale, sat roughly 38 dB above the microphone floor. Whether `okay_nabu` still triggers over music is the first hardware test. If it does not, the options are a lower default media volume on this tablet, the on-screen mic button, or the software echo canceller below.

**Later: software echo cancellation.** An in-process satellite can do what no companion app can: it has the playback signal. Sendspin PCM and the voice output could feed a reference into WebRTC AEC3 or speexdsp ahead of the wake word. Two things are unknown: whether a linear canceller works after the vendor's non-linear processing, and whether the playback delay is stable enough to align. Both need a spike on hardware before any design.

## Timers

Home Assistant owns the countdown. The satellite receives four events (started, updated, cancelled, finished), each with an id, a name, total seconds, seconds left and an active flag (**verified**, `api.proto:1945-1963`). Ava keeps a pending map and one ringing timer, and with Repeat Timer Sound on it rings until the stop word, a wake word, or a stop call; with it off it plays once (**verified**, `A/esphome/voiceassistant/VoiceAssistant.kt:60-68`, `151-178`, `212-228`, `296-305`).

In Hearth:

- The service forwards every timer event over the channel.
- `TimerService` gains a second kind of timer: remote, keyed by HA's string id, carrying a name and a paused flag, with remaining time taken from the event and counted down locally between events. Local timers (`startTimer(Duration)`) are untouched.
- Remote timers show in the timer screen and on the home screen beside local ones. They are cancelled by voice or from HA, not from the timer screen, since the protocol has no cancel message from the device.
- On `finished`, `TimerService` raises the existing full-screen alert, which also wakes the kiosk. Dismissing it calls `stopTimerRing` on the service. The stop word and the wake word stop it too, and the service tells Dart so the overlay closes.
- The ring is played by the service, so it works when the Flutter side is busy and follows the ducking table above. `TimerService` can start the same ring for a local timer, which gives Android the timer chime it lacks today (requirements spec, follow-up 4).
- The MQTT `timer` sensor already reads `TimerService`, so it includes voice timers with no change.

The Pi does not get this. LVA has no hand-off, and Home Assistant does not expose voice timers as entities (**assumed**; we did not find one in the `esphome` or `assist_satellite` components, and did not search the rest of HA). Voice timers on the Pi keep ringing from LVA alone.

## Platform channel

One `MethodChannel` and one `EventChannel` named `com.hearth/voice`. Dart is the only caller.

| Direction | Name | Payload |
|---|---|---|
| Dart → native | `start` | name, MAC, port, wake words, sensitivity, audio source, wake sound on/off |
| Dart → native | `stop` | — |
| Dart → native | `setMuted` | bool. Local shortcut; the HA switch still works. |
| Dart → native | `wake` | — (on-screen mic button) |
| Dart → native | `startTimerRing` | — (a local timer fired) |
| Dart → native | `stopTimerRing` | — |
| Dart → native | `listWakeWords` | → ids and display names |
| native → Dart | `state` | idle, listening, processing, responding, error; connected to HA or not |
| native → Dart | `timer` | event type, id, name, total, left, active |
| native → Dart | `duck` | bool |
| native → Dart | `ringStopped` | — |
| native → Dart | `settingChanged` | mute, wake sound, or active wake words changed from Home Assistant |
| native → Dart | `health` | permission missing, port in use, mic open failed, model load failed |

`VoiceSatelliteBridge` in Dart owns the channel. On non-Android platforms it is a no-op, so the Pi and desktop paths do not change. The `state` event is not wired to the pill in the first version; it exists for diagnostics, and it is the hook if we later want the pill to react without the HA round trip.

## Android changes

- Permissions: `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`, `MODIFY_AUDIO_SETTINGS`. `WAKE_LOCK` and the multicast permission are already declared.
- One service, `foregroundServiceType="microphone|mediaPlayback"`, not exported.
- `MainActivity` stops being a bare `FlutterActivity`: it registers the channel and requests `RECORD_AUDIO` on first enable.
- The service is started only from the visible activity, which satisfies the Android 14+ rule. After a reboot the HOME role relaunches Hearth and Dart starts the service again. No boot receiver.
- A partial wake lock and a Wi-Fi lock for the life of the service, as Ava holds (**verified**, `A/wakelocks/WifiWakeLock.kt:22-37`).
- The service returns `START_NOT_STICKY`. A restart without the activity could not open the microphone, and the HOME role brings the activity back anyway (**assumed**).
- Nothing extra under lock task: it is the same package.
- APK size grows by LiteRT, Media3 ExoPlayer, the protobuf-lite runtime and the frontend library for each ABI. The amount is unmeasured.

## Settings

A plugin renders twice, so each of these exists in the on-device panel and the `:8090` portal.

- Voice satellite on/off, and satellite name. This whole group renders only on Android; the rest of the Voice plugin is unchanged on every platform.
- Wake word, second wake word, sensitivity.
- Wake sound on/off.
- Audio source (advanced).
- Read-only: MAC, connected to Home Assistant, last health event.
- First-run note: add the discovered ESPHome device in Home Assistant.

New `HubConfig` fields: `voiceSatelliteEnabled`, `voiceSatelliteName`, `voiceSatelliteMac`, `voiceWakeWords`, `voiceWakeSensitivity`, `voiceWakeSound`, `voiceAudioSource`. `voiceAssistantEntityId` stays as the manual pin.

## Sendspin

Hearth's Android Sendspin is guarded off today (`lib/services/sendspin/sendspin_service.dart:819`), and follow-up 10 of the requirements spec plans it as the Dart client plus an NDK FLAC build and an `AudioTrack` sink behind the existing `com.hearth/sendspin_audio` channel.

SendspinDroid is a second route. All **verified** at `3af5666`:

- A complete Android player: MIT, minSdk 26, at `2.0.0-Beta20` (`android/app/build.gradle.kts`, `LICENSE`).
- Protocol, Noise encryption, pairing, transports and the clock filter are already a Kotlin Multiplatform library, `:shared` (`android/shared/build.gradle.kts`).
- The player itself is in `:app`, not in a library: `SyncAudioPlayer` (2,023 lines), the `SendSpin` client, `SendSpinProtocolHandler` (2,240 lines) and the decoders. `SyncAudioPlayer` and `SendSpin` take no `Context` in their constructors, and the audio output is injected through an `AudioSink` interface (`S/sendspin/SyncAudioPlayer.kt:214-227`, `S/sendspin/SendSpin.kt:83-86`, `S/sendspin/audio/AudioSink.kt`).
- FLAC and Opus decode through `MediaCodec`, so there is no native library to build (`S/sendspin/decoder/`).
- Output is a low-latency `AudioTrack` with DAC-position-aware start alignment and sample insert/drop correction (`S/sendspin/SyncAudioPlayer.kt:145-162`, `260-264`, `422-425`).
- Mute is per reason (`PLAYER`, `SYNC`, `INTERRUPTION`) and is a gain of 0 or 1; there is no partial duck (`SyncAudioPlayer.kt:686-707`).
- On transient audio-focus loss it mutes locally and keeps sync, except during a call, when it pauses the group on the server (`S/playback/AudioInterruptionPolicy.kt:76-83`).
- `PlaybackService` (3,748 lines) is the Media3 session, notification and Android Auto layer. Hearth needs none of it.

**What the satellite needs from an Android Sendspin player**, whichever route is taken:

1. A local mute that takes effect within one audio buffer and is not reported to the server.
2. To run in the same process, so that mute is a call and not a message.
3. Later, a tap on the PCM it writes, as the echo reference.

The Dart route could meet the first two through the existing `setMuted` on its sink; the third would mean sending the reference back across the channel.

**Decision.** Use SendspinDroid's player on Android, inside `HearthAudioService`, and keep the Dart `SendspinService` as the settings and state facade over a channel. It is a released beta that we have not yet run on this tablet, it needs no NDK FLAC build, it meets all three needs natively, and adding a `VOICE` mute reason is a one-line change in a repository we own. The cost is extracting the player from `:app` into a library module in SendspinDroid, and two Sendspin implementations in Hearth (Dart on the Pi and desktop, Kotlin on Android).

This replaces the plan in follow-up 10 and gets its own spec. The satellite does not wait for it: with Sendspin off on Android there is nothing to mute, and the `AudioCoordinator` is written against an interface.

## Testing

- **JVM unit tests** travel with the lifted code. Ava ships tests for the assistant, pipeline, voice input, voice output, announcements and timers, with stubs for the microphone, player and wake word (**verified**, `app/src/test/java/com/example/ava/`). They move into the fork's `:satellite` module; the Tasker tests stay behind.
- **Dart tests** with a fake channel: `VoiceSatelliteBridge` event decoding, remote timers in `TimerService` (start, update, pause, cancel, finish, dismiss), the Android MAC source in `VoiceAssistantService`, and the duck request reaching media_kit owners.
- **Portrait tests**: the Voice plugin panel and the timer screen with remote timers, at all three canvas sizes.
- **Hardware checklist** per phase, since no CI job builds the APK: the items under [Open questions](#open-questions--needs-hardware).

## Phases

Each line is one task. Sizes are relative.

| # | Task | Size | Depends on |
|---|---|---|---|
| 1 | Fork Ava, extract `:satellite`, carry the JVM tests. Done in `chrisuthe/Ava-hearth` pull request 1; needs merging and a tag. | Small | — |
| 2 | Pin the fork as a submodule; `HearthAudioService` with Hearth's own device builder, manifest, permissions, `com.hearth/voice` channel, `VoiceSatelliteBridge`, start from Dart | Medium | 1 |
| 3 | Identity: `voiceSatelliteMac`, Android MAC source in `VoiceAssistantService`, device info | Small | 2 |
| 4 | Hardware pass 1: HA discovery, the four states, mute, announce, wake word at distance, wake word over playback | Small | 3 |
| 5 | Voice plugin settings on both surfaces, health reporting, `settingChanged` | Small-medium | 4 |
| 6 | Timers: remote timers in `TimerService`, alert overlay, ring with gaps, `startTimerRing` and `stopTimerRing` | Medium | 4, 7 |
| 7 | `AudioCoordinator` and the media_kit duck request | Small | 4 |
| 8 | Sendspin on Android through SendspinDroid's player (own spec) | Large | 7 |
| 9 | Echo-cancellation spike with a playback reference | Medium, may end in "no" | 8 |
| 10 | Move Hearth's MQTT entities onto the ESPHome device | Small-medium | 3 |

Tasks 1 to 4 are the minimum that answers whether this works on the tablet. Task 4 gates everything after it.

## Open questions / needs hardware

- Does `okay_nabu` trigger reliably from across a room on this tablet's processed microphone? With music playing at a normal volume?
- How long is the vendor gain control's recovery after loud playback, and does it swallow the first word after the wake sound?
- Does the stop word land in a one-second gap in the timer ring?
- Does Home Assistant discover the service from an `NsdManager` registration made inside a foreground service, and keep the connection for days?
- Does the service survive under lock task, and across the activity being recreated on rotation?
- Does requesting `RECORD_AUDIO` from the Flutter activity behave under immersive mode and as the HOME app?
- How much does the APK grow per ABI?
- Does the stock assistant's hotword, if the tablet has one, contend for the microphone?
- Is a linear echo canceller usable after the vendor processing? (Task 9.)
- Behaviour on a second, non-Rockchip tablet with working platform effects.

## Decisions

Made on 2026-10-13:

1. **Packaging**: a fork of Ava, pinned as a submodule. Copying the code into `android/` was the alternative.
2. **Sendspin on Android**: SendspinDroid's native player. The Dart client with a native sink, as follow-up 10 of the requirements spec used to describe, was the alternative.

3. **Auto-brightness on the Apolosign**: left alone. The light sensor does not work, so system auto-brightness holds the panel near minimum; we are not changing that for now.
