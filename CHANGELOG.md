# Changelog

Changes are recorded in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-26

### Added

- A new version shows a badge next to the menu bar icon and a line in the popover instead of a dialog. **Update…** opens the update window with Install, Remind Me Later and Skip.
- **Settings › Updates › Install updates automatically** (off by default) and the current version beside **Check Now**.
- `ULTRALINK_NO_UPDATE_CHECK=1` turns off the automatic check; it is also off under `CI` and in test launches.
- `PRIVACY.md` and `docs/updates.md`.

### Changed

- The update check sends the fixed user agent `ultralink-update-check` instead of the app version.
- The update window shows short release notes from this changelog instead of loading the GitHub release page.

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
