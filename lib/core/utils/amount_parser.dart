/// Parses monetary input entered with either decimal comma or decimal point.
///
/// Examples: "1234.56", "1,234.56", "1.234,56" and "123,45".
double? parseAmount(String input) {
  var value = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;

  final comma = value.lastIndexOf(',');
  final dot = value.lastIndexOf('.');

  if (comma >= 0 && dot >= 0) {
    // The last separator is treated as the decimal separator.
    if (comma > dot) {
      value = value.replaceAll('.', '').replaceFirst(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }
  } else if (comma >= 0) {
    value = value.replaceAll(',', '.');
  }

  final amount = double.tryParse(value);
  if (amount == null || !amount.isFinite) return null;
  return amount;
}
