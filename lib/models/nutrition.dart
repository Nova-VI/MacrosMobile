class MacroNutrients {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const MacroNutrients({
    this.calories = 0.0,
    this.proteinG = 0.0,
    this.carbsG = 0.0,
    this.fatG = 0.0,
  });

  factory MacroNutrients.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MacroNutrients();
    return MacroNutrients(
      calories: (data['calories'] as num?)?.toDouble() ?? 0.0,
      proteinG: (data['protein_g'] as num?)?.toDouble() ?? 0.0,
      carbsG: (data['carbs_g'] as num?)?.toDouble() ?? 0.0,
      fatG: (data['fat_g'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'calories': calories,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
    };
  }

  MacroNutrients scale(double multiplier) {
    return MacroNutrients(
      calories: calories * multiplier,
      proteinG: proteinG * multiplier,
      carbsG: carbsG * multiplier,
      fatG: fatG * multiplier,
    );
  }
}

class MicroNutrients {
  final double fiberG;
  final double sugarG;
  final double sodiumMg;
  final double saturatedFatG;
  final double cholesterolMg;
  final double potassiumMg;
  final double vitaminAUg;
  final double vitaminCMg;
  final double vitaminDUg;
  final double calciumMg;
  final double ironMg;

  const MicroNutrients({
    this.fiberG = 0.0,
    this.sugarG = 0.0,
    this.sodiumMg = 0.0,
    this.saturatedFatG = 0.0,
    this.cholesterolMg = 0.0,
    this.potassiumMg = 0.0,
    this.vitaminAUg = 0.0,
    this.vitaminCMg = 0.0,
    this.vitaminDUg = 0.0,
    this.calciumMg = 0.0,
    this.ironMg = 0.0,
  });

  factory MicroNutrients.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MicroNutrients();
    return MicroNutrients(
      fiberG: (data['fiber_g'] as num?)?.toDouble() ?? 0.0,
      sugarG: (data['sugar_g'] as num?)?.toDouble() ?? 0.0,
      sodiumMg: (data['sodium_mg'] as num?)?.toDouble() ?? 0.0,
      saturatedFatG: (data['saturated_fat_g'] as num?)?.toDouble() ?? 0.0,
      cholesterolMg: (data['cholesterol_mg'] as num?)?.toDouble() ?? 0.0,
      potassiumMg: (data['potassium_mg'] as num?)?.toDouble() ?? 0.0,
      vitaminAUg: (data['vitamin_a_ug'] as num?)?.toDouble() ?? 0.0,
      vitaminCMg: (data['vitamin_c_mg'] as num?)?.toDouble() ?? 0.0,
      vitaminDUg: (data['vitamin_d_ug'] as num?)?.toDouble() ?? 0.0,
      calciumMg: (data['calcium_mg'] as num?)?.toDouble() ?? 0.0,
      ironMg: (data['iron_mg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fiber_g': fiberG,
      'sugar_g': sugarG,
      'sodium_mg': sodiumMg,
      'saturated_fat_g': saturatedFatG,
      'cholesterol_mg': cholesterolMg,
      'potassium_mg': potassiumMg,
      'vitamin_a_ug': vitaminAUg,
      'vitamin_c_mg': vitaminCMg,
      'vitamin_d_ug': vitaminDUg,
      'calcium_mg': calciumMg,
      'iron_mg': ironMg,
    };
  }

  MicroNutrients scale(double multiplier) {
    return MicroNutrients(
      fiberG: fiberG * multiplier,
      sugarG: sugarG * multiplier,
      sodiumMg: sodiumMg * multiplier,
      saturatedFatG: saturatedFatG * multiplier,
      cholesterolMg: cholesterolMg * multiplier,
      potassiumMg: potassiumMg * multiplier,
      vitaminAUg: vitaminAUg * multiplier,
      vitaminCMg: vitaminCMg * multiplier,
      vitaminDUg: vitaminDUg * multiplier,
      calciumMg: calciumMg * multiplier,
      ironMg: ironMg * multiplier,
    );
  }
}