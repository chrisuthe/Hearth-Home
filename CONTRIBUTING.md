# Contributing to Hearth

Thanks for your interest. Hearth is a Flutter smart-home kiosk targeting a Raspberry Pi 5 with an 11" AMOLED display. Most contributions fall into one of three buckets:

1. **Bug fixes & small improvements** — open a PR.
2. **New features in core areas** (weather, photos, Home Assistant, etc) — open an issue first to align on scope, then PR.
3. **A new screen module** (e.g., Google Calendar, Stocks, Stravaboard) — keep reading.

## Contributing a community module

Hearth ships with a small set of first-party modules (Media, Controls, Cameras, Recipes, Alarm Clock). Anyone can contribute additional modules by writing a self-contained Flutter screen + service that implements the `HearthModule` interface. Once merged, your module ships with every Hearth release, **disabled by default**, and users opt in through Settings → Screens → Community Contributed.

### What a module is

A module is a screen the user can navigate to (PageView swipe or menu) plus its own backend wiring (services, Riverpod providers, models). It lives entirely in its own folder under `lib/modules/<your_id>/` and exposes a single class implementing `HearthModule`.

### The interface

```dart
abstract class HearthModule {
  String get id;                                 // 'google-calendar'
  String get name;                               // Display name in Settings
  IconData get icon;                             // Page indicator + settings tile
  int get defaultOrder;                          // Position in PageView; negative = left of Home
  bool isConfigured(HubConfig config);           // false → setup prompt instead of screen
  Widget buildScreen({required bool isActive});  // The actual screen widget
  Widget? buildSettingsSection();                // Settings UI for your module, or null
  bool get isCommunity => false;                 // Override to true for community modules
}
```

### Folder convention

```
lib/modules/your_id/
  your_id_module.dart      # implements HearthModule
  your_id_screen.dart      # the UI
  your_id_service.dart     # API client / state (if needed)
  models.dart              # data models (if needed)
  widgets/                 # screen-specific widgets
```

Don't reach into other modules' folders. If your module needs something that's clearly cross-cutting (a shared widget, a utility), discuss in the PR — it might belong under `lib/widgets/` or `lib/utils/` instead.

### Step-by-step

1. **Fork** the repo and create a branch.
2. **Create your folder** under `lib/modules/<your_id>/`.
3. **Implement your module class** with `isCommunity => true`. Use `MealieModule` (`lib/modules/mealie/mealie_module.dart`) as the simplest reference.
4. **Build your screen** — any Flutter widget tree you like, gated by `isActive` for expensive work.
5. **Add config fields** to `lib/config/hub_config.dart` if you need persistent user config: declaration, default, `copyWith`, `toJson`, `fromJson`. Prefix field names with your module id (e.g., `googleCalendarApiKey`, not `apiKey`) to avoid collisions.
6. **Register** in `lib/modules/module_registry.dart` — one import line, one entry in `allModules`.
7. **Tests** — at minimum a widget smoke test that builds your screen with mocked services. Service unit tests are encouraged.
8. **Open a PR**. Include a screenshot of your screen running on the kiosk.

### What gets auto-wired

Once you're in `allModules`, Hearth handles:
- Settings → Screens placement UI (swipe / menu1 / menu2 toggles per module)
- Per-module section under Settings (your `buildSettingsSection()` widget is rendered automatically)
- Setup prompt when `isConfigured()` returns false
- Module reordering via drag-and-drop

You don't write navigation code, register routes, or modify HubShell.

### Capability access

Modules can freely use:
- **Toasts** — `ref.read(toastProvider.notifier).show(...)` from `lib/services/toast_service.dart`
- **Timers** — `lib/services/timer_service.dart`
- **Alarms** — the alarm-clock module's service is publicly accessible
- **HTTP** — use `dio` (already a dependency); please don't add another HTTP client
- **Your own config** — anything you added to `HubConfig`
- **Your own Riverpod providers** — keep them in your folder

Modules **should ask before using**:
- **Home Assistant service calls** (`ha.callService(...)`) — privilege escalation risk; flag in your PR description
- **Music Assistant / Frigate / Immich** services — these are first-party integrations; opt-in case-by-case
- **Native code / FFI / Process.run** — describe what and why; needs extra review
- **New pub package dependencies** — discuss before adding; coordinate on shared deps (`dio`, `googleapis`, etc) so versions don't conflict between community modules

### Conventions

- **Linting**: project enforces `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`. Use `debugPrint` not `print`.
- **State**: Riverpod for everything stateful.
- **Logging**: use `Log.i('YourModule', '...')` from `lib/utils/log.dart` rather than `debugPrint` for service-layer messages.
- **Theme**: dark theme, true black background (AMOLED), indigo accent `0xFF646CFF`.
- **Render resolution**: 1184×864 (the panel's half-resolution). Design for that, not for desktop.
- **Performance**: the `isActive` parameter to `buildScreen()` tells you when your screen is on-stage. Pause expensive work (timers, animations, network polling) when inactive.

### What we'll review

- **Security**: does the module exfiltrate data, expose tokens, or escalate privilege? Does it call HA services without user awareness?
- **Reliability**: does it crash on a flaky network? Leak resources? Block the UI thread?
- **Fit**: does it serve a kiosk audience? (Hearth is not a phone — touch targets must be large, text must be readable from across the room.)
- **Maintenance**: are you committing to maintain it? Modules without an active maintainer that break against a third-party API can be marked broken or removed.
- **Tests**: at minimum, a widget smoke test that doesn't crash.

### Dependency policy

Hearth has a single `pubspec.yaml`. If two community modules depend on incompatible versions of the same package, the build breaks for everyone. To avoid that:

- Prefer existing dependencies (`dio`, `flutter_riverpod`, `cached_network_image`, etc) over adding new ones.
- If you must add a dep, pick a well-maintained package with a permissive license.
- If you need a version bump on a shared dep, raise it in the PR — we may need to coordinate with other modules.

### After your PR is merged

- Your module ships in the next Hearth release, **disabled by default**.
- Users see it in Settings → Screens under "Community Contributed" with a description noting it's community-authored.
- You get a credit in the release notes.
- If your module breaks against a third-party API change, you're the first contact for fixing it.

## Submitting a PR (for any change)

- Fork, branch, commit, push, open PR against `main`.
- Run `flutter analyze` and `flutter test` locally before opening — CI runs these and will reject on warnings.
- Keep PRs focused. One module per PR; one bug fix per PR.
- Match existing commit message style (look at `git log` for tone).
- If your change affects architecture, update `CLAUDE.md`.

Maintainers cutting a release should follow [docs/RELEASING.md](docs/RELEASING.md),
which covers syncing both remotes, the version bump, tagging, the wiki, and CI
verification.

## Questions

Open an issue with the `question` label, or start a discussion. Module ideas welcome before you write code — we'll tell you up front if a module is in or out of scope for Hearth.
