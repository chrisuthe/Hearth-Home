# Module System + Mealie Integration — Design Spec

**Date:** 2026-04-09
**Status:** Approved

## Overview

Add a plugin-style module system to Hearth so optional screens (Cameras, Controls, Media, Recipes) can be enabled/disabled per user. Includes the first new module: Mealie recipe integration for browsing and cooking.

## Module Interface

```dart
abstract class HearthModule {
  String get id;              // 'mealie', 'cameras', 'controls', 'media'
  String get name;            // 'Recipes', 'Cameras'
  IconData get icon;          // For page indicators and settings
  int get defaultOrder;       // Sort position (lower = further left)

  bool isConfigured(HubConfig config);
  Widget buildScreen({required bool isActive});
  Widget? buildSettingsSection();
}
```

- Home is always present at a fixed center position — not a module.
- Immich (ambient photos) is the background layer — not a module.
- Settings, Setup, and Timer are core UI — not modules.
- A module can be enabled but not configured — shows "configure in Settings" instead of being hidden.

## Module Registry

Static list in `lib/modules/module_registry.dart`:

```dart
final allModules = <HearthModule>[
  MediaModule(),
  ControlsModule(),
  CamerasModule(),
  MealieModule(),
];
```

No dynamic loading, no plugin manifest. Adding a module = implement the interface + add one line to the registry.

## Config

New HubConfig fields:

```dart
final List<String> enabledModules;  // Default: all current modules enabled
final String mealieUrl;             // Mealie server URL
final String mealieToken;           // Mealie API token
```

Existing installs get all current modules enabled by default so no screens disappear on upgrade.

## Dynamic PageView (HubShell)

HubShell builds the PageView dynamically:

1. Filter `allModules` to those whose `id` is in `enabledModules`
2. Sort by `defaultOrder`
3. Insert Home at the center
4. Build PageView from the result
5. Home is always the initial page

Screen order is fixed by `defaultOrder` for now. User reordering is a future enhancement.

## Settings

- New "Modules" section with a toggle for each module in `allModules`
- Each module's `buildSettingsSection()` is rendered after the core settings sections
- Module settings sections only appear when the module is enabled

## File Reorganization

Move all optional screens and their services into `lib/modules/<name>/`:

```
lib/modules/
  hearth_module.dart              # Interface definition
  module_registry.dart            # Static registry list
  cameras/
    cameras_module.dart
    cameras_screen.dart           # from lib/screens/cameras/
    frigate_service.dart          # from lib/services/
  controls/
    controls_module.dart
    controls_screen.dart          # from lib/screens/controls/
    light_card.dart               # from lib/screens/controls/
    climate_card.dart             # from lib/screens/controls/
  media/
    media_module.dart
    media_screen.dart             # from lib/screens/media/
  mealie/
    mealie_module.dart            # new
    mealie_screen.dart            # new
    mealie_service.dart           # new
```

Stays in `lib/screens/` (core, not optional):
- `home/` — always present
- `settings/` — always present
- `setup/` — first-boot wizard
- `timer/` — overlay, not a page
- `ambient/` — background layer (Immich photos)

Stays in `lib/services/` (shared infrastructure):
- `home_assistant_service.dart` — used by multiple modules
- `music_assistant_service.dart` — used by media module + ambient overlays
- `weather_service.dart` — used by home screen
- `display_mode_service.dart`, `local_api_server.dart`, `wifi_service.dart`, `update_service.dart`, `timer_service.dart` — core services
- `immich_service.dart` — ambient background, not a module
- `sendspin/` — could become a module later

## Mealie Module

### Service (`mealie_service.dart`)

REST client using Dio with Bearer token auth:
- `getMealPlanToday()` — `GET /api/households/mealplans/today`
- `searchRecipes(String query)` — `GET /api/recipes?search=<query>`
- `getRecipe(String slug)` — `GET /api/recipes/<slug>`
- `getCategories()` — `GET /api/organizers/categories`
- Recipe images: `GET /api/media/recipes/<id>/images/min-original.webp` with auth header
- Auto-refreshes meal plan every 30 minutes

### Browse View (default state)

- **Top**: Today's meal plan — breakfast/lunch/dinner cards with recipe image and name
- **Below**: Search bar + category chips for filtering
- **Tap** a meal plan item or search result to open recipe detail
- **Empty states**: "Configure Mealie in Settings" (not configured), "No meal plan for today" (configured but empty)

### Recipe Detail View (within the same screen)

- Back button returns to browse
- Recipe image header
- Title, prep/cook time, servings
- Ingredients list (scrollable, checkbox-style for tracking while cooking)
- Instructions as numbered steps with large readable text
- Stays in the PageView — user can swipe to cameras/timers/music and come back with state preserved

### Settings Section

- Mealie URL field
- Mealie API Token field (obscured)
- Same tile pattern as existing HA/Immich settings

## What's Out of Scope

- User-configurable screen ordering (future enhancement)
- Dynamic plugin loading / third-party modules
- Voice control for cooking mode
- Shopping list integration
- Mealie recipe editing from the kiosk
