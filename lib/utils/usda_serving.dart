bool isUsdaLiquid(Map<String, dynamic> data) {
  final unit = (data['servingSizeUnit'] ?? '').toString().toLowerCase();
  final description = (data['description'] ?? '').toString().toLowerCase();
  return unit == 'ml' ||
      unit.contains('fl oz') ||
      RegExp(
        r'juice|milk|water|beverage|soda|oil|vinegar|sauce|syrup|soup|broth|drink|beer|wine|cider|fluid',
      ).hasMatch(description);
}

double usdaDensity(Map<String, dynamic> data) {
  double? inferred;
  final portions = data['foodPortions'];
  if (portions is List) {
    for (final portion in portions) {
      if (portion is! Map) continue;
      final modifier = (portion['modifier'] ?? '').toString().toLowerCase();
      final grams = (portion['gramWeight'] as num?)?.toDouble();
      if (grams == null || grams <= 0 || modifier.isEmpty) continue;
      final multiplier =
          double.tryParse(
            RegExp(r'\d+(?:\.\d+)?').firstMatch(modifier)?.group(0) ?? '',
          ) ??
          1.0;
      if (multiplier <= 0) continue;
      if (modifier.contains('cup')) {
        inferred = grams / (multiplier * 236.588);
      } else if (modifier.contains('fl') || modifier.contains('fluid')) {
        inferred = grams / (multiplier * 29.5735);
      } else if (modifier.contains('ml')) {
        inferred = grams / multiplier;
      }
      if (inferred != null) break;
    }
  }

  if (inferred == null) {
    final household = (data['householdServingFullText'] ?? '')
        .toString()
        .toLowerCase();
    final sizeValue = data['servingSize'];
    final servingSize = sizeValue is num
        ? sizeValue.toDouble()
        : double.tryParse(sizeValue?.toString() ?? '');
    final unit = (data['servingSizeUnit'] ?? '').toString().toLowerCase();
    final grams = double.tryParse(
      RegExp(r'(\d+(?:\.\d+)?)\s*g\b').firstMatch(household)?.group(1) ?? '',
    );
    final milliliters = double.tryParse(
      RegExp(r'(\d+(?:\.\d+)?)\s*ml\b').firstMatch(household)?.group(1) ?? '',
    );
    if (grams != null && milliliters != null && milliliters > 0) {
      inferred = grams / milliliters;
    } else if (servingSize != null && servingSize > 0) {
      if (unit == 'ml' && grams != null) inferred = grams / servingSize;
      if (unit == 'g' && milliliters != null && milliliters > 0) {
        inferred = servingSize / milliliters;
      }
    }
  }

  return inferred != null &&
          inferred.isFinite &&
          inferred >= 0.5 &&
          inferred <= 2.0
      ? inferred
      : 1.0;
}
