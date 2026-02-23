# NijiStream 🌈

> Your anime, everywhere.

NijiStream is an open-source, cross-platform anime streaming and management app built with Flutter. Browse, watch, track, and download anime — all from a single app on Android, Windows, and Linux.

## Features

- 🔌 **Extensible** — Community-driven JavaScript extensions for anime sources
- 📺 **Built-in Player** — Hardware-accelerated video with HLS/DASH, subtitles, quality selection
- 📊 **Tracking** — Sync your progress with AniList, MyAnimeList, and Kitsu
- ⬇️ **Downloads** — Save episodes for offline viewing
- 📚 **Library** — Organize your collection with status tracking
- 🎨 **Beautiful** — Modern dark UI with Material 3 design

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x |
| Language | Dart |
| State Management | Riverpod |
| Video Player | media_kit (libmpv) |
| Database | drift (SQLite) |
| Extensions | QuickJS (JavaScript) |

## Building

```bash
# Get dependencies
flutter pub get

# Generate database code
dart run build_runner build

# Run on Windows
flutter run -d windows

# Build APK
flutter build apk --release
```

## Legal Disclaimer

NijiStream does not provide, host, or distribute any media content. All content is sourced through third-party extensions created and maintained by the community. Users are responsible for ensuring they access content through legal means. NijiStream developers are not responsible for content accessed through extensions.

## License

MIT License — see [LICENSE](LICENSE) for details.
