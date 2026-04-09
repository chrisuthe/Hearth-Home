# GStreamer Video Player Integration — Design Spec

**Date:** 2026-04-09
**Status:** Approved

## Overview

Replace the snapshot-only camera expansion with real RTSP video playback on the Pi using flutter-pi's GStreamer video player plugin. Create a platform-aware video abstraction that uses media_kit on desktop and GStreamer on Pi. This unlocks both live camera feeds and future DLNA media playback.

## Current State

- Desktop: media_kit (libmpv) handles video via `Player`/`VideoController`/`Video` widgets
- Pi: `HEARTH_NO_MEDIAKIT=1` skips media_kit init; camera tap shows auto-refreshing snapshot instead of video
- The `flutterpi_gstreamer_video_player` package is already installed on the Pi (flutter-pi includes it), but we don't use it from Dart

## Frigate Stream Details

All cameras stream H.264 (High profile) via go2rtc RTSP restream:
- `rtsp://10.0.2.3:8554/FrontDoorbell` (896x672)
- `rtsp://10.0.2.3:8554/GarageDoorbell` (896x672)
- `rtsp://10.0.2.3:8554/DrivewayPTZ` (1280x720)
- `rtsp://10.0.2.3:8554/GarageEast` (1280x720)
- `rtsp://10.0.2.3:8554/YardNorth` (1280x720)
- Sub-streams available as `<camera>_sub` for doorbells

Pi 5 decodes H.264 via software (`avdec_h264`) — no hardware decode for H.264, but the A76 cores handle 1080p30 fine.

## Architecture

### Platform Video Abstraction

```dart
/// Platform-agnostic video player that uses media_kit on desktop
/// and GStreamer custom pipelines on Pi (flutter-pi).
abstract class HearthVideoPlayer {
  Future<void> play(String url);
  Future<void> stop();
  Widget buildView();
  bool get isPlaying;
  
  factory HearthVideoPlayer.create() {
    if (Platform.environment.containsKey('HEARTH_NO_MEDIAKIT')) {
      return GstreamerVideoPlayer();
    }
    return MediaKitVideoPlayer();
  }
}
```

### GStreamer Pipeline for RTSP

Low-latency pipeline for camera feeds:
```
rtspsrc location=<url> latency=200 buffer-mode=slave
  ! rtph264depay ! h264parse
  ! avdec_h264
  ! videoconvert
  ! video/x-raw,format=RGBA
  ! appsink name=sink sync=false drop=true
```

Using `flutterpi_gstreamer_video_player`'s custom pipeline API, this becomes:
```dart
final controller = VideoPlayerController.withGstreamerPipeline(
  'rtspsrc location=$rtspUrl latency=200 buffer-mode=slave '
  '! rtph264depay ! h264parse ! avdec_h264 '
  '! videoconvert ! video/x-raw,format=RGBA '
  '! appsink name=sink sync=false drop=true',
);
```

### Integration Points

1. **Camera screen** — expanded view uses `HearthVideoPlayer` instead of snapshot
2. **Future: DLNA renderer** — receives media URLs, plays via the same abstraction
3. **Future: Plex casting** — same video player, different URL source

## Conditional Dependency

The `flutterpi_gstreamer_video_player` package is only available on flutter-pi (ARM64 with GStreamer). It must be a conditional import:

- `lib/services/video/hearth_video_player.dart` — abstract interface
- `lib/services/video/media_kit_player.dart` — desktop implementation using media_kit
- `lib/services/video/gstreamer_player.dart` — Pi implementation using flutterpi_gstreamer_video_player

The `prepare-pi-build.sh` script already handles the media_kit → gstreamer dependency swap for CI. The Dart code uses conditional imports based on `HEARTH_NO_MEDIAKIT` env var at runtime.

Actually, since both packages may not compile on both platforms, the cleaner approach:
- Desktop build: only media_kit in pubspec, `MediaKitVideoPlayer` is the only implementation
- Pi build: `prepare-pi-build.sh` swaps to `flutterpi_gstreamer_video_player`, `GstreamerVideoPlayer` is the implementation
- Runtime: `HEARTH_NO_MEDIAKIT` env var selects which to use
- Both implement the same `HearthVideoPlayer` interface

## Cameras Module Changes

In `lib/modules/cameras/cameras_screen.dart`:

1. Replace `_hasMediaKit` check with `HearthVideoPlayer.create()`
2. In `_expandCamera`, create a `HearthVideoPlayer`, call `play(camera.rtspUrl)`
3. The expanded view uses `player.buildView()` instead of `Video(controller:)` or `_CameraSnapshotTile`
4. `_collapseCamera` calls `player.stop()` and disposes it

The RTSP URL is built from the Frigate service: `rtsp://<frigateHost>:8554/<cameraName>`

The Frigate host is extracted from `config.frigateUrl` (strip the port, use 8554 for RTSP).

## What's Out of Scope

- H.265 transcoding on go2rtc (cameras output H.264)
- WebRTC playback (RTSP is simpler and lower latency for this use case)
- Audio from camera feeds (video only for now)
- DLNA renderer (future feature, uses this video player)
- Multi-camera simultaneous video (one expanded at a time)
