The Library is the headset's own shelf, `~/Videos/Library`, shown in Files as posters, seasons and episodes. It is a
folder and not a database: what is in the folder is what shows, read when the viewer opens it. Keep exactly to these
paths and names, relative to that folder. They are the ones Kodi and Jellyfin expect, and anything else shows as a plain
folder.

```
TV Shows/<Show> (<Year>)/tvshow.nfo
TV Shows/<Show> (<Year>)/poster.jpg
TV Shows/<Show> (<Year>)/fanart.jpg
TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>.<ext>
TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>.nfo
TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>-thumb.jpg
Movies/<Title> (<Year>)/<Title> (<Year>).<ext>
Movies/<Title> (<Year>)/<Title> (<Year>).nfo
Movies/<Title> (<Year>)/poster.jpg
Movies/<Title> (<Year>)/fanart.jpg
```

- `<Year>` is the year the show first aired or the film came out. Check it (web search, the broadcaster's own page), it is
  not a guess; if sources disagree, ask the viewer. Two shows of one name differ only by this year.
- Numbers are two digits: `Season 02`, `S02E05`. Specials are `Season 00`. Two episodes in one file: `S01E01-E02`, with
  two `<episodedetails>` one after the other in its NFO.
- Names hold no `/ \ : * ? " < > |`, and don't start with a dot: drop the character or write ` - `.
- Pictures: poster 2:3 (about 1000 x 1500), fanart 16:9 (about 1920 x 1080), an episode's thumbnail 16:9 (640 wide), JPEG.
- Every field of an NFO is optional, but a show needs `tvshow.nfo` and a film its `.nfo` to appear as one. NFOs are UTF-8
  XML: write `&amp;` for `&`. The fields read are these (the player never fetches a URL from a file):

```xml
<tvshow><title>Show</title><plot>A few sentences.</plot><premiered>2011-03-04</premiered><genre>Drama</genre>
  <namedseason number="2">A season's own name</namedseason></tvshow>
<episodedetails><title>Title</title><showtitle>Show</showtitle><season>1</season><episode>1</episode>
  <plot>One or two sentences.</plot><aired>2011-03-04</aired><runtime>44</runtime></episodedetails>
<movie><title>Title</title><plot>A few sentences.</plot><tagline>A line.</tagline><premiered>2019-06-21</premiered>
  <runtime>104</runtime><genre>Drama</genre></movie>
```

`runtime` is in minutes. Write plots in your own words, short: the viewer reads them on a small panel.

**Filling it.** Which way depends on where the file is:

- **From a network share, always through the player.** It holds the login and you never need it. Never mount a share,
  never use `gio`, `smbclient` or `mount`, never ask the viewer for a share's password and never read `~/.smb-password`.
  "Refused a guest login", or any other login error, means you went round the player: stop, and use these commands.
  - Find it: `list_dir` with `path=network://` gives the saved hosts and shares; `list_dir` with an entry's `path` goes
    in. Each entry has its exact `path`: pass that on. Add `all=true` to see every file, not just videos (an NFO,
    subtitles or pictures beside a video).
  - Copy it: `copy_to_library` with `from` (that `path`) and `to` (a path above, relative to the Library). It needs
    "Let the assistant manage files". One at a time, on a worker: the `library_copy` event says `progress`, then
    `done`, `failed` or `cancelled`, `library_copy` in `/state` shows it, and `copy_cancel` stops it. A file already
    there is refused.
  - A share that isn't saved: suggest it with `add_place`. The viewer adds it, and the headset asks them for its login.
- **From your own machine:** serve the file on the LAN as in the fetch recipe, and `fetch` with `to` (a path above) and
  `open=false`. NFOs and pictures come the same way.
- **On the headset itself:** write into the folder directly (make the folders first). yt-dlp, get_iplayer, ffmpeg and
  ffprobe are there.

**Where the details come from:**

- yt-dlp: `--write-info-json` gives the title, description, channel, date and duration as JSON beside the video, and
  `--write-thumbnail --convert-thumbnails jpg` a picture. Use the formats of the fetch recipe, then move and rename into
  the layout and write the `.nfo` from the JSON.
- get_iplayer: its search covers only recent broadcasts. For anything older, find the show's brand or series pid on
  iPlayer (it is in the page's address), list the episodes with `get_iplayer --pid=<brand> --pid-recursive-list`, and
  record each by its own pid. `--metadata` writes an XML file of its own beside the recording, `<name>.xml`, with what
  it knows (names, series and episode numbers, descriptions, first broadcast), and `--thumb` the thumbnail.
  `--metadata-only` and `--thumbnail-only` do just that, for a recording you already have. Rename into the layout and
  write the `.nfo` from that XML; it isn't an NFO.
- A frame as the thumbnail: `ffmpeg -ss 300 -i "<video>" -frames:v 1 -vf scale=640:-2 -q:v 3 "<name>-thumb.jpg"`. Pick a
  time past the titles, and look for a frame that isn't black.
- Plots, years and posters: web search. For a file with nothing beside it, work out what it is from its name and path
  and `ffprobe`, and say so if you aren't sure rather than filling in a likely answer.

When a file is in place, `open` it by its full path if the viewer wants it now. An episode's overlay title, and `title`
and `library` in `/state`, come from its NFO, and next and previous follow the season.
