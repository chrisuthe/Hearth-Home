# Expose Hearth as a Home Assistant Device via MQTT Discovery

## Context

Hearth connects to Home Assistant as a client (reads entities, calls services) but HA has no awareness of Hearth as a device. Making Hearth appear as a proper HA device enables powerful bidirectional integration — HA automations can control the kiosk, and kiosk state is visible in HA dashboards.

## Approach: MQTT Discovery

HA's MQTT discovery protocol lets devices self-register by publishing config payloads to well-known MQTT topics. Hearth connects to the MQTT broker (same one HA uses) and publishes entity configs + state updates. No custom HA integration needed — works out of the box with any HA installation that has MQTT configured.

## Config

Add to HubConfig:
- `mqttBrokerUrl` (String, default '') — e.g. `mqtt://10.0.2.2:1883`
- `mqttUsername` (String, default '')
- `mqttPassword` (String, default '', redacted in API)

When configured, Hearth connects to MQTT and publishes discovery payloads. When empty, the feature is disabled.

## Device Identity

```json
{
  "identifiers": ["hearth_<clientId>"],
  "name": "Hearth",
  "model": "Hearth Smart Home Kiosk",
  "manufacturer": "Hearth",
  "sw_version": "<installed version>",
  "configuration_url": "http://hearth.local:8090"
}
```

## Entities to Expose

### Switches (controllable from HA)

| Entity | Description | Maps to |
|--------|-------------|---------|
| `switch.hearth_night_mode` | Force night/day mode | DisplayModeService |
| `switch.hearth_screen_active` | Wake/idle the screen | IdleController |
| `switch.hearth_dnd` | Suppress alerts and voice | New DND flag |

### Sensors (read-only in HA)

| Entity | State | Attributes |
|--------|-------|------------|
| `sensor.hearth_current_screen` | "home", "media", "controls", etc. | screen index |
| `sensor.hearth_now_playing` | track title or "idle" | artist, album, player_id, playback_state |
| `sensor.hearth_next_alarm` | ISO datetime or "none" | label, days, sunrise_enabled |
| `sensor.hearth_sendspin` | "streaming", "connected", etc. | sync_precision_ms, codec |
| `sensor.hearth_version` | version string | update_available, latest_version |
| `binary_sensor.hearth_voice_active` | ON during voice pipeline | - |

### Numbers (adjustable from HA)

| Entity | Range | Maps to |
|--------|-------|---------|
| `number.hearth_volume` | 0-100 | ALSA output volume |
| `number.hearth_idle_timeout` | 10-600 seconds | HubConfig.idleTimeoutSeconds |

### Buttons (trigger actions from HA)

| Entity | Action |
|--------|--------|
| `button.hearth_skip_photo` | Advance photo carousel |
| `button.hearth_force_update` | Trigger OTA update |
| `button.hearth_navigate_home` | Navigate to home screen |
| `button.hearth_navigate_media` | Navigate to media screen |
| `button.hearth_navigate_cameras` | Navigate to cameras screen |

## What This Enables

### Example Automations

**Wake kiosk on doorbell:**
```yaml
automation:
  trigger:
    - platform: state
      entity_id: binary_sensor.doorbell
      to: "on"
  action:
    - service: switch.turn_on
      entity_id: switch.hearth_screen_active
    - service: button.press
      entity_id: button.hearth_navigate_cameras
```

**Night mode when bedroom light turns off:**
```yaml
automation:
  trigger:
    - platform: state
      entity_id: light.bedroom
      to: "off"
  action:
    - service: switch.turn_on
      entity_id: switch.hearth_night_mode
```

**Preheat house 30 min before alarm:**
```yaml
automation:
  trigger:
    - platform: template
      value_template: >
        {{ (as_timestamp(states('sensor.hearth_next_alarm')) - as_timestamp(now())) < 1800 }}
  action:
    - service: climate.set_temperature
      entity_id: climate.thermostat
      data:
        temperature: 72
```

**HA Dashboard card:**
```yaml
type: entities
entities:
  - entity: sensor.hearth_current_screen
  - entity: sensor.hearth_now_playing
  - entity: switch.hearth_night_mode
  - entity: number.hearth_volume
  - entity: sensor.hearth_next_alarm
```

## Implementation

### MQTT Client (lib/services/mqtt_service.dart)

- Connect to broker with credentials from config
- Publish HA MQTT discovery configs on connect (retained messages)
- Publish state updates when Hearth state changes
- Subscribe to command topics for switches/numbers/buttons
- Handle commands by calling appropriate Hearth services
- Auto-reconnect with exponential backoff
- Use the `mqtt_client` pub.dev package

### Discovery Topics

Format: `homeassistant/<component>/hearth_<entity>/config`

### State Publishing

- On startup: publish all current states (retained)
- On change: publish changed entity state
- Retained messages so HA gets current state after restart

### Command Handling

Subscribe to `hearth/<clientId>/+/set` and `hearth/<clientId>/+/press`. Parse topic to determine entity, execute action.

## Dependencies

- `mqtt_client` package (pub.dev)
- MQTT broker accessible from Pi (Mosquitto, HA built-in, etc.)

## Files

- `lib/services/mqtt_service.dart` — new
- `lib/config/hub_config.dart` — mqtt fields
- `lib/screens/settings/settings_screen.dart` — MQTT settings
- `lib/services/local_api_server.dart` — web portal
- `lib/main.dart` — initialize
- `pubspec.yaml` — mqtt_client dependency
