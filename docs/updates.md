# Updates

<!-- update-contract: v1 -->

UltraLink follows the project's update contract: it tells you about a newer release and makes updating one step, without collecting usage data.

## Checking

- Fresh installs check the signed Sparkle feed at most once every 24 hours, in the background. The feed is the project's public GitHub latest-release record.
- The check is one anonymous GET with the fixed User-Agent `ultralink-update-check`, set through Sparkle's `userAgentString` API. It sends no user id, app version, usage, machine or OS profile; `SUSendProfileInfo` is off.
- **Timeout gap:** `UpdateFeedProtocol` is registered globally, but the four-second request and resource timeout is proven only for a session that includes the relay; the standalone unit test uses `URLSession.shared`. Sparkle 2.10 creates its appcast request in its own private `NSURLSession` from the default configuration, and Sparkle's private session does not honor the relay. The app therefore cannot enforce a four-second timeout on Sparkle's own feed request; Sparkle's session defaults apply. Do not assume a four-second cap for automatic checks or **Check Now**. Update downloads are not relayed.
- A failed check is logged locally and never shown as noise or retried in a loop.
- Checks are on by default in interactive use. They are off in CI and headless modes (`--probe`, `--snapshot`).

## Choosing

- **Settings › Updates** has **Check for updates automatically** (on for fresh installs), **Install updates automatically** (off for fresh installs), the current version on the left of the last row (`Version 0.3.2` in this build), and **Check Now** on the right, aligned with those switches. There is no explanatory caption under the controls; with the run-time opt-out, the only caption is **Checks are off for this run.**
- Your later choice is saved by Sparkle and is not overwritten at launch, so an existing opt-out stays off.
- To turn checks off for a run or for every launch, set `ULTRALINK_NO_UPDATE_CHECK=1`, or turn off **Check for updates automatically** in Settings. Turning checks off also turns off automatic installation.
- A found update produces a non-modal prompt with the version, release notes, **Install Update**, **Remind Me Later** and **Skip This Version**. **Automatically download and install updates in the future** is unchecked until you check it.

## Installing

- **Install updates automatically** is off by default and only works while automatic checks are on.
- Downloads are verified with the EdDSA public key in `Info.plist`; releases are signed and notarized for macOS. The update applies on relaunch.
- Use **Check for Updates…** in the app menu or **Check Now** in Settings at any time. If the signed feed cannot be read, the app keeps working.

The README keeps a five-line Privacy summary rather than the contract's long form; [PRIVACY.md](../PRIVACY.md) lists every request and every local file with its lifetime.
