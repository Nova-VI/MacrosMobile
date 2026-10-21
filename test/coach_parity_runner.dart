import 'dart:convert';
import 'dart:io';

import 'package:macro_tracker_mobile/models/user_profile.dart';
import 'package:macro_tracker_mobile/services/coach_pipeline.dart';

Map<String, double> numbers(dynamic values) => (values as Map<String, dynamic>)
    .map((key, value) => MapEntry(key, (value as num).toDouble()));

List<Map<String, dynamic>> runCoachCases(String fixturePath) {
  final fixture =
      jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final cases = fixture['cases'] as List<dynamic>;
  final results = <Map<String, dynamic>>[];
  for (final raw in cases) {
    final item = raw as Map<String, dynamic>;
    final dailyWeightsMap = numbers(item['dailyWeightsMap']);
    final dailyCaloriesMap = numbers(item['dailyCaloriesMap']);
    final weightDates = dailyWeightsMap.keys.toList()..sort();
    final initialWeightKg = weightDates.isNotEmpty
        ? dailyWeightsMap[weightDates.first]!
        : (item['profileWeightKg'] as num).toDouble();
    final replay = replayCoach(
      today: item['today'] as String,
      initialWeightKg: initialWeightKg,
      heightCm: (item['heightCm'] as num).toDouble(),
      ageYears: (item['ageYears'] as num).toInt(),
      gender: item['gender'] as String,
      activityMultiplier: (item['activityMultiplier'] as num).toDouble(),
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
    )!;
    final phase = GoalPhase.fromMap(item['phase'] as Map<String, dynamic>);
    final proposal = evaluateCoachWeek(
      today: item['today'] as String,
      phase: phase,
      goalOffsetKcal: (item['goalOffsetKcal'] as num).toDouble(),
      profileWeightKg: (item['profileWeightKg'] as num).toDouble(),
      proteinMultiplierGPerKg: (item['proteinMultiplierGPerKg'] as num)
          .toDouble(),
      currentCalories: (item['currentCalories'] as num).toDouble(),
      currentProteinG: (item['currentProteinG'] as num).toDouble(),
      currentCarbsG: (item['currentCarbsG'] as num).toDouble(),
      currentFatG: (item['currentFatG'] as num).toDouble(),
      state: replay.state,
      dailyCaloriesMap: dailyCaloriesMap,
      dailyWeightsMap: dailyWeightsMap,
      trendWeightsMap: replay.trendWeightsMap,
    );
    results.add({
      'id': item['id'],
      'trendWeightsMap': replay.trendWeightsMap,
      'state': {
        'estimatedMassKg': replay.state.estimatedMassKg,
        'tissueVelocityKgPerDay': replay.state.tissueVelocityKgPerDay,
        'tdeeKcal': replay.state.tdeeKcal,
        'informationGain': replay.state.informationGain,
        'tissueEnthalpy': replay.state.tissueEnthalpy,
      },
      'proposal': proposal == null
          ? null
          : {
              'date': proposal.date,
              'proposedCalories': proposal.proposedCalories,
              'proposedProteinG': proposal.proposedProteinG,
              'proposedCarbsG': proposal.proposedCarbsG,
              'proposedFatG': proposal.proposedFatG,
              'currentCalories': proposal.currentCalories,
              'currentProteinG': proposal.currentProteinG,
              'currentCarbsG': proposal.currentCarbsG,
              'currentFatG': proposal.currentFatG,
              'currentTdeeKcal': proposal.currentTdeeKcal,
              'trendWeightKg': proposal.trendWeightKg,
              'rateOfLossKgPerWeek': proposal.rateOfLossKgPerWeek,
              'informationGain': proposal.informationGain,
            },
    });
  }
  return results;
}

void main(List<String> args) {
  stdout.write(jsonEncode(runCoachCases(args.single)));
}
