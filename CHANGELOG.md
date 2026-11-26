# Changelog

Changes are recorded in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

## [0.2.3] - 2026-11-26

### Fixed

- Update checks now set the fixed User-Agent through Sparkle's `userAgentString` API instead of `httpHeaders`, and the signed feed GET is bounded to four seconds by `UpdateFeedProtocol` (Sparkle 2.10 exposes no appcast timeout property).
- The README download link points to the published latest release instead of a branch-only 0.2.2 asset.
- **Settings › Updates** keeps one short caption and no duplicate version label; the version remains in the footer.

### Added

- Privacy and standalone unit checks for the User-Agent API, the four-second feed timeout and the bounded GET.

## [0.2.2] - 2026-11-26

### Fixed

- **Settings › Updates** shows the contractual defaults before the updater starts, including in snapshot and headless runs, without making a feed request in those runs.

## [0.2.1] - 2026-11-26

### Changed

- Fresh installs check the signed GitHub feed once a day by default; the request is anonymous, uses a fixed User-Agent and sends no system profile. Existing Settings choices are preserved, including an earlier opt-out.
- **Settings › Updates** now shows **Check for updates automatically** (on), **Install updates automatically** (off), **Check Now** and the current version. `ULTRALINK_NO_UPDATE_CHECK=1`, CI and headless modes disable checks for that run.

### Added

- `docs/updates.md` with the update-contract v1 marker, a README **Updates** section and a privacy regression test for the new defaults.

## [0.2.0] - 2026-11-26

### Changed

- Sparkle update checks are off by default; the GitHub feed is fetched only when you use Check Now or enable automatic checks in Settings.
- History directory and file are created with private permissions (0700/0600); Erase History also removes an unreadable-file backup.
- `--snapshot` renders each window's own view to PNG instead of calling `screencapture`, which could not capture these windows, and no longer brings the app to the front.

### Added

- A `## Privacy` section in the README and a privacy regression check in `tests/unit.sh`.

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
