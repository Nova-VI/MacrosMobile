import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../models/weight_log.dart';
import '../services/auth_service.dart';
import '../services/api_key_store.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/api_key_guide_sheet.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  int _currentStep = 0;
  static const int _totalSteps = 9;

  // Step 1: Name
  final _nameController = TextEditingController();

  // Step 2: Demographics & Birthday Wheel Picker
  String _gender = 'male';
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;

  late FixedExtentScrollController _yearWheelController;
  late FixedExtentScrollController _monthWheelController;
  late FixedExtentScrollController _dayWheelController;

  static final int _minYear = 1930;
  static final int _maxYear = DateTime.now().year;

  // Step 3: Body Metrics
  final _heightController = TextEditingController(text: '175');
  final _weightController = TextEditingController(text: '70');

  // Step 4: Activity Level
  String _activityLevel = '1.2';

  // Step 5: Goal Strategy
  String _weeklyGoal = '0';

  // Step 6: Protein Preference
  final List<double> _proteinOptions = [1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0];
  int _selectedProteinIndex = 4; // Default 2.0
  late FixedExtentScrollController _proteinWheelController;

  String get _proteinMultiplier => _proteinOptions[_selectedProteinIndex].toStringAsFixed(1);

  // Step 7: Targets & Manual Override
  bool _isManualOverride = false;
  final _targetCalController = TextEditingController(text: '2000');
  final _targetProController = TextEditingController(text: '140');
  final _targetCarbController = TextEditingController(text: '210');
  final _targetFatController = TextEditingController(text: '56');

  // Step 8 & 9: API Keys
  final _usdaKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  bool _includeBranded = false;
  bool _obscureUsda = true;
  bool _obscureGemini = true;

  @override
  void initState() {
    super.initState();
    final user = _authService.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameController.text = user.displayName!;
      } else {
        _nameController.text = user.email?.split('@').first ?? '';
      }
    }

    _selectedYear = 2001;
    _selectedMonth = 1;
    _selectedDay = 1;

    _yearWheelController = FixedExtentScrollController(initialItem: _selectedYear - _minYear);
    _monthWheelController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _dayWheelController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _proteinWheelController = FixedExtentScrollController(initialItem: _selectedProteinIndex);

    _calculateTargets();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectAll(_nameController);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _targetCalController.dispose();
    _targetProController.dispose();
    _targetCarbController.dispose();
    _targetFatController.dispose();
    _usdaKeyController.dispose();
    _geminiKeyController.dispose();
    _yearWheelController.dispose();
    _monthWheelController.dispose();
    _dayWheelController.dispose();
    _proteinWheelController.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController ctrl) {
    Future.delayed(Duration.zero, () {
      if (ctrl.text.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
  }

  int get _daysInSelectedMonth {
    return DateTime(_selectedYear, _selectedMonth + 1, 0).day;
  }

  int get _calculatedAge {
    final now = DateTime.now();
    int age = now.year - _selectedYear;
    if (now.month < _selectedMonth || (now.month == _selectedMonth && now.day < _selectedDay)) {
      age--;
    }
    return age > 0 ? age : 25;
  }

  void _calculateTargets() {
    final age = _calculatedAge;
    final height = double.tryParse(_heightController.text) ?? 175.0;
    final weight = double.tryParse(_weightController.text) ?? 70.0;
    final activity = double.tryParse(_activityLevel) ?? 1.2;
    final goalAdjustment = double.tryParse(_weeklyGoal) ?? 0.0;
    final proteinFactor = double.tryParse(_proteinMultiplier) ?? 2.0;

    double bmr;
    if (_gender == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    final tdee = bmr * activity;
    final targetCals = (tdee + goalAdjustment).round();
    final protein = (weight * proteinFactor).round();
    final fat = ((targetCals * 0.25) / 9).round();
    final carbs = ((targetCals - (protein * 4) - (fat * 9)) / 4).round().clamp(0, 9999);

    if (!_isManualOverride) {
      setState(() {
        _targetCalController.text = targetCals.toString();
        _targetProController.text = protein.toString();
        _targetCarbController.text = carbs.toString();
        _targetFatController.text = fat.toString();
      });
    }
  }

  void _onManualMacroChanged() {
    final p = double.tryParse(_targetProController.text) ?? 0.0;
    final c = double.tryParse(_targetCarbController.text) ?? 0.0;
    final f = double.tryParse(_targetFatController.text) ?? 0.0;
    final cals = (p * 4) + (c * 4) + (f * 9);

    setState(() {
      _targetCalController.text = cals.round().toString();
    });
  }

  void _onManualCalorieChanged(String val) {
    final cals = double.tryParse(val) ?? 0.0;
    if (cals > 0) {
      final weight = double.tryParse(_weightController.text) ?? 70.0;
      final proteinFactor = double.tryParse(_proteinMultiplier) ?? 2.0;
      final protein = (weight * proteinFactor).round();
      final fat = ((cals * 0.25) / 9).round();
      final carbs = ((cals - (protein * 4) - (fat * 9)) / 4).round().clamp(0, 9999);

      setState(() {
        _targetProController.text = protein.toString();
        _targetCarbController.text = carbs.toString();
        _targetFatController.text = fat.toString();
      });
    }
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _previousPage() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _submitStep1Name() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await _authService.updateDisplayName(name);
    _nextPage();
  }

  Future<void> _submitStep7Targets() async {
    final birthDateStr = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${_selectedDay.toString().padLeft(2, '0')}';
    final age = _calculatedAge;
    final height = double.tryParse(_heightController.text) ?? 175.0;
    final weight = double.tryParse(_weightController.text) ?? 70.0;
    final activity = double.tryParse(_activityLevel) ?? 1.2;

    double bmr;
    if (_gender == 'male') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    final initialTdee = bmr * activity;

    final payload = UserProfile(
      id: '1',
      goalMode: _isManualOverride ? 'manual' : 'calculator',
      targetCalories: double.tryParse(_targetCalController.text) ?? 2000.0,
      targetProteinG: double.tryParse(_targetProController.text) ?? 150.0,
      targetCarbsG: double.tryParse(_targetCarbController.text) ?? 200.0,
      targetFatG: double.tryParse(_targetFatController.text) ?? 65.0,
      birthDate: birthDateStr,
      gender: _gender,
      height: height,
      weight: weight,
      activity: _activityLevel,
      goal: _weeklyGoal,
      proteinMultiplier: _proteinMultiplier,
      estimatedTdee: initialTdee, // Explicitly saved from Day 1
    );

    await _firestoreService.saveProfile(payload);

    final w = double.tryParse(_weightController.text) ?? 0.0;
    if (w > 0) {
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _firestoreService.setWeightLog(WeightLog(date: todayKey, weightKg: w));
    }

    _nextPage();
  }

 Future<void> _submitStep8Usda() async {
    final usdaKey = _usdaKeyController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (usdaKey.isNotEmpty && user != null) {
      final prefs = await SharedPreferences.getInstance();
      await ApiKeyStore.write(user.uid, 'usda', usdaKey);
      await prefs.setBool('usda_include_branded_${user.uid}', _includeBranded);

      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('config')
          .set({
        'usda_api_key': usdaKey,
        'usda_include_branded': _includeBranded,
      }, SetOptions(merge: true));
    }
    _nextPage();
  }

  Future<void> _submitStep9GeminiAndFinish() async {
    final geminiKey = _geminiKeyController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (geminiKey.isNotEmpty && user != null) {
      await ApiKeyStore.write(user.uid, 'gemini', geminiKey);

      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('config')
          .set({
        'gemini_api_key': geminiKey,
      }, SetOptions(merge: true));
    }

    HapticFeedback.mediumImpact();
    await _authService.setOnboardingCompleted(true);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: AppColors.textMuted,
                      onPressed: _previousPage,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentStep + 1) / _totalSteps,
                        minHeight: 6,
                        backgroundColor: AppColors.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Step ${_currentStep + 1} of $_totalSteps',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentStep = idx),
                children: [
                  _buildStep1NameView(),
                  _buildStep2DemographicsView(),
                  _buildStep3BodyMetricsView(),
                  _buildStep4ActivityLevelView(),
                  _buildStep5GoalStrategyView(),
                  _buildStep6ProteinTumblerView(),
                  _buildStep7TargetStrategyView(),
                  _buildStep8UsdaView(),
                  _buildStep9GeminiView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1NameView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 20),
        Icon(Icons.waving_hand_rounded, size: 48, color: AppColors.primary),
        const SizedBox(height: 16),
        const Text(
          'Welcome to MacroTracker',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: AppColors.textMain,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'What should we call you? You can change this anytime in your profile settings.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 36),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _nameController,
            autofocus: true,
            onTap: () => _selectAll(_nameController),
            style: const TextStyle(color: AppColors.textMain, fontSize: 17, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Your Name or Nickname',
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.textMuted),
            ),
            onSubmitted: (_) => _submitStep1Name(),
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton(
          onPressed: _submitStep1Name,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep2DemographicsView() {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'About You',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select your biological sex and birthdate to determine baseline metabolic expenditure.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(child: _buildGenderButton('Male', 'male', Icons.male_rounded)),
            const SizedBox(width: 8),
            Expanded(child: _buildGenderButton('Female', 'female', Icons.female_rounded)),
          ],
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DATE OF BIRTH',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_calculatedAge yrs old',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Separated 3-Wheel Tumbler with Horizontal Margins
              SizedBox(
                height: 160,
                child: Row(
                  children: [
                    // Year Tumbler
                    Expanded(
                      flex: 4,
                      child: CupertinoPicker.builder(
                        scrollController: _yearWheelController,
                        itemExtent: 42,
                        selectionOverlay: _buildWheelSelectionOverlay(),
                        childCount: _maxYear - _minYear + 1,
                        onSelectedItemChanged: (idx) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedYear = _minYear + idx;
                            if (_selectedDay > _daysInSelectedMonth) {
                              _selectedDay = _daysInSelectedMonth;
                              _dayWheelController.jumpToItem(_selectedDay - 1);
                            }
                          });
                          _calculateTargets();
                        },
                        itemBuilder: (context, idx) {
                          final y = _minYear + idx;
                          final isSel = y == _selectedYear;
                          return Center(
                            child: Text(
                              '$y',
                              style: TextStyle(
                                fontSize: isSel ? 18 : 14,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.w500,
                                color: isSel ? AppColors.primary : AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Month Tumbler
                    Expanded(
                      flex: 4,
                      child: CupertinoPicker.builder(
                        scrollController: _monthWheelController,
                        itemExtent: 42,
                        selectionOverlay: _buildWheelSelectionOverlay(),
                        childCount: 12,
                        onSelectedItemChanged: (idx) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedMonth = idx + 1;
                            if (_selectedDay > _daysInSelectedMonth) {
                              _selectedDay = _daysInSelectedMonth;
                              _dayWheelController.jumpToItem(_selectedDay - 1);
                            }
                          });
                          _calculateTargets();
                        },
                        itemBuilder: (context, idx) {
                          final isSel = (idx + 1) == _selectedMonth;
                          return Center(
                            child: Text(
                              months[idx],
                              style: TextStyle(
                                fontSize: isSel ? 18 : 14,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.w500,
                                color: isSel ? AppColors.primary : AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Day Tumbler
                    Expanded(
                      flex: 3,
                      child: CupertinoPicker.builder(
                        scrollController: _dayWheelController,
                        itemExtent: 42,
                        selectionOverlay: _buildWheelSelectionOverlay(),
                        childCount: _daysInSelectedMonth,
                        onSelectedItemChanged: (idx) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedDay = idx + 1;
                          });
                          _calculateTargets();
                        },
                        itemBuilder: (context, idx) {
                          final d = idx + 1;
                          final isSel = d == _selectedDay;
                          return Center(
                            child: Text(
                              '$d',
                              style: TextStyle(
                                fontSize: isSel ? 18 : 14,
                                fontWeight: isSel ? FontWeight.w900 : FontWeight.w500,
                                color: isSel ? AppColors.primary : AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _nextPage,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep3BodyMetricsView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Body Metrics',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your height and current scale weight establish your starting point.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(child: _buildBiometricInput('Height', _heightController, 'cm')),
            const SizedBox(width: 10),
            Expanded(child: _buildBiometricInput('Current Weight', _weightController, 'kg')),
          ],
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () {
            _calculateTargets();
            _nextPage();
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep4ActivityLevelView() {
    final activityOptions = [
      {
        'value': '1.2',
        'title': 'Sedentary',
        'desc': 'Desk job, little to no structured workouts or daily steps.',
        'icon': Icons.chair_rounded,
      },
      {
        'value': '1.375',
        'title': 'Lightly Active',
        'desc': '1 to 3 workout sessions per week or light on-foot movement.',
        'icon': Icons.directions_walk_rounded,
      },
      {
        'value': '1.55',
        'title': 'Moderately Active',
        'desc': '3 to 5 intense training sessions per week with moderate daily movement.',
        'icon': Icons.fitness_center_rounded,
      },
      {
        'value': '1.725',
        'title': 'Very Active',
        'desc': '6 to 7 intense workouts per week or a physically demanding job.',
        'icon': Icons.bolt_rounded,
      },
      {
        'value': '1.9',
        'title': 'Extremely Active / Athlete',
        'desc': 'Daily double sessions, competitive training, or heavy physical labor.',
        'icon': Icons.sports_mma_rounded,
      },
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Daily Activity Level',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose the level that best reflects your non-exercise and exercise physical expenditure.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 16),

        ...activityOptions.map((opt) {
          final isSelected = _activityLevel == opt['value'];
          return _buildRadioCard(
            title: opt['title'] as String,
            description: opt['desc'] as String,
            icon: opt['icon'] as IconData,
            isSelected: isSelected,
            onTap: () {
              setState(() => _activityLevel = opt['value'] as String);
              _calculateTargets();
            },
          );
        }),
        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: () {
            _calculateTargets();
            _nextPage();
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep5GoalStrategyView() {
    final goalOptions = [
      {
        'value': '-500',
        'title': 'Weight Loss (Cut)',
        'desc': 'Target pace of ~0.5 kg/week with a -500 kcal daily deficit.',
        'badge': 'FAT LOSS',
        'color': AppColors.warning,
        'icon': Icons.trending_down_rounded,
      },
      {
        'value': '-250',
        'title': 'Gentle Fat Loss',
        'desc': 'Moderate pace of ~0.25 kg/week with a gentle -250 kcal deficit.',
        'badge': 'SLOW CUT',
        'color': AppColors.warning,
        'icon': Icons.arrow_downward_rounded,
      },
      {
        'value': '0',
        'title': 'Weight Maintenance',
        'desc': 'Maintain body weight with energy balance (0 kcal delta).',
        'badge': 'EQUILIBRIUM',
        'color': AppColors.primary,
        'icon': Icons.balance_rounded,
      },
      {
        'value': '250',
        'title': 'Lean Muscle Gain (Bulk)',
        'desc': 'Controlled lean gain of ~0.25 kg/week with a +250 kcal surplus.',
        'badge': 'LEAN BULK',
        'color': AppColors.secondary,
        'icon': Icons.arrow_upward_rounded,
      },
      {
        'value': '500',
        'title': 'Aggressive Muscle Gain',
        'desc': 'Accelerated muscle building pace with a +500 kcal surplus.',
        'badge': 'FAST BULK',
        'color': AppColors.secondary,
        'icon': Icons.trending_up_rounded,
      },
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Target Objective',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'What is your primary nutritional focus right now?',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 16),

        ...goalOptions.map((opt) {
          final isSelected = _weeklyGoal == opt['value'];
          return _buildRadioCard(
            title: opt['title'] as String,
            description: opt['desc'] as String,
            badge: opt['badge'] as String,
            badgeColor: opt['color'] as Color,
            icon: opt['icon'] as IconData,
            isSelected: isSelected,
            onTap: () {
              setState(() => _weeklyGoal = opt['value'] as String);
              _calculateTargets();
            },
          );
        }),
        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: () {
            _calculateTargets();
            _nextPage();
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildStep6ProteinTumblerView() {
    final weight = double.tryParse(_weightController.text) ?? 70.0;
    final selectedMultiplier = _proteinOptions[_selectedProteinIndex];
    final calculatedProteinG = (weight * selectedMultiplier).round();

    String getTierLabel(double val) {
      if (val <= 1.2) return 'Minimum Recommended';
      if (val <= 1.6) return 'Moderate Intake';
      if (val <= 2.0) return 'Optimal Muscle Preservation';
      if (val <= 2.4) return 'High Protein Recomposition';
      return 'Athlete / High Recovery';
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Protein Target Intake',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'Scroll to select your daily protein multiplier per kilogram of bodyweight.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.protein.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DAILY PROTEIN TARGET',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      getTierLabel(selectedMultiplier),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.protein.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$calculatedProteinG g / day',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.protein),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              const Text(
                'SWIPE MULTIPLIER (g / kg)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: CupertinoPicker.builder(
                  scrollController: _proteinWheelController,
                  itemExtent: 44,
                  selectionOverlay: _buildWheelSelectionOverlay(margin: const EdgeInsets.symmetric(horizontal: 12)),
                  childCount: _proteinOptions.length,
                  onSelectedItemChanged: (idx) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedProteinIndex = idx;
                    });
                    _calculateTargets();
                  },
                  itemBuilder: (context, idx) {
                    final factor = _proteinOptions[idx];
                    final isSel = idx == _selectedProteinIndex;
                    return Center(
                      child: Text(
                        '${factor.toStringAsFixed(1)} g / kg',
                        style: TextStyle(
                          fontSize: isSel ? 19 : 14,
                          fontWeight: isSel ? FontWeight.w900 : FontWeight.w500,
                          color: isSel ? AppColors.protein : AppColors.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () {
            _calculateTargets();
            _nextPage();
          },
          child: const Text('Calculate Nutrition Plan'),
        ),
      ],
    );
  }

  Widget _buildStep7TargetStrategyView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Your Nutrition Plan',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'Calculated baseline targets based on your metabolic expenditure.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DAILY MACRO TARGETS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isManualOverride ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isManualOverride ? 'MANUAL' : 'RECOMMENDED',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _isManualOverride ? AppColors.warning : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Energy Budget', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain)),
                    Row(
                      children: [
                        if (_isManualOverride)
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _targetCalController,
                              onTap: () => _selectAll(_targetCalController),
                              onChanged: _onManualCalorieChanged,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          )
                        else
                          Text(
                            _targetCalController.text,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                          ),
                        const SizedBox(width: 5),
                        const Text('kcal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  _buildMacroCapsule('Protein', _targetProController, AppColors.protein, enabled: _isManualOverride),
                  const SizedBox(width: 8),
                  _buildMacroCapsule('Carbs', _targetCarbController, AppColors.carbs, enabled: _isManualOverride),
                  const SizedBox(width: 8),
                  _buildMacroCapsule('Fat', _targetFatController, AppColors.fat, enabled: _isManualOverride),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _isManualOverride = !_isManualOverride;
              if (!_isManualOverride) {
                _calculateTargets();
              }
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _isManualOverride ? AppColors.warning : AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _isManualOverride ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: _isManualOverride ? AppColors.warning : AppColors.textMuted,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Customize targets manually',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textMain),
                    ),
                  ],
                ),
                Text(
                  _isManualOverride ? 'Enabled' : 'Off',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _isManualOverride ? AppColors.warning : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),

        if (_isManualOverride) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Manual overrides are not recommended. Future adaptive coaching algorithms operate best on standard baseline targets.',
                    style: TextStyle(fontSize: 12, color: AppColors.warning, height: 1.35, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _submitStep7Targets,
          child: const Text('Save Plan & Continue'),
        ),
      ],
    );
  }

  Widget _buildStep8UsdaView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(),
      children: [
        const Icon(Icons.dataset_outlined, size: 44, color: AppColors.secondary),
        const SizedBox(height: 12),
        const Text(
          'USDA Food Database',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 6),
        const Text(
          'Search over 300,000+ verified foods with complete macronutrient and micronutrient profiles.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 16),

        Center(
          child: OutlinedButton.icon(
            onPressed: () => ApiKeyGuideSheet.show(context, initialService: ApiKeyType.usda),
            icon: const Icon(Icons.help_outline_rounded, size: 16),
            label: const Text('How to get a free USDA Key (1-min guide)'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.6)),
              foregroundColor: AppColors.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              TextField(
                controller: _usdaKeyController,
                onTap: () => _selectAll(_usdaKeyController),
                obscureText: _obscureUsda,
                style: const TextStyle(color: AppColors.textMain),
                decoration: InputDecoration(
                  labelText: 'USDA API Key (Optional)',
                  hintText: 'Paste your 40-char key here',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureUsda ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureUsda = !_obscureUsda),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _includeBranded,
                onChanged: (val) => setState(() => _includeBranded = val ?? false),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Include Branded Foods in USDA Search',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMain),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _submitStep8Usda,
          child: const Text('Continue'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _nextPage,
          child: const Text('Skip for now', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildStep9GeminiView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(),
      children: [
        Icon(Icons.auto_awesome_rounded, size: 44, color: AppColors.primary),
        const SizedBox(height: 12),
        const Text(
          'Gemini AI Assistant',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enables automatic emoji detection for all your food entries and smart nutrition insights.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 16),

        Center(
          child: OutlinedButton.icon(
            onPressed: () => ApiKeyGuideSheet.show(context, initialService: ApiKeyType.gemini),
            icon: const Icon(Icons.help_outline_rounded, size: 16),
            label: const Text('How to get a free Gemini Key (1-min guide)'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _geminiKeyController,
            onTap: () => _selectAll(_geminiKeyController),
            obscureText: _obscureGemini,
            style: const TextStyle(color: AppColors.textMain),
            decoration: InputDecoration(
              labelText: 'Gemini AI API Key (Optional)',
              hintText: 'Paste your AI key here',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureGemini ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _submitStep9GeminiAndFinish,
          child: const Text('Complete Setup & Start'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _submitStep9GeminiAndFinish,
          child: const Text('Skip for now', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // --- Helper Card and Input Widgets ---

  Widget _buildRadioCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                              color: isSelected ? AppColors.primary : AppColors.textMain,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: badgeColor ?? AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWheelSelectionOverlay({EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 2)}) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1),
      ),
    );
  }

  Widget _buildGenderButton(String label, String value, IconData icon) {
    final isSelected = _gender == value;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _gender = value);
        _calculateTargets();
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricInput(String label, TextEditingController controller, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onTap: () => _selectAll(controller),
                  onChanged: (_) => _calculateTargets(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textMain),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Text(unit, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroCapsule(String label, TextEditingController controller, Color color, {bool enabled = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (enabled)
                  SizedBox(
                    width: 38,
                    child: TextField(
                      controller: controller,
                      onTap: () => _selectAll(controller),
                      onChanged: (_) => _onManualMacroChanged(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  )
                else
                  Text(
                    controller.text,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
                  ),
                const SizedBox(width: 2),
                Text('g', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
