/// NijiStream — Color palette.
///
/// The app uses a vibrant purple accent by default, with a dark-first
/// Material 3 color scheme. Users can customize the accent color later.
library;

import 'package:flutter/material.dart';

class NijiColors {
  NijiColors._();

  // ── Primary accent (vibrant purple) ──
  static const Color primary = Color(0xFFA855F7);
  static const Color primaryLight = Color(0xFFC084FC);
  static const Color primaryDark = Color(0xFF7C3AED);

  // ── Surface / background (dark theme) ──
  static const Color background = Color(0xFF0F0F14);
  static const Color surface = Color(0xFF1A1A24);
  static const Color surfaceVariant = Color(0xFF24243A);
  static const Color surfaceBright = Color(0xFF2A2A40);

  // ── AMOLED black option ──
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);

  // ── Text on dark ──
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFFA0A0B0);
  static const Color textTertiary = Color(0xFF707080);

  // ── Semantic colors ──
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ── Misc ──
  static const Color divider = Color(0xFF2A2A3A);
  static const Color shimmerBase = Color(0xFF1E1E2E);
  static const Color shimmerHighlight = Color(0xFF2E2E3E);

  /// Build a [ColorScheme] for dark mode from the given accent [seed].
  /// Falls back to the default purple if [seed] is null.
  static ColorScheme darkScheme({Color? seed}) {
    final accent = seed ?? primary;
    return ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: accent.withValues(alpha: 0.15),
      secondary: accent.withValues(alpha: 0.7),
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      error: error,
      onError: Colors.white,
      outline: divider,
    );
  }
}
