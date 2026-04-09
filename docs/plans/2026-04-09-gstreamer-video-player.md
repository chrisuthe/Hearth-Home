# GStreamer Video Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace snapshot-only camera expansion on Pi with real RTSP video playback via GStreamer, using a platform-aware video abstraction layer.

**Architecture:** A `HearthVideoPlayer` interface with two implementations: `MediaKitVideoPlayer` (desktop/libmpv) and `GstreamerVideoPlayer` (Pi/flutter-pi). Runtime selection via `HEARTH_NO_MEDIAKIT` env var. RTSP streams from Frigate's go2rtc restream at `rtsp://<host>:8554/<camera>`.

**Tech Stack:** Flutter, media_kit (desktop), flutterpi_gstreamer_video_player (Pi), GStreamer, RTSP

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/services/video/hearth_video_player.dart` | Abstract interface + factory |
| `lib/services/video/media_kit_player.dart` | Desktop implementation using media_kit |
| `lib/services/video/gstreamer_player.dart` | Pi implementation using GStreamer custom pipeline |
| `test/services/video/hearth_video_player_test.dart` | Factory selection tests |

### Modified Files
| File | Changes |
|------|---------|
| `lib/modules/cameras/cameras_screen.dart` | Use HearthVideoPlayer instead of raw media_kit/snapshot |
| `lib/modules/cameras/frigate_service.dart` | Add rtspUrl builder method |
| `scripts/prepare-pi-build.sh` | Ensure flutterpi_gstreamer_video_player is added |
| `pubspec.yaml` | Add video_player package (standard Flutter, needed for GStreamer player interface) |

---

### Task 1: Video Player Interface

**Files:**
- Create: `lib/services/video/hearth_video_player.dart`

- [ ] **Step 1: Create the abstract interface**

Create `lib/services/video/hearth_video_player.dart`:

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-agnostic video player for RTSP streams and media playback.
///
/// Uses media_kit (libmpv) on desktop and GStreamer on Pi (flutter-pi).
/// Create via the factory constructor which selects the right implementation
/// based on the HEARTH_NO_MEDIAKIT environment variable.
abstract class HearthVideoPlayer {
  /// Start playing a video URL (RTSP, HTTP, file).
  Future<void> play(String url);

  /// Stop playback and release resources.
  Future<void> stop();

  /// Dispose the player permanently.
  void dispose();

  /// Whether the player is currently playing.
  bool get isPlaying;

  /// Build the video rendering widget.
  Widget buildView({BoxFit fit = BoxFit.contain});

  /// Factory that selects the correct implementation for the current platform.
  static HearthVideoPlayer create() {
    if (kIsWeb) {
      throw UnsupportedError('Video playback not supported on web');
    }
    if (Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
      // On Pi with flutter-pi — use GStreamer
      return _createGstreamerPlayer();
    }
    // Desktop — use media_kit
    return _createMediaKitPlayer();
  }
}

// These are late-bound to avoid importing platform-specific packages at compile time.
// The actual implementations register themselves at app startup.
HearthVideoPlayer Function() _createMediaKitPlayer = () =>
    throw StateError('MediaKitVideoPlayer not registered');
HearthVideoPlayer Function() _createGstreamerPlayer = () =>
    throw StateError('GstreamerVideoPlayer not registered');

/// Called at app startup to register platform-specific implementations.
void registerVideoPlayerFactory({
  HearthVideoPlayer Function()? mediaKit,
  HearthVideoPlayer Function()? gstreamer,
}) {
  if (mediaKit != null) _createMediaKitPlayer = mediaKit;
  if (gstreamer != null) _createGstreamerPlayer = gstreamer;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/video/hearth_video_player.dart
git commit -m "feat: add HearthVideoPlayer abstract interface with factory"
```

---

### Task 2: Media Kit Implementation (Desktop)

**Files:**
- Create: `lib/services/video/media_kit_player.dart`

- [ ] **Step 1: Create the media_kit implementation**

Create `lib/services/video/media_kit_player.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'hearth_video_player.dart';

class MediaKitVideoPlayer implements HearthVideoPlayer {
  Player? _player;
  VideoController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    _player = Player();
    _controller = VideoController(_player!);
    _player!.open(Media(url));
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  @override
  void dispose() {
    stop();
  }

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null) return const SizedBox.shrink();
    return Video(controller: _controller!, fit: fit);
  }
}

/// Register the media_kit factory at app startup.
void registerMediaKitPlayer() {
  registerVideoPlayerFactory(
    mediaKit: () => MediaKitVideoPlayer(),
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/video/media_kit_player.dart
git commit -m "feat: add MediaKitVideoPlayer implementation for desktop"
```

---

### Task 3: GStreamer Implementation (Pi)

**Files:**
- Create: `lib/services/video/gstreamer_player.dart`

- [ ] **Step 1: Create the GStreamer implementation**

Create `lib/services/video/gstreamer_player.dart`:

This file will only compile on Pi builds where `flutterpi_gstreamer_video_player` is in pubspec. On desktop builds, it's never imported (the factory registration is conditional).

```dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'hearth_video_player.dart';

/// GStreamer-based video player for flutter-pi on Raspberry Pi.
///
/// Uses flutterpi_gstreamer_video_player's custom pipeline API for
/// low-latency RTSP playback via GStreamer.
class GstreamerVideoPlayer implements HearthVideoPlayer {
  VideoPlayerController? _controller;
  bool _playing = false;

  @override
  Future<void> play(String url) async {
    await stop();
    // Use network URL — GStreamer handles RTSP natively
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    await _controller!.initialize();
    await _controller!.play();
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
    await _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    stop();
  }

  @override
  bool get isPlaying => _playing;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

/// Register the GStreamer factory at app startup.
void registerGstreamerPlayer() {
  registerVideoPlayerFactory(
    gstreamer: () => GstreamerVideoPlayer(),
  );
}
```

Note: The `video_player` package is the standard Flutter video player. On Pi with flutter-pi, `flutterpi_gstreamer_video_player` provides the platform implementation. The `VideoPlayerController.networkUrl` can play RTSP URLs because GStreamer handles the protocol natively.

- [ ] **Step 2: Add video_player to pubspec.yaml**

Add to dependencies in `pubspec.yaml`:
```yaml
  video_player: ^2.9.1
```

Run `flutter pub get`.

- [ ] **Step 3: Update prepare-pi-build.sh**

In `scripts/prepare-pi-build.sh`, ensure `flutterpi_gstreamer_video_player` is added. Check if it's already there from earlier work. If not, add it after the media_kit comment-out section:

```bash
if ! grep -q 'flutterpi_gstreamer_video_player' "$PUBSPEC"; then
    sed -i '/^  media_kit_libs_linux:/a\  flutterpi_gstreamer_video_player: ^0.1.0' "$PUBSPEC"
fi
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/video/gstreamer_player.dart pubspec.yaml scripts/prepare-pi-build.sh
git commit -m "feat: add GstreamerVideoPlayer implementation for Pi"
```

---

### Task 4: Register Players in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Register the video player factory at startup**

In `lib/main.dart`, after the `MediaKit.ensureInitialized()` block, register the video player:

```dart
// Register platform video player
if (!kIsWeb) {
  if (!Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
    // Desktop — use media_kit for video
    registerMediaKitPlayer();
  } else {
    // Pi — use GStreamer for video
    registerGstreamerPlayer();
  }
}
```

Add imports:
```dart
import 'services/video/media_kit_player.dart';
import 'services/video/gstreamer_player.dart';
```

Wait — the GStreamer import will fail on desktop since `video_player`'s platform implementation isn't available. The conditional import approach is needed. Actually, since `video_player` is a standard Flutter package that works on all platforms (it just uses different backends), the import is fine. The `flutterpi_gstreamer_video_player` is only needed at runtime on Pi — the `video_player` package itself compiles everywhere.

So the imports are safe. The `registerGstreamerPlayer()` call only happens when `HEARTH_NO_MEDIAKIT` is set (Pi only).

- [ ] **Step 2: Run tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register platform video player at startup"
```

---

### Task 5: Add RTSP URL to Frigate Service

**Files:**
- Modify: `lib/modules/cameras/frigate_service.dart`

- [ ] **Step 1: Add RTSP URL builder**

In `FrigateCamera` class (or wherever the camera model is defined), add a method or field for the RTSP URL.

Read the current `FrigateCamera` class in `lib/models/frigate_event.dart` first — it may already have `rtspUrl`. Check what fields it has and how the RTSP URL should be constructed from the Frigate host.

The RTSP URL pattern is: `rtsp://<frigate_host_ip>:8554/<camera_name>`

The Frigate host is in `config.frigateUrl` (e.g., `http://10.0.2.3:5000`). Extract the host/IP, use port 8554.

If `FrigateCamera` already has `rtspUrl`, verify it uses the correct format. If not, add it.

- [ ] **Step 2: Commit**

```bash
git add lib/models/frigate_event.dart lib/modules/cameras/frigate_service.dart
git commit -m "feat: add RTSP URL to FrigateCamera model"
```

---

### Task 6: Update Cameras Screen for Video Playback

**Files:**
- Modify: `lib/modules/cameras/cameras_screen.dart`

- [ ] **Step 1: Replace snapshot/media_kit with HearthVideoPlayer**

The cameras screen currently has two code paths:
1. Desktop (`_hasMediaKit`): creates media_kit `Player`/`VideoController`/`Video`
2. Pi: shows `_CameraSnapshotTile` in expanded view

Replace both with the unified `HearthVideoPlayer`:

1. Remove the `_hasMediaKit` check and the raw media_kit imports
2. Add: `import '../../services/video/hearth_video_player.dart';`
3. Replace `Player? _player` and `VideoController? _videoController` with `HearthVideoPlayer? _videoPlayer`
4. In `_expandCamera`:
```dart
void _expandCamera(FrigateCamera camera) {
  _disposePlayer();
  final player = HearthVideoPlayer.create();
  player.play(camera.rtspUrl);
  setState(() {
    _expandedCamera = camera;
    _videoPlayer = player;
  });
}
```
5. In `_collapseCamera`:
```dart
void _collapseCamera() {
  _videoPlayer?.dispose();
  _videoPlayer = null;
  setState(() => _expandedCamera = null);
}
```
6. In the expanded view, replace the `Video(controller:)` / `_CameraSnapshotTile` conditional with:
```dart
_videoPlayer!.buildView(fit: BoxFit.contain),
```

7. Remove the `import 'dart:io' show Platform;` and `_hasMediaKit` getter if no longer needed.
8. Remove `import 'package:media_kit/media_kit.dart';` and `import 'package:media_kit_video/media_kit_video.dart';`

- [ ] **Step 2: Run tests and analyze**

Run: `flutter test`
Run: `flutter analyze`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add lib/modules/cameras/cameras_screen.dart
git commit -m "feat: use HearthVideoPlayer for camera RTSP streams"
```

---

### Task 7: Update CLAUDE.md and Create PR

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add a note about the video player abstraction in the Architecture section, under the Module System subsection or as its own subsection:

```markdown
### Video Player

`HearthVideoPlayer` (`lib/services/video/`) abstracts platform-specific video playback. Desktop uses media_kit (libmpv), Pi uses GStreamer via flutterpi_gstreamer_video_player. Factory selection via `HEARTH_NO_MEDIAKIT` env var. Used by the Cameras module for RTSP streams and will be used for future DLNA playback.
```

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Run: `flutter analyze`
Expected: ALL PASS

- [ ] **Step 3: Commit and push**

```bash
git add CLAUDE.md
git commit -m "docs: add video player abstraction to CLAUDE.md"
git push -u origin task/gstreamer-video-player
```

- [ ] **Step 4: Create PR**

```bash
gh pr create --repo chrisuthe/Hearth-Home --title "feat: GStreamer video player for RTSP camera streams" --body "## Summary

Adds platform-aware video playback for camera RTSP streams. Desktop uses media_kit, Pi uses GStreamer via flutterpi_gstreamer_video_player.

### Changes
- HearthVideoPlayer abstract interface with factory selection
- MediaKitVideoPlayer for desktop (wraps existing media_kit usage)
- GstreamerVideoPlayer for Pi (uses video_player + GStreamer backend)
- Cameras screen uses the abstraction instead of raw media_kit/snapshots
- RTSP URLs built from Frigate host config

### Architecture
- lib/services/video/hearth_video_player.dart — interface + factory
- lib/services/video/media_kit_player.dart — desktop impl
- lib/services/video/gstreamer_player.dart — Pi impl
- Runtime selection via HEARTH_NO_MEDIAKIT env var
- Registration at app startup in main.dart

### Testing
- Requires Pi hardware to test GStreamer path
- Desktop path tested with existing media_kit
- RTSP streams from Frigate go2rtc at rtsp://<host>:8554/<camera>"
```
