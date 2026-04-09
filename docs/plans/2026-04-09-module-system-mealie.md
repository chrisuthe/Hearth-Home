# Module System + Mealie Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a module system that makes PageView screens pluggable, then implement Mealie recipe browsing as the first new module.

**Architecture:** Each optional screen implements a `HearthModule` interface. A static registry lists all modules. HubShell builds the PageView dynamically from enabled modules. Existing screens (Media, Controls, Cameras) are wrapped as modules and moved to `lib/modules/<name>/`. Mealie is built as a new module with a REST service, browse view, and recipe detail view.

**Tech Stack:** Flutter, Riverpod, Dio (HTTP), CachedNetworkImage, existing dark theme patterns

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/modules/hearth_module.dart` | Abstract module interface |
| `lib/modules/module_registry.dart` | Static list of all modules + Riverpod providers |
| `lib/modules/media/media_module.dart` | Module wrapper for media screen |
| `lib/modules/controls/controls_module.dart` | Module wrapper for controls screen |
| `lib/modules/cameras/cameras_module.dart` | Module wrapper for cameras screen |
| `lib/modules/mealie/mealie_module.dart` | Module wrapper for Mealie |
| `lib/modules/mealie/mealie_service.dart` | Mealie REST client |
| `lib/modules/mealie/mealie_screen.dart` | Browse + recipe detail views |
| `lib/modules/mealie/models.dart` | MealieRecipe, MealieMealPlan data classes |
| `test/modules/mealie/mealie_service_test.dart` | Service unit tests |

### Moved Files
| From | To |
|------|------|
| `lib/screens/media/media_screen.dart` | `lib/modules/media/media_screen.dart` |
| `lib/screens/controls/controls_screen.dart` | `lib/modules/controls/controls_screen.dart` |
| `lib/screens/controls/light_card.dart` | `lib/modules/controls/light_card.dart` |
| `lib/screens/controls/climate_card.dart` | `lib/modules/controls/climate_card.dart` |
| `lib/screens/cameras/cameras_screen.dart` | `lib/modules/cameras/cameras_screen.dart` |
| `lib/services/frigate_service.dart` | `lib/modules/cameras/frigate_service.dart` |

### Modified Files
| File | Changes |
|------|---------|
| `lib/config/hub_config.dart` | Add `enabledModules`, `mealieUrl`, `mealieToken` fields |
| `lib/app/hub_shell.dart` | Dynamic PageView from module registry |
| `lib/screens/settings/settings_screen.dart` | Module toggles section + Mealie settings |
| `lib/services/local_api_server.dart` | Add `mealieUrl`, `mealieToken` to web portal |
| All files importing moved screens/services | Update import paths |

---

### Task 1: Module Interface and Registry

**Files:**
- Create: `lib/modules/hearth_module.dart`
- Create: `lib/modules/module_registry.dart`

- [ ] **Step 1: Create the module interface**

Create `lib/modules/hearth_module.dart`:

```dart
import 'package:flutter/material.dart';
import '../config/hub_config.dart';

/// Interface for pluggable Hearth screen modules.
///
/// Each optional screen (Cameras, Controls, Media, Recipes) implements
/// this interface. The module registry collects all implementations and
/// HubShell builds the PageView dynamically from enabled modules.
abstract class HearthModule {
  /// Unique identifier stored in config (e.g., 'mealie', 'cameras').
  String get id;

  /// Display name shown in Settings (e.g., 'Recipes', 'Cameras').
  String get name;

  /// Icon for page indicators and module settings toggles.
  IconData get icon;

  /// Default sort position in the PageView. Lower = further left from Home.
  /// Negative = left of Home, positive = right of Home.
  int get defaultOrder;

  /// Whether this module has enough config to function.
  /// A module can be enabled but not configured — it shows a setup prompt.
  bool isConfigured(HubConfig config);

  /// The main screen widget for the PageView.
  Widget buildScreen({required bool isActive});

  /// Settings section widget, or null if the module needs no settings.
  Widget? buildSettingsSection();
}
```

- [ ] **Step 2: Create the module registry**

Create `lib/modules/module_registry.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/hub_config.dart';
import 'hearth_module.dart';
import 'media/media_module.dart';
import 'controls/controls_module.dart';
import 'cameras/cameras_module.dart';
import 'mealie/mealie_module.dart';

/// All available modules. Order here doesn't matter — defaultOrder controls display.
final allModules = <HearthModule>[
  MediaModule(),
  ControlsModule(),
  CamerasModule(),
  MealieModule(),
];

/// Modules that are currently enabled, sorted by defaultOrder.
final enabledModulesProvider = Provider<List<HearthModule>>((ref) {
  final config = ref.watch(hubConfigProvider);
  final enabledIds = config.enabledModules;
  return allModules
      .where((m) => enabledIds.contains(m.id))
      .toList()
    ..sort((a, b) => a.defaultOrder.compareTo(b.defaultOrder));
});
```

- [ ] **Step 3: Commit**

```bash
git add lib/modules/hearth_module.dart lib/modules/module_registry.dart
git commit -m "feat: add HearthModule interface and module registry"
```

---

### Task 2: Add Config Fields

**Files:**
- Modify: `lib/config/hub_config.dart`
- Modify: `test/config/hub_config_test.dart`

- [ ] **Step 1: Add new fields to HubConfig**

Add after `currentVersion`:

```dart
final List<String> enabledModules;
final String mealieUrl;
final String mealieToken;
```

Constructor defaults:
```dart
this.enabledModules = const ['media', 'controls', 'cameras'],
this.mealieUrl = '',
this.mealieToken = '',
```

Add to `copyWith` (enabledModules as `List<String>?`, mealieUrl and mealieToken as `String?`).

Add to `toJson`:
```dart
'enabledModules': enabledModules,
'mealieUrl': mealieUrl,
'mealieToken': mealieToken,
```

Add to `fromJson`:
```dart
enabledModules: (json['enabledModules'] as List<dynamic>?)?.cast<String>() ?? const ['media', 'controls', 'cameras'],
mealieUrl: json['mealieUrl'] as String? ?? '',
mealieToken: json['mealieToken'] as String? ?? '',
```

- [ ] **Step 2: Add tests**

In `test/config/hub_config_test.dart`:

```dart
test('enabledModules defaults to media, controls, cameras', () {
  const config = HubConfig();
  expect(config.enabledModules, ['media', 'controls', 'cameras']);
});

test('mealie fields round-trip through JSON', () {
  const config = HubConfig(
    mealieUrl: 'http://mealie.local:9925',
    mealieToken: 'test-token',
  );
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.mealieUrl, 'http://mealie.local:9925');
  expect(restored.mealieToken, 'test-token');
});

test('enabledModules round-trips through JSON', () {
  const config = HubConfig(enabledModules: ['cameras', 'mealie']);
  final json = config.toJson();
  final restored = HubConfig.fromJson(json);
  expect(restored.enabledModules, ['cameras', 'mealie']);
});
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/config/hub_config_test.dart -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/config/hub_config.dart test/config/hub_config_test.dart
git commit -m "feat: add enabledModules and Mealie config fields"
```

---

### Task 3: Move Existing Screens to Module Directories

**Files:**
- Move: `lib/screens/media/media_screen.dart` → `lib/modules/media/media_screen.dart`
- Move: `lib/screens/controls/controls_screen.dart` → `lib/modules/controls/controls_screen.dart`
- Move: `lib/screens/controls/light_card.dart` → `lib/modules/controls/light_card.dart`
- Move: `lib/screens/controls/climate_card.dart` → `lib/modules/controls/climate_card.dart`
- Move: `lib/screens/cameras/cameras_screen.dart` → `lib/modules/cameras/cameras_screen.dart`
- Move: `lib/services/frigate_service.dart` → `lib/modules/cameras/frigate_service.dart`
- Update: all files with imports to these moved files

- [ ] **Step 1: Create module directories and move files**

```bash
mkdir -p lib/modules/media lib/modules/controls lib/modules/cameras lib/modules/mealie
git mv lib/screens/media/media_screen.dart lib/modules/media/media_screen.dart
git mv lib/screens/controls/controls_screen.dart lib/modules/controls/controls_screen.dart
git mv lib/screens/controls/light_card.dart lib/modules/controls/light_card.dart
git mv lib/screens/controls/climate_card.dart lib/modules/controls/climate_card.dart
git mv lib/screens/cameras/cameras_screen.dart lib/modules/cameras/cameras_screen.dart
git mv lib/services/frigate_service.dart lib/modules/cameras/frigate_service.dart
```

- [ ] **Step 2: Update all imports**

Find and replace all import paths across the codebase. Key files that import these:
- `lib/app/hub_shell.dart` — imports MediaScreen, ControlsScreen, CamerasScreen
- `lib/modules/controls/controls_screen.dart` — imports light_card.dart, climate_card.dart
- `lib/modules/cameras/cameras_screen.dart` — imports frigate_service.dart
- `test/services/frigate_entity_parsing_test.dart` — imports frigate_service.dart
- `lib/screens/settings/settings_screen.dart` — may import frigate or controls
- Any other files referencing the old paths

Use `grep -rn` to find all imports that reference the old paths and update them.

The new import paths follow the pattern:
- `import '../../modules/media/media_screen.dart';` (from hub_shell.dart)
- `import '../modules/cameras/frigate_service.dart';` (from services that reference frigate)

- [ ] **Step 3: Run tests and analyze**

Run: `flutter test`
Run: `flutter analyze`
Expected: ALL PASS, no broken imports

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: move optional screens into lib/modules/ directories"
```

---

### Task 4: Create Module Wrappers for Existing Screens

**Files:**
- Create: `lib/modules/media/media_module.dart`
- Create: `lib/modules/controls/controls_module.dart`
- Create: `lib/modules/cameras/cameras_module.dart`

- [ ] **Step 1: Create MediaModule**

Create `lib/modules/media/media_module.dart`:

```dart
import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'media_screen.dart';

class MediaModule implements HearthModule {
  @override
  String get id => 'media';

  @override
  String get name => 'Music';

  @override
  IconData get icon => Icons.music_note;

  @override
  int get defaultOrder => -10;

  @override
  bool isConfigured(HubConfig config) =>
      config.musicAssistantUrl.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const MediaScreen();

  @override
  Widget? buildSettingsSection() => null;
}
```

- [ ] **Step 2: Create ControlsModule**

Create `lib/modules/controls/controls_module.dart`:

```dart
import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'controls_screen.dart';

class ControlsModule implements HearthModule {
  @override
  String get id => 'controls';

  @override
  String get name => 'Controls';

  @override
  IconData get icon => Icons.lightbulb_outline;

  @override
  int get defaultOrder => 10;

  @override
  bool isConfigured(HubConfig config) =>
      config.haUrl.isNotEmpty && config.pinnedEntityIds.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const ControlsScreen();

  @override
  Widget? buildSettingsSection() => null;
}
```

- [ ] **Step 3: Create CamerasModule**

Create `lib/modules/cameras/cameras_module.dart`:

```dart
import 'package:flutter/material.dart';
import '../../config/hub_config.dart';
import '../hearth_module.dart';
import 'cameras_screen.dart';

class CamerasModule implements HearthModule {
  @override
  String get id => 'cameras';

  @override
  String get name => 'Cameras';

  @override
  IconData get icon => Icons.videocam;

  @override
  int get defaultOrder => 20;

  @override
  bool isConfigured(HubConfig config) =>
      config.frigateUrl.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) =>
      CamerasScreen(isActive: isActive);

  @override
  Widget? buildSettingsSection() => null;
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/modules/media/media_module.dart lib/modules/controls/controls_module.dart lib/modules/cameras/cameras_module.dart
git commit -m "feat: create module wrappers for existing screens"
```

---

### Task 5: Dynamic PageView in HubShell

**Files:**
- Modify: `lib/app/hub_shell.dart`

- [ ] **Step 1: Update HubShell to use module registry**

In `lib/app/hub_shell.dart`:

1. Add imports:
```dart
import '../modules/module_registry.dart';
import '../modules/hearth_module.dart';
```

2. Remove hardcoded imports for MediaScreen, ControlsScreen, CamerasScreen (they're now accessed through modules).

3. Replace the hardcoded PageView children with dynamic building. In `_HubShellState`:

Replace:
```dart
static const int _homeIndex = 1;
static const int _pageCount = 5;
```

With a computed approach. The home index depends on how many modules have negative defaultOrder (they go left of Home).

In the `build` method, compute the screen list:
```dart
final modules = ref.watch(enabledModulesProvider);
final leftModules = modules.where((m) => m.defaultOrder < 0).toList();
final rightModules = modules.where((m) => m.defaultOrder >= 0).toList();
final homeIndex = leftModules.length;
final pages = <Widget>[
  ...leftModules.map((m) => m.buildScreen(isActive: _currentPage == leftModules.indexOf(m))),
  const HomeScreen(),
  ...rightModules.map((m) => m.buildScreen(
      isActive: _currentPage == homeIndex + 1 + rightModules.indexOf(m))),
  const SettingsScreen(),
];
```

4. Update `_pageController` initialization. Since `homeIndex` depends on modules (which depend on config loaded via Riverpod), the PageController needs to be created or updated when modules change. The simplest approach: compute `homeIndex` in `initState` from the initial config, and recreate the controller if modules change.

Actually simpler: since the module list rarely changes (only when user toggles in Settings), compute it in build and use the index there. The PageController's initialPage is set once in initState — use the default module count for that.

5. Replace the hardcoded PageView children:
```dart
PageView(
  controller: _pageController,
  physics: idle.isIdle
      ? const NeverScrollableScrollPhysics()
      : const BouncingScrollPhysics(),
  children: pages,
),
```

6. Update keyboard navigation to use dynamic page count instead of hardcoded 5.

- [ ] **Step 2: Run tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add lib/app/hub_shell.dart
git commit -m "feat: build PageView dynamically from enabled modules"
```

---

### Task 6: Module Settings Section

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

- [ ] **Step 1: Add Modules section to Settings**

In `lib/screens/settings/settings_screen.dart`:

1. Add imports:
```dart
import '../../modules/module_registry.dart';
```

2. Add a "Modules" section after the "Network" / "Web Access" sections and before "Connections". Show a SwitchListTile for each module in `allModules`:

```dart
_SectionHeader(title: 'Modules'),
const SizedBox(height: 8),
...allModules.map((module) {
  final isEnabled = config.enabledModules.contains(module.id);
  return SwitchListTile(
    secondary: Icon(module.icon, color: Colors.white54),
    title: Text(module.name),
    value: isEnabled,
    onChanged: (v) {
      final updated = List<String>.from(config.enabledModules);
      if (v) {
        updated.add(module.id);
      } else {
        updated.remove(module.id);
      }
      _updateConfig((c) => c.copyWith(enabledModules: updated));
    },
  );
}),
const SizedBox(height: 24),
```

3. After the existing settings sections, append each enabled module's settings section:

```dart
...allModules
    .where((m) => config.enabledModules.contains(m.id))
    .map((m) => m.buildSettingsSection())
    .whereType<Widget>(),
```

- [ ] **Step 2: Run tests**

Run: `flutter test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat: add module toggle switches and per-module settings sections"
```

---

### Task 7: Mealie Data Models

**Files:**
- Create: `lib/modules/mealie/models.dart`
- Create: `test/modules/mealie/models_test.dart`

- [ ] **Step 1: Create data models**

Create `lib/modules/mealie/models.dart`:

```dart
/// A recipe summary (from list/search endpoints).
class MealieRecipeSummary {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? image; // relative path or null
  final int? totalTime; // minutes, parsed from ISO 8601
  final int? rating;

  const MealieRecipeSummary({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.image,
    this.totalTime,
    this.rating,
  });

  factory MealieRecipeSummary.fromJson(Map<String, dynamic> json) {
    return MealieRecipeSummary(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      image: json['image'] as String?,
      totalTime: _parseIsoDuration(json['totalTime'] as String?),
      rating: json['rating'] as int?,
    );
  }
}

/// Full recipe detail (from /api/recipes/{slug}).
class MealieRecipe {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? image;
  final int? prepTime;
  final int? cookTime;
  final int? totalTime;
  final String? recipeYield;
  final List<MealieIngredient> ingredients;
  final List<MealieInstruction> instructions;

  const MealieRecipe({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.image,
    this.prepTime,
    this.cookTime,
    this.totalTime,
    this.recipeYield,
    this.ingredients = const [],
    this.instructions = const [],
  });

  factory MealieRecipe.fromJson(Map<String, dynamic> json) {
    return MealieRecipe(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      image: json['image'] as String?,
      prepTime: _parseIsoDuration(json['prepTime'] as String?),
      cookTime: _parseIsoDuration(json['cookTime'] as String?),
      totalTime: _parseIsoDuration(json['totalTime'] as String?),
      recipeYield: json['recipeYield'] as String?,
      ingredients: (json['recipeIngredient'] as List<dynamic>?)
              ?.map((e) => MealieIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      instructions: (json['recipeInstructions'] as List<dynamic>?)
              ?.map((e) => MealieInstruction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class MealieIngredient {
  final String display;
  final bool isFood;

  const MealieIngredient({required this.display, this.isFood = true});

  factory MealieIngredient.fromJson(Map<String, dynamic> json) {
    return MealieIngredient(
      display: json['display'] as String? ?? json['note'] as String? ?? '',
      isFood: json['isFood'] as bool? ?? true,
    );
  }
}

class MealieInstruction {
  final String text;

  const MealieInstruction({required this.text});

  factory MealieInstruction.fromJson(Map<String, dynamic> json) {
    return MealieInstruction(
      text: json['text'] as String? ?? '',
    );
  }
}

class MealieMealPlanEntry {
  final String entryType; // 'breakfast', 'lunch', 'dinner', 'side'
  final MealieRecipeSummary? recipe;

  const MealieMealPlanEntry({required this.entryType, this.recipe});

  factory MealieMealPlanEntry.fromJson(Map<String, dynamic> json) {
    final recipeJson = json['recipe'] as Map<String, dynamic>?;
    return MealieMealPlanEntry(
      entryType: json['entryType'] as String? ?? '',
      recipe: recipeJson != null ? MealieRecipeSummary.fromJson(recipeJson) : null,
    );
  }
}

/// Parses ISO 8601 duration (e.g., "PT30M", "PT1H15M") to minutes.
int? _parseIsoDuration(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final match = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?').firstMatch(iso);
  if (match == null) return null;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  return hours * 60 + minutes;
}
```

- [ ] **Step 2: Write tests**

Create `test/modules/mealie/models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/mealie/models.dart';

void main() {
  group('MealieRecipeSummary', () {
    test('parses from JSON', () {
      final json = {
        'id': 'abc-123',
        'slug': 'chicken-soup',
        'name': 'Chicken Soup',
        'description': 'A classic',
        'totalTime': 'PT45M',
        'rating': 5,
      };
      final recipe = MealieRecipeSummary.fromJson(json);
      expect(recipe.slug, 'chicken-soup');
      expect(recipe.name, 'Chicken Soup');
      expect(recipe.totalTime, 45);
    });

    test('handles missing optional fields', () {
      final json = {'id': '1', 'slug': 'test', 'name': 'Test'};
      final recipe = MealieRecipeSummary.fromJson(json);
      expect(recipe.totalTime, isNull);
      expect(recipe.description, isNull);
    });
  });

  group('MealieRecipe', () {
    test('parses full recipe with ingredients and instructions', () {
      final json = {
        'id': 'abc',
        'slug': 'pasta',
        'name': 'Pasta',
        'prepTime': 'PT15M',
        'cookTime': 'PT30M',
        'totalTime': 'PT45M',
        'recipeYield': '4 servings',
        'recipeIngredient': [
          {'display': '500g pasta'},
          {'display': '2 cups sauce'},
        ],
        'recipeInstructions': [
          {'text': 'Boil water'},
          {'text': 'Cook pasta'},
        ],
      };
      final recipe = MealieRecipe.fromJson(json);
      expect(recipe.prepTime, 15);
      expect(recipe.cookTime, 30);
      expect(recipe.ingredients.length, 2);
      expect(recipe.instructions.length, 2);
      expect(recipe.ingredients[0].display, '500g pasta');
      expect(recipe.instructions[1].text, 'Cook pasta');
    });
  });

  group('ISO duration parsing', () {
    test('parses PT30M', () {
      final recipe = MealieRecipeSummary.fromJson({
        'id': '1', 'slug': 't', 'name': 't', 'totalTime': 'PT30M'
      });
      expect(recipe.totalTime, 30);
    });

    test('parses PT1H15M', () {
      final recipe = MealieRecipeSummary.fromJson({
        'id': '1', 'slug': 't', 'name': 't', 'totalTime': 'PT1H15M'
      });
      expect(recipe.totalTime, 75);
    });

    test('returns null for empty', () {
      final recipe = MealieRecipeSummary.fromJson({
        'id': '1', 'slug': 't', 'name': 't'
      });
      expect(recipe.totalTime, isNull);
    });
  });

  group('MealieMealPlanEntry', () {
    test('parses with recipe', () {
      final json = {
        'entryType': 'dinner',
        'recipe': {'id': '1', 'slug': 'steak', 'name': 'Steak'},
      };
      final entry = MealieMealPlanEntry.fromJson(json);
      expect(entry.entryType, 'dinner');
      expect(entry.recipe?.name, 'Steak');
    });

    test('handles null recipe', () {
      final json = {'entryType': 'lunch'};
      final entry = MealieMealPlanEntry.fromJson(json);
      expect(entry.recipe, isNull);
    });
  });
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/modules/mealie/models_test.dart -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/modules/mealie/models.dart test/modules/mealie/models_test.dart
git commit -m "feat: add Mealie data models with JSON parsing"
```

---

### Task 8: Mealie Service

**Files:**
- Create: `lib/modules/mealie/mealie_service.dart`
- Create: `test/modules/mealie/mealie_service_test.dart`

- [ ] **Step 1: Create the service**

Create `lib/modules/mealie/mealie_service.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../utils/logger.dart';
import 'models.dart';

class MealieService {
  final Dio _dio;
  final String _baseUrl;

  MealieService({required String baseUrl, required String token})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _dio = Dio(BaseOptions(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// Get today's meal plan entries.
  Future<List<MealieMealPlanEntry>> getMealPlanToday() async {
    try {
      final response = await _dio.get('$_baseUrl/api/households/mealplans/today');
      final list = response.data as List<dynamic>? ?? [];
      return list
          .map((e) => MealieMealPlanEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch meal plan: $e');
      return [];
    }
  }

  /// Search recipes by keyword.
  Future<List<MealieRecipeSummary>> searchRecipes(String query) async {
    try {
      final response = await _dio.get('$_baseUrl/api/recipes', queryParameters: {
        'search': query,
        'perPage': 20,
      });
      final data = response.data as Map<String, dynamic>?;
      final items = data?['items'] as List<dynamic>? ?? [];
      return items
          .map((e) => MealieRecipeSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('Mealie', 'Search failed: $e');
      return [];
    }
  }

  /// Get full recipe details by slug.
  Future<MealieRecipe?> getRecipe(String slug) async {
    try {
      final response = await _dio.get('$_baseUrl/api/recipes/$slug');
      return MealieRecipe.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch recipe $slug: $e');
      return null;
    }
  }

  /// Get all recipe categories.
  Future<List<String>> getCategories() async {
    try {
      final response = await _dio.get('$_baseUrl/api/organizers/categories');
      final data = response.data as Map<String, dynamic>?;
      final items = data?['items'] as List<dynamic>? ?? [];
      return items
          .map((e) => (e as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch categories: $e');
      return [];
    }
  }

  /// Build the full image URL for a recipe.
  String imageUrl(String recipeId) =>
      '$_baseUrl/api/media/recipes/$recipeId/images/min-original.webp';
}

final mealieServiceProvider = Provider<MealieService?>((ref) {
  final config = ref.watch(hubConfigProvider);
  if (config.mealieUrl.isEmpty || config.mealieToken.isEmpty) return null;
  return MealieService(baseUrl: config.mealieUrl, token: config.mealieToken);
});
```

- [ ] **Step 2: Write tests**

Create `test/modules/mealie/mealie_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/modules/mealie/mealie_service.dart';

void main() {
  group('MealieService', () {
    test('imageUrl builds correct path', () {
      final service = MealieService(
        baseUrl: 'http://mealie.local:9925',
        token: 'test',
      );
      expect(
        service.imageUrl('abc-123'),
        'http://mealie.local:9925/api/media/recipes/abc-123/images/min-original.webp',
      );
    });

    test('imageUrl strips trailing slash from baseUrl', () {
      final service = MealieService(
        baseUrl: 'http://mealie.local:9925/',
        token: 'test',
      );
      expect(
        service.imageUrl('abc'),
        'http://mealie.local:9925/api/media/recipes/abc/images/min-original.webp',
      );
    });
  });
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/modules/mealie/ -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/modules/mealie/mealie_service.dart test/modules/mealie/mealie_service_test.dart
git commit -m "feat: add Mealie REST service with meal plan and recipe endpoints"
```

---

### Task 9: Mealie Screen (Browse + Recipe Detail)

**Files:**
- Create: `lib/modules/mealie/mealie_screen.dart`

- [ ] **Step 1: Create the Mealie screen**

Create `lib/modules/mealie/mealie_screen.dart` with two views managed by internal state:

**Browse view (default):**
- Today's meal plan section at top (horizontal list of meal cards)
- Search bar
- Category chips (horizontal scrollable)
- Search results grid

**Recipe detail view:**
- Back button → returns to browse
- Recipe image, title, times, servings
- Ingredients with checkboxes
- Numbered instruction steps in large text

The screen is a `ConsumerStatefulWidget` that tracks:
- `MealieRecipe? _selectedRecipe` — null = browse, non-null = detail view
- `List<MealieMealPlanEntry> _mealPlan`
- `List<MealieRecipeSummary> _searchResults`
- `String _searchQuery`
- `Set<int> _checkedIngredients` — for checkbox tracking in detail view

Follow the existing dark theme patterns: `Colors.black.withValues(alpha: 0.7)` background, `Color(0xFF646CFF)` accent, white text with alpha for subdued.

Use `CachedNetworkImage` for recipe images with the auth header passed via `httpHeaders: {'Authorization': 'Bearer $token'}`.

The screen should show "Configure Mealie in Settings" when the service is null (not configured).

This is the largest single file — implement it as a complete widget. Follow patterns from existing screens (cameras_screen.dart for the grid layout, settings_screen.dart for the list patterns).

- [ ] **Step 2: Run the app on desktop to verify**

Run: `flutter run -d windows`
Expected: The app launches. If Mealie module is enabled, its screen appears in the PageView. Without a configured Mealie server, it shows the "configure" message.

- [ ] **Step 3: Commit**

```bash
git add lib/modules/mealie/mealie_screen.dart
git commit -m "feat: add Mealie browse and recipe detail screen"
```

---

### Task 10: Mealie Module Wrapper and Settings

**Files:**
- Create: `lib/modules/mealie/mealie_module.dart`
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/services/local_api_server.dart`

- [ ] **Step 1: Create MealieModule**

Create `lib/modules/mealie/mealie_module.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../app/app.dart' show kDialogBackground;
import '../hearth_module.dart';
import 'mealie_screen.dart';

class MealieModule implements HearthModule {
  @override
  String get id => 'mealie';

  @override
  String get name => 'Recipes';

  @override
  IconData get icon => Icons.restaurant_menu;

  @override
  int get defaultOrder => 30;

  @override
  bool isConfigured(HubConfig config) =>
      config.mealieUrl.isNotEmpty && config.mealieToken.isNotEmpty;

  @override
  Widget buildScreen({required bool isActive}) => const MealieScreen();

  @override
  Widget? buildSettingsSection() => const _MealieSettings();
}

class _MealieSettings extends ConsumerWidget {
  const _MealieSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(hubConfigProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MEALIE', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.4),
          letterSpacing: 1.2,
        )),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.restaurant_menu, color: Colors.white54, size: 22),
          title: const Text('Mealie URL', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.mealieUrl.isEmpty ? 'Not configured' : config.mealieUrl,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => _showTextInput(context, ref, 'Mealie URL', config.mealieUrl,
              'http://192.168.1.x:9925', (v) => ref.read(hubConfigProvider.notifier)
                  .update((c) => c.copyWith(mealieUrl: v))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        ListTile(
          leading: const Icon(Icons.key, color: Colors.white54, size: 22),
          title: const Text('Mealie API Token', style: TextStyle(fontSize: 15)),
          subtitle: Text(
            config.mealieToken.isEmpty ? 'Not configured' : '\u2022' * 8,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => _showTextInput(context, ref, 'Mealie API Token', config.mealieToken,
              'Paste your Mealie API token', (v) => ref.read(hubConfigProvider.notifier)
                  .update((c) => c.copyWith(mealieToken: v)),
              obscure: true),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _showTextInput(BuildContext context, WidgetRef ref, String title,
      String current, String hint, ValueChanged<String> onSave,
      {bool obscure = false}) {
    final controller = TextEditingController(text: current);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogBackground,
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); onSave(controller.text); },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add Mealie fields to web portal**

In `lib/services/local_api_server.dart`:

Add `mealieUrl` and `mealieToken` to:
- The HTML form (new "Mealie" section with URL and token fields)
- The `textFields` JS array
- The `secretFields` JS array (for mealieToken)
- The `_handlePostConfig` method's copyWith call

Add `mealieToken` to the `secretFields` list in `_handleGetConfig` for redaction.

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Run: `flutter analyze`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add lib/modules/mealie/mealie_module.dart lib/screens/settings/settings_screen.dart lib/services/local_api_server.dart
git commit -m "feat: add Mealie module with settings and web portal config"
```

---

### Task 11: Update CLAUDE.md and Final Integration Test

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

Add a "Module System" section to CLAUDE.md explaining the architecture:

```markdown
### Module System

Optional screens implement `HearthModule` (in `lib/modules/hearth_module.dart`). Each module provides:
- An `id`, `name`, `icon`, and `defaultOrder` for the PageView
- `isConfigured(HubConfig)` to check if the module has the config it needs
- `buildScreen()` for the PageView widget
- `buildSettingsSection()` for the Settings screen (optional)

Modules live in `lib/modules/<name>/` with their screen, service, and data models.
The registry is a static list in `lib/modules/module_registry.dart`.
HubShell builds the PageView dynamically from enabled modules.

Current modules: Media (music), Controls (HA entities), Cameras (Frigate), Recipes (Mealie).
```

Update the screen order description to note it's now dynamic.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Run: `flutter analyze`
Expected: ALL PASS, no errors

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with module system architecture"
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin task/module-system-mealie
gh pr create --repo chrisuthe/Hearth-Home --title "feat: module system + Mealie recipe integration" --body "Adds a pluggable module system and Mealie recipe browsing.

## Module System
- HearthModule interface for optional screens
- Static module registry with enable/disable toggles in Settings
- Dynamic PageView built from enabled modules
- Existing screens (Media, Controls, Cameras) wrapped as modules and moved to lib/modules/

## Mealie Integration
- REST service for meal plans, recipe search, and full recipe details
- Browse view with today's meal plan, search, and categories
- Recipe detail view with ingredients (checkboxes) and step-by-step instructions
- Settings for Mealie URL and API token (kiosk + web portal)

## File Reorganization
- Optional screens moved from lib/screens/ to lib/modules/<name>/
- Frigate service moved to lib/modules/cameras/
- Core screens (Home, Settings, Setup, Timer, Ambient) stay in lib/screens/"
```
