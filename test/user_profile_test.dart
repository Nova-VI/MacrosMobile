import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/user_profile.dart';

void main() {
  test('latest same-day adjustment wins for its date and later dates', () {
    final profile = UserProfile(targetCalories: 2600, goalPhases: [
      GoalPhase(
        id: 'phase', startDate: '2025-01-01', goal: '250',
        goalType: GoalType.bulk, initialCalories: 2500,
        initialProteinG: 150, initialCarbsG: 300, initialFatG: 80,
        adjustments: [
          TargetAdjustment(id: 'one', date: '2025-01-08', targetCalories: 2600,
              targetProteinG: 150, targetCarbsG: 300, targetFatG: 80),
          TargetAdjustment(id: 'two', date: '2025-01-15', targetCalories: 2700,
              targetProteinG: 150, targetCarbsG: 300, targetFatG: 80),
          TargetAdjustment(id: 'three', date: '2025-01-15', targetCalories: 2500,
              targetProteinG: 150, targetCarbsG: 300, targetFatG: 80),
          TargetAdjustment(id: 'four', date: '2025-01-12', targetCalories: 2650,
              targetProteinG: 150, targetCarbsG: 300, targetFatG: 80),
        ],
      ),
    ]);

    expect(profile.getTargetForDate('2025-01-14').targetCalories, 2650);
    expect(profile.getTargetForDate('2025-01-15').targetCalories, 2500);
    expect(profile.getTargetForDate('2025-01-16').targetCalories, 2500);
  });
}
