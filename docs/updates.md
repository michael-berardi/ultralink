# Updates

<!-- update-contract: v1 -->

UltraLink updates itself with [Sparkle](https://sparkle-project.org) from the signed feed published with each GitHub release.

## Check

- With **Settings › Updates › Check for updates automatically** on (the default), UltraLink requests the feed at most once a day, in the background. The request is anonymous: fixed user agent `ultralink-update-check`, no version, identifier or system profile.
- No automatic check runs when `CI` is set, when `ULTRALINK_NO_UPDATE_CHECK=1` is set, or in the `--show-…`/`--snapshot` test launches. **Check Now** still works.
- Only stable versions newer than the installed one are offered. A failed automatic check stays quiet and is tried again the next day; **Check Now** shows the cause.

## Notice

- A new version never opens a window over your work. A badge appears next to the menu bar icon, and the popover shows “UltraLink 0.3.0 is available — you have 0.2.0.” with an **Update…** button.
- **Update…** opens the update window: release notes, **Install Update**, **Remind Me Later**, **Skip This Version**, and **Automatically download and install updates in the future** (unchecked by default). A skipped version stays hidden until a newer one is released.
- **Settings › Updates** has **Check for updates automatically** (on), **Install updates automatically** (off), the current version and **Check Now**.

## Automatic install

Off by default. Turn it on with the checkbox in the update window or in **Settings › Updates**. UltraLink then downloads new versions in the background and installs them when it quits. If a download or install fails, the current version keeps working and the update is offered again.

## Safety

Before installing, Sparkle checks the download’s EdDSA signature against the public key built into the app, and checks that the new app is signed by the same developer. The app is replaced in one step. To go back, download the previous version from [Releases](https://github.com/michael-berardi/ultralink/releases).

## What is stored

- Update state (last check time, skipped version, the two switches) lives in UltraLink’s preferences. There is no separate update file and no update log.
- Downloads go to UltraLink’s folder in `~/Library/Caches` and are removed after installing or failing. No copy of the old version is kept.
- To remove everything, quit UltraLink, delete the app, then delete `~/Library/Application Support/UltraLink` and the UltraLink entries in `~/Library/Preferences` and `~/Library/Caches`.
