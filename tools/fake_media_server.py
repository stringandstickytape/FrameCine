#!/usr/bin/env python3
"""A small UPnP/DLNA media server for testing the app's media-server source (docs/media-servers.md) on a desktop.
Python 3.8+, standard library only. LAN test tool: it answers SSDP searches and serves the folder you give.

    python tools/fake_media_server.py --dir PATH [--port 47950] [--page 200] [--name "Desktop test server"]

It answers M-SEARCH on 239.255.255.250:1900 (if the port can be shared on this PC), serves its device description
at http://IP:PORT/description.xml, answers ContentDirectory Browse at /cd/control (root: "Films" with the folder's
videos, "Music" with one audio item the app should skip, and "Empty"), and serves the files at /media/NAME with
Range requests. --page N caps each Browse answer at N entries, to test paging.
"""

import argparse
import html
import os
import re
import socket
import struct
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote

VIDEO_MIME = {".mkv": "video/x-matroska", ".mp4": "video/mp4", ".webm": "video/webm", ".ts": "video/mp2t",
              ".mov": "video/quicktime", ".avi": "video/x-msvideo"}


def local_ip_for(peer):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((peer, 9))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Server:
    def __init__(self, a):
        self.a = a
        self.udn = str(uuid.uuid5(uuid.NAMESPACE_URL, "fake-media-server-%d" % a.port))
        self.files = sorted(f for f in os.listdir(a.dir) if os.path.splitext(f)[1].lower() in VIDEO_MIME) \
            if a.dir else []
        self.browses = []

    def description(self):
        return """<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><specVersion><major>1</major><minor>0</minor></specVersion>
<device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
<friendlyName>%s</friendlyName><manufacturer>test</manufacturer><modelName>fake_media_server.py</modelName>
<UDN>uuid:%s</UDN><serviceList>
<service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId><controlURL>/cm/control</controlURL><eventSubURL>/cm/event</eventSubURL><SCPDURL>/cm.xml</SCPDURL></service>
<service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType><serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId><controlURL>cd/control</controlURL><eventSubURL>/cd/event</eventSubURL><SCPDURL>/cd.xml</SCPDURL></service>
</serviceList></device></root>""" % (html.escape(self.a.name), self.udn)

    def children(self, oid, host):
        """[(didl element text)] for a container."""
        if oid == "0":
            return ['<container id="1" parentID="0" childCount="%d" restricted="1"><dc:title>Films</dc:title>'
                    '<upnp:class>object.container.storageFolder</upnp:class></container>' % len(self.files),
                    '<container id="2" parentID="0" childCount="1" restricted="1"><dc:title>Music &amp; more</dc:title>'
                    '<upnp:class>object.container.storageFolder</upnp:class></container>',
                    '<container id="3" parentID="0" childCount="0" restricted="1"><dc:title>Empty</dc:title>'
                    '<upnp:class>object.container.storageFolder</upnp:class></container>']
        if oid == "1":
            out = []
            for i, f in enumerate(self.files):
                path = os.path.join(self.a.dir, f)
                mime = VIDEO_MIME[os.path.splitext(f)[1].lower()]
                url = "http://%s:%d/media/%s" % (host, self.a.port, quote(f))
                title = html.escape(os.path.splitext(f)[0])
                out.append('<item id="1$%d" parentID="1" restricted="1"><dc:title>%s</dc:title>'
                           '<upnp:class>object.item.videoItem</upnp:class>'
                           '<res protocolInfo="http-get:*:image/jpeg:*">http://%s:%d/thumb/%d.jpg</res>'
                           '<res protocolInfo="http-get:*:%s:DLNA.ORG_OP=01;DLNA.ORG_CI=0" size="%d" '
                           'duration="0:01:30.000" resolution="1920x1080">%s</res></item>'
                           % (i, title, host, self.a.port, i, mime, os.path.getsize(path), html.escape(url)))
            return out
        if oid == "2":
            return ['<item id="2$0" parentID="2" restricted="1"><dc:title>A song</dc:title>'
                    '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
                    '<res protocolInfo="http-get:*:audio/mpeg:*" size="1000">http://%s:%d/media/song.mp3</res></item>'
                    % (host, self.a.port)]
        if oid == "3":
            return []
        return None

    def browse(self, body, host):
        m = lambda tag: (re.search(r"<%s>(.*?)</%s>" % (tag, tag), body, re.S) or [None, ""])[1]  # noqa: E731
        oid, start, count = html.unescape(m("ObjectID")), int(m("StartingIndex") or 0), int(m("RequestedCount") or 0)
        self.browses.append(oid)
        kids = self.children(oid, host)
        if kids is None:
            return None
        n = min(count or len(kids), self.a.page)
        page = kids[start:start + n]
        didl = ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" '
                'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">' + "".join(page) + "</DIDL-Lite>")
        return ('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
                's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
                '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
                '<Result>%s</Result><NumberReturned>%d</NumberReturned><TotalMatches>%d</TotalMatches>'
                '<UpdateID>1</UpdateID></u:BrowseResponse></s:Body></s:Envelope>'
                % (html.escape(didl, quote=False), len(page), len(kids)))

    def ssdp(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("", 1900))
            mreq = struct.pack("4s4s", socket.inet_aton("239.255.255.250"), socket.inet_aton("0.0.0.0"))
            s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        except OSError as e:
            print("SSDP: can't listen on 1900 (%s); add the server by URL: media_servers url=http://IP:%d/description.xml"
                  % (e, self.a.port), flush=True)
            return
        print("SSDP: answering M-SEARCH on 239.255.255.250:1900", flush=True)
        while True:
            data, addr = s.recvfrom(4096)
            text = data.decode("utf-8", "replace")
            if not text.startswith("M-SEARCH"):
                continue
            st = (re.search(r"(?im)^ST:\s*(.+?)\s*$", text) or [None, ""])[1]
            if st not in ("ssdp:all", "upnp:rootdevice", "urn:schemas-upnp-org:device:MediaServer:1",
                          "urn:schemas-upnp-org:service:ContentDirectory:1"):
                continue
            ip = local_ip_for(addr[0])
            reply = ("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\n"
                     "LOCATION: http://%s:%d/description.xml\r\nSERVER: test/1 UPnP/1.0 fake/1\r\nST: %s\r\n"
                     "USN: uuid:%s::%s\r\n\r\n" % (ip, self.a.port, st, self.udn, st))
            out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            out.sendto(reply.encode(), addr)
            out.close()
            print("SSDP: answered %s:%d (%s)" % (addr[0], addr[1], st), flush=True)


def make_handler(srv):
    class H(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print("HTTP: %s %s" % (self.address_string(), fmt % args), flush=True)

        def _host(self):
            return self.headers.get("Host", "127.0.0.1").split(":")[0]

        def _send(self, code, body, ctype="text/xml; charset=utf-8"):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/description.xml":
                return self._send(200, srv.description())
            if self.path.startswith("/media/"):
                name = unquote(self.path[7:])
                if name not in srv.files:
                    return self._send(404, "no such file", "text/plain")
                path = os.path.join(srv.a.dir, name)
                size = os.path.getsize(path)
                start, end = 0, size - 1
                rng = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
                if rng:
                    if rng.group(1):
                        start = int(rng.group(1))
                        end = int(rng.group(2)) if rng.group(2) else size - 1
                    else:
                        start = size - int(rng.group(2))
                self.send_response(206 if rng else 200)
                self.send_header("Content-Type", VIDEO_MIME[os.path.splitext(name)[1].lower()])
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(end - start + 1))
                if rng:
                    self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
                self.end_headers()
                with open(path, "rb") as f:
                    f.seek(start)
                    left = end - start + 1
                    try:
                        while left > 0:
                            chunk = f.read(min(left, 1 << 16))
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                            left -= len(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                return None
            return self._send(404, "not found", "text/plain")

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
            if self.path == "/cd/control" and "#Browse" in self.headers.get("SOAPAction", ""):
                answer = srv.browse(body, self._host())
                if answer is None:
                    return self._send(500, '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                                           '<s:Fault><detail><UPnPError><errorCode>701</errorCode>'
                                           '<errorDescription>No such object</errorDescription></UPnPError></detail>'
                                           '</s:Fault></s:Body></s:Envelope>')
                return self._send(200, answer)
            return self._send(404, "not found", "text/plain")
    return H


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="", help="folder of videos to serve")
    ap.add_argument("--port", type=int, default=47950)
    ap.add_argument("--page", type=int, default=200, help="most entries per Browse answer")
    ap.add_argument("--name", default="Desktop test server")
    a = ap.parse_args(argv)
    srv = Server(a)
    threading.Thread(target=srv.ssdp, daemon=True).start()
    http = ThreadingHTTPServer(("0.0.0.0", a.port), make_handler(srv))
    print("HTTP: http://%s:%d/description.xml (%d videos)" % (local_ip_for("192.168.0.1"), a.port, len(srv.files)),
          flush=True)
    try:
        http.serve_forever()
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
