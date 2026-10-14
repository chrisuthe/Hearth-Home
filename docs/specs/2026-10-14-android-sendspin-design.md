# Sendspin on Android — Design

**Date:** 2026-10-14
**Status:** Phases 1 and 2, in SendspinDroid, are merged. Phases 3 to 5 are done in Hearth: the player is pinned and built into the APK, `HearthAudioService` hosts the engine, and the Dart side drives it over `com.hearth/sendspin`. Phase 6, the hardware pass, ran on the tablet on 2026-10-14 for everything that does not need a person in the room; see [Hardware pass 1](#hardware-pass-1-phase-6).
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

### Phase 1: the `:player` library (merged)

SendspinDroid gains a third Gradle module, `:player` (namespace `com.sendspindroid.player`), beside `:app`, `:shared` and `:conformance-client`. It holds:

| Moved from `:app` | Why |
|---|---|
| The whole `sendspin` package: `SendSpin`, `SendSpinProtocolHandler`, `SyncAudioPlayer`, the decoders, `AudioSink` / `AudioTrackSink`, `MinBufferEstimator`, `SendSpinEndpoint`, the pairing flows | The player |
| `coordinator/InboundConnections`, `coordinator/TransportState` | Server-initiated connections; the client's state type |
| `discovery/NsdAdvertiser` | `_sendspin._tcp` advertisement |
| `logging/LogLevel`, `logging/LogCategory`, and the category loggers as `PlayerLog` | The player's 60 log calls, without the file capture |

Three classes in the `sendspin` package stay in `:app` because they are the app's storage: `EncryptedPrefsTrustStore`, `AndroidPairingConfigStore` and `PairedServers` (its `PairingOutcome` type moves to `:player`). The player reached them, and `UserSettings` and `BuildConfig`, directly. It now reaches them through one interface, `SendSpinHost`, passed to the `SendSpin` constructor. The app implements it as `AppSendSpinHost`, which delegates every call to `UserSettings` and `PairedServers` when the call is made. `AppLog` keeps the file writer and the logcat bridge, and its level is now held by `PlayerLog`, so the app's log setting still gates the player.

Behaviour is meant to be unchanged; the pull request lists the checks. The unit tests stay in `:app` for now, so the same suite runs before and after the move. As a result, two test seams that were `internal` (`SendSpin.handshakeTimeoutMs`, `SendSpinProtocolHandler.installEncryptedChannel`) are now public.

Link: https://github.com/chrisuthe/SendspinDroid/pull/326, merged as `92fdc211` after a rebase onto #324. Not tagged.

### Phase 2: the engine (merged)

The pipeline in `PlaybackService` moves into `:player` as `SendSpinEngine` (`P/playback/SendSpinEngine.kt`). It owns (**verified**, by the pull request below):

- the decode worker, its channel, the stream generations, and the stream/start handling (`StreamStartAction`);
- creating, reusing and replacing the `SyncAudioPlayer`, including a format change that plays out the old format first;
- the mutes: `INTERRUPTION` and `VOICE` are held and applied to every later player, `PLAYER` is read from the host when a player is created, `SYNC` stays with its player;
- the server's stopped, paused and playing states as applied to the player.

The host passes on the client's stream callbacks (`onStreamStart`, `onAudioChunk`, `onStreamClear`, `onStreamEnd`, `onSyncMuteChanged`, `onNetworkChanged`), sets `engine.client` to the client being played from, calls `endStream()` whenever that client is not Ready and `releasePlayer()` when it goes Idle, and hears back through `SendSpinEngine.Listener` (stream started, player changed, player state). The stream callbacks are thread-safe; every other engine method is main-thread only.

The connection side stays with each host: the listener, `InboundConnections`, the advertiser, choosing which client to play from, the reconnect loop. So do device volume and audio focus. In SendspinDroid those are entangled with its connection modes, reconnect coordinator and notification, and are app policy rather than shared machinery. Hearth needs only the server-initiated half, about 100 lines of glue over classes already in `:player` (**verified**, `A/playback/PlaybackService.kt`, `startAdvertising`, `stopAdvertising`, `newInboundClient`, `onServerAdmitted`, `useClient`), and about 70 lines for `STREAM_MUSIC` (`initializeVolumeControl`, `setVolume`). See [The service](#the-service).

`PlaybackService` is the engine's first host, and Hearth's service the second. The pull request also adds the `VOICE` mute reason and moves the player's R8 rules into `player/consumer-rules.pro`. It moves the pipeline tests to `:player`, where `DecoderPipelineIntegrationTest` now drives the real engine instead of a copy of the service's callbacks. 860 `:app`, 40 `:player` and 611 `:shared` tests pass, debug and release build, and it has not been run on a device.

Link: https://github.com/chrisuthe/SendspinDroid/pull/329, merged as `0e6c67c5`. Not tagged; Hearth pins that commit in phase 3.

The alternative was for Hearth to write its own copy of the pipeline against `:player`. That is about 400 lines of subtle threading that SendspinDroid has already debugged (the comments at `PlaybackService.kt:242-262` record two races), and two copies would drift. We did not take it.

### Phase 3: pinning it in Hearth

As with the Ava fork:

- SendspinDroid is a submodule at `android/third_party/sendspindroid`, pinned to commit `0e6c67c5`, the merge of phase 2. There is no tag yet. A `v*` tag there runs SendspinDroid's release workflow and publishes an app release (**verified**, `.github/workflows/release.yml`), so a tag is cut only when there is a reason to; the pin moves to it then.
- Hearth builds `:shared` and `:player` from its own scripts under `android/sendspin/shared` and `android/sendspin/player`, with source sets pointing into the submodule, and includes them from `android/settings.gradle.kts` as `:sendspin-shared` and `:sendspin-player`.
- The scripts take their SDK levels from `:app`, as `android/ava/satellite/build.gradle.kts` does.
- **Done.** `0e6c67c5` is the merge of pull request 329 (**verified**, `git log -1` in the submodule). The module layout read there: `:shared` has `commonMain`, `jvmShared`, `androidMain` and `jvmMain` sources, Kotlin only; `:player` has a bare manifest, sources under `src/main/java`, and `consumer-rules.pro`; neither imports AndroidX (**verified**). `:app` depends on `:sendspin-player`.

Differences from Ava:

- **`:shared` is Kotlin Multiplatform with `expect`/`actual` declarations** (**verified**, `Platform.kt` in `commonMain` against `Platform.android.kt` in `androidMain`, and others). It cannot be compiled as a plain Android library. Hearth's script applies `org.jetbrains.kotlin.multiplatform` and `com.android.kotlin.multiplatform.library` with only the `androidLibrary` target, and points `commonMain`, the intermediate `jvmShared` and `androidMain` at the submodule. It builds under Hearth's AGP 9.1.0 and Kotlin 2.4.0 (SendspinDroid uses 9.0.1 and 2.3.0) (**verified**, `flutter build apk --debug` and `scripts/build-android-apk.sh`). Hearth's script leaves out upstream's `jvm()` target, which only the conformance harness uses, and its test source sets. It compiles both modules for JVM 17, Hearth's JDK, where upstream uses a JDK 21 toolchain; the sources need nothing newer (**verified**, they build). `android/settings.gradle.kts` declares the multiplatform and KMP-library plugins at Hearth's versions. `:player` applies `org.jetbrains.kotlin.android` itself, because Hearth sets `android.builtInKotlin=false` and upstream relies on AGP 9's built-in Kotlin.
- **No version catalog.** SendspinDroid writes dependency versions inline in each `build.gradle.kts` (**verified**). Hearth's scripts copy them by hand, and moving the pin means diffing those files. Hearth's `CLAUDE.md` gets the same note it has for Ava.
- **No `UPSTREAM_PIN` and no drift check.** SendspinDroid is not a fork; we own it. The submodule is bumped by hand, like the Ava pin, and Renovate does not see it.
- **R8.** SendspinDroid's keep and `-dontwarn` rules for Ktor, OkHttp, BouncyCastle and kotlinx are in `app/proguard-rules.pro` (**verified**). The engine pull request moves the ones the player needs into `:player`'s `consumer-rules.pro` (OkHttp, coroutines, serialization, Ktor), so Hearth's release build inherits them. SendspinDroid's release build still keeps OkHttp's class names with the rules moved (**verified**, `assembleRelease` and the dex). In Hearth, R8 accepts them: the release build completes with no missing-class errors (**verified**, `scripts/build-android-apk.sh`). That they are sufficient at runtime is **assumed** until a release APK plays.
- **Nothing referenced the player in phase 3, so R8 dropped all of it**: the first release build had no `com.sendspindroid` class (**verified**, `dexdump`). `android/app/proguard-rules.pro` kept `SendSpinEngine` and `SendSpin` with their public members until phase 4 referenced them; phase 4 deleted the file. With it, both APKs carry `com.sendspindroid.playback.SendSpinEngine` and `com.sendspindroid.sendspin.SendSpin` (**verified**, `dexdump` of every `classes*.dex`).
- **Size.** Ktor's server and client, BouncyCastle and OkHttp join the APK. SendspinDroid already strips BouncyCastle's unused resources (about 1.2 MB) and Ktor's `kotlin-reflect` and `jansi` (about 590 KB) (**verified**, `app/build.gradle.kts`, `shared/build.gradle.kts`); Hearth's scripts and packaging options do the same: `:app` has the same two `packaging` excludes, and neither APK contains a picnic table or `CertPathReviewerMessages` (**verified**, `unzip -l`), and `kotlin-reflect` and `jansi` are absent from `:app`'s release runtime classpath (**verified**, `:app:dependencies`).

  Measured at `0e6c67c5` (**verified**):

  | APK | Before | After | Growth |
  |---|---|---|---|
  | `flutter build apk --debug` | 248,817,919 B | 261,031,328 B | +12.2 MB |
  | `scripts/build-android-apk.sh` (release, arm64, R8) | 81,244,316 B | 81,991,051 B | +0.75 MB |

  The release figure is with the keep rule above. Without it the growth was 0.63 MB, all library code that `consumer-rules.pro` keeps whole (`okhttp3.**`, `okio.**`), so the player's own reachable code costs about 0.11 MB. Phase 4's real references should land near the figure with the rule.

  With phase 4's real references and no keep rule, the release APK is 82,491,328 B, 0.50 MB more than with the rule (**verified**, `scripts/build-android-apk.sh`). R8 now renames the player's classes, as it does Ava's, so look them up in `build/app/outputs/mapping/release/mapping.txt` first; the short names change from build to build. `SendSpinEngine` and `SendSpin` are in the release dex under their mapped names, and under their own in the debug dex (**verified**, `dexdump` of every `classes*.dex`). `NsdAdvertiser` and `SendspinWebSocketServer` were merged into their callers; their methods appear in the mapping under other classes (**verified**).

**Licences.** SendspinDroid is MIT (**verified**, `LICENSE`). Comparing `:app:dependencies --configuration releaseRuntimeClasspath` before and after found these new libraries, each checked at its source (**verified**): Ktor 3.1.1, OkHttp 4.12.0, Okio 3.10.2, Typesafe Config 1.4.3 (Apache-2.0, POM licences); kotlinx-io and kotlinx-coroutines-slf4j (Apache-2.0, POM licences, folded into the existing Kotlin entry); BouncyCastle `bcprov-jdk18on` 1.80 (Bouncy Castle Licence, MIT text, from `org.bouncycastle.LICENSE` in the jar); SLF4J API 2.0.16 (MIT, `META-INF/LICENSE.txt` in the jar). Typesafe Config and SLF4J come in through Ktor's server. OkHttp also carries the Public Suffix List (`okhttp3/internal/publicsuffix/publicsuffixes.gz`, MPL-2.0, per its `NOTICE`), which lands in both APKs unmodified (**verified**, `unzip -l`) and has its own entry. Each has an entry in `assets/licenses/notices.json` (platform `android`), and `THIRD_PARTY_NOTICES.md` is regenerated (`2026-10-14-third-party-notices-design.md`). `third_party_notices_test.dart` catches a missing entry for the submodule and, since phase 3, for any module under `android/sendspin/`. It does not catch the Maven libraries, so they are checked against `:app:dependencies` by hand.

## The service

`HearthAudioService` hosts the engine beside the voice satellite. Today it shuts down when the voice config is missing or `RECORD_AUDIO` is not granted (**verified**, `android/app/src/main/kotlin/com/hearth/hearth/voice/HearthAudioService.kt:74-112`). That changes:

- The service runs when `voiceSatelliteEnabled` or `sendspinEnabled` is set, and stops when neither is.
- **What the service writes itself**, after `PlaybackService`: the `SendspinWebSocketServer` listener, `InboundConnections`, the `NsdAdvertiser`, a new `SendSpin` per inbound connection with the current volume and mute, and switching `engine.client` to the admitted one. Then the volume mapping onto `STREAM_MUSIC`, both ways. The engine does none of these.
- Foreground type: `mediaPlayback` always, plus `microphone` only when voice is on and the permission is granted. Sendspin alone needs no microphone and no prompt.
- Start stays Dart-driven, from the visible activity. Each feature configures itself over its own channel: `start` on `com.hearth/voice`, `configure` on `com.hearth/sendspin`. Whichever arrives first starts the service, and the service stops when both are off. A Sendspin `configure` rebuilds only the engine, not the satellite, so a playing stream survives a wake-word change and the other way round.
- The partial wake lock and the Wi-Fi lock the satellite takes cover Sendspin too. SendspinDroid holds a 30-minute playback wake lock and refreshes it (**verified**, `PlaybackService.kt:2370-2385`); Hearth's service-lifetime lock replaces it.
- **Audio focus.** Hearth is a single-app kiosk. Its other players are media_kit, in the same process. The engine does not request focus in Hearth. Losing focus to a call or another app is not handled in the first version (**assumed** adequate on a dedicated tablet; listed under open questions).
- **Settings and storage.** `HubConfig` stays the source of truth, as for voice. `configure` carries the player name, server URL, unpaired access, output delay and last-playback server. When a server changes the output delay, or a new server becomes the last one to play, the service reports it and Dart writes `HubConfig`, as it does on the Pi through `onOutputDelayPersist` and `onLastPlaybackServer` (**verified**, `sendspin_service.dart:827-837`).
- **Secrets are the exception.** The device's key pair, the pairing PSK and the trust records stay out of `hub_config.json`, as the Dart client already keeps them out (**verified**, `sendspin_stores.dart:12`). Hearth's `SendSpinHost` keeps them in the app's private files directory under `sendspin/`. This is the one thing the service persists. Clearing Hearth's data therefore unpairs it from every server, as on the Pi when its identity file is deleted.
- **Dynamic pairing code** (a code shown on the device's screen) is off in the first version: `PairingConfigStore` reports it disabled. Unpaired access and the pairing token cover setup, as on the Pi.

## mDNS advertisement

- On Android the engine advertises, not Dart: `NsdAdvertiser` registers `_sendspin._tcp` through `NsdManager` with the port the listener actually bound, `path=/sendspin` and `name=<player name>`, and holds a `WifiManager.MulticastLock` while it does (**verified**, `P/discovery/NsdAdvertiser.kt:12-48`, `141-155`). `bonsoir` stays the Pi and desktop path. The multicast permission is already in Hearth's manifest.
- It runs inside the foreground service, beside the satellite's `_esphomelib._tcp` registration, so both live as long as the service does.
- When the network changes, SendspinDroid re-registers, or re-binds the listener if that failed (**verified**, `A/playback/PlaybackService.kt`, `advertiseAgainAfterNetworkChange`). That trigger stays in `PlaybackService`, so Hearth's service registers its own network callback and does the same.
- A bind or registration failure is reported as a `health` event, which the Sendspin plugin shows, as SendspinDroid shows "waiting" only over a working advertisement.
- Advertising and dialling are exclusive, as the spec requires ("Clients MUST NOT manually connect to servers while advertising", quoted at `P/discovery/NsdAdvertiser.kt:20-21`). With `sendspinServerUrl` set the engine does not advertise; that is phase 8.

## Platform channel

One `MethodChannel` and one `EventChannel` named `com.hearth/sendspin`, separate from `com.hearth/voice` so neither feature's Dart side depends on the other.

| Direction | Name | Payload |
|---|---|---|
| Dart → native | `configure` | enabled, player name, server URL, unpaired access, output delay ms, last-playback server id. Starts the service if it is not running; with `enabled` false, stops the engine and, if voice is off too, the service. |
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

## As built (phases 4 and 5)

Built and unit-tested on 2026-10-14. What the tablet confirmed is under [Hardware pass 1](#hardware-pass-1-phase-6); anything not listed there is still **assumed**.

- **Service lifecycle.** Each channel puts its feature's request in `HearthAudioService`'s companion and either hands it to the running service or starts one. The service records what is wanted on the main thread, goes foreground with `mediaPlayback`, adding `microphone` only while voice is wanted, and rebuilds only the feature whose request arrived, under `lifecycleMutex`. When the last job finds neither feature wanted it stops with `stopSelfResult`, so a start that arrived meanwhile keeps it. The wake and Wi-Fi locks are held while either feature runs. Voice `stop` no longer stops the service (`HearthAudioService.stopVoice`). The notification now reads "Hearth audio" and carries a line from each running feature.
- **The glue** is `SendspinPlayer` (`android/app/src/main/kotlin/com/hearth/hearth/sendspin/`), ported from `PlaybackService` as listed under [The service](#the-service). `InboundConnections` runs on a scope that a reconfigure does not cancel, because it destroys a displaced client after its goodbye, which can land after the listener has closed. The network trigger is a default-network callback that re-advertises, or re-binds a listener that never came up, when the network or its addresses change. Hardware volume reaches the server through a `ContentObserver` on `Settings.System`, as SendspinDroid does.
- **`SendSpinHost`** (`HearthSendSpinHost`): `lowMemoryMode` off, `highPowerMode` on (a kiosk on mains power), preferred codec `opus` (SendspinDroid's default), the server's output delay held and reported. `SendspinSecrets` keeps the private key, the pairing PSK and the trust records in `filesDir/sendspin/` (`identity`, `pairing_psk`, `trust.json`), written through a temporary file and a rename, and refuses to overwrite an unreadable key. It reports `storageIsEncrypted` false: the files are private to the app but not Keystore-encrypted. The server's `PLAYER` mute is held for the life of the process, not persisted.
- **Channel additions** beyond the table: the `state` event also carries `pairedServers` and `group` (id, name, playback state), and Dart reloads `pairingInfo` when the count changes; two more `health` codes, `dialledUnsupported` (a server URL is set; nothing is advertised) and `secretsUnreadable`. `clockOffsetMs` carries the clock filter's error in ms, -1 until it is ready, which is what the Media screen's sync badge reads on the Pi.
- **Dart.** `AndroidSendspinService` (`lib/services/sendspin/android_sendspin_service.dart`) implements `SendspinService`'s interface, so its consumers are unchanged; `sendspinNative` picks it in the provider. It is configured when Sendspin is off too, so the native side can stop. The Sendspin plugin hides Buffer Size on Android on both surfaces and shows the last `health` event in the sidebar.

## Hardware pass 1 (phase 6)

2026-10-14, on the Apolosign (RK3576, Android 16), driven over adb, the `:8090` API and Home Assistant's media player services against the house Music Assistant ("MA Production"). The tablet ran with voice enabled throughout unless a step says otherwise. A debug APK first, then the release APK (R8, arm64) installed over it with its data kept.

| Check | Result |
|---|---|
| Server URL set (the tablet's existing config, `ws://…:8927`) | **verified**: no advertisement, `dialledUnsupported` health event |
| Advertising after the URL was cleared | **verified**: listener on 8928 `/sendspin`; `NsdAdvertiser` registered `_sendspin._tcp` with `name` and `path` TXT and the multicast lock |
| Discovery and admission | **verified**: Music Assistant connected within a second of the registration, completed the Noise handshake on the Sentinel PSK (unpaired access), and was admitted through `InboundConnections`; it appears in Home Assistant as `media_player.kitchenscreen` |
| Playback | **verified**: opus 48 kHz stereo, `PLAYING` about 1.1 s after `stream/start`; Android shows Hearth's `USAGE_MEDIA` AudioTrack started on the speaker. The Media screen's badge read "Sendspin ±<1ms", so `state` events reach Dart as `streaming` |
| Pause and resume from HA | **verified**: `stream/end`, the player idles and its track pauses; resume reuses the warm player, `PLAYING` 340 ms after `stream/start` |
| Volume, server to device | **verified**: 40 % from HA set `STREAM_MUSIC` to 40/100 and was reported back |
| Volume, device to server | **verified after a fix**: hardware keys were reported one step low (42 on the device, 41 at the server), because `SendSpin.setVolume` truncates `volume * 100` and 41/100 is 40.99… as a float. `SendspinPlayer.reportVolume` now sends the half step; after the fix the device and HA agree (40/0.40; 37 on release) |
| Voice off and on mid-stream | **verified**: foreground type 130 → 2 → 130 (`microphone|mediaPlayback` to `mediaPlayback` and back), the AudioTrack kept playing, no stream end |
| Sendspin off and on with voice running | **verified**: the advertisement withdrawn, goodbyes sent, the track gone, the service kept at `0x82`, the satellite not rebuilt; on again, 8928 bound afresh and Music Assistant was readmitted within a second |
| `lastPlaybackServer` write-back | **verified**: `sendspinLastPlaybackServerId` in `hub_config.json` holds the server's id |
| Restart (force-stop, launch) | **verified**: no new `identity` or `pairing_psk` was created, and the same server was readmitted |
| Notification | **verified**: "Hearth audio — Listening for the wake word · Sendspin connected to MA Production (…)" |
| Release APK | **verified after a fix**: it crashed when Home Assistant asked the satellite for its device info, because R8 stripped the protobuf-lite fields of `com.example.esphomeproto` (a voice-satellite gap present since the satellite landed). `android/ava/esphomeproto/src/main/resources/META-INF/proguard/esphomeproto.pro` keeps them. Then: voice connected, Sendspin advertised, handshook (BouncyCastle survives R8), played and moved volume both ways |

Not run, because each needs someone in the room or the Music Assistant UI: sync against the Pi in one group, pairing by token, an output delay set by the server and its persistence, a spoken voice exchange on the release build, and Doze over hours of idle.

Found, not fixed here:

- `client/hello` names the product "SendSpinDroid": `MessageBuilder` in SendspinDroid's `:shared` hardcodes `product_name`, and `manufacturer` is `Build.MANUFACTURER` ("Electron" on this tablet). A SendspinDroid change, so `SendSpinHost` can supply both.
- Stopping the player sends `client/goodbye` reason `another_server` before `shutdown`: `InboundConnections.close()` releases the held connection with `leaveForAnotherServer()`. Same in SendspinDroid's app.
- The volume truncation is in SendspinDroid's `setVolume`; its own app has the same off-by-one.

## Muting at wake

The voice design's `AudioCoordinator` table says Sendspin is "muted at once" when the wake word fires (`2026-10-13-android-native-voice-satellite-design.md`, "Echo and ducking"). Concretely:

- SendspinDroid adds a fourth mute reason, `VOICE`, in the engine pull request (**verified**, pull request 329). Like `SYNC` and `INTERRUPTION` it is local: only `PLAYER` is reported in `client/state` (**verified**, `SyncAudioPlayer.kt:686-694`), so other rooms in the group are unaffected.
- The coordinator calls `engine.setMuted(VOICE, true)` from the detector's callback, through `AudioCoordinator.addMute` in `android/.../voice/AudioCoordinator.kt`. Engine methods are main-thread only, as `SyncAudioPlayer.setMuted` is (**verified**, `SyncAudioPlayer.kt:697-702`), so the coordinator posts the call to the main looper. A mute set between streams is held and applied to the next player (**verified**, `SendSpinEngineTest`). The cost is at most one turn of the main loop, not a channel round trip.
- The gain change applies to audio the mixer has not yet taken. Audio already in the `AudioTrack` buffer still plays, so the mute lands within one track buffer (**assumed**, from `AudioTrack.setVolume`'s documentation; to be measured on the tablet).
- The player keeps draining in sync while muted, so the unmute at idle is exactly in time (**verified**, the comment at `SyncAudioPlayer.kt:697-702`, and `SyncAudioPlayerMuteTest`).
- **Later, the echo reference:** the engine takes a player factory from its host (`newPlayer`), and Hearth's builds the `SyncAudioPlayer` with a `sinkFactory` that wraps `AudioTrackSink` to copy what it writes. That is phase 9 of the voice design and needs nothing more from SendspinDroid.

## Testing

- **SendspinDroid**: its own JVM suite, run on every pull request there (`testDebugUnitTest`, `:shared:testAndroidHostTest`, **verified**, `.github/workflows/pr-tests.yml`). The engine pull request moves the pipeline tests to `:player` (`DecoderPipelineIntegrationTest`, now against the real engine, `StreamStartDecoderPipelineTest`, `PauseFlushTest` and others) and adds `SendSpinEngineTest`. CI's `testDebugUnitTest` runs them there.
- **Hearth, Dart**: the Android backend against a fake channel — `state` decoding into `SendspinPlayerState`, the `outputDelay` and `lastPlaybackServer` write-backs, `setLocalDuckFactor` ignored, and the provider choosing a backend by platform.
- **Hearth, build**: `flutter build apk --debug` and `scripts/build-android-apk.sh` with the submodule, checked with `dexdump` for the player's classes as the satellite was.
- **Hardware**: the items under [Open questions](#open-questions--needs-hardware).

## Phases

Each line is one task. Sizes are relative. Phases 1 and 2 are pull requests in SendspinDroid; the rest are Hearth tasks, and phase 8 may also touch SendspinDroid.

| # | Task | Where | Size | Depends on |
|---|---|---|---|---|
| 1 | Extract `:player` from `:app`, behaviour unchanged. SendspinDroid pull request 326, merged. | SendspinDroid | Medium | — |
| 2 | Move the pipeline into `SendSpinEngine` in `:player`, with the `VOICE` mute reason, `consumer-rules.pro`, and the pipeline tests. `PlaybackService` becomes its host. SendspinDroid pull request 329, merged. | SendspinDroid | Large | 1 |
| 3 | **Done.** Pin SendspinDroid as a submodule; Hearth-owned scripts for `:sendspin-shared` and `:sendspin-player`; the APK builds with the classes in it; third-party notices; `CLAUDE.md` maintenance note | Hearth | Small-medium | 2 |
| 4 | **Done.** `HearthAudioService` hosts the engine: Sendspin configured on its own channel beside voice, foreground type by feature, `SendSpinHost` with private-file storage, the listener and advertiser glue, `STREAM_MUSIC` volume, `com.hearth/sendspin` | Hearth | Medium | 3 |
| 5 | **Done.** Dart: Android backend for `SendspinService`, remove the provider guard, hide buffer length on Android, the system slider on `STREAM_MUSIC`, and the requirements spec rows | Hearth | Medium | 4 |
| 6 | **Partly done** (see [Hardware pass 1](#hardware-pass-1-phase-6)): group sync, pairing by token, server-set output delay and a soak remain. Hardware pass: Music Assistant finds the tablet, pairing, playback in a group with the Pi, volume from both sides, output-delay persistence across a restart, and a release APK | Hearth | Small | 5 |
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
6. **The engine is the pipeline only.** Connections, volume and focus stay with each host, because in SendspinDroid they are app policy tied to its connection modes and reconnect loop. Hearth writes its own small version of each.
