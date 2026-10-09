import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/platform/update_service.dart';

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo update,
) async {
  final isAndroid = Platform.isAndroid;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var isUpdating = false;
      var installerOpened = false;
      var hasError = false;
      var permissionRequired = false;
      var receivedBytes = 0;
      int? totalBytes;
      var statusMessage = 'Listo para descargar la actualización.';

      String formatBytes(int bytes) {
        if (bytes < 1024) return '$bytes B';
        if (bytes < 1024 * 1024) {
          return '${(bytes / 1024).toStringAsFixed(1)} KB';
        }
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }

      return StatefulBuilder(
        builder: (context, setState) {
          final progress = totalBytes != null && totalBytes! > 0
              ? (receivedBytes / totalBytes!).clamp(0.0, 1.0)
              : null;
          final percentage = progress == null
              ? null
              : (progress * 100).round();

          Future<void> startUpdate() async {
            // Capture this before resetting the state: a permission retry should
            // tell the user we are reusing the cached APK, not downloading again.
            final retryingAfterPermission = permissionRequired;
            setState(() {
              isUpdating = true;
              installerOpened = false;
              hasError = false;
              permissionRequired = false;
              receivedBytes = 0;
              totalBytes = null;
              statusMessage = retryingAfterPermission
                  ? 'Usando el APK descargado. Preparando el instalador…'
                  : 'Preparando actualización…';
            });

            final installResult = await UpdateService.downloadAndInstall(
              update,
              onProgress: (received, total) {
                setState(() {
                  receivedBytes = received;
                  totalBytes = total;
                  statusMessage = 'Descargando actualización…';
                });
              },
              onOpeningInstaller: () {
                setState(() {
                  statusMessage = 'APK listo. Abriendo instalador de Android…';
                });
              },
            );

            if (!context.mounted) return;
            setState(() {
              isUpdating = false;
              switch (installResult) {
                case ApkInstallResult.opened:
                  installerOpened = true;
                  statusMessage =
                      'Android abrió el instalador. Revisa la pantalla del sistema y confirma la instalación.';
                  break;
                case ApkInstallResult.permissionRequired:
                  hasError = true;
                  permissionRequired = true;
                  statusMessage =
                      'Android necesita permiso para instalar aplicaciones de Finora. Actívalo en Ajustes y vuelve a Finora para pulsar Reintentar.';
                  break;
                case ApkInstallResult.failed:
                  hasError = true;
                  statusMessage =
                      'No se pudo descargar el APK o abrir el instalador. Comprueba la conexión e inténtalo de nuevo.';
                  break;
              }
            });
          }

          return PopScope(
            canPop: !isUpdating,
            child: AlertDialog(
              title: Text(
                isUpdating
                    ? 'Actualizando Finora'
                    : installerOpened
                        ? 'Instalador abierto'
                        : hasError
                            ? permissionRequired
                                ? 'Permiso necesario'
                                : 'No se pudo actualizar'
                            : 'Nueva versión disponible',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUpdating && !installerOpened && !hasError) ...[
                      Text(
                        update.releaseName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Versión actual: ${update.currentVersion}+${update.currentBuild}',
                      ),
                      Text(
                        'Nueva versión: ${update.latestVersion}+${update.latestBuild}',
                      ),
                      if (update.notes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('Cambios:'),
                        const SizedBox(height: 4),
                        ...update.notes.map((note) => Text('• $note')),
                      ],
                      if (update.apk != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'APK: ${update.apk!.name}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                    if (isUpdating || installerOpened || hasError) ...[
                      const SizedBox(height: 4),
                      Center(
                        child: Icon(
                          hasError
                              ? Icons.error_outline_rounded
                              : installerOpened
                                  ? Icons.verified_outlined
                                  : Icons.downloading_rounded,
                          size: 42,
                          color: hasError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(statusMessage),
                      if (isUpdating && !installerOpened) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        if (percentage != null)
                          Text(
                            '$percentage% · ${formatBytes(receivedBytes)} de ${formatBytes(totalBytes!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Text(
                            '${formatBytes(receivedBytes)} descargados',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ],
                    if (!isAndroid) ...[
                      const SizedBox(height: 12),
                      Text(
                        'La actualización automática solo está disponible en Android.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!isUpdating && !update.mandatory && !installerOpened)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Más tarde'),
                  ),
                if (isAndroid &&
                    update.apk != null &&
                    !isUpdating &&
                    !installerOpened)
                  FilledButton(
                    onPressed: startUpdate,
                    child: Text(
                      permissionRequired
                          ? 'Reintentar'
                          : hasError
                              ? 'Reintentar'
                              : 'Actualizar',
                    ),
                  ),
                if (installerOpened || !isAndroid)
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cerrar'),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}