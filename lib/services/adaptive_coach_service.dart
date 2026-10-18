import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import 'adaptive_coach_engine.dart';
import 'firestore_service.dart';
import '../utils/calendar_date.dart';

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
  final ValueNotifier<Map<String, double>> trendWeightsNotifier = ValueNotifier({});

  void resetState() {
    checkInProposalNotifier.value = null;
    dismissedProposalNotifier.value = null;
    liveObserverStateNotifier.value = null;
    trendWeightsNotifier.value = {};
  }

  Future<void> recomputeAndEvaluate() async {
    await _firestoreService.ensureAllMonthsLoaded();

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
    final Map<String, double> computedTrendWeights = {};

    while (!cursor.isAfter(today)) {
      final dateKey = DateFormat('yyyy-MM-dd').format(cursor);
      final weightReading = dailyWeightsMap[dateKey];

      // True 14-calendar-day lookback [t-14 ... t-1]
      int validCount = 0;
      double sumValidCals = 0.0;

      for (int i = 1; i <= 14; i++) {
        final lookbackDate = addCalendarDays(cursor, -i);
        final lookbackKey = DateFormat('yyyy-MM-dd').format(lookbackDate);
        final dayCal = dailyCaloriesMap[lookbackKey] ?? 0.0;

        if (dayCal >= 450.0) {
          validCount++;
          sumValidCals += dayCal;
        }
      }

      final validMean = validCount > 0 ? (sumValidCals / validCount) : 0.0;

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

      computedTrendWeights[dateKey] = currentState.estimatedMassKg;

      studyDay++;
      cursor = addCalendarDays(cursor, 1);
    }

    liveObserverStateNotifier.value = currentState;
    trendWeightsNotifier.value = computedTrendWeights;

    await _evaluateWeeklyCheckInEligibility(
      profile: profile,
      latestState: currentState,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
      computedTrendWeights: computedTrendWeights,
    );
  }

  Future<void> _evaluateWeeklyCheckInEligibility({
    required UserProfile profile,
    required AdaptiveCoachState latestState,
    required Map<String, double> dailyCaloriesMap,
    required Map<String, double> dailyWeightsMap,
    required Map<String, double> computedTrendWeights,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = _firestoreService.currentUid;

    final activePhase = profile.goalPhases.isNotEmpty ? profile.goalPhases.last : null;
    DateTime lastCheckInDate = addCalendarDays(today, -8);

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

    final daysSinceLastReview = calendarDaysBetween(lastCheckInDate, today);
    if (daysSinceLastReview < 7) {
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = null;
      return;
    }

    int validCalCount7d = 0;
    int validWeightCount7d = 0;

    for (int i = 1; i <= 7; i++) {
      final dKey = DateFormat('yyyy-MM-dd').format(addCalendarDays(today, -i));
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

    // Fix: Resolve true historical starting weight at the phase start date
    double initialPhaseMass = profile.weight;
    if (activePhase != null) {
      final phaseStartDateKey = activePhase.startDate;
      if (dailyWeightsMap.containsKey(phaseStartDateKey)) {
        initialPhaseMass = dailyWeightsMap[phaseStartDateKey]!;
      } else if (computedTrendWeights.containsKey(phaseStartDateKey)) {
        initialPhaseMass = computedTrendWeights[phaseStartDateKey]!;
      } else {
        // Fallback: look for the closest recorded weight on or prior to phase start
        final sortedDates = dailyWeightsMap.keys.toList()..sort();
        String? closestDate;
        for (final d in sortedDates) {
          if (d.compareTo(phaseStartDateKey) <= 0) {
            closestDate = d;
          } else {
            break;
          }
        }
        if (closestDate != null) {
          initialPhaseMass = dailyWeightsMap[closestDate]!;
        } else if (sortedDates.isNotEmpty) {
          initialPhaseMass = dailyWeightsMap[sortedDates.first]!;
        } else {
          initialPhaseMass = profile.weight;
        }
      }
    }

    final phaseDaysElapsed = activePhase != null
        ? calendarDaysBetween(DateFormat('yyyy-MM-dd').parse(activePhase.startDate), today)
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
    final dismissedDateStr = uid != null ? prefs.getString('dismissed_checkin_date_$uid') : null;

    int daysSinceDismissal = 999;
    if (dismissedDateStr != null && dismissedDateStr.isNotEmpty) {
      try {
        final d = DateFormat('yyyy-MM-dd').parse(dismissedDateStr);
        daysSinceDismissal = calendarDaysBetween(d, today);
      } catch (_) {}
    }

    if (daysSinceDismissal < 7) {
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

      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('config')
          .set({
        'dismissed_checkin_date': null,
      }, SetOptions(merge: true));
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

      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('config')
          .set({
        'dismissed_checkin_date': proposal.date,
      }, SetOptions(merge: true));
    }
  }
}
