import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../finance/presentation/providers.dart';

class DashboardStat extends StatelessWidget {
  static const muted = TextStyle(color: AppColors.textSecondary);
  final String label;
  final double value;
  final Color color;

  const DashboardStat(this.label, this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: muted),
              Text(money(value),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);
    final summaryState = ref.watch(summaryProvider);
    final movementsState = ref.watch(movementsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Finora',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tu resumen financiero',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Configuración',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AsyncValueView(
          state: summaryState,
          onRetry: () => ref.invalidate(summaryProvider),
          data: (summary) => Row(
            children: [
              Expanded(
                  child: DashboardStat(
                      'Ingresos', summary.income, AppColors.success)),
              Expanded(
                  child: DashboardStat(
                      'Gastos', summary.expense, AppColors.error)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Cuentas', style: TextStyle(fontWeight: FontWeight.w600)),
        AsyncValueView(
          state: accountsState,
          onRetry: () => ref.invalidate(accountsProvider),
          data: (accounts) => accounts.isEmpty
              ? const Text('Crea tu primera cuenta en la pestaña Cuentas.',
                  style: DashboardStat.muted)
              : Column(
                  children: [
                    for (final account in accounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account.name),
                        trailing: Text(money(account.balance)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        const Text('Movimientos recientes',
            style: TextStyle(fontWeight: FontWeight.w600)),
        AsyncValueView(
          state: movementsState,
          onRetry: () => ref.invalidate(movementsProvider),
          data: (movements) => movements.isEmpty
              ? const Text('Aún no hay movimientos.',
                  style: DashboardStat.muted)
              : Column(
                  children: [
                    for (final movement in movements.take(5))
                      MovementTile(movement),
                  ],
                ),
        ),
      ],
    );
  }
}
