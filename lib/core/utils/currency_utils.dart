import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _f = NumberFormat('#,##0.##');
String _currencyCode = 'DOP';

String get selectedCurrencyCode => _currencyCode;

String currencyLabel(String code) {
  switch (code) {
    case 'USD':
      return 'USD — Dólar estadounidense';
    case 'EUR':
      return 'EUR — Euro';
    default:
      return 'DOP — Peso dominicano';
  }
}

/// Load the saved display currency before the app builds.
Future<void> initializeCurrency() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('finance_currency') ?? 'DOP';
  _currencyCode = const {'DOP', 'USD', 'EUR'}.contains(saved) ? saved : 'DOP';
}

/// Updates the display symbol only; it does not convert stored amounts.
void setCurrencyCodeInMemory(String code) {
  if (const {'DOP', 'USD', 'EUR'}.contains(code)) {
    _currencyCode = code;
  }
}

String money(double value) {
  final symbol = switch (_currencyCode) {
    'USD' => r'USD$ ',
    'EUR' => '€ ',
    _ => r'RD$ ',
  };
  return symbol + _f.format(value);
}
