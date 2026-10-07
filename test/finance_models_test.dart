import 'package:flutter_test/flutter_test.dart';
import 'package:finora/features/finance/domain/models.dart';

void main() {
  test('summary calculates the net balance', () {
    const summary = Summary(2500, 875.50);

    expect(summary.balance, closeTo(1624.50, 0.0001));
  });

  test('models preserve account and movement data', () {
    const account = Account(1, 'Banco', 'bank', 1200);
    const movement = Movement(
      'expense',
      'Alimentación',
      'Banco',
      85.75,
      '2026-10-04T12:00:00.000Z',
    );

    expect(account.id, 1);
    expect(account.name, 'Banco');
    expect(account.balance, 1200);
    expect(movement.kind, 'expense');
    expect(movement.amount, 85.75);
  });
}
