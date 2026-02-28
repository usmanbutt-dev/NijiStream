/// NijiStream — Tracking Accounts screen.
///
/// Lets users connect/disconnect AniList and MyAnimeList accounts via OAuth.
/// Once connected, watch progress and library status are synced automatically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../data/services/tracking_service.dart';
import '../../data/services/tracking_sync_service.dart';

class TrackingAccountsScreen extends ConsumerWidget {
  const TrackingAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(trackingProvider);
    final notifier = ref.read(trackingProvider.notifier);
    final syncStatus = ref.watch(trackingSyncProvider);
    final syncService = ref.read(trackingSyncProvider.notifier);

    final hasConnected =
        tracking.anilistConnected || tracking.malConnected;

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
            description: 'Connect your AniList account.',
            isConnected: tracking.anilistConnected,
            username: tracking.anilistUsername,
            isLoading: tracking.isLoading,
            onConnect: tracking.anilistConfigured
                ? notifier.connectAnilist
                : null,
            onDisconnect: () => _confirmDisconnect(
              context,
              name: 'AniList',
              onConfirm: notifier.disconnectAnilist,
            ),
            notConfiguredMessage: !tracking.anilistConfigured
                ? 'Client ID not configured'
                : null,
          ),

          const Divider(height: 1),

          // ── MyAnimeList ──
          _ServiceCard(
            logo: _MALLogo(),
            name: 'MyAnimeList',
            description: 'Connect your MyAnimeList account.',
            isConnected: tracking.malConnected,
            username: tracking.malUsername,
            isLoading: tracking.isLoading,
            onConnect: tracking.malConfigured
                ? notifier.connectMal
                : null,
            onDisconnect: () => _confirmDisconnect(
              context,
              name: 'MyAnimeList',
              onConfirm: notifier.disconnectMal,
            ),
            notConfiguredMessage: !tracking.malConfigured
                ? 'Client ID not configured'
                : null,
          ),

          // ── Sync section ──
          if (hasConnected) ...[
            const Divider(height: 1),
            _SyncSection(
              syncStatus: syncStatus,
              onSyncAll: syncService.syncAll,
            ),
          ],

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
                'Tracking integration requires valid OAuth client IDs. '
                'Once configured, NijiStream uses OAuth — no password is ever '
                'stored, only access tokens which you can revoke at any time.',
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
  final String? notConfiguredMessage;

  const _ServiceCard({
    required this.logo,
    required this.name,
    required this.description,
    required this.isConnected,
    required this.username,
    required this.isLoading,
    required this.onConnect,
    required this.onDisconnect,
    this.notConfiguredMessage,
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
                  else if (notConfiguredMessage != null)
                    Text(
                      notConfiguredMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NijiColors.textTertiary,
                      ),
                    )
                  else
                    Text(
                      description,
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

// ═══════════════════════════════════════════════════════════════════
// Sync Section
// ═══════════════════════════════════════════════════════════════════

class _SyncSection extends StatelessWidget {
  final SyncStatus syncStatus;
  final VoidCallback onSyncAll;

  const _SyncSection({
    required this.syncStatus,
    required this.onSyncAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_rounded,
                  color: NijiColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('Library Sync', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (syncStatus.isSyncing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  onPressed: onSyncAll,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label:
                      const Text('Sync Now', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          if (syncStatus.lastResult != null) ...[
            const SizedBox(height: 8),
            Text(
              syncStatus.lastResult!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: syncStatus.lastResult!.contains('failed')
                    ? NijiColors.error
                    : NijiColors.success,
              ),
            ),
          ],
          if (syncStatus.lastSyncTime != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last synced: ${_formatTime(syncStatus.lastSyncTime!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.day}/${time.month}/${time.year}';
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
