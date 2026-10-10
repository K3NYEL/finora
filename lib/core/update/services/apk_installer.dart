import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/update_info.dart';

enum ApkInstallResult {
  opened,
  permissionRequired,
  failed,
}

class ApkInstaller {
  const ApkInstaller._();

  static const MethodChannel _installerChannel =
      MethodChannel('com.finora.app/apk_installer');
  static const int _maxApkBytes = 100 * 1024 * 1024;

  static Future<ApkInstallResult> downloadAndInstall(
    UpdateAsset apk, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    VoidCallback? onOpeningInstaller,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint(
        '[FINORA UPDATE] La instalación automática solo está disponible en Android.',
      );
      return ApkInstallResult.failed;
    }

    if (!_isTrustedReleaseAsset(apk) ||
        apk.sha256 == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(apk.sha256!) ||
        apk.size < 1 ||
        apk.size > _maxApkBytes) {
      debugPrint('[FINORA UPDATE] APK rechazado: URL, tamaño o SHA-256 no válido.');
      return ApkInstallResult.failed;
    }

    final client = http.Client();
    IOSink? sink;
    File? apkFile;
    File? partialFile;
    var installerInvoked = false;

    try {
      final directory = await getTemporaryDirectory();
      apkFile = File('\${directory.path}/\${apk.name}');
      partialFile = File('\${apkFile.path}.part');

      if (await _isCompleteApk(apkFile) &&
          await _matchesExpectedDigest(apkFile, apk)) {
        debugPrint('[FINORA UPDATE] APK en caché verificado por SHA-256.');
      } else {
        await _deleteIfExists(apkFile);
        await _deleteIfExists(partialFile);

        debugPrint('[FINORA UPDATE] Descargando \${apk.name}...');
        final request = http.Request('GET', Uri.parse(apk.downloadUrl));
        final response = await client
            .send(request)
            .timeout(const Duration(minutes: 2));

        if (response.statusCode != HttpStatus.ok) {
          debugPrint('[FINORA UPDATE] Error HTTP \${response.statusCode} al descargar APK.');
          await response.stream.drain<void>();
          return ApkInstallResult.failed;
        }

        final contentLength = response.contentLength;
        if (contentLength != null && contentLength != apk.size) {
          await response.stream.drain<void>();
          debugPrint('[FINORA UPDATE] Tamaño HTTP no coincide con el manifiesto.');
          return ApkInstallResult.failed;
        }

        var receivedBytes = 0;
        sink = partialFile.openWrite();
        onProgress?.call(0, apk.size);

        await for (final chunk
            in response.stream.timeout(const Duration(minutes: 5))) {
          receivedBytes += chunk.length;
          if (receivedBytes > apk.size || receivedBytes > _maxApkBytes) {
            throw const _InvalidApkException('La descarga excede el tamaño esperado.');
          }
          sink.add(chunk);
          onProgress?.call(receivedBytes, apk.size);
        }

        await sink.flush();
        await sink.close();
        sink = null;

        if (receivedBytes != apk.size ||
            !await _isCompleteApk(partialFile) ||
            !await _matchesExpectedDigest(partialFile, apk)) {
          debugPrint('[FINORA UPDATE] APK rechazado: tamaño, formato o SHA-256 incorrecto.');
          await _deleteIfExists(partialFile);
          return ApkInstallResult.failed;
        }

        await partialFile.rename(apkFile.path);
        debugPrint('[FINORA UPDATE] Descarga validada con SHA-256.');
      }

      onOpeningInstaller?.call();
      installerInvoked = true;
      final installerResult = await _installerChannel.invokeMethod<String>(
        'installApk',
        {'path': apkFile.path},
      );

      if (installerResult == 'opened') return ApkInstallResult.opened;
      if (installerResult == 'permission_required') {
        return ApkInstallResult.permissionRequired;
      }

      await _deleteIfExists(apkFile);
      return ApkInstallResult.failed;
    } catch (e, stackTrace) {
      debugPrint('[FINORA UPDATE] Error instalando actualización: $e');
      debugPrint('$stackTrace');
      if (installerInvoked && apkFile != null) {
        await _deleteIfExists(apkFile);
      }
      return ApkInstallResult.failed;
    } finally {
      if (sink != null) await sink.close();
      if (partialFile != null) await _deleteIfExists(partialFile);
      client.close();
    }
  }

  static bool _isTrustedReleaseAsset(UpdateAsset apk) {
    final uri = Uri.tryParse(apk.downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return false;
    }

    final namePattern = RegExp(
      r'^Finora_v[0-9]+\.[0-9]+\.[0-9]+_(arm64-v8a|armeabi-v7a|x86_64)\.apk$',
    );
    if (!namePattern.hasMatch(apk.name)) return false;

    const expectedPrefix = '/K3NYEL/finora/releases/download/';
    if (!uri.path.startsWith(expectedPrefix)) return false;
    return uri.pathSegments.isNotEmpty && uri.pathSegments.last == apk.name;
  }

  static Future<bool> _matchesExpectedDigest(
    File file,
    UpdateAsset asset,
  ) async {
    try {
      final expected = asset.sha256;
      if (expected == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
        return false;
      }
      if (!await file.exists() || await file.length() != asset.size) {
        return false;
      }
      final actual = await sha256.bind(file.openRead()).first;
      return actual.toString() == expected;
    } catch (e) {
      debugPrint('[FINORA UPDATE] No se pudo verificar SHA-256: $e');
      return false;
    }
  }

  static Future<bool> _isCompleteApk(File file) async {
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 22) return false;

      final handle = await file.open();
      try {
        final header = await handle.read(4);
        if (header.length != 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4b ||
            header[2] != 0x03 ||
            header[3] != 0x04) {
          return false;
        }

        final tailLength = length < 65557 ? length : 65557;
        await handle.setPosition(length - tailLength);
        final tail = await handle.read(tailLength);
        for (var i = 0; i <= tail.length - 4; i++) {
          if (tail[i] == 0x50 &&
              tail[i + 1] == 0x4b &&
              tail[i + 2] == 0x05 &&
              tail[i + 3] == 0x06) {
            return true;
          }
        }
        return false;
      } finally {
        await handle.close();
      }
    } catch (e) {
      debugPrint('[FINORA UPDATE] No se pudo validar APK en caché: $e');
      return false;
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('[FINORA UPDATE] No se pudo limpiar archivo temporal: $e');
    }
  }
}

class _InvalidApkException implements Exception {
  const _InvalidApkException(this.message);
  final String message;

  @override
  String toString() => message;
}
