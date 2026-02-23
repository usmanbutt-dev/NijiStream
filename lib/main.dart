/// NijiStream — Application entry point.
///
/// Wraps the app in a [ProviderScope] (Riverpod) so that any widget in
/// the tree can access providers. The database is initialized lazily on
/// first access via its [LazyDatabase] connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // ProviderScope is Riverpod's container. It sits at the top of the
    // widget tree so all descendants can read providers.
    const ProviderScope(
      child: NijiStreamApp(),
    ),
  );
}
