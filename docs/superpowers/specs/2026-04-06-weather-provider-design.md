# Weather Provider Design

**Date:** 2026-04-06
**Status:** Approved

## Overview

Wire live weather data from Home Assistant's `weather.pirateweather` entity into the kiosk UI, replacing the hardcoded placeholder. Add a tap-to-expand full-screen forecast overlay with hourly and 7-day views.

## Data Source

Home Assistant `weather.*` entity via the existing WebSocket connection. Current conditions arrive as entity state updates. Forecasts are fetched via HA's `weather.get_forecasts` service call (HA 2023.12+), which returns both `hourly` and `daily` forecast arrays.

## Data Model

New file: `lib/models/weather_state.dart`

```
WeatherState
  condition: String        // HA condition: sunny, cloudy, partlycloudy, rainy, etc.
  temperature: double      // current temp
  high: double?            // today's high
  low: double?             // today's low
  humidity: double?        // percentage
  windSpeed: double?       // speed in configured unit
  hourlyForecast: List<HourlyForecast>  // next 24 hours
  dailyForecast: List<DailyForecast>    // 7 days

HourlyForecast
  time: DateTime
  temperature: double
  condition: String

DailyForecast
  date: DateTime
  high: double
  low: double
  condition: String
```

## Weather Service

New file: `lib/services/weather_service.dart`

- Riverpod `Provider` that watches `hubConfigProvider.select((c) => c.weatherEntityId)`
- Self-initializing: when the entity ID is non-empty, subscribes to HA entity stream filtered to that ID
- On each entity update, parses current conditions from entity state and attributes
- Fetches forecasts via HA WebSocket `weather.get_forecasts` service call every 30 minutes
- Requires adding a response-aware `callServiceWithResponse` method to `HomeAssistantService` (the existing `callService` is fire-and-forget — forecast needs the result data back)
- Exposes `Stream<WeatherState>` for widgets
- Disposes subscription on provider invalidation

## Config Change

Add `weatherEntityId` field to `HubConfig`:
- Default: empty string (shows placeholder)
- Type: `String`
- Added to: constructor, copyWith, toJson, fromJson
- Settings UI: new "Weather" section with text input for entity ID (e.g., `weather.pirateweather`)
- Local API server: included in config POST/GET (non-secret field)

## Condition Icon Mapping

New dependency: `weather_icons` package in pubspec.yaml.

New file: `lib/utils/weather_icons.dart`

Maps HA condition strings to `weather_icons` glyphs with day/night awareness:
- Day (6am–6pm): sun-based icons (wi_day_sunny, wi_day_cloudy, etc.)
- Night (6pm–6am): moon-based icons (wi_night_clear, wi_night_cloudy, etc.)

HA conditions to map:
- `sunny` / `clear-night` → day_sunny / night_clear
- `partlycloudy` → day_cloudy / night_alt_cloudy
- `cloudy` → cloudy
- `rainy` → rain
- `pouring` → rain_wind
- `snowy` → snow
- `snowy-rainy` → sleet
- `lightning` / `lightning-rainy` → thunderstorm
- `hail` → hail
- `fog` → fog
- `windy` / `windy-variant` → strong_wind
- `exceptional` → na (fallback)

## UI Changes

### Ambient Overlays (bottom-right weather)

Replace placeholder with:
- Condition icon (24px, from weather_icons)
- Current temperature (36px, existing style)
- Condition text (14px, existing style — now live, remove "(placeholder)")
- Wrap in GestureDetector → opens forecast overlay

### Home Screen (weather row)

Replace placeholder with:
- Condition icon (36px)
- Current temperature (48px, existing style)
- "H: XX° L: XX°" (existing style — now live, remove "(placeholder)")
- Wrap in GestureDetector → opens forecast overlay

### Forecast Overlay

New file: `lib/screens/weather/forecast_overlay.dart`

Full-screen overlay using the same pattern as the timer alert (dark scrim, tap to dismiss). Layout:

**Hero section (top):**
- Large condition icon (80px)
- Current temperature (64px)
- Condition text
- Humidity and wind speed in a subtitle row

**Hourly strip (middle):**
- Horizontal ListView of next 24 hours
- Each item: time label (top), small icon (middle), temperature (bottom)
- Fixed-width items, horizontally scrollable

**Daily section (bottom):**
- 7-row list, each row:
  - Day name (left-aligned)
  - Condition icon (center)
  - High/low temperature with a visual range bar (right-aligned)
- No scroll needed — 7 rows fit in the available space at 864px height

**Dismiss:** Tap anywhere outside content, or swipe down.

## Provider Wiring

```
weatherServiceProvider (watches weatherEntityId + homeAssistantServiceProvider)
  └─ weatherStateProvider (StreamProvider<WeatherState>)

Widgets watch weatherStateProvider:
  - AmbientOverlays
  - HomeScreen
  - ForecastOverlay
```

## Error Handling

- Empty `weatherEntityId` → show placeholder text (no icon, "Set weather in Settings")
- HA not connected → show placeholder
- Entity not found / no data → show "--°" with a generic icon
- Forecast fetch fails → show current conditions only, retry on next 30-min cycle
- Stale forecast (>1hr old) → still display it, next refresh will update

## Testing

- `WeatherState` model parsing from HA entity attributes (unit test)
- Condition → icon mapping for all HA conditions + day/night (unit test)
- Weather service entity filtering (unit test with fake HA channel)
- Forecast overlay renders with sample data (widget test if feasible)

## Dependencies

Add to `pubspec.yaml`:
```yaml
weather_icons: ^3.0.0
```
