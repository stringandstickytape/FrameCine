# Media servers on the LAN

Ideas #68 (media-server clients) and #86 (more sources) in `docs/ideas.md`. The app browses UPnP/DLNA media servers on
the LAN and plays their videos as they are, with no transcoding. Many home media-server programs and NAS boxes have
this interface. The code is GDScript only: `app/scripts/net/media_servers.gd` and `app/scripts/net/http_get.gd`.

The server gives each video as an HTTP URL. MediaSource reads http:// and https:// from the PLAYER_INPUTS engine on
(its own HTTP/1.1 reader with a readahead ring; Range requests make a file seekable; a server that ignores Range plays
from the start, not seekable). On an older engine the test pattern stands in, with the reason ("Protocol not found").
A live item, such as a TV channel whose server gives no length, plays as a live stream (app-features, de55674): not
seekable, the overlay says LIVE, and `[network] live_latency` sets its buffer.

## How it works

1. **Discovery.** It sends an SSDP M-SEARCH to 239.255.255.250:1900, twice, for MediaServer and ContentDirectory. It
   collects the LOCATION of every answer from a private address for 3 s. When multicast does not get through, add a
   server by its description URL instead (`media_servers url=...`).
2. **Description.** It reads the device description: the MediaServer device (an embedded one too), its name and
   UDN, and the ContentDirectory service's control URL. The URL is resolved on URLBase or the description's own
   address.
3. **Browse.** It sends a SOAP Browse with BrowseDirectChildren, 200 entries a page, up to 5000. The DIDL-Lite result
   gives folders (id, title, child count) and items. Only videos are kept: `object.item.videoItem`, or a resource of
   type video/*. Each video's resource is its first http-get one with a video type, which is the original on most
   servers, not a thumbnail or a transcode. The size, duration and resolution come from it, and so does whether
   byte seeks work (`DLNA.ORG_OP=x1`).

All of this blocks, so it runs on worker threads. The HTTP client follows redirects, sends a DLNA-style User-Agent,
and has a timeout per request.

## Paths

The file browser's paths for it:

| Path | Lists |
|---|---|
| `upnp://` | the servers found (discovery runs when none are known) |
| `upnp://<uuid>/` | a server's root folder |
| `upnp://<uuid>/<object id>` | a folder (the id is URI-encoded) |

A video's path is its http:// URL. Open it with the folder's other videos as the playlist:
`main.open_path(url, true, sibling_urls)`. The app treats http:// and https:// like smb://. There is no local file
check, the open runs on a worker thread, and there is no folder listing for the playlist.

## Commands

| Command | Arguments | Result |
|---|---|---|
| `media_servers` | `seconds` = 3, or `url` (a description URL) | `[{uuid, name, model, location, control}]` |
| `list_dir` | `path=upnp://...` | entries with `path` (a folder path, or a video's URL), `size`, `duration`, `resolution`, `mime`, `seekable` |
| `open` | `path=http://...` | plays it |

```
python tools/listener.py send media_servers
python tools/listener.py send list_dir path=upnp://
```

The phone remote's file list works on `upnp://` paths too.

## For the pane (app-shell)

Add a "Media servers" place with the path `upnp://`. For paths where `MediaServers.is_upnp(path)` is true, list with
`MediaServers.list(path)` on a worker thread instead of DirectoryLister. It returns the same shape, plus a `path` on
each entry and a `parent`. Open a video with the `path` of the entry; the siblings are the other video paths.

## The test server

`tools/fake_media_server.py --dir FOLDER` (standard library only) answers SSDP searches and serves a device
description. It answers Browse with three folders: "Films" (the folder's videos), "Music & more" (one audio item the
app must skip) and "Empty". It serves the files with Range requests. `--page N` caps each Browse answer, to test
paging.

## Tested

On the desktop only, with the stock 4.7.2 Windows build and the test server, on 2026-10-31.

- **`tests/test_media_servers.gd`** passes. It checks SSDP headers, a description with an embedded MediaServer and a
  relative control URL on URLBase, and a Browse envelope with escaped DIDL. It also checks that the video resource is
  picked over the thumbnail and the song is skipped, the duration, the DLNA byte-seek flag both ways, a relative
  resource URL, and URL splitting and resolving.
- **Live:** `media_servers` found the test server by SSDP (on Windows, with the system's SSDP service running). Then
  `list_dir` listed its three folders with child counts, the two films with size, duration and resolution, and
  titles with "&" in them. "Music & more" came back empty, because the song is skipped. An unknown folder gave the
  server's fault ("No such object"). With `--page 1` the same lists came back in 15 requests instead of 7.
- **Opening a film's URL** (2026-10-31, the fork's x86_64 build with http input, in WSL): `media_servers url=...`,
  `list_dir` down to the video, and `open` with its percent-encoded URL (`.../media/Test%20clip.mkv`). The engine
  logged `HTTP from 127.0.0.1 (7.7 MB, seekable)` and probed the file (H.264, chapters, AAC). The picture was the test
  pattern: on a desktop without the headset's decoder (`/dev/video-dec0`) the app uses the stand-in even for 8-bit
  H.264, so playback and seeking over HTTP were not really exercised.

Not tested: the picture over HTTP (needs the headset's decoder), a real media server, the Frame's Wi-Fi and
multicast, and large libraries. On the command line, `--file=` with a percent-encoded URL arrived decoded ("%20" became a space), so use
the browser or the `open` command for such URLs.
