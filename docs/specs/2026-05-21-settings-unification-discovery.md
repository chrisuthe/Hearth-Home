# Settings Unification — Discovery & Open Questions

**Status:** Discovery — not yet brainstormed or approved
**Date:** 2026-05-21
**Goal of this doc:** Capture what we found surveying the on-device Settings and the web portal, surface the architectural problem (flat sections won't scale as Hearth grows), and pose the design questions a future brainstorm needs to answer.

This is a *thinking document*, not a spec. The next session should run it through `superpowers:brainstorming` before any code is written.

---

## What prompted this

User observation, paraphrased: *"reorganize the web interface into something more organized, maybe a tab per integration/area, and make sure we're not missing anything from the on-device config to the web config."*

Pulling on that thread surfaced something bigger than a tab restructure. The on-device Settings has grown to 8 sections × N controls each (1420 LOC); the web portal is a flat 900-line HTML page. They're already drifting apart. And Hearth is on a growth trajectory — more integrations, N webviews, multi-dashboard support, future modules — that a flat structure can't absorb.

User direction:
- **Keep on-device and web mirrored** — same information architecture both places, so users don't have to learn two layouts
- **Think about scale** before picking a tab structure — the answer needs to handle N integrations / N webviews / N modules cleanly

---

## Current state: parity audit

### On-device Settings (`lib/screens/settings/settings_screen.dart`, 1420 LOC)

Eight numbered sections in `ListView` order:

1. **Screens** — module placement chips (swipe/menu1/menu2) per module, reorder list, separate "Community Contributed" subsection
2. **Services** — sub-headers per integration:
   - Home Assistant: URL + token
   - Immich: URL + API key + **PhotoSourcesSection** (Immich source picker — albums, recent, etc.)
   - Music Assistant: URL + token + default zone
   - Frigate: URL + username + password
   - Mealie: URL + token (conditional on module enabled)
   - Weather: entity ID
   - Voice Assistant: satellite entity dropdown (with HA-discovered options)
3. **Display & Behavior** — 24-hour clock, timezone, idle timeout, **UiScaleSection**, **DisplaySettingsSection** (display profile, mirror connector, etc.), OSK mode, Night mode (source + conditional sub-settings), top/bottom edge swipe actions
4. **Devices** — pinned entity IDs (entity picker dialog)
5. **Audio** — Sendspin enable + player name + server URL + buffer size + status
6. **Voice Assistant** (separate section) — mic mute toggle, show-voice-feedback toggle
7. **Network & Access** — WifiSettingsSection (scan/connect UI), web portal PIN (read-only)
8. **System** — UpdateSettingsSection (autoUpdate, Gitea token, check/install)
9. **Webviews** — WebviewSettingsSection (HA dashboards toggle list + custom URLs editor)
10. **Per-module settings** — modules that opt in via `buildSettingsSection()` get appended (currently AlarmClock)

### Web portal config (`lib/services/local_api_server.dart` `_configPageHtml`, ~900 LOC)

Currently a single flat `<form>` page with `<h2>` separators. Fields present:

- Connections: `immichUrl`, `immichApiKey`, `haUrl`, `haToken`, `musicAssistantUrl`, `musicAssistantToken`, `defaultMusicZone`, `frigateUrl`, `frigateUsername`, `frigatePassword`, `mealieUrl`, `mealieToken`, `weatherEntityId`
- Behavior: `idleTimeoutSeconds`, `use24HourClock`, `timezone`, `displayProfile`
- Night mode: `nightModeSource`, `nightModeHaEntity`, `nightModeClockStart`, `nightModeClockEnd`
- Devices: `pinnedEntityIds` (textarea, one per line)
- Audio: `sendspinEnabled`, `sendspinPlayerName`, `sendspinServerUrl`, `sendspinBufferSeconds`
- Alarms: list with add
- System: `autoUpdate`, `giteaApiToken`, check / install buttons
- Capture: `captureToolsEnabled`

### Gaps — on-device has it, web doesn't

| Missing on web | Lives in on-device section |
|---|---|
| Module placement chips + reorder | Screens |
| Community-contributed module subsection | Screens |
| **PhotoSourcesSection** (Immich source picker) | Services |
| Voice Assistant satellite entity picker | Services |
| **UiScaleSection** | Display & Behavior |
| **DisplaySettingsSection** (display profile, mirror, etc.) | Display & Behavior |
| On-screen keyboard mode | Display & Behavior |
| Top / bottom edge swipe actions | Display & Behavior |
| Mic mute toggle | Voice Assistant |
| Show voice feedback toggle | Voice Assistant |
| **WifiSettingsSection** UI (API endpoints exist, no UI) | Network & Access |
| **WebviewSettingsSection** (just shipped in v1.10.0) | Webviews |
| Per-module settings (AlarmClock, future modules) | Bottom of list |

### Gaps — web has it, on-device doesn't

- `giteaApiToken` — for private OTA builds. Deliberately web-only (typing it on the kiosk OSK is painful).

### Mirroring principle

The user wants **the same IA both places**. So new entries added to one need to appear in the other. Today that's a manual cross-reference; the next refactor should make it structural.

---

## The architectural problem: things that have *N* entries

Hearth is growing in dimensions where N is unbounded:

- **N integrations** — 6 today, more likely (Home Assistant first-class, but room for others)
- **N webviews** — user-configurable, can be many
- **N modules** — 5 first-party, designed to be extended; some are community
- **N pinned entities** — currently a flat list
- **N HA dashboards** — auto-discovered from HA, can be dozens
- **N custom URLs** — companion to webviews
- **N alarms** — flat list with add/remove
- **N WiFi networks** — scan results, saved networks
- **Eventually N OAuth-style connected accounts** — when proper HA auth lands

The flat `<h2>`-section model doesn't handle N gracefully. Each addition either expands one section past usefulness or spawns a new top-level section. Today's 8-section count already drifts toward "lots."

### Two competing UX patterns

**Pattern A: List + detail (master/detail)** — for any collection of N things, show a list with Add. Click an entry to edit it in detail. Examples in Hearth today: pinned entities (picker dialog), alarms (list + add). Examples we should add: integrations (one row per service), webviews (already roughly there), HA dashboards (toggle list).

**Pattern B: Plugin/module registration** — each "thing" registers itself with the settings system. The settings UI iterates registered things and renders each one's settings panel. Hearth's `HearthModule.buildSettingsSection()` already does this for modules; could be extended to "integrations" as a class of object that registers a settings panel.

Both can coexist. The interesting question is *which abstraction owns which boundary*.

### Settings-as-data vs settings-as-UI

A deeper choice: do we treat the settings tree as **structured data** that both surfaces render? Or two parallel UIs that happen to share field IDs?

- **Structured data**: one source-of-truth JSON-Schema-ish definition of "what settings exist, what type, what validation, what category." Both Flutter and HTML are renderers. Adding a setting is a one-line addition to the schema; both surfaces pick it up.
- **Parallel UIs**: each surface owns its own UI code; we wire shared field IDs through. Today's pattern. Easier to make per-surface customizations; harder to keep in sync.

This is the highest-leverage decision in the redesign. **Structured data** is the only answer that scales to N integrations without per-integration UI code in two languages.

---

## Open design questions for next session's brainstorm

1. **Information architecture** — what are the actual top-level categories? Direct mirror of today's 8 on-device sections, or a re-think? Likely candidates:
   - Screens / Modules
   - Connections (all integrations)
   - Display
   - Devices
   - Audio
   - Voice
   - Network
   - System
   - Webviews (or: merge into Connections under "external pages"?)

2. **Settings as schema vs settings as UI code** — go full schema-driven (one JSON descriptor → both surfaces render it) or keep parallel UIs and improve discipline?

3. **List + detail pattern** — how do we handle N entries (webviews, integrations, alarms, dashboards)? Modal dialog (today's on-device pattern for pinned entities), drill-into-detail screen (today's pattern for webview add), inline expander?

4. **Mirroring discipline** — when a new setting is added, what's the structural guarantee it appears on both surfaces? A test that fails if a `HubConfig` field doesn't appear in a known location in both UIs?

5. **Per-integration registration** — should each integration (HA, Immich, MA, Frigate, Mealie) become a first-class "Integration" object similar to `HearthModule`, with its own `buildSettingsSection`? That would naturally let new integrations show up on both surfaces.

6. **Web-portal-specific affordances** — Gitea API token, file uploads, anything else that's painful on the kiosk OSK. How are these surfaced (web-only sub-section in System) without breaking the mirroring contract?

7. **Search** — at some point, "where is this setting" becomes a real question. A search box across all settings is a feature both surfaces could share if the schema is structured.

8. **Web nav pattern** — given the answers above: tabs, sidebar, card grid, or breadcrumb-drill? Most likely answer depends on the mirroring approach.

---

## What's already in place that the redesign should reuse

- **HubConfig** is already a strongly-typed Riverpod-backed config with `copyWith` and JSON round-trip — solid foundation for a schema-driven approach.
- **HearthModule** interface is the model for plugin-style registration — already proven for screens/modules; the integrations could follow the same pattern.
- **WebviewConfig + WebviewSource** is a recently-added (v1.10.0) example of an N-entry config object with both a typed model and a settings UI.
- **`_SectionHeader` widget** on-device + `<h2>` on web — both surfaces have a section-header concept; would map cleanly to a schema "category" field.
- **The web portal already has a PIN auth flow and session cookie management** — the redesign reuses this; no security changes implied.

---

## Suggested next-session flow

1. Run `superpowers:brainstorming` with this discovery doc as input. Particularly answer questions 1–5 above before sketching any UI.
2. Write the design spec — should land in `docs/specs/2026-XX-XX-settings-unification-design.md`.
3. Write the plan with explicit phases: schema definition first, then refactor of one section as a proof-of-concept (probably **Connections**), then migrate the rest.
4. Implementation likely spans 2–3 sessions because of the structural-rewrite nature.

The work needs to land BEFORE we add more integrations, otherwise we'll be paying parallel-UI tax on every addition. There's no urgency to a specific delivery date, but every new feature added in the meantime makes the eventual migration harder.

---

## Pieces NOT to lose between sessions

- This file
- `docs/specs/2026-05-21-webview-integration-design.md` (the shipped webview feature spec — provides one concrete N-entry example)
- The fact that the existing web portal is `_configPageHtml` (line ~1009 of `lib/services/local_api_server.dart`) — a single raw HTML string. A schema-driven approach would replace this with a generated render.
- The web portal already serves `/`, `/logs`, `/capture` as distinct pages — this multi-page pattern is already in place and worth preserving.

---

*End of discovery. Next session, brainstorm.*
