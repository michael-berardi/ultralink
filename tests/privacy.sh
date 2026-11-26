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

# No general HTTP client: the only socket in the app is the local dish transport.
if grep -RIn 'URLSession' Sources | grep -v ':[0-9]*: *//'; then
  fail "URLSession found in shipped code"
fi

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
grep -qF '"User-Agent": "ultralink-update-check"' "$app" || fail "update check User-Agent is not fixed"
grep -qF 'controller?.updater.automaticallyChecksForUpdates ?? true' "$app" ||
  fail "automatic update state does not default to on"
grep -qF 'controller?.updater.automaticallyDownloadsUpdates ?? false' "$app" ||
  fail "automatic installation state does not default to off"

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
