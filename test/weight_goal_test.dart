import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/user_profile.dart';
import 'package:macro_tracker_mobile/models/weight_log.dart';
import 'package:macro_tracker_mobile/utils/weight_goal.dart';

void main() {
  final weights = [
    WeightLog(date: '2026-10-01', weightKg: 80),
    WeightLog(date: '2026-10-08', weightKg: 79.5),
    WeightLog(date: '2026-10-15', weightKg: 79),
  ];
  final profile = UserProfile(goal: '-500', goalPhases: [
    GoalPhase(id: 'cut', startDate: '2026-10-01', endDate: '2026-10-08',
      goal: '-500', goalType: GoalType.cut, initialCalories: 2000,
      initialProteinG: 150, initialCarbsG: 200, initialFatG: 65),
    GoalPhase(id: 'bulk', startDate: '2026-10-09', goal: '250',
      goalType: GoalType.bulk, initialCalories: 2500,
      initialProteinG: 150, initialCarbsG: 250, initialFatG: 75),
  ]);

  test('goal path uses the phase anchor and goal rate', () {
    expect(goalWeightAtDate(profile, weights, DateTime(2026, 10, 1)), 80);
    expect(goalWeightAtDate(profile, weights, DateTime(2026, 10, 8)),
        closeTo(80 - 3500 / 7700, 1e-9));
    expect(goalWeightAtDate(profile, weights, DateTime(2026, 10, 16)),
        closeTo(79.5 + 1750 / 7700, 1e-9));
  });

  test('period change uses trend estimates inside the selected range', () {
    final trend = {'2026-10-01': 80.0, '2026-10-08': 79.8, '2026-10-15': 79.6};
    expect(periodTrendChange(trend, DateTime(2026, 10, 5), DateTime(2026, 10, 15)),
        closeTo(-0.2, 1e-9));
    expect(periodTrendChange(trend, DateTime(2026, 10, 9), DateTime(2026, 10, 15)), isNull);
  });

  test('phase start uses coach trend anchor without a weigh-in that day', () {
    expect(goalWeightAtDate(profile, weights, DateTime(2026, 10, 9),
        trendWeightsMap: {'2026-10-09': 79.4}), 79.4);
  });

  test('phase start prefers trend over a noisy same-day weigh-in', () {
    expect(goalWeightAtDate(profile, weights, DateTime(2026, 10, 1),
        trendWeightsMap: {'2026-10-01': 80.4}), 80.4);
  });

  test('current phase shortcut resolves only an active phase', () {
    expect(currentPhaseStartDate(profile, DateTime(2026, 10, 16)),
        DateTime(2026, 10, 9));
    expect(currentPhaseStartDate(profile, DateTime(2026, 9, 30)), isNull);
  });
}
