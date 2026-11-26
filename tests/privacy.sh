#!/bin/sh
# Fails if telemetry code, undocumented remote endpoints, an identifying update
# check, non-private history permissions or detailed logs are reintroduced, or if
# the README privacy section grows past six lines or loses its PRIVACY.md detail.
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

# Every URL in the shipped app must be the project's own GitHub (feed, source link).
urls=$(grep -RhoE 'https?://[^"[:space:]<)]+' Sources Resources/Info.plist | sort -u || true)
for u in $urls; do
  case "$u" in
    https://github.com/michael-berardi/ultralink*|http://www.apple.com/DTDs/PropertyList-1.0.dtd) ;;
    *) fail "undocumented endpoint: $u" ;;
  esac
done

# The daily update check stays anonymous and can be turned off (behavior: tests/updates).
app=Sources/UltraLink/UltraLinkApp.swift
grep -qF 'c.updater.userAgentString = "ultralink-update-check"' "$app" ||
  fail "update check does not use the fixed anonymous User-Agent"
grep -qF 'ULTRALINK_NO_UPDATE_CHECK' Sources/UltraLink/UpdateRules.swift || fail "environment opt-out is missing"
if grep -q '<key>SUSendProfileInfo</key>' Resources/Info.plist &&
   ! grep -A1 '<key>SUSendProfileInfo</key>' Resources/Info.plist | grep -q '<false/>'; then
  fail "update check sends a system profile"
fi

# User readings on disk must stay private, including the unreadable-file backup.
store=Sources/UltraLink/Store.swift
grep -qF '.posixPermissions: 0o700' "$store" || fail "history directory is not private"
grep -qF '.posixPermissions: mode' "$store" || fail "history attributes are not applied"
grep -qF 'protect(url, 0o600)' "$store" || fail "history file is not private"
grep -qF 'protect(backup, 0o600)' "$store" || fail "backup is not private"
grep -qF 'history.unreadable.json"))' "$store" || fail "Erase History leaves the unreadable backup"

# Log messages must not carry addresses, paths or readings.
if grep -REIn '(NSLog|os_log)\(.*(localizedDescription|\\\(error|\.path)' Sources; then
  fail "unfiltered error detail in logs"
fi

# Build tooling that honours the standard opt-out collects nothing.
grep -qx 'export DO_NOT_TRACK=1' scripts/build.sh || fail "build.sh does not set DO_NOT_TRACK=1"

# README Privacy: at most six short lines that link PRIVACY.md; the detail lives there.
section=$(awk '/^## Privacy$/ { on = 1; next } on && /^## / { exit } on && NF' README.md)
lines=$(printf '%s\n' "$section" | grep -c .)
[ "$lines" -ge 3 ] && [ "$lines" -le 6 ] || fail "README Privacy has $lines non-empty lines (3-6 allowed)"
printf '%s' "$section" | grep -qF '(PRIVACY.md)' || fail "README Privacy does not link PRIVACY.md"
printf '%s' "$section" | grep -qi 'no telemetry' || fail "README Privacy does not state there is no telemetry"
printf '%s' "$section" | grep -qF 'Settings › Updates' || fail "README Privacy does not name the update opt-out"
for detail in 'history.json' 'one week of per-minute readings' '400 daily totals' '200 outages' '0700' '0600' \
              'history.unreadable.json' 'Demo mode writes no history' 'no readings, dish ID, addresses or file paths' \
              'Erase History' 'defaults delete com.libertydesignstudio.ultralink' 'Library/Caches/com.libertydesignstudio.ultralink' \
              'ultralink-update-check' 'ULTRALINK_NO_UPDATE_CHECK=1' 'DO_NOT_TRACK=1'; do
  grep -qF "$detail" PRIVACY.md || fail "PRIVACY.md does not document: $detail"
done

# No stale "nothing leaves the Mac" claims now that a daily update check exists.
if grep -nE 'sends nothing to the internet|never sends anything|off by default.*update|update.*off by default' \
   README.md PRIVACY.md Sources/UltraLink/SettingsView.swift | grep -v 'install'; then
  fail "privacy copy contradicts the default anonymous daily update check"
fi

echo "PASS: privacy regression checks"
