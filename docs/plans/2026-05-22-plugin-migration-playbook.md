# Plugin Migration Playbook

Recipe for migrating an existing Hearth integration / module / cross-cutting
section into a `HearthPlugin`. Established alongside the Weather migration
(see `docs/specs/2026-05-22-settings-unification-design.md`).

## When to use

You're migrating ONE existing thing — e.g. "Home Assistant integration" or
"the Network section" — from the legacy `settings_screen.dart` +
`_legacyConfigHtml` inline code into a `HearthPlugin` implementation.

This playbook assumes Phase 1 (framework foundations + Weather canary) is
already shipped at v1.11.0.

## Steps

1. **Identify the scope.** What HubConfig fields does this plugin own? Does
   it have a PageView screen (i.e. was it a HearthModule)? Does it have HTTP
   routes? List them.

2. **Pick the plugin ID.** Convention: `hearth.<lowercase-name>`. Pick the
   sort order — first-party plugins go in 10-step gaps within their
   category.

3. **Create the plugin folder.** `lib/plugins/<name>/<name>_plugin.dart`.
   Mirror the Weather example at `lib/plugins/weather/weather_plugin.dart`.

4. **Add needed field primitives if missing.** Phase 1 only shipped
   `TextSettingField`. If your plugin needs `BoolSettingField`,
   `SelectSettingField`, `SliderSettingField`, etc., build that primitive
   FIRST as its own commit before the plugin itself. Use
   `TextSettingField` (`lib/plugins/framework/fields/text_setting_field.dart`)
   as the template. Each primitive needs both Flutter `buildWidget` and
   HTML `buildHtml` implementations plus tests.

5. **Write the `HearthPlugin` implementation:**
   - `id`, `name`, `icon`, `category`, `order`, `isCommunity`
   - `statusFor(config)` — derive from current HubConfig
   - `buildSettingsWidget(ref)` — compose field primitives into a `Column`
   - `buildSettingsHtml(ctx)` — concatenate field primitives' HTML output
   - `pageScreen` — if was a HearthModule, port the screen here
   - `registerHttpRoutes(router)` — if had backend endpoints, register them
   - `dependencies` — list any plugin IDs this depends on

6. **Add to the registry.** Edit `lib/plugins/plugin_registry.dart`, add
   `XPlugin()` to `_firstPartyPlugins`. The order in the list doesn't
   matter — sort is determined by `category` + `order`.

7. **Remove the legacy code.** Strip the plugin's fields from:
   - `lib/screens/settings/settings_screen.dart`'s `_buildLegacyPanel` method
   - `lib/services/local_api_server.dart`'s `_legacyConfigHtml` constant
   - Any old `/api/<thing>/...` routes in `_handleRequest`'s dispatch chain
     — they're replaced by `/api/plugin/<id>/...`
   - Any references in the JS textFields array inside `_legacyConfigHtml`

8. **Write tests:**
   - Plugin smoke tests (id, statusFor, buildSettingsHtml content match)
   - Field primitive tests if you added a new one
   - HTTP route tests if you registered routes
   - Aim for the same coverage as `test/plugins/weather/weather_plugin_test.dart`

9. **Bump version + tag.** Each plugin migration is a release. Use the
   patch number (1.11.1, 1.11.2, ...). Convention: each migration commit
   message starts with `feat(<plugin-name>): migrate to HearthPlugin`.

10. **Manual smoke test on Pi** (`ssh hearthdev@10.0.1.13`):
    - Verify the plugin appears in the sidebar on both surfaces
    - Verify all its fields render correctly
    - Verify a field edit round-trips through the config
    - Verify the legacy duplicate is gone

## Recommended migration order

Per the design spec, the recommended order:

1. ✅ WeatherPlugin (done — canary in v1.11.0)
2. HomeAssistantPlugin (largest scope; consolidates URL, token, voice
   satellite, Controls module, pinned entities)
3. WebviewPlugin (already exists structurally — refactor)
4. FrigatePlugin (integration + Cameras module)
5. MusicAssistantPlugin (integration + Media module)
6. ImmichPlugin (integration + photo sources)
7. MealiePlugin (integration + Recipes module)
8. AlarmClockPlugin
9. SendspinPlugin
10. ScreensOrderPlugin (the new home for module placement + reorder UI)
11. DisplayPlugin
12. AudioPlugin
13. VoicePlugin
14. NetworkPlugin
15. SystemPlugin (logs + updates + capture)

After SystemPlugin: Phase 5 cleanup — remove `_legacyConfigHtml`, the
Legacy sidebar entry, and any remaining inline code in
`settings_screen.dart`'s `_buildLegacyPanel`.

## Common pitfalls

- **Forgetting to add the new primitive to the framework folder.** If a
  plugin needs `BoolSettingField`, it goes in
  `lib/plugins/framework/fields/`, not in the plugin's own folder. Plugins
  consume framework primitives.

- **Confusing `configPath` with custom read/write.** Use `configPath` for
  scalar fields with names matching `HubConfig.toJson()` keys directly.
  For lists, maps, computed values, override `readValue` and `writeValue`.

- **Leaving the legacy route in place.** When migrating a plugin that had
  HTTP endpoints, REMOVE the old routes from `local_api_server.dart`'s
  switch in `_handleRequest`. Otherwise dead code accumulates and may
  shadow plugin routes.

- **Forgetting tests.** Each migration adds tests; over time the framework
  becomes resilient to changes.

- **Bespoke widget escape hatches.** Some Settings UIs don't compress into
  primitives (entity picker, WiFi scanner, photo source browser, timezone
  picker). For those, the plugin returns a fully-bespoke widget/HTML
  fragment from `buildSettingsWidget` / `buildSettingsHtml`. Don't try to
  generalize what's a one-off.

## What's NOT in this playbook

- Hot-loadable / runtime plugins (compile-time only by design)
- Cross-plugin coordination (plugins don't talk to each other directly —
  they read each other's config via HubConfig if needed)
- Plugin marketplace mechanics
- Field-label-text search (only plugin-name search is in v1)
- Plugin disable/enable UI (plugins compiled into the binary always appear)

## Useful file pointers

- Interface: `lib/plugins/hearth_plugin.dart`
- Registry: `lib/plugins/plugin_registry.dart`
- Field primitives: `lib/plugins/framework/fields/`
- HTTP router: `lib/plugins/framework/plugin_router.dart`
- Web rendering: `lib/plugins/framework/web_renderer.dart`,
  `lib/plugins/framework/web_assets.dart`
- Flutter UI shell: `lib/plugins/framework/plugin_sidebar.dart`,
  `lib/plugins/framework/plugin_panel.dart`
- Canary example: `lib/plugins/weather/weather_plugin.dart`,
  `test/plugins/weather/weather_plugin_test.dart`
