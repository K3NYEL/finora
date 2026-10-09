import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../providers.dart';

TextStyle _muted(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final movements = ref.watch(movementsProvider);
    if (movements.hasError) {
      return AsyncStateView(
        error: movements.error,
        onRetry: () => ref.invalidate(movementsProvider),
      );
    }
    if (movements.isLoading) return const AsyncStateView();
    final all = movements.value ?? [];
    final list =
        filter == 'all' ? all : all.where((m) => m.kind == filter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (kind, label) in [
                ('all', 'Todos'),
                ('income', 'Ingresos'),
                ('expense', 'Gastos'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: filter == kind,
                  onSelected: (_) =>
                      ref.read(filterProvider.notifier).state = kind,
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Aún no hay movimientos.',
                    style: _muted(context),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [for (final movement in list) MovementTile(movement)],
                ),
        ),
      ],
    );
  }
}

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  Future<void> _new(BuildContext c, WidgetRef ref) async {
    final name = TextEditingController();
    final balance = TextEditingController();
    var type = 'bank';
    try {
      await showDialog(
        context: c,
        builder: (_) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('Nueva cuenta'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  onChanged: (value) {
                    if (value != null) set(() => type = value);
                  },
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'bank', child: Text('Banco')),
                    DropdownMenuItem(value: 'savings', child: Text('Ahorros')),
                    DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                    DropdownMenuItem(value: 'other', child: Text('Otra')),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Balance inicial'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref.read(repoProvider).addAccount(
                          name.text,
                          type,
                          double.tryParse(balance.text.replaceAll(',', '.')) ??
                              0,
                        );
                    refreshAccounts(ref);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } on AppException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      balance.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    if (accounts.hasError) {
      return AsyncStateView(
        error: accounts.error,
        onRetry: () => ref.invalidate(accountsProvider),
      );
    }
    if (accounts.isLoading) return const AsyncStateView();
    final accountList = accounts.value ?? [];
    final total = accountList.fold<double>(0, (sum, account) => sum + account.balance);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mis cuentas', style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              onPressed: () => _new(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (accountList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Todavía no tienes cuentas.', style: _muted(context)),
            ),
          ),
        for (final account in accountList)
          Card(
            child: ListTile(
              title: Text(account.name),
              subtitle: Text(account.type, style: _muted(context)),
              trailing: Text(money(account.balance)),
            ),
          ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: _muted(context)),
            Text(money(total), style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ],
    );
  }
}

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final categories = ref.watch(byCategoryProvider);
    if (summary.hasError) {
      return AsyncStateView(
        error: summary.error,
        onRetry: () => ref.invalidate(summaryProvider),
      );
    }
    if (categories.hasError) {
      return AsyncStateView(
        error: categories.error,
        onRetry: () => ref.invalidate(byCategoryProvider),
      );
    }
    if (summary.isLoading || categories.isLoading) {
      return const AsyncStateView();
    }

    final s = summary.value;
    final categoryTotals = categories.value ?? [];
    final maxValue =
        categoryTotals.isEmpty ? 1.0 : categoryTotals.first.$2;
    final theme = Theme.of(context);

    Widget row(String label, double value, Color color) => ListTile(
          title: Text(label, style: _muted(context)),
          trailing: Text(
            money(value),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Este mes', style: theme.textTheme.titleLarge),
        row('Ingresos', s?.income ?? 0, AppColors.success),
        row('Gastos', s?.expense ?? 0, theme.colorScheme.error),
        row('Balance', s?.balance ?? 0, theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Gastos por categoría', style: theme.textTheme.titleMedium),
        if (categoryTotals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Todavía no hay gastos registrados este mes.',
              style: _muted(context),
            ),
          ),
        for (final (name, value) in categoryTotals)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name)),
                    const SizedBox(width: 12),
                    Text(money(value), style: _muted(context)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value / maxValue).clamp(0.0, 1.0),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
