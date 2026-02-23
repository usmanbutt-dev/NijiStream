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

/// Handy formatters for dates, durations, and file sizes.
class Formatters {
  Formatters._();

  /// Format a duration in milliseconds to "mm:ss" or "h:mm:ss".
  static String duration(int ms) {
    final d = Duration(milliseconds: ms);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$secs';
    return '$minutes:$secs';
  }

  /// Format bytes to a human-readable string (KB, MB, GB).
  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Format a Unix timestamp (seconds) to a relative time string.
  static String relativeTime(int unixSeconds) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final diff = now.difference(date);

    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
