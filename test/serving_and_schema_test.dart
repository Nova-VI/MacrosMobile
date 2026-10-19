import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/daily_log.dart';
import 'package:macro_tracker_mobile/models/food_item.dart';
import 'package:macro_tracker_mobile/models/nutrition.dart';
import 'package:macro_tracker_mobile/utils/open_food_facts_serving.dart';
import 'package:macro_tracker_mobile/utils/usda_serving.dart';

void main() {
  test(
    'Open Food Facts quantity units control serving and nutrition scaling',
    () {
      final ounces = openFoodFactsServingAmount(1, 'oz', '1 oz');
      expect(ounces, closeTo(28.3495, 0.0001));
      expect(10 * ounces / 100, closeTo(2.83495, 0.0001));
      expect(
        openFoodFactsServingAmount(1, 'fl oz', '1 fl oz'),
        closeTo(29.5735, 0.0001),
      );
      expect(openFoodFactsServingAmount(null, '', '1 bar (40 g)'), 40);
      expect(openFoodFactsServingAmount(100, 'g', '1 bar (40 g)'), 100);
      expect(openFoodFactsServingAmount(null, '', 'unknown serving'), 100);
    },
  );

  test('USDA portions preserve liquid density and ignore mass ounces', () {
    final milk = {
      'description': 'Milk',
      'foodPortions': [
        {'modifier': '1 cup', 'gramWeight': 260.2468},
      ],
    };
    expect(isUsdaLiquid(milk), isTrue);
    expect(usdaDensity(milk), closeTo(1.1, 0.0001));
    final cheese = {
      'description': 'Cheese',
      'servingSizeUnit': 'oz',
      'foodPortions': [
        {'modifier': '1 oz', 'gramWeight': 28.3495},
      ],
    };
    expect(isUsdaLiquid(cheese), isFalse);
    expect(usdaDensity(cheese), 1);
  });

  test(
    'food and dated log keep serving, density, and nutrition through storage maps',
    () {
      final food = FoodItem(
        id: 'food-1',
        name: 'Test soup',
        baseUnit: 'ml',
        servingSizeG: 240,
        density: 1.2,
        macros: const MacroNutrients(calories: 123, proteinG: 4.5),
        micros: const MicroNutrients(sodiumMg: 321),
      );
      final savedFood = FoodItem.fromFirestore(food.id, food.toMap());
      expect(savedFood.baseUnit, 'ml');
      expect(savedFood.servingSizeG, 240);
      expect(savedFood.density, 1.2);
      expect(savedFood.macros.proteinG, 4.5);
      expect(savedFood.micros.sodiumMg, 321);

      final log = DailyLog(
        id: 'log-1',
        date: '2026-10-18',
        loggedAt: '2026-10-18T09:37:15.000+02:00',
        foodId: food.id,
        foodName: food.name,
        baseUnit: food.baseUnit,
        servings: 1.5,
        servingSizeG: 360,
        macros: food.macros,
        micros: food.micros,
      );
      final savedLog = DailyLog.fromFirestore(log.id, log.toMap());
      expect(savedLog.date, '2026-10-18');
      expect(savedLog.foodId, food.id);
      expect(savedLog.servings, 1.5);
      expect(savedLog.servingSizeG, 360);
      expect(savedLog.micros.sodiumMg, 321);
    },
  );
}
