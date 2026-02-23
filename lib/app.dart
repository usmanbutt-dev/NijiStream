/// NijiStream — Application root widget.
///
/// Sets up the [MaterialApp.router] with the dark theme, go_router,
/// and global configuration. This is where theme switching and
/// accent color customization will be wired in later.
library;

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class NijiStreamApp extends StatelessWidget {
  const NijiStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NijiStream',
      debugShowCheckedModeBanner: false,

      // ── Theme ──
      theme: NijiTheme.dark(),
      darkTheme: NijiTheme.dark(),
      themeMode: ThemeMode.dark,

      // ── Router ──
      routerConfig: appRouter,
    );
  }
}
