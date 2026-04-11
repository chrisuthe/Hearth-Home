# Alarm Clock Module Design

## Overview

A sunrise alarm clock module for Hearth that replicates the Google Nest Hub sunrise alarm experience. The AMOLED display gradually brightens through dawn colors before the alarm fires, HA-connected lights ramp brightness and color temperature in sync, and configurable alarm tones play via ALSA or Music Assistant.

This also includes a module system enhancement: modules can now appear in the swipe PageView, quick-action menus, or both — configured per-module in Settings.

## Module System Enhancement

### Module Placement Model

Replace the current `enabledModules: List<String>` in HubConfig with `modulePlacements: Map<String, List<String>>`.

Each module ID maps to a list of placement strings: `'swipe'`, `'menu1'`, `'menu2'`. A module can appear in multiple placements. An empty list (or absence from the map) means disabled.

Example:
```json
{
  "modulePlacements": {
    "media": ["swipe"],
    "controls": ["swipe"],
    "cameras": ["menu2", "swipe"],
    "alarm_clock": ["menu1"],
    "mealie": ["menu2"]
  }
}
```

### Settings UI

Replace the current per-module `SwitchListTile` with a row of three `FilterChip` toggles per module: `Menu 1` | `Menu 2` | `Swipe`. Multiple can be selected. No chips selected = disabled.

### HubShell Integration

- Modules with `'swipe'` placement go in the PageView (ordered by `moduleOrder` as before).
- Modules with `'menu1'` or `'menu2'` placement get a `_QuickAction` entry in the corresponding menu tray.
- Tapping a menu-placed module opens its screen as a Navigator push (same pattern as the current Timer screen).
- Module order in menus follows the same `moduleOrder` / `defaultOrder` sorting.

### Migration

On first load with no `modulePlacements` key, derive placements from the existing `enabledModules` list — all enabled modules set to `['swipe']`. Delete `enabledModules` from the persisted config after migration.

## Alarm Data Model

### Alarm Object

Stored in `alarms.json` in the app support directory (separate from `hub_config.json`):

```json
{
  "id": "a1b2c3",
  "time": "06:30",
  "label": "Work",
  "enabled": true,
  "days": [1, 2, 3, 4, 5],
  "oneTime": false,
  "sunriseDuration": 15,
  "sunriseLights": ["light.bedroom_lamp"],
  "soundType": "builtin",
  "soundId": "gentle_morning",
  "snoozeDuration": 10,
  "volume": 0.7
}
```

Field details:
- `id`: Short unique identifier (generated via `shortid` or similar).
- `time`: 24-hour `HH:mm` format (internal storage, displayed per user's 12h/24h preference).
- `label`: Optional user-friendly name. Empty string if not set.
- `enabled`: Whether the alarm is active.
- `days`: ISO weekday numbers (1=Monday, 7=Sunday). Empty list = one-time alarm.
- `oneTime`: When true, fires at the next occurrence of `time` then auto-disables.
- `sunriseDuration`: Minutes before alarm to begin sunrise effect. 0 = no sunrise.
- `sunriseLights`: HA entity IDs to ramp during sunrise. Empty list = display only.
- `soundType`: `"builtin"` (bundled tone), `"music_assistant"` (MA playback), or `"none"`.
- `soundId`: Builtin tone name or MA media URI depending on `soundType`.
- `snoozeDuration`: Snooze length in minutes.
- `volume`: Alarm sound volume, 0.0 to 1.0.

### One-Time Alarms

When `days` is empty, the alarm is one-time. `oneTime` is set to `true`. After firing and being dismissed, `enabled` is set to `false` automatically. If the specified time has already passed today, it fires tomorrow.

## Service Architecture

### AlarmService (ChangeNotifier)

Manages alarm state, persistence, and firing detection.

- Loads `alarms.json` on initialization; saves on every mutation.
- Computes `nextAlarmTime` for each enabled alarm based on current time and day-of-week schedule.
- Runs a 30-second periodic ticker (minute-resolution is sufficient for alarms).
- Each tick: checks if any alarm's `nextAlarmTime` is now or in the past (within a 60-second window to avoid missing due to tick timing).
- On fire: sets `firedAlarm` property, notifies listeners.
- Tracks `snoozedUntil: DateTime?` for snooze state.
- Exposes `nextAlarm: (Alarm, DateTime)?` for display on the home screen.
- Registered as a Riverpod `ChangeNotifierProvider`.

### SunriseController

Manages the sunrise display effect and HA light ramping. Separate from AlarmService to keep concerns clean.

- Created by AlarmService when a sunrise-enabled alarm is approaching.
- Drives a progress value from 0.0 to 1.0 over the configured duration.
- Interpolates display colors through keyframes.
- Calls HA light services every 30 seconds with interpolated brightness and color temperature.
- Handles snooze (dims to 30%, re-ramps) and dismiss (fade out).

## Sunrise Display Effect

### Color Keyframes

The AMOLED screen simulates dawn. Pure black pixels emit no light, so the effect starts from true darkness:

| Progress | Color | Description |
|----------|-------|-------------|
| 0% | `#000000` | Black (no light) |
| 15% | `#0A1028` | Deep navy |
| 30% | `#2A1040` | Dark purple |
| 50% | `#4A2010` | Warm amber |
| 70% | `#C05820` | Orange |
| 85% | `#E8A030` | Golden yellow |
| 100% | `#FFD890` | Warm white |

Interpolation between keyframes uses `Color.lerp` for smooth transitions. The animation ticks at 1-second intervals (sunrise is slow enough that per-second updates are imperceptibly smooth).

### Pre-Alarm Sound

At 80% sunrise progress (~last 2-3 minutes of the sunrise window), if the alarm has sound enabled, a soft ambient loop (bundled `pre_alarm_birds.ogg` or similar) fades in at low volume via ALSA. This is separate from the main alarm tone.

### Display Layer Placement

The sunrise gradient renders in the HubShell stack:
1. Photo carousel (bottom, always)
2. **Sunrise gradient overlay** (above photos, semi-transparent at low progress)
3. Active screen layer (PageView)
4. Menu overlays
5. **Alarm alert overlay** (topmost when fired)

During sunrise, the ambient photos remain visible through the gradient at early stages, creating a dawn-over-landscape effect.

## HA Smart Light Integration

### Brightness Ramp

During the sunrise window, call `light.turn_on` on each entity in `sunriseLights` every 30 seconds:
- Brightness: 0% to 100%, following a quadratic ease-in curve (slow start, accelerating).
- The curve matches natural sunrise perception better than linear.

### Color Temperature Shift

If the light entity supports `color_temp` (check `supported_color_modes` in HA entity attributes):
- Ramp from 2200K (very warm) to 4000K (daylight) over the sunrise duration.
- Lights that don't support color_temp get brightness-only ramping.

### Snooze Behavior

On snooze: call `light.turn_on` with brightness 30% and color_temp 2200K (dim warm). Then re-ramp over the snooze duration.

### Dismiss Behavior

On dismiss: leave lights at their current state. The user is awake; turning lights off would be counterproductive.

## Alarm Alert Overlay

### Layout

Full-screen overlay above the sunrise gradient:
- Current time in large text (center, top third).
- Alarm label if set (below time, smaller).
- "Tap anywhere to snooze" text (faint, near bottom).
- "Dismiss" button (bottom center, generous 60dp+ height, visually distinct).

### Interaction

- **Tap anywhere** (except dismiss button) = snooze. Easiest possible action when groggy.
- **Tap dismiss button** = stop alarm. Slightly more deliberate to prevent accidental dismissal.
- Snooze: display dims, re-sunrises over snooze duration. Sound stops, restarts when snooze ends.
- Dismiss: sunrise fades out (3 seconds), sound stops, alert closes.

### Idle Interaction

- Fired alarms suppress idle return-to-home (same guard as timer alerts).
- Sunrise in progress does NOT suppress idle — the ambient display should stay visible during the gradual brightening.

## Alarm Screen UX

### Alarm List (Default View)

Vertical scrollable list of alarm cards:
- Time in large text (respects 12h/24h config).
- Label (if set) and day summary: "Mon-Fri", "Weekends", "Tomorrow", "Every day".
- Enable/disable toggle on the right side of each card.
- Tap card to open editor.
- Header showing next alarm: "Next alarm in 6h 23m" or "No alarms set".
- FAB or bottom button to add new alarm.

### Add/Edit Alarm (Navigator Push)

Full-screen editor:
- **Time picker**: Hour and minute scroll wheels (reuse timer `_ScrollWheel` pattern).
- **Day toggles**: Row of 7 circular buttons (M T W T F S S). None selected = one-time.
- **Label**: Optional text field.
- **Sunrise section**: Toggle on/off + duration chips (5/10/15/20/25/30 min).
- **Sunrise lights**: Multi-select list of HA light entities.
- **Sound picker**: Grid/list of builtin tones (tap to preview) + "Music Assistant" option.
- **Snooze duration**: Chip row (5/10/15/20 min).
- **Volume slider**.
- **Delete button** (edit mode only, at bottom, red).
- **Save button** at top or bottom.

## Bundled Alarm Tones

Five audio files bundled in `assets/alarm_tones/`, sourced from CC0/royalty-free libraries:

| ID | Name | Character |
|----|------|-----------|
| `gentle_morning` | Gentle Morning | Soft melodic chime, rises gradually |
| `birds` | Birdsong | Nature sounds with gentle melody |
| `classic` | Classic | Traditional alarm beep pattern |
| `bright` | Bright Day | Upbeat, energetic tone |
| `urgent` | Wake Up | Louder, assertive (heavy sleepers) |

Plus one pre-alarm ambient loop:
| `pre_alarm_ambient` | Pre-alarm | Soft nature sounds for sunrise fade-in |

Each tone is a 5-10 second loop. Playback via ALSA on Pi (same path as Sendspin audio sink), platform audio on Windows. Loops until dismissed or snoozed.

Music Assistant option: calls `playMedia` on the configured player. Falls back to `gentle_morning` builtin if MA is disconnected or playback fails within 5 seconds.

## Web Portal

### API Endpoints

- `GET /api/alarms` — returns the full alarm list as JSON array.
- `POST /api/alarms` — create or update an alarm (upsert by `id`). Returns the saved alarm.
- `DELETE /api/alarms/:id` — delete an alarm by ID.

All endpoints require API key authentication (same as existing config endpoints).

### Web UI

Add an "Alarms" section to the web config portal with:
- List of existing alarms with enable/disable toggles.
- Add/edit form with time, days, label, sunrise toggle, sound selection.
- Delete button per alarm.

## File Structure

```
lib/modules/alarm_clock/
  alarm_clock_module.dart     # HearthModule implementation
  alarm_clock_screen.dart     # List + FAB
  alarm_editor_screen.dart    # Add/edit form
  alarm_alert_overlay.dart    # Fired alarm overlay (in HubShell)
  alarm_service.dart          # State, persistence, firing
  sunrise_controller.dart     # Display effect + HA light ramping
  alarm_models.dart           # Alarm data class + JSON serialization

assets/alarm_tones/
  gentle_morning.ogg
  birds.ogg
  classic.ogg
  bright.ogg
  urgent.ogg
  pre_alarm_ambient.ogg
```

## Module Registration

```dart
class AlarmClockModule implements HearthModule {
  String get id => 'alarm_clock';
  String get name => 'Alarms';
  IconData get icon => Icons.alarm;
  int get defaultOrder => 5;  // Right of Home, before Controls
  
  bool isConfigured(HubConfig config) => true;  // No external config needed
  Widget buildScreen({required bool isActive}) => const AlarmClockScreen();
  Widget? buildSettingsSection() => null;
}
```

Default placement: `['menu1']` (accessible from quick-action menu, not cluttering the swipe order).
