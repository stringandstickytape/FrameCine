#!/usr/bin/env python3
"""A local HTTP server for app/tests/test_model_download.gd: serves the files of one folder with range requests,
and can misbehave on purpose. Python 3 standard library only.

    python3 model_server.py --dir DIR --port PORT [--log FILE]

Routes (NAME is a file in DIR):
    /full/NAME            200, or 206 for "Range: bytes=N-" (Content-Range set), 416 past the end
    /cut/NAME?at=N        as /full, but the connection closes after byte N of the file (a download cut at half)
    /plain/NAME           ignores Range: always 200 and the whole file
    /stall/NAME?at=N      as /full, but stops sending after byte N and keeps the connection open
    /silent               reads the request and never answers
    /redirect/REST        302 to /REST (as GitHub sends release downloads elsewhere)
    anything else         404
Each request is one line in the log: "PATH RANGE" (RANGE "-" when none).
"""

import argparse
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

CHUNK = 64 * 1024


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--log", default="")
    args = ap.parse_args()
    root = os.path.abspath(args.dir)

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *a):  # quiet: the log file has what the test needs
            pass

        def _log(self):
            if args.log:
                with open(args.log, "a", encoding="utf-8") as f:
                    f.write("%s %s\n" % (self.path, self.headers.get("Range", "-")))

        def _send_status(self, code, extra=None, body=b""):
            self.send_response(code)
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            if body:
                self.wfile.write(body)

        def do_GET(self):
            self._log()
            u = urlsplit(self.path)
            q = parse_qs(u.query)
            parts = u.path.lstrip("/").split("/", 1)
            kind = parts[0]
            rest = parts[1] if len(parts) > 1 else ""
            if kind == "silent":
                time.sleep(600)
                return
            if kind == "redirect":
                self._send_status(302, {"Location": "/" + rest + (("?" + u.query) if u.query else "")})
                return
            if kind not in ("full", "cut", "plain", "stall"):
                self._send_status(404, body=b"not found")
                return
            path = os.path.join(root, os.path.basename(rest))
            if not os.path.isfile(path):
                self._send_status(404, body=b"not found")
                return
            size = os.path.getsize(path)
            start = 0
            rng = self.headers.get("Range", "")
            if kind != "plain" and rng.startswith("bytes=") and rng.endswith("-"):
                start = int(rng[6:-1])
                if start >= size:
                    self._send_status(416, {"Content-Range": "bytes */%d" % size})
                    return
            stop_at = int(q.get("at", [str(size)])[0])
            self.send_response(206 if start > 0 else 200)
            if start > 0:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, size - 1, size))
            self.send_header("Content-Length", str(size - start))
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Connection", "close")
            self.end_headers()
            with open(path, "rb") as f:
                f.seek(start)
                at = start
                while at < size:
                    n = min(CHUNK, size - at)
                    if kind in ("cut", "stall"):
                        n = min(n, stop_at - at)
                        if n <= 0:
                            break
                    data = f.read(n)
                    try:
                        self.wfile.write(data)
                    except (BrokenPipeError, ConnectionResetError):
                        return
                    at += len(data)
            if kind == "stall" and at < size:
                self.wfile.flush()
                time.sleep(600)
            self.close_connection = True

    ThreadingHTTPServer.daemon_threads = True
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("model_server: listening on 127.0.0.1:%d" % args.port, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
