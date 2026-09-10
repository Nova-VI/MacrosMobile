class WeightLog {
  final String date;
  final double weightKg;
  final double? trendWeightKg;

  WeightLog({
    required this.date,
    required this.weightKg,
    this.trendWeightKg,
  });

  factory WeightLog.fromFirestore(Map<String, dynamic> data) {
    return WeightLog(
      date: data['date'] ?? '',
      weightKg: (data['weight_kg'] as num?)?.toDouble() ?? 0.0,
      trendWeightKg: (data['trend_weight_kg'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'weight_kg': weightKg,
      if (trendWeightKg != null) 'trend_weight_kg': trendWeightKg,
    };
  }
}