import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  const UpdateService._();

  static const String _manifestUrl =
      'https://k3nyel.github.io/finora/updates/latest.json';

  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) {
      return null;
    }

    try {
      final manifestUri = Uri.parse(_manifestUrl).replace(
        queryParameters: {
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      debugPrint('[FINORA UPDATE] Consultando manifest...');
      debugPrint('[FINORA UPDATE] $manifestUri');

      final response = await http.get(
        manifestUri,
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
          '[FINORA UPDATE] Manifest respondió ${response.statusCode}',
        );
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final latestVersion = data['version'] as String?;
      final build = (data['build'] as num?)?.toInt();
      final release = data['release'] as String?;
      final mandatory = data['mandatory'] as bool? ?? false;

      if (latestVersion == null || build == null) {
        debugPrint(
          '[FINORA UPDATE] Manifest inválido: faltan version/build.',
        );
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint(
        '[FINORA UPDATE] Versión instalada: '
        '$currentVersion+$currentBuild',
      );

      debugPrint(
        '[FINORA UPDATE] Última versión: '
        '$latestVersion+$build',
      );

      if (!_isNewer(
        latestVersion,
        build,
        currentVersion,
        currentBuild,
      )) {
        debugPrint('[FINORA UPDATE] Finora está actualizada.');
        return null;
      }

      debugPrint('[FINORA UPDATE] Nueva versión disponible.');

      UpdateAsset? apk;

      if (Platform.isAndroid) {
        apk = await _selectApk(data['android']);
      }

      final notes =
          (data['notes'] as List<dynamic>? ?? []).whereType<String>().toList();

      return UpdateInfo(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: latestVersion,
        latestBuild: build,
        releaseName: release ?? 'Finora $latestVersion',
        releaseUrl: 'https://github.com/K3NYEL/finora/releases',
        mandatory: mandatory,
        notes: notes,
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
      debugPrint(
        '[FINORA UPDATE] La instalación automática '
        'solo está disponible en Android.',
      );
      return false;
    }

    final apk = update.apk;

    if (apk == null || apk.downloadUrl.isEmpty) {
      debugPrint('[FINORA UPDATE] No hay APK disponible.');
      return false;
    }

    try {
      debugPrint('[FINORA UPDATE] Descargando ${apk.name}...');

      final directory = await getTemporaryDirectory();

      final apkFile = File('${directory.path}/${apk.name}');

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

      await apkFile.writeAsBytes(response.bodyBytes, flush: true);

      if (!await apkFile.exists()) {
        debugPrint('[FINORA UPDATE] El APK no pudo guardarse.');
        return false;
      }

      debugPrint('[FINORA UPDATE] APK descargado: ${apkFile.path}');

      final result = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
        '[FINORA UPDATE] Instalador: '
        '${result.type} - ${result.message}',
      );

      return result.type == ResultType.done;
    } catch (e, stackTrace) {
      debugPrint(
        '[FINORA UPDATE] Error instalando actualización: $e',
      );
      debugPrint('$stackTrace');
      return false;
    }
  }

  static Future<UpdateAsset?> _selectApk(dynamic androidData) async {
    if (androidData is! Map<String, dynamic>) {
      debugPrint('[FINORA UPDATE] No existe configuración Android.');
      return null;
    }

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final abis = androidInfo.supportedAbis;

    debugPrint('[FINORA UPDATE] ABIs del dispositivo: $abis');

    String? architecture;

    if (abis.contains('arm64-v8a')) {
      architecture = 'arm64-v8a';
    } else if (abis.contains('armeabi-v7a')) {
      architecture = 'armeabi-v7a';
    } else if (abis.contains('x86_64')) {
      architecture = 'x86_64';
    }

    if (architecture == null) {
      debugPrint('[FINORA UPDATE] Arquitectura no compatible.');
      return null;
    }

    final downloadUrl = androidData[architecture] as String?;

    if (downloadUrl == null || downloadUrl.isEmpty) {
      debugPrint(
        '[FINORA UPDATE] No hay APK para $architecture.',
      );
      return null;
    }

    final apkName = 'app-$architecture-release.apk';

    debugPrint('[FINORA UPDATE] APK seleccionado: $apkName');

    return UpdateAsset(
      name: apkName,
      downloadUrl: downloadUrl,
      size: 0,
    );
  }

  static bool _isNewer(
    String latestVersion,
    int latestBuild,
    String currentVersion,
    int currentBuild,
  ) {
    final latest = _parseVersion(latestVersion);
    final current = _parseVersion(currentVersion);

    for (var i = 0; i < 3; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }

    return latestBuild > currentBuild;
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
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.releaseName,
    required this.releaseUrl,
    required this.mandatory,
    required this.notes,
    required this.apk,
  });

  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String releaseName;
  final String? releaseUrl;
  final bool mandatory;
  final List<String> notes;
  final UpdateAsset? apk;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}