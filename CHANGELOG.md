# Changelog

Changes are recorded in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

## [0.3.2] - 2026-11-26

### Changed

- The README **Privacy** section is now a five-line summary: no telemetry, one anonymous daily update check you can opt out of, nothing uploaded, what stays local, and how to remove it. All fine detail moved to the new [PRIVACY.md](PRIVACY.md), linked from the README.
- `PRIVACY.md` inventories every local write — history, unreadable-history backup, settings plist, Sparkle's update download cache and private temp space — with each file's lifetime and removal steps.

### Fixed

- Update leftovers and temp files no longer accumulate. `Retention.sweep()` runs once at launch, before any update check, and deletes an unreadable-history copy after 7 days, update downloads left in `~/Library/Caches/com.libertydesignstudio.ultralink` after 7 days and `$TMPDIR/UltraLink` debris after 1 day. It only deletes, never writes, creates no folder, and is skipped in demo mode.
- `Store.directoryPath` exposes the history folder without creating it, so the launch sweep cannot touch the disk on a fresh install.

### Added

- Retention regression test in `tests/unit/main.swift`: stale history backups, downloads and temp files are removed while `history.json`, recent downloads and files UltraLink does not own are kept; a missing directory is a no-op.
- Privacy regression checks for the README summary length, the `PRIVACY.md` link, the retention bounds and the launch sweep.

## [0.3.1] - 2026-11-26

### Fixed

- **Settings › Updates** puts the current version on the left and **Check Now** on the right, aligned with the update switches; the spacer no longer reverses them.
- The branch version is above the published v0.3.0 tag. The README points to the published v0.3.0 download and does not claim a 0.3.1 release asset.

## [0.2.4] - 2026-11-26

### Fixed

- **Settings › Updates** now shows the current version beside **Check Now**, with the button aligned to the other controls. The redundant explanatory caption is gone, the opt-out notice is a short status line, and the footer no longer repeats the version.
- `docs/updates.md`, the README and the source comments no longer claim a four-second cap on Sparkle's own feed request. The standalone test proves that cap only for a session using `UpdateFeedProtocol`; Sparkle 2.10's private session does not honor the relay, so the app cannot enforce it on Sparkle's feed GET. The exact gap is recorded in `docs/updates.md`.

## [0.2.3] - 2026-11-26

### Fixed

- Update checks now set the fixed User-Agent through Sparkle's `userAgentString` API instead of `httpHeaders`. A four-second `UpdateFeedProtocol` relay was added; a later review found that Sparkle's feed session does not use it (see 0.2.4).
- The README download link points to the published latest release instead of a branch-only 0.2.2 asset.
- **Settings › Updates** kept one short caption and no duplicate version label; the version was in the footer.

### Added

- Privacy and standalone unit checks for the User-Agent API, the relay's four-second timeout in a test session and the bounded GET.

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
