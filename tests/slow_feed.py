#!/usr/bin/env python3
"""Local, loopback-only slow HTTP server for the update-feed timeout test."""
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class SlowHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(10)  # Longer than the four-second client timeout.
        self.send_response(200)
        self.send_header("Content-Type", "application/xml")
        self.end_headers()
        self.wfile.write(b"<rss/>")

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1])
    ThreadingHTTPServer(("127.0.0.1", port), SlowHandler).serve_forever()
