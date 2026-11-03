# The headset as a media server

Idea #89 in `docs/ideas.md`. The headset serves its own folders over HTTP on the LAN. Use it to pull films and
screenshots to a PC or phone, to upload files into a Drop folder, and to play the headset's files on another player.
It reuses the phone remote's server (`app/scripts/remote/remote_server.gd`). The routes are in
`app/scripts/remote/share_routes.gd`.

## On and off

It is off by default. Turn it on in one of these ways:
- `--share` on the command line;
- `[share] enabled = true` in the settings;
- the pane: `remote.start_share(main, true)`, and `stop_share` to turn it off;
- the `share_files on=true` command. This is at the change level, so the PC link needs the allowed window, and the
  phone remote cannot turn it on.

The phone remote and sharing are separate switches on one server (port 47880). With only sharing on, the remote's
page and API answer 404. With only the remote on, `/share` answers 404.

The rules are the same as for the remote:
- Only private addresses can connect.
- Every request needs the pairing code, as `?k=CODE` or `X-Remote-Key`.
- The code is never logged, and the `share_files` reply does not contain it. The pane shows it, and
  `server.get_share_url()` gives the address with the code, for a QR code.

## What it serves

| Request | Does |
|---|---|
| `GET /share?k=CODE` | a page: the folders, their files as links, "Screenshot now", and an upload box |
| `GET /share/list?k=CODE` | the folders: `{roots: [{name, writable}]}`; with `root=N&path=P`, a folder: `{entries: [{name, is_dir, size, modified}]}` |
| `GET /share/file/N/PATH?k=CODE` | a file, with Range requests, so a player on the PC can seek in a film on the headset. It is sent from disk piece by piece. |
| `PUT /share/upload/NAME?k=CODE` | the body is saved in Drop with a Content-Length of up to 64 GB. An existing file is never overwritten: the copy is "name (2).ext". A cut-off upload is removed. 507 if the disk is short of space. |
| `GET /share/screenshot.png?k=CODE&width=960` | a new screenshot of both eyes, also kept in Screenshots |

The folders are the `[share] folders` list if one is set, else Videos and Downloads. Then come Drop
(`[share] drop`, default `~/Videos/Drop`), which is the only writable one, and Screenshots (`user://screenshots`). A path
cannot leave its folder: `..`, absolute paths, backslashes and NUL are refused.

```
curl -O "http://HEADSET:47880/share/file/0/film.mkv?k=CODE"
curl -T clip.mkv "http://HEADSET:47880/share/upload/clip.mkv?k=CODE"
```

A player on the PC can play `http://HEADSET:47880/share/file/0/film.mkv?k=CODE` directly and seek in it.

The frame never waits. Downloads go out as the socket takes them. An upload is read on its own thread, because one
read per frame limited it to about 4 MB/s on the desktop.

## Tested

On the desktop only, with the stock 4.7.2 Windows build, on 2026-10-31. The user folder was a scratch one, so no real
folder was written.

- **Access:** no code gave 403. The remote's page gave 404 while only sharing was on, and `/share` gave 404 while
  only the remote was on. With both on, both worked.
- **Upload:** a 30 MB upload was saved at about 700 MB/s over loopback. A second upload with the same name became
  "test clip (2).mkv".
- **Download:** the file came back identical at about 170 to 240 MB/s. `bytes=1000-1999` and `bytes=-500` gave the
  right bytes with 206. A range past the end gave 416.
- **Paths:** three escape attempts (`..%2F..`, `../..`, and a list with `path=../..`) gave 404.
- **Screenshot:** a 320 px wide PNG came back and was kept in Screenshots. The page listed the files and had the
  upload box.
- **A cut-off upload** (1 MB of 10 MB, then the connection closed) left no file.
- **`share_files`** was refused without the allowed window. With it, it turned sharing on and off. The pairing code
  did not appear in the PC listener's log.

Not tested on the device: Wi-Fi rates, a phone's browser, SteamOS's Videos and Downloads folders, and the space check
on the Frame's storage.
