/// NijiStream — Tracking Accounts screen.
///
/// Lets users connect/disconnect AniList and MyAnimeList accounts via OAuth.
/// Once connected, watch progress and library status are synced automatically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../data/services/tracking_service.dart';

class TrackingAccountsScreen extends ConsumerWidget {
  const TrackingAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(trackingProvider);
    final notifier = ref.read(trackingProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Tracking Accounts')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Error banner ──
          if (tracking.error != null)
            _ErrorBanner(message: tracking.error!),

          // ── AniList ──
          _ServiceCard(
            logo: _AniListLogo(),
            name: 'AniList',
            description: 'Sync your watch list and scores to AniList.',
            isConnected: tracking.anilistConnected,
            username: tracking.anilistUsername,
            isLoading: tracking.isLoading,
            onConnect: () => notifier.connectAnilist(),
            onDisconnect: () => _confirmDisconnect(
              context,
              name: 'AniList',
              onConfirm: () => notifier.disconnectAnilist(),
            ),
          ),

          const Divider(height: 1),

          // ── MyAnimeList ──
          _ServiceCard(
            logo: _MALLogo(),
            name: 'MyAnimeList',
            description: 'Sync your anime list to MyAnimeList.',
            isConnected: tracking.malConnected,
            username: tracking.malUsername,
            isLoading: tracking.isLoading,
            onConnect: () => notifier.connectMal(),
            onDisconnect: () => _confirmDisconnect(
              context,
              name: 'MyAnimeList',
              onConfirm: () => notifier.disconnectMal(),
            ),
          ),

          const Divider(height: 1),

          // ── Kitsu (placeholder) ──
          _ServiceCard(
            logo: _KitsuLogo(),
            name: 'Kitsu',
            description: 'Kitsu integration coming soon.',
            isConnected: false,
            username: null,
            isLoading: false,
            onConnect: null, // disabled
            onDisconnect: null,
          ),

          const SizedBox(height: 24),

          // ── Info note ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NijiColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'NijiStream uses OAuth to connect to tracking services. '
                'No password is ever stored — only access tokens which you can '
                'revoke at any time from the respective service\'s settings.',
                style: TextStyle(
                  color: NijiColors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDisconnect(
    BuildContext context, {
    required String name,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: Text('Disconnect $name?'),
        content: Text(
          'Your local library data will not be deleted, but future changes '
          'will no longer sync to $name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NijiColors.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Service Card
// ═══════════════════════════════════════════════════════════════════

class _ServiceCard extends StatelessWidget {
  final Widget logo;
  final String name;
  final String description;
  final bool isConnected;
  final String? username;
  final bool isLoading;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const _ServiceCard({
    required this.logo,
    required this.name,
    required this.description,
    required this.isConnected,
    required this.username,
    required this.isLoading,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onConnect == null && !isConnected;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Logo
            SizedBox(width: 48, height: 48, child: logo),
            const SizedBox(width: 16),

            // Name + description / username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  if (isConnected && username != null)
                    Text(
                      'Connected as $username',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NijiColors.success,
                      ),
                    )
                  else
                    Text(
                      disabled ? 'Coming soon' : description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NijiColors.textSecondary,
                      ),
                      maxLines: 2,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Action button
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (isConnected)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: NijiColors.error,
                  side: const BorderSide(color: NijiColors.error),
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: onDisconnect,
                child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
              )
            else if (onConnect != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: onConnect,
                child: const Text('Connect', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Service Logos (simple text/icon stand-ins)
// ═══════════════════════════════════════════════════════════════════

class _AniListLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF02A9FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text(
          'AL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

class _MALLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2E51A2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text(
          'MAL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _KitsuLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFF6500),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text(
          'K',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Error Banner
// ═══════════════════════════════════════════════════════════════════

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NijiColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NijiColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: NijiColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: NijiColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
