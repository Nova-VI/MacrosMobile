// Regression coverage for log editing and recipe unit conversion.
// Firebase is mocked; these tests do not contact the deployed project.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/models/daily_log.dart';
import 'package:macro_tracker_mobile/models/food_item.dart';
import 'package:macro_tracker_mobile/models/nutrition.dart';
import 'package:macro_tracker_mobile/screens/log_food_screen.dart';
import 'package:macro_tracker_mobile/screens/recipes_library_screen.dart';
import 'package:macro_tracker_mobile/services/firestore_service.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());

  testWidgets('editing a manual calorie log preserves its calorie ratio', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LogFoodScreen(
      editLog: DailyLog(
        id: 'log_1', date: '2026-10-20', loggedAt: '2026-10-20T12:00:00',
        foodName: 'Label calories', servings: 1, servingSizeG: 100,
        macros: const MacroNutrients(calories: 200, proteinG: 10),
        micros: const MicroNutrients(),
      ),
      onLogCompleted: () {},
    )));
    await tester.pump();
    await tester.ensureVisible(field('Servings Multiplier'));
    await tester.enterText(field('Servings Multiplier'), '2');
    await tester.pump();
    await tester.ensureVisible(field('Calories (kcal)'));
    final actual = tester.widget<TextField>(field('Calories (kcal)')).controller!.text;
    await tester.pumpWidget(const SizedBox());
    expect(actual, '400', reason: '200 manually entered kcal multiplied by two servings');
  });

  testWidgets('recipe gram weights account for a liquid food density', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FirestoreService().foodsNotifier.value = [FoodItem(
      id: 'food_liquid', name: 'Audit liquid', baseUnit: 'ml',
      servingSizeG: 100, density: 1.2,
      macros: const MacroNutrients(calories: 120, carbsG: 30),
      micros: const MicroNutrients(),
    )];
    await tester.pumpWidget(const MaterialApp(home: RecipesLibraryScreen(initialTabIndex: 1)));
    final search = find.byWidgetPredicate((widget) => widget is TextField &&
        widget.decoration?.hintText == 'Search or scan ingredient...');
    await tester.enterText(search, 'Audit');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Audit liquid'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Weight (g)'), '120');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final texts = tester.widgetList<Text>(find.byType(Text)).map(
      (widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '',
    ).toList();
    final calorieText = texts.where((text) => RegExp(r'^\d+cal').hasMatch(text)).toList();
    await tester.pumpWidget(const SizedBox());
    FirestoreService().foodsNotifier.value = [];
    expect(calorieText, contains('120cal  '),
      reason: '120g at 1.2g/ml = 100ml = one 120kcal serving. Actual UI: $calorieText');
  });
}
