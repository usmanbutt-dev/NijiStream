/// NijiStream — User-facing error message sanitizer.
///
/// Converts raw exception messages (which may contain JS stack traces,
/// internal Dio errors, etc.) into friendly, actionable strings for display.
library;

/// Return a user-friendly error string for display in the UI.
///
/// Raw exception messages (JS stack traces, socket errors, etc.) are never
/// shown directly to users. Keep [debugPrint] calls at the call site for
/// developer visibility.
String userFriendlyError(dynamic error) {
  final msg = error.toString().toLowerCase();

  if (msg.contains('socketexception') ||
      msg.contains('connection refused') ||
      msg.contains('network is unreachable') ||
      msg.contains('failed host lookup')) {
    return 'Network error — check your internet connection and try again.';
  }

  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Request timed out — the source may be temporarily unavailable.';
  }

  if (msg.contains('js') ||
      msg.contains('undefined is not') ||
      msg.contains('quickjs') ||
      msg.contains('typeerror') ||
      msg.contains('referenceerror')) {
    return 'Extension error — try updating the extension or switching to a different source.';
  }

  if (msg.contains('404') || msg.contains('not found')) {
    return 'Content not found — it may have been removed from this source.';
  }

  if (msg.contains('403') || msg.contains('forbidden')) {
    return 'Access denied — this content may require a subscription or is region-locked.';
  }

  if (msg.contains('500') || msg.contains('502') || msg.contains('503')) {
    return 'Server error — the source is temporarily down. Please try again later.';
  }

  return 'Something went wrong. Please try again.';
}
