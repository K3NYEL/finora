import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/database.dart';
import '../core/platform/update_service.dart';
import '../features/accounts/presentation/pages/accounts_page.dart';
import '../features/auth/presentation/pages/auth_page.dart';
import '../features/auth/presentation/session_provider.dart';
import '../features/dashboard/presentation/pages/dashboard_page.dart';
import '../features/finance/presentation/pages/transaction_form_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/statistics/presentation/pages/statistics_page.dart';
import '../features/transactions/presentation/pages/transactions_page.dart';
import '../shared/widgets/update_dialog.dart';
import 'router_refresh_notifier.dart';
import 'shell/app_shell.dart';

const _pageDuration = Duration(milliseconds: 320);
const _minimumSplashDuration = Duration(milliseconds: 900);

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = RouterRefreshNotifier(ref);

  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;

      final isAuthRoute = location == '/auth';
      final isSplashRoute = location == '/splash';

      // El splash controla la inicialización de la aplicación.
      if (isSplashRoute) {
        return null;
      }

      // No hay sesión: solamente puede entrar a /auth.
      if (session == null && !isAuthRoute) {
        return '/auth';
      }

      // Ya hay sesión: no tiene sentido volver a /auth.
      if (session != null && isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthPage(),
      ),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const DashboardPage(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (_, __) => const StatisticsPage(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const TransactionsPage(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (_, __) => const AccountsPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/transactions/new/:kind',
        pageBuilder: (_, state) => _page(
          state,
          TransactionFormPage(
            kind: state.pathParameters['kind']!,
          ),
        ),
      ),
    ],
  );
});

CustomTransitionPage<void> _page(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: _pageDuration,
    reverseTransitionDuration: _pageDuration,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        ),
      );
    },
  );
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _redirectTimer;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint('[FINORA] Iniciando aplicación...');

      // La base de datos y la comprobación de actualización se realizan
      // en paralelo para que el splash no añada tiempo innecesario.
      final results = await Future.wait<dynamic>([
        AppDatabase.instance,
        UpdateService.checkForUpdate(),
      ]);

      final latestUpdate = results[1] as UpdateInfo?;

      debugPrint('[FINORA] Base de datos y actualización comprobadas.');

      // Mantener el splash visible un instante para evitar un arranque
      // prácticamente imperceptible, incluso cuando todo responde rápido.
      final remaining = _minimumSplashDuration - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }

      if (!mounted) return;

      if (latestUpdate != null) {
        debugPrint('[FINORA] Nueva versión disponible.');

        await showUpdateDialog(context, latestUpdate);
      }

      if (!mounted) return;

      // La cuenta recordada se muestra en AuthPage, pero la contraseña
      // siempre debe volver a verificarse al abrir Finora.
      _redirectTimer = Timer(
        Duration.zero,
        () => context.go('/auth'),
      );
    } catch (e, stackTrace) {
      debugPrint('[FINORA] ERROR DURANTE INICIALIZACIÓN: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      // Incluso si falla un servicio secundario, respetamos el tiempo
      // mínimo del splash antes de continuar con el acceso.
      final remaining = _minimumSplashDuration - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }

      if (!mounted) return;

      _redirectTimer = Timer(
        Duration.zero,
        () => context.go('/auth'),
      );
    }
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.scale(
            scale: 0.96 + (_controller.value * 0.04),
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  Icons.auto_graph_rounded,
                  size: 46,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Finora',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
