#!/bin/sh
# Standalone decoder, update-rule and privacy tests; no app launch, dish, or schema needed.
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -module-cache-path .build/module-cache Sources/UltraLink/Models.swift Sources/UltraLink/Protobuf.swift tests/unit/main.swift -o .build/unit-tests
.build/unit-tests
swiftc -module-cache-path .build/module-cache Sources/UltraLink/UpdateRules.swift tests/updates/main.swift -o .build/update-tests
.build/update-tests
sh tests/privacy.sh
