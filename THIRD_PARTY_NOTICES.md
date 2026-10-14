# Third-party notices

<!-- Generated from assets/licenses/notices.json by `dart run tool/gen_third_party_notices.dart`. Do not edit by hand. -->

Hearth is MIT-licensed (see `LICENSE`). Its builds also ship the code and content below, under their own licences. Every Dart package is credited separately by Flutter's package licences, which the app shows under Settings → System → Open-source licences next to these.

Full licence texts are in `assets/licenses/`. **Verified** means we read the licence at its source; **assumed** means we did not, and says why. This is our reading of each licence, not legal advice.

| Component | Licence | Platforms | Status |
|---|---|---|---|
| [Ava (Android voice satellite)](#ava) | Apache-2.0 | android | verified |
| [TensorFlow Lite microfrontend](#tflite-microfrontend) | Apache-2.0 | android | verified |
| [KISS FFT](#kissfft) | BSD-3-Clause | android | verified |
| [ESPHome native API protocol (api.proto)](#esphome-api-proto) | MIT | android | verified |
| [microWakeWord models: okay_nabu, hey_jarvis, stop](#microwakeword-models) | Apache-2.0 | android | verified |
| [Home Assistant Voice Preview Edition sounds](#voice-pe-sounds) | CC-BY-4.0 | android | verified |
| [LiteRT](#litert) | Apache-2.0 | android | verified |
| [AndroidX libraries, including Media3](#androidx) | Apache-2.0 | android | verified |
| [Kotlin standard library, kotlinx.coroutines, kotlinx.serialization, JetBrains annotations](#kotlin) | Apache-2.0 | android | verified |
| [Guava](#guava) | Apache-2.0 | android | verified |
| [ReLinker](#relinker) | Apache-2.0 | android | verified |
| [JSpecify annotations](#jspecify) | Apache-2.0 | android | verified |
| [Timber](#timber) | Apache-2.0 | android | verified |
| [Protocol Buffers (Java and Kotlin lite runtimes)](#protobuf) | BSD-3-Clause | android | verified |
| [libmpv and FFmpeg (media_kit native builds)](#libmpv) | LGPL-2.1-or-later | android, windows | assumed |
| [Inter font](#inter) | OFL-1.1 | android, pi, linux, windows | verified |
| [Weather Icons font](#weather-icons) | OFL-1.1 | android, pi, linux, windows | verified |
| [Alarm tones](#alarm-tones) | CC-BY-4.0 and CC0-1.0 | android, pi, linux, windows | verified |
| [flutter-pi](#flutter-pi) | MIT | pi | verified |
| [flutterpi_gstreamer_video_player](#flutterpi-gstreamer-video-player) | MIT | pi | verified |
| [libFLAC](#libflac) | BSD-3-Clause | linux, windows | verified |

<a id="ava"></a>
## Ava (Android voice satellite)

Copyright 2025 Brownard.

Hearth builds a fork, chrisuthe/Ava-hearth, that moves Ava's device code into a :satellite library module. The fork's README lists the moved files.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/brownard/Ava>
- Fork: <https://github.com/chrisuthe/Ava-hearth>
- Platforms: android
- Status: **verified**. LICENSE.md in the fork and upstream.

<a id="tflite-microfrontend"></a>
## TensorFlow Lite microfrontend

Copyright 2018 The TensorFlow Authors. All Rights Reserved.

The wake-word audio feature frontend, compiled into Ava's :microfeatures library.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/tensorflow/tflite-micro>
- Platforms: android
- Status: **verified**. File headers under microfeatures/src/main/cpp/tensorflow.

<a id="kissfft"></a>
## KISS FFT

Compiled into Ava's :microfeatures library.

- Licence: BSD-3-Clause (`assets/licenses/kissfft.txt`)
- Source: <https://github.com/mborgerding/kissfft>
- Platforms: android
- Status: **verified**. Header of microfeatures/src/main/cpp/kissfft/kiss_fft.c.

<a id="esphome-api-proto"></a>
## ESPHome native API protocol (api.proto)

Ava's :esphomeproto library is generated from ESPHome's api.proto. ESPHome licenses its C and C++ files under GPLv3 and every other file, api.proto included, under MIT.

- Licence: MIT (`assets/licenses/esphome-mit.txt`)
- Source: <https://github.com/esphome/esphome>
- Platforms: android
- Status: **verified**. ESPHome LICENSE.

<a id="microwakeword-models"></a>
## microWakeWord models: okay_nabu, hey_jarvis, stop

Wake-word models trained by Kevin Ahrendt (https://www.kevinahrendt.com/).

hey_jarvis from esphome/micro-wake-word-models; okay_nabu and stop from the kahrendt/microWakeWord releases okay_nabu_20241226.3 and stop-20241016.2.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/kahrendt/microWakeWord>
- Platforms: android
- Status: **verified**. Each bundled .tflite is byte-identical to the file in an Apache-2.0 repository: hey_jarvis to esphome/micro-wake-word-models models/v2, okay_nabu and stop to the kahrendt/microWakeWord release assets named above.

<a id="voice-pe-sounds"></a>
## Home Assistant Voice Preview Edition sounds

Home Assistant Voice Preview Edition Sounds (https://github.com/esphome/home-assistant-voice-pe/tree/dev/sounds) © 2024 by Clayton Charles Tapp (https://www.cctaudio.com/).

The wake, timer-finished and error sounds, as distributed with Ava.

- Licence: CC-BY-4.0 (`assets/licenses/cc-by-4.0.txt`)
- Source: <https://github.com/esphome/home-assistant-voice-pe>
- Platforms: android
- Status: **verified**. satellite/src/main/assets/sounds/LICENSE.md in Ava.

<a id="litert"></a>
## LiteRT

Copyright Google LLC.

Runs the wake-word models.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/google-ai-edge/LiteRT>
- Platforms: android
- Status: **verified**. Maven POM licence of com.google.ai.edge.litert.

<a id="androidx"></a>
## AndroidX libraries, including Media3

Copyright The Android Open Source Project.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://developer.android.com/jetpack/androidx>
- Platforms: android
- Status: **verified**. Maven POM licence of every androidx artifact on the release runtime classpath.

<a id="kotlin"></a>
## Kotlin standard library, kotlinx.coroutines, kotlinx.serialization, JetBrains annotations

Copyright JetBrains s.r.o. and Kotlin Programming Language contributors.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/JetBrains/kotlin>
- Platforms: android
- Status: **verified**. Maven POM licences.

<a id="guava"></a>
## Guava

Copyright The Guava Authors.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/google/guava>
- Platforms: android
- Status: **verified**. Maven POM licence (guava-parent).

<a id="relinker"></a>
## ReLinker

Copyright KeepSafe Software, Inc.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/KeepSafe/ReLinker>
- Platforms: android
- Status: **verified**. Maven POM licence.

<a id="jspecify"></a>
## JSpecify annotations

Copyright The JSpecify Authors.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/jspecify/jspecify>
- Platforms: android
- Status: **verified**. Maven POM licence.

<a id="timber"></a>
## Timber

Copyright 2013 Jake Wharton.

- Licence: Apache-2.0 (`assets/licenses/apache-2.0.txt`)
- Source: <https://github.com/JakeWharton/timber>
- Platforms: android
- Status: **verified**. Repository LICENSE.txt and Maven POM licence.

<a id="protobuf"></a>
## Protocol Buffers (Java and Kotlin lite runtimes)

- Licence: BSD-3-Clause (`assets/licenses/protobuf.txt`)
- Source: <https://github.com/protocolbuffers/protobuf>
- Platforms: android
- Status: **verified**. Repository LICENSE and Maven POM licence (protobuf-parent).

<a id="libmpv"></a>
## libmpv and FFmpeg (media_kit native builds)

media_kit downloads prebuilt libmpv, which statically includes FFmpeg and other libraries, from media-kit/libmpv-android-video-build (Android) and media-kit/libmpv-win32-video-build (Windows). Source for those builds is in the repositories named here.

Linux desktop uses the system's libmpv and does not bundle it; the Pi does not use it.

- Licence: LGPL-2.1-or-later (`assets/licenses/lgpl-2.1.txt`)
- Source: <https://github.com/media-kit/libmpv-android-video-build>
- Platforms: android, windows
- Status: **assumed**. Not confirmed: we have not read the build flags. mpv and FFmpeg are LGPL-2.1-or-later only when built without their GPL parts.

<a id="inter"></a>
## Inter font

- Licence: OFL-1.1 (`assets/licenses/ofl-inter.txt`)
- Source: <https://github.com/rsms/inter>
- Platforms: android, pi, linux, windows
- Status: **verified**. Repository LICENSE.txt and the font's name table.

<a id="weather-icons"></a>
## Weather Icons font

- Licence: OFL-1.1 (`assets/licenses/ofl-weather-icons.txt`)
- Source: <https://github.com/erikflowers/weather-icons>
- Platforms: android, pi, linux, windows
- Status: **verified**. Repository README licensing section and the font's name table.

<a id="alarm-tones"></a>
## Alarm tones

"Chord Alert Notification" by graham_makes (https://freesound.org/people/graham_makes/sounds/457518/), licensed under CC BY 4.0. Loudness-normalized and re-encoded as Ogg Vorbis for Hearth.

The other tones are CC0 and need no credit: "ambientBell.wav" by Divinux, "Birds Chirping" by Lizardhood, "Alarm Clock" by dcloh, all from Freesound.

- Licence: CC-BY-4.0 and CC0-1.0 (`assets/licenses/cc-by-4.0.txt`)
- Source: <https://freesound.org/>
- Platforms: android, pi, linux, windows
- Status: **verified**. Freesound pages, recorded in assets/alarm_tones/CREDITS.md.

<a id="flutter-pi"></a>
## flutter-pi

The Pi runs Hearth on flutter-pi, built from the fork chrisuthe/flutter-pi-hearth.

- Licence: MIT (`assets/licenses/flutter-pi.txt`)
- Source: <https://github.com/ardera/flutter-pi>
- Fork: <https://github.com/chrisuthe/flutter-pi-hearth>
- Platforms: pi
- Status: **verified**. LICENSE in upstream and the fork.

<a id="flutterpi-gstreamer-video-player"></a>
## flutterpi_gstreamer_video_player

A Dart package, built from the fork chrisuthe/flutterpi_gstreamer_video_player-hearth. Flutter's package licences already list it, so it is not registered again.

- Licence: MIT
- Source: <https://github.com/ardera/flutter_packages>
- Fork: <https://github.com/chrisuthe/flutterpi_gstreamer_video_player-hearth>
- Platforms: pi
- Status: **verified**. LICENSE in the fork.

<a id="libflac"></a>
## libFLAC

Decodes FLAC for Sendspin through native/sendspin_flac. Linux links the system's libFLAC; a Windows build bundles it when one is found at build time.

- Licence: BSD-3-Clause (`assets/licenses/libflac.txt`)
- Source: <https://github.com/xiph/flac>
- Platforms: linux, windows
- Status: **verified**. COPYING.Xiph in the repository.
