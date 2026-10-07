import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'router.dart';

final _theme = buildAppTheme();

class FinoraApp extends StatelessWidget {
  const FinoraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
      title: 'Finora',
      theme: _theme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false);
}
