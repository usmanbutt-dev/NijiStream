/// NijiStream — Video Player screen.
///
/// Full-screen, immersive video player powered by media_kit (libmpv).
/// Features:
/// - Multi-quality source selection (from extension's getVideoSources)
/// - Optional subtitle track selection
/// - Adaptive controls (Material on mobile, Desktop on desktop)
/// - Next/previous episode navigation
/// - Watch progress tracking (saves position every 5s and on exit)
/// - Resume playback from last saved position
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/error_utils.dart';
import '../../core/utils/hls_utils.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/services/watch_progress_service.dart';
import '../../extensions/api/extension_api.dart';
import '../../extensions/models/extension_manifest.dart';
import '../settings/settings_screen.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String extensionId;
  final String animeId;
  final String episodeId;
  final String animeTitle;
  final int episodeNumber;
  final String? episodeTitle;

  /// Optional: for next/prev episode navigation.
  final List<ExtensionEpisode>? episodes;
  final int? currentEpisodeIndex;

  /// Optional: full anime detail used to auto-register in library on watch.
  final ExtensionAnimeDetail? animeDetail;

  const VideoPlayerScreen({
    super.key,
    required this.extensionId,
    required this.animeId,
    required this.episodeId,
    required this.animeTitle,
    required this.episodeNumber,
    this.episodeTitle,
    this.episodes,
    this.currentEpisodeIndex,
    this.animeDetail,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  late final WatchProgressService _progressService;

  ExtensionVideoResponse? _videoResponse;
  ExtensionVideoSource? _selectedSource;
  ExtensionSubtitle? _selectedSubtitle;
  bool _isLoading = true;
  String? _error;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  Timer? _saveTimer;

  // When non-null, seek to this position once duration becomes known.
  int? _pendingResumeMs;

  // Current playback state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  // Stream subscriptions for player events
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();

    // Create the media_kit player and controller.
    _player = Player();
    _videoController = VideoController(_player);

    // Obtain the DB-backed progress service.
    _progressService = ref.read(watchProgressServiceProvider);

    // Listen to player state streams.
    _subscriptions.addAll([
      _player.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),
      _player.stream.duration.listen((dur) {
        if (mounted) {
          setState(() => _duration = dur);
          // Once duration is known, seek to resume position if pending.
          if (_pendingResumeMs != null && dur.inMilliseconds > 0) {
            final ms = _pendingResumeMs!;
            _pendingResumeMs = null;
            _player.seek(Duration(milliseconds: ms));
          }
        }
      }),
      _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      _player.stream.completed.listen((completed) {
        if (completed && mounted) _onPlaybackComplete();
      }),
    ]);

    // Force immersive mode on mobile.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadVideoSources();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _saveTimer?.cancel();
    // Save final position synchronously-ish before disposing.
    _saveProgress();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadVideoSources() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(extensionRepositoryProvider);
      final rawResponse = await repo.getVideoSources(
        widget.extensionId,
        widget.episodeId,
      );

      if (!mounted) return;

      if (rawResponse == null || rawResponse.sources.isEmpty) {
        // Direct-scraping extensions may be blocked by the site's anti-bot
        // protection (e.g. Cloudflare JS challenges). Give a more helpful hint.
        final isDirect = widget.extensionId.contains('direct');
        setState(() {
          _error = isDirect
              ? 'No video sources found.\n\nThis extension scrapes the site directly and may be blocked by anti-bot protection. Try again later or use a different source.'
              : 'No video sources available for this episode.';
          _isLoading = false;
        });
        return;
      }

      // Load saved progress to resume from.
      final saved = await _progressService.load(
        widget.extensionId,
        widget.episodeId,
      );

      if (!mounted) return;

      // If there's a single HLS source (master M3U8), parse it to extract
      // individual quality variants so the user can manually select quality.
      final response = await expandHlsVariants(rawResponse);

      if (!mounted) return;

      setState(() {
        _videoResponse = response;
        _isLoading = false;
      });

      // Queue resume seek if there's a non-trivial saved position.
      final resumeMs =
          (saved != null && !saved.completed && saved.positionMs > 5000)
              ? saved.positionMs
              : null;

      // Apply user's preferred quality setting.
      final preferredQuality =
          ref.read(playerSettingsProvider).defaultQuality;
      final selectedSource = (preferredQuality != 'auto')
          ? response.sources.firstWhere(
              (s) => s.quality.toLowerCase().contains(preferredQuality.toLowerCase()),
              orElse: () => response.sources.first,
            )
          : response.sources.first;

      _selectSource(selectedSource, resumePositionMs: resumeMs);

      // Auto-register in library as "watching" if not already added.
      _autoAddToLibrary();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userFriendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  /// Auto-add this anime to the library with status "watching" when playback
  /// starts, but only if it isn't already in the library.
  /// Preserves any existing user-set status (e.g. 'completed').
  Future<void> _autoAddToLibrary() async {
    final detail = widget.animeDetail;
    if (detail == null) return;
    try {
      await ref.read(libraryRepositoryProvider).autoAddIfAbsent(
            extensionId: widget.extensionId,
            animeId: widget.animeId,
            detail: detail,
          );
    } catch (_) {}
  }

  void _selectSource(
    ExtensionVideoSource source, {
    int? resumePositionMs,
  }) {
    setState(() => _selectedSource = source);

    if (resumePositionMs != null) {
      _pendingResumeMs = resumePositionMs;
    }

    final media = Media(
      source.url,
      httpHeaders: source.headers ?? {},
    );
    _player.open(media);

    // Auto-select the first English subtitle, or first available.
    final subs = _videoResponse?.subtitles ?? [];
    if (subs.isNotEmpty) {
      final english = subs.where(
        (s) => s.lang.toLowerCase().contains('english'),
      );
      final autoSub = english.isNotEmpty ? english.first : subs.first;
      _setSubtitle(autoSub);
    } else {
      setState(() => _selectedSubtitle = null);
    }

    // Start periodic progress saving.
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });

    _resetHideTimer();
  }

  void _setSubtitle(ExtensionSubtitle sub) {
    setState(() => _selectedSubtitle = sub);
    _player.setSubtitleTrack(
      SubtitleTrack.uri(sub.url, title: sub.label, language: sub.lang),
    );
  }

  void _disableSubtitles() {
    setState(() => _selectedSubtitle = null);
    _player.setSubtitleTrack(SubtitleTrack.no());
  }

  void _saveProgress() {
    if (_duration.inMilliseconds == 0) return;
    final completed = _position.inMilliseconds / _duration.inMilliseconds > 0.9;
    _progressService.save(
      widget.extensionId,
      widget.episodeId,
      WatchProgressEntry(
        positionMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
        completed: completed,
      ),
    );
  }

  void _onPlaybackComplete() {
    // Mark episode as completed in SharedPreferences.
    _progressService.markCompleted(widget.extensionId, widget.episodeId);

    // Update watched-episode count in the library DB.
    // episodeNumber is 1-based, so it directly represents episodes watched.
    ref.read(libraryRepositoryProvider).setProgressIfGreater(
          extensionId: widget.extensionId,
          animeId: widget.animeId,
          newProgress: widget.episodeNumber,
        );

    // Auto-play next episode if available.
    if (widget.episodes != null && widget.currentEpisodeIndex != null) {
      final nextIndex = widget.currentEpisodeIndex! + 1;
      if (nextIndex < widget.episodes!.length) {
        _navigateToEpisode(nextIndex);
        return;
      }
    }
  }

  void _navigateToEpisode(int index) {
    if (widget.episodes == null ||
        index < 0 ||
        index >= widget.episodes!.length) {
      return;
    }

    final episode = widget.episodes![index];

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          extensionId: widget.extensionId,
          animeId: widget.animeId,
          episodeId: episode.id,
          animeTitle: widget.animeTitle,
          episodeNumber: episode.number,
          episodeTitle: episode.title,
          episodes: widget.episodes,
          currentEpisodeIndex: index,
          animeDetail: widget.animeDetail,
        ),
      ),
    );
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _resetHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? _LoadingView(
              animeTitle: widget.animeTitle,
              episodeNumber: widget.episodeNumber,
            )
          : _error != null
              ? _ErrorView(
                  error: _error!,
                  onRetry: _loadVideoSources,
                )
              : _PlayerView(
                  videoController: _videoController,
                  controlsVisible: _controlsVisible,
                  onToggleControls: _toggleControls,
                  onResetTimer: _resetHideTimer,
                  overlay: _buildControlsOverlay(),
                ),
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.transparent,
                Colors.transparent,
                Colors.black87,
              ],
              stops: [0.0, 0.2, 0.7, 1.0],
            ),
          ),
          child: Column(
            children: [
              // ── Top bar: title + back ──
              _TopBar(
                animeTitle: widget.animeTitle,
                episodeNumber: widget.episodeNumber,
                episodeTitle: widget.episodeTitle,
                onBack: () => Navigator.of(context).pop(),
              ),

              const Spacer(),

              // ── Center controls: prev / play-pause / next ──
              _CenterControls(
                isPlaying: _isPlaying,
                isBuffering: _isBuffering,
                hasPrevious: widget.currentEpisodeIndex != null &&
                    widget.currentEpisodeIndex! > 0,
                hasNext: widget.episodes != null &&
                    widget.currentEpisodeIndex != null &&
                    widget.currentEpisodeIndex! <
                        widget.episodes!.length - 1,
                onPlayPause: () => _player.playOrPause(),
                onPrevious: () => _navigateToEpisode(
                  widget.currentEpisodeIndex! - 1,
                ),
                onNext: () => _navigateToEpisode(
                  widget.currentEpisodeIndex! + 1,
                ),
                onRewind: () => _player.seek(
                  _position - const Duration(seconds: 10),
                ),
                onFastForward: () => _player.seek(
                  _position + const Duration(seconds: 10),
                ),
              ),

              const Spacer(),

              // ── Bottom bar: seek bar + quality + subtitles ──
              _BottomBar(
                position: _position,
                duration: _duration,
                formatDuration: _formatDuration,
                onSeek: (value) {
                  final pos = Duration(
                    milliseconds:
                        (value * _duration.inMilliseconds).round(),
                  );
                  _player.seek(pos);
                  _resetHideTimer();
                },
                selectedSource: _selectedSource,
                sources: _videoResponse?.sources ?? [],
                onSourceSelected: (source) =>
                    _selectSource(source, resumePositionMs: null),
                selectedSubtitle: _selectedSubtitle,
                subtitles: _videoResponse?.subtitles ?? [],
                onSubtitleSelected: _setSubtitle,
                onSubtitlesOff: _disableSubtitles,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Player View (Video + overlay)
// ═══════════════════════════════════════════════════════════════════

class _PlayerView extends StatelessWidget {
  final VideoController videoController;
  final bool controlsVisible;
  final VoidCallback onToggleControls;
  final VoidCallback onResetTimer;
  final Widget overlay;

  const _PlayerView({
    required this.videoController,
    required this.controlsVisible,
    required this.onToggleControls,
    required this.onResetTimer,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggleControls,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video surface
          Video(
            controller: videoController,
            controls: NoVideoControls,
          ),

          // Custom overlay controls
          overlay,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Top Bar
// ═══════════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final String animeTitle;
  final int episodeNumber;
  final String? episodeTitle;
  final VoidCallback onBack;

  const _TopBar({
    required this.animeTitle,
    required this.episodeNumber,
    this.episodeTitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    animeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    episodeTitle != null
                        ? 'Episode $episodeNumber — $episodeTitle'
                        : 'Episode $episodeNumber',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Center Controls (play/pause, skip, rewind/ff)
// ═══════════════════════════════════════════════════════════════════

class _CenterControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRewind;
  final VoidCallback onFastForward;

  const _CenterControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onRewind,
    required this.onFastForward,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous episode
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 36,
          color: hasPrevious
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          onPressed: hasPrevious ? onPrevious : null,
        ),

        const SizedBox(width: 12),

        // Rewind 10s
        IconButton(
          icon: const Icon(Icons.replay_10_rounded),
          iconSize: 36,
          color: Colors.white,
          onPressed: onRewind,
        ),

        const SizedBox(width: 16),

        // Play/Pause (large button)
        isBuffering
            ? const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  iconSize: 48,
                  color: Colors.white,
                  onPressed: onPlayPause,
                ),
              ),

        const SizedBox(width: 16),

        // Forward 10s
        IconButton(
          icon: const Icon(Icons.forward_10_rounded),
          iconSize: 36,
          color: Colors.white,
          onPressed: onFastForward,
        ),

        const SizedBox(width: 12),

        // Next episode
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 36,
          color: hasNext
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          onPressed: hasNext ? onNext : null,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Bottom Bar (seek slider + quality + time)
// ═══════════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final String Function(Duration) formatDuration;
  final ValueChanged<double> onSeek;
  final ExtensionVideoSource? selectedSource;
  final List<ExtensionVideoSource> sources;
  final ValueChanged<ExtensionVideoSource> onSourceSelected;
  final ExtensionSubtitle? selectedSubtitle;
  final List<ExtensionSubtitle> subtitles;
  final ValueChanged<ExtensionSubtitle> onSubtitleSelected;
  final VoidCallback onSubtitlesOff;

  const _BottomBar({
    required this.position,
    required this.duration,
    required this.formatDuration,
    required this.onSeek,
    required this.selectedSource,
    required this.sources,
    required this.onSourceSelected,
    required this.selectedSubtitle,
    required this.subtitles,
    required this.onSubtitleSelected,
    required this.onSubtitlesOff,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek slider
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 14,
              ),
              activeTrackColor: NijiColors.primary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbColor: NijiColors.primary,
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onSeek,
            ),
          ),

          // Time labels + quality button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Current / Total time
                Text(
                  '${formatDuration(position)} / ${formatDuration(duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),

                const Spacer(),

                // Subtitle selector
                if (subtitles.isNotEmpty)
                  _SubtitleButton(
                    selectedSubtitle: selectedSubtitle,
                    subtitles: subtitles,
                    onSubtitleSelected: onSubtitleSelected,
                    onSubtitlesOff: onSubtitlesOff,
                  ),

                // Quality selector (always visible)
                _QualityButton(
                  selectedSource: selectedSource,
                  sources: sources,
                  onSourceSelected: onSourceSelected,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Subtitle Selector Button
// ═══════════════════════════════════════════════════════════════════

class _SubtitleButton extends StatelessWidget {
  final ExtensionSubtitle? selectedSubtitle;
  final List<ExtensionSubtitle> subtitles;
  final ValueChanged<ExtensionSubtitle> onSubtitleSelected;
  final VoidCallback onSubtitlesOff;

  const _SubtitleButton({
    required this.selectedSubtitle,
    required this.subtitles,
    required this.onSubtitleSelected,
    required this.onSubtitlesOff,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: Icon(
        selectedSubtitle != null
            ? Icons.closed_caption_rounded
            : Icons.closed_caption_off_rounded,
        size: 18,
      ),
      label: Text(
        selectedSubtitle?.lang ?? 'CC',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _showSubtitleSheet(context),
    );
  }

  void _showSubtitleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NijiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Subtitles',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              // "Off" option
              ListTile(
                leading: Icon(
                  selectedSubtitle == null
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selectedSubtitle == null ? NijiColors.primary : null,
                ),
                title: const Text('Off'),
                onTap: () {
                  Navigator.pop(context);
                  onSubtitlesOff();
                },
              ),
              // Each subtitle track
              ...subtitles.map(
                (sub) => ListTile(
                  leading: Icon(
                    sub == selectedSubtitle
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: sub == selectedSubtitle ? NijiColors.primary : null,
                  ),
                  title: Text(sub.lang),
                  onTap: () {
                    Navigator.pop(context);
                    onSubtitleSelected(sub);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Quality Selector Button
// ═══════════════════════════════════════════════════════════════════

class _QualityButton extends StatelessWidget {
  final ExtensionVideoSource? selectedSource;
  final List<ExtensionVideoSource> sources;
  final ValueChanged<ExtensionVideoSource> onSourceSelected;

  const _QualityButton({
    required this.selectedSource,
    required this.sources,
    required this.onSourceSelected,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: const Icon(Icons.hd_rounded, size: 18),
      label: Text(
        selectedSource?.quality ?? 'Quality',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _showQualitySheet(context),
    );
  }

  void _showQualitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NijiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Video Quality',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ...sources.map(
                (source) => ListTile(
                  leading: Icon(
                    source == selectedSource
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: source == selectedSource
                        ? NijiColors.primary
                        : null,
                  ),
                  title: Text(source.quality),
                  subtitle: source.server != null
                      ? Text(
                          source.server!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: NijiColors.textTertiary,
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    onSourceSelected(source);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Loading / Error States
// ═══════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  final String animeTitle;
  final int episodeNumber;

  const _LoadingView({
    required this.animeTitle,
    required this.episodeNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: NijiColors.primary),
          const SizedBox(height: 24),
          Text(
            animeTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Loading Episode $episodeNumber...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: NijiColors.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
