import '../widgets/app_toast.dart';
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
import '../widgets/barcode_scanner_sheet.dart';

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
  late int _selectedSegment;

  final _librarySearchController = TextEditingController();
  String _selectedFilterTag = 'all';

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

  String _formatAmount(double val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

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
    final localMatches = allFoods
        .where((f) => f.name.toLowerCase().contains(query) && f.source != 'composite')
        .toList();

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Amount of ${food.name}',
          style: const TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter weight used in grams:',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ingredientWeightController,
              onTap: () => _selectAll(_ingredientWeightController),
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
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
                    if (grams.isFinite && grams > 0) {
                      final density = food.baseUnit == 'ml' &&
                              food.density.isFinite && food.density > 0
                          ? food.density : 1.0;
                      final multiplier = grams / density /
                          (food.servingSizeG > 0 ? food.servingSizeG : 100.0);
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
      _showToast('Enter a recipe name', isError: true);
      return;
    }
    if (_recipeIngredients.isEmpty) {
      _showToast('Add an ingredient', isError: true);
      return;
    }
    final nutrients = [
      ..._aggregatedRecipeMacros.toMap().values,
      ..._aggregatedRecipeMicros.toMap().values,
    ];
    if (!_totalRecipeGrams.isFinite || _totalRecipeGrams <= 0 ||
        nutrients.any((value) => value is! num || !value.isFinite || value < 0)) {
      _showToast('Check recipe amounts', isError: true);
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
      _showToast('Updated');
    } else {
      final newId = await _firestoreService.addFood(recipeItem);
      if (triggerAi) {
        _handleRecipeAiEmoji(newId, name);
      }
      _showToast('Saved');
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _editingRecipeId = null;
      _recipeNameController.clear();
      _recipeUnitController.clear();
      _recipeEmoji = '🍽️';
      _recipeIngredients.clear();
      _selectedSegment = 0;
    });
  }

  Future<void> _confirmDeleteCurrentRecipe() async {
    if (_editingRecipeId == null) return;
    HapticFeedback.mediumImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Delete Recipe',
          style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove "${_recipeNameController.text.isNotEmpty ? _recipeNameController.text : 'this recipe'}" from your library? Past daily logs will remain intact.',
          style: const TextStyle(color: AppColors.textMuted),
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
                    elevation: 0,
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

    if (confirm == true && mounted) {
      await _firestoreService.deleteFood(_editingRecipeId!);
      HapticFeedback.mediumImpact();
      _showToast('Deleted');
      setState(() {
        _editingRecipeId = null;
        _recipeNameController.clear();
        _recipeUnitController.clear();
        _recipeEmoji = '🍽️';
        _recipeIngredients.clear();
        _selectedSegment = 0;
      });
    }
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
      _selectedSegment = 1;
    });
  }

  void _showToast(String message, {bool isError = false}) =>
      showAppToast(context, message, isError: isError);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _buildSegmentedHeader(),
            ),
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
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: TextField(
                        controller: _librarySearchController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: AppColors.textMain, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: 'Search saved library foods...',
                          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                          suffixIcon: _librarySearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                                  onPressed: () {
                                    _librarySearchController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    BarcodeScannerSheet.show(
                      context,
                      onFoodFound: (scannedFood, {bool isUnreliable = false}) {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (ctx) => EditFoodSheet(food: scannedFood),
                        );
                      },
                      onNotFound: (message) {
                        _showToast(message, isError: true);
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
    final badgeLabel = isComposite ? 'RECIPE' : food.source.toUpperCase();
    final badgeColor = isComposite
        ? const Color(0xFF9333EA)
        : (food.source == 'usda' ? AppColors.secondary : AppColors.primary);

    final int cVal = food.macros.calories.round();
    final String pVal = _formatAmount(food.macros.proteinG);
    final String cCarbVal = _formatAmount(food.macros.carbsG);
    final String fVal = _formatAmount(food.macros.fatG);
    final String basePortion =
        '${food.servingSizeG.round()}${food.baseUnit}${food.servingName.isNotEmpty ? ' (${food.servingName})' : ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 2),
              child: Text(
                food.emoji.isNotEmpty ? food.emoji : '🍽️',
                style: const TextStyle(fontSize: 28),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          food.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$cVal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMain,
                          ),
                        ),
                        TextSpan(
                          text: 'cal  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary.withValues(alpha: 0.95),
                          ),
                        ),
                        TextSpan(
                          text: pVal,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMain,
                          ),
                        ),
                        TextSpan(
                          text: 'p  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.protein.withValues(alpha: 0.95),
                          ),
                        ),
                        TextSpan(
                          text: cCarbVal,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMain,
                          ),
                        ),
                        TextSpan(
                          text: 'c  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.carbs.withValues(alpha: 0.95),
                          ),
                        ),
                        TextSpan(
                          text: fVal,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMain,
                          ),
                        ),
                        TextSpan(
                          text: 'f',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.fat.withValues(alpha: 0.95),
                          ),
                        ),
                        TextSpan(
                          text: ' • $basePortion',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    food.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: food.isFavorite ? const Color(0xFFFBBF24) : AppColors.textMuted,
                    size: 20,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _firestoreService.updateFood(food.id, {'is_favorite': !food.isFavorite});
                  },
                  tooltip: 'Favorite',
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, size: 21, color: AppColors.textMuted),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                  tooltip: 'Edit / Delete Item',
                ),
              ],
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
      child: const Column(
        children: [
          Icon(Icons.menu_book_rounded, size: 36, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'No Foods Found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
          ),
          SizedBox(height: 4),
          Text(
            'Save custom items while logging or build composite meals with the Recipe Composer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeComposerTab() {
    final totalMacros = _aggregatedRecipeMacros;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildRecipeIdentityCard(),
        const SizedBox(height: 14),
        _buildIngredientSearchCard(),
        const SizedBox(height: 14),
        _buildIngredientsListCard(),
        const SizedBox(height: 14),
        _buildRecipeTotalsCard(totalMacros),
        const SizedBox(height: 14),
        if (_editingRecipeId != null) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _confirmDeleteCurrentRecipe,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete Recipe', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saveRecipe,
                  child: const Text('Update Recipe'),
                ),
              ),
            ],
          ),
        ] else ...[
          ElevatedButton(
            onPressed: _saveRecipe,
            child: const Text('Save Recipe to Library'),
          ),
        ],
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
                  child: const Text(
                    'Cancel Edit',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
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
                  child: Text(_recipeEmoji, style: const TextStyle(fontSize: 28)),
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
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: TextField(
                      controller: _ingredientSearchController,
                      onChanged: _onIngredientSearchChanged,
                      style: const TextStyle(color: AppColors.textMain, fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: 'Search or scan ingredient...',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                        suffixIcon: _isSearchingIngredients
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                ),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  BarcodeScannerSheet.show(
                    context,
                    onFoodFound: (food, {bool isUnreliable = false}) {
                      _openIngredientWeightModal(food);
                    },
                    onNotFound: (message) {
                      _showToast(message, isError: true);
                    },
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ],
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
                          leading: Text(food.emoji, style: const TextStyle(fontSize: 20)),
                          title: Text(food.name, style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 13)),
                          trailing: Text('LIBRARY', style: TextStyle(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          onTap: () => _openIngredientWeightModal(food),
                        )),
                    ..._ingredientUsdaResults.map((usda) => ListTile(
                          dense: true,
                          leading: const Text('🍽️', style: TextStyle(fontSize: 20)),
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
              Text('${_recipeIngredients.length} added', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          if (_recipeIngredients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No ingredients added yet. Search or scan above to add items.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            )
          else
            ..._recipeIngredients.asMap().entries.map((entry) {
              final idx = entry.key;
              final ing = entry.value;

              final int cVal = ing.macros.calories.round();
              final String pVal = _formatAmount(ing.macros.proteinG);
              final String cCarbVal = _formatAmount(ing.macros.carbsG);
              final String fVal = _formatAmount(ing.macros.fatG);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Text(ing.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${ing.name} (${ing.quantityG.round()}g)',
                            style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '$cVal', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textMain)),
                                TextSpan(text: 'cal  ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary.withValues(alpha: 0.95))),
                                TextSpan(text: pVal, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textMain)),
                                TextSpan(text: 'p  ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.protein.withValues(alpha: 0.95))),
                                TextSpan(text: cCarbVal, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textMain)),
                                TextSpan(text: 'c  ', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.carbs.withValues(alpha: 0.95))),
                                TextSpan(text: fVal, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textMain)),
                                TextSpan(text: 'f', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.fat.withValues(alpha: 0.95))),
                              ],
                            ),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ],
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
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecipeTotalsCard(MacroNutrients macros) {
    final int cVal = macros.calories.round();
    final String pVal = _formatAmount(macros.proteinG);
    final String cCarbVal = _formatAmount(macros.carbsG);
    final String fVal = _formatAmount(macros.fatG);

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
                  const SizedBox(height: 2),
                  Text('Total Batch Yield: ${_totalRecipeGrams.round()}g', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMain)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$cVal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textMain)),
                      TextSpan(text: 'cal  ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary.withValues(alpha: 0.95))),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: pVal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                      TextSpan(text: 'p  ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.protein.withValues(alpha: 0.95))),
                      TextSpan(text: cCarbVal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                      TextSpan(text: 'c  ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.carbs.withValues(alpha: 0.95))),
                      TextSpan(text: fVal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                      TextSpan(text: 'f', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.fat.withValues(alpha: 0.95))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
