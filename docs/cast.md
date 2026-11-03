# Cast from the PC

Idea #43 in `docs/ideas.md`. Play a file on the headset from the PC: from a terminal, from Explorer's "Send to"
menu, by dropping files on a desktop icon, or by putting a file in a watched folder. The tool is `tools/cast.py`,
Python 3.8 or later with the standard library only.

It sends `open` over the dev link (`docs/dev/control-protocol.md`). So the listener must run on the PC
(`python tools/listener.py serve`), and the headset must be connected to it (`--listener=<PC address>`).

## Use

```
python tools/cast.py D:/Videos/film.mkv            # a file in a shared folder of the PC
python tools/cast.py D:/Videos/film.mkv --seek 600 # start at 10 minutes
python tools/cast.py smb://nas/films/a.mkv         # an smb:// URL as it is
python tools/cast.py /home/steamos/films/a.mkv     # a file on the headset
python tools/cast.py https://example.com/page      # a web page, through the Browser source
python tools/cast.py --dry-run D:/Videos/film.mkv  # print the URL only
```

The headset makes the file's folder the playlist, as when a file is opened in the pane. With several files, as from
a multi-select Send to, the first one plays.

## How a PC file becomes a URL

The headset reads the file from the PC's file share, so nothing is copied:

1. **The share.** The tool reads the PC's own shares with `Get-SmbShare` on Windows. It takes the most specific
   share that contains the file, so `D:\Videos\a.mkv` with a `Videos` share becomes `smb://<host>/Videos/a.mkv`.
   `--map LOCAL=smb://host/share` adds or overrides a mapping, for example for a NAS. A file outside every shared
   folder is refused with a hint.
2. **The host.** The tool asks the headset for its saved hosts (Network place). It uses the saved host that names
   this PC, so the headset has the user name and password. If none matches, it uses the PC's name and warns:
   "add it under Network > Add host". `--host NAME` sets it.

## Drop targets

```
python tools/cast.py --install-sendto      # Explorer: right-click > Send to > Play on headset
python tools/cast.py --install-desktop     # a "Play on headset" icon on the desktop: drop files on it
python tools/cast.py --watch D:/Videos/_cast   # cast each video file that appears in the folder
```

The two installers write a small `Play on headset.cmd` that runs `cast.py` with the dropped or sent files. If the
cast fails, its window stays open with the reason. Delete the file to remove it.

`--watch` casts each new video file once its size has been stable for 2 s, so a copy in progress is not opened.
Files already in the folder at the start are ignored. Put the folder inside a shared folder, so the file can be
mapped.

## Tested

On the desktop only, on 2026-10-31, against the stock 4.7.2 Windows build, headless. That build has no SMB, so the
headset side showed the stand-in with its reason. The tests covered:

- the mapping, on five cases against the test PC's shares (a folder share, a whole-drive share and nested shares);
- a cast of a file in a shared folder, first without a saved host (with the warning), then with one, where the saved
  host's own spelling was used;
- `--seek`, a web page, and `--watch` with `--map`;
- `--install-sendto` with APPDATA pointed at a scratch folder. The real Send to folder and desktop were not touched.

Not tested: playing the mapped URL on the headset over SMB, and the launchers in Explorer.
