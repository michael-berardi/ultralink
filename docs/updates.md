# Updates

<!-- update-contract: v1 -->

UltraLink follows the project's update contract: it tells you about a newer release and makes updating one step, without collecting usage data.

## Checking

- Fresh installs check the signed Sparkle feed at most once every 24 hours, in the background, with a short timeout. The feed is the project's public GitHub latest-release record.
- The check is one anonymous GET with the fixed User-Agent `ultralink-update-check`. It sends no user id, app version, usage, machine or OS profile; `SUSendProfileInfo` is off.
- A failed check is logged locally and never shown as noise or retried in a loop.
- Checks are on by default in interactive use. They are off in CI and headless modes (`--probe`, `--snapshot`).

## Choosing

- **Settings › Updates** has **Check for updates automatically** (on for fresh installs), **Check Now**, and the current version. Your later choice is saved by Sparkle and is not overwritten at launch, so an existing opt-out stays off.
- To turn checks off for a run or for every launch, set `ULTRALINK_NO_UPDATE_CHECK=1`, or turn off **Check for updates automatically** in Settings. Turning checks off also turns off automatic installation.
- A found update produces a non-modal prompt with the version, release notes, **Install Update**, **Remind Me Later** and **Skip This Version**. **Automatically download and install updates in the future** is unchecked until you check it.

## Installing

- **Install updates automatically** is off by default and only works while automatic checks are on.
- Downloads are verified with the EdDSA public key in `Info.plist`; releases are signed and notarized for macOS. The update applies on relaunch.
- Use **Check for Updates…** in the app menu or **Check Now** in Settings at any time. If the signed feed cannot be read, the app keeps working.
