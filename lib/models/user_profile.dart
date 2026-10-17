import 'package:intl/intl.dart';

enum GoalType { cut, maintain, bulk }

/// Represents an individual macro & calorie target adjustment
/// (applied either via adaptive check-in or manual user override).
class TargetAdjustment {
  final String id;
  final String date; // YYYY-MM-DD
  final double targetCalories;
  final double targetProteinG;
  final double targetCarbsG;
  final double targetFatG;
  final double? estimatedExpenditure; // Estimated TDEE in kcal
  final bool acceptedByUser;
  final bool isManual;
  final String? notes;

  TargetAdjustment({
    required this.id,
    required this.date,
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatG,
    this.estimatedExpenditure,
    this.acceptedByUser = true,
    this.isManual = false,
    this.notes,
  });

  factory TargetAdjustment.fromMap(Map<String, dynamic> data) {
    return TargetAdjustment(
      id: data['id']?.toString() ?? '',
      date: data['date'] ?? '',
      targetCalories: (data['target_calories'] as num?)?.toDouble() ?? 2000.0,
      targetProteinG: (data['target_protein_g'] as num?)?.toDouble() ?? 150.0,
      targetCarbsG: (data['target_carbs_g'] as num?)?.toDouble() ?? 200.0,
      targetFatG: (data['target_fat_g'] as num?)?.toDouble() ?? 65.0,
      estimatedExpenditure: (data['estimated_expenditure'] as num?)?.toDouble(),
      acceptedByUser: data['accepted_by_user'] == true,
      isManual: data['is_manual'] == true,
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
      'is_manual': isManual,
      if (notes != null) 'notes': notes,
    };
  }
}

/// Represents a major dietary phase (e.g. Cut, Bulk, Maintenance).
class GoalPhase {
  final String id;
  final String startDate; // YYYY-MM-DD
  final String? endDate; // YYYY-MM-DD, null if active
  final String goal; // Surplus/deficit offset (e.g. '-500', '0', '+250')
  final GoalType goalType;
  final double initialCalories;
  final double initialProteinG;
  final double initialCarbsG;
  final double initialFatG;
  final List<TargetAdjustment> adjustments;

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
    this.adjustments = const [],
  });

  TargetAdjustment? get latestAdjustment => adjustments.isNotEmpty ? adjustments.last : null;

  double get currentCalories => latestAdjustment?.targetCalories ?? initialCalories;
  double get currentProteinG => latestAdjustment?.targetProteinG ?? initialProteinG;
  double get currentCarbsG => latestAdjustment?.targetCarbsG ?? initialCarbsG;
  double get currentFatG => latestAdjustment?.targetFatG ?? initialFatG;

  factory GoalPhase.fromMap(Map<String, dynamic> data) {
    final rawAdjustments = (data['adjustments'] ?? data['weekly_adjustments']) as List<dynamic>? ?? [];
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
      adjustments: rawAdjustments
          .map((e) => TargetAdjustment.fromMap(Map<String, dynamic>.from(e)))
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
      'adjustments': adjustments.map((e) => e.toMap()).toList(),
    };
  }
}

/// Resolved target representation for any given day in history.
class DayTarget {
  final String date;
  final double targetCalories;
  final double targetProteinG;
  final double targetCarbsG;
  final double targetFatG;
  final String goal;
  final GoalType goalType;

  DayTarget({
    required this.date,
    required this.targetCalories,
    required this.targetProteinG,
    required this.targetCarbsG,
    required this.targetFatG,
    required this.goal,
    required this.goalType,
  });
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
  final double? estimatedTdee; // In-memory calibrated expenditure synced to Firestore
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
    this.estimatedTdee,
    this.goalPhases = const [],
  });

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

  TargetAdjustment? get latestAdjustment {
    if (goalPhases.isNotEmpty && goalPhases.last.adjustments.isNotEmpty) {
      return goalPhases.last.adjustments.last;
    }
    return null;
  }

  double get activeTargetCalories => latestAdjustment?.targetCalories ?? targetCalories;
  double get activeTargetProteinG => latestAdjustment?.targetProteinG ?? targetProteinG;
  double get activeTargetCarbsG => latestAdjustment?.targetCarbsG ?? targetCarbsG;
  double get activeTargetFatG => latestAdjustment?.targetFatG ?? targetFatG;

  factory UserProfile.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return UserProfile();

    final rawPhases = (data['goal_phases'] ?? data['phases']) as List<dynamic>? ?? [];
    final parsedPhases = rawPhases
        .map((e) => GoalPhase.fromMap(Map<String, dynamic>.from(e)))
        .toList();

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
      estimatedTdee: (data['estimated_tdee'] as num?)?.toDouble(),
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
      if (estimatedTdee != null) 'estimated_tdee': estimatedTdee,
      'goal_phases': goalPhases.map((e) => e.toMap()).toList(),
    };
  }
}

List<GoalPhase> buildGoalPhasesForSave(
    UserProfile currentProfile, UserProfile newProfile, String todayStr) {
  final phases = List<GoalPhase>.from(
    newProfile.goalPhases.isNotEmpty
        ? newProfile.goalPhases
        : currentProfile.goalPhases,
  );
  final goalChanged = currentProfile.goal != newProfile.goal ||
      currentProfile.goalMode != newProfile.goalMode || phases.isEmpty;
  if (!goalChanged) return phases;

  if (phases.isNotEmpty && phases.last.endDate == null) {
    final last = phases.removeLast();
    if (last.startDate != todayStr) {
      final today = DateTime.parse(todayStr);
      final yesterday = DateFormat('yyyy-MM-dd').format(
        DateTime.utc(today.year, today.month, today.day - 1),
      );
      phases.add(GoalPhase(
        id: last.id,
        startDate: last.startDate,
        endDate: yesterday,
        goal: last.goal,
        goalType: last.goalType,
        initialCalories: last.initialCalories,
        initialProteinG: last.initialProteinG,
        initialCarbsG: last.initialCarbsG,
        initialFatG: last.initialFatG,
        adjustments: last.adjustments,
      ));
    }
  }

  phases.add(GoalPhase(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    startDate: todayStr,
    goal: newProfile.goal,
    goalType: newProfile.goalType,
    initialCalories: newProfile.targetCalories,
    initialProteinG: newProfile.targetProteinG,
    initialCarbsG: newProfile.targetCarbsG,
    initialFatG: newProfile.targetFatG,
  ));
  return phases;
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

  DayTarget getTargetForDate(String dateStr, {String? earliestLogDate}) {
    if (goalPhases.isNotEmpty) {
      final sortedPhases = List<GoalPhase>.from(goalPhases)
        ..sort((a, b) => b.startDate.compareTo(a.startDate));

      for (final phase in sortedPhases) {
        final afterStart = dateStr.compareTo(phase.startDate) >= 0;
        final beforeEnd = phase.endDate == null || dateStr.compareTo(phase.endDate!) <= 0;
        if (afterStart && beforeEnd) {
          if (phase.adjustments.isNotEmpty) {
            final sortedAdj = List<TargetAdjustment>.from(phase.adjustments)
              ..sort((a, b) => a.date.compareTo(b.date));
            TargetAdjustment? matchedAdj;
            for (final adj in sortedAdj) {
              if (adj.date.compareTo(dateStr) <= 0) {
                matchedAdj = adj;
              } else {
                break;
              }
            }
            if (matchedAdj != null) {
              return DayTarget(
                date: matchedAdj.date,
                targetCalories: matchedAdj.targetCalories,
                targetProteinG: matchedAdj.targetProteinG,
                targetCarbsG: matchedAdj.targetCarbsG,
                targetFatG: matchedAdj.targetFatG,
                goal: phase.goal,
                goalType: phase.goalType,
              );
            }
          }
          return DayTarget(
            date: phase.startDate,
            targetCalories: phase.initialCalories,
            targetProteinG: phase.initialProteinG,
            targetCarbsG: phase.initialCarbsG,
            targetFatG: phase.initialFatG,
            goal: phase.goal,
            goalType: phase.goalType,
          );
        }
      }
    }

    return DayTarget(
      date: earliestLogDate ?? dateStr,
      targetCalories: targetCalories,
      targetProteinG: targetProteinG,
      targetCarbsG: targetCarbsG,
      targetFatG: targetFatG,
      goal: goal,
      goalType: goalType,
    );
  }
}
