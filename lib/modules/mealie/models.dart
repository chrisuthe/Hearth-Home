/// A recipe summary (from list/search endpoints).
class MealieRecipeSummary {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? image;
  final int? totalTime;
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
      rating: (json['rating'] as num?)?.round(),
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
  final String entryType;
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
