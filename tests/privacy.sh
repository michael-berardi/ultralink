#!/bin/sh
# Fails if telemetry code, undocumented remote endpoints, a non-conforming
# update default, or non-private history permissions are reintroduced.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1"; exit 1; }

# Known analytics/crash reporting packages and collection endpoints.
if grep -REIni '(sentry|bugsnag|posthog|mixpanel|amplitude|google-analytics|googletagmanager|segment\.io|heap\.io|plausible\.io|countly|datadog|opentelemetry|appcenter|firebase)' \
   Sources Package.swift Package.resolved Resources scripts; then
  fail "telemetry package or endpoint found"
fi

# No general HTTP client: the dish transport is local, and URLSession is used only
# by the bounded signed-feed relay (never for telemetry or dish data).
feed=Sources/UltraLink/UpdateFeedProtocol.swift
if grep -RIn 'URLSession' Sources | grep -v "^$feed:" | grep -v ':[0-9]*: *//'; then
  fail "URLSession found outside the update-feed relay"
fi
grep -qF 'configuration.timeoutIntervalForRequest = Self.timeout' "$feed" ||
  fail "feed request has no bounded timeout"
grep -qF 'configuration.timeoutIntervalForResource = Self.timeout' "$feed" ||
  fail "feed resource has no bounded timeout"
grep -qF 'static let timeout: TimeInterval = 4' "$feed" ||
  fail "feed timeout is not four seconds"
grep -qF '/releases/latest/download/appcast.xml' "$feed" ||
  fail "feed relay is not scoped to the signed appcast URL"
grep -qF 'url == feedURL || url.hasPrefix(feedURL + "?")' "$feed" ||
  fail "feed relay URL match is not exact"

# Every URL in the shipped app must be one already documented in the README.
urls=$(grep -RhoE 'https?://[^"[:space:]<)]+' Sources Resources/Info.plist | sort -u || true)
for u in $urls; do
  case "$u" in
    https://github.com/michael-berardi/ultralink*|http://www.apple.com/DTDs/PropertyList-1.0.dtd) ;;
    *) fail "undocumented endpoint: $u" ;;
  esac
done

# Update contract v1: checks on by default, install off, anonymous and daily,
# with an environment opt-out. The opposite default must fail this test.
grep -A1 '<key>SUEnableAutomaticChecks</key>' Resources/Info.plist | grep -q '<true/>' ||
  fail "SUEnableAutomaticChecks is not enabled in Info.plist"
grep -A1 '<key>SUAutomaticallyUpdate</key>' Resources/Info.plist | grep -q '<false/>' ||
  fail "automatic installation is not off by default in Info.plist"
grep -A1 '<key>SUSendProfileInfo</key>' Resources/Info.plist | grep -q '<false/>' ||
  fail "system profile is sent with update checks"
grep -A1 '<key>SUScheduledCheckInterval</key>' Resources/Info.plist | grep -q '<integer>86400</integer>' ||
  fail "update checks are not limited to once per 24 h"
app=Sources/UltraLink/UltraLinkApp.swift
if grep -q 'startingUpdater: true' "$app"; then fail "updater starts before the opt-out is evaluated"; fi
grep -qF 'ULTRALINK_NO_UPDATE_CHECK' "$app" || fail "environment opt-out is missing"
grep -qF 'c.updater.userAgentString = "ultralink-update-check"' "$app" ||
  fail "fixed User-Agent is not set through Sparkle's userAgentString API"
if grep -qF '.httpHeaders =' "$app"; then fail "update User-Agent still uses httpHeaders"; fi
grep -qF 'URLProtocol.registerClass(UpdateFeedProtocol.self)' "$app" ||
  fail "bounded update-feed relay is not registered"
if grep -qE 'releases/download/v0\.[0-9]+\.[0-9]+/UltraLink' README.md; then
  fail "README links to a version-pinned asset"
fi
grep -qF '[download the latest published UltraLink release](https://github.com/michael-berardi/ultralink/releases/latest)' README.md ||
  fail "README download link is not the published latest release"
grep -qF 'displayedUpdateState(key: "SUEnableAutomaticChecks", plistDefault: true)' "$app" ||
  fail "automatic update state does not default to on"
grep -qF 'displayedUpdateState(key: "SUAutomaticallyUpdate", plistDefault: false)' "$app" ||
  fail "automatic installation state does not default to off"
grep -qF 'UserDefaults.standard.object(forKey: key) as? NSNumber' "$app" ||
  fail "Settings ignores a saved update preference"
grep -qF 'Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber' "$app" ||
  fail "Settings ignores the Info.plist update default"

# The four-second cap is proven for the relay's own session only, not Sparkle's.
grep -qF "Sparkle's private session does not honor the relay" docs/updates.md ||
  fail "update docs omit the Sparkle relay gap"
grep -qF 'cannot enforce a four-second timeout on Sparkle' docs/updates.md ||
  fail "update docs must state that Sparkle's timeout is not enforced"
if grep -qF 'signed update feed, bounded to four seconds' README.md; then
  fail "README still claims a proven cap on Sparkle's feed request"
fi

# User readings on disk must stay private, including the unreadable-file backup.
store=Sources/UltraLink/Store.swift
grep -qF '.posixPermissions: 0o700' "$store" || fail "history directory is not private"
grep -qF '.posixPermissions: mode' "$store" || fail "history attributes are not applied"
grep -qF 'protect(url, 0o600)' "$store" || fail "history file is not private"
grep -qF 'protect(backup, 0o600)' "$store" || fail "backup is not private"

# The README keeps a short summary and PRIVACY.md keeps the detail.
[ -f PRIVACY.md ] || fail "PRIVACY.md is missing"
grep -qF '(PRIVACY.md)' README.md || fail "README does not link to PRIVACY.md"
privacy_lines=$(awk '/^## Privacy$/{f=1;next} /^## /{f=0} f && NF' README.md | wc -l | tr -d ' ')
[ "$privacy_lines" -ge 3 ] && [ "$privacy_lines" -le 6 ] ||
  fail "README Privacy section is not 3-6 lines ($privacy_lines)"
if awk '/^## Privacy$/{f=1;next} /^## /{f=0} f' README.md | grep -qE 'Application Support|Library/Caches|defaults delete'; then
  fail "README Privacy section still carries the local-path detail"
fi
grep -qF 'The only automatic internet request' README.md ||
  fail "README still describes the update check as the only automatic request"
grep -qF 'skipped **only** in demo mode: `--probe` still sweeps' PRIVACY.md ||
  fail "PRIVACY.md does not state that only demo mode skips the sweep"
if grep -qF 'neither demo mode nor `--probe` mode' PRIVACY.md; then
  fail "PRIVACY.md still claims the sweep is skipped in probe mode"
fi
for detail in 'history.json' 'history.unreadable.json' 'com.libertydesignstudio.ultralink' \
              'Library/Caches' 'TMPDIR' 'networkQuality'; do
  grep -qF "$detail" PRIVACY.md || fail "PRIVACY.md omits $detail"
done

# Every local write has a bounded lifetime enforced by the launch sweep.
ret=Sources/UltraLink/Retention.swift
[ -f "$ret" ] || fail "Retention.swift is missing"
grep -qF 'static let unreadableHistory: TimeInterval = 7 * 86_400' "$ret" ||
  fail "unreadable-history backup has no seven-day bound"
grep -qF 'static let updateDownload: TimeInterval = 7 * 86_400' "$ret" ||
  fail "update downloads have no seven-day bound"
grep -qF 'static let temporary: TimeInterval = 86_400' "$ret" ||
  fail "temporary files have no one-day bound"
grep -qF 'static func sweep(' "$ret" || fail "retention sweep is missing"
grep -qF 'names: [unreadableName]' "$ret" ||
  fail "sweep does not limit the history folder to its own backup"
grep -qF 'Retention.sweep()' Sources/UltraLink/UltraLinkApp.swift ||
  fail "retention sweep is not run at launch"
grep -qF 'if !Monitor.shared.demo { Retention.sweep() }' Sources/UltraLink/UltraLinkApp.swift ||
  fail "retention sweep is not skipped in demo mode"
grep -qF 'static var directoryPath: URL' "$store" ||
  fail "Store creates the history folder before the sweep can run"
grep -qF 'Retention.unreadableName' "$store" ||
  fail "Store and Retention disagree on the backup name"
grep -qF 'Sources/UltraLink/Retention.swift' tests/unit.sh ||
  fail "the retention test is not compiled"
grep -qF 'retention sweep bounds unreadable-history copies' tests/unit/main.swift ||
  fail "the retention regression test is missing"
grep -qF 'PASS: retention sweep keeps a fresh nested download in an old cache folder' tests/unit/main.swift ||
  fail "the fresh nested download regression test is missing"

# Log messages must not carry addresses, paths or readings.
if grep -REIn 'NSLog\([^)]*localizedDescription|os_log\([^)]*localizedDescription' Sources; then
  fail "unfiltered error detail in logs"
fi

echo "PASS: privacy regression checks"
