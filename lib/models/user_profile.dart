class GoalHistoryEntry {
  final String date;
  final double targetCalories;
  final double targetProteinG;
  final double targetCarbsG;
  final double targetFatG;
  final String goal;

  GoalHistoryEntry({
    required this.date,
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatG,
    required this.goal,
  });

  factory GoalHistoryEntry.fromMap(Map<String, dynamic> data) {
    return GoalHistoryEntry(
      date: data['date'] ?? '',
      targetCalories: (data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      targetProteinG: (data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      targetCarbsG: (data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      targetFatG: (data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      goal: data['goal']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'target_calories': targetCalories,
      'target_protein_g': targetProteinG,
      'target_carbs_g': targetCarbsG,
      'target_fat_g': targetFatG,
      'goal': goal,
    };
  }

  GoalType get goalType {
    final val = double.tryParse(goal) ?? 0.0;
    if (val < -50) return GoalType.cut;
    if (val > 50) return GoalType.bulk;
    return GoalType.maintain;
  }
}

class UserProfile {
  final String id;
  final String goalMode;
  final double targetCalories;
  final double targetProteinG;
  final double targetCarbsG;
  final double targetFatG;
  final int age;
  final String gender;
  final double height;
  final double weight;
  final String activity;
  final String goal;
  final String proteinMultiplier;
  final List<GoalHistoryEntry> goalHistory;

  UserProfile({
    this.id = '1',
    this.goalMode = 'calculator',
    this.targetCalories = 2000.0,
    this.targetProteinG = 150.0,
    this.targetCarbsG = 200.0,
    this.targetFatG = 65.0,
    this.age = 25,
    this.gender = 'male',
    this.height = 175.0,
    this.weight = 70.0,
    this.activity = '1.2',
    this.goal = '0',
    this.proteinMultiplier = '2.0',
    this.goalHistory = const [],
  });

  factory UserProfile.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return UserProfile();

    final rawHistory = data['goal_history'] as List<dynamic>? ?? [];
    final parsedHistory = rawHistory
        .map((e) => GoalHistoryEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return UserProfile(
      id: data['id']?.toString() ?? '1',
      goalMode: data['goal_mode'] ?? 'calculator',
      targetCalories: (data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      targetProteinG: (data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      targetCarbsG: (data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      targetFatG: (data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      age: (data['age'] as num?)?.toInt() ?? 25,
      gender: data['gender'] ?? 'male',
      height: (data['height'] as num?)?.toDouble() ?? 175.0,
      weight: (data['weight'] as num?)?.toDouble() ?? 70.0,
      activity: data['activity']?.toString() ?? '1.2',
      goal: data['goal']?.toString() ?? '0',
      proteinMultiplier: data['protein_multiplier']?.toString() ?? '2.0',
      goalHistory: parsedHistory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'goal_mode': goalMode,
      'target_calories': targetCalories,
      'target_protein_g': targetProteinG,
      'target_carbs_g': targetCarbsG,
      'target_fat_g': targetFatG,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'activity': activity,
      'goal': goal,
      'protein_multiplier': proteinMultiplier,
      'goal_history': goalHistory.map((e) => e.toMap()).toList(),
    };
  }
}

enum GoalType { cut, maintain, bulk }

extension UserProfileGoalExtension on UserProfile {
  GoalType get goalType {
    final val = double.tryParse(goal) ?? 0.0;
    if (val < -50) return GoalType.cut;
    if (val > 50) return GoalType.bulk;
    return GoalType.maintain;
  }

  String get goalTypeLabel {
    switch (goalType) {
      case GoalType.cut:
        return 'Weight Loss (Cut)';
      case GoalType.bulk:
        return 'Weight Gain (Bulk)';
      case GoalType.maintain:
        return 'Maintenance';
    }
  }

  /// Strictly returns whatever goal was configured and active on [dateStr]
  GoalHistoryEntry getTargetForDate(String dateStr, {String? earliestLogDate}) {
    if (goalHistory.isEmpty) {
      return GoalHistoryEntry(
        date: earliestLogDate ?? dateStr,
        targetCalories: targetCalories,
        targetProteinG: targetProteinG,
        targetCarbsG: targetCarbsG,
        targetFatG: targetFatG,
        goal: goal,
      );
    }

    final sorted = List<GoalHistoryEntry>.from(goalHistory)
      ..sort((a, b) => a.date.compareTo(b.date));

    GoalHistoryEntry? matched;
    for (final entry in sorted) {
      if (entry.date.compareTo(dateStr) <= 0) {
        matched = entry;
      } else {
        break;
      }
    }

    // If dateStr is before the first recorded change, return the earliest configured goal
    return matched ?? sorted.first;
  }
}