# Privacy

UltraLink is a local reader for a Starlink dish. It has no telemetry, no analytics, no crash
reporting, no account and no identifier, and it never changes the dish's settings. This page lists
every request UltraLink can make and every file it can leave on this Mac, with each file's lifetime
and how to remove it. The README keeps the short version.

## What goes over the network

| Request | When | What it carries | To whom |
| --- | --- | --- | --- |
| Dish status and history poll | While UltraLink runs | Nothing but the read-only gRPC-web request itself: no id, no readings, no machine profile | Your dish at the address you set, default `192.168.100.1:9201`, over your local network |
| Update feed check | Once a day, unless you opt out | One anonymous GET with the fixed User-Agent `ultralink-update-check`; no user id, app version, usage, machine or OS profile (`SUSendProfileInfo` is off) | GitHub (`releases/latest/download/appcast.xml`) |
| Update download | Only when you accept a found update, or with automatic installation on | A plain signed download; verified with the EdDSA key in `Info.plist` before it is installed | GitHub |
| Speed test | Only when you press **Start** | Whatever macOS `networkQuality` sends to Apple's own servers | Apple |
| Links you click | Only when you click them | Your browser's normal request | Wherever the link points |

Nothing else is sent. There is no general HTTP client in the app: `URLSession` appears only in the
bounded update-feed relay, and the privacy regression check fails the build if it spreads.

**Timeout gap:** `UpdateFeedProtocol` caps a feed GET at four seconds only for a session that uses
that relay. Sparkle 2.10 makes its appcast request in its own private `NSURLSession`, which does not
honor the relay, so UltraLink cannot enforce a four-second timeout on Sparkle's own check.
[docs/updates.md](docs/updates.md) records the exact gap.

## What stays on this Mac

Everything below is written by UltraLink itself. Nothing in it is uploaded.

| Path | What it holds | Lifetime | How to remove it |
| --- | --- | --- | --- |
| `~/Library/Application Support/UltraLink/history.json` | One week of per-minute readings, up to 400 daily totals and 200 outages. Folder `0700`, file `0600`. | The newest week only; older buckets, days and outages are pruned continuously while the app runs | **Settings › Data › Erase History…**, or delete the folder after quitting |
| `~/Library/Application Support/UltraLink/history.unreadable.json` | A private backup of `history.json` written only when that file cannot be decoded, kept so the damage can be inspected | **7 days** after it was written, then deleted automatically at launch (`Retention.unreadableHistory`) | Same as above, or just wait for the automatic sweep |
| `~/Library/Preferences/com.libertydesignstudio.ultralink.plist` | Your settings: dish address, demo mode, notification and update choices | Until you remove it | Quit UltraLink, run `defaults delete com.libertydesignstudio.ultralink` |
| `~/Library/Caches/com.libertydesignstudio.ultralink/` | Update downloads and partial downloads that Sparkle stages there | **7 days** for anything left behind, then deleted automatically at launch (`Retention.updateDownload`); a fresh download stays until it is used | Delete the folder after quitting |
| `$TMPDIR/UltraLink/` | Private scratch space. No file is kept here today. | **1 day** for anything that appears, then deleted automatically at launch (`Retention.temporary`) | Nothing to do |

Lifetime notes:

- Retention bounds live in `Sources/UltraLink/Retention.swift` and are enforced by `Retention.sweep()`,
  which the app runs once at launch before any update check. The sweep only deletes; it never writes
  a file and never creates a folder, and it runs in neither demo mode nor `--probe` mode.
- `tests/unit` covers the bounds: `tests/unit/main.swift` plants stale and fresh files in a scratch
  folder and proves that stale unreadable-history copies, update downloads and temp files are removed
  while `history.json`, recent downloads and files UltraLink does not own are kept.
- **Demo mode** writes no history and no settings.
- **UltraLink's own logs** (`NSLog`, visible in Console) contain no readings, dish ID, addresses or
  paths. A failed update check and an unreadable history are logged as short phrases only, and a
  failed check is never retried in a loop.
- `--snapshot <dir>` (QA only) writes PNG files into the directory you name on the command line.
  Those are your files, they are not in any of the paths above, and you delete them yourself.
- `--probe` and `--demo` write no history file.

## Update checks

The daily check is on by default for fresh installs, sending the anonymous GET described above.
Automatic installation is off unless you opt in. Turn checks off in **Settings › Updates** or with
`ULTRALINK_NO_UPDATE_CHECK=1`; checks are also off in CI and in headless (`--probe`, `--snapshot`)
runs. Your later choice is preserved across launches. See [docs/updates.md](docs/updates.md).

## Removing everything

1. Quit UltraLink.
2. Delete `~/Library/Application Support/UltraLink` and `~/Library/Caches/com.libertydesignstudio.ultralink`.
3. Run `defaults delete com.libertydesignstudio.ultralink`.

UltraLink is not sandboxed, so those three steps are the whole of its footprint. The only third
parties contacted are GitHub (updates and the links you click) and Apple (`networkQuality`), and
only in the cases listed above.
