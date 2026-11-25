# Changelog

Changes are recorded in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Versions follow [Semantic Versioning](https://semver.org/).

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
