/// NijiStream — Extension management screen.
///
/// Accessible from Settings → Extensions. Provides:
/// - List of installed extensions with remove option
/// - Button to add extension repos by URL
/// - Browse available extensions from added repos
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../data/providers/extension_providers.dart';
import '../../extensions/models/extension_manifest.dart';

class ExtensionManagementScreen extends ConsumerStatefulWidget {
  const ExtensionManagementScreen({super.key});

  @override
  ConsumerState<ExtensionManagementScreen> createState() =>
      _ExtensionManagementScreenState();
}

class _ExtensionManagementScreenState
    extends ConsumerState<ExtensionManagementScreen> {
  final _repoUrlController = TextEditingController();
  bool _isFetchingRepo = false;
  List<ExtensionRepoEntry>? _availableExtensions;
  String? _repoError;

  @override
  void dispose() {
    _repoUrlController.dispose();
    super.dispose();
  }

  Future<void> _addRepo() async {
    final url = _repoUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isFetchingRepo = true;
      _repoError = null;
    });

    final notifier = ref.read(extensionNotifierProvider.notifier);
    final repo = await notifier.fetchRepo(url);

    if (mounted) {
      setState(() {
        _isFetchingRepo = false;
        if (repo != null) {
          _availableExtensions = repo.extensions;
        } else {
          _repoError = 'Failed to fetch repository. Check the URL.';
        }
      });
    }
  }

  Future<void> _installExtension(ExtensionRepoEntry entry) async {
    final notifier = ref.read(extensionNotifierProvider.notifier);
    await notifier.installExtension(entry);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${entry.name} installed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeExtension(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Extension'),
        content: Text('Remove "$name"? You can reinstall it later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(extensionNotifierProvider.notifier).removeExtension(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extState = ref.watch(extensionNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Extensions')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Add Repo Section ──
          Text(
            'ADD REPOSITORY',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _repoUrlController,
                  decoration: InputDecoration(
                    hintText: 'Extension repo URL (index.json)',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(
                      color: NijiColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: NijiColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isFetchingRepo ? null : _addRepo,
                child: _isFetchingRepo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Fetch'),
              ),
            ],
          ),
          if (_repoError != null) ...[
            const SizedBox(height: 8),
            Text(
              _repoError!,
              style: theme.textTheme.bodySmall?.copyWith(color: NijiColors.error),
            ),
          ],

          // ── Available Extensions from Repo ──
          if (_availableExtensions != null && _availableExtensions!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'AVAILABLE EXTENSIONS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ..._availableExtensions!.map(
              (entry) {
                final isInstalled = extState.loadedExtensions
                    .any((m) => m.id == entry.id);
                return _ExtensionTile(
                  name: entry.name,
                  version: entry.version,
                  lang: entry.lang,
                  trailing: isInstalled
                      ? Chip(
                          label: const Text('Installed'),
                          labelStyle: theme.textTheme.labelSmall?.copyWith(
                            color: NijiColors.success,
                          ),
                          side: BorderSide(
                            color: NijiColors.success.withValues(alpha: 0.3),
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      : FilledButton.tonal(
                          onPressed: () => _installExtension(entry),
                          child: const Text('Install'),
                        ),
                );
              },
            ),
          ],

          // ── Installed Extensions ──
          const SizedBox(height: 24),
          Text(
            'INSTALLED EXTENSIONS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),

          if (extState.loadedExtensions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.extension_off_rounded,
                      size: 48,
                      color: NijiColors.textTertiary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No extensions installed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: NijiColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add a repo URL above to browse available extensions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NijiColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...extState.loadedExtensions.map(
              (manifest) => _ExtensionTile(
                name: manifest.name,
                version: manifest.version,
                lang: manifest.lang,
                description: manifest.description,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: NijiColors.error,
                  onPressed: () =>
                      _removeExtension(manifest.id, manifest.name),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Extension Tile
// ═══════════════════════════════════════════════════════════════════

class _ExtensionTile extends StatelessWidget {
  final String name;
  final String version;
  final String lang;
  final String? description;
  final Widget trailing;

  const _ExtensionTile({
    required this.name,
    required this.version,
    required this.lang,
    this.description,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Extension icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.extension_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v$version • $lang',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NijiColors.textTertiary,
                    ),
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: NijiColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Action
            trailing,
          ],
        ),
      ),
    );
  }
}
