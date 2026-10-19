String? validateNutritionValues({
  Map<String, String> positive = const {},
  Map<String, String> nonnegative = const {},
}) {
  for (final entry in positive.entries) {
    final value = double.tryParse(entry.value.trim());
    if (value == null || !value.isFinite || value <= 0) {
      return 'Enter a positive ${entry.key}.';
    }
  }
  for (final entry in nonnegative.entries) {
    final raw = entry.value.trim();
    final value = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (value == null || !value.isFinite || value < 0) {
      return '${entry.key} cannot be negative.';
    }
  }
  return null;
}
