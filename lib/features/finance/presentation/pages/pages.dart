import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../providers.dart';

const _muted = TextStyle(color: AppColors.textSecondary);

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filterProvider);
    final movements = ref.watch(movementsProvider);
    if (movements.hasError) {
      return AsyncStateView(
          error: movements.error,
          onRetry: () => ref.invalidate(movementsProvider));
    }
    if (movements.isLoading) return const AsyncStateView();
    final all = movements.value ?? [];
    final list = f == 'all' ? all : all.where((m) => m.kind == f).toList();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            for (final (k, l) in [
              ('all', 'Todos'),
              ('income', 'Ingresos'),
              ('expense', 'Gastos')
            ])
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(l),
                      selected: f == k,
                      onSelected: (_) =>
                          ref.read(filterProvider.notifier).state = k)),
          ])),
      Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('Aún no hay movimientos.', style: _muted))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [for (final m in list) MovementTile(m)])),
    ]);
  }
}

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  Future<void> _new(BuildContext c, WidgetRef ref) async {
    final name = TextEditingController(), bal = TextEditingController();
    var type = 'bank';
    try {
      await showDialog(
          context: c,
          builder: (_) => StatefulBuilder(
              builder: (ctx, set) => AlertDialog(
                    title: const Text('Nueva cuenta'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Nombre')),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                          initialValue: type,
                          onChanged: (v) => set(() => type = v!),
                          items: const [
                            DropdownMenuItem(
                                value: 'cash', child: Text('Efectivo')),
                            DropdownMenuItem(
                                value: 'bank', child: Text('Banco')),
                            DropdownMenuItem(
                                value: 'savings', child: Text('Ahorros')),
                            DropdownMenuItem(
                                value: 'card', child: Text('Tarjeta')),
                            DropdownMenuItem(
                                value: 'other', child: Text('Otra')),
                          ]),
                      const SizedBox(height: 8),
                      TextField(
                          controller: bal,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Balance inicial')),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar')),
                      FilledButton(
                        onPressed: () async {
                          try {
                            await ref.read(repoProvider).addAccount(
                                  name.text,
                                  type,
                                  double.tryParse(bal.text) ?? 0,
                                );

                            refreshAccounts(ref);

                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
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
                  )));
    } finally {
      name.dispose();
      bal.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    if (accounts.hasError) {
      return AsyncStateView(
          error: accounts.error,
          onRetry: () => ref.invalidate(accountsProvider));
    }
    if (accounts.isLoading) return const AsyncStateView();
    final accountList = accounts.value ?? [];
    final total = accountList.fold<double>(0, (a, b) => a + b.balance);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Mis cuentas', style: Theme.of(context).textTheme.titleLarge),
        IconButton(
            onPressed: () => _new(context, ref), icon: const Icon(Icons.add)),
      ]),
      for (final a in accountList)
        Card(
            child: ListTile(
                title: Text(a.name),
                subtitle: Text(a.type, style: _muted),
                trailing: Text(money(a.balance)))),
      const Divider(height: 32),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total', style: _muted),
        Text(money(total), style: Theme.of(context).textTheme.titleLarge)
      ]),
    ]);
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
          error: summary.error, onRetry: () => ref.invalidate(summaryProvider));
    }
    if (categories.hasError) {
      return AsyncStateView(
          error: categories.error,
          onRetry: () => ref.invalidate(byCategoryProvider));
    }
    if (summary.isLoading || categories.isLoading) {
      return const AsyncStateView();
    }
    final s = summary.value;
    final cats = categories.value ?? [];
    final maxV = cats.isEmpty ? 1.0 : cats.first.$2;
    Widget row(String l, double v, Color c) => ListTile(
        title: Text(l, style: _muted),
        trailing: Text(money(v),
            style: TextStyle(color: c, fontWeight: FontWeight.w600)));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Este mes', style: Theme.of(context).textTheme.titleLarge),
      row('Ingresos', s?.income ?? 0, AppColors.success),
      row('Gastos', s?.expense ?? 0, AppColors.error),
      row('Balance', s?.balance ?? 0, AppColors.primary),
      const SizedBox(height: 16),
      const Text('Gastos por categoría',
          style: TextStyle(fontWeight: FontWeight.w600)),
      for (final (n, v) in cats)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(n), Text(money(v), style: _muted)]),
              const SizedBox(height: 6),
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child:
                      LinearProgressIndicator(value: v / maxV, minHeight: 6)),
            ])),
    ]);
  }
}
