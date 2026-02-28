# NijiStream 🌈

> Your anime, everywhere.

NijiStream is an open-source, cross-platform anime streaming and management app built with Flutter. Browse, watch, track, and download anime — all from a single app on Android, Windows, and Linux.

## Download

[![Android](https://img.shields.io/badge/Android-APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/usmanbutt-dev/NijiStream/releases/latest/download/NijiStream-android.apk)
[![Windows](https://img.shields.io/badge/Windows-ZIP-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/usmanbutt-dev/NijiStream/releases/latest/download/NijiStream-windows-x64.zip)
[![Linux](https://img.shields.io/badge/Linux-tar.gz-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/usmanbutt-dev/NijiStream/releases/latest/download/NijiStream-linux-x64.tar.gz)

> These links always point to the latest release. See [all releases](https://github.com/usmanbutt-dev/NijiStream/releases) for older versions.

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

# Generate database code (required after any changes to database tables)
dart run build_runner build --delete-conflicting-outputs

# Run on Windows
flutter run -d windows

# Build APK
flutter build apk --release

# Run on Linux
flutter run -d linux
```

### Linux system dependencies

The following packages are required on Debian/Ubuntu-based systems before building or running on Linux:

```bash
sudo apt-get install -y \
  libmpv-dev \          # media_kit video backend
  mpv \                 # runtime MPV libraries
  libsqlite3-dev \      # SQLite (drift database)
  libsecret-1-dev \     # flutter_secure_storage (OAuth tokens)
  libjsoncpp-dev \      # flutter_js / QuickJS dependency
  pkg-config \
  cmake \
  ninja-build \
  clang \
  libgtk-3-dev \
  libblkid-dev \
  liblzma-dev
```

On Fedora/RHEL:

```bash
sudo dnf install -y \
  mpv-libs-devel \
  sqlite-devel \
  libsecret-devel \
  jsoncpp-devel \
  pkg-config \
  cmake \
  ninja-build \
  clang \
  gtk3-devel
```

## Legal Disclaimer

NijiStream does not provide, host, or distribute any media content. All content is sourced through third-party extensions created and maintained by the community. Users are responsible for ensuring they access content through legal means. NijiStream developers are not responsible for content accessed through extensions.

## License

MIT License — see [LICENSE](LICENSE) for details.
