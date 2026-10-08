import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../../auth/presentation/session_provider.dart';

final repoProvider = Provider<FinanceRepository>((ref) {
  final user = ref.watch(sessionProvider);

  if (user == null) {
    throw StateError('No hay una sesión activa.');
  }

  return FinanceRepository(
    userId: user.id,
  );
});
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
