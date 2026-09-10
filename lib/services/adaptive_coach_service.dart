import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'adaptive_coach_engine.dart';
import 'firestore_service.dart';

class WeeklyCheckInProposal {
  final String date;
  final int proposedCalories;
  final int proposedProteinG;
  final int proposedCarbsG;
  final int proposedFatG;
  final int currentCalories;
  final int currentProteinG;
  final int currentCarbsG;
  final int currentFatG;
  final double currentTdeeKcal;
  final double trendWeightKg;
  final double rateOfLossKgPerWeek;
  final double informationGain;
  final AdaptiveCoachState stateSnapshot;

  const WeeklyCheckInProposal({
    required this.date,
    required this.proposedCalories,
    required this.proposedProteinG,
    required this.proposedCarbsG,
    required this.proposedFatG,
    required this.currentCalories,
    required this.currentProteinG,
    required this.currentCarbsG,
    required this.currentFatG,
    required this.currentTdeeKcal,
    required this.trendWeightKg,
    required this.rateOfLossKgPerWeek,
    required this.informationGain,
    required this.stateSnapshot,
  });
}

class AdaptiveCoachService {
  static final AdaptiveCoachService _instance = AdaptiveCoachService._internal();
  factory AdaptiveCoachService() => _instance;
  AdaptiveCoachService._internal();

  final FirestoreService _firestoreService = FirestoreService();

  final ValueNotifier<WeeklyCheckInProposal?> checkInProposalNotifier = ValueNotifier(null);
  final ValueNotifier<WeeklyCheckInProposal?> dismissedProposalNotifier = ValueNotifier(null);
  final ValueNotifier<AdaptiveCoachState?> liveObserverStateNotifier = ValueNotifier(null);

  /// Holds the dynamically computed trend weights (Date -> kg) derived in memory
  final ValueNotifier<Map<String, double>> trendWeightsNotifier = ValueNotifier({});

  void resetState() {
    checkInProposalNotifier.value = null;
    dismissedProposalNotifier.value = null;
    liveObserverStateNotifier.value = null;
    trendWeightsNotifier.value = {};
  }

  Future<void> recomputeAndEvaluate() async {
    final profile = _firestoreService.profileNotifier.value;
    final allLogs = _firestoreService.logsNotifier.value;
    final allWeights = _firestoreService.weightLogsNotifier.value;

    if (profile.goalPhases.isEmpty || (allWeights.isEmpty && allLogs.isEmpty)) {
      return;
    }

    final weightDates = allWeights.map((w) => w.date).where((d) => d.isNotEmpty);
    final logDates = allLogs.map((l) => l.date).where((d) => d.isNotEmpty);

    final allDates = {...weightDates, ...logDates}.toList()..sort();
    if (allDates.isEmpty) return;

    final startDateStr = allDates.first;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime cursor = DateFormat('yyyy-MM-dd').parse(startDateStr);

    final Map<String, double> dailyWeightsMap = {};
    for (final w in allWeights) {
      dailyWeightsMap[w.date] = w.weightKg;
    }

    final Map<String, double> dailyCaloriesMap = {};
    for (final l in allLogs) {
      dailyCaloriesMap[l.date] = (dailyCaloriesMap[l.date] ?? 0.0) + l.macros.calories;
    }

    final initialWeight = allWeights.isNotEmpty ? allWeights.first.weightKg : profile.weight;
    final initialFat = AdaptiveCoachEngine.estimateInitialFatMass(
      weightKg: initialWeight,
      heightCm: profile.height,
      ageYears: profile.age,
      gender: profile.gender,
    );
    final initialBmr = AdaptiveCoachEngine.calculateBmr(
      weightKg: initialWeight,
      heightCm: profile.height,
      ageYears: profile.age,
      gender: profile.gender,
    );
    final activityMultiplier = double.tryParse(profile.activity) ?? 1.38;
    final initialTdee = initialBmr * activityMultiplier;

    AdaptiveCoachState currentState = AdaptiveCoachState.initial(
      initialWeightKg: initialWeight,
      initialTdeeKcal: initialTdee,
      initialFatMassKg: initialFat,
    );

    int studyDay = 0;
    final List<double> recent14dCalories = [];
    final Map<String, double> computedTrendWeights = {};

    while (!cursor.isAfter(today)) {
      final dateKey = DateFormat('yyyy-MM-dd').format(cursor);
      final isToday = cursor.year == today.year && cursor.month == today.month && cursor.day == today.day;

      final weightReading = dailyWeightsMap[dateKey];
      final calorieTotal = dailyCaloriesMap[dateKey] ?? 0.0;

      if (!isToday && calorieTotal >= 450.0) {
        recent14dCalories.add(calorieTotal);
        if (recent14dCalories.length > 14) {
          recent14dCalories.removeAt(0);
        }
      }

      final validCount = recent14dCalories.length;
      final validMean = validCount > 0
          ? (recent14dCalories.reduce((a, b) => a + b) / validCount)
          : initialTdee;

      currentState = AdaptiveCoachEngine.stepObserver(
        prevState: currentState,
        scaleWeightLogKg: weightReading,
        validMeanCalories14d: validMean,
        validIntakeDaysCount: validCount,
        initialFatMassKg: initialFat,
        heightCm: profile.height,
        ageYears: profile.age,
        gender: profile.gender,
        studyDayIndex: studyDay,
        activityMultiplier: activityMultiplier,
      );

      // Record in-memory trend weight for every recorded day
      computedTrendWeights[dateKey] = currentState.estimatedMassKg;

      studyDay++;
      cursor = cursor.add(const Duration(days: 1));
    }

    liveObserverStateNotifier.value = currentState;
    trendWeightsNotifier.value = computedTrendWeights;

    await _evaluateWeeklyCheckInEligibility(
      profile: profile,
      latestState: currentState,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
    );
  }

  Future<void> _evaluateWeeklyCheckInEligibility({
    required UserProfile profile,
    required AdaptiveCoachState latestState,
    required Map<String, double> dailyCaloriesMap,
    required Map<String, double> dailyWeightsMap,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = _firestoreService.currentUid;

    final activePhase = profile.goalPhases.isNotEmpty ? profile.goalPhases.last : null;
    DateTime lastCheckInDate = today.subtract(const Duration(days: 8));

    if (activePhase != null) {
      if (activePhase.adjustments.isNotEmpty) {
        try {
          lastCheckInDate = DateFormat('yyyy-MM-dd').parse(activePhase.adjustments.last.date);
        } catch (_) {}
      } else {
        try {
          lastCheckInDate = DateFormat('yyyy-MM-dd').parse(activePhase.startDate);
        } catch (_) {}
      }
    }

    final daysSinceLastReview = today.difference(lastCheckInDate).inDays;
    if (daysSinceLastReview < 7) {
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = null;
      return;
    }

    int validCalCount7d = 0;
    int validWeightCount7d = 0;

    for (int i = 1; i <= 7; i++) {
      final dKey = DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i)));
      if ((dailyCaloriesMap[dKey] ?? 0.0) >= 450.0) validCalCount7d++;
      if ((dailyWeightsMap[dKey] ?? 0.0) > 0.0) validWeightCount7d++;
    }

    if (validCalCount7d < 4 || validWeightCount7d < 3 || latestState.informationGain < 0.20) {
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = null;
      return;
    }

    final goalOffset = double.tryParse(profile.goal) ?? 0.0;
    final weeklyKgDelta = (goalOffset * 7.0) / 7700.0;
    final proteinMultiplier = double.tryParse(profile.proteinMultiplier) ?? 2.0;

    final initialPhaseMass = activePhase != null
        ? (activePhase.initialCalories > 0 ? latestState.estimatedMassKg : profile.weight)
        : profile.weight;

    final phaseDaysElapsed = activePhase != null
        ? today.difference(DateFormat('yyyy-MM-dd').parse(activePhase.startDate)).inDays
        : 14;

    final prescription = AdaptiveCoachEngine.synthesizePrescription(
      currentState: latestState,
      initialPhaseMassKg: initialPhaseMass,
      targetWeeklyWeightDeltaKg: weeklyKgDelta,
      phaseDayIndex: phaseDaysElapsed,
      proteinMultiplierGPerKg: proteinMultiplier,
    );

    final proposal = WeeklyCheckInProposal(
      date: todayStr,
      proposedCalories: prescription.caloriesKcal,
      proposedProteinG: prescription.proteinG,
      proposedCarbsG: prescription.carbsG,
      proposedFatG: prescription.fatG,
      currentCalories: profile.activeTargetCalories.round(),
      currentProteinG: profile.activeTargetProteinG.round(),
      currentCarbsG: profile.activeTargetCarbsG.round(),
      currentFatG: profile.activeTargetFatG.round(),
      currentTdeeKcal: latestState.tdeeKcal,
      trendWeightKg: latestState.estimatedMassKg,
      rateOfLossKgPerWeek: latestState.tissueVelocityKgPerDay * 7.0,
      informationGain: latestState.informationGain,
      stateSnapshot: latestState,
    );

    final prefs = await SharedPreferences.getInstance();
    final dismissedDate = uid != null ? prefs.getString('dismissed_checkin_date_$uid') : null;

    if (dismissedDate == todayStr) {
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = proposal;
    } else {
      checkInProposalNotifier.value = proposal;
      dismissedProposalNotifier.value = null;
    }
  }

  Future<void> acceptProposal(WeeklyCheckInProposal proposal) async {
    final profile = _firestoreService.profileNotifier.value;
    final updatedPhases = List<GoalPhase>.from(profile.goalPhases);
    final uid = _firestoreService.currentUid;

    final newAdjustment = TargetAdjustment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: proposal.date,
      targetCalories: proposal.proposedCalories.toDouble(),
      targetProteinG: proposal.proposedProteinG.toDouble(),
      targetCarbsG: proposal.proposedCarbsG.toDouble(),
      targetFatG: proposal.proposedFatG.toDouble(),
      estimatedExpenditure: proposal.currentTdeeKcal,
      acceptedByUser: true,
      isManual: false,
    );

    if (updatedPhases.isNotEmpty) {
      final lastPhase = updatedPhases.removeLast();
      final adjList = List<TargetAdjustment>.from(lastPhase.adjustments)..add(newAdjustment);

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
    } else {
      updatedPhases.add(GoalPhase(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startDate: proposal.date,
        goal: profile.goal,
        goalType: profile.goalType,
        initialCalories: proposal.proposedCalories.toDouble(),
        initialProteinG: proposal.proposedProteinG.toDouble(),
        initialCarbsG: proposal.proposedCarbsG.toDouble(),
        initialFatG: proposal.proposedFatG.toDouble(),
        adjustments: [newAdjustment],
      ));
    }

    final updatedProfile = UserProfile(
      id: profile.id,
      goalMode: profile.goalMode,
      targetCalories: proposal.proposedCalories.toDouble(),
      targetProteinG: proposal.proposedProteinG.toDouble(),
      targetCarbsG: proposal.proposedCarbsG.toDouble(),
      targetFatG: proposal.proposedFatG.toDouble(),
      birthDate: profile.birthDate,
      gender: profile.gender,
      height: profile.height,
      weight: profile.weight,
      activity: profile.activity,
      goal: profile.goal,
      proteinMultiplier: profile.proteinMultiplier,
      estimatedTdee: proposal.currentTdeeKcal,
      goalPhases: updatedPhases,
    );

    checkInProposalNotifier.value = null;
    dismissedProposalNotifier.value = null;

    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dismissed_checkin_date_$uid');
    }

    await _firestoreService.saveProfile(updatedProfile);
  }

  Future<void> dismissProposal() async {
    final proposal = checkInProposalNotifier.value ?? dismissedProposalNotifier.value;
    final uid = _firestoreService.currentUid;

    if (proposal != null && uid != null) {
      dismissedProposalNotifier.value = proposal;
      checkInProposalNotifier.value = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dismissed_checkin_date_$uid', proposal.date);
    }
  }
}