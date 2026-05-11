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
      expect(entry.title, isNull);
      expect(entry.hasContent, isFalse);
      expect(entry.displayName, isEmpty);
    });

    test('parses custom title entry (no linked recipe)', () {
      // What Mealie actually returns for a typed-in meal plan entry —
      // recipe is null, title carries the text.
      final json = {
        'date': '2026-05-11',
        'entryType': 'lunch',
        'title': 'BBQ Meatballs',
        'text': '',
        'recipeId': null,
        'recipe': null,
      };
      final entry = MealieMealPlanEntry.fromJson(json);
      expect(entry.entryType, 'lunch');
      expect(entry.title, 'BBQ Meatballs');
      expect(entry.recipe, isNull);
      expect(entry.hasContent, isTrue);
      expect(entry.displayName, 'BBQ Meatballs');
    });

    test('linked recipe takes precedence over title for displayName', () {
      final json = {
        'entryType': 'dinner',
        'title': 'fallback title',
        'recipe': {'id': '1', 'slug': 'steak', 'name': 'Steak'},
      };
      final entry = MealieMealPlanEntry.fromJson(json);
      expect(entry.displayName, 'Steak');
      expect(entry.hasContent, isTrue);
    });

    test('empty title string parses as null', () {
      final json = {'entryType': 'breakfast', 'title': '', 'text': ''};
      final entry = MealieMealPlanEntry.fromJson(json);
      expect(entry.title, isNull);
      expect(entry.text, isNull);
      expect(entry.hasContent, isFalse);
    });
  });
}
