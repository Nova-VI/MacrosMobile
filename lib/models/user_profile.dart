import 'package:intl/intl.dart';

enum GoalType { cut, maintain, bulk }

/// Represents a weekly micro-adjustment / check-in recommendation
/// (MacroFactor-style automated weekly adjustment).
class WeeklyGoalAdjustment {
  final String id;
  final String date; // YYYY-MM-DD of the weekly check-in
  final double targetCalories;
  final double targetProteinG;
  final double targetCarbsG;
  final double targetFatG;
  final double? estimatedExpenditure; // Estimated TDEE in kcal
  final bool acceptedByUser;
  final String? notes;

  WeeklyGoalAdjustment({
    required this.id,
    required this.date,
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatG,
    this.estimatedExpenditure,
    this.acceptedByUser = true,
    this.notes,
  });

  factory WeeklyGoalAdjustment.fromMap(Map<String, dynamic> data) {
    return WeeklyGoalAdjustment(
      id: data['id']?.toString() ?? '',
      date: data['date'] ?? '',
      targetCalories: (data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      targetProteinG: (data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      targetCarbsG: (data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      targetFatG: (data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      estimatedExpenditure: (data['estimated_expenditure'] as num?)?.toDouble(),
      acceptedByUser: data['accepted_by_user'] == true,
      notes: data['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'target_calories': targetCalories,
      'target_protein_g': targetProteinG,
      'target_carbs_g': targetCarbsG,
      'target_fat_g': targetFatG,
      'estimated_expenditure': estimatedExpenditure,
      'accepted_by_user': acceptedByUser,
      if (notes != null) 'notes': notes,
    };
  }
}

/// Represents a major dietary phase (e.g. Cut, Bulk, Maintenance).
class GoalPhase {
  final String id;
  final String startDate; // YYYY-MM-DD
  final String? endDate;   // YYYY-MM-DD, null if active
  final String goal;       // Weekly surplus/deficit offset (e.g. '-500', '0', '+250')
  final GoalType goalType;
  final double initialCalories;
  final double initialProteinG;
  final double initialCarbsG;
  final double initialFatG;
  final List<WeeklyGoalAdjustment> weeklyAdjustments;

  GoalPhase({
    required this.id,
    required this.startDate,
    this.endDate,
    required this.goal,
    required this.goalType,
    required this.initialCalories,
    required this.initialProteinG,
    required this.initialCarbsG,
    required this.initialFatG,
    this.weeklyAdjustments = const [],
  });

  factory GoalPhase.fromMap(Map<String, dynamic> data) {
    final rawAdjustments = data['weekly_adjustments'] as List<dynamic>? ?? [];
    final goalVal = data['goal']?.toString() ?? '0';

    GoalType parsedType = GoalType.maintain;
    final numVal = double.tryParse(goalVal) ?? 0.0;
    if (numVal < -50) {
      parsedType = GoalType.cut;
    } else if (numVal > 50) {
      parsedType = GoalType.bulk;
    }

    return GoalPhase(
      id: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      startDate: data['start_date'] ?? data['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
      endDate: data['end_date'],
      goal: goalVal,
      goalType: parsedType,
      initialCalories: (data['initial_calories'] ?? data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      initialProteinG: (data['initial_protein_g'] ?? data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      initialCarbsG: (data['initial_carbs_g'] ?? data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      initialFatG: (data['initial_fat_g'] ?? data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      weeklyAdjustments: rawAdjustments
          .map((e) => WeeklyGoalAdjustment.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_date': startDate,
      'end_date': endDate,
      'goal': goal,
      'goal_type': goalType.name,
      'initial_calories': initialCalories,
      'initial_protein_g': initialProteinG,
      'initial_carbs_g': initialCarbsG,
      'initial_fat_g': initialFatG,
      'weekly_adjustments': weeklyAdjustments.map((e) => e.toMap()).toList(),
    };
  }
}

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
  final String birthDate; // YYYY-MM-DD
  final String gender;
  final double height;
  final double weight;
  final String activity;
  final String goal;
  final String proteinMultiplier;
  final List<GoalHistoryEntry> goalHistory;
  final List<GoalPhase> goalPhases;

  UserProfile({
    this.id = '1',
    this.goalMode = 'calculator',
    this.targetCalories = 2000.0,
    this.targetProteinG = 150.0,
    this.targetCarbsG = 200.0,
    this.targetFatG = 65.0,
    this.birthDate = '2001-01-01',
    this.gender = 'male',
    this.height = 175.0,
    this.weight = 70.0,
    this.activity = '1.2',
    this.goal = '0',
    this.proteinMultiplier = '2.0',
    this.goalHistory = const [],
    this.goalPhases = const [],
  });

  /// Automatically computes exact age based on [birthDate]
  int get age {
    if (birthDate.isEmpty) return 25;
    try {
      final dob = DateTime.parse(birthDate);
      final now = DateTime.now();
      int calculated = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        calculated--;
      }
      return calculated > 0 ? calculated : 25;
    } catch (_) {
      return 25;
    }
  }

  factory UserProfile.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return UserProfile();

    final rawHistory = data['goal_history'] as List<dynamic>? ?? [];
    final parsedHistory = rawHistory
        .map((e) => GoalHistoryEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    final rawPhases = data['goal_phases'] as List<dynamic>? ?? [];
    final parsedPhases = rawPhases
        .map((e) => GoalPhase.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    // Backward compatibility: derive birthDate if older schema stored integer age
    String resolvedBirthDate = data['birth_date']?.toString() ?? '';
    if (resolvedBirthDate.isEmpty) {
      final legacyAge = (data['age'] as num?)?.toInt() ?? 25;
      final currentYear = DateTime.now().year;
      resolvedBirthDate = '${currentYear - legacyAge}-01-01';
    }

    return UserProfile(
      id: data['id']?.toString() ?? '1',
      goalMode: data['goal_mode'] ?? 'calculator',
      targetCalories: (data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      targetProteinG: (data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      targetCarbsG: (data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      targetFatG: (data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      birthDate: resolvedBirthDate,
      gender: data['gender'] ?? 'male',
      height: (data['height'] as num?)?.toDouble() ?? 175.0,
      weight: (data['weight'] as num?)?.toDouble() ?? 70.0,
      activity: data['activity']?.toString() ?? '1.2',
      goal: data['goal']?.toString() ?? '0',
      proteinMultiplier: data['protein_multiplier']?.toString() ?? '2.0',
      goalHistory: parsedHistory,
      goalPhases: parsedPhases,
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
      'birth_date': birthDate,
      'gender': gender,
      'height': height,
      'weight': weight,
      'activity': activity,
      'goal': goal,
      'protein_multiplier': proteinMultiplier,
      'goal_history': goalHistory.map((e) => e.toMap()).toList(),
      'goal_phases': goalPhases.map((e) => e.toMap()).toList(),
    };
  }
}

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
    // 1. First check if any subphase / weekly check-in within major phases covers this date
    if (goalPhases.isNotEmpty) {
      for (final phase in goalPhases) {
        final afterStart = dateStr.compareTo(phase.startDate) >= 0;
        final beforeEnd = phase.endDate == null || dateStr.compareTo(phase.endDate!) <= 0;
        if (afterStart && beforeEnd) {
          // If there are weekly adjustments, pick the latest adjustment prior to or on dateStr
          if (phase.weeklyAdjustments.isNotEmpty) {
            final sortedAdj = List<WeeklyGoalAdjustment>.from(phase.weeklyAdjustments)
              ..sort((a, b) => a.date.compareTo(b.date));
            WeeklyGoalAdjustment? matchedAdj;
            for (final adj in sortedAdj) {
              if (adj.date.compareTo(dateStr) <= 0) {
                matchedAdj = adj;
              } else {
                break;
              }
            }
            if (matchedAdj != null) {
              return GoalHistoryEntry(
                date: matchedAdj.date,
                targetCalories: matchedAdj.targetCalories,
                targetProteinG: matchedAdj.targetProteinG,
                targetCarbsG: matchedAdj.targetCarbsG,
                targetFatG: matchedAdj.targetFatG,
                goal: phase.goal,
              );
            }
          }
          return GoalHistoryEntry(
            date: phase.startDate,
            targetCalories: phase.initialCalories,
            targetProteinG: phase.initialProteinG,
            targetCarbsG: phase.initialCarbsG,
            targetFatG: phase.initialFatG,
            goal: phase.goal,
          );
        }
      }
    }

    // 2. Fallback to flat goal history
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

    return matched ?? sorted.first;
  }

  // =========================================================================
  // PLACEHOLDER: ADAPTIVE WEEKLY ALGORITHM
  // =========================================================================
  /// Future logic will calculate estimated expenditure by comparing weekly 
  /// scale weight trend against average daily calorie intake, then produce 
  /// a new [WeeklyGoalAdjustment] for user approval.
  WeeklyGoalAdjustment? calculateWeeklyAdaptiveAdjustment({
    required List<double> recentWeightsKg,
    required double averageCaloriesConsumed,
  }) {
    // TODO: Implement adaptive expenditure calculation & weekly macro delta
    return null;
  }
}