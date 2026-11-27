#!/bin/sh
# Fails if telemetry code, undocumented remote endpoints, an identifying update
# check, non-private history permissions, unbounded local leftovers, detailed logs,
# or a README privacy section that hides the detail in PRIVACY.md are reintroduced.
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
grep -A1 '<key>SUSendProfileInfo</key>' Resources/Info.plist | grep -q '<false/>' ||
  fail "update check sends a system profile"

# Version 0.3.2 is not a published release: link to the published download instead.
if grep -qE 'releases/download/v0\.[0-9]+\.[0-9]+/UltraLink' README.md; then
  fail "README links to a version-pinned download asset"
fi
grep -qF '[download the latest published UltraLink release](https://github.com/michael-berardi/ultralink/releases/latest)' README.md ||
  fail "README download link is not the published latest release"

# User readings on disk must stay private, including the unreadable-file backup.
store=Sources/UltraLink/Store.swift
grep -qF '.posixPermissions: 0o700' "$store" || fail "history directory is not private"
grep -qF '.posixPermissions: mode' "$store" || fail "history attributes are not applied"
grep -qF 'protect(url, 0o600)' "$store" || fail "history file is not private"
grep -qF 'protect(backup, 0o600)' "$store" || fail "backup is not private"
grep -qF 'Retention.unreadableName' "$store" || fail "Erase History leaves the unreadable backup"

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
grep -qF 'Sources/UltraLink/Retention.swift' tests/unit.sh ||
  fail "the retention test is not compiled"
grep -qF 'retention sweep bounds unreadable-history copies' tests/unit/main.swift ||
  fail "the retention regression test is missing"
grep -qF 'PASS: retention sweep keeps a fresh nested download in an old cache folder' tests/unit/main.swift ||
  fail "the fresh nested download regression test is missing"

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
printf '%s' "$section" | grep -qF 'The only automatic internet request' ||
  fail "README Privacy does not describe the automatic request"
for detail in 'history.json' 'one week of per-minute readings' '400 daily totals' '200 outages' '0700' '0600' \
              'history.unreadable.json' 'Demo mode writes no history' 'no readings, dish ID, addresses or file paths' \
              'Erase History' 'defaults delete com.libertydesignstudio.ultralink' 'Library/Caches/com.libertydesignstudio.ultralink' \
              'ultralink-update-check' 'ULTRALINK_NO_UPDATE_CHECK=1' 'DO_NOT_TRACK=1' 'networkQuality' 'TMPDIR' \
              'com.libertydesignstudio.ultralink'; do
  grep -qF "$detail" PRIVACY.md || fail "PRIVACY.md does not document: $detail"
done
grep -qF 'skipped **only** in demo mode: `--probe` still sweeps' PRIVACY.md ||
  fail "PRIVACY.md does not state that only demo mode skips the sweep"
if grep -qF 'neither demo mode nor `--probe` mode' PRIVACY.md; then
  fail "PRIVACY.md still claims the sweep is skipped in probe mode"
fi

# No stale "nothing leaves the Mac" claims now that a daily update check exists.
if grep -nE 'sends nothing to the internet|never sends anything|off by default.*update|update.*off by default' \
   README.md PRIVACY.md Sources/UltraLink/SettingsView.swift | grep -v 'install'; then
  fail "privacy copy contradicts the default anonymous daily update check"
fi

echo "PASS: privacy regression checks"
