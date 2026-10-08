import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  const UpdateService._();

  static const String _repository =
      'https://api.github.com/repos/K3NYEL/finora/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse(_repository),
        headers: const {
          'Accept': 'application/vnd.github+json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '[FINORA UPDATE] GitHub respondió ${response.statusCode}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final latestTag = data['tag_name'] as String?;
      final releaseName = data['name'] as String?;
      final releaseUrl = data['html_url'] as String?;

      if (latestTag == null) {
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint(
        '[FINORA UPDATE] Versión instalada detectada: '
        '${packageInfo.version}+${packageInfo.buildNumber}',
      );

      debugPrint(
        '[FINORA UPDATE] Última versión de GitHub: $latestTag',
      );
      if (!_isNewerVersion(latestTag, currentVersion)) {
        debugPrint(
          '[FINORA UPDATE] Finora está actualizada ($currentVersion)',
        );
        return null;
      }

      final assets = (data['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(UpdateAsset.fromJson)
          .toList();

      final apk = await _selectApk(assets);

      if (apk == null) {
        debugPrint(
          '[FINORA UPDATE] No hay un APK compatible con este dispositivo.',
        );
        return null;
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestTag,
        releaseName: releaseName ?? latestTag,
        releaseUrl: releaseUrl,
        apk: apk,
      );
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  static Future<bool> downloadAndInstall(UpdateInfo update) async {
    if (!Platform.isAndroid) {
      return false;
    }

    final apk = update.apk;

    if (apk == null || apk.downloadUrl.isEmpty) {
      debugPrint(
        '[FINORA UPDATE] No hay APK disponible para este dispositivo.',
      );
      return false;
    }

    try {
      debugPrint(
        '[FINORA UPDATE] Descargando ${apk.name}...',
      );

      final directory = await getTemporaryDirectory();

      final apkFile = File(
        '${directory.path}/${apk.name}',
      );

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final response = await http
          .get(Uri.parse(apk.downloadUrl))
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        debugPrint(
          '[FINORA UPDATE] Error HTTP ${response.statusCode}',
        );
        return false;
      }

      await apkFile.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      final fileExists = await apkFile.exists();

      if (!fileExists) {
        debugPrint(
          '[FINORA UPDATE] El APK no pudo guardarse.',
        );
        return false;
      }

      debugPrint(
        '[FINORA UPDATE] APK descargado: ${apkFile.path}',
      );

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
        '[FINORA UPDATE] Instalador: ${result.type} - ${result.message}',
      );

      return result.type == ResultType.done;
    } catch (e, stackTrace) {
      debugPrint(
        '[FINORA UPDATE] Error descargando APK: $e',
      );
      debugPrint('$stackTrace');

      return false;
    }
  }

  static Future<UpdateAsset?> _selectApk(
    List<UpdateAsset> assets,
  ) async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    final abis = androidInfo.supportedAbis;

    debugPrint('[FINORA UPDATE] ABIs del dispositivo: $abis');

    String? apkName;

    if (abis.contains('arm64-v8a')) {
      apkName = 'app-arm64-v8a-release.apk';
    } else if (abis.contains('armeabi-v7a')) {
      apkName = 'app-armeabi-v7a-release.apk';
    } else if (abis.contains('x86_64')) {
      apkName = 'app-x86_64-release.apk';
    }

    if (apkName == null) {
      debugPrint(
        '[FINORA UPDATE] Arquitectura no compatible.',
      );
      return null;
    }

    for (final asset in assets) {
      if (asset.name == apkName) {
        debugPrint(
          '[FINORA UPDATE] APK seleccionado: ${asset.name}',
        );
        return asset;
      }
    }

    debugPrint(
      '[FINORA UPDATE] No se encontró $apkName en la release.',
    );

    return null;
  }

  static bool _isNewerVersion(
    String latestTag,
    String currentVersion,
  ) {
    final latest = _parseVersion(latestTag);
    final current = _parseVersion(currentVersion);

    for (var i = 0; i < 3; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }

    return false;
  }

  static List<int> _parseVersion(String version) {
    final clean = version.trim().replaceFirst('v', '');
    final parts = clean.split('.');

    return List.generate(3, (index) {
      if (index >= parts.length) return 0;

      return int.tryParse(
            parts[index].replaceAll(RegExp(r'[^0-9].*'), ''),
          ) ??
          0;
    });
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.apk,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String? releaseUrl;
  final UpdateAsset? apk;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String downloadUrl;
  final int size;
}
