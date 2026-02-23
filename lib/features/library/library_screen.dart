/// NijiStream — Library screen.
///
/// Displays the user's anime collection organized by watch status.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: LibraryStatus.all.length + 1, // +1 for "All" tab
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: NijiColors.textSecondary,
            tabs: [
              const Tab(text: 'All'),
              ...LibraryStatus.all.map((s) => Tab(text: LibraryStatus.label(s))),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EmptyLibraryView(theme: theme),
            ...LibraryStatus.all.map((_) => _EmptyLibraryView(theme: theme)),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibraryView extends StatelessWidget {
  final ThemeData theme;
  const _EmptyLibraryView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Anime you add will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: NijiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
