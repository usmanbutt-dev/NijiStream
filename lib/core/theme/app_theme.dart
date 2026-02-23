/// NijiStream — Material 3 theme configuration.
///
/// Assembles [ColorScheme], [TextTheme], and component themes into a
/// complete [ThemeData] for the app.
library;

import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

class NijiTheme {
  NijiTheme._();

  /// The default dark theme.
  static ThemeData dark({Color? accentSeed}) {
    final colorScheme = NijiColors.darkScheme(seed: accentSeed);
    final textTheme = NijiTypography.textTheme(Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: NijiColors.background,

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: NijiColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
      ),

      // ── Bottom Navigation ──
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: NijiColors.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: NijiColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
      ),

      // ── NavigationRail (desktop sidebar) ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: NijiColors.surface,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: const IconThemeData(color: NijiColors.textTertiary),
        indicatorColor: colorScheme.primary.withValues(alpha: 0.15),
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: NijiColors.textTertiary,
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: NijiColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: NijiColors.surfaceVariant,
        selectedColor: colorScheme.primary.withValues(alpha: 0.2),
        labelStyle: textTheme.labelMedium,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── SnackBar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NijiColors.surfaceBright,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: NijiColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── Input decoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NijiColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: NijiColors.textSecondary,
        size: 24,
      ),

      // ── Page transitions ──
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
