import '../models/user_profile.dart';
import '../utils/coach_review.dart';
import 'adaptive_coach_engine.dart';

int _day(String key) =>
    DateTime.parse('${key}T00:00:00Z').millisecondsSinceEpoch ~/ 86400000;
String _keyForDay(int day) => DateTime.fromMillisecondsSinceEpoch(
  day * 86400000,
  isUtc: true,
).toIso8601String().substring(0, 10);

class CoachReplayResult {
  final AdaptiveCoachState state;
  final Map<String, double> trendWeightsMap;
  const CoachReplayResult(this.state, this.trendWeightsMap);
}

CoachReplayResult? replayCoach({
  required String today,
  required double initialWeightKg,
  required double heightCm,
  required int ageYears,
  required String gender,
  required double activityMultiplier,
  required Map<String, double> dailyCaloriesMap,
  required Map<String, double> dailyWeightsMap,
}) {
  final dates = {...dailyWeightsMap.keys, ...dailyCaloriesMap.keys}.toList()
    ..sort();
  if (dates.isEmpty) return null;
  final initialFatMassKg = AdaptiveCoachEngine.estimateInitialFatMass(
    weightKg: initialWeightKg,
    heightCm: heightCm,
    ageYears: ageYears,
    gender: gender,
  );
  final initialTdeeKcal =
      AdaptiveCoachEngine.calculateBmr(
        weightKg: initialWeightKg,
        heightCm: heightCm,
        ageYears: ageYears,
        gender: gender,
      ) *
      activityMultiplier;
  var state = AdaptiveCoachState.initial(
    initialWeightKg: initialWeightKg,
    initialTdeeKcal: initialTdeeKcal,
    initialFatMassKg: initialFatMassKg,
  );
  final trendWeightsMap = <String, double>{};
  for (
    var date = _day(dates.first), index = 0;
    date <= _day(today);
    date++, index++
  ) {
    var validCount = 0;
    var sumValidCals = 0.0;
    for (var lag = 1; lag <= 14; lag++) {
      final calories = dailyCaloriesMap[_keyForDay(date - lag)] ?? 0.0;
      if (calories >= 450) {
        validCount++;
        sumValidCals += calories;
      }
    }
    final dateKey = _keyForDay(date);
    state = AdaptiveCoachEngine.stepObserver(
      prevState: state,
      scaleWeightLogKg: dailyWeightsMap[dateKey],
      validMeanCalories14d: validCount > 0 ? sumValidCals / validCount : 0.0,
      validIntakeDaysCount: validCount,
      initialFatMassKg: initialFatMassKg,
      heightCm: heightCm,
      ageYears: ageYears,
      gender: gender,
      studyDayIndex: index,
      activityMultiplier: activityMultiplier,
    );
    trendWeightsMap[dateKey] = state.estimatedMassKg;
  }
  return CoachReplayResult(state, trendWeightsMap);
}

class CoachWeekResult {
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

  const CoachWeekResult({
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
  });
}

CoachWeekResult? evaluateCoachWeek({
  required String today,
  required GoalPhase? phase,
  required double goalOffsetKcal,
  required double profileWeightKg,
  required double proteinMultiplierGPerKg,
  required double currentCalories,
  required double currentProteinG,
  required double currentCarbsG,
  required double currentFatG,
  required AdaptiveCoachState state,
  required Map<String, double> dailyCaloriesMap,
  required Map<String, double> dailyWeightsMap,
  required Map<String, double> trendWeightsMap,
}) {
  final lastReview = lastMeaningfulReviewDate(phase);
  if (lastReview != null && _day(today) - _day(lastReview) < 7) return null;
  var validCalories = 0;
  var validWeights = 0;
  for (var lag = 1; lag <= 7; lag++) {
    final dateKey = _keyForDay(_day(today) - lag);
    if ((dailyCaloriesMap[dateKey] ?? 0.0) >= 450) validCalories++;
    if ((dailyWeightsMap[dateKey] ?? 0.0) > 0) validWeights++;
  }
  if (validCalories < 4 || validWeights < 3 || state.informationGain < 0.20) {
    return null;
  }

  final phaseStart = phase?.startDate ?? today;
  final weightDates = dailyWeightsMap.keys.toList()..sort();
  final preceding = weightDates.where(
    (date) => date.compareTo(phaseStart) <= 0,
  );
  final fallbackWeight = weightDates.isEmpty
      ? null
      : dailyWeightsMap[preceding.isNotEmpty
            ? preceding.last
            : weightDates.first];
  final initialPhaseMassKg =
      trendWeightsMap[phaseStart] ??
      dailyWeightsMap[phaseStart] ??
      fallbackWeight ??
      profileWeightKg;
  final prescription = AdaptiveCoachEngine.synthesizePrescription(
    currentState: state,
    initialPhaseMassKg: initialPhaseMassKg,
    targetWeeklyWeightDeltaKg: goalOffsetKcal * 7 / 7700,
    phaseDayIndex: (_day(today) - _day(phaseStart)).clamp(0, 1000000),
    currentTargetCaloriesKcal: currentCalories,
    proteinMultiplierGPerKg: proteinMultiplierGPerKg,
  );
  return CoachWeekResult(
    date: today,
    proposedCalories: prescription.caloriesKcal,
    proposedProteinG: prescription.proteinG,
    proposedCarbsG: prescription.carbsG,
    proposedFatG: prescription.fatG,
    currentCalories: currentCalories.round(),
    currentProteinG: currentProteinG.round(),
    currentCarbsG: currentCarbsG.round(),
    currentFatG: currentFatG.round(),
    currentTdeeKcal: state.tdeeKcal,
    trendWeightKg: state.estimatedMassKg,
    rateOfLossKgPerWeek: state.tissueVelocityKgPerDay * 7,
    informationGain: state.informationGain,
  );
}
