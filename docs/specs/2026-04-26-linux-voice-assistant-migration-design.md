# Linux Voice Assistant Migration Design

**Status:** Draft
**Date:** 2026-04-26
**Author:** Chris (with Claude)
**Goal:** Replace `wyoming-satellite` + `wyoming-openwakeword` on the Pi with [Linux Voice Assistant](https://github.com/OHF-Voice/linux-voice-assistant) (LVA) — the official Open Home Foundation successor.

## Why

1. **wyoming-satellite is deprecated.** The OHF released LVA as its replacement; upstream development has shifted there.
2. **Continue-conversation support.** LVA exposes `start/continue conversation` natively. Wyoming-satellite 1.4.1 hardcodes `restart_on_end = False` and has no path to follow-up — every voice command requires the wake word again.
3. **Voice ducking unblocked.** LVA uses persistent PipeWire streams with proper `media.role` tagging, which makes WirePlumber-rule-based ducking trivial. Wyoming-satellite's per-response `aplay` subprocess gives PipeWire too-short stream lifetimes to react against.
4. **Better audio mute path.** LVA bundles a mute mechanism (`--mute-sound`/`--unmute-sound` config + presumably an internal pause-wakeword); the existing UX bug (Gitea #130 — ALSA-mute toolbar icon doesn't actually stop voice processing) becomes addressable, possibly resolves outright.
5. **Modern feature surface.** Announcements, timers, media-player integration with the satellite — all Wyoming-satellite lacks.

## Current state — what we have today

```
┌─────────────────────────┐          ┌─────────────────────────┐
│  wyoming-satellite      │  Wyoming │  Home Assistant         │
│  (Python, port 10700)   │ protocol │  Wyoming integration    │
│                         ├──────────►                         │
│  --mic-command arecord  │          │  Creates entity:        │
│  --snd-command aplay    │          │  assist_satellite.hearth│
│  --wake-uri (oww)       │          │                         │
└─────────────────────────┘          └──────────┬──────────────┘
            │                                   │
            │   Wyoming protocol                │  HA WebSocket
            ▼                                   ▼
┌─────────────────────────┐          ┌─────────────────────────┐
│  wyoming-openwakeword   │          │  Hearth (flutter-pi)    │
│  (Python, port 10400)   │          │  voice_assistant_service│
│  ok_nabu wake word      │          │  listens to entityStream│
└─────────────────────────┘          └─────────────────────────┘
```

Two systemd services on the Pi (`wyoming-satellite.service`, `wyoming-openwakeword.service`), both running as `hearth` user. State transitions reach Hearth via HA's `assist_satellite.hearth` entity, which `voice_assistant_service.dart` consumes through `_ha.entityStream`.

## Target state — Linux Voice Assistant

```
┌─────────────────────────┐         ┌─────────────────────────┐
│  Linux Voice Assistant  │ ESPHome │  Home Assistant         │
│  (Python, port 6053)    │   API   │  ESPHome integration    │
│                         ├─────────►                         │
│  Bundled openWakeWord   │  mDNS   │  Creates entity:        │
│  (--wake-model ok_nabu) │  disco  │  assist_satellite.<name>│
│  PipeWire I/O via       │         │                         │
│  PULSE_SERVER           │         │                         │
└─────────────────────────┘         └──────────┬──────────────┘
                                               │  HA WebSocket
                                               ▼
                                    ┌─────────────────────────┐
                                    │  Hearth (flutter-pi)    │
                                    │  voice_assistant_service│
                                    │  unchanged — same       │
                                    │  assist_satellite domain│
                                    └─────────────────────────┘
```

**Key insight:** HA's `assist_satellite` entity domain is protocol-agnostic — it gets populated whether the satellite uses Wyoming protocol or ESPHome protocol. So Hearth's `voice_assistant_service.dart` (which listens for `assist_satellite.*` entities via `_ha.entityStream`) needs **no changes**. The state transitions still flow through the same path.

### What's the same

- HA-side: `assist_satellite` entity domain.
- Hearth: `voice_assistant_service.dart`, the voice pill UI, the entity-watching logic.
- Wake word: `okay_nabu` (LVA's default, matches today).
- Audio: PipeWire bridge via `PULSE_SERVER=unix:/run/user/999/pulse/native` — same pattern we used for `hearth.service` and `wyoming-satellite.service`.
- Run as `hearth` user (uid 999).

### What changes

- Two systemd services (`wyoming-satellite.service`, `wyoming-openwakeword.service`) replaced by one (`linux-voice-assistant.service`).
- Wake-word detection moves from a separate process to LVA's bundled `openWakeWord` (or `microWakeWord`).
- Subprocess `aplay`/`arecord` paths replaced by LVA's libpipewire-pulse direct integration.
- HA-side: switch from Wyoming integration to ESPHome integration for the satellite (auto-discovered via mDNS).
- The existing `assist_satellite.hearth` entity will be replaced with a new one whose entity ID depends on what name LVA reports to HA via ESPHome. May or may not be `assist_satellite.hearth` exactly.

### What gets unlocked

- **Continue conversation** — built-in, no work needed beyond enabling the right HA pipeline option.
- **Voice ducking** — small WirePlumber rule matching `media.role=communication` that ducks other streams while voice plays. Validates LVA's role tagging while delivering the long-deferred feature.
- **Announcements, timers, media-player** — features for later, not part of this migration.

### What gets cleaned up

- `wyoming-satellite.service` + `wyoming-openwakeword.service` systemd units.
- `/opt/wyoming/satellite-env/`, `/opt/wyoming/wyoming-openwakeword/` Python venvs (Wyoming's installs).
- `setup-pi.sh` Wyoming install + service-write blocks (~80 lines).
- `lib/services/voice_assistant_service.dart` `mute()`, `unmute()`, `isSatelliteRunning` methods (Gitea #130's preserved fix path) — they reference `wyoming-satellite.service` which won't exist after migration. The bug the user reported (ALSA mute doesn't stop voice processing) gets re-evaluated against LVA's mute mechanism.
- `/etc/sudoers.d/hearth-voice` (the NOPASSWD rules for restarting wyoming-satellite).

## Migration approach

Two viable strategies:

### Strategy A — Side-by-side test, then cutover (recommended)

1. Install LVA in parallel with Wyoming. LVA on port 6053, Wyoming on its existing port (10700 satellite, 10400 wakeword). They listen on different ports; HA can discover both. The user's HA setup gets a SECOND `assist_satellite` entity (whichever LVA registers as).
2. Create a separate Voice Assistant pipeline in HA pointing at the LVA satellite. Test with that pipeline. Verify continue-conversation, audio quality, wake-word reliability.
3. When confident, swap HA's default pipeline to LVA's. Wyoming becomes inert (still running, just unused).
4. Stop and disable `wyoming-satellite.service` + `wyoming-openwakeword.service`.
5. Remove their venvs, drop their lines from `setup-pi.sh`.
6. Hearth's auto-detection picks up the new entity ID (it scans for `assist_satellite.*` and uses the first available).

**Tradeoff:** ~30 minutes of extra disk + memory while both run. Safer rollback (just switch HA's default pipeline back to Wyoming).

### Strategy B — Hard cutover

Stop Wyoming, install LVA, hope it works. Faster but higher risk and worse failure mode (no voice control until you fix it). Not recommended given LVA's "experimental" status.

**Decision: Strategy A.**

## Audio integration

Same `PULSE_SERVER` pattern proven during the PipeWire migration:

```
Environment=PULSE_SERVER=unix:/run/user/999/pulse/native
Environment=XDG_RUNTIME_DIR=/run/user/999
```

LVA's [install_application.md](https://github.com/OHF-Voice/linux-voice-assistant/blob/main/docs/install_application.md) documents `LVA_PULSE_SERVER` and `LVA_XDG_RUNTIME_DIR` env vars with defaults that already point at `/run/user/${LVA_USER_ID}/pulse/native` — so if `LVA_USER_ID=999` the defaults work and we don't need explicit overrides. Need to verify by inspecting the docker-entrypoint.sh.

## Wake-word system

LVA bundles `openWakeWord` and `microWakeWord` engines and ships `okay_nabu`, `alexa`, `hey_jarvis`, `hey_mycroft`, `hey_luna`, `hey_home_assistant`. Default model is `okay_nabu` — matches what Wyoming was using (`ok_nabu`). No retraining or custom-model wrangling needed.

## Mute mechanism

LVA accepts `--mute-sound`/`--unmute-sound` flags suggesting it has internal mute state. The exact mechanism isn't fully documented — could be local pause-wakeword, could be a pipe-through-HA action. Need to verify before assuming Gitea #130 is auto-resolved. If LVA exposes a clean mute API via the ESPHome protocol, Hearth's existing toolbar mute icon can call through it (replacing the broken ALSA-mute path).

## Risks

### High

- **LVA "experimental" label.** It's actively maintained but not declared stable. Expect rough edges. Mitigated by Strategy A side-by-side approach — if it doesn't work, Wyoming stays as fallback.
- **Entity-name change breaks Hearth's hardcoded selection.** Need to verify `voice_assistant_service.dart` actually scans for `assist_satellite.*` rather than the literal string `assist_satellite.hearth`. If hardcoded, add a small change to make it pattern-based or configurable.

### Medium

- **HA-side discovery.** ESPHome integration's mDNS discovery should pick up LVA automatically, but if the Pi's network setup blocks mDNS or HA's ESPHome integration isn't enabled, we'd need to add the device manually by IP.
- **Pipeline configuration.** HA's voice-assist pipeline has many knobs (STT, conversation agent, TTS, language). Switching to LVA shouldn't require rebuilding the pipeline, but if LVA expects a specific pipeline shape (e.g., specific TTS engines), we'd need to adjust.
- **Voice ducking actually working.** Documentation doesn't explicitly confirm LVA tags streams with `media.role=communication`. Need to verify with `pw-cli list-objects` while LVA is responding, and only enable the ducking rule if the role is set.

### Low

- **Mic mute story** (Gitea #130). LVA's mute behavior is undocumented in detail. Worst case: same bug exists in a different form; we file an upstream issue. Best case: it's fixed by LVA and we delete the systemctl-based methods.
- **Resource use.** LVA bundles two wake-word engines plus a pulse client. Memory/CPU should be similar to Wyoming + openWakeWord, possibly less because it's a single process.

## Open questions

1. **Will the existing HA pipeline configuration work as-is with LVA, or does it need adjustment?** (Verify by adding LVA in HA UI and running a test command before changing default pipeline.)

2. **What entity name does LVA register?** Hearth's `voice_assistant_service.dart` currently picks `assist_satellite.hearth` somehow — need to confirm the selection logic and adjust if entity name changes.

3. **Does LVA tag streams with `media.role=communication`?** If not, voice ducking needs a different match condition (`application.process.binary` or similar).

4. **Mute mechanism — pause wakeword or harder cutoff?** Determines whether Gitea #130 is auto-resolved or still needs work.

5. **PiCompose image vs source build vs Docker?** The PiCompose route ships a whole different OS, which is wrong for Hearth (we have our own Pi OS + setup script flow). Source build via `script/setup --dev` or Docker. **Recommend source build** — matches our setup-pi.sh model and gives the same observability we have for Wyoming today.

## Effort estimate

- **Phase 1** — Install LVA from source via setup-pi.sh, side-by-side with Wyoming: 1-2 hours
- **Phase 2** — HA-side configuration, pipeline assignment, basic voice command verification: 1 hour
- **Phase 3** — Verify Hearth's voice_assistant_service picks up the new entity, fix entity selection if needed, validate continue-conversation: 1-2 hours
- **Phase 4** — Decommission Wyoming, clean up sudoers.d/setup-pi.sh: 30 min
- **Phase 5** — Voice ducking via WirePlumber rule: 30 min - 1 hour

**Total: ~half a day of focused work** assuming LVA installs cleanly and HA discovery just works. Add a buffer for the experimental label.

## Future work unlocked (out of scope here)

- Per-stream volume in Hearth UI (now that PipeWire owns audio)
- Bluetooth speaker support
- Multi-room audio
- Frigate camera audio (separate from this migration but enabled by PipeWire generally)
- Announcements / TTS pushes from automations into Hearth's audio output

## What this is NOT

- A change to Hearth's voice UX (the pill, the mic icon, the listening animations stay the same)
- A change to which wake word users say (`okay_nabu` either way)
- A change to HA's STT/LLM/TTS pipeline (the satellite is the messenger, not the speaker)
