import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/modules/mealie/mealie_service.dart';
import 'package:hearth/modules/mealie/models.dart';

import 'module_support.dart';
import 'portrait_harness.dart';

const _longTitle =
    'Slow-Roasted Heirloom Tomato, White Bean and Rosemary Soup with Garlic '
    'Sourdough Croutons';

MealieRecipeSummary _summary(int i) => MealieRecipeSummary(
      id: 'r$i',
      slug: 'recipe-$i',
      name: i == 1 ? _longTitle : 'Recipe $i',
      totalTime: i.isEven ? 25 + i : null,
    );

/// Serves canned data; the Dio client it inherits is never used.
class _CannedMealie extends MealieService {
  _CannedMealie() : super(baseUrl: 'http://mealie.invalid', token: 't');

  @override
  Future<List<MealieMealPlanEntry>> getMealPlanToday() async => [
        MealieMealPlanEntry(entryType: 'breakfast', recipe: _summary(0)),
        MealieMealPlanEntry(entryType: 'lunch', recipe: _summary(1)),
        const MealieMealPlanEntry(
            entryType: 'dinner', title: 'Leftovers from the weekend roast'),
        MealieMealPlanEntry(entryType: 'side', recipe: _summary(3)),
        MealieMealPlanEntry(entryType: 'dessert', recipe: _summary(4)),
        MealieMealPlanEntry(entryType: 'snack', recipe: _summary(5)),
        MealieMealPlanEntry(entryType: 'drink', recipe: _summary(6)),
      ];

  @override
  Future<List<MealieCategory>> getCategories() async => [
        for (final n in [
          'Breakfast',
          'Weeknight Dinners Under Thirty Minutes',
          'Soup',
          'Baking',
          'Vegetarian',
          'Slow Cooker',
          'Desserts',
          'Holiday',
          'Grilling',
          'Kid Friendly',
        ])
          MealieCategory(name: n, slug: n.toLowerCase().replaceAll(' ', '-')),
      ];

  @override
  Future<List<MealieRecipeSummary>> getRecipes({String? categorySlug}) async =>
      [for (var i = 0; i < 24; i++) _summary(i)];

  @override
  Future<List<MealieRecipeSummary>> searchRecipes(String query) async =>
      [for (var i = 0; i < 5; i++) _summary(i)];

  @override
  Future<MealieRecipe?> getRecipe(String slug) async => MealieRecipe(
        id: 'r1',
        slug: slug,
        name: _longTitle,
        prepTime: 20,
        cookTime: 95,
        totalTime: 115,
        recipeYield: '6 generous servings, or 8 as a starter',
        ingredients: [
          for (var i = 0; i < 20; i++)
            MealieIngredient(
              display: i.isEven
                  ? '${i + 1} tbsp extra-virgin olive oil, plus more for '
                      'drizzling over the finished bowls just before serving'
                  : '${i + 1} cloves garlic',
            ),
        ],
        instructions: [
          for (var i = 0; i < 10; i++)
            const MealieInstruction(
              text: 'Heat the oven to 150°C. Halve the tomatoes, toss them '
                  'with the oil, rosemary and a generous pinch of salt, then '
                  'spread cut-side up on two lined trays and roast for ninety '
                  'minutes, turning the trays once, until collapsed and '
                  'caramelised at the edges but not dried out.',
            ),
        ],
      );
}

void main() {
  final screen = staticModule('mealie').buildScreen(isActive: true);
  const config =
      HubConfig(mealieUrl: 'http://mealie.invalid', mealieToken: 't');

  testLayouts('recipes before Mealie is configured', (tester, canvas) async {
    await pumpModule(tester, screen);
    expect(find.text('Recipes not configured'), findsOneWidget);
  });

  testLayouts('recipe browse view with a meal plan and 24 recipes',
      (tester, canvas) async {
    await pumpModule(tester, screen, config: config, overrides: [
      mealieServiceProvider.overrideWith((ref) => _CannedMealie()),
    ]);
    expect(find.text("Today's Menu"), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Recipe 20'), 400,
        scrollable: find.byType(Scrollable).first);
  },
      // Recipe cards start a network image load whose cache hits path_provider
      // mid-pump, so the first run in a process throws.
      goldens: false);

  testLayouts('recipe detail with 20 ingredients and 10 steps',
      (tester, canvas) async {
    await pumpModule(tester, screen, config: config, overrides: [
      mealieServiceProvider.overrideWith((ref) => _CannedMealie()),
    ]);
    await tester.tap(find.text('Recipe 0').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Instructions'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('10'), 400,
        scrollable: find.byType(Scrollable).first);
  });
}
