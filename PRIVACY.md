# Privacy

UltraLink has no accounts, telemetry or analytics. It sends nothing about you, your Mac or your dish to anyone.

## The dish

The dish’s unofficial gRPC-web API is normally at `192.168.100.1:9201`. Firmware changes may affect compatibility. UltraLink only reads from it and never changes dish settings. It tries the default route, then Wi-Fi and Ethernet interfaces, which can help when a VPN takes over the default route. This does not guarantee access through every VPN or router configuration.

Status is polled every two seconds when the popover is open or the menu bar shows speeds or latency, otherwise every six seconds. Failed polls use a five-second delay. History is refreshed every ten seconds with the popover open, otherwise every minute. Request time adds to these intervals.

## On this Mac

History stays in `~/Library/Application Support/UltraLink/history.json`: one week of per-minute readings, up to 400 daily totals and 200 outages. The folder is created with mode 0700 and the file 0600, so other accounts on the Mac cannot read them. A history file that cannot be read is moved aside to `history.unreadable.json` (also 0600) instead of being overwritten. Demo mode writes no history.

Settings, including the dish address, are in `~/Library/Preferences/com.libertydesignstudio.ultralink.plist`, together with Sparkle’s update state. A downloaded update waits in `~/Library/Caches/com.libertydesignstudio.ultralink` until it is installed.

UltraLink’s own log messages contain no readings, dish ID, addresses or file paths.

**Settings › Data › Erase History…** deletes the history and any unreadable backup. To remove everything, quit UltraLink, delete the app, `~/Library/Application Support/UltraLink` and `~/Library/Caches/com.libertydesignstudio.ultralink`, then run `defaults delete com.libertydesignstudio.ultralink`.

## Speed test

The speed test runs Apple’s `networkQuality` tool, which contacts Apple’s servers. It runs only when you press **Start**.

## Update check

While **Settings › Updates › Check for updates automatically** is on (the default), UltraLink makes one anonymous request a day for the signed release feed (`appcast.xml`) on GitHub Releases. The request carries the fixed user agent `ultralink-update-check` and no version, identifier, system profile or dish data. Downloading an update fetches the release file from GitHub. Turn the check off in **Settings › Updates**, or set `ULTRALINK_NO_UPDATE_CHECK=1` for a launch. See [docs/updates.md](docs/updates.md).

## Third parties

The only services UltraLink contacts are Apple (the speed test) and GitHub (the update feed, update downloads, and links you click, which open in your browser).

## Building

`scripts/build.sh` sets `DO_NOT_TRACK=1`, so build tools that honour that standard opt-out collect no usage data.
