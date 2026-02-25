/// NijiStream — Settings screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';

// ── Player settings provider ─────────────────────────────────────────────────

/// Key for storing the preferred video quality in SharedPreferences.
const _kDefaultQuality = 'player_default_quality';

/// Available quality options. "auto" means the extension's first source.
const _qualityOptions = ['auto', '1080p', '720p', '480p', '360p'];

/// Public provider — accessed by the video player to apply quality preference.
final playerSettingsProvider =
    StateNotifierProvider<PlayerSettingsNotifier, PlayerSettings>((ref) {
  return PlayerSettingsNotifier();
});

class PlayerSettings {
  final String defaultQuality;
  const PlayerSettings({this.defaultQuality = 'auto'});
}

class PlayerSettingsNotifier extends StateNotifier<PlayerSettings> {
  PlayerSettingsNotifier() : super(const PlayerSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PlayerSettings(
      defaultQuality: prefs.getString(_kDefaultQuality) ?? 'auto',
    );
  }

  Future<void> setQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultQuality, quality);
    state = PlayerSettings(defaultQuality: quality);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Settings Screen
// ═══════════════════════════════════════════════════════════════════

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playerSettings = ref.watch(playerSettingsProvider);

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
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => context.push('/settings/tracking'),
          ),
          const Divider(),

          // ── Extensions section ──
          _SectionHeader(title: 'Extensions', theme: theme),
          _SettingsTile(
            icon: Icons.extension_rounded,
            title: 'Manage Extensions',
            subtitle: 'Browse repos, install & update extensions',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => context.push('/settings/extensions'),
          ),
          const Divider(),

          // ── Player section ──
          _SectionHeader(title: 'Player', theme: theme),
          _SettingsTile(
            icon: Icons.hd_rounded,
            title: 'Default Quality',
            subtitle: 'Preferred quality when multiple sources are available',
            trailing: DropdownButton<String>(
              value: playerSettings.defaultQuality,
              underline: const SizedBox.shrink(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              items: _qualityOptions
                  .map((q) => DropdownMenuItem(
                        value: q,
                        child: Text(q == 'auto' ? 'Auto' : q),
                      ))
                  .toList(),
              onChanged: (q) {
                if (q != null) {
                  ref
                      .read(playerSettingsProvider.notifier)
                      .setQuality(q);
                }
              },
            ),
            onTap: null,
          ),
          const Divider(),

          // ── Appearance section ──
          _SectionHeader(title: 'Appearance', theme: theme),
          _SettingsTile(
            icon: Icons.palette_rounded,
            title: 'Theme',
            subtitle: 'Dark mode (more options coming soon)',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
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
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () {
              // TODO: Navigate to download settings
            },
          ),
          const Divider(),

          // ── About section ──
          _SectionHeader(title: 'About', theme: theme),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: AppConstants.appName,
            subtitle: 'v${AppConstants.appVersion}',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => _showAboutDialog(context, theme),
          ),
          _SettingsTile(
            icon: Icons.gavel_rounded,
            title: 'Disclaimer',
            subtitle: 'Legal disclaimer and content policy',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => _showDisclaimerDialog(context, theme),
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
            const SizedBox(height: 8),
            Text(
              'Version ${AppConstants.appVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Open-source • MIT License',
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textSecondary,
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

  void _showDisclaimerDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: NijiColors.warning),
            SizedBox(width: 8),
            Text('Disclaimer'),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NijiColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              AppConstants.disclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Shared components
// ═══════════════════════════════════════════════════════════════════

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
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
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
      trailing: trailing,
      onTap: onTap,
    );
  }
}
