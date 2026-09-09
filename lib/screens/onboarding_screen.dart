import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../models/weight_log.dart';
import '../services/auth_service.dart';
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
  static const int _totalSteps = 4;

  // Step 1: Name Controller
  final _nameController = TextEditingController();

  // Step 2: Biometrics Controllers
  DateTime _birthDate = DateTime(2001, 1, 1);
  final _heightController = TextEditingController(text: '175');
  final _weightController = TextEditingController(text: '70');
  final _targetCalController = TextEditingController(text: '2000');
  final _targetProController = TextEditingController(text: '140');
  final _targetCarbController = TextEditingController(text: '210');
  final _targetFatController = TextEditingController(text: '56');

  String _gender = 'male';
  String _activityLevel = '1.2';
  String _weeklyGoal = '0';
  String _proteinMultiplier = '2.0';

  // Step 3 & 4: API Key Controllers
  final _usdaKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  bool _includeBranded = false;
  bool _obscureUsda = true;
  bool _obscureGemini = true;

  int get _calculatedAge {
    final now = DateTime.now();
    int age = now.year - _birthDate.year;
    if (now.month < _birthDate.month || (now.month == _birthDate.month && now.day < _birthDate.day)) {
      age--;
    }
    return age > 0 ? age : 25;
  }

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
    super.dispose();
  }

  void _selectAll(TextEditingController ctrl) {
    Future.delayed(Duration.zero, () {
      if (ctrl.text.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
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

    setState(() {
      _targetCalController.text = targetCals.toString();
      _targetProController.text = protein.toString();
      _targetCarbController.text = carbs.toString();
      _targetFatController.text = fat.toString();
    });
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
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _previousPage() {
    HapticFeedback.selectionClick();
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

  Future<void> _submitStep2Biometrics() async {
    final birthDateStr = DateFormat('yyyy-MM-dd').format(_birthDate);
    final payload = UserProfile(
      id: '1',
      goalMode: 'calculator',
      targetCalories: double.tryParse(_targetCalController.text) ?? 2000.0,
      targetProteinG: double.tryParse(_targetProController.text) ?? 150.0,
      targetCarbsG: double.tryParse(_targetCarbController.text) ?? 200.0,
      targetFatG: double.tryParse(_targetFatController.text) ?? 65.0,
      birthDate: birthDateStr,
      gender: _gender,
      height: double.tryParse(_heightController.text) ?? 175.0,
      weight: double.tryParse(_weightController.text) ?? 70.0,
      activity: _activityLevel,
      goal: _weeklyGoal,
      proteinMultiplier: _proteinMultiplier,
    );

    await _firestoreService.saveProfile(payload);

    final w = double.tryParse(_weightController.text) ?? 0.0;
    if (w > 0) {
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _firestoreService.setWeightLog(WeightLog(date: todayKey, weightKg: w));
    }

    _nextPage();
  }

  Future<void> _submitStep3Usda() async {
    final usdaKey = _usdaKeyController.text.trim();
    if (usdaKey.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usda_api_key', usdaKey);
      await prefs.setBool('usda_include_branded', _includeBranded);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
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
    }
    _nextPage();
  }

  Future<void> _submitStep4GeminiAndFinish() async {
    final geminiKey = _geminiKeyController.text.trim();
    if (geminiKey.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gemini_api_key', geminiKey);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('config')
            .set({
          'gemini_api_key': geminiKey,
        }, SetOptions(merge: true));
      }
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
            // Top Progress Bar
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

            // Main Step Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentStep = idx),
                children: [
                  _buildStep1NameView(),
                  _buildStep2BiometricsView(),
                  _buildStep3UsdaView(),
                  _buildStep4GeminiView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 1: User Display Name ---
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

  // --- Step 2: Biometrics & Target Goals Calculator ---
  Widget _buildStep2BiometricsView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text(
          'Target Goals Baseline',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textMain),
        ),
        const SizedBox(height: 4),
        const Text(
          'We\'ll calculate your metabolic targets. You can accept these or customize them anytime.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
        ),
        const SizedBox(height: 16),

        // Gender Switcher
        Row(
          children: [
            Expanded(child: _buildGenderButton('Male', 'male', Icons.male_rounded)),
            const SizedBox(width: 8),
            Expanded(child: _buildGenderButton('Female', 'female', Icons.female_rounded)),
          ],
        ),
        const SizedBox(height: 12),

        // Date of Birth Selector with Auto Age
        _buildBirthDatePicker(),
        const SizedBox(height: 12),

        // Height & Weight Row
        Row(
          children: [
            Expanded(child: _buildBiometricInput('Height', _heightController, 'cm')),
            const SizedBox(width: 8),
            Expanded(child: _buildBiometricInput('Weight', _weightController, 'kg')),
          ],
        ),
        const SizedBox(height: 12),

        // Dropdowns
        _buildSelectorTile(
          label: 'Activity Level',
          value: _activityLevel,
          items: const [
            DropdownMenuItem(value: '1.2', child: Text('Sedentary (Little/no exercise)')),
            DropdownMenuItem(value: '1.375', child: Text('Lightly Active (1-3 days/wk)')),
            DropdownMenuItem(value: '1.55', child: Text('Moderately Active (3-5 days/wk)')),
            DropdownMenuItem(value: '1.725', child: Text('Very Active (6-7 days/wk)')),
            DropdownMenuItem(value: '1.9', child: Text('Athlete (Hard daily exercise)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _activityLevel = val);
              _calculateTargets();
            }
          },
        ),
        const SizedBox(height: 8),
        _buildSelectorTile(
          label: 'Goal Preset',
          value: _weeklyGoal,
          items: const [
            DropdownMenuItem(value: '-500', child: Text('Lose 2 kg/month (-500 kcal)')),
            DropdownMenuItem(value: '-250', child: Text('Lose 1 kg/month (-250 kcal)')),
            DropdownMenuItem(value: '0', child: Text('Maintain Weight (0 kcal)')),
            DropdownMenuItem(value: '250', child: Text('Gain 1 kg/month (+250 kcal)')),
            DropdownMenuItem(value: '500', child: Text('Gain 2 kg/month (+500 kcal)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _weeklyGoal = val);
              _calculateTargets();
            }
          },
        ),
        const SizedBox(height: 8),
        _buildSelectorTile(
          label: 'Protein Target Preference',
          value: _proteinMultiplier,
          items: const [
            DropdownMenuItem(value: '2.2', child: Text('High Protein (2.2g / kg)')),
            DropdownMenuItem(value: '2.0', child: Text('Moderate Protein (2.0g / kg)')),
            DropdownMenuItem(value: '1.7', child: Text('Lower Protein (1.7g / kg)')),
            DropdownMenuItem(value: '1.2', child: Text('Minimum Protein (1.2g / kg)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _proteinMultiplier = val);
              _calculateTargets();
            }
          },
        ),
        const SizedBox(height: 14),

        // Live Calculated Targets Box with Editable Calories & Macros
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CALCULATED TARGETS',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.4),
                  ),
                  Text(
                    'Tap to edit values',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Main Calorie Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Target Calories', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
                    Row(
                      children: [
                        SizedBox(
                          width: 65,
                          child: TextField(
                            controller: _targetCalController,
                            onTap: () => _selectAll(_targetCalController),
                            onChanged: _onManualCalorieChanged,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primary),
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
                        const SizedBox(width: 4),
                        const Text('kcal', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Macro Capsules with Auto-Recalculate on Change
              Row(
                children: [
                  _buildMacroCapsule('Protein', _targetProController, AppColors.protein),
                  const SizedBox(width: 8),
                  _buildMacroCapsule('Carbs', _targetCarbController, AppColors.carbs),
                  const SizedBox(width: 8),
                  _buildMacroCapsule('Fat', _targetFatController, AppColors.fat),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: _submitStep2Biometrics,
          child: const Text('Save Goals & Continue'),
        ),
      ],
    );
  }

  // --- Step 3: USDA Food Database API Key ---
  Widget _buildStep3UsdaView() {
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
          onPressed: _submitStep3Usda,
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

  // --- Step 4: Gemini AI API Key ---
  Widget _buildStep4GeminiView() {
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
          'Enables automatic emoji detection for all your food entries (including regional dishes) and smart nutrition insights.',
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
          onPressed: _submitStep4GeminiAndFinish,
          child: const Text('Complete Setup & Start'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _submitStep4GeminiAndFinish,
          child: const Text('Skip for now', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // --- Helper Widgets ---

  Widget _buildBirthDatePicker() {
    return InkWell(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picked = await showDatePicker(
          context: context,
          initialDate: _birthDate,
          firstDate: DateTime(1930),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            _birthDate = picked;
          });
          _calculateTargets();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Date of Birth',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy').format(_birthDate),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textMain),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_calculatedAge years old',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
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
                fontSize: 13,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
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
              Text(unit, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorTile({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
              style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 13),
              onChanged: onChanged,
              items: items,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroCapsule(String label, TextEditingController controller, Color color) {
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
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 38,
                  child: TextField(
                    controller: controller,
                    onTap: () => _selectAll(controller),
                    onChanged: (_) => _onManualMacroChanged(),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
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
                Text('g', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}