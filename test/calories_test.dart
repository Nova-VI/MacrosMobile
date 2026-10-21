import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/nutrition.dart';

void main() {
  test('rounded egg calories are automatic', () {
    expect(const MacroNutrients(calories: 69, proteinG: 6.3, carbsG: 0.4,
        fatG: 4.8).hasCalorieOverride, isFalse);
  });

  test('combined macro and calorie rounding includes the boundary', () {
    for (final calories in [68.65, 71.35]) {
      expect(MacroNutrients(calories: calories, proteinG: 17.5)
          .hasCalorieOverride, isFalse);
    }
    expect(const MacroNutrients(calories: 71.36, proteinG: 17.5)
        .hasCalorieOverride, isTrue);
  });

  test('real overrides and calories without macros are preserved', () {
    expect(const MacroNutrients(calories: 200, proteinG: 10)
        .hasCalorieOverride, isTrue);
    expect(const MacroNutrients(calories: 69).hasCalorieOverride, isTrue);
    expect(const MacroNutrients(proteinG: 10).hasCalorieOverride, isFalse);
  });
}
