import 'package:flutter/foundation.dart';

/// API endpoint supplied at build time; no production server is assumed.
/// Configure with --dart-define=FINORA_API_BASE_URL=https://api.example.com
class FinoraApiConfig {
  FinoraApiConfig._();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'FINORA_API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl => _configuredBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  static bool get isConfigured {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (uri.scheme != 'https' && !_isLocalDevelopmentHost(uri.host)) return false;
    if (kReleaseMode && uri.scheme != 'https') return false;
    return true;
  }

  static Uri get baseUri {
    if (!isConfigured) {
      throw StateError('Finora API is not configured. Set FINORA_API_BASE_URL at build time.');
    }
    return Uri.parse('$baseUrl/');
  }

  static bool _isLocalDevelopmentHost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
}
