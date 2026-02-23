/// NijiStream — Extension data models.
///
/// These are plain Dart classes used to represent extension data flowing
/// through the app. They're separate from the drift database tables —
/// drift generates its own data classes, and we map between them
/// in the repositories.
library;

/// Metadata about an extension from its manifest.
class ExtensionManifest {
  final String id;
  final String name;
  final String version;
  final String lang;
  final String author;
  final String description;
  final String? iconUrl;
  final bool nsfw;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    this.lang = 'en',
    this.author = '',
    this.description = '',
    this.iconUrl,
    this.nsfw = false,
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    return ExtensionManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '0.0.0',
      lang: json['lang'] as String? ?? 'en',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      iconUrl: json['icon'] as String?,
      nsfw: json['nsfw'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'lang': lang,
        'author': author,
        'description': description,
        'icon': iconUrl,
        'nsfw': nsfw,
      };
}

/// An entry in an extension repository index.
class ExtensionRepoEntry {
  final String id;
  final String name;
  final String version;
  final String lang;
  final String url; // URL to the .js file
  final String? iconUrl;
  final bool nsfw;
  final String? changelog;

  const ExtensionRepoEntry({
    required this.id,
    required this.name,
    required this.version,
    this.lang = 'en',
    required this.url,
    this.iconUrl,
    this.nsfw = false,
    this.changelog,
  });

  factory ExtensionRepoEntry.fromJson(Map<String, dynamic> json) {
    return ExtensionRepoEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '0.0.0',
      lang: json['lang'] as String? ?? 'en',
      url: json['url'] as String? ?? '',
      iconUrl: json['icon'] as String?,
      nsfw: json['nsfw'] as bool? ?? false,
      changelog: json['changelog'] as String?,
    );
  }
}

/// A parsed extension repository index (the JSON file hosted on GitHub).
class ExtensionRepo {
  final String name;
  final String author;
  final String description;
  final List<ExtensionRepoEntry> extensions;

  const ExtensionRepo({
    required this.name,
    this.author = '',
    this.description = '',
    this.extensions = const [],
  });

  factory ExtensionRepo.fromJson(Map<String, dynamic> json) {
    final extList = (json['extensions'] as List<dynamic>?)
            ?.map((e) =>
                ExtensionRepoEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return ExtensionRepo(
      name: json['name'] as String? ?? 'Unknown',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      extensions: extList,
    );
  }
}

/// Search result returned by an extension's `search()` method.
class ExtensionSearchResult {
  final String id;
  final String title;
  final String? coverUrl;
  final String url;

  const ExtensionSearchResult({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.url,
  });

  factory ExtensionSearchResult.fromJson(Map<String, dynamic> json) {
    return ExtensionSearchResult(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      coverUrl: json['cover'] as String?,
      url: json['url'] as String? ?? '',
    );
  }
}

/// Paginated search results from an extension.
class ExtensionSearchResponse {
  final bool hasNextPage;
  final List<ExtensionSearchResult> results;

  const ExtensionSearchResponse({
    this.hasNextPage = false,
    this.results = const [],
  });
}

/// Episode info from an extension's `getDetail()`.
class ExtensionEpisode {
  final int number;
  final String? title;
  final String url;

  const ExtensionEpisode({
    required this.number,
    this.title,
    required this.url,
  });

  factory ExtensionEpisode.fromJson(Map<String, dynamic> json) {
    return ExtensionEpisode(
      number: json['number'] as int? ?? 0,
      title: json['title'] as String?,
      url: json['url'] as String? ?? '',
    );
  }
}

/// Full anime details from an extension's `getDetail()`.
class ExtensionAnimeDetail {
  final String title;
  final String? coverUrl;
  final String? bannerUrl;
  final String? synopsis;
  final List<String> genres;
  final String? status;
  final List<ExtensionEpisode> episodes;

  const ExtensionAnimeDetail({
    required this.title,
    this.coverUrl,
    this.bannerUrl,
    this.synopsis,
    this.genres = const [],
    this.status,
    this.episodes = const [],
  });
}

/// A single video source URL with quality info.
class ExtensionVideoSource {
  final String url;
  final String quality; // e.g., "1080p", "720p", "auto"
  final String type; // "hls", "mp4", "dash"

  const ExtensionVideoSource({
    required this.url,
    this.quality = 'auto',
    this.type = 'mp4',
  });

  factory ExtensionVideoSource.fromJson(Map<String, dynamic> json) {
    return ExtensionVideoSource(
      url: json['url'] as String? ?? '',
      quality: json['quality'] as String? ?? 'auto',
      type: json['type'] as String? ?? 'mp4',
    );
  }
}

/// A subtitle track.
class ExtensionSubtitle {
  final String url;
  final String lang;
  final String type; // "srt", "vtt", "ass"

  const ExtensionSubtitle({
    required this.url,
    this.lang = 'en',
    this.type = 'srt',
  });

  factory ExtensionSubtitle.fromJson(Map<String, dynamic> json) {
    return ExtensionSubtitle(
      url: json['url'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      type: json['type'] as String? ?? 'srt',
    );
  }
}

/// Video sources + subtitles from an extension's `getVideoSources()`.
class ExtensionVideoResponse {
  final List<ExtensionVideoSource> sources;
  final List<ExtensionSubtitle> subtitles;

  const ExtensionVideoResponse({
    this.sources = const [],
    this.subtitles = const [],
  });
}
