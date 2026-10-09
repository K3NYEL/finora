import 'dart:io';

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

    // Accept only HTTPS assets hosted by the official Finora GitHub release path.
    // The Android package manager still enforces APK signing compatibility.
    if (!_isTrustedReleaseAsset(apk)) {
      debugPrint(
        '[FINORA UPDATE] URL o nombre de APK no autorizado; descarga rechazada.',
      );
      return ApkInstallResult.failed;
    }

    final client = http.Client();
    IOSink? sink;
    File? apkFile;
    File? partialFile;
    var installerInvoked = false;

    try {
      final directory = await getTemporaryDirectory();
      apkFile = File('${directory.path}/${apk.name}');
      partialFile = File('${apkFile.path}.part');

      // Keep a complete cached APK so permission retries do not download it again.
      if (await _isCompleteApk(apkFile)) {
        debugPrint(
          '[FINORA UPDATE] Reutilizando APK en caché: ${apkFile.path}',
        );
      } else {
        if (await apkFile.exists()) {
          await apkFile.delete();
        }
        if (await partialFile.exists()) {
          await partialFile.delete();
        }

        debugPrint('[FINORA UPDATE] Descargando ${apk.name}...');
        final request = http.Request('GET', Uri.parse(apk.downloadUrl));
        final response = await client
            .send(request)
            .timeout(const Duration(minutes: 2));

        if (response.statusCode != HttpStatus.ok) {
          debugPrint(
            '[FINORA UPDATE] Error HTTP ${response.statusCode} al descargar APK.',
          );
          await response.stream.drain<void>();
          return ApkInstallResult.failed;
        }

        final contentLength = response.contentLength;
        final totalBytes = contentLength != null && contentLength > 0
            ? contentLength
            : null;
        var receivedBytes = 0;
        sink = partialFile.openWrite();

        onProgress?.call(0, totalBytes);

        await for (final chunk
            in response.stream.timeout(const Duration(minutes: 5))) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }

        await sink.flush();
        await sink.close();
        sink = null;

        if (receivedBytes == 0 ||
            (totalBytes != null && receivedBytes != totalBytes) ||
            !await _isCompleteApk(partialFile)) {
          debugPrint(
            '[FINORA UPDATE] La descarga está vacía, incompleta o no es un APK ZIP válido.',
          );
          if (await partialFile.exists()) {
            await partialFile.delete();
          }
          return ApkInstallResult.failed;
        }

        // Rename only after the download has completed and passed validation.
        await partialFile.rename(apkFile.path);
        debugPrint(
          '[FINORA UPDATE] APK descargado y validado: ${apkFile.path} ($receivedBytes bytes)',
        );
      }

      onOpeningInstaller?.call();
      installerInvoked = true;
      final installerResult = await _installerChannel.invokeMethod<String>(
        'installApk',
        {'path': apkFile.path},
      );

      if (installerResult == 'opened') return ApkInstallResult.opened;
      if (installerResult == 'permission_required') {
        // Keep the APK: the user will return from Android Settings and retry.
        return ApkInstallResult.permissionRequired;
      }

      // A failed installer attempt should not trap the user with a bad cached APK.
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
      if (sink != null) {
        await sink.close();
      }
      if (partialFile != null) {
        await _deleteIfExists(partialFile);
      }
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

  static Future<bool> _isCompleteApk(File file) async {
    try {
      if (!await file.exists()) return false;

      final length = await file.length();
      // An APK is a ZIP archive. Check its local-file header and end record
      // to avoid reusing a leftover partial download.
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
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[FINORA UPDATE] No se pudo limpiar ${file.path}: $e');
    }
  }
}