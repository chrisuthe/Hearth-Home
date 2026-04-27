# Linux Voice Assistant Migration — Implementation Plan

**Spec:** [docs/specs/2026-04-26-linux-voice-assistant-migration-design.md](../specs/2026-04-26-linux-voice-assistant-migration-design.md)

**Goal:** Replace `wyoming-satellite` + `wyoming-openwakeword` with [Linux Voice Assistant](https://github.com/OHF-Voice/linux-voice-assistant) running side-by-side initially, then cut over and decommission Wyoming. Validate continue-conversation works. Wire up voice ducking as a bonus.

**Architecture summary:** LVA installs from source under `/opt/lva/`, runs as `hearth` user via `linux-voice-assistant.service`, talks to HA via ESPHome protocol on port 6053 (auto-discovered by mDNS). Audio goes through the same PipeWire bridge we set up in the PipeWire migration (`PULSE_SERVER=unix:/run/user/999/pulse/native`). Hearth's `voice_assistant_service.dart` watches `assist_satellite.*` entities — protocol-agnostic, no code change required.

**Tech Stack:** Python 3.11+, openWakeWord (bundled), libpipewire (via pulse compat), HA ESPHome integration, existing PipeWire stack from prior migration.

---

## Phase 1 — Install LVA side-by-side with Wyoming

Goal: LVA running on the Pi as a separate systemd service. Wyoming continues running. HA can see both as separate satellites.

### Task 1.1: Verify LVA install requirements on the Pi

**Files:** None (research task).

- [ ] **Step 1: Check Python 3.11+ availability**

```bash
ssh hearthdev@10.0.1.13 'python3 --version'
```

LVA requires Python 3.11 or 3.12. Pi OS Trixie ships Python 3.13 — should be compatible (LVA supports 3.11/3.12, untested on 3.13). If Python 3.13 doesn't work, install python3.12 from apt.

- [ ] **Step 2: Verify build deps**

```bash
ssh hearthdev@10.0.1.13 'dpkg -l | grep -E "build-essential|libffi-dev|libssl-dev|cmake"'
```

LVA's `script/setup` likely needs build-essential + libffi-dev for Python wheels. Install missing pieces.

- [ ] **Step 3: Verify the user audio group + PipeWire socket are still in place**

```bash
ssh hearthdev@10.0.1.13 'ls -la /run/user/999/pulse/native; groups hearth'
```

Should show socket exists with `srw-rw-rw-` perms and `hearth` in the `audio` group (post-PipeWire-migration this should already be true).

### Task 1.2: Clone and build LVA from source

**Files:**
- Modify: `scripts/setup-pi.sh` (add LVA install block — see Step 4)

- [ ] **Step 1: Clone the repo into /opt/lva**

```bash
ssh hearthdev@10.0.1.13 'sudo install -d -o hearth -g hearth /opt/lva && sudo -u hearth git clone https://github.com/OHF-Voice/linux-voice-assistant.git /opt/lva/linux-voice-assistant'
```

- [ ] **Step 2: Run setup script**

```bash
ssh hearthdev@10.0.1.13 'cd /opt/lva/linux-voice-assistant && sudo -u hearth ./script/setup --dev'
```

This creates a venv and installs Python dependencies. On Pi 5 should take 2-5 minutes.

- [ ] **Step 3: List audio devices to verify PipeWire is reachable**

```bash
ssh hearthdev@10.0.1.13 'cd /opt/lva/linux-voice-assistant && sudo -u hearth bash -c "LVA_PULSE_SERVER=unix:/run/user/999/pulse/native LVA_XDG_RUNTIME_DIR=/run/user/999 LIST_DEVICES=1 ./docker-entrypoint.sh"'
```

Expected: prints input + output devices including HDMI sink and USB mic via PipeWire.

- [ ] **Step 4: Add the install block to setup-pi.sh**

After the `# Wyoming satellite service` block (which we'll remove in Phase 4), add:

```bash
# --- Linux Voice Assistant (replaces wyoming-satellite) ---
sudo install -d -o hearth -g hearth /opt/lva
if [ ! -d /opt/lva/linux-voice-assistant ]; then
    sudo -u hearth git clone --depth 1 \
        https://github.com/OHF-Voice/linux-voice-assistant.git \
        /opt/lva/linux-voice-assistant
fi
cd /opt/lva/linux-voice-assistant
sudo -u hearth git pull --ff-only || true
sudo -u hearth ./script/setup --dev
cd -
```

Don't commit yet — we'll commit the full Phase 1 setup-pi.sh changes once everything is validated.

### Task 1.3: Write the linux-voice-assistant systemd unit

**Files:**
- Create: `/etc/systemd/system/linux-voice-assistant.service` (on Pi)
- Modify: `scripts/setup-pi.sh` (write the unit on fresh installs)

- [ ] **Step 1: Draft the unit**

```
[Unit]
Description=Linux Voice Assistant
After=network.target user@999.service

[Service]
Type=simple
User=hearth
Group=hearth
WorkingDirectory=/opt/lva/linux-voice-assistant
Environment=LVA_USER_ID=999
Environment=LVA_USER_GROUP=999
Environment=LVA_PULSE_SERVER=unix:/run/user/999/pulse/native
Environment=LVA_XDG_RUNTIME_DIR=/run/user/999
Environment=PORT=6053
Environment=WAKE_MODEL=okay_nabu
Environment=CLIENT_NAME=Hearth
ExecStart=/opt/lva/linux-voice-assistant/docker-entrypoint.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

The `After=user@999.service` ordering ensures the hearth user manager (and PipeWire) is up before LVA starts.

- [ ] **Step 2: Apply on the live Pi**

```bash
ssh hearthdev@10.0.1.13 'sudo tee /etc/systemd/system/linux-voice-assistant.service' < /dev/stdin
sudo systemctl daemon-reload
sudo systemctl enable --now linux-voice-assistant.service
```

(User authorization required for live systemd write — pattern from prior migrations.)

- [ ] **Step 3: Verify it started**

```bash
ssh hearthdev@10.0.1.13 'systemctl is-active linux-voice-assistant.service && journalctl -u linux-voice-assistant.service -n 30 --no-pager'
```

Look for: server listening on port 6053, wake-word model loaded, audio device acquired. No tracebacks.

- [ ] **Step 4: Verify port is open**

```bash
ssh hearthdev@10.0.1.13 'ss -tlnp | grep 6053'
```

Expected: tcp listener on 0.0.0.0:6053.

- [ ] **Step 5: Add to setup-pi.sh**

Same content as Step 1 but written via `sudo tee` heredoc (don't commit yet).

### Task 1.4: Verify LVA appears in PipeWire as a client

**Files:** None — verification only.

- [ ] **Step 1: Check PipeWire client registration**

```bash
ssh hearthdev@10.0.1.13 'sudo -u hearth XDG_RUNTIME_DIR=/run/user/999 pw-cli list-objects Client | grep -B1 -A4 -i "voice\|lva\|linux-voice"'
```

Expected: at least one client with `application.name` containing voice/lva/linux-voice. If not registered, the `LVA_PULSE_SERVER` env path is wrong — verify it matches `wpctl status`'s socket location.

---

## Phase 2 — HA-side configuration

Goal: HA discovers LVA via mDNS, adds it as an ESPHome device, exposes it as a new `assist_satellite.*` entity. Voice command via the LVA satellite works end-to-end.

### Task 2.1: Add LVA to HA via ESPHome integration

**Files:** None (HA UI work — manual).

- [ ] **Step 1: Confirm mDNS discovery**

In HA, navigate to **Settings → Devices & Services**. There should be a discovered ESPHome device named "Hearth" (matching `CLIENT_NAME=Hearth` in the unit). If discovery doesn't fire, add manually via **Add Integration → ESPHome → IP=10.0.1.13, Port=6053**.

- [ ] **Step 2: Set the encryption / API password if prompted**

LVA's docs likely cover encryption setup. If LVA generated an API password on first run, retrieve it from `/opt/lva/linux-voice-assistant/<config-location>` and paste into HA. (Investigate during step 1; document the exact location once known.)

- [ ] **Step 3: Verify the new assist_satellite entity exists**

In HA: **Developer Tools → States** → filter `assist_satellite.`. Expect to see the original `assist_satellite.hearth` (Wyoming) AND a new entity from LVA (likely `assist_satellite.hearth_2` or `assist_satellite.hearth_lva` depending on naming).

### Task 2.2: Create a test pipeline pointed at LVA

**Files:** None (HA UI work).

- [ ] **Step 1: Settings → Voice assistants → Add assistant**

Name: "Hearth (LVA test)". Conversation agent: same as the existing pipeline (Home Assistant or whatever you use). STT/TTS: same. **Default for LVA satellite: yes.**

- [ ] **Step 2: Test a voice command via the new pipeline**

Use **Developer Tools → Actions → assist_satellite.start_conversation** targeting the LVA entity, with a test message like "What time is it?". Expect:
- LVA logs show "wake word detected" or equivalent
- HA pipeline runs through STT → conversation → TTS
- Audio response plays through Hearth's HDMI output

If audio plays cleanly: continue. If not, debug the LVA-side audio (likely `LVA_PULSE_SERVER` env or pulse socket access).

- [ ] **Step 3: Try wake-word activation**

Say "okay nabu, what time is it" near the kiosk's mic. Expect the same flow without the manual trigger.

### Task 2.3: Validate continue_conversation

**Files:** None — feature validation.

- [ ] **Step 1: Configure HA pipeline for follow-up**

In the LVA-test pipeline, ensure the conversation agent supports continue conversation. (For HA's built-in agent, verify; for LLM-backed agents like OpenAI Conversation, set "Allow assistant to control your home" + "Continue conversation" options if available.)

- [ ] **Step 2: Test follow-up**

Say a command that the conversation agent will respond with `continue_conversation=true` (e.g., a multi-turn intent or a clarifying question — depends on agent). After TTS finishes, expect the satellite to listen for a follow-up WITHOUT requiring "okay nabu" again. Validate visually via the kiosk's voice pill UI staying in listening state.

If continue-conversation doesn't fire, this is the migration's headline feature failing. Investigate before proceeding.

---

## Phase 3 — Hearth-side adjustments

Goal: Hearth's voice UI continues working with the new entity. Adjust selection logic if needed.

### Task 3.1: Verify entity auto-detection

**Files:**
- Investigate: `lib/services/voice_assistant_service.dart`

- [ ] **Step 1: Read the entity-selection logic**

Find where `voice_assistant_service.dart` decides which `assist_satellite.*` entity to follow. Earlier logs showed `INFO:root: Selected satellite entity: assist_satellite.hearth` — find the code that produces this log line.

- [ ] **Step 2: Decide selection strategy**

Three possible cases:
- (a) Code scans for `assist_satellite.*` and picks the first available — works transparently after Wyoming is decommissioned.
- (b) Code hardcodes `assist_satellite.hearth` as a string — breaks if LVA registers as a different name.
- (c) Code reads from config — needs config update post-migration.

If (b) or (c), change to (a) or expose entity name as a config field.

- [ ] **Step 3: Test on the live kiosk during side-by-side phase**

While Wyoming and LVA both expose entities, verify Hearth's selected entity (visible in voice pill behavior + journal log). If it's still pointing at Wyoming's `assist_satellite.hearth`, that's expected for now — the cutover happens in Phase 4 when Wyoming is removed.

### Task 3.2: Strip Wyoming-specific code paths in Hearth

**Files:**
- Modify: `lib/services/voice_assistant_service.dart`

- [ ] **Step 1: Remove the systemctl-based mute methods**

Per Gitea #130 — the `mute()`, `unmute()`, `isSatelliteRunning` methods at lines 202-242 shell out to `systemctl ... wyoming-satellite.service`. After Wyoming is removed in Phase 4, these are pointing at a service that doesn't exist. Two options:

- **Delete them entirely** — Gitea #130's mic-mute UX still doesn't work but the dead code goes away.
- **Reroute to LVA's mute mechanism** — depends on whether LVA exposes mute via the ESPHome API. Investigate during Phase 2 testing.

Recommend: delete them, then add proper mute via LVA's API as separate follow-up if LVA supports it cleanly.

- [ ] **Step 2: Update Gitea #130**

Note in the issue that the systemctl-mute is gone with the Wyoming migration. If LVA mute works, close the issue. If LVA mute also doesn't work, file a fresh upstream issue against LVA.

---

## Phase 4 — Decommission Wyoming

Goal: stop Wyoming services, remove their code paths and venvs, clean up sudoers.

### Task 4.1: Disable Wyoming services on the Pi

**Files:** None — live Pi state changes.

- [ ] **Step 1: Set HA's default pipeline to the LVA pipeline**

Make sure no devices are still using the Wyoming pipeline. Settings → Voice assistants → make LVA pipeline the default.

- [ ] **Step 2: Stop and disable Wyoming services**

```bash
ssh hearthdev@10.0.1.13 'sudo systemctl disable --now wyoming-satellite.service wyoming-openwakeword.service'
```

(Per prior pattern — needs explicit user authorization.)

- [ ] **Step 3: Remove HA's Wyoming integration entry**

In HA: **Settings → Devices & Services**, find the Wyoming entry for the kiosk, **Delete**. The `assist_satellite.hearth` (Wyoming) entity disappears.

- [ ] **Step 4: Verify Hearth is following the LVA entity**

After the Wyoming entity disappears, Hearth's auto-detection should fall back to the LVA-backed `assist_satellite.*` entity. Verify via journal: `journalctl -u hearth.service | grep "Selected satellite"`.

### Task 4.2: Clean up Wyoming installation files

**Files:**
- Modify: `scripts/setup-pi.sh` (drop the Wyoming install + service-write blocks)
- Modify: `lib/services/voice_assistant_service.dart` (drop the systemctl mute methods if not done in Phase 3)

- [ ] **Step 1: Remove the Wyoming systemd units on the Pi**

```bash
ssh hearthdev@10.0.1.13 'sudo rm /etc/systemd/system/wyoming-satellite.service /etc/systemd/system/wyoming-openwakeword.service && sudo systemctl daemon-reload'
```

- [ ] **Step 2: Remove the Wyoming Python venvs**

```bash
ssh hearthdev@10.0.1.13 'sudo rm -rf /opt/wyoming'
```

- [ ] **Step 3: Remove the sudoers.d/hearth-voice file**

```bash
ssh hearthdev@10.0.1.13 'sudo rm /etc/sudoers.d/hearth-voice'
```

(This was the NOPASSWD rule for `systemctl restart wyoming-satellite.service` — irrelevant now.)

- [ ] **Step 4: Update setup-pi.sh**

Drop:
- The wyoming-satellite + wyoming-openwakeword service blocks
- The wyoming-openwakeword install block (clone + venv + pip install)
- The wyoming-satellite install block (clone + venv + pip install)
- The sudoers.d/hearth-voice write
- Any references to `MIC_CARD` / `SPEAKER_CARD` detection that were Wyoming-specific (they may have been used elsewhere — verify)

- [ ] **Step 5: Reboot and verify**

```bash
ssh hearthdev@10.0.1.13 'sudo reboot'
# wait ~60s
ssh hearthdev@10.0.1.13 'systemctl is-active linux-voice-assistant.service hearth.service; ls /etc/systemd/system/wyoming* 2>&1'
```

Expected: LVA + hearth active, no wyoming unit files.

### Task 4.3: Update docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/specs/2026-04-12-voice-satellite-design.md` (add superseded note — it's now historical)

- [ ] **Step 1: Update CLAUDE.md if it mentions Wyoming**

Check + update.

- [ ] **Step 2: Add superseded note to the voice-satellite design spec**

Same pattern as the stream-to-obs design got post-PipeWire — note at the top pointing at the LVA migration design as the current state.

---

## Phase 5 — Voice ducking (the unlocked feature)

Goal: when LVA is listening or speaking, automatically duck other audio streams (sendspin, media_kit) so the user can hear / be heard clearly.

### Task 5.1: Verify LVA tags streams with media.role

**Files:** None — investigation.

- [ ] **Step 1: Trigger a voice response while inspecting PipeWire**

```bash
# In one terminal: trigger via HA Developer Tools → assist_satellite.start_conversation
# In another: continuously inspect
ssh hearthdev@10.0.1.13 'while :; do sudo -u hearth XDG_RUNTIME_DIR=/run/user/999 pw-cli list-objects Node | grep -B1 -A8 "linux-voice\|lva"; sleep 0.5; done'
```

Expected: an active node with `media.class = Stream/Output/Audio`, ideally with `media.role = "communication"` or similar role tag.

- [ ] **Step 2: Decide ducking strategy based on tags**

If `media.role` is set: write a WirePlumber rule keyed on it. If not: fall back to `application.name` matching against LVA's name. Worst case: file an upstream issue asking LVA to set the role tag.

### Task 5.2: Write the WirePlumber ducking rule

**Files:**
- Create: `/etc/wireplumber/wireplumber.conf.d/60-voice-ducking.conf` (on Pi)
- Modify: `scripts/setup-pi.sh` (write the rule on fresh installs)

- [ ] **Step 1: Draft the rule (assuming media.role = communication)**

```
node.rules = [
  {
    matches = [
      { media.role = "communication" }
    ]
    actions = {
      update-props = {
        node.passive = false
      }
    }
  }
]

stream.rules = [
  {
    matches = [
      { media.class = "Stream/Output/Audio" }
      { media.role = "!communication" }
    ]
    actions = {
      update-props = {
        # Duck non-voice streams by 12dB while a communication stream is active
        # (Implementation depends on WirePlumber version — may need
        # module-role-cork from PipeWire's pulse compat layer instead.)
      }
    }
  }
]
```

The exact rule shape depends on WirePlumber 0.5.x's role-handling support — may require enabling `module-role-cork` via the pulse compat layer, OR using a custom Lua script. Investigate during this task.

- [ ] **Step 2: Apply on the Pi**

Reload WirePlumber:
```bash
ssh hearthdev@10.0.1.13 'sudo -u hearth XDG_RUNTIME_DIR=/run/user/999 systemctl --user restart wireplumber'
```

- [ ] **Step 3: Test ducking**

Start a sendspin track (or media_kit playback). With music playing audibly, trigger a voice command. Expected: music drops in volume by ~12dB while voice plays, returns to normal after voice TTS finishes.

- [ ] **Step 4: Add to setup-pi.sh**

Heredoc-write the rule file as part of fresh-install provisioning.

### Task 5.3: Update memory note

**Files:**
- Modify: `~/.claude/projects/C--Users-chris-hearth/memory/project_voice_ducking.md` (mark as implemented, note actual ducking config)

---

## Validation gate before declaring done

- [ ] LVA service active, no errors in journal across 24+ hours
- [ ] Voice command end-to-end works (wake word → STT → response → TTS audible)
- [ ] Continue conversation works (follow-up doesn't require wake word)
- [ ] Wyoming services + venvs gone, /etc/sudoers.d/hearth-voice gone
- [ ] Hearth's voice pill UI still animates correctly (listening / processing / responding)
- [ ] Voice ducking works when music is playing
- [ ] After full reboot: all of the above still works without manual intervention

## Rollback plan

Per phase:

- **Phase 1 broken:** stop and disable linux-voice-assistant.service. Wyoming continues working unchanged.
- **Phase 2 broken:** delete the LVA pipeline in HA, switch default back to Wyoming pipeline.
- **Phase 3 broken:** revert any voice_assistant_service.dart changes; keep using whatever Hearth's auto-selection picks.
- **Phase 4 broken:** restore Wyoming services from setup-pi.sh history (`git show v1.7.21:scripts/setup-pi.sh`), reinstall the Python venvs, restart.
- **Phase 5 broken:** delete the WirePlumber config file, restart wireplumber. Voice still works without ducking.

The migration is per-phase reversible until Phase 4 (the actual decommission). Phases 1-3 are additive and can sit indefinitely if you want to defer the Wyoming removal.

## Effort estimate (refined from spec)

- Phase 1: 1-2 hours
- Phase 2: 1 hour
- Phase 3: 30 min - 1 hour (depends on entity-selection refactor scope)
- Phase 4: 30 min
- Phase 5: 30 min - 1 hour (depends on `media.role` actually being set)

**Total: ~half a day** with a buffer for the experimental label.

## Open questions to resolve during implementation

1. (Phase 1) Does Python 3.13 work, or do we need to install python3.12 explicitly?
2. (Phase 2) What entity name does LVA register with HA? Affects Phase 3 scope.
3. (Phase 2) Is the Wyoming HA pipeline reusable for LVA, or do we build a fresh one?
4. (Phase 3) Is voice_assistant_service.dart's entity selection pattern-based or hardcoded?
5. (Phase 4) Are MIC_CARD / SPEAKER_CARD detection in setup-pi.sh used outside the Wyoming block? If yes, keep the detection.
6. (Phase 5) Does LVA tag streams with `media.role=communication`?
