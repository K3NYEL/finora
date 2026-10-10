import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/updates/notifications_and_patches_dialog.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/finora_skeleton.dart';
import '../../../finance/presentation/providers.dart';

class DashboardStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const DashboardStat(this.label, this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              money(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);
    final summaryState = ref.watch(summaryProvider);
    final movementsState = ref.watch(movementsProvider);
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

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
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Tu resumen financiero', style: mutedStyle),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Notificaciones y parches',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const NotificationsAndPatchesDialog(),
              ),
              icon: const Icon(Icons.notifications_active_outlined),
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
          loading: const Row(
            children: [
              Expanded(child: SkeletonCard(height: 82)),
              SizedBox(width: 12),
              Expanded(child: SkeletonCard(height: 82)),
            ],
          ),
          data: (summary) => Row(
            children: [
              Expanded(
                child: DashboardStat(
                  'Ingresos',
                  summary.income,
                  theme.brightness == Brightness.dark
                      ? AppColors.success
                      : const Color(0xFF15803D),
                ),
              ),
              Expanded(
                child: DashboardStat(
                  'Gastos',
                  summary.expense,
                  theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Cuentas', style: theme.textTheme.titleMedium),
        AsyncValueView(
          state: accountsState,
          onRetry: () => ref.invalidate(accountsProvider),
          loading: const Column(
            children: [
              SizedBox(height: 12),
              SkeletonCard(height: 64),
              SizedBox(height: 8),
              SkeletonCard(height: 64),
            ],
          ),
          data: (accounts) => accounts.isEmpty
              ? Text(
                  'Crea tu primera cuenta en la pestaña Cuentas.',
                  style: mutedStyle,
                )
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
        Text('Movimientos recientes', style: theme.textTheme.titleMedium),
        AsyncValueView(
          state: movementsState,
          onRetry: () => ref.invalidate(movementsProvider),
          loading: const Column(
            children: [
              SizedBox(height: 12),
              SkeletonCard(height: 68),
              SizedBox(height: 8),
              SkeletonCard(height: 68),
              SizedBox(height: 8),
              SkeletonCard(height: 68),
            ],
          ),
          data: (movements) => movements.isEmpty
              ? Text('Aún no hay movimientos.', style: mutedStyle)
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
