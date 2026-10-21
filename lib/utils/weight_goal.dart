import '../models/user_profile.dart';
import '../models/weight_log.dart';

DateTime? currentPhaseStartDate(UserProfile profile, DateTime today) {
  final todayKey = _key(today);
  final active = profile.goalPhases.where((phase) =>
      phase.startDate.compareTo(todayKey) <= 0 &&
      (phase.endDate == null || phase.endDate!.compareTo(todayKey) >= 0)).toList()
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
  return active.isEmpty ? null : DateTime.tryParse(active.first.startDate);
}

/// The same phase anchor and kcal-to-kg rate used by the weekly coach.
double? goalWeightAtDate(UserProfile profile, List<WeightLog> weights, DateTime date,
    {Map<String, double> trendWeightsMap = const {}}) {
  if (weights.isEmpty) return null;
  final dateKey = _key(date);
  final phases = List<GoalPhase>.from(profile.goalPhases)
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  GoalPhase? phase;
  for (final candidate in phases) {
    if (candidate.startDate.compareTo(dateKey) <= 0 &&
        (candidate.endDate == null || candidate.endDate!.compareTo(dateKey) >= 0)) {
      phase = candidate;
    }
  }
  final anchorDate = phase?.startDate ?? weights.first.date;
  if (dateKey.compareTo(anchorDate) < 0) return null;
  WeightLog anchor = weights.first;
  for (final weight in weights) {
    if (weight.date.compareTo(anchorDate) <= 0) {
      anchor = weight;
    } else {
      break;
    }
  }
  final exactWeight = weights.where((w) => w.date == anchorDate);
  final initialWeight = trendWeightsMap[anchorDate] ??
      (exactWeight.isNotEmpty ? exactWeight.first.weightKg : anchor.weightKg);
  final goal = double.tryParse(phase?.goal ?? profile.goal) ?? 0;
  final days = DateTime.parse('${dateKey}T00:00:00Z')
      .difference(DateTime.parse('${anchorDate}T00:00:00Z')).inDays;
  return initialWeight + goal * days / 7700;
}

double? periodTrendChange(Map<String, double> trendWeightsMap, DateTime start, DateTime end) {
  final firstKey = _key(start);
  final lastKey = _key(end);
  final dates = trendWeightsMap.keys.where((date) =>
      date.compareTo(firstKey) >= 0 && date.compareTo(lastKey) <= 0 &&
      trendWeightsMap[date]!.isFinite).toList()..sort();
  return dates.length < 2 ? null
      : trendWeightsMap[dates.last]! - trendWeightsMap[dates.first]!;
}

String _key(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
