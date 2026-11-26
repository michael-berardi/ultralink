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

# User readings on disk must stay private, including the unreadable-file backup.
store=Sources/UltraLink/Store.swift
grep -qF '.posixPermissions: 0o700' "$store" || fail "history directory is not private"
grep -qF '.posixPermissions: mode' "$store" || fail "history attributes are not applied"
grep -qF 'protect(url, 0o600)' "$store" || fail "history file is not private"
grep -qF 'protect(backup, 0o600)' "$store" || fail "backup is not private"

# Log messages must not carry addresses, paths or readings.
if grep -REIn 'NSLog\([^)]*localizedDescription|os_log\([^)]*localizedDescription' Sources; then
  fail "unfiltered error detail in logs"
fi

echo "PASS: privacy regression checks"
