/// NijiStream — App-wide constants and configuration.
library;

/// API base URLs for tracking services.
class ApiUrls {
  ApiUrls._();

  /// AniList GraphQL endpoint.
  static const String anilistGraphQL = 'https://graphql.anilist.co';

  /// AniList OAuth authorization URL.
  static const String anilistAuth = 'https://anilist.co/api/v2/oauth/authorize';

  /// AniList OAuth token URL.
  static const String anilistToken = 'https://anilist.co/api/v2/oauth/token';

  /// MyAnimeList API v2 base URL.
  static const String malApi = 'https://api.myanimelist.net/v2';

  /// MyAnimeList OAuth authorization URL.
  static const String malAuth = 'https://myanimelist.net/v1/oauth2/authorize';

  /// MyAnimeList OAuth token URL.
  static const String malToken = 'https://myanimelist.net/v1/oauth2/token';

  /// Kitsu API base URL.
  static const String kitsuApi = 'https://kitsu.app/api/edge';

  /// Kitsu OAuth token URL.
  static const String kitsuToken = 'https://kitsu.io/api/oauth/token';
}

/// Application metadata.
class AppConstants {
  AppConstants._();

  static const String appName = 'NijiStream';
  static const String appTagline = 'Your anime, everywhere.';
  static const String appVersion = '0.1.0';
  static const String githubUrl = 'https://github.com/nijistream/nijistream';

  /// Default number of concurrent downloads.
  static const int defaultConcurrentDownloads = 2;

  /// Background sync interval in minutes.
  static const int syncIntervalMinutes = 15;

  /// Extension repo fetch timeout in seconds.
  static const int repoFetchTimeoutSeconds = 30;

  /// Search debounce duration in milliseconds.
  static const int searchDebounceMs = 500;

  /// Legal disclaimer shown to users.
  static const String disclaimer =
      'NijiStream does not provide, host, or distribute any media content. '
      'All content is sourced through third-party extensions created and '
      'maintained by the community. Users are responsible for ensuring they '
      'access content through legal means. NijiStream developers are not '
      'responsible for content accessed through extensions.';
}

/// Library entry status values.
class LibraryStatus {
  LibraryStatus._();

  static const String watching = 'watching';
  static const String planToWatch = 'plan_to_watch';
  static const String completed = 'completed';
  static const String onHold = 'on_hold';
  static const String dropped = 'dropped';

  static const List<String> all = [
    watching,
    planToWatch,
    completed,
    onHold,
    dropped,
  ];

  /// Human-readable label for a status value.
  static String label(String status) {
    return switch (status) {
      watching => 'Watching',
      planToWatch => 'Plan to Watch',
      completed => 'Completed',
      onHold => 'On Hold',
      dropped => 'Dropped',
      _ => status,
    };
  }
}

/// Download task status values.
class DownloadStatus {
  DownloadStatus._();

  static const String queued = 'queued';
  static const String downloading = 'downloading';
  static const String paused = 'paused';
  static const String completed = 'completed';
  static const String failed = 'failed';
}
