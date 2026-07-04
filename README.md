# Digi Station

A Flutter tablet/kiosk app for RES (Renewable Energy Systems) shop-floor
workstations. It runs full-screen in landscape and gives an operator live
process readings, work instructions and configuration on a single device.

## What it does

The app is a multi-screen kiosk. Screens can be enabled/disabled and reordered
from **Settings → Layout & Navigation**:

| Screen | Purpose |
| --- | --- |
| **Home** | Dew point / PPMv monitoring with permitted-range status, sensor information, and the current process slip. Speaks a **voice alert** when the dew point leaves the permitted range. |
| **Live Readings** | Live **thickness/height (mm)** and **weight (g)** from the weighing balance and thickness gauge, streamed from a Raspberry Pi. Shows Pi temperature and per-machine min/max limits. |
| **Work Instructions** | Plays the instruction videos configured for the workstation. |
| **Sensor Configuration** | Select the DET channel and view/edit its sensor details (probe ID, calibration dates, permitted range). |
| **Web Logs** | Embedded WebView of the ops portal; auto-fills the focused field with the live gauge value while visible. |
| **Settings** | Two-pane configuration: Machine, Station & API, Work Instructions, Updates, and screen layout. |

## Data sources

- **Dew point** — native WebSocket to the DET server.
- **Live Readings** — Socket.IO to the selected **Machine** (HPM / CPM / APM / EPM),
  each a Raspberry Pi on the local network.
- **Process slips** — HTTP + SSE for real-time updates.

Server URLs live in [`lib/config/api_constants.dart`](lib/config/api_constants.dart);
the machine → IP mapping is in [`lib/services/config_service.dart`](lib/services/config_service.dart).
The active machine, workstation ID, enabled videos and screen layout are stored
locally (SharedPreferences) and configured in **Settings**.

## Requirements

- Flutter SDK (Dart `^3.9`)
- Android device/tablet (landscape). The build targets Android; `min_sdk 21`.
- A GitHub token for the in-app updater (see below).

## Run (development)

```bash
flutter pub get
flutter run                 # debug
flutter run --release       # judge real performance in release, not debug
```

## Build a release APK

The in-app updater authenticates to a private GitHub repo, so the token is
baked in at build time via `--dart-define`:

```bash
flutter build apk --release --dart-define=GITHUB_TOKEN=<your_token>
```

## Cutting a release

Releases are published as GitHub Releases on `Renewable-Energy-Systems/wi-display`;
the installed app checks that repo and offers an update when the release tag is
newer than the installed version. The release notes shown in-app are the GitHub
release body.

Use the helper script (Windows: use the `py` launcher):

```bash
# This release (ships the current pubspec version, tags v<version>):
py scripts/release.py --no-bump --token <your_token>

# Normal release (auto-increments the patch version, then builds + publishes):
py scripts/release.py --token <your_token>
```

The token may also be provided via a `.env` file (`GITHUB_TOKEN=...`) instead of
`--token`. Push your commits to `main` before running it — the script tags the
release against `main` on GitHub. The release body text lives in
`github_upload()` in [`scripts/release.py`](scripts/release.py); keep it in sync
with [`CHANGELOG.md`](CHANGELOG.md).

## App icon & name

The launcher icon and adaptive icon are generated from the source art in
[`assets/icon/`](assets/icon/) with `flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons
```

The display name (`Digi Station`) is set via `android:label` in
`android/app/src/main/AndroidManifest.xml` and `MaterialApp.title` in
[`lib/main.dart`](lib/main.dart).

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md).
