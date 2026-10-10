import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/updates/finora_updates_service.dart';

void main() {
  group('FinoraUpdatesManifest', () {
    test('parses notifications and patch notes', () {
      final manifest = FinoraUpdatesManifest.fromJson({
        'schemaVersion': 1,
        'updatedAt': '2026-10-10T00:00:00Z',
        'notifications': [
          {
            'id': 'maintenance-1',
            'title': 'Mantenimiento',
            'message': 'El servicio estará disponible próximamente.',
            'publishedAt': '2026-10-10T00:00:00Z',
            'level': 'info',
          },
        ],
        'patches': [
          {
            'id': 'v0.5.28',
            'version': '0.5.28',
            'title': 'Correcciones',
            'summary': 'Mejoras de estabilidad.',
            'notes': ['Se corrigió un error.'],
            'releaseUrl': 'https://github.com/K3NYEL/finora/releases/tag/v0.5.28',
            'publishedAt': '2026-10-10T00:00:00Z',
            'required': false,
          },
        ],
      });

      expect(manifest.notifications, hasLength(1));
      expect(manifest.notifications.single.title, 'Mantenimiento');
      expect(manifest.patches, hasLength(1));
      expect(manifest.patches.single.version, '0.5.28');
      expect(manifest.patches.single.releaseUrl, isNotNull);
    });

    test('rejects unsupported schema versions', () {
      expect(
        () => FinoraUpdatesManifest.fromJson({
          'schemaVersion': 2,
          'notifications': [],
          'patches': [],
        }),
        throwsFormatException,
      );
    });

    test('does not trust release links outside the Finora GitHub releases', () {
      final manifest = FinoraUpdatesManifest.fromJson({
        'schemaVersion': 1,
        'notifications': [],
        'patches': [
          {
            'id': 'patch-1',
            'version': '0.5.28',
            'title': 'Correcciones',
            'summary': 'Mejoras de estabilidad.',
            'notes': [],
            'releaseUrl': 'https://example.com/download.apk',
            'publishedAt': '2026-10-10T00:00:00Z',
            'required': false,
          },
        ],
      });

      expect(manifest.patches.single.releaseUrl, isNull);
    });
  });
}
