# Stream Hearth Screen + Audio to OBS

## Summary

Add a live streaming output to Hearth's capture tools so a workstation running OBS on the LAN can receive the Pi's screen and system audio as a network source. Intended for on-demand live demos and marketing recordings where OBS composes the final video. Target protocol is SRT with the Pi as caller and OBS as listener, chosen for its native ffmpeg + OBS support, low latency, and WiFi packet-loss tolerance.

The feature sits alongside the existing screenshot + recording capabilities under the same `captureToolsEnabled` master toggle, in the `/capture` web page.

## Goals

- One-click start/stop of a live screen + system-audio stream to a pre-configured OBS host.
- "System mix" audio capture — whatever the Pi plays through its HDMI output (Sendspin music, Wyoming TTS, alert tones).
- A local MP4 backup of every streamed session, produced automatically via ffmpeg's `tee` muxer (no second subprocess, no second kmsgrab).
- Native transport — no new daemons, no server processes on the Pi. ffmpeg and OBS's built-in SRT support are the only moving parts.
- Gated behind `captureToolsEnabled` so normal users never see it.

## Non-Goals

- Multi-viewer / broadcast-style distribution. One SRT caller → one OBS listener per session.
- Public-internet streaming. LAN only; no NAT traversal, no STUN/TURN, no auth beyond what the existing capture gate provides.
- Cloud ingest (RTMP to Twitch/YouTube directly from the Pi). OBS does that if you want it; Hearth only feeds OBS.
- Per-source audio control (stream music but not TTS). System mix is the product; splitting it would require a richer audio graph we don't have.
- Stream-side overlays, annotations, or video effects. OBS does those.
- Mid-stream target reconfiguration. Stop, change host/port, start again.

## Architecture

```
┌──────────────────────────── Pi 5 ────────────────────────────┐
│                                                              │
│  kmsgrab (DRM plane 0) ──┐                                   │
│                          ├──► ffmpeg ──┬──► MP4 (local file) │
│  ALSA hw:Loopback,1,0 ───┘  (one proc) └──► SRT (caller) ─┐  │
│                                                           │  │
│  Apps play to `hdmi_tee` ──► HDMI card ─► (physical audio) │  │
│                           └─► hw:Loopback,0,0 (to ffmpeg)  │  │
└────────────────────────────────────────────────────────────┼──┘
                                                             │
                                           srt://<obs>:9999 ─┤
                                                             ▼
                                                      ┌──────────────┐
                                                      │ OBS (LAN)    │
                                                      │ Media Source │
                                                      │ listener     │
                                                      └──────────────┘
```

Three new pieces:

1. **`StreamService`** (`lib/services/stream_service.dart`) — Riverpod `Provider` singleton. Owns the single `ffmpeg` tee subprocess, session filename, state machine, and exposes start/stop/status.
2. **`LocalApiServer` extensions** — three new endpoints under `/api/stream/*`, plus a new "Stream to OBS" panel rendered into the existing `/capture` HTML. All gated by `captureToolsEnabled` via the same early-404 in `_handleRequest`.
3. **Audio routing setup** — `snd-aloop` kernel module + `/etc/asound.conf` defining an `hdmi_tee` device, plus changes to Sendspin default config and the Wyoming systemd unit. Provisioned by `setup-pi.sh`; existing Pis run a one-shot migration script.

### Dependency flow

```
HubConfig.captureToolsEnabled ──► API gate in LocalApiServer._handleRequest
HubConfig.streamTargetHost    ──┐
HubConfig.streamTargetPort    ──┴► StreamService.start() target
CaptureService.isRecording    ──► cross-exclusion in /api/stream/start
StreamService.isStreaming     ──► cross-exclusion in /api/capture/recording/start
```

No circular dependencies. `StreamService` doesn't know about `CaptureService`; `LocalApiServer` is the only place that sees both and enforces the mutual exclusion.

## Audio Routing

### Current state

Sendspin and Wyoming both write to `plughw:CARD=vc4hdmi0,DEV=0` (HDMI card). Pure ALSA — no PulseAudio, no PipeWire. There is no monitor source on ALSA the way PulseAudio would give us; the only way to capture "what a process played" is to physically duplicate the output at the ALSA layer.

### New state

`snd-aloop` creates a virtual loopback: bytes written to `hw:Loopback,0,0` come out on `hw:Loopback,1,0` (and vice versa). A `type multi` ALSA plugin device named `hdmi_tee` binds two stereo slaves — the real HDMI card and the loopback playback end. Apps write once to `hdmi_tee`; samples land on both.

`/etc/asound.conf`:

```
pcm.hdmi_tee {
  type plug
  slave.pcm "hdmi_tee_multi"
}
pcm.hdmi_tee_multi {
  type multi
  slaves.a.pcm "hw:vc4hdmi0,0"
  slaves.b.pcm "hw:Loopback,0,0"
  slaves.a.channels 2
  slaves.b.channels 2
  bindings.0 { slave a; channel 0; }
  bindings.1 { slave a; channel 1; }
  bindings.2 { slave b; channel 0; }
  bindings.3 { slave b; channel 1; }
}
```

`/etc/modules-load.d/hearth-loopback.conf`:

```
snd-aloop
```

ffmpeg captures from the *other* end of the loopback:

```
ffmpeg ... -f alsa -ac 2 -ar 48000 -i hw:Loopback,1,0 ...
```

### Config changes for apps

- **Sendspin** — default `sendspinAlsaDevice` in `HubConfig` flips from `plughw:CARD=vc4hdmi0,DEV=0` to `hdmi_tee`. Existing installs keep their current value unless the migration script is run. Users who changed this manually are unaffected.
- **Wyoming** — the systemd unit's `--snd-command` becomes `aplay -D hdmi_tee -r 22050 -c 1 -f S16_LE -t raw`. Applied by `setup-pi.sh` for new installs; migration script updates the running unit file and issues a `daemon-reload` + `restart`.

### Latency impact

ALSA's `plug` chain is sub-millisecond on every transform. Doubling the output path through `type multi` adds no perceptible latency to playback. Loopback capture is zero-copy kernel-side.

### Failure modes

- If `snd-aloop` isn't loaded, `hdmi_tee` construction fails at open time — apps relying on it can't play audio. `setup-pi.sh` verifies the module loads successfully before writing the asound.conf; the module is declared in `modules-load.d` so systemd loads it before any audio-using service starts.
- If `hw:vc4hdmi0,0` is busy (two apps without `dmix`), the multi device surfaces `EBUSY`. This is the same failure mode existing HDMI playback has today — not new.

## StreamService

### Responsibilities

- Own the single ffmpeg subprocess lifetime.
- Assign timestamped filenames that follow the existing `hearth-YYYYMMDD-HHMMSS.mp4` regex so the capture gallery picks them up.
- Enforce the single-stream invariant (second `start()` throws).
- Capture ffmpeg stderr into a ring buffer (same pattern as `CaptureService`) for debugging.
- Surface state via a `Stream<StreamState>` consumed by `/api/stream/status`.

### ffmpeg invocation

```
ffmpeg
  -f kmsgrab -framerate 30 -i -                 # video: same DRM device CaptureService
                                                #        already uses for recording
  -f alsa -ac 2 -ar 48000 -i hw:Loopback,1,0    # audio: ALSA loopback capture
  -vf 'hwdownload,format=bgra,format=yuv420p'   # kmsgrab frames → system memory
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 4000k
  -c:a aac -b:a 128k
  -f tee -map 0:v -map 1:a
    "[f=mp4]/home/hearth/.local/share/hearth/captures/hearth-<ts>.mp4
     |[f=mpegts:onfail=ignore]srt://<host>:<port>?mode=caller&pkt_size=1316&transtype=live"
```

The `onfail=ignore` on the SRT output means an OBS disconnect doesn't tear down the MP4 leg. ffmpeg stays alive; we eventually send SIGINT on stop.

Runs as the `hearth` user via the existing sudo rule for `/usr/bin/ffmpeg` (already provisioned by `setup-pi.sh`).

### Lifecycle

```dart
enum StreamPhase { idle, starting, active, stopping, error }

class StreamState {
  final StreamPhase phase;
  final String? filename;
  final DateTime? startedAt;
  final String? targetHost;
  final int? targetPort;
  final String? errorMessage;
}
```

State transitions:

| From       | Event                            | To        |
|------------|----------------------------------|-----------|
| idle       | `start()`                        | starting  |
| starting   | ffmpeg logs `Output #0` + SRT ok | active    |
| starting   | ffmpeg exits non-zero within 10s | error     |
| active     | `stop()`                         | stopping  |
| active     | ffmpeg exits non-zero            | error     |
| stopping   | ffmpeg exits                     | idle      |
| error      | (30s timeout)                    | idle      |

The "starting → active" transition uses a simple liveness check rather than parsing stderr: one second after spawn, if the ffmpeg process is still running, transition to `active`. SRT connection failures from a missing OBS listener produce an ffmpeg exit within ~1–3 s, which we catch via `Process.exitCode` and map to `error` with the stderr tail as `errorMessage`. We keep a 10-second hard upper bound — if ffmpeg is still running but hasn't produced output frames (rare; implies a hung connect), we surface a timeout error and SIGKILL it.

### Invariants

- At most one ffmpeg subprocess owned by this service at a time.
- `filename` always matches the regex `^hearth-\d{8}-\d{6}\.mp4$` and is reserved before ffmpeg spawns (touch the file) so the capture gallery doesn't miss it if the user polls mid-startup.
- `stop()` is idempotent once `phase == stopping` — duplicate calls no-op.
- `dispose()` (Riverpod teardown) hard-kills any running ffmpeg; MP4 may be truncated but is kept.

## API Endpoints

All under the existing capture gate. When `captureToolsEnabled` is false, every route below returns 404 before auth runs — same early-return pattern the `/api/capture/*` routes use today.

```
POST /api/stream/start
     Body: { "host": "192.168.1.42", "port": 9999 }
     Starts ffmpeg. Persists host+port to HubConfig.
     200 → { filename, startedAt, targetHost, targetPort }
     409 → { error: "recording is active" }
     409 → { error: "stream already active", activeFilename }
     400 → { error: "host required" } / port out of range
     500 → { error: "ffmpeg failed to start", stderrTail }

POST /api/stream/stop
     Sends SIGINT to the active ffmpeg, awaits exit, finalizes the MP4.
     200 → { filename, durationSeconds, sizeBytes }
     400 → { error: "no active stream" }

GET  /api/stream/status
     Always 200.
     → { phase: "idle"|"starting"|"active"|"stopping"|"error",
         filename?, startedAt?, targetHost?, targetPort?, errorMessage? }
```

Cross-exclusion with the existing recording endpoint is implemented in `LocalApiServer._handleCaptureRequest` + the new stream handler:

- `POST /api/capture/recording/start` returns 409 `{error: "stream is active"}` when the stream service is active.
- `POST /api/stream/start` returns 409 `{error: "recording is active"}` when the capture service is recording.

## Web UI — "Stream to OBS" panel

Added to the existing `/capture` page, between the Screenshot/Recording buttons and the Touch Indicator section. Matches the existing card visual language.

```
─── Stream to OBS ───────────────────────────────────────
  Host  [192.168.1.42               ]
  Port  [9999        ]
  [ ● Start streaming ]   ○ Idle
──────────────────────────────────────────────────────────
```

When the stream is active:

```
─── Stream to OBS ───────────────────────────────────────
  Host  [192.168.1.42               ]   (readonly while streaming)
  Port  [9999        ]
  [ ■ Stop streaming ]   ● 00:01:24 · 17 MB · 192.168.1.42:9999
──────────────────────────────────────────────────────────
```

Error state is a red status pill with the last `errorMessage` ("OBS isn't listening on 192.168.1.42:9999" or similar). Dismissed automatically on next successful start.

Polling: status endpoint polled at 1 Hz while panel is visible (same cadence as the recording panel already uses).

Disabled-with-tooltip states:
- "Stop the recording first" when `CaptureService.isRecording`.
- "Stop the stream first" applied to the existing Record button when `StreamService.isStreaming`.

## HubConfig additions

```dart
final String streamTargetHost;   // default ''
final int streamTargetPort;      // default 9999
```

Both persisted in `hub_config.json`. Added to `copyWith`, `toJson`, `fromJson`, constructor defaults, and the `/api/config` POST handler. `streamTargetHost` is included in the `GET /api/config` response (no redaction — it's a LAN IP, not a secret).

No Settings-screen UI for these. They're edited only through the Stream panel on `/capture` (and therefore only by users who've enabled capture tools).

## Setup & Migration

### New installs (`setup-pi.sh`)

Add a new section after the existing ALSA-related setup:

```bash
# --- Audio routing: tee HDMI output to loopback for capture ---
sudo tee /etc/modules-load.d/hearth-loopback.conf > /dev/null << 'EOF'
snd-aloop
EOF
sudo modprobe snd-aloop

sudo tee /etc/asound.conf > /dev/null << 'EOF'
pcm.hdmi_tee {
  type plug
  slave.pcm "hdmi_tee_multi"
}
pcm.hdmi_tee_multi {
  type multi
  slaves.a.pcm "hw:vc4hdmi0,0"
  slaves.b.pcm "hw:Loopback,0,0"
  slaves.a.channels 2
  slaves.b.channels 2
  bindings.0 { slave a; channel 0; }
  bindings.1 { slave a; channel 1; }
  bindings.2 { slave b; channel 0; }
  bindings.3 { slave b; channel 1; }
}
EOF

# Sanity: ensure tone → loopback works before declaring success
speaker-test -D hdmi_tee -t sine -f 440 -l 1 -s 1 > /dev/null 2>&1 &
sleep 0.5
arecord -D hw:Loopback,1,0 -d 1 -f S16_LE -r 48000 -c 2 /tmp/hearth-audio-check.wav > /dev/null 2>&1
[ -s /tmp/hearth-audio-check.wav ] || echo "WARNING: hdmi_tee → loopback test produced empty capture"
rm -f /tmp/hearth-audio-check.wav
```

Wyoming service ExecStart's `--snd-command` changes to `aplay -D hdmi_tee ...` in the unit file template written by `setup-pi.sh`.

### Existing Pis — migration script

`scripts/migrate-audio-routing.sh` applies the same changes without re-running all of setup-pi.sh:

1. Write `/etc/modules-load.d/hearth-loopback.conf` and `modprobe snd-aloop`.
2. Write `/etc/asound.conf`.
3. Run the tone-in / tone-out sanity check.
4. `sed -i` the Wyoming unit file's `--snd-command` to use `hdmi_tee`, `daemon-reload`, restart wyoming-satellite.service.
5. Update `sendspinAlsaDevice` in the running Pi's `hub_config.json` only if its current value is the default (`plughw:CARD=vc4hdmi0,DEV=0`); leave custom values alone.
6. Restart hearth.service so Sendspin picks up the new device.

Idempotent — re-running on an already-migrated Pi is a no-op.

## Testing

### Unit tests — `StreamService`

- Inject a fake process spawner (same pattern as `CaptureServiceTest`).
- Verify command-line construction: correct `-i hw:Loopback,1,0`, correct SRT URL with `mode=caller` and `pkt_size=1316`, correct tee string with both outputs and `onfail=ignore` on the SRT leg, MP4 path under the captures directory and matching the filename regex.
- Second `start()` while active throws a defined exception type.
- `stop()` when idle throws.
- `dispose()` kills any running process.
- Filename-reservation test: after `start()`, the MP4 path exists (even if empty) before ffmpeg has had time to write anything.
- Starting-state timeout: if fake ffmpeg exits non-zero within 10s of spawn, state machine transitions to `error` with the stderr tail.

### Integration tests — `LocalApiServer`

- `POST /api/stream/start` with `captureToolsEnabled: false` → 404. With it true → 200 and fake spawner records the expected command line.
- Start twice → second returns 409.
- Start stream while `CaptureService.startRecording` is active → 409 with `{error: "recording is active"}`.
- `POST /api/capture/recording/start` while stream is active → 409 with `{error: "stream is active"}`.
- `POST /api/stream/stop` with no active stream → 400.
- `GET /api/stream/status` reflects the current phase across all transitions.
- Host+port POST body round-trips through `HubConfig` and is reflected on the next `GET /api/stream/status`.

### Manual validation on the Pi

Documented as a checklist in the PR:

1. Apply the audio migration script on an existing Pi; run `speaker-test -D hdmi_tee -t sine` and confirm audible + `arecord -D hw:Loopback,1,0` produces a non-empty WAV containing the tone.
2. Confirm Sendspin music still plays audibly post-migration.
3. Confirm Wyoming wake-word + TTS response still plays audibly post-migration.
4. On a workstation: add an OBS Media Source with `Input: srt://0.0.0.0:9999?mode=listener`. On the Pi: open `/capture`, enter workstation IP + 9999, click Start. Verify video + audio arrive in OBS within 2 seconds of click.
5. Start a recording separately with the stream still active — expect 409 and a toast in the UI.
6. Click Stop. Verify OBS stream ends cleanly and the MP4 file shows up in `/api/capture/list` with the expected filename and non-zero duration.
7. Start stream with OBS *not* listening — expect error state surfacing "Connection refused" or similar within 10 seconds.
8. Mid-stream, kill OBS. ffmpeg's SRT leg fails with `onfail=ignore`; MP4 leg continues until Stop. Verify final MP4 is playable.

GStreamer/ffmpeg codec correctness is verified by visual inspection and VLC playback of the produced MP4 — automating video codec validation isn't worth the tooling cost.

## Scope boundaries

**In scope:**
- `StreamService` with the ffmpeg tee pipeline
- Three `/api/stream/*` endpoints
- Stream panel in `/capture` web UI
- `HubConfig.streamTargetHost` and `streamTargetPort`
- Audio routing setup in `setup-pi.sh` + migration script
- Cross-exclusion with existing recording
- Tests as described above

**Out of scope (future specs):**
- Per-source audio selection (stream TTS but not music, etc.).
- Multi-viewer / HLS / WebRTC.
- Bitrate, framerate, or resolution user-tunable knobs.
- Authentication on the SRT stream (use `passphrase=` is a one-liner we can add later if LAN trust isn't enough).
- Stream preview thumbnail in the web UI.
- Persisting stream history / "recent sessions" metadata.

## Open risks

- **kmsgrab + tee output under sustained load** — the `-f tee` muxer has had historical bugs where one output's back-pressure stalls the other. `onfail=ignore` on the SRT leg mitigates but doesn't eliminate this; if we see MP4 glitches during streaming, the fallback is two separate ffmpegs reading from the same kmsgrab via a `-f mpegts pipe:` then `tee` as shell pipe. Validate during implementation.
- **SRT caller behavior when OBS is the listener but a firewall blocks the response** — ffmpeg logs `Connection timed out` after ~10s. We surface that. If it's a recurring user confusion, we can add a "Test connection" button that issues a short-lived ffmpeg probe.
- **Pi CPU headroom during simultaneous stream + record + active display** — Pi 5 should handle 1184×864@30fps x264 ultrafast + AAC encode + tee with margin. If we see kiosk frame drops during streaming, the fallback is `-preset superfast` or downscaling the stream leg only via tee's per-output filters.
- **`snd-aloop` interaction with audio-using services on boot ordering** — `modules-load.d` runs early; wyoming-satellite depends on `network.target`, so ordering is fine. But Sendspin's Flutter consumer opens the ALSA device later; if the module isn't loaded yet at that point we'll see a one-time open failure on boot. Mitigation: explicit `After=systemd-modules-load.service` on hearth.service if we see this.
