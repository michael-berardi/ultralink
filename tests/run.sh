#!/bin/sh
# End-to-end check of the wire path: a mock dish encodes real-schema messages, UltraLink --probe decodes them.
#   tests/run.sh path/to/dish.protoset
set -eu
cd "$(dirname "$0")/.."
protoset="${1:?pass a dish.protoset (dumped via gRPC reflection)}"
bin=${ULTRALINK_BIN:-dist/UltraLink.app/Contents/MacOS/UltraLink}
port=19201
python3 tests/mock_dish.py --protoset "$protoset" --port $port >/dev/null &
mock=$!
trap 'kill $mock 2>/dev/null' EXIT
sleep 1.5
out=$("$bin" --probe 127.0.0.1 --port $port)
echo "$out"
echo "$out" | grep -q "hw rev4_panda_prod2" || { echo "FAIL: device info"; exit 1; }
echo "$out" | grep -q 'slow_ethernet_speeds' || { echo "FAIL: alerts"; exit 1; }
echo "$out" | grep -q "samples 900" || { echo "FAIL: history ring"; exit 1; }
echo "$out" | grep -q "Obstructed 7s" || { echo "FAIL: outage decode"; exit 1; }
echo "$out" | grep -q "123x123" || { echo "FAIL: obstruction map"; exit 1; }
echo "PASS"
