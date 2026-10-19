import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/food_item.dart';
import '../models/nutrition.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/nutrition_validation.dart';
import 'emoji_picker_sheet.dart';

class EditFoodSheet extends StatefulWidget {
  final FoodItem food;

  const EditFoodSheet({
    super.key,
    required this.food,
  });

  @override
  State<EditFoodSheet> createState() => _EditFoodSheetState();
}

class _EditFoodSheetState extends State<EditFoodSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _servingGController;
  late final TextEditingController _servingUnitController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _densityController;

  late final TextEditingController _fiberController;
  late final TextEditingController _sugarController;
  late final TextEditingController _sodiumController;
  late final TextEditingController _satFatController;
  late final TextEditingController _cholesterolController;
  late final TextEditingController _potassiumController;
  late final TextEditingController _vitAController;
  late final TextEditingController _vitCController;
  late final TextEditingController _vitDController;
  late final TextEditingController _calciumController;
  late final TextEditingController _ironController;

  late String _selectedEmoji;
  late String _selectedBaseUnit;
  bool _isManualCalories = false;
  bool _isMicrosExpanded = false;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _selectedEmoji = f.emoji.isNotEmpty ? f.emoji : '🍽️';
    _selectedBaseUnit = f.baseUnit;

    _nameController = TextEditingController(text: f.name);
    _servingGController = TextEditingController(
      text: (f.servingSizeG % 1 == 0)
          ? f.servingSizeG.toInt().toString()
          : f.servingSizeG.toStringAsFixed(1),
    );
    _servingUnitController = TextEditingController(text: f.servingName);
    _proteinController = TextEditingController(
      text: f.macros.proteinG > 0 ? f.macros.proteinG.toStringAsFixed(1) : '',
    );
    _carbsController = TextEditingController(
      text: f.macros.carbsG > 0 ? f.macros.carbsG.toStringAsFixed(1) : '',
    );
    _fatController = TextEditingController(
      text: f.macros.fatG > 0 ? f.macros.fatG.toStringAsFixed(1) : '',
    );
    _caloriesController = TextEditingController(
      text: f.macros.calories > 0 ? f.macros.calories.round().toString() : '',
    );
    _densityController = TextEditingController(text: f.density.toStringAsFixed(2));

    final m = f.micros;
    _fiberController = TextEditingController(text: m.fiberG > 0 ? m.fiberG.toStringAsFixed(1) : '');
    _sugarController = TextEditingController(text: m.sugarG > 0 ? m.sugarG.toStringAsFixed(1) : '');
    _sodiumController = TextEditingController(text: m.sodiumMg > 0 ? m.sodiumMg.round().toString() : '');
    _satFatController = TextEditingController(text: m.saturatedFatG > 0 ? m.saturatedFatG.toStringAsFixed(1) : '');
    _cholesterolController = TextEditingController(text: m.cholesterolMg > 0 ? m.cholesterolMg.round().toString() : '');
    _potassiumController = TextEditingController(text: m.potassiumMg > 0 ? m.potassiumMg.round().toString() : '');
    _vitAController = TextEditingController(text: m.vitaminAUg > 0 ? m.vitaminAUg.round().toString() : '');
    _vitCController = TextEditingController(text: m.vitaminCMg > 0 ? m.vitaminCMg.toStringAsFixed(1) : '');
    _vitDController = TextEditingController(text: m.vitaminDUg > 0 ? m.vitaminDUg.toStringAsFixed(1) : '');
    _calciumController = TextEditingController(text: m.calciumMg > 0 ? m.calciumMg.round().toString() : '');
    _ironController = TextEditingController(text: m.ironMg > 0 ? m.ironMg.toStringAsFixed(1) : '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _servingGController.dispose();
    _servingUnitController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _caloriesController.dispose();
    _densityController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    _satFatController.dispose();
    _cholesterolController.dispose();
    _potassiumController.dispose();
    _vitAController.dispose();
    _vitCController.dispose();
    _vitDController.dispose();
    _calciumController.dispose();
    _ironController.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController ctrl) {
    Future.delayed(Duration.zero, () {
      if (ctrl.text.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
  }

  void _onMacroChanged() {
    if (!_isManualCalories) {
      final p = double.tryParse(_proteinController.text) ?? 0.0;
      final c = double.tryParse(_carbsController.text) ?? 0.0;
      final f = double.tryParse(_fatController.text) ?? 0.0;
      final calculatedCalories = (p * 4.0) + (c * 4.0) + (f * 9.0);
      _caloriesController.text = calculatedCalories > 0 ? calculatedCalories.round().toString() : '';
    }
  }

  void _openEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => EmojiPickerSheet(
        onEmojiSelected: (emoji) => setState(() => _selectedEmoji = emoji),
      ),
    );
  }

  void _confirmDeleteFood() {
    HapticFeedback.mediumImpact();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Delete Food',
          style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove "${widget.food.name}" from your library? Past daily logs will remain intact.',
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
                  onPressed: () async {
                    Navigator.pop(ctx, true);
                    try {
                      await FirestoreService().deleteFood(widget.food.id);
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not delete food: $error')),
                        );
                      }
                      return;
                    }
                    if (!mounted) return;
                    Navigator.pop(context);
                    HapticFeedback.mediumImpact();
                  },
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final validationError = validateNutritionValues(
      positive: {'base serving size': _servingGController.text, 'density': _densityController.text},
      nonnegative: {
        'Protein': _proteinController.text, 'Carbs': _carbsController.text,
        'Fat': _fatController.text, 'Calories': _caloriesController.text,
        'Fiber': _fiberController.text, 'Sugar': _sugarController.text,
        'Sodium': _sodiumController.text, 'Saturated fat': _satFatController.text,
        'Cholesterol': _cholesterolController.text, 'Potassium': _potassiumController.text,
        'Vitamin A': _vitAController.text, 'Vitamin C': _vitCController.text,
        'Vitamin D': _vitDController.text, 'Calcium': _calciumController.text,
        'Iron': _ironController.text,
      },
    );
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    final p = double.tryParse(_proteinController.text) ?? 0.0;
    final c = double.tryParse(_carbsController.text) ?? 0.0;
    final f = double.tryParse(_fatController.text) ?? 0.0;
    final cal = double.tryParse(_caloriesController.text) ?? ((p * 4.0) + (c * 4.0) + (f * 9.0));

    final updatedItem = FoodItem(
      id: widget.food.id,
      name: name,
      source: widget.food.source,
      usdaFdcId: widget.food.usdaFdcId,
      servingSizeG: double.tryParse(_servingGController.text) ?? 100.0,
      baseUnit: _selectedBaseUnit,
      servingName: _servingUnitController.text.trim(),
      emoji: _selectedEmoji,
      isFavorite: widget.food.isFavorite,
      density: double.tryParse(_densityController.text) ?? 1.0,
      macros: MacroNutrients(
        proteinG: p,
        carbsG: c,
        fatG: f,
        calories: cal,
      ),
      micros: MicroNutrients(
        fiberG: double.tryParse(_fiberController.text) ?? 0.0,
        sugarG: double.tryParse(_sugarController.text) ?? 0.0,
        sodiumMg: double.tryParse(_sodiumController.text) ?? 0.0,
        saturatedFatG: double.tryParse(_satFatController.text) ?? 0.0,
        cholesterolMg: double.tryParse(_cholesterolController.text) ?? 0.0,
        potassiumMg: double.tryParse(_potassiumController.text) ?? 0.0,
        vitaminAUg: double.tryParse(_vitAController.text) ?? 0.0,
        vitaminCMg: double.tryParse(_vitCController.text) ?? 0.0,
        vitaminDUg: double.tryParse(_vitDController.text) ?? 0.0,
        calciumMg: double.tryParse(_calciumController.text) ?? 0.0,
        ironMg: double.tryParse(_ironController.text) ?? 0.0,
      ),
      ingredients: widget.food.ingredients,
    );

    try {
      await FirestoreService().updateFood(widget.food.id, updatedItem.toMap());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save food: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Edit Food Definition',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textMain),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _confirmDeleteFood,
                    tooltip: 'Delete Food',
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: _openEmojiPicker,
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
                        child: Text(_selectedEmoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 16),
                        decoration: const InputDecoration(labelText: 'Food Name'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _servingGController,
                        onTap: () => _selectAll(_servingGController),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(labelText: 'Base Serving Size'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBaseUnit,
                            dropdownColor: AppColors.surface,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
                            style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 14),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedBaseUnit = val);
                            },
                            items: const [
                              DropdownMenuItem(value: 'g', child: Text('g')),
                              DropdownMenuItem(value: 'ml', child: Text('ml')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _servingUnitController,
                  onTap: () => _selectAll(_servingUnitController),
                  style: const TextStyle(color: AppColors.textMain),
                  decoration: const InputDecoration(
                    labelText: 'Serving Unit Name (optional)',
                    hintText: 'e.g. slice, cup, portion',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'MACRONUTRIENTS (PER BASE SERVING)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMacroField('Protein (g)', _proteinController, AppColors.protein),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMacroField('Carbs (g)', _carbsController, AppColors.carbs),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMacroField('Fat (g)', _fatController, AppColors.fat),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _caloriesController,
                  onTap: () => _selectAll(_caloriesController),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    setState(() => _isManualCalories = v.isNotEmpty);
                  },
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16),
                  decoration: const InputDecoration(labelText: 'Calories (kcal)'),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => setState(() => _isMicrosExpanded = !_isMicrosExpanded),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _isMicrosExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Advanced Micronutrients',
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isMicrosExpanded) ...[
                  const SizedBox(height: 10),
                  Container(
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
                            Expanded(child: _buildMicroInput('Fiber (g)', _fiberController)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMicroInput('Sugar (g)', _sugarController)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildMicroInput('Sodium (mg)', _sodiumController)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMicroInput('Sat Fat (g)', _satFatController)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildMicroInput('Chol (mg)', _cholesterolController)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMicroInput('Potassium (mg)', _potassiumController)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildMicroInput('Vit A (µg)', _vitAController)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMicroInput('Vit C (mg)', _vitCController)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildMicroInput('Vit D (µg)', _vitDController)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMicroInput('Calcium (mg)', _calciumController)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildMicroInput('Iron (mg)', _ironController)),
                            const SizedBox(width: 8),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
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
                        onPressed: _confirmDeleteFood,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saveChanges,
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroField(String label, TextEditingController controller, Color color) {
    return TextField(
      controller: controller,
      onTap: () => _selectAll(controller),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => _onMacroChanged(),
      style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildMicroInput(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      onTap: () => _selectAll(ctrl),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.textMain, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
