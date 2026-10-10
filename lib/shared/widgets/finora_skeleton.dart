import 'dart:async';

import 'package:flutter/material.dart';

class FinoraSkeleton extends StatefulWidget {
  const FinoraSkeleton({
    super.key,
    this.child,
    this.borderRadius = 12,
    this.height,
    this.width,
  });

  final Widget? child;
  final double borderRadius;
  final double? height;
  final double? width;

  @override
  State<FinoraSkeleton> createState() => _FinoraSkeletonState();
}

class _FinoraSkeletonState extends State<FinoraSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final begin = Alignment(-1.4 + (t * 2.8), 0);
        final end = Alignment(-0.7 + (t * 2.8), 0);

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: begin,
            end: end,
            colors: [
              scheme.surfaceContainerHighest,
              scheme.surfaceContainerHighest.withValues(alpha: 0.48),
              scheme.surfaceContainerHighest,
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: widget.child,
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return FinoraSkeleton(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 88,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return FinoraSkeleton(
      height: height,
      borderRadius: 16,
    );
  }
}

class SkeletonText extends StatelessWidget {
  const SkeletonText({
    super.key,
    this.width = 120,
    this.height = 14,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: height / 2,
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 92, height: 24),
                  SizedBox(height: 8),
                  SkeletonText(width: 150),
                ],
              ),
            ),
            SkeletonBox(width: 44, height: 44, borderRadius: 14),
          ],
        ),
        SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: SkeletonCard(height: 82)),
            SizedBox(width: 12),
            Expanded(child: SkeletonCard(height: 82)),
          ],
        ),
        SizedBox(height: 24),
        SkeletonText(width: 80),
        SizedBox(height: 12),
        SkeletonCard(height: 64),
        SizedBox(height: 8),
        SkeletonCard(height: 64),
        SizedBox(height: 24),
        SkeletonText(width: 150),
        SizedBox(height: 12),
        SkeletonCard(height: 68),
        SizedBox(height: 8),
        SkeletonCard(height: 68),
        SizedBox(height: 8),
        SkeletonCard(height: 68),
      ],
    );
  }
}

class AccountsSkeleton extends StatelessWidget {
  const AccountsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(child: SkeletonText(width: 132, height: 24)),
            SkeletonBox(
              width: 42,
              height: 42,
              borderRadius: 14,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SkeletonBox(width: 54, height: 54, borderRadius: 27),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 145, height: 18),
                      SizedBox(height: 9),
                      SkeletonText(width: 190, height: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const SkeletonCard(height: 76),
        const SizedBox(height: 12),
        const SkeletonCard(height: 76),
        const SizedBox(height: 12),
        const SkeletonCard(height: 76),
        const SizedBox(height: 12),
        const SkeletonCard(height: 76),
        const SizedBox(height: 24),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonText(width: 64),
            SkeletonText(width: 104, height: 22),
          ],
        ),
      ],
    );
  }
}

class TransactionsSkeleton extends StatelessWidget {
  const TransactionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Row(
          children: [
            Expanded(child: SkeletonText(width: 60)),
            SizedBox(width: 8),
            Expanded(child: SkeletonText(width: 60)),
            SizedBox(width: 8),
            Expanded(child: SkeletonText(width: 60)),
          ],
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < 7; i++) ...[
          const SkeletonCard(height: 68),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class StatisticsSkeleton extends StatelessWidget {
  const StatisticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonText(width: 115, height: 24),
        const SizedBox(height: 18),
        const SkeletonCard(height: 70),
        const SizedBox(height: 8),
        const SkeletonCard(height: 70),
        const SizedBox(height: 8),
        const SkeletonCard(height: 70),
        const SizedBox(height: 24),
        const SkeletonText(width: 180, height: 20),
        const SizedBox(height: 14),
        for (var i = 0; i < 5; i++) ...[
          const SkeletonCard(height: 48),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class FinoraLoadingScreen extends StatefulWidget {
  const FinoraLoadingScreen({
    super.key,
    this.message = 'Preparando tu espacio financiero...',
    this.onReady,
    this.minimumDuration = const Duration(milliseconds: 900),
  });

  final String message;
  final VoidCallback? onReady;
  final Duration minimumDuration;

  @override
  State<FinoraLoadingScreen> createState() => _FinoraLoadingScreenState();
}

class _FinoraLoadingScreenState extends State<FinoraLoadingScreen>
    with SingleTickerProviderStateMixin {
  Timer? _readyTimer;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _readyTimer = Timer(widget.minimumDuration, () {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.scale(
              scale: 0.985 + (_controller.value * 0.015),
              child: child,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.32),
                          ),
                        ),
                        child: Icon(
                          Icons.auto_graph_rounded,
                          size: 40,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Finora',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const DashboardSkeleton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
