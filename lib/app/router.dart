import 'dart:async';

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

      // El splash controla su propia restauración de sesión.
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
      // ------------------------------------------------------------
      // SPLASH
      // ------------------------------------------------------------
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),

      // ------------------------------------------------------------
      // AUTENTICACIÓN
      // ------------------------------------------------------------
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthPage(),
      ),

      // ------------------------------------------------------------
      // APLICACIÓN PRINCIPAL
      // ------------------------------------------------------------
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

      // ------------------------------------------------------------
      // NUEVA TRANSACCIÓN
      // ------------------------------------------------------------
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
    try {
      debugPrint('[FINORA] Iniciando base de datos...');
      await AppDatabase.instance;
      debugPrint('[FINORA] Base de datos OK');

      debugPrint('[FINORA] Comprobando actualización...');
      final update = await UpdateService.checkForUpdate();
      debugPrint('[FINORA] UpdateService OK');

      if (!mounted) return;

      if (update != null) {
        debugPrint(
          '[FINORA] Nueva versión disponible: ${update.latestVersion}',
        );

        await showUpdateDialog(context, update);
      }

      if (!mounted) return;

      await ref.read(sessionProvider.notifier).restore();

      final user = ref.read(sessionProvider);

      _redirectTimer = Timer(
        Duration.zero,
        () => context.go(
          user == null ? '/auth' : '/',
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[FINORA] ERROR DURANTE INICIALIZACIÓN: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      final user = ref.read(sessionProvider);

      _redirectTimer = Timer(
        Duration.zero,
        () => context.go(
          user == null ? '/auth' : '/',
        ),
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
                  color: theme.colorScheme.primary.withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(
                      alpha: 0.35,
                    ),
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
