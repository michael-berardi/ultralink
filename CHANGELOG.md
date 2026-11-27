# Changelog

Changes are recorded in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

## [0.3.2] - 2026-11-26

### Added

- A bounded retention sweep runs once at launch, before any update check. It removes unreadable-history copies after 7 days, update downloads left in `~/Library/Caches/com.libertydesignstudio.ultralink` after 7 days, and `$TMPDIR/UltraLink` debris after 1 day. Files are judged individually, so a fresh nested download in an old cache folder survives; the sweep only deletes and never creates a folder. Demo mode leaves the disk untouched.
- `PRIVACY.md` now inventories every local write, its lifetime and its removal steps; the README **Privacy** section is a short summary that links to it. A retention regression test covers stale, recent, nested and unrelated files.

### Changed

- The anonymous daily update check and its gentle, non-modal update prompt are unchanged: **Settings › Updates** or `ULTRALINK_NO_UPDATE_CHECK=1` turns checks off, and automatic installation remains an opt-in.

## [0.3.0] - 2026-11-26

### Added

- A new version shows a badge next to the menu bar icon and a line in the popover instead of a dialog. **Update…** opens the update window with Install, Remind Me Later and Skip.
- **Settings › Updates › Install updates automatically** (off by default) and the current version beside **Check Now**.
- `ULTRALINK_NO_UPDATE_CHECK=1` turns off the automatic check; it is also off under `CI` and in test launches.
- `PRIVACY.md` and `docs/updates.md`.
- A privacy regression check (`tests/privacy.sh`, run by `tests/unit.sh`).

### Changed

- The update check sends the fixed user agent `ultralink-update-check` instead of the app version.
- The update window shows short release notes from this changelog instead of loading the GitHub release page.
- The history folder and file are private (0700 and 0600), including the backup of an unreadable file; **Erase History…** also removes that backup.
- Log messages no longer include error details that could carry addresses or file paths.
- `scripts/build.sh` sets `DO_NOT_TRACK=1` for build tools.

## [0.1.1] - 2026-11-15

### Fixed

- Reject overflowing protobuf varints and malformed field lengths instead of accepting them or crashing.
- Resolved universal binary path through SwiftPM and bounded build parallelism.

### Added

- Standalone protobuf decoder unit tests (`tests/unit.sh`) and clearer setup and polling documentation.

## [0.1.0] - 2026-10-01

### Added

- Initial signed and notarized macOS 13+ menu bar release for monitoring a local Starlink dish.
- Live speed, ping, packet loss, obstruction percentage, power, and data usage with 15-minute, 1-hour, 1-day, and 1-week history charts.
- Outage log and notifications, Sky View obstruction map, macOS `networkQuality` speed test, VPN-friendly interface fallback, and Sparkle updates.
