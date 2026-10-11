import 'package:flutter/material.dart';

import '../../core/utils/currency_utils.dart';
import '../../features/finance/domain/models.dart';

class MovementTile extends StatelessWidget {
  final Movement m;

  const MovementTile(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parsedDate = DateTime.tryParse(m.date)?.toLocal();
    final dateLabel = parsedDate == null
        ? ''
        : '${MaterialLocalizations.of(context).formatShortDate(parsedDate)} · '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(parsedDate))}';
    final subtitle = [m.subtitle, dateLabel].where((part) => part.isNotEmpty).join(' · ');
    final (icon, color, sign, label) = switch (m.kind) {
      'income' => (
          Icons.south_west_rounded,
          const Color(0xFF16A34A),
          '+',
          'Ingreso',
        ),
      'expense' => (
          Icons.north_east_rounded,
          scheme.error,
          '−',
          'Gasto',
        ),
      _ => (
          Icons.swap_horiz_rounded,
          scheme.primary,
          '',
          'Movimiento',
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle.isNotEmpty ? subtitle : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$sign${money(m.amount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
