/// NijiStream — Application entry point.
///
/// Wraps the app in a [ProviderScope] (Riverpod) so that any widget in
/// the tree can access providers. Initializes both MediaKit and the
/// extension system on startup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/providers/extension_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit (libmpv) for video playback.
  MediaKit.ensureInitialized();

  runApp(
    ProviderScope(
      child: _AppBootstrap(),
    ),
  );
}

/// Bootstrap widget that initializes async services before showing the app.
class _AppBootstrap extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap> {
  @override
  void initState() {
    super.initState();
    // Initialize the extension system on startup.
    // This loads any previously installed extensions from disk.
    Future.microtask(() {
      ref.read(extensionNotifierProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const NijiStreamApp();
  }
}
