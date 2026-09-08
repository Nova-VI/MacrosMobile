import 'nutrition.dart';

class DailyLog {
  final String id;
  final String date;
  final String loggedAt;
  final String? foodId;
  final String foodName;
  final String servingName;
  final String baseUnit;
  final String emoji;
  final double servings;
  final double servingSizeG;
  final MacroNutrients macros;
  final MicroNutrients micros;

  DailyLog({
    required this.id,
    required this.date,
    required this.loggedAt,
    this.foodId,
    required this.foodName,
    this.servingName = '',
    this.baseUnit = 'g',
    this.emoji = '🍽️',
    this.servings = 1.0,
    this.servingSizeG = 100.0,
    required this.macros,
    required this.micros,
  });

  factory DailyLog.fromFirestore(String id, Map<String, dynamic> data) {
    return DailyLog(
      id: id,
      date: data['date'] ?? '',
      loggedAt: data['logged_at'] ?? DateTime.now().toIso8601String(),
      foodId: data['food_id']?.toString(),
      foodName: data['food_name'] ?? 'Unnamed Food',
      servingName: data['serving_name'] ?? '',
      baseUnit: data['base_unit'] ?? 'g',
      emoji: data['emoji'] ?? '🍽️',
      servings: (data['servings'] as num?)?.toDouble() ?? 1.0,
      servingSizeG: (data['serving_size_g'] as num?)?.toDouble() ?? 100.0,
      macros: MacroNutrients.fromMap(data['macros']),
      micros: MicroNutrients.fromMap(data['micros']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'logged_at': loggedAt,
      'food_id': foodId,
      'food_name': foodName,
      'serving_name': servingName,
      'base_unit': baseUnit,
      'emoji': emoji,
      'servings': servings,
      'serving_size_g': servingSizeG,
      'macros': macros.toMap(),
      'micros': micros.toMap(),
    };
  }
}