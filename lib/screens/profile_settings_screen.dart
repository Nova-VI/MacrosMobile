import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/adaptive_coach_service.dart';
import '../theme/app_theme.dart';
import '../utils/nutrition_validation.dart';
import '../widgets/api_key_guide_sheet.dart';
import '../widgets/weekly_checkin_sheet.dart';
import 'weight_tracker_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const String _cloudinaryCloudName = 'sovwat1e';
  static const String _cloudinaryUploadPreset = 'macro_avatars';

  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  // Calculator Form Controllers
  DateTime _birthDate = DateTime(2001, 1, 1);
  final _heightController = TextEditingController(text: '175');
  final _targetCalController = TextEditingController();
  final _targetProController = TextEditingController();
  final _targetCarbController = TextEditingController();
  final _targetFatController = TextEditingController();

  // API Key Controllers
  final _usdaKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();

  String _gender = 'male';
  String _activityLevel = '1.2';
  String _weeklyGoal = '0';
  String _proteinMultiplier = '2.0';
  String _calcMethod = 'calculator';
  DateTime _goalPhaseStartDate = DateTime.now();

  // Memory baseline to preserve adaptive corrections when toggling dropdowns
  String _originalGoal = '0';
  double _originalActiveCalories = 2000.0;

  bool _obscureUsda = true;
  bool _obscureGemini = true;
  bool _includeBranded = false;
  bool _isUploadingPhoto = false;

  String? _userPhotoUrl;

  int get _calculatedAge {
    final now = DateTime.now();
    int age = now.year - _birthDate.year;
    if (now.month < _birthDate.month || (now.month == _birthDate.month && now.day < _birthDate.day)) {
      age--;
    }
    return age > 0 ? age : 25;
  }

  double get _latestWeight {
    final logs = _firestoreService.weightLogsNotifier.value;
    if (logs.isNotEmpty) {
      return logs.last.weightKg;
    }
    return _firestoreService.profileNotifier.value.weight;
  }

  double get _currentBmr {
    final age = _calculatedAge;
    final height = double.tryParse(_heightController.text) ?? 175.0;
    final weight = _latestWeight;
    if (_gender == 'male') {
      return (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      return (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }
  }

  double? get _calibratedTdee {
    return AdaptiveCoachService().liveObserverStateNotifier.value?.tdeeKcal ??
        _firestoreService.profileNotifier.value.estimatedTdee;
  }

  bool get _isEngineCalibrated {
    final tdee = _calibratedTdee;
    final hasEnoughLogs = _firestoreService.logsNotifier.value.length >= 7 ||
        _firestoreService.weightLogsNotifier.value.length >= 4;
    return tdee != null && tdee > 1000 && hasEnoughLogs;
  }

  double get _effectiveBaseTdee {
    if (_isEngineCalibrated) {
      return _calibratedTdee!;
    }
    final activity = double.tryParse(_activityLevel) ?? 1.2;
    return _currentBmr * activity;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _heightController.dispose();
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

  Future<void> _loadInitialData() async {
    final user = _authService.currentUser;
    if (user != null) {
      setState(() {
        _userPhotoUrl = user.photoURL;
      });
    }

    final p = _firestoreService.profileNotifier.value;
    DateTime phaseStart = DateTime.now();

    if (p.goalPhases.isNotEmpty) {
      try {
        phaseStart = DateFormat('yyyy-MM-dd').parse(p.goalPhases.last.startDate);
      } catch (_) {}
    }

    DateTime parsedDob = DateTime(2001, 1, 1);
    if (p.birthDate.isNotEmpty) {
      try {
        parsedDob = DateTime.parse(p.birthDate);
      } catch (_) {}
    }

    final activePhase = p.goalPhases.isNotEmpty ? p.goalPhases.last : null;
    final latestAdj = (activePhase != null && activePhase.adjustments.isNotEmpty)
        ? activePhase.adjustments.last
        : null;

    final activeCal = latestAdj?.targetCalories ?? p.targetCalories;
    final activePro = latestAdj?.targetProteinG ?? p.targetProteinG;
    final activeCarb = latestAdj?.targetCarbsG ?? p.targetCarbsG;
    final activeFat = latestAdj?.targetFatG ?? p.targetFatG;

    setState(() {
      _calcMethod = p.goalMode;
      _birthDate = parsedDob;
      _gender = p.gender;
      _heightController.text = (p.height % 1 == 0) ? p.height.toInt().toString() : p.height.toStringAsFixed(1);
      _activityLevel = p.activity;
      _weeklyGoal = p.goal;
      _proteinMultiplier = p.proteinMultiplier;
      _goalPhaseStartDate = phaseStart;

      _originalGoal = p.goal;
      _originalActiveCalories = activeCal;

      _targetCalController.text = activeCal.round().toString();
      _targetProController.text = activePro.round().toString();
      _targetCarbController.text = activeCarb.round().toString();
      _targetFatController.text = activeFat.round().toString();
    });

    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _usdaKeyController.text = prefs.getString('usda_api_key_${user.uid}') ?? '';
        _geminiKeyController.text = prefs.getString('gemini_api_key_${user.uid}') ?? '';
        _includeBranded = prefs.getBool('usda_include_branded_${user.uid}') ?? false;
      });
    }
  }

  void _performLiveCalculations({bool isMacroOnlyChange = false}) {
    final weight = _latestWeight;
    final proteinFactor = double.tryParse(_proteinMultiplier) ?? 2.0;

    double targetCalsDouble;

    if (isMacroOnlyChange) {
      // Macro changes preserve the active calorie budget
      targetCalsDouble = double.tryParse(_targetCalController.text) ?? _originalActiveCalories;
    } else {
      if (_weeklyGoal == _originalGoal) {
        // Switching back to active goal strategy preserves the adaptive check-in target (e.g. -628 kcal)
        targetCalsDouble = _originalActiveCalories;
      } else {
        // Genuine new goal strategy calculates from TDEE + Goal offset
        final goalAdjustment = double.tryParse(_weeklyGoal) ?? 0.0;
        targetCalsDouble = _effectiveBaseTdee + goalAdjustment;
      }
      _targetCalController.text = targetCalsDouble.round().toString();
    }

    final targetCals = targetCalsDouble.round();
    final protein = (weight * proteinFactor).round();
    final fat = ((targetCals * 0.25) / 9).round();
    final carbs = ((targetCals - (protein * 4) - (fat * 9)) / 4).round().clamp(0, 9999);

    setState(() {
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
      final weight = _latestWeight;
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

  void _navigateToWeightTrackerWithAutoEdit() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WeightTrackerScreen(autoEditLatest: true),
      ),
    ).then((_) {
      if (mounted) {
        _performLiveCalculations(isMacroOnlyChange: false);
      }
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null || !mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _cloudinaryUploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', image.path));

      final response = await request.send();
      final resBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
        final data = json.decode(resBody);
        final secureUrl = data['secure_url'] as String;

        await user.updatePhotoURL(secureUrl);
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'photoURL': secureUrl,
        }, SetOptions(merge: true));
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;

        setState(() {
          _userPhotoUrl = secureUrl;
        });

        HapticFeedback.mediumImpact();
        _showToast('Profile photo updated!');
      } else {
        _showToast('Photo upload failed.', isError: true);
      }
    } catch (_) {
      _showToast('Connection error uploading photo.', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showEditNameDialog(String currentName) {
    final nameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'What should we call you?',
          style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          onTap: () => _selectAll(nameController),
          style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            labelText: 'Your Name or Nickname',
            hintText: 'e.g. Alex',
          ),
          onSubmitted: (_) {
            _handleNameSave(nameController.text, currentName, ctx);
          },
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
                  onPressed: () => _handleNameSave(nameController.text, currentName, ctx),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleNameSave(String rawNewName, String currentName, BuildContext dialogContext) {
    Navigator.pop(dialogContext);
    HapticFeedback.selectionClick();

    final trimmed = rawNewName.trim();
    if (trimmed.isEmpty || trimmed == currentName.trim()) return;

    _authService.updateDisplayName(trimmed);
    _showToast('Name updated to "$trimmed"');
  }

  Future<void> _saveProfileAndGoals() async {
    final validationError = validateNutritionValues(
      positive: {'height': _heightController.text, 'calorie target': _targetCalController.text},
      nonnegative: {
        'Protein target': _targetProController.text,
        'Carb target': _targetCarbController.text,
        'Fat target': _targetFatController.text,
      },
    );
    if (validationError != null) {
      _showToast(validationError, isError: true);
      return;
    }
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final birthDateStr = DateFormat('yyyy-MM-dd').format(_birthDate);
    final currentProfile = _firestoreService.profileNotifier.value;
    final updatedPhases = List<GoalPhase>.from(currentProfile.goalPhases);

    final newCal = double.tryParse(_targetCalController.text) ?? 2000.0;
    final newPro = double.tryParse(_targetProController.text) ?? 150.0;
    final newCarb = double.tryParse(_targetCarbController.text) ?? 200.0;
    final newFat = double.tryParse(_targetFatController.text) ?? 65.0;

    final manualAdjustment = TargetAdjustment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: todayStr,
      targetCalories: newCal,
      targetProteinG: newPro,
      targetCarbsG: newCarb,
      targetFatG: newFat,
      estimatedExpenditure: _effectiveBaseTdee,
      acceptedByUser: false,
      isManual: true,
      notes: 'Manual profile settings update',
    );

    final goalChanged = currentProfile.goal != _weeklyGoal ||
        currentProfile.goalMode != _calcMethod;
    if (updatedPhases.isNotEmpty && !goalChanged) {
      final lastPhase = updatedPhases.removeLast();
      final adjList = List<TargetAdjustment>.from(lastPhase.adjustments)
        ..removeWhere((a) => a.date == todayStr)
        ..add(manualAdjustment);

      updatedPhases.add(GoalPhase(
        id: lastPhase.id,
        startDate: lastPhase.startDate,
        endDate: lastPhase.endDate,
        goal: lastPhase.goal,
        goalType: lastPhase.goalType,
        initialCalories: lastPhase.initialCalories,
        initialProteinG: lastPhase.initialProteinG,
        initialCarbsG: lastPhase.initialCarbsG,
        initialFatG: lastPhase.initialFatG,
        adjustments: adjList,
      ));
    }

    final payload = UserProfile(
      id: '1',
      goalMode: _calcMethod,
      targetCalories: newCal,
      targetProteinG: newPro,
      targetCarbsG: newCarb,
      targetFatG: newFat,
      birthDate: birthDateStr,
      gender: _gender,
      height: double.tryParse(_heightController.text) ?? 175.0,
      weight: _latestWeight,
      activity: _activityLevel,
      goal: _weeklyGoal,
      proteinMultiplier: _proteinMultiplier,
      estimatedTdee: _effectiveBaseTdee, // Never null
      goalPhases: updatedPhases,
    );

    try {
      await _firestoreService.saveProfile(payload);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _showToast('Target goals saved successfully!');
    } catch (error) {
      if (mounted) _showToast('Could not save goals: $error', isError: true);
    }
  }

  void _saveApiSettings() {
    final usdaKey = _usdaKeyController.text.trim();
    final geminiKey = _geminiKeyController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('usda_api_key_${user.uid}', usdaKey);
        prefs.setString('gemini_api_key_${user.uid}', geminiKey);
        prefs.setBool('usda_include_branded_${user.uid}', _includeBranded);
      });

      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('settings').doc('config').set({
        'usda_api_key': usdaKey,
        'gemini_api_key': geminiKey,
        'usda_include_branded': _includeBranded,
      }, SetOptions(merge: true));
    }

    HapticFeedback.mediumImpact();
    _showToast('API credentials saved!');
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
    return ValueListenableBuilder<int>(
      valueListenable: ThemeManager.notifier,
      builder: (context, _, __) {
        final user = _authService.currentUser;
        final email = user?.email ?? '';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Profile & Settings'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
              physics: const BouncingScrollPhysics(),
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: AuthService.userNameNotifier,
                  builder: (context, displayName, _) {
                    return _buildAccountCard(displayName, email);
                  },
                ),
                const SizedBox(height: 14),
                _buildAppearanceCard(),
                const SizedBox(height: 14),
                _buildGoalsCalculatorCard(),
                const SizedBox(height: 14),
                _buildIntegrationsCard(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Sign Out of Account', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () async {
                    final confirm = await _showSignOutDialog();
                    if (confirm == true && mounted) {
                      Navigator.pop(context);
                      await _authService.signOut();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppearanceCard() {
    final Map<String, Color> accents = {
      'Emerald': const Color(0xFF10B981),
      'Galaxy': const Color(0xFF3B82F6),
      'Amethyst': const Color(0xFF8B5CF6),
      'Sunset': const Color(0xFFF97316),
      'Rose': const Color(0xFFF43F5E),
    };

    final Map<String, List<Color>> backgrounds = {
      'AMOLED Black': [const Color(0xFF08080A), const Color(0xFF16161C)],
      'Midnight Blue': [const Color(0xFF0A0F1C), const Color(0xFF151C2C)],
      'Charcoal Grey': [const Color(0xFF121212), const Color(0xFF1E1E1E)],
    };

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
            'Appearance & Theme',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
          ),
          const SizedBox(height: 16),
          const Text(
            'ACCENT COLOR',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: accents.entries.map((entry) {
              final isSelected = AppColors.primary.value == entry.value.value;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ThemeManager.setAccent(entry.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: isSelected ? 2.5 : 0,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: entry.value.withValues(alpha: 0.6), blurRadius: 10, spreadRadius: 2)]
                        : [],
                  ),
                  child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            'BACKGROUND STYLE',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Column(
            children: backgrounds.entries.map((entry) {
              final bgColors = entry.value;
              final isSelected = AppColors.background.value == bgColors[0].value;

              return InkWell(
                onTap: () => ThemeManager.setBackground(bgColors[0], bgColors[1]),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgColors[1],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(color: bgColors[0], shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                          ),
                          const SizedBox(width: 10),
                          Text(entry.key, style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                      if (isSelected)  Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(String name, String email) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.background,
                backgroundImage: _userPhotoUrl != null && _userPhotoUrl!.isNotEmpty
                    ? NetworkImage(_userPhotoUrl!)
                    : null,
                child: _userPhotoUrl == null || _userPhotoUrl!.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style:  TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: _isUploadingPhoto ? null : _pickAndUploadAvatar,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: _isUploadingPhoto
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMain,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => _showEditNameDialog(name),
                      tooltip: 'Edit Name',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:  Text(
                    'Cloud Sync Active',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsCalculatorCard() {
    return ValueListenableBuilder(
      valueListenable: _firestoreService.weightLogsNotifier,
      builder: (context, _, __) {
        final currentWeight = _latestWeight;
        final baseTdeeVal = _effectiveBaseTdee;
        final isCalibrated = _isEngineCalibrated;

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
                'Target Goals Calculator',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
              const SizedBox(height: 2),
              const Text(
                'Mifflin-St Jeor metabolic baseline with adaptive adjustments',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),

              // Live TDEE Expenditure Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CALCULATED EXPENDITURE (TDEE)',
                          style: TextStyle(fontSize: 9.5, color: AppColors.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${baseTdeeVal.round()} kcal / day',
                          style:  TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCalibrated ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceHover,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCalibrated ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
                        ),
                      ),
                      child: Text(
                        isCalibrated ? 'CALIBRATED' : 'FORMULA BASELINE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isCalibrated ? AppColors.primary : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Active Goal Phase Info Pill
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ACTIVE GOAL PHASE', style: TextStyle(fontSize: 9.5, color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                        const SizedBox(height: 2),
                        Text('Active since ${DateFormat('MMM d, yyyy').format(_goalPhaseStartDate)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _weeklyGoal == '0' ? 'MAINTAIN' : (double.tryParse(_weeklyGoal)! > 0 ? 'BULK' : 'CUT'),
                        style:  TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              ValueListenableBuilder<WeeklyCheckInProposal?>(
                valueListenable: AdaptiveCoachService().dismissedProposalNotifier,
                builder: (context, proposal, _) {
                  if (proposal == null) return const SizedBox.shrink();

                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      WeeklyCheckInSheet.show(context, proposal);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text(
                                'Review Adaptive Adjustment',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                '${proposal.proposedCalories} kcal',
                                style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                              const SizedBox(width: 4),
                               Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildGenderButton('Male', 'male', Icons.male_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildGenderButton('Female', 'female', Icons.female_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildBirthDatePicker(),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildBiometricInput('Height', _heightController, 'cm'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildReadOnlyWeightTile(currentWeight),
                  ),
                ],
              ),
              const SizedBox(height: 12),

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
                    _performLiveCalculations(isMacroOnlyChange: false);
                  }
                },
              ),
              const SizedBox(height: 10),

              _buildSelectorTile(
                label: 'Goal Strategy Preset',
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
                    _performLiveCalculations(isMacroOnlyChange: false);
                  }
                },
              ),
              const SizedBox(height: 10),

              _buildSelectorTile(
                label: 'Protein Target Preference',
                value: _proteinMultiplier,
                items: const [
                  DropdownMenuItem(value: '1.2', child: Text('Minimum (1.2g / kg)')),
                  DropdownMenuItem(value: '1.4', child: Text('Low (1.4g / kg)')),
                  DropdownMenuItem(value: '1.6', child: Text('Moderate (1.6g / kg)')),
                  DropdownMenuItem(value: '1.7', child: Text('Standard (1.7g / kg)')),
                  DropdownMenuItem(value: '1.8', child: Text('Active (1.8g / kg)')),
                  DropdownMenuItem(value: '2.0', child: Text('Optimal (2.0g / kg)')),
                  DropdownMenuItem(value: '2.2', child: Text('High Protein (2.2g / kg)')),
                  DropdownMenuItem(value: '2.4', child: Text('Intense (2.4g / kg)')),
                  DropdownMenuItem(value: '2.6', child: Text('Bodybuilding (2.6g / kg)')),
                  DropdownMenuItem(value: '2.8', child: Text('Very High (2.8g / kg)')),
                  DropdownMenuItem(value: '3.0', child: Text('Maximum (3.0g / kg)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _proteinMultiplier = val);
                    // Protein modification locks the active calorie budget
                    _performLiveCalculations(isMacroOnlyChange: true);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Target Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DAILY TARGETS',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                        ),
                        Text(
                          'Tap to adjust manually',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Target Calories',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain),
                          ),
                          Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: _targetCalController,
                                  onTap: () => _selectAll(_targetCalController),
                                  onChanged: _onManualCalorieChanged,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.right,
                                  style:  TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
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
                              const SizedBox(width: 6),
                              const Text('kcal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildTargetMacroCapsule('Protein', _targetProController, AppColors.protein),
                        const SizedBox(width: 8),
                        _buildTargetMacroCapsule('Carbs', _targetCarbController, AppColors.carbs),
                        const SizedBox(width: 8),
                        _buildTargetMacroCapsule('Fat', _targetFatController, AppColors.fat),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saveProfileAndGoals,
                child: const Text('Save Target Goals'),
              ),
            ],
          ),
        );
      },
    );
  }

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
          _performLiveCalculations(isMacroOnlyChange: false);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
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
                '$_calculatedAge yrs',
                style:  TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyWeightTile(double weightKg) {
    final displayWeight = (weightKg % 1 == 0) ? weightKg.toInt().toString() : weightKg.toStringAsFixed(1);

    return InkWell(
      onTap: _navigateToWeightTrackerWithAutoEdit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
             Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Weight (Latest)', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  displayWeight,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textMain),
                ),
                const SizedBox(width: 4),
                const Text('kg', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ],
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
        _performLiveCalculations(isMacroOnlyChange: false);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : AppColors.background,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onTap: () => _selectAll(controller),
                  onChanged: (_) => _performLiveCalculations(isMacroOnlyChange: false),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textMain),
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
              Text(unit, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
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
    final safeItems = List<DropdownMenuItem<String>>.from(items);
    final exists = safeItems.any((item) => item.value == value);
    if (!exists && value.isNotEmpty) {
      safeItems.insert(
        0,
        DropdownMenuItem(
          value: value,
          child: Text('$value (Custom)'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted, size: 18),
              style: const TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w700, fontSize: 13),
              onChanged: onChanged,
              items: safeItems,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetMacroCapsule(String label, TextEditingController controller, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.3),
            ),
            const SizedBox(height: 4),
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
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
                const SizedBox(width: 2),
                Text('g', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntegrationsCard() {
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
              const Text(
                'API Keys & Database',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain),
              ),
              InkWell(
                onTap: () => ApiKeyGuideSheet.show(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child:  Row(
                    children: [
                      Icon(Icons.help_outline_rounded, size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Setup Guide',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _usdaKeyController,
            onTap: () => _selectAll(_usdaKeyController),
            obscureText: _obscureUsda,
            style: const TextStyle(color: AppColors.textMain),
            decoration: InputDecoration(
              labelText: 'USDA API Access Key',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon:  Icon(Icons.help_outline_rounded, color: AppColors.textMuted, size: 18),
                    onPressed: () => ApiKeyGuideSheet.show(context, initialService: ApiKeyType.usda),
                    tooltip: 'How to get USDA key?',
                  ),
                  IconButton(
                    icon: Icon(
                      _obscureUsda ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureUsda = !_obscureUsda),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _geminiKeyController,
            onTap: () => _selectAll(_geminiKeyController),
            obscureText: _obscureGemini,
            style: const TextStyle(color: AppColors.textMain),
            decoration: InputDecoration(
              labelText: 'Gemini AI API Key',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded, color: AppColors.textMuted, size: 18),
                    onPressed: () => ApiKeyGuideSheet.show(context, initialService: ApiKeyType.gemini),
                    tooltip: 'How to get Gemini key?',
                  ),
                  IconButton(
                    icon: Icon(
                      _obscureGemini ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          CheckboxListTile(
            value: _includeBranded,
            onChanged: (val) => setState(() => _includeBranded = val ?? false),
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Include Branded Foods in USDA Search',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain),
            ),
          ),
          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: _saveApiSettings,
            child: const Text('Save API Keys'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showSignOutDialog() {
    HapticFeedback.mediumImpact();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
        title: const Text('Sign Out', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to sign out of your account?', style: TextStyle(color: AppColors.textMuted)),
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
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
