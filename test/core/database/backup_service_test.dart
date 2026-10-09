import 'package:flutter_test/flutter_test.dart';
import 'package:finora/core/database/backup_service.dart';
import 'package:finora/core/errors/app_exception.dart';

void main() {
  const service = BackupService();

  group('BackupService.restoreBackup validation', () {
    test('rejects invalid JSON before opening the database', () async {
      await expectLater(
        service.restoreBackup(userId: 'user-1', jsonText: '{not json'),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects an unknown backup format', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '{"format":"other","schema_version":1,'
              '"accounts":[],"categories":[],"transactions":[],"transfers":[]}',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects duplicate account identifiers', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '''
          {
            "format": "finora-backup",
            "schema_version": 1,
            "accounts": [
              {"id": 1, "name": "Cuenta A", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-01"},
              {"id": 1, "name": "Cuenta B", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-02"}
            ],
            "categories": [],
            "transactions": [],
            "transfers": []
          }
          ''',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects movements referencing missing backup records', () async {
      await expectLater(
        service.restoreBackup(
          userId: 'user-1',
          jsonText: '''
          {
            "format": "finora-backup",
            "schema_version": 1,
            "accounts": [
              {"id": 1, "name": "Cuenta", "type": "cash",
               "initial_balance": 0, "created_at": "2026-01-01"}
            ],
            "categories": [],
            "transactions": [
              {"id": 1, "account_id": 999, "category_id": 888,
               "type": "income", "amount": 10, "date": "2026-01-01"}
            ],
            "transfers": []
          }
          ''',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
