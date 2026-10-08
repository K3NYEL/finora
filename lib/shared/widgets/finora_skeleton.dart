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
    duration: const Duration(milliseconds: 1250),
  )..repeat();

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
            const SkeletonBox(width: 44, height: 44, borderRadius: 14),
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.minimumDuration, () {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.scale(
            scale: 0.97 + (_controller.value * 0.03),
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(
                  Icons.auto_graph_rounded,
                  size: 46,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Finora',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 170,
                child: SkeletonBox(height: 6, borderRadius: 99),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
