import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import 'adaptive_coach_engine.dart';
import 'coach_pipeline.dart';
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
  static final AdaptiveCoachService _instance =
      AdaptiveCoachService._internal();
  factory AdaptiveCoachService() => _instance;
  AdaptiveCoachService._internal();

  final FirestoreService _firestoreService = FirestoreService();

  final ValueNotifier<WeeklyCheckInProposal?> checkInProposalNotifier =
      ValueNotifier(null);
  final ValueNotifier<WeeklyCheckInProposal?> dismissedProposalNotifier =
      ValueNotifier(null);
  final ValueNotifier<AdaptiveCoachState?> liveObserverStateNotifier =
      ValueNotifier(null);
  final ValueNotifier<Map<String, double>> trendWeightsNotifier = ValueNotifier(
    {},
  );
  Future<void>? _recomputeInFlight;
  bool _recomputeRequested = false;
  int _recomputeRevision = 0;

  void resetState() {
    _recomputeRevision++;
    _recomputeRequested = false;
    checkInProposalNotifier.value = null;
    dismissedProposalNotifier.value = null;
    liveObserverStateNotifier.value = null;
    trendWeightsNotifier.value = {};
  }

  Future<void> recomputeAndEvaluate() {
    _recomputeRevision++;
    _recomputeRequested = true;
    return _recomputeInFlight ??= _drainRecomputations().whenComplete(() {
      _recomputeInFlight = null;
    });
  }

  Future<void> _drainRecomputations() async {
    while (_recomputeRequested) {
      _recomputeRequested = false;
      await _recomputeOnce(_recomputeRevision);
    }
  }

  Future<void> _recomputeOnce(int revision) async {
    final uid = _firestoreService.currentUid;
    if (uid == null) return;
    await _firestoreService.ensureAllMonthsLoaded();
    if (revision != _recomputeRevision || uid != _firestoreService.currentUid) {
      return;
    }

    final profile = _firestoreService.profileNotifier.value;
    final allLogs = _firestoreService.logsNotifier.value;
    final allWeights = _firestoreService.weightLogsNotifier.value;

    if (profile.goalPhases.isEmpty || (allWeights.isEmpty && allLogs.isEmpty)) {
      liveObserverStateNotifier.value = null;
      trendWeightsNotifier.value = {};
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = null;
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    final Map<String, double> dailyWeightsMap = {};
    for (final w in allWeights) {
      if (w.date.isNotEmpty) dailyWeightsMap[w.date] = w.weightKg;
    }

    final Map<String, double> dailyCaloriesMap = {};
    for (final l in allLogs) {
      if (l.date.isNotEmpty) {
        dailyCaloriesMap[l.date] =
            (dailyCaloriesMap[l.date] ?? 0.0) + l.macros.calories;
      }
    }

    final sortedWeightDates = dailyWeightsMap.keys.toList()..sort();
    final initialWeight = sortedWeightDates.isNotEmpty
        ? dailyWeightsMap[sortedWeightDates.first]!
        : (profile.weight > 0 ? profile.weight : 70.0);
    final activityValue = double.tryParse(profile.activity);
    final activityMultiplier = activityValue != null && activityValue > 0
        ? activityValue
        : 1.38;
    final replay = replayCoach(
      today: todayStr,
      initialWeightKg: initialWeight,
      heightCm: profile.height > 0 ? profile.height : 175.0,
      ageYears: profile.age,
      gender: profile.gender.isNotEmpty ? profile.gender : 'male',
      activityMultiplier: activityMultiplier,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
    );
    if (replay == null) return;
    final currentState = replay.state;
    final computedTrendWeights = replay.trendWeightsMap;

    if (revision != _recomputeRevision || uid != _firestoreService.currentUid) {
      return;
    }
    liveObserverStateNotifier.value = currentState;
    trendWeightsNotifier.value = computedTrendWeights;

    await _evaluateWeeklyCheckInEligibility(
      profile: profile,
      latestState: currentState,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
      computedTrendWeights: computedTrendWeights,
      revision: revision,
      uid: uid,
    );
  }

  Future<void> _evaluateWeeklyCheckInEligibility({
    required UserProfile profile,
    required AdaptiveCoachState latestState,
    required Map<String, double> dailyCaloriesMap,
    required Map<String, double> dailyWeightsMap,
    required Map<String, double> computedTrendWeights,
    required int revision,
    required String uid,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);

    final activePhase = profile.goalPhases.isNotEmpty
        ? profile.goalPhases.last
        : null;
    final proteinValue = double.tryParse(profile.proteinMultiplier);
    final calculation = evaluateCoachWeek(
      today: todayStr,
      phase: activePhase,
      goalOffsetKcal: double.tryParse(profile.goal) ?? 0.0,
      profileWeightKg: profile.weight > 0 ? profile.weight : 70.0,
      proteinMultiplierGPerKg: proteinValue != null && proteinValue > 0
          ? proteinValue
          : 2.0,
      currentCalories: profile.activeTargetCalories,
      currentProteinG: profile.activeTargetProteinG,
      currentCarbsG: profile.activeTargetCarbsG,
      currentFatG: profile.activeTargetFatG,
      state: latestState,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
      trendWeightsMap: computedTrendWeights,
    );
    if (calculation == null) {
      checkInProposalNotifier.value = null;
      dismissedProposalNotifier.value = null;
      return;
    }

    final proposal = WeeklyCheckInProposal(
      date: calculation.date,
      proposedCalories: calculation.proposedCalories,
      proposedProteinG: calculation.proposedProteinG,
      proposedCarbsG: calculation.proposedCarbsG,
      proposedFatG: calculation.proposedFatG,
      currentCalories: calculation.currentCalories,
      currentProteinG: calculation.currentProteinG,
      currentCarbsG: calculation.currentCarbsG,
      currentFatG: calculation.currentFatG,
      currentTdeeKcal: calculation.currentTdeeKcal,
      trendWeightKg: calculation.trendWeightKg,
      rateOfLossKgPerWeek: calculation.rateOfLossKgPerWeek,
      informationGain: calculation.informationGain,
      stateSnapshot: latestState,
    );

    final prefs = await SharedPreferences.getInstance();
    if (revision != _recomputeRevision || uid != _firestoreService.currentUid) {
      return;
    }
    final dismissedDateStr = prefs.getString('dismissed_checkin_date_$uid');

    int daysSinceDismissal = 999;
    if (dismissedDateStr != null && dismissedDateStr.isNotEmpty) {
      try {
        final d = DateFormat('yyyy-MM-dd').parse(dismissedDateStr);
        daysSinceDismissal = DateTime.utc(
          today.year,
          today.month,
          today.day,
        ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
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
      final adjList = List<TargetAdjustment>.from(lastPhase.adjustments)
        ..add(newAdjustment);

      updatedPhases.add(
        GoalPhase(
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
        ),
      );
    } else {
      updatedPhases.add(
        GoalPhase(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          startDate: proposal.date,
          goal: profile.goal,
          goalType: profile.goalType,
          initialCalories: proposal.proposedCalories.toDouble(),
          initialProteinG: proposal.proposedProteinG.toDouble(),
          initialCarbsG: proposal.proposedCarbsG.toDouble(),
          initialFatG: proposal.proposedFatG.toDouble(),
          adjustments: [newAdjustment],
        ),
      );
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
      if (uid != _firestoreService.currentUid) return;

      await _firestoreService.saveSettings({'dismissed_checkin_date': null});
    }

    if (uid != _firestoreService.currentUid) return;
    await _firestoreService.saveProfile(updatedProfile);
  }

  Future<void> dismissProposal() async {
    final proposal =
        checkInProposalNotifier.value ?? dismissedProposalNotifier.value;
    final uid = _firestoreService.currentUid;

    if (proposal != null && uid != null) {
      dismissedProposalNotifier.value = proposal;
      checkInProposalNotifier.value = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dismissed_checkin_date_$uid', proposal.date);
      if (uid != _firestoreService.currentUid) return;

      await _firestoreService.saveSettings({
        'dismissed_checkin_date': proposal.date,
      });
    }
  }
}
