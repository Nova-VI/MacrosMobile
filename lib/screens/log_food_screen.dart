import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/food_item.dart';
import '../models/daily_log.dart';
import '../models/nutrition.dart';
import '../services/firestore_service.dart';
import '../services/usda_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/barcode_scanner_sheet.dart';
import '../widgets/ai_meal_prompt_sheet.dart';
import 'profile_settings_screen.dart';

class LogFoodScreen extends StatefulWidget {
  final DateTime? initialDate;
  final DailyLog? editLog;
  final VoidCallback onLogCompleted;

  const LogFoodScreen({
    super.key,
    this.initialDate,
    this.editLog,
    required this.onLogCompleted,
  });

  @override
  State<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends State<LogFoodScreen> {
  final ScrollController _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _servingSizeController = TextEditingController(text: '100');
  final _servingUnitController = TextEditingController();
  final _servingsController = TextEditingController(text: '1');
  final _totalAmountController = TextEditingController(text: '100');

  // Macros
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _caloriesController = TextEditingController();

  // Micros
  final _fiberController = TextEditingController();
  final _sugarController = TextEditingController();
  final _sodiumController = TextEditingController();
  final _satFatController = TextEditingController();
  final _cholesterolController = TextEditingController();
  final _potassiumController = TextEditingController();
  final _vitAController = TextEditingController();
  final _vitCController = TextEditingController();
  final _vitDController = TextEditingController();
  final _calciumController = TextEditingController();
  final _ironController = TextEditingController();

  final UsdaService _usdaService = UsdaService();
  final FirestoreService _firestoreService = FirestoreService();

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  String _selectedBaseUnit = 'g';
  String _selectedEmoji = '🍽️';
  bool _saveToLibrary = false;
  bool _isManualCalories = false;
  bool _isMicrosExpanded = false;
  bool _isSearching = false;
  bool _isLibraryBound = false;
  bool _isCustomTimeSet = false;
  bool _isCustomDateSet = false;
  bool _showFloatingLogButton = false;

  String _lastAiPromptDraft = '';

  FoodItem? _currentBaseFood;
  String? _editingLogId;

  Timer? _debounceTimer;
  Timer? _liveClockTimer;
  List<FoodItem> _localSearchResults = [];
  List<Map<String, dynamic>> _usdaSearchResults = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _selectedTime = TimeOfDay.now();

    if (widget.editLog != null) {
      _initEditMode(widget.editLog!);
    } else {
      _resetToNewQuickLog();
    }

    _scrollController.addListener(_updateFloatingButtonVisibility);

    _liveClockTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isCustomTimeSet && _editingLogId == null && mounted) {
        final now = TimeOfDay.now();
        if (_selectedTime.hour != now.hour || _selectedTime.minute != now.minute) {
          setState(() {
            _selectedTime = now;
            if (!_isCustomDateSet && widget.initialDate == null) {
              _selectedDate = DateTime.now();
            }
          });
        }
      }
    });
  }

  void _updateFloatingButtonVisibility() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final isNearBottom = (maxScroll - currentScroll) < 100;

    final isSavedOrEdit = _isLibraryBound || _editingLogId != null;
    final shouldShow = isSavedOrEdit && !isNearBottom;

    if (shouldShow != _showFloatingLogButton) {
      setState(() => _showFloatingLogButton = shouldShow);
    }
  }

  void _selectAll(TextEditingController controller) {
    Future.delayed(Duration.zero, () {
      if (controller.text.isNotEmpty) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  void _resetToNewQuickLog() {
    setState(() {
      _editingLogId = null;
      _currentBaseFood = null;
      _selectedEmoji = '🍽️';
      _selectedBaseUnit = 'g';
      _saveToLibrary = false;
      _isManualCalories = false;
      _isLibraryBound = false;
      _isCustomTimeSet = false;
      _isCustomDateSet = false;
      _selectedTime = TimeOfDay.now();
      _selectedDate = widget.initialDate ?? DateTime.now();

      _nameController.clear();
      _servingSizeController.text = '100';
      _servingUnitController.clear();
      _servingsController.text = '1';
      _totalAmountController.text = '100';

      _proteinController.clear();
      _carbsController.clear();
      _fatController.clear();
      _caloriesController.clear();

      _fiberController.clear();
      _sugarController.clear();
      _sodiumController.clear();
      _satFatController.clear();
      _cholesterolController.clear();
      _potassiumController.clear();
      _vitAController.clear();
      _vitCController.clear();
      _vitDController.clear();
      _calciumController.clear();
      _ironController.clear();
    });
    _updateFloatingButtonVisibility();
  }

  void _initEditMode(DailyLog log) {
    _editingLogId = log.id;
    _isLibraryBound = true;
    _selectedEmoji = log.emoji.isNotEmpty ? log.emoji : '🍽️';
    _nameController.text = log.foodName;
    _selectedBaseUnit = log.baseUnit;
    _servingUnitController.text = log.servingName;

    final baseServingG = log.servings > 0 ? (log.servingSizeG / log.servings) : 100.0;
    _servingSizeController.text = (baseServingG % 1 == 0)
        ? baseServingG.toInt().toString()
        : baseServingG.toStringAsFixed(1);
    _servingsController.text = (log.servings % 1 == 0)
        ? log.servings.toInt().toString()
        : log.servings.toStringAsFixed(2);
    _totalAmountController.text = (log.servingSizeG % 1 == 0)
        ? log.servingSizeG.toInt().toString()
        : log.servingSizeG.toStringAsFixed(1);

    _proteinController.text = log.macros.proteinG > 0 ? log.macros.proteinG.toStringAsFixed(1) : '';
    _carbsController.text = log.macros.carbsG > 0 ? log.macros.carbsG.toStringAsFixed(1) : '';
    _fatController.text = log.macros.fatG > 0 ? log.macros.fatG.toStringAsFixed(1) : '';
    _caloriesController.text = log.macros.calories > 0 ? log.macros.calories.round().toString() : '';

    _fiberController.text = log.micros.fiberG > 0 ? log.micros.fiberG.toStringAsFixed(1) : '';
    _sugarController.text = log.micros.sugarG > 0 ? log.micros.sugarG.toStringAsFixed(1) : '';
    _sodiumController.text = log.micros.sodiumMg > 0 ? log.micros.sodiumMg.round().toString() : '';
    _satFatController.text = log.micros.saturatedFatG > 0 ? log.micros.saturatedFatG.toStringAsFixed(1) : '';
    _cholesterolController.text = log.micros.cholesterolMg > 0 ? log.micros.cholesterolMg.round().toString() : '';
    _potassiumController.text = log.micros.potassiumMg > 0 ? log.micros.potassiumMg.round().toString() : '';
    _vitAController.text = log.micros.vitaminAUg > 0 ? log.micros.vitaminAUg.round().toString() : '';
    _vitCController.text = log.micros.vitaminCMg > 0 ? log.micros.vitaminCMg.toStringAsFixed(1) : '';
    _vitDController.text = log.micros.vitaminDUg > 0 ? log.micros.vitaminDUg.toStringAsFixed(1) : '';
    _calciumController.text = log.micros.calciumMg > 0 ? log.micros.calciumMg.round().toString() : '';
    _ironController.text = log.micros.ironMg > 0 ? log.micros.ironMg.toStringAsFixed(1) : '';

    try {
      if (log.date.isNotEmpty) {
        _selectedDate = DateFormat('yyyy-MM-dd').parse(log.date);
      }
      if (log.loggedAt.isNotEmpty) {
        final dt = DateTime.parse(log.loggedAt).toLocal();
        _selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    } catch (_) {}

    _currentBaseFood = FoodItem(
      id: log.foodId ?? '',
      name: log.foodName,
      source: 'custom',
      servingSizeG: baseServingG,
      baseUnit: log.baseUnit,
      servingName: log.servingName,
      emoji: log.emoji,
      macros: log.macros.scale(1.0 / (log.servings > 0 ? log.servings : 1.0)),
      micros: log.micros.scale(1.0 / (log.servings > 0 ? log.servings : 1.0)),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _liveClockTimer?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _servingSizeController.dispose();
    _servingUnitController.dispose();
    _servingsController.dispose();
    _totalAmountController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _caloriesController.dispose();
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

  void _openBarcodeScanner() {
    HapticFeedback.lightImpact();
    BarcodeScannerSheet.show(
      context,
      onFoodFound: (scannedFood, {bool isUnreliable = false}) {
        _populateFromScannedFood(scannedFood, isUnreliable: isUnreliable);
      },
      onNotFound: (message) {
        _showToast(message, isError: true);
      },
    );
  }

  Future<void> _openAiMealPrompt() async {
    HapticFeedback.lightImpact();

    final apiKey = await GeminiService.getApiKey();
    if (!mounted) return;

    if (apiKey.isEmpty) {
      _showApiKeyRequiredDialog();
      return;
    }

    AiMealPromptSheet.show(
      context,
      initialText: _lastAiPromptDraft,
      onMealParsed: (parsedFood) {
        _lastAiPromptDraft = '';
        _populateFromAiAnalysis(parsedFood);
      },
      onError: (errorMessage, lastPrompt) {
        _lastAiPromptDraft = lastPrompt;
        if (errorMessage.isNotEmpty) {
          _showToast(errorMessage, isError: true);
        }
      },
    );
  }

  void _showApiKeyRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Gemini API Key Required',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: const Text(
          'To use AI meal analysis, please add a free Gemini API key in your Profile Settings.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
                    );
                  },
                  child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _populateFromAiAnalysis(FoodItem food) {
    _editingLogId = null;
    _isLibraryBound = false;
    _selectedEmoji = food.emoji.isNotEmpty ? food.emoji : '🍽️';
    _selectedBaseUnit = food.baseUnit;
    _nameController.text = food.name;
    _servingUnitController.text = food.servingName;

    final baseG = (food.servingSizeG > 0) ? food.servingSizeG : 100.0;
    _servingSizeController.text = (baseG % 1 == 0)
        ? baseG.toInt().toString()
        : baseG.toStringAsFixed(1);
    _servingsController.text = '1';
    _totalAmountController.text = _servingSizeController.text;

    final pro = food.macros.proteinG;
    final carb = food.macros.carbsG;
    final fat = food.macros.fatG;
    final dynamicCalories = (pro * 4.0) + (carb * 4.0) + (fat * 9.0);

    _proteinController.text = pro > 0 ? pro.toStringAsFixed(1) : '';
    _carbsController.text = carb > 0 ? carb.toStringAsFixed(1) : '';
    _fatController.text = fat > 0 ? fat.toStringAsFixed(1) : '';
    _caloriesController.text = dynamicCalories > 0 ? dynamicCalories.round().toString() : '';

    final mic = food.micros;
    _fiberController.text = mic.fiberG > 0 ? mic.fiberG.toStringAsFixed(1) : '';
    _sugarController.text = mic.sugarG > 0 ? mic.sugarG.toStringAsFixed(1) : '';
    _sodiumController.text = mic.sodiumMg > 0 ? mic.sodiumMg.round().toString() : '';
    _satFatController.text = mic.saturatedFatG > 0 ? mic.saturatedFatG.toStringAsFixed(1) : '';
    _cholesterolController.text = mic.cholesterolMg > 0 ? mic.cholesterolMg.round().toString() : '';
    _potassiumController.text = mic.potassiumMg > 0 ? mic.potassiumMg.round().toString() : '';
    _vitAController.text = mic.vitaminAUg > 0 ? mic.vitaminAUg.round().toString() : '';
    _vitCController.text = mic.vitaminCMg > 0 ? mic.vitaminCMg.toStringAsFixed(1) : '';
    _vitDController.text = mic.vitaminDUg > 0 ? mic.vitaminDUg.toStringAsFixed(1) : '';
    _calciumController.text = mic.calciumMg > 0 ? mic.calciumMg.round().toString() : '';
    _ironController.text = mic.ironMg > 0 ? mic.ironMg.toStringAsFixed(1) : '';

    _currentBaseFood = FoodItem(
      id: '',
      name: food.name,
      source: 'custom',
      servingSizeG: baseG,
      baseUnit: food.baseUnit,
      servingName: food.servingName,
      emoji: _selectedEmoji,
      macros: MacroNutrients(
        proteinG: pro,
        carbsG: carb,
        fatG: fat,
        calories: dynamicCalories,
      ),
      micros: mic,
    );

    _showToast('Loaded "${food.name}" into Quick Log');
    setState(() {});
    _updateFloatingButtonVisibility();
  }

  void _populateFromScannedFood(FoodItem food, {bool isUnreliable = false}) {
    _editingLogId = null;
    _isLibraryBound = false;
    _selectedEmoji = food.emoji.isNotEmpty ? food.emoji : '🍽️';
    _selectedBaseUnit = food.baseUnit;
    _nameController.text = food.name;
    _servingUnitController.text = food.servingName;

    final baseG = (food.servingSizeG > 0) ? food.servingSizeG : 100.0;
    _servingSizeController.text = (baseG % 1 == 0)
        ? baseG.toInt().toString()
        : baseG.toStringAsFixed(1);
    _servingsController.text = '1';
    _totalAmountController.text = _servingSizeController.text;

    if (isUnreliable) {
      _proteinController.clear();
      _carbsController.clear();
      _fatController.clear();
      _caloriesController.clear();

      _fiberController.clear();
      _sugarController.clear();
      _sodiumController.clear();
      _satFatController.clear();
      _cholesterolController.clear();
      _potassiumController.clear();
      _vitAController.clear();
      _vitCController.clear();
      _vitDController.clear();
      _calciumController.clear();
      _ironController.clear();

      _currentBaseFood = FoodItem(
        id: '',
        name: food.name,
        source: food.source,
        servingSizeG: baseG,
        baseUnit: food.baseUnit,
        servingName: food.servingName,
        emoji: _selectedEmoji,
        macros: const MacroNutrients(),
        micros: const MicroNutrients(),
      );

      _showToast(
        'Found "${food.name}", but nutrition facts are missing. Please enter macros manually.',
        isError: true,
      );
    } else {
      final pro = food.macros.proteinG;
      final carb = food.macros.carbsG;
      final fat = food.macros.fatG;
      final dynamicCalories = (pro * 4.0) + (carb * 4.0) + (fat * 9.0);

      _proteinController.text = pro > 0 ? pro.toStringAsFixed(1) : '';
      _carbsController.text = carb > 0 ? carb.toStringAsFixed(1) : '';
      _fatController.text = fat > 0 ? fat.toStringAsFixed(1) : '';
      _caloriesController.text = dynamicCalories > 0 ? dynamicCalories.round().toString() : '';

      final mic = food.micros;
      _fiberController.text = mic.fiberG > 0 ? mic.fiberG.toStringAsFixed(1) : '';
      _sugarController.text = mic.sugarG > 0 ? mic.sugarG.toStringAsFixed(1) : '';
      _sodiumController.text = mic.sodiumMg > 0 ? mic.sodiumMg.round().toString() : '';
      _satFatController.text = mic.saturatedFatG > 0 ? mic.saturatedFatG.toStringAsFixed(1) : '';
      _cholesterolController.text = mic.cholesterolMg > 0 ? mic.cholesterolMg.round().toString() : '';
      _potassiumController.text = mic.potassiumMg > 0 ? mic.potassiumMg.round().toString() : '';
      _vitAController.text = mic.vitaminAUg > 0 ? mic.vitaminAUg.round().toString() : '';
      _vitCController.text = mic.vitaminCMg > 0 ? mic.vitaminCMg.toStringAsFixed(1) : '';
      _vitDController.text = mic.vitaminDUg > 0 ? mic.vitaminDUg.toStringAsFixed(1) : '';
      _calciumController.text = mic.calciumMg > 0 ? mic.calciumMg.round().toString() : '';
      _ironController.text = mic.ironMg > 0 ? mic.ironMg.toStringAsFixed(1) : '';

      _currentBaseFood = FoodItem(
        id: '',
        name: food.name,
        source: food.source,
        servingSizeG: baseG,
        baseUnit: food.baseUnit,
        servingName: food.servingName,
        emoji: _selectedEmoji,
        macros: MacroNutrients(
          proteinG: pro,
          carbsG: carb,
          fatG: fat,
          calories: dynamicCalories,
        ),
        micros: mic,
      );

      _showToast('Found "${food.name}"');
    }

    setState(() {});
    _updateFloatingButtonVisibility();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final q = query.trim().toLowerCase();

    if (q.length < 2) {
      setState(() {
        _localSearchResults = [];
        _usdaSearchResults = [];
        _isSearching = false;
      });
      return;
    }

    final allFoods = _firestoreService.foodsNotifier.value;
    final localMatches = allFoods.where((f) => f.name.toLowerCase().contains(q)).toList();

    setState(() {
      _localSearchResults = localMatches;
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 380), () async {
      final usdaMatches = await _usdaService.searchFoods(q);
      if (mounted && _searchController.text.trim().toLowerCase() == q) {
        setState(() {
          _usdaSearchResults = usdaMatches;
          _isSearching = false;
        });
      }
    });
  }

  void _onFoodNameChanged(String typedName) {
    if (_editingLogId != null) return;
    final trimmed = typedName.trim().toLowerCase();

    if (trimmed.length < 2) {
      if (_isLibraryBound) {
        setState(() {
          _isLibraryBound = false;
          _currentBaseFood = null;
          _selectedEmoji = '🍽️';
        });
      }
      _updateFloatingButtonVisibility();
      return;
    }

    final allFoods = _firestoreService.foodsNotifier.value;
    FoodItem? matched;
    for (final f in allFoods) {
      if (f.name.trim().toLowerCase() == trimmed) {
        matched = f;
        break;
      }
    }

    if (matched != null && !_isLibraryBound) {
      HapticFeedback.mediumImpact();
      _populateFromLibraryItem(matched, preserveTypedName: typedName);
    } else if (matched == null && _isLibraryBound) {
      setState(() {
        _isLibraryBound = false;
        _currentBaseFood = null;
      });
    }
    _updateFloatingButtonVisibility();
  }

  void _populateFromLibraryItem(FoodItem food, {String? preserveTypedName}) {
    _currentBaseFood = food;
    _isLibraryBound = true;
    _selectedEmoji = food.emoji.isNotEmpty ? food.emoji : '🍽️';
    _selectedBaseUnit = food.baseUnit;
    _servingUnitController.text = food.servingName;
    _servingSizeController.text = (food.servingSizeG % 1 == 0)
        ? food.servingSizeG.toInt().toString()
        : food.servingSizeG.toStringAsFixed(1);

    if (preserveTypedName == null) {
      _nameController.text = food.name;
    }

    _servingsController.text = '1';
    _totalAmountController.text = _servingSizeController.text;

    _scaleNutrients(1.0);
    setState(() {});
    _updateFloatingButtonVisibility();
  }

  void _selectFoodItem(FoodItem food) {
    HapticFeedback.selectionClick();
    _searchController.clear();
    _localSearchResults.clear();
    _usdaSearchResults.clear();
    _populateFromLibraryItem(food);
  }

  void _scaleNutrients(double multiplier) {
    if (_currentBaseFood == null) return;

    final m = _currentBaseFood!.macros;
    final pro = m.proteinG * multiplier;
    final carb = m.carbsG * multiplier;
    final fat = m.fatG * multiplier;

    _proteinController.text = pro > 0 ? pro.toStringAsFixed(1) : '';
    _carbsController.text = carb > 0 ? carb.toStringAsFixed(1) : '';
    _fatController.text = fat > 0 ? fat.toStringAsFixed(1) : '';

    if (!_isManualCalories) {
      final cals = (pro * 4.0) + (carb * 4.0) + (fat * 9.0);
      _caloriesController.text = cals > 0 ? cals.round().toString() : '';
    } else {
      final manualCals = m.calories * multiplier;
      _caloriesController.text = manualCals > 0 ? manualCals.round().toString() : '';
    }

    final mic = _currentBaseFood!.micros;
    _fiberController.text = (mic.fiberG * multiplier) > 0 ? (mic.fiberG * multiplier).toStringAsFixed(1) : '';
    _sugarController.text = (mic.sugarG * multiplier) > 0 ? (mic.sugarG * multiplier).toStringAsFixed(1) : '';
    _sodiumController.text = (mic.sodiumMg * multiplier) > 0 ? (mic.sodiumMg * multiplier).round().toString() : '';
    _satFatController.text = (mic.saturatedFatG * multiplier) > 0 ? (mic.saturatedFatG * multiplier).toStringAsFixed(1) : '';
    _cholesterolController.text = (mic.cholesterolMg * multiplier) > 0 ? (mic.cholesterolMg * multiplier).round().toString() : '';
    _potassiumController.text = (mic.potassiumMg * multiplier) > 0 ? (mic.potassiumMg * multiplier).round().toString() : '';
    _vitAController.text = (mic.vitaminAUg * multiplier) > 0 ? (mic.vitaminAUg * multiplier).round().toString() : '';
    _vitCController.text = (mic.vitaminCMg * multiplier) > 0 ? (mic.vitaminCMg * multiplier).toStringAsFixed(1) : '';
    _vitDController.text = (mic.vitaminDUg * multiplier) > 0 ? (mic.vitaminDUg * multiplier).toStringAsFixed(1) : '';
    _calciumController.text = (mic.calciumMg * multiplier) > 0 ? (mic.calciumMg * multiplier).round().toString() : '';
    _ironController.text = (mic.ironMg * multiplier) > 0 ? (mic.ironMg * multiplier).toStringAsFixed(1) : '';
  }

  void _onBaseServingChanged(String val) {
    if (_isLibraryBound || _editingLogId != null) return;
    final newBase = double.tryParse(val) ?? 100.0;
    final oldBase = _currentBaseFood?.servingSizeG ?? 100.0;

    if (newBase > 0 && oldBase > 0 && newBase != oldBase) {
      final ratio = newBase / oldBase;
      if (_currentBaseFood != null) {
        _currentBaseFood = FoodItem(
          id: _currentBaseFood!.id,
          name: _currentBaseFood!.name,
          source: _currentBaseFood!.source,
          usdaFdcId: _currentBaseFood!.usdaFdcId,
          servingSizeG: newBase,
          baseUnit: _selectedBaseUnit,
          servingName: _servingUnitController.text.trim(),
          emoji: _selectedEmoji,
          macros: _currentBaseFood!.macros.scale(ratio),
          micros: _currentBaseFood!.micros.scale(ratio),
        );
      }
    }

    final mult = double.tryParse(_servingsController.text) ?? 1.0;
    final total = newBase * mult;
    _totalAmountController.text = (total % 1 == 0) ? total.toInt().toString() : total.toStringAsFixed(1);
    _scaleNutrients(mult);
  }

  void _onServingsChanged(String val) {
    final mult = double.tryParse(val) ?? 0.0;
    final base = double.tryParse(_servingSizeController.text) ?? 100.0;
    final total = base * mult;
    _totalAmountController.text = (total % 1 == 0) ? total.toInt().toString() : total.toStringAsFixed(1);
    _scaleNutrients(mult);
    _updateFloatingButtonVisibility();
  }

  void _onTotalAmountChanged(String val) {
    final total = double.tryParse(val) ?? 0.0;
    final base = double.tryParse(_servingSizeController.text) ?? 100.0;
    if (base > 0) {
      final mult = total / base;
      _servingsController.text = (mult % 1 == 0) ? mult.toInt().toString() : mult.toStringAsFixed(2);
      _scaleNutrients(mult);
      _updateFloatingButtonVisibility();
    }
  }

  void _onManualNutrientTyped() {
    final mult = double.tryParse(_servingsController.text) ?? 1.0;
    final m = mult > 0 ? mult : 1.0;

    final p = double.tryParse(_proteinController.text) ?? 0.0;
    final c = double.tryParse(_carbsController.text) ?? 0.0;
    final f = double.tryParse(_fatController.text) ?? 0.0;

    if (!_isManualCalories) {
      final displayCals = (p * 4.0) + (c * 4.0) + (f * 9.0);
      _caloriesController.text = displayCals > 0 ? displayCals.round().toString() : '';
    }

    final baseP = p / m;
    final baseC = c / m;
    final baseF = f / m;
    final baseCal = !_isManualCalories
        ? (baseP * 4.0) + (baseC * 4.0) + (baseF * 9.0)
        : (double.tryParse(_caloriesController.text) ?? 0.0) / m;

    _currentBaseFood = FoodItem(
      id: _editingLogId != null
          ? (_currentBaseFood?.id ?? '')
          : (_isLibraryBound ? (_currentBaseFood?.id ?? '') : ''),
      name: _nameController.text.trim(),
      source: _currentBaseFood?.source ?? 'custom',
      servingSizeG: double.tryParse(_servingSizeController.text) ?? 100.0,
      baseUnit: _selectedBaseUnit,
      servingName: _servingUnitController.text.trim(),
      emoji: _selectedEmoji,
      macros: MacroNutrients(proteinG: baseP, carbsG: baseC, fatG: baseF, calories: baseCal),
      micros: _getParsedMicros().scale(1.0 / m),
    );
    _updateFloatingButtonVisibility();
  }

  void _openEmojiPicker() {
    if (_editingLogId != null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => EmojiPickerSheet(
        onEmojiSelected: (emoji) => setState(() => _selectedEmoji = emoji),
      ),
    );
  }

  void _saveOnlyToLibrary() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showToast('Food name is required to save to library.', isError: true);
      return;
    }

    final mult = double.tryParse(_servingsController.text) ?? 1.0;
    final baseG = double.tryParse(_servingSizeController.text) ?? 100.0;
    final pro = double.tryParse(_proteinController.text) ?? 0.0;
    final carb = double.tryParse(_carbsController.text) ?? 0.0;
    final fat = double.tryParse(_fatController.text) ?? 0.0;
    final cals = double.tryParse(_caloriesController.text) ?? 0.0;

    final item = FoodItem(
      id: '',
      name: name,
      source: _currentBaseFood?.source ?? 'custom',
      usdaFdcId: _currentBaseFood?.usdaFdcId,
      servingSizeG: baseG,
      baseUnit: _selectedBaseUnit,
      servingName: _servingUnitController.text.trim(),
      emoji: _selectedEmoji,
      macros: MacroNutrients(
        proteinG: mult > 0 ? pro / mult : pro,
        carbsG: mult > 0 ? carb / mult : carb,
        fatG: mult > 0 ? fat / mult : fat,
        calories: mult > 0 ? cals / mult : cals,
      ),
      micros: _getParsedMicros().scale(mult > 0 ? 1.0 / mult : 1.0),
    );

    HapticFeedback.mediumImpact();
    _showToast('"$name" saved to library!');
    _resetToNewQuickLog();

    _firestoreService.addFood(item).then((id) {
      if (_selectedEmoji == '🍽️') {
        _handleBackgroundAiEmoji(id, null, name);
      }
    });
  }

  MicroNutrients _getParsedMicros() {
    return MicroNutrients(
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
    );
  }

  void _submitLog() {
    final name = _nameController.text.trim();
    if (name.isEmpty && _saveToLibrary) {
      _showToast('Food name is required to save to library.', isError: true);
      return;
    }

    final displayName = name.isNotEmpty ? name : 'Quick Log Food';
    final mult = double.tryParse(_servingsController.text) ?? 1.0;
    final totalG = double.tryParse(_totalAmountController.text) ?? 100.0;
    final baseG = double.tryParse(_servingSizeController.text) ?? 100.0;

    final pro = double.tryParse(_proteinController.text) ?? 0.0;
    final carb = double.tryParse(_carbsController.text) ?? 0.0;
    final fat = double.tryParse(_fatController.text) ?? 0.0;
    final cals = double.tryParse(_caloriesController.text) ?? 0.0;
    final micros = _getParsedMicros();

    String? foodId = _currentBaseFood?.id;
    final String finalEmoji = _selectedEmoji;
    final bool triggerAiEmoji = (finalEmoji == '🍽️' && name.isNotEmpty);

    if (_saveToLibrary && _editingLogId == null && !_isLibraryBound) {
      final libraryItem = FoodItem(
        id: '',
        name: displayName,
        source: _currentBaseFood?.source ?? 'custom',
        usdaFdcId: _currentBaseFood?.usdaFdcId,
        servingSizeG: baseG,
        baseUnit: _selectedBaseUnit,
        servingName: _servingUnitController.text.trim(),
        emoji: finalEmoji,
        macros: MacroNutrients(
          proteinG: mult > 0 ? pro / mult : pro,
          carbsG: mult > 0 ? carb / mult : carb,
          fatG: mult > 0 ? fat / mult : fat,
          calories: mult > 0 ? cals / mult : cals,
        ),
        micros: micros.scale(mult > 0 ? 1.0 / mult : 1.0),
      );

      _firestoreService.addFood(libraryItem).then((id) => foodId = id);
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final dt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final logPayload = DailyLog(
      id: _editingLogId ?? '',
      date: dateStr,
      loggedAt: dt.toIso8601String(),
      foodId: foodId,
      foodName: displayName,
      servingName: _servingUnitController.text.trim(),
      baseUnit: _selectedBaseUnit,
      emoji: finalEmoji,
      servings: mult,
      servingSizeG: totalG,
      macros: MacroNutrients(calories: cals, proteinG: pro, carbsG: carb, fatG: fat),
      micros: micros,
    );

    HapticFeedback.mediumImpact();
    if (_editingLogId != null) {
      _firestoreService.updateLog(_editingLogId!, logPayload.toMap());
      _showToast('Daily log updated!');
      widget.onLogCompleted();
    } else {
      _showToast('"$displayName" logged successfully!');
      _resetToNewQuickLog();
      _firestoreService.addLog(logPayload).then((newLogId) {
        if (triggerAiEmoji) {
          _handleBackgroundAiEmoji(foodId, newLogId, displayName);
        }
      });
    }
  }

  void _confirmAndDeleteCurrentLog() {
    if (_editingLogId == null) return;
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
          'Delete Entry',
          style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Remove "${_nameController.text.isNotEmpty ? _nameController.text : 'this food'}" from this day\'s log?',
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
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
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
                  onPressed: () {
                    Navigator.pop(ctx, true);
                    _firestoreService.deleteLog(_editingLogId!);
                    HapticFeedback.mediumImpact();
                    _showToast('Daily log entry deleted.');
                    widget.onLogCompleted();
                  },
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleBackgroundAiEmoji(String? foodId, String? logId, String name) async {
    final aiEmoji = await GeminiService.fetchFoodEmoji(name);
    if (aiEmoji.isNotEmpty && aiEmoji != '🍽️') {
      if (foodId != null && foodId.isNotEmpty) {
        _firestoreService.updateFood(foodId, {'emoji': aiEmoji});
      }
      if (logId != null && logId.isNotEmpty) {
        _firestoreService.updateLog(logId, {'emoji': aiEmoji});
      }
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
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
    final favorites = _firestoreService.getFavoriteFoods();
    final frequents = _firestoreService.getFrequentFoods();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              physics: const BouncingScrollPhysics(),
              children: [
                if (_editingLogId == null) _buildSearchField(),
                if (_editingLogId == null) const SizedBox(height: 12),

                if (_localSearchResults.isNotEmpty || _usdaSearchResults.isNotEmpty || _isSearching)
                  _buildSearchResultsTray(),

                if (_editingLogId == null && (favorites.isNotEmpty || frequents.isNotEmpty)) ...[
                  _buildShortcutsSection(favorites, frequents),
                  const SizedBox(height: 14),
                ],

                _buildFoodIdentityCard(),
                const SizedBox(height: 14),
                _buildPortionCard(),
                const SizedBox(height: 14),
                _buildNutritionCard(),
                const SizedBox(height: 14),
                _buildActionsCard(),
              ],
            ),

            if (_showFloatingLogButton)
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: _buildFloatingLogBubble(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingLogBubble() {
    final isEditing = _editingLogId != null;
    final cals = _caloriesController.text.isNotEmpty ? _caloriesController.text : '0';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * val),
          child: Opacity(opacity: val, child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _submitLog,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(_selectedEmoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Text(
                      isEditing ? 'Update Entry' : 'Log Food',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$cals kcal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onTap: () => _selectAll(_searchController),
            style: const TextStyle(color: AppColors.textMain, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              isDense: true,
              hintText: 'Search foods...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
              suffixIcon: _isSearching
                  ?  Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    )
                  : _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _openBarcodeScanner,
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
            child:  Icon(
              Icons.qr_code_scanner_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _openAiMealPrompt,
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
              Icons.auto_awesome_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultsTray() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          children: [
            ..._localSearchResults.map((food) => _buildSearchResultTile(
                  title: food.name,
                  emoji: food.emoji,
                  badge: food.source == 'composite' ? 'composite' : 'library',
                  isUsda: false,
                  onTap: () => _selectFoodItem(food),
                )),
            ..._usdaSearchResults.map((usda) => _buildSearchResultTile(
                  title: usda['description'],
                  emoji: '🍽️',
                  badge: 'USDA',
                  isUsda: true,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final details = await _usdaService.getFoodDetails(usda['fdcId']);
                    if (details != null) _selectFoodItem(details);
                  },
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultTile({
    required String title,
    required String emoji,
    required String badge,
    required bool isUsda,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Text(emoji, style: const TextStyle(fontSize: 18)),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isUsda ? AppColors.secondary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          badge.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: isUsda ? AppColors.secondary : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutsSection(List<FoodItem> favorites, List<FoodItem> frequents) {
    final items = favorites.isNotEmpty ? favorites : frequents;
    final title = favorites.isNotEmpty ? 'Favorites' : 'Frequent Foods';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final item = items[idx];
              return InkWell(
                onTap: () => _selectFoodItem(item),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.emoji.isNotEmpty ? item.emoji : '🍽️', style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                      Text(
                        item.name,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMain),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFoodIdentityCard() {
    final isEditMode = _editingLogId != null;

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
              Row(
                children: [
                  Text(
                    isEditMode ? 'Edit Entry' : (_isLibraryBound ? 'Saved Food' : 'Quick Log'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMain,
                    ),
                  ),
                  if (isEditMode) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: _confirmAndDeleteCurrentLog,
                      tooltip: 'Delete Entry',
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  _buildPillDatePicker(),
                  const SizedBox(width: 6),
                  _buildPillTimePicker(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isEditMode) ...[
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(_selectedEmoji, style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nameController.text,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMain,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Base serving: ${_servingSizeController.text}$_selectedBaseUnit ${_servingUnitController.text.isNotEmpty ? '(${_servingUnitController.text})' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
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
                    child: Text(_selectedEmoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    onTap: () => _selectAll(_nameController),
                    onChanged: _onFoodNameChanged,
                    style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Food Name',
                      hintText: 'e.g. Scrambled Eggs',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPortionCard() {
    final isEditMode = _editingLogId != null;

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
            'PORTION & SERVINGS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),

          if (!isEditMode && !_isLibraryBound) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _servingSizeController,
                    onTap: () => _selectAll(_servingSizeController),
                    onChanged: _onBaseServingChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(labelText: 'Base Serving'),
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
                          if (val != null) {
                            setState(() => _selectedBaseUnit = val);
                            _onBaseServingChanged(_servingSizeController.text);
                          }
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
              onChanged: (_) => _onManualNutrientTyped(),
              style: const TextStyle(color: AppColors.textMain),
              decoration: const InputDecoration(
                labelText: 'Serving Unit Name (optional)',
                hintText: 'e.g. slice, cup, portion',
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _servingsController,
                  onTap: () => _selectAll(_servingsController),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _onServingsChanged,
                  style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(labelText: 'Servings Multiplier'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _totalAmountController,
                  onTap: () => _selectAll(_totalAmountController),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _onTotalAmountChanged,
                  style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(labelText: 'Total ($_selectedBaseUnit)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionCard() {
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
            'NUTRITION VALUES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMacroField('Protein (g)', _proteinController, AppColors.protein),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMacroField('Carbs (g)', _carbsController, AppColors.secondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMacroField('Fat (g)', _fatController, AppColors.warning),
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
              _onManualNutrientTyped();
            },
            style:  TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Calories (kcal)',
              suffixIcon: _isManualCalories
                  ? Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:  Text(
                        '✎ manual',
                        style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(minHeight: 24, minWidth: 24),
            ),
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
                    'Hide Micronutrients',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          if (_isMicrosExpanded) ...[
            const SizedBox(height: 10),
            _buildDualColumnMicros(),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (_editingLogId == null && !_isLibraryBound) ...[
            CheckboxListTile(
              value: _saveToLibrary,
              onChanged: (val) => setState(() => _saveToLibrary = val ?? false),
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Save to food library for future logs',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textMain),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_editingLogId != null) ...[
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
                    onPressed: _confirmAndDeleteCurrentLog,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitLog,
                    child: const Text('Update Log Entry'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (!_isLibraryBound) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textMain,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _saveOnlyToLibrary,
                      child: const Text('Save Only', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitLog,
                    child: const Text('Log Food'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroField(String label, TextEditingController controller, Color color) {
    return TextField(
      controller: controller,
      onTap: () => _selectAll(controller),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => _onManualNutrientTyped(),
      style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color.withValues(alpha: 0.9), fontWeight: FontWeight.w600, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildDualColumnMicros() {
    return Container(
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

  Widget _buildPillDatePicker() {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) {
          setState(() {
            _selectedDate = picked;
            _isCustomDateSet = true;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          DateFormat('MMM d').format(_selectedDate),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMain),
        ),
      ),
    );
  }

  Widget _buildPillTimePicker() {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picked = await showTimePicker(
          context: context,
          initialTime: _selectedTime,
        );
        if (picked != null) {
          setState(() {
            _selectedTime = picked;
            _isCustomTimeSet = true;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHover,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          _selectedTime.format(context),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMain),
        ),
      ),
    );
  }
}