#!/bin/sh
# Fails if telemetry code, undocumented remote endpoints, automatic update
# checks, or non-private history permissions are reintroduced.
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

# Update checks must stay off until the user asks for them.
grep -A1 '<key>SUEnableAutomaticChecks</key>' Resources/Info.plist | grep -q '<false/>' ||
  fail "SUEnableAutomaticChecks is enabled in Info.plist"
app=Sources/UltraLink/UltraLinkApp.swift
if grep -q 'startingUpdater: true' "$app"; then fail "updater starts before the opt-out"; fi
optout=$(grep -n 'c.updater.automaticallyChecksForUpdates = false' "$app" | cut -d: -f1)
startup=$(grep -n 'c.startUpdater()' "$app" | cut -d: -f1)
[ -n "$optout" ] && [ -n "$startup" ] && [ "$optout" -lt "$startup" ] ||
  fail "automatic checks are not disabled before startUpdater"
grep -qF 'automaticallyChecksForUpdates ?? false' "$app" || fail "automatic update state defaults to on"

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
