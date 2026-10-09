/// Parses monetary input entered with decimal commas or points and optional
/// thousands separators.
///
/// Examples: "1234.56", "1,234.56", "1.234,56", "123,45",
/// "1,234" and "1.234.567".
double? parseAmount(String input) {
  var value = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;

  final comma = value.lastIndexOf(',');
  final dot = value.lastIndexOf('.');

  if (comma >= 0 && dot >= 0) {
    // When both separators exist, the last one is the decimal separator.
    final decimalSeparator = comma > dot ? ',' : '.';
    final decimalIndex = value.lastIndexOf(decimalSeparator);
    final integerPart = value
        .substring(0, decimalIndex)
        .replaceAll(RegExp(r'[,.]'), '');
    final fractionalPart = value.substring(decimalIndex + 1);
    if (fractionalPart.isEmpty) return null;
    value = '$integerPart.$fractionalPart';
  } else if (comma >= 0 || dot >= 0) {
    final separator = comma >= 0 ? ',' : '.';
    final parts = value.split(separator);
    final firstPart = parts.first.replaceFirst(RegExp(r'^[+-]'), '');
    final hasThreeDigitGroups = parts.length > 1 &&
        firstPart.isNotEmpty &&
        firstPart.length <= 3 &&
        parts.skip(1).every((part) => part.length == 3);

    if (hasThreeDigitGroups) {
      // A 3-digit group is treated as a thousands separator.
      value = value.replaceAll(separator, '');
    } else if (parts.length > 2) {
      // Repeated separators: the final group is the decimal fraction.
      final integerPart = parts.take(parts.length - 1).join();
      final fractionalPart = parts.last;
      if (fractionalPart.isEmpty) return null;
      value = '$integerPart.$fractionalPart';
    } else {
      value = value.replaceFirst(separator, '.');
    }
  }

  final amount = double.tryParse(value);
  if (amount == null || !amount.isFinite) return null;
  return amount;
}
