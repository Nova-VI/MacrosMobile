import '../models/user_profile.dart';

String? lastMeaningfulReviewDate(GoalPhase? phase) {
  if (phase == null) return null;
  var lastDate = phase.startDate;
  var priorCalories = phase.initialCalories;
  final adjustments = List<TargetAdjustment>.from(phase.adjustments)
    ..sort((a, b) => a.date.compareTo(b.date));
  for (final adjustment in adjustments) {
    final calories = adjustment.targetCalories;
    final changedCalories = calories.isFinite &&
        (!priorCalories.isFinite || (calories - priorCalories).abs() >= 1);
    if (!adjustment.isManual || changedCalories) lastDate = adjustment.date;
    if (calories.isFinite) priorCalories = calories;
  }
  return lastDate;
}
