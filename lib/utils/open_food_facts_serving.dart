double openFoodFactsServingAmount(
  Object? rawQuantity,
  String quantityUnit,
  String rawServingSize,
) {
  final quantity = rawQuantity is num
      ? rawQuantity.toDouble()
      : double.tryParse(rawQuantity?.toString() ?? '');

  double? normalize(double amount, String unit) {
    if (!amount.isFinite || amount <= 0) return null;
    switch (unit.trim().toLowerCase()) {
      case 'g':
      case 'gram':
      case 'grams':
      case 'ml':
        return amount;
      case 'kg':
      case 'l':
        return amount * 1000;
      case 'cl':
        return amount * 10;
      case 'oz':
        return amount * 28.3495;
      case 'fl oz':
        return amount * 29.5735;
      default:
        return null;
    }
  }

  final declared = quantity == null ? null : normalize(quantity, quantityUnit);
  if (declared != null) return declared;

  final match = RegExp(
    r'([\d]+(?:[\.,][\d]+)?)\s*(fl\s*oz|kg|g|ml|cl|l|oz)\b',
    caseSensitive: false,
  ).allMatches(rawServingSize).lastOrNull;
  if (match == null) return 100.0;
  final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (amount == null) return 100.0;
  final unit = match.group(2)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return normalize(amount, unit) ?? 100.0;
}
