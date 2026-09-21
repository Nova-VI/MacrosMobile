import 'nutrition.dart';

class RecipeIngredient {
  final String? foodId;
  final int? usdaFdcId;
  final String name;
  final String emoji;
  final double quantityG;
  final String source;
  final MacroNutrients macros;
  final MicroNutrients micros;

  RecipeIngredient({
    this.foodId,
    this.usdaFdcId,
    required this.name,
    this.emoji = '🍽️',
    required this.quantityG,
    this.source = 'custom',
    required this.macros,
    required this.micros,
  });

  factory RecipeIngredient.fromMap(Map<String, dynamic> data) {
    return RecipeIngredient(
      foodId: data['food_id']?.toString(),
      usdaFdcId: (data['usda_fdc_id'] as num?)?.toInt(),
      name: data['name'] ?? '',
      emoji: data['emoji'] ?? '🍽️',
      quantityG: (data['quantity_g'] as num?)?.toDouble() ?? 0.0,
      source: data['source'] ?? 'custom',
      macros: MacroNutrients.fromMap(data['macros']),
      micros: MicroNutrients.fromMap(data['micros']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'food_id': foodId,
      'usda_fdc_id': usdaFdcId,
      'name': name,
      'emoji': emoji,
      'quantity_g': quantityG,
      'source': source,
      'macros': macros.toMap(),
      'micros': micros.toMap(),
    };
  }
}

class FoodItem {
  final String id;
  final String name;
  final String source;
  final int? usdaFdcId;
  final double servingSizeG;
  final String baseUnit;
  final double density;
  final String servingName;
  final String emoji;
  final bool isFavorite;
  final MacroNutrients macros;
  final MicroNutrients micros;
  final List<RecipeIngredient> ingredients;

  FoodItem({
    required this.id,
    required this.name,
    this.source = 'custom',
    this.usdaFdcId,
    this.servingSizeG = 100.0,
    this.baseUnit = 'g',
    this.density = 1.0,
    this.servingName = '',
    this.emoji = '🍽️',
    this.isFavorite = false,
    required this.macros,
    required this.micros,
    this.ingredients = const [],
  });

factory FoodItem.fromFirestore(String id, Map<String, dynamic>? data) {
    if (data == null || data['_deleted'] == true) {
      return FoodItem(
        id: id,
        name: '',
        macros: const MacroNutrients(),
        micros: const MicroNutrients(),
      );
    }

    final rawIngredients = data['ingredients'] as List<dynamic>? ?? [];
    return FoodItem(
      id: id,
      name: data['name'] ?? '',
      source: data['source'] ?? 'custom',
      usdaFdcId: (data['usda_fdc_id'] as num?)?.toInt(),
      servingSizeG: (data['serving_size_g'] as num?)?.toDouble() ?? 100.0,
      baseUnit: data['base_unit'] ?? 'g',
      density: (data['density'] as num?)?.toDouble() ?? 1.0,
      servingName: data['serving_name'] ?? '',
      emoji: data['emoji'] ?? '🍽️',
      isFavorite: data['is_favorite'] == true,
      macros: MacroNutrients.fromMap(data['macros'] as Map<String, dynamic>?),
      micros: MicroNutrients.fromMap(data['micros'] as Map<String, dynamic>?),
      ingredients: rawIngredients
          .map((item) => RecipeIngredient.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'source': source,
      'usda_fdc_id': usdaFdcId,
      'serving_size_g': servingSizeG,
      'base_unit': baseUnit,
      'density': density,
      'serving_name': servingName,
      'emoji': emoji,
      'is_favorite': isFavorite,
      'macros': macros.toMap(),
      'micros': micros.toMap(),
      if (ingredients.isNotEmpty)
        'ingredients': ingredients.map((i) => i.toMap()).toList(),
    };
  }
}