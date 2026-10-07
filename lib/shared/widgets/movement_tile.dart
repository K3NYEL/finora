import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../core/utils/currency_utils.dart';
import '../../features/finance/domain/models.dart';

class MovementTile extends StatelessWidget {
  final Movement m;
  const MovementTile(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final (icon, color, sign) = switch (m.kind) {
      'income' => (Icons.arrow_upward, AppColors.success, '+'),
      'expense' => (Icons.arrow_downward, AppColors.error, '-'),
      _ => (Icons.swap_horiz, AppColors.primary, ''),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: AppColors.surface, child: Icon(icon, color: color, size: 20)),
      title: Text(m.title),
      subtitle: Text(m.subtitle, style: const TextStyle(color: AppColors.textSecondary)),
      trailing: Text('$sign${money(m.amount)}', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
