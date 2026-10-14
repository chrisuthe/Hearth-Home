# Android Native Voice Satellite — Design

**Date:** 2026-10-13
**Status:** Phases 1–5 and 7 built. Hardware pass 1 ran on 2026-10-14; results under [Hardware pass 1](#hardware-pass-1-2026-10-14). The hardware facts were measured on one tablet.
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

### As built (phase 7)

- **Driven by Ava's `duck`, not by the `state` event.** Ava calls `VoiceOutput.duck()` before the wake sound, at `RUN_START`, for an announcement and for a timer ring, and `unDuck()` when the conversation, the announcement or the ring ends (**verified**, `satellite/.../VoiceAssistant.kt:171`, `195`, `244`, `274`, `282`, `292`, `307` and `VoicePipeline.kt:81` in the fork). The `state` event misses two rows: it stays idle while the wake sound plays, because the pipeline starts only after it, and for the whole of a timer ring. `CoordinatedVoiceOutput` wraps Ava's output and reports both calls to `AudioCoordinator` (`android/.../voice/AudioCoordinator.kt`), which sends `duck` (`active`: bool) only on a change. The fork is unchanged.
- **Dart.** `AudioCoordinator` (`lib/services/audio_coordinator.dart`) ducks while the service is running and connected, and either the last `duck` was true or the state is listening, processing or responding. The states are a backstop for a missed event; on the way out the duck holds until `unDuck`, which Ava sends after the state returns to idle. It sets `playbackDuck`, a factor every `MediaKitVideoPlayer` multiplies into the volume its caller set, so DLNA's reported volume is untouched and restoring is exact. A player started while ducked starts ducked. The level is 0.20, as the Pi uses for Sendspin. This covers DLNA and Plex casts and Live TV; Music Assistant does not play through media_kit on the tablet, and its local playback will be Sendspin.
- **Released without `unDuck`.** Ava does not call it when Home Assistant drops mid-exchange (`onDisconnected` resets the state) or when the device is closed. Natively, the service releases on a lost connection and in `tearDown`, which covers stop, rebuild and a failure. In Dart, a stopped service, a lost connection or a new health report drops the request, so a service that dies without a last event cannot leave playback ducked. The coordinator's disposal restores too.
- **Pi unchanged.** `VoiceDucker` still ducks Sendspin from the Home Assistant entity. The coordinator is read only where `voiceSatelliteSupported`.
- **The Sendspin seam.** `AudioCoordinator.addMute` takes a callback that gets the current state on registration and every change after, on the main thread with no channel round trip. Sendspin's engine registers `engine.setMuted(VOICE, …)` there when it joins the service (`2026-10-14-android-sendspin-design.md`, "Muting at wake").
- **Deviation.** None from the table.
- **On the tablet (2026-10-14, debug build).** After a reboot, a cast ducked at the wake word and came back afterwards, by ear, through a conversation that HA continued into a second turn. The log holds only the end: Ava's last `TTS finished` at 12:10:34.102 and the coordinator's "restoring playback" at 12:10:34.131, 29 ms later, so the restore crossed the channel within a frame or two. The wake word and the duck itself had already scrolled out, because the debug build logs every `VoiceAssistantAudio` frame (about 30 a second) and the main buffer holds only seconds of a conversation. Not measured: the time from the wake word to the duck, and whether the wake word triggers over the tablet's own playback without it.
- **Seen on the same build, not caused by it.** Before that reboot, a Plex cast decoded its first frame and then stalled at 0 s (`h264_mediacodec`: "Both surface and native_window are NULL"), and two later casts never created an mpv player. The ducking factor was 1.0 throughout, which leaves the player's volume calls as they were. Plex casting on Android was untested before this; it is not followed up here.

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

### As built (phase 6)

The fork is unchanged; Hearth wraps what Ava already exposes.

- **Events in.** `TimerEventTap` wraps Ava's `Server` and copies each `VoiceAssistantTimerEventResponse` to the channel as a `timer` event (`type` started, updated, cancelled or finished; `id`, `name`, `total` and `left` in seconds, `active`) before Ava handles it. `VoiceEvents` keeps the live ones and replays them, with `left` counted down, to a listener that attaches later, so a recreated engine does not lose its timers. A stopped service clears them.
- **One ring, Ava's.** Ava's ring stays the only one: it already ducks, stops on the stop word and on a wake word, and pauses for one second after each play (`onTimerSoundFinished`, `delay(1000)`), which is the gap the stop word lands in. Hearth plays nothing for a voice timer, so it cannot ring twice. `startTimerRing` hands Ava a finished timer of Hearth's own (id `hearth-local`) through `VoiceAssistant.handleMessage`, so a local timer rings and stops the same way; it answers false when no device is running, and Dart falls back to its own beep, which is inert on Android. `stopTimerRing` is Ava's `stopTimer()`.
- **`ringStopped`** is sent when Ava's ringing timer clears, whatever cleared it, read from `VoiceAssistant.allTimers`, and when the device closes while ringing. Dart dismisses every fired timer on it, since they share the one ring. Dart calls `stopTimerRing` only when the last fired timer is dismissed, as the Pi's beep stops.
- **In `TimerService`** a voice timer is a `HubTimer` with a `remoteId`, a name and a paused flag. It is done only on `finished`, never by its own countdown. One that sits at zero for 60 s without `finished`, as across a lost connection, is dropped. It cannot be dismissed while it runs, from the timer screen or the MQTT cancel command. The timer screen shows its name and "Paused"; the alert card's body is its name, or the duration when it has none.
- **Cancelling from Hearth is not built.** Home Assistant does offer a way: `POST /api/intent/handle` with `HassCancelTimer` and the satellite's `device_id` (**verified**, HA core `intent/__init__.py` `IntentHandleView`, `intent/timers.py` `CancelTimerIntentHandler` and `_find_timer`). It matches by name, area or starting duration, not by timer id, so it cannot reliably cancel one timer of two that share a name or a duration. Left as a follow-up.
- **On the tablet (2026-10-14, debug build of this branch).** Timers were set from Home Assistant's intent API with the tablet's `device_id` (`HassStartTimer`, `HassPauseTimer`, `HassIncreaseTimer`, `HassCancelTimer`), not spoken: the events the satellite receives are the same, and speech recognition is not part of this check. **Verified**:
  - A 3-minute "Eggs" timer showed on the home pill and on the timer screen with its name, counting down. Paused with 2 minutes added, it showed the new time and "Paused"; cancelled, it went.
  - A 10-second "Tea" timer raised the alert card ("Time's up", "Tea") as HA sent `finished`, and the coordinator ducked. The only audio was Ava's ring, one assistant player per cycle, about 3 s of tone and 1 s of silence; Hearth played nothing of its own.
  - The card's dismiss stopped it: Ava logged `Stop timer`, playback was restored 43 ms later, and no further cycle started.
  - A 1-minute local timer rang through the same ring (`startTimerRing`).
  - The stop word stopped that ring and closed Hearth's alert. It landed in the gap: the last play ended at 13:48:56.958 and Ava stopped the timer at 13:48:57.630. How many tries it took was not recorded.
  - A wake word stopped a ringing "Pizza" timer and closed the alert (seen by the person at the tablet; the log line scrolled out). As in pass 1, it also opened a conversation, which HA continued into a second turn. The fork follow-up below still applies.

The Pi does not get this. LVA has no hand-off, and Home Assistant does not expose voice timers as entities (**assumed**; we did not find one in the `esphome` or `assist_satellite` components, and did not search the rest of HA). Voice timers on the Pi keep ringing from LVA alone.

## Platform channel

One `MethodChannel` and one `EventChannel` named `com.hearth/voice`. Dart is the only caller.

| Direction | Name | Payload |
|---|---|---|
| Dart → native | `start` | name, MAC, port, wake words, sensitivity, audio source, wake sound on/off, media player volume |
| Dart → native | `stop` | — |
| Dart → native | `setMuted` | bool. Local shortcut; the HA switch still works. |
| Dart → native | `wake` | — (on-screen mic button) |
| Dart → native | `startTimerRing` | — (a local timer fired) |
| Dart → native | `stopTimerRing` | — |
| Dart → native | `listWakeWords` | → ids and display names |
| native → Dart | `state` | idle, listening, processing, responding, error; connected to HA or not |
| native → Dart | `timer` | event type, id, name, total, left, active |
| native → Dart | `duck` | `active`: bool |
| native → Dart | `ringStopped` | — |
| native → Dart | `settingChanged` | mute, wake sound, active wake words or media player volume changed from Home Assistant |
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

New `HubConfig` fields: `voiceSatelliteEnabled`, `voiceSatelliteName`, `voiceSatelliteMac`, `voiceWakeWords`, `voiceWakeSensitivity`, `voiceWakeSound`, `voiceAudioSource`, `voiceSatelliteVolume`. `voiceAssistantEntityId` stays as the manual pin.

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

This replaces the plan in follow-up 10 and gets its own spec, `2026-10-14-android-sendspin-design.md`. The satellite does not wait for it: with Sendspin off on Android there is nothing to mute, and the `AudioCoordinator` is written against an interface.

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
| 4 | Hardware pass 1: HA discovery, the four states, mute, announce, wake word at distance, wake word over playback. Done 2026-10-14 except the release install. | Small | 3 |
| 5 | Voice plugin settings on both surfaces, health reporting, `settingChanged` | Small-medium | 4 |
| 6 | Timers: remote timers in `TimerService`, alert overlay, ring with gaps, `startTimerRing` and `stopTimerRing`. Built and run on the tablet; see "As built" under [Timers](#timers) | Medium | 4, 7 |
| 7 | `AudioCoordinator` and the media_kit duck request. Built; see "As built" under [Echo and ducking](#echo-and-ducking). Ducked a cast on the tablet | Small | 4 |
| 8 | Sendspin on Android through SendspinDroid's player: `2026-10-14-android-sendspin-design.md`, phases 1 to 6. Its phase 7, the Sendspin mute, needs task 7 | Large | — |
| 9 | Echo-cancellation spike with a playback reference | Medium, may end in "no" | 8 |
| 10 | Move Hearth's MQTT entities onto the ESPHome device | Small-medium | 3 |

Tasks 1 to 4 are the minimum that answers whether this works on the tablet. Task 4 gates everything after it.

## Hardware pass 1 (2026-10-14)

Apolosign Calendar (RK3576, Android 16), debug APK from `main` at `8b83864` plus this branch's two fixes, Home Assistant 2026.10.1. Everything below is **verified** on that tablet unless marked. Wake word `okay_nabu` (both `okay_nabu` and `hey_jarvis` active), sensitivity `very` (set in the Voice plugin before the pass).

**Verdict: proceed with timers (task 6) and the audio coordinator (task 7).** Nothing found blocks them. Two Hearth bugs were found and fixed on this branch. The release (R8) build was built but not installed, so whether R8 breaks the satellite at runtime is still **assumed** and has to be checked before a release ships it. Three fork changes become a follow-up task (below).

**Step 1: enable and permissions.** With Hearth as the HOME app in immersive mode, enabling the satellite showed the microphone prompt, then the notification prompt (order and grants from the log), and the tester reported both displayed fine over Hearth. The foreground service started straight after the grant (Android logged it as allowed from a `TOP` process), and the `_esphomelib._tcp` record was registered within a second.

**Step 2: discovery and adoption.** HA discovered the device by itself over zeroconf, and it was adopted from the discovery card. Device info: name `hearth`, friendly name `Hearth`, manufacturer `Hearth`, model `Apolosign Calendar`. The firmware field shows Hearth's app version (`1.20.0`), while the mDNS TXT record says `2025.9.0`. Entities: Media Player, Mute Microphone, Enable Wake Sound, plus HA's own assistant, wake word and finished-speaking selects. With the name left empty, the device is called `hearth`, the same name as the Pi's older satellite, so HA suffixed the tablet's entities (`assist_satellite.hearth_assist_satellite_2`). The device also has no area until one is assigned in HA.

**Step 3: the four states.** "Okay nabu, turn off the fireplace lights" and "okay nabu, what time is it" each ran end to end: wake sound, listening, processing, the spoken reply, back to idle. The reply was clear. Once fix 1 below was in, Hearth tracked the tablet's own satellite through listening, processing, responding and idle (from the log; the pill itself was not checked on screen).

**Step 4: mute, announce, volume.**
- Mute from HA and from Hearth's mic button both work and stay in step (after fix 1). Muting stops capture; unmuting reloads the wake-word models.
- `assist_satellite.announce` played the pre-announce chime and the message five times out of five.
- Volume from HA (0.86, 0.3, 1.0, 0.9) changed the output audibly and was saved to `voiceSatelliteVolume`.
- Choosing wake words in HA was saved to `voiceWakeWords`.

**Step 5: wake word at distance.** One attempt per cell unless noted, "okay nabu, what time is it":

| Distance | Quiet room | Music (large desktop speakers next to the tablet, normal volume) |
|---|---|---|
| 1 m | 1/1 | 1/1 |
| 3 m | 1/1 | 1/1 |
| 7 m | 3/3 | 1/1 |

The samples are small, but no attempt missed. Two **false wakes** in about an hour at sensitivity `very`, one on room conversation and one on barking dogs. `slightly` (the default) was not tried. The music was played by another machine. Playback *from the tablet itself* could not be tested, because Sendspin is inert on Android, so the ducking table above is still untested.

With music, the wake word held but speech after it suffered: once the start of the sentence was lost (" It's it."), and once HA's speech detection did not start until the sentence was repeated, 10.5 s in. The microphone gets no platform processing at all: `HearthMicrophone` logged `Platform audio effects attached: []`.

**First word swallowed: yes, for two reasons, and the vendor gain recovery is not one we could separate.**
- Ava starts streaming only after the wake sound finishes (`satellite/.../VoiceAssistant.kt:243-248` in the fork), 1.3 to 2.0 s after the wake word. Anything said over the chime is dropped. Every lost word in the quiet runs was speech over the chime.
- With the wake sound off, streaming starts 47 ms after the detection, but the detection itself fires a few hundred ms after the word ends. Running straight on ("okay nabu set a timer") still lost "set". Ava keeps no lead-in buffer.
- Turning the wake sound off (the Voice plugin, or HA's Enable Wake Sound) is the recommended setting on this tablet for now. A short pause after the wake word still helps.

**Step 6: robustness.**
- Rotation: no interruption. Orientation is in the activity's `configChanges`, so the activity is not recreated.
- Activity recreated in the same process (a relaunch with `CLEAR_TASK`, and a later HOME launch that created a second instance): broke the satellite before fix 2, survives after it. The new engine restarts the device and HA reconnects within about 1.5 s.
- Wi-Fi off for about 15 s: the service and its process survived. HA reconnected to the satellite about 30 s after the drop, without the record being registered again, and Hearth's own HA connection came back with backoff. The next wake word worked.
- Overnight soak and lock task: not run in this pass.

**Step 7: release build.** `scripts/build-android-apk.sh` with the release keystore built `hearth-android-dev.apk`: arm64 only (the script builds no other ABI), 81.2 MB, versionCode 1020000. It was **not installed**: replacing the debug build means another uninstall, and the satellite's MAC cannot be restored through the `:8090` API (`voiceSatelliteMac` is read-only there), so HA would see a new device. Deferred to a later session. For comparison, the universal debug APK is 249 MB.

**Step 8: cleanup.** `com.hearth.micprobe` and its recordings are removed from the tablet.

**Timers (seen along the way).** HA's timer events reach the service (started, finished), and Ava rings by itself on `finished`. Hearth shows nothing yet, as planned (task 6). A wake word while the timer rings both stops the ring *and* opens a conversation, 34 ms apart. Twice the extra conversation went wrong (" Thank you." heard; "could not find a timer named Eggs" after the ring had already ended). The stop word on its own was not tried.

**Home Assistant side, not Hearth.** The household pipeline sends everything to an LLM agent (`prefer_local_intents` off). The agent asked for a timer name and area, and once passed the name as `conversation_command`, which HA rejected (`NoTimerCommandError`). The satellite's part was right: every run carried the tablet's `device_id` and `satellite_id`. Turning on "Prefer handling commands locally" is the fix.

### Fixed on this branch

1. **Wrong satellite, and a mute that could not unmute.** `VoiceAssistantService` matched the MAC once, before HA had adopted the tablet, then auto-picked the Pi's satellite and a stale mute switch for the rest of the session. The mic button read that switch as unmuted, so every tap sent "mute". Now the MAC is matched again whenever a new `assist_satellite` entity appears. While the in-app satellite runs, mute is local: `micMuted` drives the service through the bridge, and the service reports it to HA itself.
2. **Activity recreation stopped the satellite.** A relaunch creates the new activity before the old one is destroyed. The old one's `cleanUpFlutterEngine` stopped the service the new engine had just started, and its `VoiceChannel.dispose()` cleared the process-wide event relay the new engine had attached to. The service is now stopped only when the last `MainActivity` finishes, and the relay detaches only for the listener that attached it.

### Follow-ups

- **Fork (one task):** stream from the moment of the wake, with the chime playing alongside; keep a short lead-in buffer of microphone audio; and make a wake word during a ringing timer stop the ring without starting a conversation. Each needs a hardware check of how the chime and the buffered wake-word tail affect transcription.
- **`:8090` after activity recreation:** the second engine's `main()` cannot bind the local API port while the first engine still holds it ("The shared flag to bind() needs to be true"), and the API stays down until the process restarts. Not satellite code.
- **Health event on reconnect:** when HA first connects, the wake-word models restart and the cancellation is reported as `modelLoadFailed` (`ChildCancelledException`). They load fine straight after.
- **Default name:** an empty `voiceSatelliteName` gives `hearth`, which collides with the Pi's satellite. A default that includes the model, or a prompt for a name in the Voice plugin, would avoid the suffixed entity IDs.
- **Sensitivity:** rerun the false-wake count at `slightly` before choosing a default for this tablet.

## Open questions / needs hardware

- ~~Does `okay_nabu` trigger reliably from across a room? With music playing?~~ Yes, 1 m to 7 m, quiet and with room music (pass 1, small samples). False wakes at `very`; `slightly` untested. Music played *by the tablet* is still untested.
- ~~Does the first word after the wake sound get swallowed?~~ Yes, by Ava's streaming order rather than by gain recovery (pass 1). The gain recovery itself was not isolated.
- ~~Does the stop word land in a one-second gap in the timer ring?~~ Yes, once (phase 6 on the tablet): Ava stopped the timer 670 ms into the gap. Whether it is also caught over the tone was not isolated.
- ~~Does Home Assistant discover the service from an `NsdManager` registration inside a foreground service?~~ Yes. Keeping the connection for days: not yet soaked.
- Does the service survive under lock task? Not tried. ~~Across the activity being recreated on rotation?~~ Rotation does not recreate it; recreation itself is survived since fix 2.
- ~~Does requesting `RECORD_AUDIO` behave under immersive mode and as the HOME app?~~ Yes.
- How much does the APK grow per ABI? Release arm64 is 81.2 MB with the satellite; no build without it was made to compare. Does the satellite survive R8 at runtime? Not yet installed.
- Does the stock assistant's hotword, if the tablet has one, contend for the microphone?
- Is a linear echo canceller usable after the vendor processing? (Task 9.)
- Behaviour on a second, non-Rockchip tablet with working platform effects.

## Decisions

Made on 2026-10-13:

1. **Packaging**: a fork of Ava, pinned as a submodule. Copying the code into `android/` was the alternative.
2. **Sendspin on Android**: SendspinDroid's native player. The Dart client with a native sink, as follow-up 10 of the requirements spec used to describe, was the alternative.

3. **Auto-brightness on the Apolosign**: left alone. The light sensor does not work, so system auto-brightness holds the panel near minimum; we are not changing that for now.
