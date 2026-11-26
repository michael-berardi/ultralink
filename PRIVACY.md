# Privacy

UltraLink has no accounts, telemetry or analytics. It sends nothing about you, your Mac or your dish to anyone.

## The dish

The dish’s unofficial gRPC-web API is normally at `192.168.100.1:9201`. Firmware changes may affect compatibility. UltraLink only reads from it and never changes dish settings. It tries the default route, then Wi-Fi and Ethernet interfaces, which can help when a VPN takes over the default route. This does not guarantee access through every VPN or router configuration.

Status is polled every two seconds when the popover is open or the menu bar shows speeds or latency, otherwise every six seconds. Failed polls use a five-second delay. History is refreshed every ten seconds with the popover open, otherwise every minute. Request time adds to these intervals.

## On this Mac

History stays in `~/Library/Application Support/UltraLink/history.json`, with per-minute readings for a week. **Settings › Data › Erase History…** deletes it. Settings are kept in the app’s preferences.

## Speed test

The speed test runs Apple’s `networkQuality` tool, which contacts Apple’s servers. It runs only when you press **Start**.

## Update check

While **Settings › Updates › Check for updates automatically** is on (the default), UltraLink makes one anonymous request a day for the signed release feed (`appcast.xml`) on GitHub Releases. The request carries the fixed user agent `ultralink-update-check` and no version, identifier, system profile or dish data. Downloading an update fetches the release file from GitHub. Turn the check off in **Settings › Updates**, or set `ULTRALINK_NO_UPDATE_CHECK=1` for a launch. See [docs/updates.md](docs/updates.md).
