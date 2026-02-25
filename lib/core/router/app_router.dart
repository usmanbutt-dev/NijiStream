/// NijiStream — go_router configuration.
///
/// **How go_router works (quick primer):**
/// go_router is a declarative router for Flutter. You define routes as a tree,
/// and the router handles URL parsing, deep linking, and navigation state.
/// `ShellRoute` wraps child routes with a shared scaffold (our navigation shell).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/browse/browse_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/downloads/downloads_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/extension_management_screen.dart';
import '../../features/settings/tracking_accounts_screen.dart';
import '../../features/anime/anime_detail_screen.dart';
import '../utils/platform_utils.dart';

/// Route path constants — avoids typos and enables easy refactoring.
class RoutePaths {
  RoutePaths._();
  static const home = '/';
  static const browse = '/browse';
  static const library = '/library';
  static const downloads = '/downloads';
  static const settings = '/settings';
}

/// Top-level navigation destinations used by both the bottom nav bar
/// and the desktop sidebar.
class NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });
}

const navDestinations = [
  NavDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    path: RoutePaths.home,
  ),
  NavDestination(
    label: 'Browse',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    path: RoutePaths.browse,
  ),
  NavDestination(
    label: 'Library',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
    path: RoutePaths.library,
  ),
  NavDestination(
    label: 'Downloads',
    icon: Icons.download_outlined,
    selectedIcon: Icons.download_rounded,
    path: RoutePaths.downloads,
  ),
  NavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    path: RoutePaths.settings,
  ),
];

final appRouter = GoRouter(
  initialLocation: RoutePaths.home,
  routes: [
    // ── ShellRoute wraps all top-level tabs with the navigation scaffold ──
    ShellRoute(
      builder: (context, state, child) {
        return _AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: RoutePaths.home,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HomeScreen(),
          ),
        ),
        GoRoute(
          path: RoutePaths.browse,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: BrowseScreen(),
          ),
        ),
        GoRoute(
          path: RoutePaths.library,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LibraryScreen(),
          ),
        ),
        GoRoute(
          path: RoutePaths.downloads,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DownloadsScreen(),
          ),
        ),
        GoRoute(
          path: RoutePaths.settings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),

    // ── Anime Detail (full-screen, outside shell) ──
    GoRoute(
      path: '/anime/:extensionId/:animeId',
      builder: (context, state) {
        // Decode in case the caller URL-encoded the IDs (e.g. IDs with slashes).
        final extensionId =
            Uri.decodeComponent(state.pathParameters['extensionId']!);
        final animeId =
            Uri.decodeComponent(state.pathParameters['animeId']!);
        return AnimeDetailScreen(
          extensionId: extensionId,
          animeId: animeId,
        );
      },
    ),

    // ── Extension Management ──
    GoRoute(
      path: '/settings/extensions',
      builder: (context, state) => const ExtensionManagementScreen(),
    ),

    // ── Tracking Accounts ──
    GoRoute(
      path: '/settings/tracking',
      builder: (context, state) => const TrackingAccountsScreen(),
    ),
  ],
);

// ═══════════════════════════════════════════════════════════════════════
// _AppShell — Responsive navigation scaffold
// ═══════════════════════════════════════════════════════════════════════

/// The app shell provides either a [NavigationRail] (desktop) or a
/// [BottomNavigationBar] (mobile) depending on screen width.
///
/// This is the key responsive layout component — everything inside the
/// tabs is rendered as [child], which go_router swaps when the user
/// navigates.
class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < navDestinations.length; i++) {
      if (location == navDestinations[i].path) return i;
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(navDestinations[index].path);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.isDesktopLayout(context);
    final selectedIndex = _currentIndex(context);

    if (isDesktop) {
      return _DesktopShell(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        child: child,
      );
    }

    return _MobileShell(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => _onDestinationSelected(context, i),
      child: child,
    );
  }
}

/// Desktop layout: sidebar [NavigationRail] + content area.
class _DesktopShell extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const _DesktopShell({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar ──
          NavigationRail(
            extended: _isExpanded,
            minExtendedWidth: 200,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onDestinationSelected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: IconButton(
                icon: Icon(
                  _isExpanded ? Icons.menu_open : Icons.menu,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
              ),
            ),
            destinations: navDestinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),

          // ── Vertical divider ──
          const VerticalDivider(width: 1, thickness: 1),

          // ── Content area ──
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// Mobile layout: content area + bottom [BottomNavigationBar].
class _MobileShell extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  const _MobileShell({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onDestinationSelected,
        items: navDestinations
            .map(
              (d) => BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
