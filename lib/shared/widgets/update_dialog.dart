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
    builder: (context) {
      return AlertDialog(
        title: const Text('Nueva versión disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              update.releaseName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Versión actual: '
              '${update.currentVersion}+${update.currentBuild}',
            ),
            Text(
              'Nueva versión: '
              '${update.latestVersion}+${update.latestBuild}',
            ),
            if (update.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Cambios:'),
              const SizedBox(height: 4),
              ...update.notes.map(
                (note) => Text('• $note'),
              ),
            ],
            if (isAndroid && update.apk != null) ...[
              const SizedBox(height: 12),
              Text(
                'APK: ${update.apk!.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!isAndroid) ...[
              const SizedBox(height: 12),
              Text(
                'Hay una nueva versión disponible para Finora.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          if (!update.mandatory)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Más tarde'),
            ),
          if (isAndroid && update.apk != null)
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();

                await UpdateService.downloadAndInstall(
                  update,
                );
              },
              child: const Text('Actualizar'),
            ),
          if (!isAndroid)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Entendido'),
            ),
        ],
      );
    },
  );
}
