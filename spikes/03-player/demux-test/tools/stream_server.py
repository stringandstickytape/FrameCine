#!/usr/bin/env python3
"""Test server for MediaSource's network input (features_test.gd). Local only; for tests, not for use.

  stream_server.py serve ROOT PORT [CERT KEY]   HTTP (or HTTPS with a certificate) for the files under ROOT:
      /PATH                  the file, with Range support (206) and Accept-Ranges
      /redirect/PATH         a 302 to /PATH
      /norange/PATH          the file as a 200 every time, no Range support
      /live/PATH?rate=B      the file as a live feed: chunked, no length, paced at B bytes a second, looped
  stream_server.py udp FILE HOST PORT RATE      sends FILE as MPEG-TS over UDP (7 x 188 bytes a datagram), paced at
                                                RATE bytes a second, looped, until killed
"""

import http.server
import os
import socket
import socketserver
import ssl
import sys
import time
import urllib.parse


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    root = "."

    def log_message(self, *args):
        pass

    def _file(self, path):
        full = os.path.realpath(os.path.join(self.root, path.lstrip("/")))
        if not full.startswith(os.path.realpath(self.root)) or not os.path.isfile(full):
            return None
        return full

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(url.path)
        if path.startswith("/redirect/"):
            self.send_response(302)
            self.send_header("Location", path[len("/redirect"):])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path.startswith("/live/"):
            return self._live(path[len("/live"):], urllib.parse.parse_qs(url.query))
        ranged = not path.startswith("/norange/")
        if not ranged:
            path = path[len("/norange"):]
        full = self._file(path)
        if full is None:
            self.send_error(404)
            return
        size = os.path.getsize(full)
        start, end = 0, size - 1
        header = self.headers.get("Range", "")
        partial = ranged and header.startswith("bytes=")
        if partial:
            first, _, last = header[6:].partition("-")
            start = int(first) if first else 0
            end = int(last) if last else size - 1
            if start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        self.send_response(206 if partial else 200)
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        if ranged:
            self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Content-Type", "application/octet-stream")
        self.end_headers()
        with open(full, "rb") as f:
            f.seek(start)
            left = end - start + 1
            try:
                while left > 0:
                    data = f.read(min(left, 1 << 16))
                    if not data:
                        break
                    self.wfile.write(data)
                    left -= len(data)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass

    def _live(self, path, query):
        full = self._file(path)
        if full is None:
            self.send_error(404)
            return
        rate = float(query.get("rate", ["300000"])[0])
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        start = time.monotonic()
        sent = 0
        piece = 188 * 64
        try:
            while True:
                with open(full, "rb") as f:
                    while True:
                        data = f.read(piece)
                        if not data:
                            break
                        ahead = sent / rate - (time.monotonic() - start)
                        if ahead > 0:
                            time.sleep(ahead)
                        self.wfile.write(b"%x\r\n" % len(data) + data + b"\r\n")
                        sent += len(data)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def serve(root, port, cert=None, key=None):
    Handler.root = root
    server = Server(("127.0.0.1", port), Handler)
    if cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"serving {root} on port {port}{' (https)' if cert else ''}", flush=True)
    server.serve_forever()


def udp(path, host, port, rate):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    start = time.monotonic()
    sent = 0
    while True:
        with open(path, "rb") as f:
            while True:
                data = f.read(188 * 7)
                if not data:
                    break
                ahead = sent / rate - (time.monotonic() - start)
                if ahead > 0:
                    time.sleep(ahead)
                sock.sendto(data, (host, port))
                sent += len(data)


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2], int(sys.argv[3]), *(sys.argv[4:6] if len(sys.argv) >= 6 else []))
    elif sys.argv[1] == "udp":
        udp(sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5]))
