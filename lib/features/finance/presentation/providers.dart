import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';

final repoProvider = Provider((_) => FinanceRepository());
final accountsProvider =
    FutureProvider((ref) => ref.watch(repoProvider).accounts());
final movementsProvider =
    FutureProvider((ref) => ref.watch(repoProvider).movements());
final summaryProvider =
    FutureProvider((ref) => ref.watch(repoProvider).monthSummary());
final byCategoryProvider =
    FutureProvider((ref) => ref.watch(repoProvider).expenseByCategory());
final categoriesProvider = FutureProvider.family<List<Category>, String>(
    (ref, t) => ref.watch(repoProvider).categories(t));
final filterProvider = StateProvider<String>((_) => 'all');

void refreshAccounts(WidgetRef ref) => ref.invalidate(accountsProvider);

void refreshTransactions(WidgetRef ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(movementsProvider);
  ref.invalidate(summaryProvider);
  ref.invalidate(byCategoryProvider);
}
