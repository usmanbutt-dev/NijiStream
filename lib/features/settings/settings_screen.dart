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

// ── Theme settings provider ──────────────────────────────────────────────────

const _kAccentColor = 'theme_accent_color';
const _kAmoledMode = 'theme_amoled_mode';

/// Predefined accent color presets.
const _accentPresets = <String, Color>{
  'Purple': NijiColors.primary,
  'Blue': Color(0xFF3B82F6),
  'Teal': Color(0xFF14B8A6),
  'Green': Color(0xFF22C55E),
  'Pink': Color(0xFFEC4899),
  'Orange': Color(0xFFF97316),
  'Red': Color(0xFFEF4444),
  'Yellow': Color(0xFFEAB308),
};

class ThemeSettings {
  final Color? accentColor;
  final bool amoledMode;
  const ThemeSettings({this.accentColor, this.amoledMode = false});
}

final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_kAccentColor);
    final amoled = prefs.getBool(_kAmoledMode) ?? false;
    state = ThemeSettings(
      accentColor: colorValue != null ? Color(colorValue) : null,
      amoledMode: amoled,
    );
  }

  Future<void> setAccentColor(Color? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_kAccentColor, color.toARGB32());
    } else {
      await prefs.remove(_kAccentColor);
    }
    state = ThemeSettings(accentColor: color, amoledMode: state.amoledMode);
  }

  Future<void> setAmoledMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAmoledMode, enabled);
    state = ThemeSettings(accentColor: state.accentColor, amoledMode: enabled);
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
            subtitle: 'Connect AniList, MyAnimeList',
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
            subtitle: _accentLabel(ref.watch(themeSettingsProvider)),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => _showThemeDialog(context, ref),
          ),
          const Divider(),

          // ── Downloads section ──
          _SectionHeader(title: 'Downloads', theme: theme),
          _SettingsTile(
            icon: Icons.folder_rounded,
            title: 'Concurrent Downloads',
            subtitle: '${AppConstants.defaultConcurrentDownloads} simultaneous downloads',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => _showDownloadSettingsDialog(context),
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

  String _accentLabel(ThemeSettings ts) {
    if (ts.accentColor == null) return 'Purple (default)';
    for (final entry in _accentPresets.entries) {
      if (entry.value.toARGB32() == ts.accentColor!.toARGB32()) {
        return entry.key;
      }
    }
    return 'Custom';
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(themeSettingsProvider.notifier);
    final current = ref.read(themeSettingsProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: NijiColors.surface,
          title: const Text('Theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accent Color',
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                      color: NijiColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _accentPresets.entries.map((entry) {
                  final isSelected = current.accentColor == null
                      ? entry.value == NijiColors.primary
                      : entry.value.toARGB32() ==
                          current.accentColor!.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      notifier.setAccentColor(
                        entry.value == NijiColors.primary
                            ? null
                            : entry.value,
                      );
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              StatefulBuilder(
                builder: (ctx, setLocalState) {
                  var amoled = ref.read(themeSettingsProvider).amoledMode;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AMOLED Black'),
                    subtitle: Text(
                      'Pure black background for OLED screens',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: NijiColors.textTertiary,
                          ),
                    ),
                    value: amoled,
                    onChanged: (v) {
                      notifier.setAmoledMode(v);
                      setLocalState(() => amoled = v);
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showDownloadSettingsDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: const Text('Download Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.speed_rounded,
                  color: NijiColors.textSecondary),
              title: const Text('Concurrent Downloads'),
              subtitle: Text(
                '${AppConstants.defaultConcurrentDownloads} simultaneous',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NijiColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NijiColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Downloads are saved to app documents folder under NijiStream/downloads/.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NijiColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
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
