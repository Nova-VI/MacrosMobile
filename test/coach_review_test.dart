import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/user_profile.dart';
import 'package:macro_tracker_mobile/utils/coach_review.dart';

void main() {
  TargetAdjustment adjustment(String date, double calories, bool manual) =>
      TargetAdjustment(
        id: date,
        date: date,
        targetCalories: calories,
        targetProteinG: 130,
        targetCarbsG: 300,
        targetFatG: 70,
        isManual: manual,
      );

  test('unchanged manual save does not defer a weekly review', () {
    final phase = GoalPhase(
      id: 'phase',
      startDate: '2025-02-01',
      goal: '150',
      goalType: GoalType.bulk,
      initialCalories: 2100,
      initialProteinG: 130,
      initialCarbsG: 300,
      initialFatG: 70,
      adjustments: [
        adjustment('2025-02-10', 2250, false),
        adjustment('2025-02-17', 2250, true),
      ],
    );
    expect(lastMeaningfulReviewDate(phase), '2025-02-10');
    phase.adjustments.add(adjustment('2025-02-18', 2200, true));
    expect(lastMeaningfulReviewDate(phase), '2025-02-18');
  });
}
