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

  Future<MealieRecipe?> getRecipe(String slug) async {
    try {
      final response = await _dio.get('$_baseUrl/api/recipes/$slug');
      return MealieRecipe.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch recipe $slug: $e');
      return null;
    }
  }

  Future<List<MealieRecipeSummary>> getRecipes({String? categorySlug}) async {
    try {
      final params = <String, dynamic>{'perPage': 30};
      if (categorySlug != null) {
        params['categories'] = categorySlug;
      }
      final response =
          await _dio.get('$_baseUrl/api/recipes', queryParameters: params);
      final data = response.data as Map<String, dynamic>?;
      final items = data?['items'] as List<dynamic>? ?? [];
      return items
          .map((e) => MealieRecipeSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch recipes: $e');
      return [];
    }
  }

  Future<List<MealieCategory>> getCategories() async {
    try {
      final response = await _dio.get('$_baseUrl/api/organizers/categories');
      final data = response.data as Map<String, dynamic>?;
      final items = data?['items'] as List<dynamic>? ?? [];
      return items
          .map((e) =>
              MealieCategory.fromJson(e as Map<String, dynamic>))
          .where((cat) => cat.name.isNotEmpty)
          .toList();
    } catch (e) {
      Log.e('Mealie', 'Failed to fetch categories: $e');
      return [];
    }
  }

  String imageUrl(String recipeId) =>
      '$_baseUrl/api/media/recipes/$recipeId/images/min-original.webp';
}

final mealieServiceProvider = Provider<MealieService?>((ref) {
  final config = ref.watch(hubConfigProvider);
  if (config.mealieUrl.isEmpty || config.mealieToken.isEmpty) return null;
  return MealieService(baseUrl: config.mealieUrl, token: config.mealieToken);
});
