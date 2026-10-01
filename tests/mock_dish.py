#!/usr/bin/env python3
"""A fake Starlink dish for testing UltraLink's wire path without hardware.

Serves the dish's grpc-web endpoint (POST /SpaceX.API.Device.Device/Handle) with synthetic readings,
encoded with the real schema. The schema is the descriptor set dumped from a dish's gRPC reflection
(e.g. with sparky8512/starlink-grpc-tools `extract_protoset.py`, or grpcurl -protoset-out).

    tests/mock_dish.py --protoset path/to/dish.protoset [--port 9201] [--outage]
    UltraLink --probe 127.0.0.1 --port 9201
"""
import argparse, math, struct, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from google.protobuf import descriptor_pb2, descriptor_pool, json_format, message_factory

ap = argparse.ArgumentParser()
ap.add_argument("--protoset", required=True)
ap.add_argument("--port", type=int, default=9201)
ap.add_argument("--outage", action="store_true", help="report the dish as in an outage")
args = ap.parse_args()

fds = descriptor_pb2.FileDescriptorSet()
fds.ParseFromString(open(args.protoset, "rb").read())
pool = descriptor_pool.DescriptorPool()
for f in fds.file:
    pool.Add(f)
Response = message_factory.GetMessageClass(pool.FindMessageTypeByName("SpaceX.API.Device.Response"))
Request = message_factory.GetMessageClass(pool.FindMessageTypeByName("SpaceX.API.Device.Request"))
START = time.time()


def status():
    t = time.time()
    d = {"dishGetStatus": {
        "deviceInfo": {"id": "ut-mock", "hardwareVersion": "rev4_panda_prod2", "softwareVersion": "2026.07.06.mr81950", "countryCode": "US"},
        "deviceState": {"uptimeS": str(int(t - START) + 7200)},
        "obstructionStats": {"fractionObstructed": 0.012, "currentlyObstructed": False},
        "alerts": {"slowEthernetSpeeds": True},
        "downlinkThroughputBps": 120e6 + 30e6 * math.sin(t / 5), "uplinkThroughputBps": 14e6, "popPingLatencyMs": 31.5, "popPingDropRate": 0.0,
        "gpsStats": {"gpsValid": True, "gpsSats": 18}, "ethSpeedMbps": 1000, "boresightAzimuthDeg": 358.6, "boresightElevationDeg": 76.7,
        "disablementCode": "OKAY", "softwareUpdateState": "IDLE",
    }}
    if args.outage:
        d["dishGetStatus"]["outage"] = {"cause": "OBSTRUCTED", "startTimestampNs": "1"}
    return d


def history():
    cur = int(time.time() - START) + 2000
    n = 900
    arr = lambda f: [f(cur - n + 1 + ((i - cur) % n)) for i in range(n)]  # index i holds counter c with c % n == i
    return {"dishGetHistory": {
        "current": str(cur),
        "popPingDropRate": arr(lambda c: 0.0),
        "popPingLatencyMs": arr(lambda c: 30 + 5 * math.sin(c / 9)),
        "downlinkThroughputBps": arr(lambda c: 100e6 + 40e6 * math.sin(c / 30)),
        "uplinkThroughputBps": arr(lambda c: 12e6),
        "powerIn": arr(lambda c: 38.0),
        "outages": [{"cause": "OBSTRUCTED", "startTimestampNs": str(int((time.time() - 90 - 315964782) * 1e9)), "durationNs": "7000000000"}],
    }}


def obstruction():
    n = 123
    snr = [(-1 if (x - 61) ** 2 + (y - 61) ** 2 > 61 ** 2 else (0 if x > 90 and y < 40 else 0.9)) for y in range(n) for x in range(n)]
    return {"dishGetObstructionMap": {"numRows": n, "numCols": n, "snr": snr, "minElevationDeg": 10, "maxThetaDeg": 80}}


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        assert body[0] == 0, "expected an uncompressed grpc-web message frame"
        req = Request(); req.ParseFromString(body[5:5 + struct.unpack(">I", body[1:5])[0]])
        which = req.WhichOneof("request")
        build = {"get_status": status, "get_history": history, "dish_get_obstruction_map": obstruction}.get(which)
        if not build:
            self.send_response(200); self.send_header("grpc-status", "12"); self.send_header("grpc-message", "unimplemented"); self.end_headers(); return
        msg = Response(); json_format.ParseDict(build(), msg)
        payload = msg.SerializeToString()
        out = b"\x00" + struct.pack(">I", len(payload)) + payload
        trailer = b"grpc-status: 0\r\n"
        out += b"\x80" + struct.pack(">I", len(trailer)) + trailer
        self.send_response(200); self.send_header("Content-Type", "application/grpc-web+proto"); self.send_header("Content-Length", str(len(out))); self.end_headers()
        self.wfile.write(out)
        print(f"{which} -> {len(payload)} B", flush=True)

    def log_message(self, *a): pass


print(f"mock dish on 127.0.0.1:{args.port}", flush=True)
ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()
