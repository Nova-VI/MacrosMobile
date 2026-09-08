import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/food_item.dart';
import '../models/nutrition.dart';
import '../services/firestore_service.dart';
import '../services/usda_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../widgets/edit_food_sheet.dart';
import '../widgets/recipe_nutrition_sheet.dart';
import '../widgets/emoji_picker_sheet.dart';

class RecipesLibraryScreen extends StatefulWidget {
  final int initialTabIndex;

  const RecipesLibraryScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<RecipesLibraryScreen> createState() => _RecipesLibraryScreenState();
}

class _RecipesLibraryScreenState extends State<RecipesLibraryScreen> {
  late int _selectedSegment; // 0 = Food Library, 1 = Recipe Composer

  // Library State
  final _librarySearchController = TextEditingController();
  String _selectedFilterTag = 'all'; // 'all', 'favorites', 'custom', 'usda', 'composite'

  // Recipe Composer State
  final _recipeNameController = TextEditingController();
  final _recipeUnitController = TextEditingController();
  final _ingredientSearchController = TextEditingController();
  final _ingredientWeightController = TextEditingController(text: '100');

  String _recipeEmoji = '🍽️';
  String? _editingRecipeId;
  final List<RecipeIngredient> _recipeIngredients = [];

  final UsdaService _usdaService = UsdaService();
  final FirestoreService _firestoreService = FirestoreService();

  Timer? _debounceTimer;
  List<FoodItem> _ingredientLocalResults = [];
  List<Map<String, dynamic>> _ingredientUsdaResults = [];
  bool _isSearchingIngredients = false;

  @override
  void initState() {
    super.initState();
    _selectedSegment = widget.initialTabIndex;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _librarySearchController.dispose();
    _recipeNameController.dispose();
    _recipeUnitController.dispose();
    _ingredientSearchController.dispose();
    _ingredientWeightController.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController ctrl) {
    Future.delayed(Duration.zero, () {
      if (ctrl.text.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
  }

  // --- Recipe Math Rollup ---
  double get _totalRecipeGrams => _recipeIngredients.fold(0.0, (acc, i) => acc + i.quantityG);

  MacroNutrients get _aggregatedRecipeMacros {
    double cals = 0, pro = 0, carb = 0, fat = 0;
    for (final i in _recipeIngredients) {
      cals += i.macros.calories;
      pro += i.macros.proteinG;
      carb += i.macros.carbsG;
      fat += i.macros.fatG;
    }
    return MacroNutrients(calories: cals, proteinG: pro, carbsG: carb, fatG: fat);
  }

  MicroNutrients get _aggregatedRecipeMicros {
    double fiber = 0, sugar = 0, sodium = 0, satFat = 0, chol = 0, pot = 0;
    double vitA = 0, vitC = 0, vitD = 0, calcium = 0, iron = 0;

    for (final i in _recipeIngredients) {
      fiber += i.micros.fiberG;
      sugar += i.micros.sugarG;
      sodium += i.micros.sodiumMg;
      satFat += i.micros.saturatedFatG;
      chol += i.micros.cholesterolMg;
      pot += i.micros.potassiumMg;
      vitA += i.micros.vitaminAUg;
      vitC += i.micros.vitaminCMg;
      vitD += i.micros.vitaminDUg;
      calcium += i.micros.calciumMg;
      iron += i.micros.ironMg;
    }

    return MicroNutrients(
      fiberG: fiber,
      sugarG: sugar,
      sodiumMg: sodium,
      saturatedFatG: satFat,
      cholesterolMg: chol,
      potassiumMg: pot,
      vitaminAUg: vitA,
      vitaminCMg: vitC,
      vitaminDUg: vitD,
      calciumMg: calcium,
      ironMg: iron,
    );
  }

  // --- Ingredient Search for Recipe Composer ---
  void _onIngredientSearchChanged(String q) {
    _debounceTimer?.cancel();
    final query = q.trim().toLowerCase();

    if (query.length < 2) {
      setState(() {
        _ingredientLocalResults = [];
        _ingredientUsdaResults = [];
        _isSearchingIngredients = false;
      });
      return;
    }

    final allFoods = _firestoreService.foodsNotifier.value;
    final localMatches = allFoods.where((f) => f.name.toLowerCase().contains(query) && f.source != 'composite').toList();

    setState(() {
      _ingredientLocalResults = localMatches;
      _isSearchingIngredients = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 380), () async {
      final usdaMatches = await _usdaService.searchFoods(query);
      if (mounted && _ingredientSearchController.text.trim().toLowerCase() == query) {
        setState(() {
          _ingredientUsdaResults = usdaMatches;
          _isSearchingIngredients = false;
        });
      }
    });
  }

  void _openIngredientWeightModal(FoodItem food) {
    _ingredientWeightController.text = '100';
    _ingredientSearchController.clear();
    setState(() {
      _ingredientLocalResults.clear();
      _ingredientUsdaResults.clear();
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppColors.border)),
        title: Text('Amount of ${food.name}', style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter weight used in grams:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _ingredientWeightController,
              onTap: () => _selectAll(_ingredientWeightController),
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 16),
              decoration: const InputDecoration(labelText: 'Weight (g)'),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textMain,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final grams = double.tryParse(_ingredientWeightController.text) ?? 100.0;
                    if (grams > 0) {
                      final multiplier = grams / (food.servingSizeG > 0 ? food.servingSizeG : 100.0);
                      setState(() {
                        _recipeIngredients.add(RecipeIngredient(
                          foodId: food.id.isNotEmpty ? food.id : null,
                          usdaFdcId: food.usdaFdcId,
                          name: food.name,
                          emoji: food.emoji,
                          quantityG: grams,
                          source: food.source,
                          macros: food.macros.scale(multiplier),
                          micros: food.micros.scale(multiplier),
                        ));
                      });
                      HapticFeedback.selectionClick();
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecipe() async {
    final name = _recipeNameController.text.trim();
    if (name.isEmpty) {
      _showToast('Please enter a recipe name.', isError: true);
      return;
    }
    if (_recipeIngredients.isEmpty) {
      _showToast('Please add at least one ingredient.', isError: true);
      return;
    }

    String finalEmoji = _recipeEmoji;
    bool triggerAi = (finalEmoji == '🍽️');

    final recipeItem = FoodItem(
      id: _editingRecipeId ?? '',
      name: name,
      source: 'composite',
      servingSizeG: _totalRecipeGrams,
      baseUnit: 'g',
      servingName: _recipeUnitController.text.trim(),
      emoji: finalEmoji,
      macros: _aggregatedRecipeMacros,
      micros: _aggregatedRecipeMicros,
      ingredients: _recipeIngredients,
    );

    if (_editingRecipeId != null) {
      await _firestoreService.updateFood(_editingRecipeId!, recipeItem.toMap());
      _showToast('Recipe "$name" updated!');
    } else {
      final newId = await _firestoreService.addFood(recipeItem);
      if (triggerAi) {
        _handleRecipeAiEmoji(newId, name);
      }
      _showToast('Recipe "$name" saved to library!');
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _editingRecipeId = null;
      _recipeNameController.clear();
      _recipeUnitController.clear();
      _recipeEmoji = '🍽️';
      _recipeIngredients.clear();
      _selectedSegment = 0; // Switch to Library to see the saved recipe
    });
  }

  void _handleRecipeAiEmoji(String foodId, String name) async {
    final aiEmoji = await GeminiService.fetchFoodEmoji(name);
    if (aiEmoji.isNotEmpty && aiEmoji != '🍽️') {
      _firestoreService.updateFood(foodId, {'emoji': aiEmoji});
    }
  }

  void _editCompositeRecipe(FoodItem recipe) {
    setState(() {
      _editingRecipeId = recipe.id;
      _recipeNameController.text = recipe.name;
      _recipeUnitController.text = recipe.servingName;
      _recipeEmoji = recipe.emoji.isNotEmpty ? recipe.emoji : '🍽️';
      _recipeIngredients.clear();
      _recipeIngredients.addAll(recipe.ingredients);
      _selectedSegment = 1; // Switch to Recipe Composer
    });
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: isError ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isError ? AppColors.danger : AppColors.primary),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Segmented Switcher Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _buildSegmentedHeader(),
            ),

            // Tab Content
            Expanded(
              child: _selectedSegment == 0 ? _buildLibraryTab() : _buildRecipeComposerTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedHeader() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton('Food Library', 0, Icons.menu_book_rounded),
          ),
          Expanded(
            child: _buildSegmentButton('Recipe Composer', 1, Icons.soup_kitchen_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String label, int index, IconData icon) {
    final isSelected = _selectedSegment == index;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedSegment = index);
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 1: FOOD LIBRARY ====================
  Widget _buildLibraryTab() {
    return ValueListenableBuilder<List<FoodItem>>(
      valueListenable: _firestoreService.foodsNotifier,
      builder: (context, allFoods, _) {
        final query = _librarySearchController.text.trim().toLowerCase();
        var filtered = allFoods.where((f) {
          if (query.isNotEmpty && !f.name.toLowerCase().contains(query)) return false;
          if (_selectedFilterTag == 'favorites' && !f.isFavorite) return false;
          if (_selectedFilterTag == 'custom' && f.source != 'custom') return false;
          if (_selectedFilterTag == 'usda' && f.source != 'usda' && f.source != 'usda_modified') return false;
          if (_selectedFilterTag == 'composite' && f.source != 'composite') return false;
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          physics: const BouncingScrollPhysics(),
          children: [
            // Search Input
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _librarySearchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.textMain),
                decoration: InputDecoration(
                  hintText: 'Search saved library foods...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                  suffixIcon: _librarySearchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                          onPressed: () {
                            _librarySearchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Filter Chips Row
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildFilterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('★ Favorites', 'favorites'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Custom', 'custom'),
                  const SizedBox(width: 8),
                  _buildFilterChip('USDA', 'usda'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Recipes', 'composite'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Food List Items
            if (filtered.isEmpty)
              _buildEmptyLibraryState()
            else
              ...filtered.map((food) => _buildLibraryItemCard(food)),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String tag) {
    final isSelected = _selectedFilterTag == tag;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilterTag = tag);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItemCard(FoodItem food) {
    final isComposite = food.source == 'composite';
    final badgeLabel = isComposite ? 'Recipe' : food.source.toUpperCase();
    final badgeColor = isComposite ? const Color(0xFF9333EA) : (food.source == 'usda' ? AppColors.secondary : AppColors.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Favorite Star, Emoji, Title, Badge & Edit/Delete Actions
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    food.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: food.isFavorite ? const Color(0xFFFBBF24) : AppColors.textMuted,
                    size: 22,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _firestoreService.updateFood(food.id, {'is_favorite': !food.isFavorite});
                  },
                  tooltip: 'Toggle Favorite',
                ),
                const SizedBox(width: 4),
                Text(food.emoji.isNotEmpty ? food.emoji : '🍽️', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textMain, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Base: ${food.servingSizeG.round()}${food.baseUnit} ${food.servingName.isNotEmpty ? '(${food.servingName})' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: badgeColor),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.textMuted),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    if (isComposite) {
                      _editCompositeRecipe(food);
                    } else {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (ctx) => EditFoodSheet(food: food),
                      );
                    }
                  },
                  tooltip: 'Edit Item',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _confirmDeleteFood(food),
                  tooltip: 'Delete Food',
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 4 Compact Metric Capsules
            Row(
              children: [
                _buildCompactCapsule('Calories', '${food.macros.calories.round()}', color: AppColors.primary),
                const SizedBox(width: 6),
                _buildCompactCapsule('Protein', '${food.macros.proteinG.toStringAsFixed(1)}g', color: AppColors.primary),
                const SizedBox(width: 6),
                _buildCompactCapsule('Carbs', '${food.macros.carbsG.toStringAsFixed(1)}g', color: AppColors.secondary),
                const SizedBox(width: 6),
                _buildCompactCapsule('Fat', '${food.macros.fatG.toStringAsFixed(1)}g', color: AppColors.warning),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCapsule(String label, String value, {required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4.5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLibraryState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.menu_book_rounded, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('No Foods Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain)),
          const SizedBox(height: 4),
          const Text('Save custom items while logging or build composite meals with the Recipe Composer.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
        ],
      ),
    );
  }

  void _confirmDeleteFood(FoodItem food) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
        title: const Text('Delete Food', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800)),
        content: Text('Remove "${food.name}" from your library? Past daily logs will remain intact.', style: const TextStyle(color: AppColors.textMuted)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textMain,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deleteFood(food.id);
      _showToast('"${food.name}" removed from library.');
    }
  }

  // ==================== TAB 2: RECIPE COMPOSER ====================
  Widget _buildRecipeComposerTab() {
    final totalMacros = _aggregatedRecipeMacros;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        // Island 1: Recipe Identity Card
        _buildRecipeIdentityCard(),
        const SizedBox(height: 14),

        // Island 2: Ingredient Search & Autocomplete
        _buildIngredientSearchCard(),
        const SizedBox(height: 14),

        // Island 3: Ingredients List
        _buildIngredientsListCard(),
        const SizedBox(height: 14),

        // Island 4: Aggregated Total Nutrition Card
        _buildRecipeTotalsCard(totalMacros),
        const SizedBox(height: 14),

        // Save Recipe Button
        ElevatedButton(
          onPressed: _saveRecipe,
          child: Text(_editingRecipeId != null ? 'Update Recipe in Library' : 'Save Recipe to Library'),
        ),
      ],
    );
  }

  Widget _buildRecipeIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _editingRecipeId != null ? 'Edit Composite Recipe' : 'New Recipe',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
              if (_editingRecipeId != null)
                InkWell(
                  onTap: () {
                    setState(() {
                      _editingRecipeId = null;
                      _recipeNameController.clear();
                      _recipeUnitController.clear();
                      _recipeEmoji = '🍽️';
                      _recipeIngredients.clear();
                    });
                  },
                  child: const Text('Cancel Edit', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (ctx) => EmojiPickerSheet(
                      onEmojiSelected: (emoji) => setState(() => _recipeEmoji = emoji),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(_recipeEmoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _recipeNameController,
                  style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 16),
                  decoration: const InputDecoration(labelText: 'Recipe Name', hintText: 'e.g. Protein Pancakes'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _recipeUnitController,
            onTap: () => _selectAll(_recipeUnitController),
            style: const TextStyle(color: AppColors.textMain),
            decoration: const InputDecoration(
              labelText: 'Portion Unit Name (optional)',
              hintText: 'e.g. portion, bowl, slice',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientSearchCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ADD INGREDIENTS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ingredientSearchController,
            onChanged: _onIngredientSearchChanged,
            style: const TextStyle(color: AppColors.textMain),
            decoration: InputDecoration(
              hintText: 'Search ingredient from library or USDA...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: _isSearchingIngredients
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    )
                  : null,
            ),
          ),
          if (_ingredientLocalResults.isNotEmpty || _ingredientUsdaResults.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    ..._ingredientLocalResults.map((food) => ListTile(
                          dense: true,
                          leading: Text(food.emoji, style: const TextStyle(fontSize: 18)),
                          title: Text(food.name, style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 13)),
                          trailing: const Text('LIBRARY', style: TextStyle(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          onTap: () => _openIngredientWeightModal(food),
                        )),
                    ..._ingredientUsdaResults.map((usda) => ListTile(
                          dense: true,
                          leading: const Text('🍽️', style: TextStyle(fontSize: 18)),
                          title: Text(usda['description'], style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 13)),
                          trailing: const Text('USDA', style: TextStyle(color: AppColors.secondary, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          onTap: () async {
                            final details = await _usdaService.getFoodDetails(usda['fdcId']);
                            if (details != null) _openIngredientWeightModal(details);
                          },
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIngredientsListCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('INGREDIENTS LIST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
              Text('${_recipeIngredients.length} added', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),

          if (_recipeIngredients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No ingredients added yet. Search above to add items.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ),
            )
          else
            ..._recipeIngredients.asMap().entries.map((entry) {
              final idx = entry.key;
              final ing = entry.value;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(ing.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${ing.name} (${ing.quantityG.round()}g)',
                            style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.danger),
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _recipeIngredients.removeAt(idx));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('${ing.macros.calories.round()} kcal', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                        Text('P: ${ing.macros.proteinG.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                        Text('C: ${ing.macros.carbsG.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                        Text('F: ${ing.macros.fatG.toStringAsFixed(1)}g', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecipeTotalsCard(MacroNutrients macros) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RECIPE TOTAL NUTRITION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5)),
                  Text('Total Batch Weight: ${_totalRecipeGrams.round()}g', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                ],
              ),
              TextButton(
                onPressed: _recipeIngredients.isEmpty
                    ? null
                    : () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (ctx) => RecipeNutritionSheet(
                            macros: macros,
                            micros: _aggregatedRecipeMicros,
                            totalGrams: _totalRecipeGrams,
                          ),
                        );
                      },
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Full Facts ▾', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCompactCapsule('Calories', '${macros.calories.round()}', color: AppColors.primary),
              const SizedBox(width: 6),
              _buildCompactCapsule('Protein', '${macros.proteinG.toStringAsFixed(1)}g', color: AppColors.primary),
              const SizedBox(width: 6),
              _buildCompactCapsule('Carbs', '${macros.carbsG.toStringAsFixed(1)}g', color: AppColors.secondary),
              const SizedBox(width: 6),
              _buildCompactCapsule('Fat', '${macros.fatG.toStringAsFixed(1)}g', color: AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }
}