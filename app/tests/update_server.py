#!/usr/bin/env python3
"""A local HTTP server for the updater's tests (app/tests/test_update_net.gd). Standard library only.

  python3 update_server.py ROOT PORT_FILE LOG_FILE

Serves files under ROOT on 127.0.0.1, on a free port that it writes to PORT_FILE. Each request is one line in
LOG_FILE: "<path> range=<Range header or ->". The first part of the path picks the behaviour:

  /ok/<file>        the file; Range requests (bytes=N-) get 206 with Content-Range
  /redirect/<file>  302 to /ok/<file>
  /half/<file>      without Range: the full Content-Length, half the bytes, then the connection closes;
                    with Range: as /ok
  /stall/<file>     without Range: half the bytes, then nothing (the connection stays open); with Range: as /ok
  /silent/<any>     reads the request and never answers
  anything else     404
"""

import http.server
import os
import socketserver
import sys
import threading
import time

ROOT, PORT_FILE, LOG_FILE = sys.argv[1], sys.argv[2], sys.argv[3]
LOCK = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        rng = self.headers.get("Range")
        with LOCK, open(LOG_FILE, "a") as f:
            f.write("%s range=%s\n" % (self.path, rng or "-"))
        parts = self.path.lstrip("/").split("/", 1)
        mode, rest = parts[0], parts[1] if len(parts) > 1 else ""
        if mode == "silent":
            time.sleep(60)
            return
        if mode == "redirect":
            self.send_response(302)
            self.send_header("Location", "/ok/" + rest)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        path = os.path.normpath(os.path.join(ROOT, rest))
        if mode not in ("ok", "half", "stall") or not path.startswith(os.path.abspath(ROOT)) or not os.path.isfile(path):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        data = open(path, "rb").read()
        if rng and rng.startswith("bytes=") and rng.endswith("-"):
            start = int(rng[6:-1])
            if start >= len(data):
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % len(data))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, len(data) - 1, len(data)))
            self.send_header("Content-Length", str(len(data) - start))
            self.end_headers()
            self.wfile.write(data[start:])
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if mode == "ok":
            self.wfile.write(data)
            return
        self.wfile.write(data[: len(data) // 2])
        self.wfile.flush()
        if mode == "stall":
            time.sleep(60)
        self.close_connection = True


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


server = Server(("127.0.0.1", 0), Handler)
with open(PORT_FILE + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
os.replace(PORT_FILE + ".tmp", PORT_FILE)
server.serve_forever()
