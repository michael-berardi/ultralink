#!/bin/sh
# Standalone decoder and update-feed timeout tests; no app launch or dish needed.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -D DEBUG -module-cache-path .build/module-cache Sources/UltraLink/Models.swift Sources/UltraLink/Protobuf.swift Sources/UltraLink/UpdateFeedProtocol.swift tests/unit/main.swift -o .build/unit-tests

# The slow server is loopback-only and exists solely to prove the four-second cap.
python3 tests/slow_feed.py 19203 >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
sleep 0.5
ULTRALINK_TEST_FEED_URL=http://127.0.0.1:19203/appcast.xml .build/unit-tests
sh tests/privacy.sh
