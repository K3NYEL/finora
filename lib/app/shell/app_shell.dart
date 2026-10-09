import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/', '/statistics', '/transactions', '/accounts'];

  void _add(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('¿Qué quieres registrar?'),
              ),
              for (final (kind, label, icon) in [
                ('income', 'Ingreso', Icons.arrow_upward),
                ('expense', 'Gasto', Icons.arrow_downward),
                ('transfer', 'Transferir', Icons.swap_horiz),
              ])
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/transactions/new/$kind');
                  },
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selectedIndex = _tabs.indexOf(path).clamp(0, _tabs.length - 1);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop) _desktopNavigation(context, selectedIndex),
            Expanded(child: _animatedContent(context, path, child)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context),
        tooltip: 'Agregar movimiento',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar:
          isDesktop ? null : _mobileNavigation(context, selectedIndex),
    );
  }

  Widget _animatedContent(BuildContext context, String path, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (current, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: current,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(path), child: child),
    );
  }

  Widget _mobileNavigation(BuildContext context, int selectedIndex) =>
      NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        destinations: _destinations,
      );

  Widget _desktopNavigation(BuildContext context, int selectedIndex) =>
      NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Finora',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        destinations: [
          for (final destination in _destinations)
            NavigationRailDestination(
              icon: destination.icon,
              label: Text(destination.label),
            ),
        ],
      );

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
    NavigationDestination(
        icon: Icon(Icons.pie_chart_outline), label: 'Estadísticas'),
    NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined), label: 'Movimientos'),
    NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined), label: 'Cuentas'),
  ];
}
