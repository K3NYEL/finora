import 'package:flutter/material.dart';

import 'finora_skeleton.dart';

class AsyncStateView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  const AsyncStateView({super.key, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            SkeletonCard(height: 72),
            SizedBox(height: 10),
            SkeletonCard(height: 72),
            SizedBox(height: 10),
            SkeletonCard(height: 72),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('No pudimos cargar estos datos.'),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
