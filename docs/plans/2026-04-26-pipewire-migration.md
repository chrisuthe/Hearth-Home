# PipeWire Migration Implementation Plan

**Spec:** [docs/specs/2026-04-26-pipewire-migration-design.md](../specs/2026-04-26-pipewire-migration-design.md)

**Goal:** Replace Hearth's hand-rolled ALSA stack (snd-aloop loopback + custom `hdmi_tee` `multi` plugin in `/etc/asound.conf`) with PipeWire as the audio daemon. Producers continue working via PipeWire's ALSA/Pulse bridges. Streaming-to-OBS routing moves from a kernel loopback to a PipeWire null-sink.

**Architecture summary:** PipeWire owns hardware. WirePlumber assigns default sink (HDMI) and source (USB mic). All existing audio clients (`aplay`, `arecord`, libmpv, gstreamer, sendspin's libasound FFI) continue to work via pipewire-alsa. A PipeWire null-sink named `hearth_obs_capture` receives audio destined for the OBS stream; ffmpeg reads from its monitor. The `hdmi_tee` multi-plugin and snd-aloop loopback go away.

**Tech Stack:** PipeWire 1.4+, WirePlumber, pipewire-alsa, pipewire-pulse, ffmpeg, existing GStreamer / libmpv / libasound consumers (unchanged).

**Note on plan format:** Most tasks are system administration (config edits, service restarts) rather than code with testable units, so steps don't follow strict TDD. Each task still has a verification check before moving on, and commits are scoped per task.

---

## Phase 1 — Install PipeWire and validate side-by-side

Goal: get PipeWire running on the Pi alongside the existing ALSA-direct and snd-aloop setup, with no Hearth changes yet. Existing audio paths must continue working through PipeWire's ALSA bridge before we remove anything.

### Task 1.1: Resolve the user-vs-system daemon question

**Files:** None (research task, results captured in this plan).

- [ ] **Step 1: Verify Hearth and Wyoming both run as the `hearth` user**

```bash
ssh hearthdev@10.0.1.13 'systemctl show hearth.service -p User; systemctl show wyoming-satellite.service -p User'
```

Expected: both report `User=hearth`.

- [ ] **Step 2: Decide daemon mode**

If both run as `hearth`, the conventional path is per-user PipeWire with linger enabled. If they run as different users, a system-wide daemon is required (more complex). Document the decision inline below before proceeding.

**DECISION:** **per-user**, with `loginctl enable-linger hearth`. Verified 2026-04-26: `hearth.service`, `wyoming-satellite.service`, and `wyoming-openwakeword.service` all run as `User=hearth` (uid 999, member of the `audio` group). Single PipeWire daemon under uid 999 serves all three.

### Task 1.2: Install PipeWire packages

**Files:**
- Modify: `scripts/setup-pi.sh` (add install block; do NOT remove snd-aloop yet)

- [ ] **Step 1: Install on the live Pi**

```bash
ssh hearthdev@10.0.1.13 'sudo apt-get update && sudo apt-get install -y pipewire pipewire-pulse pipewire-alsa wireplumber'
```

Expected: clean install, no errors.

- [ ] **Step 2: Enable per-user lingering (if user-mode chosen)**

```bash
ssh hearthdev@10.0.1.13 'sudo loginctl enable-linger hearth'
```

- [ ] **Step 3: Start the daemon for `hearth`**

```bash
ssh hearthdev@10.0.1.13 'sudo -u hearth XDG_RUNTIME_DIR=/run/user/$(id -u hearth) systemctl --user enable --now pipewire pipewire-pulse wireplumber'
```

Expected: services report `active (running)`.

- [ ] **Step 4: Update `setup-pi.sh` so fresh installs get PipeWire too**

Add the install/enable block under a clearly labeled `### PipeWire audio stack ###` section. Keep snd-aloop install in place for now (we remove in Phase 3).

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-pi.sh
git commit -m "feat(audio): install PipeWire alongside ALSA on Pi setup"
```

### Task 1.3: Verify default device assignment

**Files:** None — verification only.

- [ ] **Step 1: Inventory PipeWire's view of the world**

```bash
ssh hearthdev@10.0.1.13 'XDG_RUNTIME_DIR=/run/user/$(id -u hearth) wpctl status'
```

Expected output structure:
- Default Sink — should point at the HDMI device (`alsa_output.platform-fef00700.hdmi.HiFi.hw_vc4hdmi0_0` or similar)
- Default Source — should point at the USB mic (`alsa_input.usb-Performance_Designed_Products_PDP_*`)

- [ ] **Step 2: If defaults are wrong, pin them via WirePlumber rule**

If the Pi auto-selected the wrong default (e.g., picked Loopback as the sink), create `/etc/wireplumber/wireplumber.conf.d/50-hearth-defaults.conf`:

```
monitor.alsa.rules = [
  {
    matches = [ { node.name = "alsa_output.platform-fef00700.hdmi.HiFi.hw_vc4hdmi0_0" } ]
    actions = { update-props = { priority.driver = 2000, priority.session = 2000 } }
  }
]
```

(Replace the node name with whatever `wpctl status` reported.)

Restart wireplumber and re-verify.

### Task 1.4: Smoke-test each consumer through the bridge

For each producer below, verify it still works with PipeWire running. The `hdmi_tee` ALSA config still exists at this point — clients using it should continue to work because PipeWire owns the hardware and the ALSA bridge handles the conversion.

**Files:** None — verification only.

- [ ] **Step 1: Test `aplay` direct path (Wyoming TTS uses this)**

```bash
ssh hearthdev@10.0.1.13 'aplay -D plughw:CARD=vc4hdmi0,DEV=0 /usr/share/sounds/alsa/Front_Center.wav'
```

Expected: voice plays "front center" through HDMI. May need to adjust `pcm.!default` config, since PipeWire grabs hardware exclusively in some configurations.

- [ ] **Step 2: Test `aplay` against PipeWire's default**

```bash
ssh hearthdev@10.0.1.13 'aplay -D default /usr/share/sounds/alsa/Front_Center.wav'
```

Expected: voice plays. This validates that the pipewire-alsa bridge is wired up.

- [ ] **Step 3: Test `arecord` (Wyoming mic uses this)**

```bash
ssh hearthdev@10.0.1.13 'arecord -D plughw:CARD=Device,DEV=0 -d 2 -f S16_LE -r 16000 -c 1 /tmp/test.wav && aplay /tmp/test.wav'
```

Expected: 2-second mic recording plays back.

- [ ] **Step 4: Test full Wyoming voice flow**

Trigger a voice command on the kiosk: "ok nabu, what's the weather". Expected: response audible through HDMI, no errors in `journalctl -u wyoming-satellite -n 20`.

- [ ] **Step 5: Test sendspin (libasound FFI)**

Stream a Sendspin track to the Hearth kiosk. Expected: audible playback, no glitches over a 60-second test track.

- [ ] **Step 6: Test alarm tones (gst-launch autoaudiosink)**

Set a one-minute alarm via the alarm clock module. Expected: tone plays at fire time.

- [ ] **Step 7: Test media_kit (Music Assistant)**

Play a track via Music Assistant from the Hearth UI. Expected: audible playback.

- [ ] **Step 8: Confirm OBS streaming still works**

(Streaming hasn't been changed yet — `ffmpeg -f alsa -i hw:Loopback,1,0` is unchanged.) Start a stream, check audio reaches OBS.

If any of steps 1-8 fail, stop here and fix before proceeding to Phase 2. Phase 1 is non-destructive — rollback is removing the PipeWire packages.

---

## Phase 2 — Replace the OBS-tee routing with a PipeWire null-sink

Goal: stop using snd-aloop for streaming. Producers tagged for streaming send to both HDMI sink + a PipeWire null-sink; ffmpeg reads from the null-sink's monitor.

### Task 2.1: Define the null-sink and routing rules

**Files:**
- Create: `/etc/pipewire/pipewire.conf.d/10-hearth-obs-capture.conf` (on the Pi; tracked in setup-pi.sh)
- Modify: `scripts/setup-pi.sh`

- [ ] **Step 1: Draft the null-sink config**

```
context.objects = [
  {
    factory = adapter
    args = {
      factory.name = support.null-audio-sink
      node.name = "hearth_obs_capture"
      node.description = "Hearth OBS Capture"
      media.class = Audio/Sink
      audio.position = [ FL FR ]
    }
  }
]
```

This creates a stereo null-sink named `hearth_obs_capture` with a monitor port automatically.

- [ ] **Step 2: Decide which producers route here**

Per the design spec's open question: sendspin yes, media_kit yes, alarm tones no, Wyoming no.

The cleanest pattern is "duplicate to monitor" via a WirePlumber rule that matches by `application.name` or `media.role` and creates a parallel link. Concrete rule for `sendspin` and `media_kit` (libmpv):

`/etc/wireplumber/wireplumber.conf.d/50-hearth-obs-routing.conf`:

```
monitor.alsa.rules = []  # noop — placeholder so file is structurally valid

stream.rules = [
  {
    matches = [
      { application.name = "sendspin" },
      { application.name = "mpv" },
      { application.process.binary = "music_kit_libmpv*" }
    ]
    actions = {
      update-props = {
        target.object = "<default-sink>"  # primary HDMI route stays
      }
      # Plus a parallel link to hearth_obs_capture — see ALT NOTE below
    }
  }
]
```

**ALT NOTE:** PipeWire doesn't directly support "send to two sinks" via stream.rules out of the box. Two implementation options:
- **Option A:** Use `module-loopback` to mirror selected streams from a virtual sink to the null-sink (more PulseAudio-native)
- **Option B:** Use a pw-link rule that runs on stream creation to wire the additional connection

Option B is more PipeWire-idiomatic but trickier. Option A is the PA-compat path and works reliably. Pick during implementation; default to A if undecided.

- [ ] **Step 3: Apply the configs to the Pi and reload**

```bash
ssh hearthdev@10.0.1.13 'XDG_RUNTIME_DIR=/run/user/$(id -u hearth) systemctl --user restart pipewire wireplumber'
```

- [ ] **Step 4: Verify the null-sink exists**

```bash
ssh hearthdev@10.0.1.13 'XDG_RUNTIME_DIR=/run/user/$(id -u hearth) wpctl status | grep -A1 hearth_obs'
```

Expected: `hearth_obs_capture` listed under Sinks, with a `.monitor` port.

- [ ] **Step 5: Test producer routing**

Play a sendspin track. Run:

```bash
ssh hearthdev@10.0.1.13 'XDG_RUNTIME_DIR=/run/user/$(id -u hearth) pw-link -l | grep -B1 -A1 obs_capture'
```

Expected: see the sendspin client connected to both HDMI sink AND `hearth_obs_capture`.

- [ ] **Step 6: Update `setup-pi.sh` to write both configs**

Add the heredoc-write blocks for `/etc/pipewire/pipewire.conf.d/10-hearth-obs-capture.conf` and `/etc/wireplumber/wireplumber.conf.d/50-hearth-obs-routing.conf`.

- [ ] **Step 7: Commit**

```bash
git add scripts/setup-pi.sh
git commit -m "feat(audio): pipewire null-sink for OBS streaming, route sendspin+media_kit"
```

### Task 2.2: Update ffmpeg to read from the null-sink monitor

**Files:**
- Modify: `lib/services/stream_service.dart` (the `ffmpegStartStream` function around line 282)

- [ ] **Step 1: Update the audio input args**

Replace:
```dart
'-thread_queue_size', '512',
'-f', 'alsa',
'-ac', '2',
'-ar', '48000',
'-i', 'hw:Loopback,1,0',
```

With:
```dart
'-thread_queue_size', '512',
'-f', 'pulse',
'-i', 'hearth_obs_capture.monitor',
```

(`-ac` and `-ar` are negotiated by the pulse input automatically; let it pick.)

- [ ] **Step 2: Update the doc comment for `ffmpegStartStream`**

Replace the "via the ALSA loopback (provisioned by setup-pi.sh's `hdmi_tee` route)" line with "via the PipeWire null-sink `hearth_obs_capture` monitor (provisioned by setup-pi.sh's PipeWire config)".

- [ ] **Step 3: Run analyzer + tests**

```bash
flutter analyze lib/services/stream_service.dart
flutter test test/services/stream_service_test.dart
```

Expected: clean. Tests use a `FakeStreamingProcess` and don't actually invoke ffmpeg, so no test changes needed.

- [ ] **Step 4: Live-test the streaming**

Tag a release, deploy to the Pi, start a stream from Hearth's UI, point OBS at the SRT URL. Expected: audio + video reach OBS without glitches over a 60-second test stream.

- [ ] **Step 5: Commit**

```bash
git add lib/services/stream_service.dart
git commit -m "fix(stream): read OBS audio from PipeWire null-sink instead of snd-aloop"
```

---

## Phase 3 — Decommission ALSA loopback and `hdmi_tee`

Goal: remove the now-unused snd-aloop kernel module config and the `/etc/asound.conf` `hdmi_tee` definition. Validate that nothing depends on them anymore.

### Task 3.1: Remove the kernel-level loopback

**Files:**
- Modify: `scripts/setup-pi.sh` (drop the snd-aloop block)
- Delete: `/etc/modules-load.d/hearth-loopback.conf` (on the Pi)

- [ ] **Step 1: Remove on the live Pi**

```bash
ssh hearthdev@10.0.1.13 'sudo rm /etc/modules-load.d/hearth-loopback.conf && sudo modprobe -r snd-aloop'
```

If `modprobe -r` fails with "module is in use", something still depends on it — investigate before continuing.

- [ ] **Step 2: Update `setup-pi.sh`**

Remove the `modprobe snd-aloop` and `tee /etc/modules-load.d/hearth-loopback.conf` lines.

- [ ] **Step 3: Reboot the Pi and verify**

```bash
ssh hearthdev@10.0.1.13 'sudo reboot'
# wait ~60s
ssh hearthdev@10.0.1.13 'lsmod | grep aloop; echo "---"; systemctl status hearth.service wyoming-satellite.service'
```

Expected: `lsmod` returns nothing for aloop. Both services active.

- [ ] **Step 4: Re-run all Phase 1 step 4 smoke tests + Phase 2 step 4 streaming test**

If anything regressed, this is the rollback point — `modprobe snd-aloop`, restore the modules-load file, restore asound.conf, and re-investigate.

### Task 3.2: Remove `/etc/asound.conf`

**Files:**
- Delete: `/etc/asound.conf` (on the Pi)
- Modify: `scripts/setup-pi.sh` (drop the `hdmi_tee` write block + the speaker-test sanity check)

- [ ] **Step 1: Remove on the live Pi**

```bash
ssh hearthdev@10.0.1.13 'sudo rm /etc/asound.conf'
```

- [ ] **Step 2: Update `setup-pi.sh`**

Remove the `tee /etc/asound.conf` heredoc block and the `speaker-test ... arecord ... /tmp/hearth-audio-check.wav` sanity check (both no longer make sense without `hdmi_tee`).

- [ ] **Step 3: Re-run all smoke tests**

Same as Task 3.1 step 4.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-pi.sh
git commit -m "chore(audio): drop snd-aloop and /etc/asound.conf from setup-pi"
```

### Task 3.3: Delete the migration script

**Files:**
- Delete: `scripts/migrate-audio-routing.sh`

- [ ] **Step 1: Confirm no other references**

```bash
grep -rn "migrate-audio-routing" docs/ scripts/
```

If any hits remain in docs, update those docs to reference the PipeWire migration plan instead.

- [ ] **Step 2: Delete the script**

```bash
git rm scripts/migrate-audio-routing.sh
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(audio): drop migrate-audio-routing.sh — superseded by PipeWire migration"
```

---

## Phase 4 — Update Hearth code

Goal: clean up Hearth's now-stale audio config surface and align documentation with the new architecture.

### Task 4.1: Repurpose or remove `sendspinAlsaDevice` config field

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/services/sendspin/sendspin_service.dart`
- Modify: `lib/services/sendspin/alsa_audio_sink.dart`

The field currently picks an ALSA device name (`hdmi_tee` by default). Under PipeWire, sendspin's libasound FFI calls land on the bridge and resolve to PipeWire's default sink — no per-track device selection is necessary for the common case. Two options:

**Option A: Remove the field entirely.** Sendspin always writes to PipeWire's default sink. Simpler, fewer settings. Loses the ability to direct sendspin to a different output (e.g., Bluetooth speaker without changing system default).

**Option B: Keep the field, repurpose it as PipeWire endpoint name.** Default value changes from `hdmi_tee` to empty/null (meaning "default sink"). Listing in Settings queries PipeWire endpoints via `wpctl` instead of `/proc/asound`. More flexible, more code.

**RECOMMENDED:** Option A for v1 — remove the field, hardcode `default` device. Add Option B back if a real use case appears.

- [ ] **Step 1: Remove the field from `HubConfig`**

Drop declaration, default, `copyWith`, `toJson`, `fromJson`. Migrate existing config files: when reading, ignore an existing `sendspinAlsaDevice` key gracefully.

- [ ] **Step 2: Update `AlsaAudioSink` default device**

```dart
AlsaAudioSink({this.device = 'default'});  // was: 'default' too — actually no change here
```

- [ ] **Step 3: Update `SendspinService` to no longer plumb the device**

Remove `_alsaDevice` field, the `alsaDevice` parameter on the constructor, and the `ref.watch(hubConfigProvider.select((c) => c.sendspinAlsaDevice))`.

Replace the `AlsaAudioSink(device: _alsaDevice)` call with `AlsaAudioSink()` (uses `default`).

- [ ] **Step 4: Remove the Sendspin device picker from Settings**

Drop the `AlsaAudioSink.listPlaybackDevices()` block in settings_screen.dart.

- [ ] **Step 5: Run analyzer + tests**

```bash
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/config/hub_config.dart lib/screens/settings/settings_screen.dart lib/services/sendspin/
git commit -m "refactor(sendspin): drop alsaDevice config — defaults to PipeWire sink"
```

### Task 4.2: Update CLAUDE.md and existing specs

**Files:**
- Modify: `CLAUDE.md` (architecture section if it mentions audio)
- Modify: `docs/specs/2026-04-12-voice-satellite-design.md` (audio routing section)
- Modify: `docs/specs/2026-04-24-stream-to-obs-design.md` (audio routing section)

- [ ] **Step 1: Find and update audio architecture mentions**

```bash
grep -rn "snd-aloop\|hdmi_tee\|/etc/asound.conf\|loopback" CLAUDE.md docs/specs/
```

For each match, update the description to reference PipeWire null-sink + WirePlumber routing.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md docs/specs/
git commit -m "docs(audio): update architecture references to PipeWire"
```

---

## Phase 5 — Cleanup and future-proofing

### Task 5.1: Update auto memory

**Files:**
- Modify: `~/.claude/projects/C--Users-chris-hearth/memory/MEMORY.md`
- Possibly remove: `project_gstreamer_rtsp_debug.md` (still relevant?)
- Possibly remove: `project_mic_mute_bug.md` (does PipeWire change the mic mute story? the systemctl path is unchanged, but ALSA mute may now work differently)

- [ ] **Step 1: Add a memory entry for the migration**

Save what was learned: PipeWire daemon mode chosen, OBS routing approach (Option A vs B from Task 2.1), any gotchas during migration.

### Task 5.2: Tag a release and deploy

- [ ] **Step 1: Bump version, push, tag**

```bash
git push origin main
git tag v1.X.0
git push origin v1.X.0
```

Note: bump the minor version (1.8.0?), not patch — this is a non-trivial architecture change worth flagging in release notes.

- [ ] **Step 2: Watch CI build**

```bash
gh run watch <run-id> --exit-status
```

- [ ] **Step 3: Pi auto-pulls via OTA updater on its next cycle**

(No manual updater trigger needed — the OTA timer fires every few minutes.)

- [ ] **Step 4: Verify on the Pi**

Run all the smoke tests from Phase 1.4 one more time. Goal: confirm the deployed bundle works as well as the manual test setup.

---

## Validation checklist (run before declaring done)

- [ ] `aplay -D default <somefile>` plays through HDMI
- [ ] `aplay -D plughw:CARD=vc4hdmi0,DEV=0 <somefile>` still works
- [ ] Wyoming voice command: full mic→TTS→audible response cycle
- [ ] Sendspin: 60-second track plays without glitches
- [ ] Music Assistant: full track plays from Hearth UI
- [ ] Alarm tones fire on schedule, audible
- [ ] OBS streaming: video + audio reach OBS, sync stays correct over a 60s stream
- [ ] After full Pi reboot: all of the above still pass without manual intervention
- [ ] `lsmod | grep aloop` returns nothing
- [ ] `cat /etc/asound.conf` returns "No such file" or empty
- [ ] `wpctl status` shows expected default sink (HDMI), default source (USB mic), and `hearth_obs_capture` null sink

## Rollback (if a phase breaks the kiosk)

Per phase:

- **Phase 1 broken:** `apt remove pipewire pipewire-pulse pipewire-alsa wireplumber` — system reverts to ALSA-direct.
- **Phase 2 broken:** revert the ffmpeg input change in stream_service.dart, redeploy. The null-sink config can stay in place.
- **Phase 3 broken:** restore `/etc/asound.conf` and `/etc/modules-load.d/hearth-loopback.conf` from git history (`git show HEAD~N:scripts/setup-pi.sh` to recover the heredoc bodies), `sudo modprobe snd-aloop`, restart services.
- **Phase 4 broken:** revert the Hearth code commits, redeploy.

The migration is per-phase reversible with no cumulative risk if you stop after each phase passes its smoke tests.

## Effort estimate (refined from spec)

- Phase 1: half day (mostly waiting on apt install + smoke tests)
- Phase 2: 1-2 days (the routing rule design is the unknown — Option A vs B testing)
- Phase 3: half day
- Phase 4: half day
- Phase 5: hours

**Total: 3-4 days focused work, plus a buffer for the "PipeWire's pulse compatibility ate my edge case" surprise.**
