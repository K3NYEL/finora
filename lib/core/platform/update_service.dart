import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../update/data/github_release_repository.dart';
import '../update/domain/update_info.dart';
import '../update/services/apk_installer.dart';

export '../update/domain/update_info.dart';
export '../update/services/apk_installer.dart' show ApkInstallResult;

class UpdateService {
  const UpdateService._();

  static const GithubReleaseRepository _releaseRepository =
      GithubReleaseRepository();

  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;

    try {
      final release = await _releaseRepository.fetchLatestRelease();
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      final latestVersion = release.version;
      final latestBuild = release.build;

      debugPrint(
        '[FINORA UPDATE] Versión instalada: $currentVersion+$currentBuild',
      );
      debugPrint(
        '[FINORA UPDATE] Última release de GitHub: $latestVersion+$latestBuild',
      );

      if (!_isNewer(
        latestVersion,
        latestBuild,
        currentVersion,
        currentBuild,
      )) {
        debugPrint('[FINORA UPDATE] Finora está actualizada.');
        return null;
      }

      UpdateAsset? apk;
      if (Platform.isAndroid) {
        apk = await _selectApk(release.assets, latestVersion);
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        releaseName: release.name,
        releaseUrl:
            'https://github.com/K3NYEL/finora/releases/tag/${release.tagName}',
        mandatory: false,
        notes: _extractNotes(release.body),
        apk: apk,
      );
    } on UpdateCheckException {
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error inesperado: $e');
      debugPrint(stackTrace.toString());
      throw UpdateCheckException(
        'No se pudo comprobar la última release de Finora: $e',
      );
    }
  }

  static Future<ApkInstallResult> downloadAndInstall(
    UpdateInfo update, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    VoidCallback? onOpeningInstaller,
  }) async {
    final apk = update.apk;

    if (apk == null || apk.downloadUrl.isEmpty) {
      debugPrint(
        '[FINORA UPDATE] No hay APK disponible para este dispositivo.',
      );
      return ApkInstallResult.failed;
    }

    return ApkInstaller.downloadAndInstall(
      apk,
      onProgress: onProgress,
      onOpeningInstaller: onOpeningInstaller,
    );
  }

  static Future<UpdateAsset?> _selectApk(
    Map<String, String> assets,
    String latestVersion,
  ) async {
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

    final normalizedVersion = latestVersion.startsWith('v')
        ? latestVersion.substring(1)
        : latestVersion;

    final apkName = 'Finora_v${normalizedVersion}_${architecture}.apk';
    final downloadUrl = assets[apkName];

    if (downloadUrl == null || downloadUrl.isEmpty) {
      debugPrint(
        '[FINORA UPDATE] GitHub Release no contiene $apkName',
      );
      return null;
    }

    debugPrint('[FINORA UPDATE] APK seleccionado: $apkName');

    return UpdateAsset(
      name: apkName,
      downloadUrl: downloadUrl,
      size: 0,
    );
  }

  static List<String> _extractNotes(String body) {
    return body
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.startsWith('- '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .toList();
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