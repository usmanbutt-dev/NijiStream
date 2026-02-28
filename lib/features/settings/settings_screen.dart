/// NijiStream — Settings screen.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../data/database/database_provider.dart';
import '../../data/services/tracking_service.dart';

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

// ── Download settings provider ───────────────────────────────────────────────

const _kDownloadPath = 'download_path';
const _kConcurrentDownloads = 'download_concurrent';

/// Public provider — accessed by the download service.
final downloadSettingsProvider =
    StateNotifierProvider<DownloadSettingsNotifier, DownloadSettings>((ref) {
  return DownloadSettingsNotifier();
});

class DownloadSettings {
  final String? downloadPath;
  final int concurrentDownloads;
  const DownloadSettings({this.downloadPath, this.concurrentDownloads = 2});
}

class DownloadSettingsNotifier extends StateNotifier<DownloadSettings> {
  DownloadSettingsNotifier() : super(const DownloadSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = DownloadSettings(
      downloadPath: prefs.getString(_kDownloadPath),
      concurrentDownloads: prefs.getInt(_kConcurrentDownloads) ?? 2,
    );
  }

  Future<void> setDownloadPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_kDownloadPath, path);
    } else {
      await prefs.remove(_kDownloadPath);
    }
    state = DownloadSettings(
      downloadPath: path,
      concurrentDownloads: state.concurrentDownloads,
    );
  }

  Future<void> setConcurrentDownloads(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConcurrentDownloads, count);
    state = DownloadSettings(
      downloadPath: state.downloadPath,
      concurrentDownloads: count,
    );
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
            icon: Icons.speed_rounded,
            title: 'Concurrent Downloads',
            subtitle:
                '${ref.watch(downloadSettingsProvider).concurrentDownloads} simultaneous downloads',
            trailing: DropdownButton<int>(
              value: ref.watch(downloadSettingsProvider).concurrentDownloads,
              underline: const SizedBox.shrink(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              items: [1, 2, 3, 4, 5]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (n) {
                if (n != null) {
                  ref
                      .read(downloadSettingsProvider.notifier)
                      .setConcurrentDownloads(n);
                }
              },
            ),
            onTap: null,
          ),
          _SettingsTile(
            icon: Icons.folder_rounded,
            title: 'Download Location',
            subtitle: ref.watch(downloadSettingsProvider).downloadPath ??
                'Default (App Documents)',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: NijiColors.textTertiary,
            ),
            onTap: () => _showDownloadLocationDialog(context, ref),
          ),
          const Divider(),

          // ── Data Management section ──
          _SectionHeader(title: 'Data Management', theme: theme),
          _SettingsTile(
            icon: Icons.delete_sweep_rounded,
            title: 'Clear Downloads',
            subtitle: 'Remove all download tasks and files',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: NijiColors.textTertiary),
            onTap: () => _confirmAction(
              context,
              ref,
              title: 'Clear Downloads?',
              message:
                  'All download tasks and downloaded files will be deleted.',
              action: () => _clearDownloads(ref),
            ),
          ),
          _SettingsTile(
            icon: Icons.link_off_rounded,
            title: 'Disconnect AniList & Clear Data',
            subtitle: 'Remove AniList account and all imported anime',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: NijiColors.textTertiary),
            onTap: () => _confirmAction(
              context,
              ref,
              title: 'Disconnect AniList?',
              message:
                  'Your AniList account will be disconnected and all anime '
                  'imported from AniList will be removed from your library.',
              action: () => _disconnectAndClear(ref, 'anilist'),
            ),
          ),
          _SettingsTile(
            icon: Icons.link_off_rounded,
            title: 'Disconnect MAL & Clear Data',
            subtitle: 'Remove MAL account and all imported anime',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: NijiColors.textTertiary),
            onTap: () => _confirmAction(
              context,
              ref,
              title: 'Disconnect MyAnimeList?',
              message:
                  'Your MAL account will be disconnected and all anime '
                  'imported from MAL will be removed from your library.',
              action: () => _disconnectAndClear(ref, 'mal'),
            ),
          ),
          _SettingsTile(
            icon: Icons.warning_amber_rounded,
            title: 'Clear Everything',
            subtitle:
                'Remove all data: library, downloads, accounts, progress',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: NijiColors.error),
            onTap: () => _confirmAction(
              context,
              ref,
              title: 'Clear All Data?',
              message:
                  'This will delete your entire library, all downloads, '
                  'watch progress, and disconnect all tracking accounts. '
                  'This cannot be undone.',
              isDangerous: true,
              action: () => _clearEverything(ref),
            ),
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

  void _showDownloadLocationDialog(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(downloadSettingsProvider.notifier);
    final current = ref.read(downloadSettingsProvider).downloadPath;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: const Text('Download Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NijiColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                current ?? 'Default (App Documents/NijiStream/downloads)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NijiColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final path =
                          await FilePicker.platform.getDirectoryPath();
                      if (path != null) {
                        await notifier.setDownloadPath(path);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Choose Folder'),
                  ),
                ),
                if (current != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await notifier.setDownloadPath(null);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Only affects new downloads. Existing files stay where they are.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: NijiColors.textTertiary,
                fontSize: 11,
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

  void _confirmAction(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required Future<void> Function() action,
    bool isDangerous = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NijiColors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isDangerous
                ? FilledButton.styleFrom(backgroundColor: NijiColors.error)
                : null,
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await action();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Done')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: Text(isDangerous ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDownloads(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await db.deleteAllDownloadTasks();
    // Delete downloaded files from disk.
    try {
      for (final dirPath in await _downloadDirs(ref)) {
        final dir = Directory(dirPath);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {
      // Non-fatal — DB records already cleared.
    }
  }

  Future<void> _disconnectAndClear(WidgetRef ref, String service) async {
    final db = ref.read(databaseProvider);
    final notifier = ref.read(trackingProvider.notifier);
    // Disconnect the account first.
    if (service == 'anilist') {
      await notifier.disconnectAnilist();
    } else {
      await notifier.disconnectMal();
    }
    // Remove all anime imported from that service.
    await db.deleteTrackingData(service);
  }

  Future<void> _clearEverything(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final notifier = ref.read(trackingProvider.notifier);
    // Disconnect all tracking accounts.
    final tracking = ref.read(trackingProvider);
    if (tracking.anilistConnected) await notifier.disconnectAnilist();
    if (tracking.malConnected) await notifier.disconnectMal();
    // Wipe all DB data.
    await db.deleteAllUserData();
    // Delete downloaded files from disk.
    try {
      for (final dirPath in await _downloadDirs(ref)) {
        final dir = Directory(dirPath);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {
      // Non-fatal.
    }
    // Clear watch progress from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final wpKeys =
        prefs.getKeys().where((k) => k.startsWith('niji_wp__')).toList();
    for (final key in wpKeys) {
      await prefs.remove(key);
    }
  }

  /// Returns all download directories to clean up (custom + default).
  Future<List<String>> _downloadDirs(WidgetRef ref) async {
    final dirs = <String>[];
    final customPath = ref.read(downloadSettingsProvider).downloadPath;
    if (customPath != null) dirs.add(customPath);
    final appDir = await getApplicationDocumentsDirectory();
    dirs.add(p.join(appDir.path, 'NijiStream', 'downloads'));
    return dirs;
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
