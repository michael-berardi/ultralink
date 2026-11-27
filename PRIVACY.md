# Privacy

UltraLink is a local reader for a Starlink dish. It has no telemetry, no analytics, no crash reporting, no account and no identifier, and it never changes the dish's settings. This page lists every request UltraLink can make and every file it can leave on this Mac, with each file's lifetime and how to remove it. The README keeps the short version.

## What goes over the network

| Request | When | What it carries | To whom |
| --- | --- | --- | --- |
| Dish status and history poll | While UltraLink runs | Only the read-only gRPC-web request itself: no id, no readings, no machine profile | Your dish at the address you set, default `192.168.100.1:9201`, over your local network |
| Update feed check | Once a day, unless you opt out | One anonymous GET with the fixed User-Agent `ultralink-update-check`; no user id, app version, usage, machine or OS profile (`SUSendProfileInfo` is off) | GitHub (`releases/latest/download/appcast.xml`) |
| Update download | Only when you choose **Install Update** in the update window, or when automatic installation is on | A plain signed download, verified with the EdDSA key in `Info.plist` before it is installed | GitHub |
| Speed test | Only when you press **Start** | Whatever macOS `networkQuality` sends to Apple's own servers | Apple |
| Links you click | Only when you click them | Your browser's normal request | Wherever the link points |

UltraLink's own code has no general HTTP client and no telemetry SDK: the dish transport is local, Sparkle handles the update feed and download, and the speed test is Apple's tool. Nothing about your dish readings, your Mac or your usage is uploaded.

## What stays on this Mac

Everything below is written by UltraLink itself. Nothing in it is uploaded.

| Path | What it holds | Lifetime | How to remove it |
| --- | --- | --- | --- |
| `~/Library/Application Support/UltraLink/history.json` | one week of per-minute readings, up to 400 daily totals and 200 outages. Folder `0700`, file `0600`. | The newest week only; older buckets, days and outages are pruned continuously while the app runs | **Settings › Data › Erase History…**, or delete the folder after quitting |
| `~/Library/Application Support/UltraLink/history.unreadable.json` | A private backup of `history.json`, written only when that file cannot be decoded, so the damage can be inspected | **7 days** from the broken file's own timestamp, then deleted automatically at launch (`Retention.unreadableHistory`) | Same as above, or wait for the automatic sweep |
| `~/Library/Preferences/com.libertydesignstudio.ultralink.plist` | Your settings: dish address, demo mode, notification and update choices | Until you remove it | Quit UltraLink, run `defaults delete com.libertydesignstudio.ultralink` |
| `~/Library/Caches/com.libertydesignstudio.ultralink/` | Update downloads and partial downloads Sparkle stages there | **7 days** per file, counted from that file's own modification date; stale leftovers are deleted automatically at launch (`Retention.updateDownload`), while a fresh nested download and its folders stay until it is used | Delete the folder after quitting |
| `$TMPDIR/UltraLink/` | Private scratch space. No file is kept here today. | **1 day** for anything that appears, then deleted automatically at launch (`Retention.temporary`) | Nothing to do |

Lifetime notes:

- The bounds live in `Sources/UltraLink/Retention.swift`. `Retention.sweep()` runs once at launch before any update check and only deletes: it never writes a file and never creates a folder. It is skipped **only** in demo mode: `--probe` still sweeps. Every file is judged by its own modification date, so an old cache folder never takes a fresh download with it.
- `tests/unit.sh` covers the bounds: `tests/unit/main.swift` plants stale and fresh files in a scratch folder and proves that stale unreadable-history copies, update downloads and temporary files are removed while `history.json`, recent downloads (including nested files in old folders) and files UltraLink does not own are kept. A missing directory is a no-op.
- **Demo mode writes no history** and no settings.
- **UltraLink's own logs** (`NSLog`, visible in Console) contain no readings, dish ID, addresses or file paths. Poll, notification, login and history failures are logged as short phrases, and a failed update check is not retried in a loop.
- `--snapshot <dir>` (QA only) writes PNG files into the directory you name on the command line. Those are your files, outside the paths above, and you delete them yourself.

## Update checks

For fresh installs UltraLink checks the signed GitHub feed once a day; automatic installation is an opt-in you turn on yourself. A found update is gentle: a badge appears beside the menu bar icon and a line in the popover, and **Update…** opens the update window with **Install Update**, **Remind Me Later** and **Skip This Version**. Its release notes come from the changelog in the app, not a web page. Turn checks off in **Settings › Updates** or with `ULTRALINK_NO_UPDATE_CHECK=1`; scheduled checks are also suppressed under `CI` and in `--show-…`/`--snapshot` QA launches unless `--scheduled-check` asks for one. **Check Now** remains available when you ask for it, and a later Settings choice is preserved across launches. See [docs/updates.md](docs/updates.md).

## Removing everything

1. Quit UltraLink.
2. Delete `~/Library/Application Support/UltraLink` and `~/Library/Caches/com.libertydesignstudio.ultralink`.
3. Run `defaults delete com.libertydesignstudio.ultralink`.

UltraLink is not sandboxed, so those three steps cover its footprint. The only third parties it contacts are GitHub (the update feed, downloads and links you click) and Apple (`networkQuality`), in the cases listed above.

## Building

`scripts/build.sh` sets `DO_NOT_TRACK=1`, so build tools that honour that standard opt-out collect no usage data.
