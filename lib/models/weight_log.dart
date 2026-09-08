class WeightLog {
  final String date;
  final double weightKg;

  WeightLog({
    required this.date,
    required this.weightKg,
  });

  factory WeightLog.fromFirestore(Map<String, dynamic> data) {
    return WeightLog(
      date: data['date'] ?? '',
      weightKg: (data['weight_kg'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'weight_kg': weightKg,
    };
  }
}