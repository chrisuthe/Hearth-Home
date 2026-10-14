# Sendspin on Android — Design

**Date:** 2026-10-14
**Status:** Design. The SendspinDroid library extraction (phase 1) is open as a pull request; nothing in Hearth is implemented.
**Goal:** Specify how the Android build plays Sendspin through SendspinDroid's native player inside `HearthAudioService`, and break the Hearth integration into tasks.
**Tracking:** issue 248.

The choice of SendspinDroid over the Dart client with a native sink was made in `2026-10-13-android-native-voice-satellite-design.md`, under "Sendspin" and "Decisions". This document takes that decision as given and covers the how.

## How to read this

- **verified** — read in source at the commit under [Sources read](#sources-read), or done by building and testing. The file or the command is named inline.
- **assumed** — reasoned from that source or from Android platform documentation, and not settled by code we read or a test we ran.

SendspinDroid paths are relative to its `android/` directory. Before the extraction the player lived under `app/src/main/java/com/sendspindroid/`, written `A/` below. After it, it lives under `player/src/main/java/com/sendspindroid/`, written `P/`.

## Sources read

| Short name | Repository | Commit | Notes |
|---|---|---|---|
| SendspinDroid | `chrisuthe/SendspinDroid` | `3af5666` (`2.0.0-Beta20`) | Still `main`'s HEAD on 2026-10-14, the commit the earlier spec read. Two open pull requests (#323, #324) were not read; #324 changes the decoder path. |
| Hearth | this repository | `dbaf6c3` | |

## What SendspinDroid gives us

Re-read at `3af5666`; everything in the earlier spec still holds. What this design adds:

- **Server-initiated connections already work.** `:shared` has the listener, `SendspinWebSocketServer`: it binds 8928 unless that port is taken, and serves `/sendspin` (**verified**, `shared/src/commonMain/kotlin/com/sendspindroid/sendspin/transport/SendspinWebSocketServer.kt:44-48`, `83`). `InboundConnections` admits one connection at a time with the spec's arbitration and gives every other connection a silent `SendSpin` of its own (**verified**, `A/coordinator/InboundConnections.kt`). `NsdAdvertiser` publishes `_sendspin._tcp` with `path` and `name` TXT records (**verified**, `A/discovery/NsdAdvertiser.kt:12-48`). Port, path and service type are the ones Hearth's Dart service uses (**verified**, `lib/services/sendspin/sendspin_service.dart`, `listenPort`, `wsPath`).
- **Encryption is mandatory.** The client speaks Noise and pairs with servers by PSK; a server without encryption is reported as `ServerLacksEncryption` (**verified**, `A/coordinator/TransportState.kt`). The Dart client implements the same pairing: identity, trust records, an `SP:0…` pairing token, unpaired access (**verified**, `lib/services/sendspin/sendspin_service.dart:17-33`, `sendspin_stores.dart`). Whether the two produce interchangeable tokens is **assumed**; it does not matter here, because no Android install has ever created a Dart identity. The provider guard has always skipped `configure()` on Android (**verified**, `sendspin_service.dart:817-819`).
- **Volume is the device's media stream.** `SyncAudioPlayer.setVolume` is a no-op. The service maps the server's volume onto `STREAM_MUSIC` through `AudioManager`, and hardware volume keys back to the server through a `ContentObserver` (**verified**, `A/sendspin/SyncAudioPlayer.kt:670-683`, `A/playback/PlaybackService.kt:1127-1183`, `1797-1803`). Mute is separate: the `PLAYER` mute reason sets the track's gain to 0 (**verified**, `SyncAudioPlayer.kt:686-707`).
- **The output can be wrapped.** `SyncAudioPlayer` takes a `sinkFactory` that builds its `AudioSink` (**verified**, `SyncAudioPlayer.kt:214-227`). A sink that passes PCM to the real one and copies it is the echo-reference tap, with no change to the player.
- **The pipeline between client and player is still in the app.** Choosing a decoder, the decode thread, discarding chunks from a superseded stream, waiting for the queue to drain on a format change, creating the `SyncAudioPlayer`, applying the sync-error mute, and audio focus all live in `PlaybackService` (**verified**, `A/playback/PlaybackService.kt:242-262`, `1280-1380`, `1836`, `2376`). So does the reconnect loop for dialled connections (`A/coordinator/ConnectionCoordinator.kt`). This is the part a second host would otherwise have to rewrite; see [The engine](#the-engine).
- **No buffer-length setting.** SendspinDroid has a low-memory mode that caps the queue at about ten seconds, and no equivalent of Hearth's `sendspinBufferSeconds` (**verified**, `A/UserSettings.kt`, `PlaybackService.kt:1360-1365`).

## Packaging

### Phase 1: the `:player` library (done, pull request open)

SendspinDroid gains a third Gradle module, `:player` (namespace `com.sendspindroid.player`), beside `:app`, `:shared` and `:conformance-client`. It holds:

| Moved from `:app` | Why |
|---|---|
| The whole `sendspin` package: `SendSpin`, `SendSpinProtocolHandler`, `SyncAudioPlayer`, the decoders, `AudioSink` / `AudioTrackSink`, `MinBufferEstimator`, `SendSpinEndpoint`, the pairing flows | The player |
| `coordinator/InboundConnections`, `coordinator/TransportState` | Server-initiated connections; the client's state type |
| `discovery/NsdAdvertiser` | `_sendspin._tcp` advertisement |
| `logging/LogLevel`, `logging/LogCategory`, and the category loggers as `PlayerLog` | The player's 60 log calls, without the file capture |

Three classes in the `sendspin` package stay in `:app` because they are the app's storage: `EncryptedPrefsTrustStore`, `AndroidPairingConfigStore` and `PairedServers` (its `PairingOutcome` type moves to `:player`). The player reached them, and `UserSettings` and `BuildConfig`, directly. It now reaches them through one interface, `SendSpinHost`, passed to the `SendSpin` constructor. The app implements it as `AppSendSpinHost`, which delegates every call to `UserSettings` and `PairedServers` when the call is made. `AppLog` keeps the file writer and the logcat bridge, and its level is now held by `PlayerLog`, so the app's log setting still gates the player.

Behaviour is meant to be unchanged; the pull request lists the checks. The unit tests stay in `:app` for now, so the same suite runs before and after the move. As a result, two test seams that were `internal` (`SendSpin.handshakeTimeoutMs`, `SendSpinProtocolHandler.installEncryptedChannel`) are now public.

Link: https://github.com/chrisuthe/SendspinDroid/pull/PR_NUMBER

### Phase 2: the engine

Before Hearth can host the player, the pipeline in `PlaybackService` moves into `:player` as one class, written here as `SendspinEngine`. It owns:

- the listener, `InboundConnections` and the advertiser, or one dialled client;
- the decode pipeline and its generations, the `SyncAudioPlayer`, and format changes;
- the sync-error mute;
- volume, through an interface the host implements (`STREAM_MUSIC` in both apps);
- a `StateFlow` of what a UI needs: connection state, server name, volume, mute, codec and format, buffer depth, clock offset, output delay, metadata and artwork.

`PlaybackService` keeps what only an app needs: the Media3 session, the notification, Android Auto, the server list, discovery and audio focus. It becomes the engine's first host, and Hearth's service the second. That is a behaviour-sensitive refactor of SendspinDroid and is its own pull request there, with SendspinDroid's tests carried across.

The alternative is for Hearth to write its own copy of the pipeline against `:player`. It is about 400 lines of subtle threading that SendspinDroid has already debugged (the comments at `PlaybackService.kt:242-262` record two races), and two copies would drift. We do not take it.

### Phase 3: pinning it in Hearth

As with the Ava fork:

- SendspinDroid is a submodule at `android/third_party/sendspindroid`, pinned to a tag (`player-v<n>` or a release tag, whichever SendspinDroid cuts first).
- Hearth builds `:shared` and `:player` from its own scripts under `android/sendspin/shared` and `android/sendspin/player`, with source sets pointing into the submodule, and includes them from `android/settings.gradle.kts` as `:sendspin-shared` and `:sendspin-player`.
- The scripts take their SDK levels from `:app`, as `android/ava/satellite/build.gradle.kts` does.

Differences from Ava:

- **`:shared` is Kotlin Multiplatform with `expect`/`actual` declarations** (**verified**, `Platform.kt` in `commonMain` against `Platform.android.kt` in `androidMain`, and others). It cannot be compiled as a plain Android library. Hearth's script applies `org.jetbrains.kotlin.multiplatform` and `com.android.kotlin.multiplatform.library` with only the `androidLibrary` target, and points `commonMain`, the intermediate `jvmShared` and `androidMain` at the submodule. That this builds under Hearth's AGP 9.1.0 and Kotlin 2.4.0 (SendspinDroid uses 9.0.1 and 2.3.0, **verified**, `android/build.gradle.kts` in both) is **assumed** until phase 3 builds it.
- **No version catalog.** SendspinDroid writes dependency versions inline in each `build.gradle.kts` (**verified**). Hearth's scripts copy them by hand, and a tag bump means diffing those files. Hearth's `CLAUDE.md` gets the same note it has for Ava.
- **No `UPSTREAM_PIN` and no drift check.** SendspinDroid is not a fork; we own it. The submodule is bumped by hand when SendspinDroid tags, like the Ava pin, and Renovate does not see it.
- **R8.** SendspinDroid's keep and `-dontwarn` rules for Ktor, OkHttp, BouncyCastle and kotlinx are in `app/proguard-rules.pro` (**verified**). The engine pull request moves the ones the player needs into `:player`'s `consumer-rules.pro`, so Hearth's release build inherits them. Until then Hearth's script lists them. That they are sufficient is **assumed** until a release APK plays.
- **Size.** Ktor's server and client, BouncyCastle and OkHttp join the APK. SendspinDroid already strips BouncyCastle's unused resources (about 1.2 MB) and Ktor's `kotlin-reflect` and `jansi` (about 590 KB) (**verified**, `app/build.gradle.kts`, `shared/build.gradle.kts`); Hearth's scripts and packaging options do the same. The growth is unmeasured.

**Licences.** SendspinDroid is MIT (**verified**, `LICENSE`). Ktor, OkHttp and kotlinx are Apache-2.0, BouncyCastle is MIT-style (**assumed**, from the publishers, not opened). All go into the credits list that issue 250 creates.

## The service

`HearthAudioService` hosts the engine beside the voice satellite. Today it shuts down when the voice config is missing or `RECORD_AUDIO` is not granted (**verified**, `android/app/src/main/kotlin/com/hearth/hearth/voice/HearthAudioService.kt:74-112`). That changes:

- The service runs when `voiceSatelliteEnabled` or `sendspinEnabled` is set, and stops when neither is.
- Foreground type: `mediaPlayback` always, plus `microphone` only when voice is on and the permission is granted. Sendspin alone needs no microphone and no prompt.
- Start stays Dart-driven, from the visible activity. The start command carries two optional sections, voice and Sendspin, and either can be absent. A Sendspin settings change restarts only the engine, not the satellite, so a playing stream survives a wake-word change and the other way round.
- The partial wake lock and the Wi-Fi lock the satellite takes cover Sendspin too. SendspinDroid holds a 30-minute playback wake lock and refreshes it (**verified**, `PlaybackService.kt:2370-2385`); Hearth's service-lifetime lock replaces it.
- **Audio focus.** Hearth is a single-app kiosk. Its other players are media_kit, in the same process. The engine does not request focus in Hearth. Losing focus to a call or another app is not handled in the first version (**assumed** adequate on a dedicated tablet; listed under open questions).
- **Settings and storage.** `HubConfig` stays the source of truth, as for voice. The start command carries the player name, server URL, unpaired access, output delay and last-playback server. When a server changes the output delay, or a new server becomes the last one to play, the service reports it and Dart writes `HubConfig`, as it does on the Pi through `onOutputDelayPersist` and `onLastPlaybackServer` (**verified**, `sendspin_service.dart:827-837`).
- **Secrets are the exception.** The device's key pair, the pairing PSK and the trust records stay out of `hub_config.json`, as the Dart client already keeps them out (**verified**, `sendspin_stores.dart:12`). Hearth's `SendSpinHost` keeps them in the app's private files directory under `sendspin/`. This is the one thing the service persists. Clearing Hearth's data therefore unpairs it from every server, as on the Pi when its identity file is deleted.
- **Dynamic pairing code** (a code shown on the device's screen) is off in the first version: `PairingConfigStore` reports it disabled. Unpaired access and the pairing token cover setup, as on the Pi.

## Platform channel

One `MethodChannel` and one `EventChannel` named `com.hearth/sendspin`, separate from `com.hearth/voice` so neither feature's Dart side depends on the other.

| Direction | Name | Payload |
|---|---|---|
| Dart → native | `configure` | enabled, player name, server URL, unpaired access, output delay ms, last-playback server id |
| Dart → native | `setVolume` | 0.0–1.0. Sets `STREAM_MUSIC` and reports it to the server. |
| Dart → native | `getVolume` | → 0.0–1.0 from `STREAM_MUSIC`, for the system slider when Sendspin is off |
| Dart → native | `pairingInfo` | → client id, pairing token, paired server count |
| native → Dart | `state` | connection state, server name, volume, muted, codec, sample rate, channels, buffer depth, clock offset, output delay, metadata |
| native → Dart | `outputDelay` | ms. Dart writes `sendspinOutputDelayMs`. |
| native → Dart | `lastPlaybackServer` | server id. Dart writes `sendspinLastPlaybackServerId`. |
| native → Dart | `health` | listener bind failed, mDNS registration failed, server lacks encryption |

Not on the channel, on purpose:

- **The voice mute.** It is a call inside the service. See [Muting at wake](#muting-at-wake).
- **Artwork bytes.** The Media screen already loads art from the metadata URL. Binary artwork is a later addition if a server sends only that.

## Dart side

- **`sendspinServiceProvider` picks a backend.** `SendspinService` keeps its public surface (`state`, `stateStream`, `pairingInfo`, `setVolume`, `setLocalDuckFactor`) and gains a second implementation for Android that drives the channel. The Dart client, the ALSA sink, `flac_ffi.dart` and `bonsoir` are never constructed on Android. The Pi and desktop paths do not change.
- **The provider guard goes** (`sendspin_service.dart:817-819`). `flac_ffi.dart`'s missing Android branch and the `com.hearth/sendspin_audio` sink stay unimplemented on Android, because nothing reaches them.
- **Settings plugin.** `sendspinBufferSeconds` is hidden on Android, since the engine has no equivalent. Everything else renders on both surfaces unchanged.
- **The system volume slider** (`hub_shell.dart`, `_SystemVolumeSlider`) reads and sets ALSA on Linux. On Android it uses `getVolume` and `setVolume`, so one slider controls all of Hearth's media volume on the tablet, as the ALSA master does on the Pi. The two `amixer` helpers stay Linux-only.
- **`VoiceDucker`** keeps calling `setLocalDuckFactor`; the Android backend ignores it, because the audio coordinator has already muted the engine natively one HA round trip earlier.
- **State consumers** (`mini_stats_row.dart`, `media_screen.dart`, the slider) read `SendspinPlayerState` from `sendspin_dart`. The Android backend builds that same type from the `state` event, so they do not change.

## Muting at wake

The voice design's `AudioCoordinator` table says Sendspin is "muted at once" when the wake word fires (`2026-10-13-android-native-voice-satellite-design.md`, "Echo and ducking"). Concretely:

- SendspinDroid adds a fourth mute reason, `VOICE`, in the engine pull request. Like `SYNC` and `INTERRUPTION` it is local: only `PLAYER` is reported in `client/state` (**verified**, `SyncAudioPlayer.kt:686-694`), so other rooms in the group are unaffected.
- The coordinator calls `engine.setVoiceMuted(true)` from the detector's callback. `SyncAudioPlayer.setMuted` is main-thread only (**verified**, `SyncAudioPlayer.kt:697-702`), so the engine posts it to the main looper. The cost is at most one turn of the main loop, not a channel round trip.
- The gain change applies to audio the mixer has not yet taken. Audio already in the `AudioTrack` buffer still plays, so the mute lands within one track buffer (**assumed**, from `AudioTrack.setVolume`'s documentation; to be measured on the tablet).
- The player keeps draining in sync while muted, so the unmute at idle is exactly in time (**verified**, the comment at `SyncAudioPlayer.kt:697-702`, and `SyncAudioPlayerMuteTest`).
- **Later, the echo reference:** the engine takes a `sinkFactory` from its host and Hearth wraps `AudioTrackSink` to copy what it writes. That is phase 9 of the voice design and needs nothing more from SendspinDroid.

## Testing

- **SendspinDroid**: its own JVM suite, run on every pull request there (`testDebugUnitTest`, `:shared:testAndroidHostTest`, **verified**, `.github/workflows/pr-tests.yml`). The engine pull request carries the `playback/` pipeline tests (`DecoderPipelineIntegrationTest`, `StreamStartDecoderPipelineTest`, `PauseFlushTest` and others) with the code.
- **Hearth, Dart**: the Android backend against a fake channel — `state` decoding into `SendspinPlayerState`, the `outputDelay` and `lastPlaybackServer` write-backs, `setLocalDuckFactor` ignored, and the provider choosing a backend by platform.
- **Hearth, build**: `flutter build apk --debug` and `scripts/build-android-apk.sh` with the submodule, checked with `dexdump` for the player's classes as the satellite was.
- **Hardware**: the items under [Open questions](#open-questions--needs-hardware).

## Phases

Each line is one task. Sizes are relative. Phases 1 and 2 are pull requests in SendspinDroid; the rest are Hearth tasks.

| # | Task | Where | Size | Depends on |
|---|---|---|---|---|
| 1 | Extract `:player` from `:app`, behaviour unchanged. Pull request open; tag after merge. | SendspinDroid | Medium | — |
| 2 | Move the pipeline into a `SendspinEngine` in `:player`, with the volume interface, the `VOICE` mute reason, `consumer-rules.pro`, and the pipeline tests. `PlaybackService` becomes its host. Tag. | SendspinDroid | Large | 1 |
| 3 | Pin SendspinDroid as a submodule; Hearth-owned scripts for `:sendspin-shared` and `:sendspin-player`; the APK builds with the classes in it; `CLAUDE.md` maintenance note | Hearth | Small-medium | 2 |
| 4 | `HearthAudioService` hosts the engine: start with voice and Sendspin as independent sections, foreground type by feature, `SendSpinHost` with private-file storage, `com.hearth/sendspin` | Hearth | Medium | 3 |
| 5 | Dart: Android backend for `SendspinService`, remove the provider guard, hide buffer length on Android, the system slider on `STREAM_MUSIC`, and the requirements spec rows | Hearth | Medium | 4 |
| 6 | Hardware pass: Music Assistant finds the tablet, pairing, playback in a group with the Pi, volume from both sides, output-delay persistence across a restart, and a release APK | Hearth | Small | 5 |
| 7 | The audio coordinator's Sendspin mute (voice design, task 7) | Hearth | Small | 6, voice task 7 |
| 8 | Dialled mode (`sendspinServerUrl`) with reconnect | Hearth and SendspinDroid | Small-medium | 6 |

Phase 6 gates the rest. The voice design's task 8 ("Sendspin on Android through SendspinDroid's player") is phases 1 to 6 here.

## Open questions / needs hardware

- Does Music Assistant discover and pair with an `NsdManager` registration made inside Hearth's foreground service, and keep the connection through Doze and hours of idle?
- Does sync hold against the Pi in one group on the Rockchip tablet's output path? SendspinDroid has been run on phones; this tablet is untested.
- How long after `setVoiceMuted(true)` is the speaker actually silent? This sets whether the mute beats the wake sound.
- Does anything on a dedicated kiosk take audio focus (a call, the stock assistant), and does the engine then need SendspinDroid's interruption policy?
- How much does the APK grow, per ABI and after R8?
- Is `STREAM_MUSIC` the stream media_kit plays on, so one slider truly covers both? (**assumed**; libmpv's Android audio output was not read.)

## Decisions

Made on 2026-10-14:

1. **Library seam**: one host interface (`SendSpinHost`) for settings, keys and pairing news, passed to the client's constructor, rather than a process-wide settings object the library reads.
2. **Tests stay in SendspinDroid's `:app` for phase 1**, so the move is checked by an unchanged suite. They move with the engine in phase 2.
3. **The engine lives in SendspinDroid**, not in Hearth. Both apps host it.
4. **Secrets in private files**, not in `hub_config.json`; everything else in `HubConfig`.
5. **Server-initiated first.** Dialled mode is phase 8.
