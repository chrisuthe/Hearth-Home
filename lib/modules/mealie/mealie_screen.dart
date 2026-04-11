import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/hub_config.dart';
import '../../app/app.dart' show kDialogBackground;
import 'mealie_service.dart';
import 'models.dart';

const _accent = Color(0xFF646CFF);

class MealieScreen extends ConsumerStatefulWidget {
  const MealieScreen({super.key});

  @override
  ConsumerState<MealieScreen> createState() => _MealieScreenState();
}

class _MealieScreenState extends ConsumerState<MealieScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  MealieRecipe? _selectedRecipe;
  List<MealieMealPlanEntry> _mealPlan = [];
  List<MealieRecipeSummary> _recipes = [];
  List<MealieRecipeSummary> _searchResults = [];
  List<MealieCategory> _categories = [];
  String? _activeCategory;
  bool _loading = false;
  final Set<int> _checkedIngredients = {};
  Timer? _searchDebounce;
  final _searchController = TextEditingController();

  List<MealieRecipeSummary> get _displayedRecipes =>
      _searchResults.isNotEmpty ? _searchResults : _recipes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final service = ref.read(mealieServiceProvider);
    if (service == null) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      service.getMealPlanToday(),
      service.getCategories(),
      service.getRecipes(),
    ]);
    if (mounted) {
      setState(() {
        _mealPlan = results[0] as List<MealieMealPlanEntry>;
        _categories = results[1] as List<MealieCategory>;
        _recipes = results[2] as List<MealieRecipeSummary>;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _activeCategory = null;
      });
      return;
    }
    setState(() => _activeCategory = null);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final service = ref.read(mealieServiceProvider);
      if (service == null) return;
      final results = await service.searchRecipes(query);
      if (mounted) {
        setState(() => _searchResults = results);
      }
    });
  }

  Future<void> _filterByCategory(MealieCategory? category) async {
    final service = ref.read(mealieServiceProvider);
    if (service == null) return;
    _searchController.clear();
    _searchDebounce?.cancel();
    setState(() {
      _activeCategory = category?.slug;
      _searchResults = [];
      _loading = true;
    });
    final results = category != null
        ? await service.getRecipes(categorySlug: category.slug)
        : await service.getRecipes();
    if (mounted) {
      setState(() {
        _recipes = results;
        _loading = false;
      });
    }
  }

  Future<void> _selectRecipe(String slug) async {
    final service = ref.read(mealieServiceProvider);
    if (service == null) return;
    setState(() => _loading = true);
    final recipe = await service.getRecipe(slug);
    if (mounted) {
      setState(() {
        _selectedRecipe = recipe;
        _checkedIngredients.clear();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final service = ref.watch(mealieServiceProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: service == null
          ? const Center(
              child: Text(
                'Configure Mealie in Settings',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white54,
                ),
              ),
            )
          : _selectedRecipe != null
              ? _buildRecipeDetail(service)
              : _buildBrowseView(service),
    );
  }

  // ---------------------------------------------------------------------------
  // Browse view
  // ---------------------------------------------------------------------------

  Widget _buildBrowseView(MealieService service) {
    final token = ref.read(hubConfigProvider).mealieToken;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Today's Menu
        if (_mealPlan.isNotEmpty) ...[
          Text(
            "Today's Menu",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _mealPlan.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = _mealPlan[index];
                final recipe = entry.recipe;
                if (recipe == null) return const SizedBox.shrink();
                return _buildMealPlanCard(entry, recipe, service, token);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Search bar
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            hintText: 'Search recipes...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            filled: true,
            fillColor: kDialogBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Category chips
        if (_categories.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isActive = _activeCategory == cat.slug;
                return FilterChip(
                  label: Text(cat.name),
                  selected: isActive,
                  onSelected: (selected) {
                    _filterByCategory(selected ? cat : null);
                  },
                  selectedColor: _accent,
                  backgroundColor: kDialogBackground,
                  labelStyle: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                  side: BorderSide.none,
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        // Loading indicator
        if (_loading)
          const Center(child: CircularProgressIndicator(color: _accent)),

        // Recipe grid (search results take priority, otherwise show all)
        if (_displayedRecipes.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _displayedRecipes.length,
            itemBuilder: (context, index) {
              final recipe = _displayedRecipes[index];
              return _buildRecipeCard(recipe, service, token);
            },
          ),
      ],
    );
  }

  Widget _buildMealPlanCard(
    MealieMealPlanEntry entry,
    MealieRecipeSummary recipe,
    MealieService service,
    String token,
  ) {
    return GestureDetector(
      onTap: () => _selectRecipe(recipe.slug),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: kDialogBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 90,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: service.imageUrl(recipe.id),
                httpHeaders: {'Authorization': 'Bearer $token'},
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.white10),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.white10,
                  child: const Icon(Icons.restaurant, color: Colors.white24, size: 32),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.entryType,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeCard(
    MealieRecipeSummary recipe,
    MealieService service,
    String token,
  ) {
    return GestureDetector(
      onTap: () => _selectRecipe(recipe.slug),
      child: Container(
        decoration: BoxDecoration(
          color: kDialogBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: service.imageUrl(recipe.id),
                  httpHeaders: {'Authorization': 'Bearer $token'},
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.white10),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.restaurant, color: Colors.white24, size: 32),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (recipe.totalTime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${recipe.totalTime} min',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recipe detail view
  // ---------------------------------------------------------------------------

  Widget _buildRecipeDetail(MealieService service) {
    final recipe = _selectedRecipe!;
    final token = ref.read(hubConfigProvider).mealieToken;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => setState(() => _selectedRecipe = null),
          ),
        ),
        const SizedBox(height: 8),

        // Recipe image header
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: service.imageUrl(recipe.id),
              httpHeaders: {'Authorization': 'Bearer $token'},
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.white10),
              errorWidget: (_, __, ___) => Container(
                color: Colors.white10,
                child: const Icon(Icons.restaurant, color: Colors.white24, size: 48),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          recipe.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
        ),
        const SizedBox(height: 12),

        // Info chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (recipe.prepTime != null)
              Chip(
                avatar: const Icon(Icons.timer_outlined, size: 16, color: Colors.white70),
                label: Text('Prep: ${recipe.prepTime} min'),
                backgroundColor: kDialogBackground,
                side: BorderSide.none,
                labelStyle: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            if (recipe.cookTime != null)
              Chip(
                avatar: const Icon(Icons.local_fire_department, size: 16, color: Colors.white70),
                label: Text('Cook: ${recipe.cookTime} min'),
                backgroundColor: kDialogBackground,
                side: BorderSide.none,
                labelStyle: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            if (recipe.recipeYield != null)
              Chip(
                avatar: const Icon(Icons.people_outline, size: 16, color: Colors.white70),
                label: Text(recipe.recipeYield!),
                backgroundColor: kDialogBackground,
                side: BorderSide.none,
                labelStyle: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Ingredients
        if (recipe.ingredients.isNotEmpty) ...[
          Text(
            'Ingredients',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(recipe.ingredients.length, (index) {
            final ingredient = recipe.ingredients[index];
            return CheckboxListTile(
              value: _checkedIngredients.contains(index),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _checkedIngredients.add(index);
                  } else {
                    _checkedIngredients.remove(index);
                  }
                });
              },
              title: Text(
                ingredient.display,
                style: TextStyle(
                  fontSize: 15,
                  decoration: _checkedIngredients.contains(index)
                      ? TextDecoration.lineThrough
                      : null,
                  color: _checkedIngredients.contains(index)
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.white,
                ),
              ),
              activeColor: _accent,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            );
          }),
          const SizedBox(height: 24),
        ],

        // Instructions
        if (recipe.instructions.isNotEmpty) ...[
          Text(
            'Instructions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(recipe.instructions.length, (index) {
            final step = recipe.instructions[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: kDialogBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.text,
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
