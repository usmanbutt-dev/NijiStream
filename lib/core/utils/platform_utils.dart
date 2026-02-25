/// NijiStream — Utility extension methods and helpers.
library;

import 'package:flutter/material.dart';

/// Platform detection helpers for responsive layout decisions.
///
/// We use screen width breakpoints rather than `Platform.isXxx` because
/// a desktop window can be resized to be narrower than a phone.
class PlatformUtils {
  PlatformUtils._();

  /// Screens wider than this use the desktop sidebar layout.
  static const double desktopBreakpoint = 600;

  /// Returns true when the window is wide enough for desktop layout.
  static bool isDesktopLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= desktopBreakpoint;
  }
}
