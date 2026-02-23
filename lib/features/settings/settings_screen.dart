/// NijiStream — Settings screen.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Tracking section ──
          _SectionHeader(title: 'Tracking', theme: theme),
          _SettingsTile(
            icon: Icons.sync_rounded,
            title: 'Tracking Accounts',
            subtitle: 'Connect AniList, MAL, Kitsu',
            onTap: () {
              // TODO: Navigate to tracking settings
            },
          ),
          const Divider(),

          // ── Extensions section ──
          _SectionHeader(title: 'Extensions', theme: theme),
          _SettingsTile(
            icon: Icons.extension_rounded,
            title: 'Manage Extensions',
            subtitle: 'Browse repos, install & update extensions',
            onTap: () {
              // TODO: Navigate to extension settings
            },
          ),
          const Divider(),

          // ── Appearance section ──
          _SectionHeader(title: 'Appearance', theme: theme),
          _SettingsTile(
            icon: Icons.palette_rounded,
            title: 'Theme',
            subtitle: 'Dark mode, accent color',
            onTap: () {
              // TODO: Navigate to appearance settings
            },
          ),
          const Divider(),

          // ── Downloads section ──
          _SectionHeader(title: 'Downloads', theme: theme),
          _SettingsTile(
            icon: Icons.folder_rounded,
            title: 'Download Settings',
            subtitle: 'Storage path, concurrent downloads',
            onTap: () {
              // TODO: Navigate to download settings
            },
          ),
          const Divider(),

          // ── Player section ──
          _SectionHeader(title: 'Player', theme: theme),
          _SettingsTile(
            icon: Icons.play_circle_rounded,
            title: 'Player Settings',
            subtitle: 'Default quality, subtitles',
            onTap: () {
              // TODO: Navigate to player settings
            },
          ),
          const Divider(),

          // ── About section ──
          _SectionHeader(title: 'About', theme: theme),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: AppConstants.appName,
            subtitle: 'v${AppConstants.appVersion}',
            onTap: () => _showAboutDialog(context, theme),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: Row(
          children: [
            Icon(Icons.play_circle_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text(AppConstants.appName),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.appTagline,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Version ${AppConstants.appVersion}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NijiColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                AppConstants.disclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NijiColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final ThemeData theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: NijiColors.textSecondary),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: NijiColors.textTertiary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: NijiColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
