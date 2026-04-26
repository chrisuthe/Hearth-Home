# PipeWire Migration Design

**Status:** Draft
**Date:** 2026-04-26
**Author:** Chris (with Claude)
**Goal:** Move Hearth's audio layer from a hand-rolled ALSA setup (snd-aloop + custom asound.conf) to a single PipeWire-based stack.

## Why

Three converging reasons:

1. **Linux Voice Assistant migration path.** wyoming-satellite is officially deprecated; the OHF replacement (Linux Voice Assistant) is built on PipeWire. Migrating audio to PipeWire is a hard prerequisite if we ever want follow-up conversation, the new HA voice features, or media-player integration with the satellite.

2. **The current ALSA setup is fragile.** We just hit a real bug where `hdmi_tee` (a `multi` plugin needing 4 channels) silently broke Wyoming voice playback because Wyoming sends mono. This kind of channel-count incompatibility is a recurring class of bug in hand-rolled ALSA. PipeWire handles per-stream format negotiation natively — no `multi` bindings, no plug wrappers, just a routing graph that converts on the fly.

3. **Future capabilities open up.** Per-stream volume (voice quieter than music), Bluetooth speaker output without rewriting asound.conf, multi-device routing — all native to PipeWire. The current architecture can't do any of these without a rebuild.

## Current state — every audio path on the Pi

| # | Producer | Mechanism | Device target | Format |
|---|----------|-----------|---------------|--------|
| 1 | Wyoming mic input | `arecord -D plughw:CARD=Device,DEV=0` (subprocess) | USB mic, plughw direct | 16 kHz, mono, S16_LE |
| 2 | Wyoming TTS playback | `aplay -D plughw:CARD=vc4hdmi0,DEV=0` (subprocess) | HDMI direct | 22.05 kHz, mono, S16_LE |
| 3 | openWakeWord | Wyoming protocol — receives audio from Wyoming satellite, no direct hardware access | n/a | 16 kHz, mono |
| 4 | Sendspin (Spotify Connect FLAC) | Custom Dart isolate, FFI to `libasound.so.2`, opens PCM with `snd_pcm_open` | `sendspinAlsaDevice` config (default `hdmi_tee`) | 44.1 kHz, stereo, S16_LE |
| 5 | Music Assistant playback | Flutter `media_kit` plugin → libmpv | libmpv auto-detect (ALSA fallback on Pi) | varies |
| 6 | Camera RTSP playback (rare) | Same `media_kit` libmpv path | libmpv auto-detect | varies |
| 7 | Alarm/timer tones | `gst-launch-1.0 ... ! autoaudiosink` (subprocess) | GStreamer autoaudiosink (picks ALSA on this Pi) | OGG decoded |
| 8 | Stream-to-OBS audio capture | `ffmpeg -f alsa -i hw:Loopback,1,0` (subprocess via `sudo`) | Snd-aloop read end, fed by `hdmi_tee` multi → Loopback,0,0 | 48 kHz, stereo |

The custom routing knot:
```
                ┌─→ hw:vc4hdmi0,0  (HDMI speakers)
hdmi_tee (plug) ─→ multi (4ch)
                └─→ hw:Loopback,0,0  ─→  hw:Loopback,1,0 ─→ ffmpeg streaming
```

Producers writing to `hdmi_tee` (today: sendspin, plus the streaming-aware paths) get their audio simultaneously played and captured. Wyoming bypasses the tee (after the recent fix), since voice responses don't belong in OBS streams.

## Target state — PipeWire-native architecture

PipeWire owns all audio devices. A WirePlumber policy assigns the default sink (HDMI) and source (USB mic). All clients write to / read from PipeWire endpoints; PipeWire handles per-stream rate/channel/format conversion in its graph.

### Devices

| Endpoint | Type | Purpose |
|---|---|---|
| `alsa_output.platform-soc_sound.HiFi` (or similar — name auto-detected) | Sink | HDMI playback |
| `alsa_input.usb-Performance_Designed_Products_PDP_Audio_Device-...` | Source | USB mic |
| `hearth_obs_capture` | Null sink | Receives audio destined for the OBS stream; producers route here in addition to the default HDMI sink. ffmpeg reads from this null sink's monitor port. |

The "tee" disappears. Instead of a multi-slave bindings table, producers that should be streamed (sendspin, media_kit) link to *both* the HDMI sink and the `hearth_obs_capture` null sink — a routing-graph concern PipeWire handles natively.

### Producers

| # | Producer | New mechanism |
|---|----------|---------------|
| 1 | Wyoming mic | Keep `arecord` — PipeWire-ALSA bridge resolves `default` to PipeWire's source. (Or switch to `pw-record` for less indirection.) |
| 2 | Wyoming TTS | Keep `aplay -D default` — same PipeWire-ALSA bridge. |
| 3 | openWakeWord | No change (Wyoming protocol, no audio path). |
| 4 | Sendspin | Two viable paths: (a) keep ALSA FFI, point at `default` device which PipeWire-ALSA bridges to a PipeWire stream; (b) rewrite the FFI sink to use libpipewire directly. (a) is much less work; (b) is cleaner long-term. |
| 5 | media_kit | libmpv has native PipeWire support — set `--ao=pipewire` (or let it auto-detect, libmpv prefers PipeWire when available). |
| 6 | Camera RTSP | Same media_kit path. |
| 7 | Alarm tones | GStreamer's autoaudiosink picks `pipewiresink` when PipeWire is running. No code change. |
| 8 | OBS streaming | Switch ffmpeg to `-f pulse -i hearth_obs_capture.monitor` (PipeWire ships PulseAudio compatibility). Or `-f alsa -i pipewire` if pipewire-alsa exposes a stable name. |

### What gets deleted

- `/etc/asound.conf` (the hdmi_tee, multi, and bindings configuration)
- `/etc/modules-load.d/hearth-loopback.conf` (snd-aloop module load)
- `scripts/migrate-audio-routing.sh` (one-shot migration is no longer relevant)
- The ALSA-loopback section of `setup-pi.sh`
- HubConfig field `sendspinAlsaDevice` becomes irrelevant for routing — sendspin just writes to the PipeWire default sink. Could be removed entirely or repurposed as a PipeWire endpoint name override for power users.

### What stays the same

- Wyoming systemd unit's mic/snd commands (PipeWire-ALSA bridge keeps `aplay`/`arecord` working)
- Hearth's Dart code paths for sendspin (if we go with FFI-via-bridge approach)
- The kmsgrab video capture in stream_service.dart
- alarm_audio.dart's gst-launch invocation

## Migration tasks (rough sequence)

This is a sketch, not a TDD plan — exact ordering and granularity will land in the eventual implementation plan.

### Phase 1: Install PipeWire, validate side-by-side

1. Install `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber` packages on the Pi
2. Decide system-vs-user mode for the daemon (more on this below — open question)
3. Verify the PipeWire daemon starts cleanly on next boot, identifies HDMI as default sink and USB mic as default source
4. Run `pw-cli list-objects | grep -i node` to inventory what PipeWire sees
5. Smoke-test each path with the existing config still in place: `aplay -D default`, `arecord -D default`, `gst-launch-1.0 ... ! autoaudiosink`, libmpv `--ao=pipewire`. Goal: confirm the bridge works for unmodified clients.

### Phase 2: Replace the OBS-tee routing

6. Define the `hearth_obs_capture` null sink in WirePlumber config (one config file under `/etc/pipewire/pipewire.conf.d/`)
7. Add a routing rule that auto-connects producers tagged for streaming to both default sink + null sink (TBD: how to tag — see open questions)
8. Update `stream_service.ffmpegStartStream` to read from the null sink's monitor: `-f pulse -i hearth_obs_capture.monitor` (PipeWire's pulse compatibility makes this trivial)
9. Test: start a stream, verify audio reaches OBS, verify HDMI playback isn't doubled or muted

### Phase 3: Decommission ALSA loopback

10. Remove `/etc/asound.conf`, `/etc/modules-load.d/hearth-loopback.conf`
11. Unload `snd-aloop` (will rejoin on reboot if not removed from modules-load)
12. Update `scripts/setup-pi.sh` — drop the asound.conf write, drop the speaker-test sanity check, drop snd-aloop module-load setup, replace with PipeWire/WirePlumber install + null-sink config
13. Delete `scripts/migrate-audio-routing.sh` — its purpose is obsolete

### Phase 4: Update Hearth code

14. Decide sendspin path (keep FFI via bridge, or switch to libpipewire). Recommend (a) for v1, defer (b).
15. Update `lib/services/sendspin/alsa_audio_sink.dart` device discovery to query PipeWire endpoints if going native, OR leave alone if using ALSA bridge
16. Update Settings → Sendspin device picker — either remove (default sink is fine) or repopulate with PipeWire endpoints
17. Update CLAUDE.md's audio architecture notes
18. Update relevant specs: `docs/specs/2026-04-12-voice-satellite-design.md`, `docs/specs/2026-04-24-stream-to-obs-design.md`

### Phase 5: Cleanup + future-proofing

19. Once stable, plan the Linux Voice Assistant migration as a follow-up — wyoming-satellite stays for now, but its replacement is unblocked
20. Document the PipeWire architecture as a permanent doc (this spec becomes the historical record)

## Risks and mitigations

### High risk

- **PipeWire user-vs-system daemon split.** PipeWire is typically per-user (`systemctl --user start pipewire`). Hearth runs as `hearth` user, but Wyoming runs as `hearth` too — same user, so a per-user daemon should work for both. The risk is `setup-pi.sh` currently runs as the provisioning user (often `pi`), which is different. **Mitigation:** explicitly start PipeWire as the `hearth` user via systemd user services, lingering enabled (`loginctl enable-linger hearth`).

- **Sendspin FFI behavior under bridge.** The custom ALSA FFI does direct `snd_pcm_writei` calls. PipeWire-ALSA *should* be transparent, but FLAC streaming has tight timing. **Mitigation:** dedicated test phase — stream a 60-second FLAC track through sendspin and verify no buffer underruns or glitches. If it breaks, fall back to libpipewire native sink (which is the cleaner long-term path anyway).

- **OBS stream audio capture path.** ffmpeg's `-f pulse` works against PipeWire's pulse compatibility, but the exact endpoint name format and any pulse-server discovery behavior differs from real Pulse. **Mitigation:** test with a real OBS instance, check for sample-rate drift / clock skew over a long stream.

### Medium risk

- **Default-sink selection at boot.** WirePlumber's policy needs to consistently pick HDMI even when USB mic is also present. **Mitigation:** explicit WirePlumber rule pinning HDMI as default sink by node name.

- **media_kit / libmpv version compatibility.** libmpv's PipeWire backend has had bugs in some versions (gapless playback, fast-track-switching glitches). **Mitigation:** check installed libmpv version on the Pi; if older than ~0.36 consider letting libmpv keep using ALSA via the bridge.

- **Alarm tones via gst autoaudiosink.** GStreamer 1.x's autoaudiosink should pick pipewiresink when PipeWire is running, but there have been bugs where it picked alsasink even with PipeWire active. **Mitigation:** explicitly hardcode `pipewiresink` in alarm_audio.dart's gst-launch arg list instead of relying on autoaudiosink.

### Low risk

- **Existing OBS streamer users / ALSA muscle memory.** Anyone with custom asound.conf tweaks loses them. Hearth's only known custom-tweak is `sendspinAlsaDevice` config field. **Mitigation:** version bump + clear release note.

- **Disk/CPU footprint of PipeWire.** PipeWire + WirePlumber is light (well under 50 MB resident, typically <1% CPU idle on Pi 5). Negligible.

## Validation plan

Each phase exits only when these checks pass:

**After Phase 1:**
- `aplay /usr/share/sounds/alsa/Front_Center.wav` plays through HDMI
- `arecord -d 2 /tmp/test.wav && aplay /tmp/test.wav` works (round-trip mic)
- Hearth boots, voice command works (mic→openWakeWord→ASR→TTS→audio out)
- `wpctl status` shows expected default sink/source

**After Phase 2:**
- Sendspin plays a track, OBS receives video AND audio without glitches
- Wyoming voice command audible on HDMI but NOT in OBS stream (the desired isolation)
- Both can run simultaneously

**After Phase 3:**
- After full reboot (no manual modprobe, no asound.conf), all of Phase 2 still passes
- `lsmod | grep aloop` returns nothing (snd-aloop gone)
- `cat /etc/asound.conf` returns "No such file" (or empty, system default)

**After Phase 4:**
- Settings UI for sendspin device shows PipeWire endpoints (or is gracefully removed)
- Fresh Pi setup via the new `setup-pi.sh` reaches a working state without manual intervention

## Rollback plan

If anything in Phase 2 or later breaks the kiosk's audio:

1. Restore `/etc/asound.conf` and `/etc/modules-load.d/hearth-loopback.conf` from git history (`git show HEAD:scripts/setup-pi.sh`)
2. `sudo modprobe snd-aloop`
3. `sudo systemctl --user stop pipewire pipewire-pulse wireplumber` (or uninstall PipeWire packages)
4. `sudo systemctl restart hearth wyoming-satellite`

Phase 1 is non-destructive (PipeWire installs alongside ALSA-direct, doesn't change asound.conf yet) — the rollback only matters from Phase 2 onward.

## Out of scope / explicitly deferred

- **Linux Voice Assistant migration.** This spec only does the audio-layer migration. Switching satellites is a separate project (probably 2027) once PipeWire is stable.
- **Per-stream volume UX.** PipeWire enables per-stream volume, but adding UI for it is feature work, not part of this migration.
- **Bluetooth speaker support.** PipeWire enables it; adding a "pair speaker" UX is feature work.
- **Multi-room audio.** Same — capability unlocked but UX is separate.
- **Native libpipewire FFI for sendspin.** Phase 4 keeps sendspin on the ALSA bridge. The native rewrite is a future cleanup once we have a baseline working.

## Open questions

1. **System vs. user PipeWire daemon?** Per-user is conventional; system-wide is sometimes done for kiosks. We need to confirm Wyoming and Hearth both run as the same user (`hearth`), and if so, per-user with linger is the right answer. Verify before Phase 1.

2. **How do producers tag themselves for streaming?** PipeWire has `media.role` and `application.name` that can be used in WirePlumber rules. Need to decide which producers (sendspin? media_kit? both?) should fan out to both HDMI and the OBS null sink. Probably: sendspin yes, media_kit (Music Assistant) yes, alarm tones no (alarms shouldn't go in someone's stream), Wyoming TTS no (already correct).

3. **Does ffmpeg's `-f pulse` work cleanly against PipeWire's pulse compat layer in the version on the Pi?** Need to verify on the actual installed ffmpeg version, since pulse compat has had edge cases.

4. **Should we rewrite sendspin to use libpipewire natively in Phase 4, or defer indefinitely?** The bridge is fine functionally; native is cleaner architecturally and removes the libasound dependency. Leaning defer — let's get the migration done first.

5. **Compatibility with `migrate-audio-routing.sh`.** That script applied the old ALSA-tee setup to Pis that pre-dated it. After this PipeWire migration ships, do existing Pis need a comparable "migrate-to-pipewire.sh" shell script, or should they just re-run `setup-pi.sh` (which is intended to be idempotent)? Probably the latter — verify setup-pi.sh handles the ALSA-tee → PipeWire transition gracefully.

## Effort estimate

- **Phase 1:** half day — package install, smoke tests, no Hearth changes
- **Phase 2:** 1-2 days — null-sink design, ffmpeg invocation update, stream validation
- **Phase 3:** half day — file deletions, setup-pi.sh edits, reboot test
- **Phase 4:** 1-2 days depending on sendspin path chosen — Hearth code + Settings UI
- **Phase 5:** ongoing

Total wall-clock: ~3-5 days of focused work, assuming no surprises in the streaming path. This is a "block out a long weekend" project, not a "knock out before bed" one.
