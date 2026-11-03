# Director mode

Idea #8 in `docs/ideas.md`. The open file's subtitle text is an index. You can search it and jump to where a line is
said. The code is in `app/scripts/director/`.

## Where the lines come from

1. **The engine's whole-track dump**, from PLAYER_REQUESTS on. This is `MediaSource.get_subtitle_lines(track)`. It
   reads every line of a text track in the container, or of a subtitle file the engine loaded, also on a share or
   over HTTP. Bitmap tracks and live streams have no text. For a track inside the film the engine reads the whole
   file. engine-demux measured these times on the host:

   | File | Time |
   |---|---|
   | 800 MB, local | 7.7 s |
   | 2.1 GB, local | 23 s |
   | 2.1 GB, share | 12.6 s |

   Lines of a loaded subtitle file come back at once. Closing the file stops a read. The result is then empty, and
   the error says "Stopped: the file was closed."
2. **Subtitle files next to the video**, parsed in GDScript (`subtitle_text.gd`): `.srt`, `.vtt`, `.ass` and `.ssa`
   named after the video (`film.srt`, `film.en.srt`). They can be in its folder or in a `Subs`, `subs` or
   `Subtitles` folder next to it. This works on local files only, and with any engine.

The track is the subtitle track shown now, else the first text track, else the first file. Each result lists all the
tracks; give `track` to pick another. The index is built on a worker thread, once per file and track. The last 4
are kept. Callers that ask while an index is read share that one read. An engine read that gives no lines and an
error, for example a stopped read or a share error, is not kept, so the next call tries again. A track that simply
has no lines is kept.

## Search

- **Words:** every word of the query must be in the line, in any order and any case. Punctuation and apostrophes
  are ignored, so "its" finds "It's". A word also matches inside a longer word: "run" finds "running".
- **Phrases:** a "quoted phrase" must appear as written. A phrase can run across the two lines of one subtitle.
- **Accents** are kept as written: "café" does not find "cafe".

Each hit has the line's index, start and end times, its text, and the lines before and after it for context.

## Commands

| Command | Arguments | Level | Result |
|---|---|---|---|
| `find_line` | `query`, `limit` = 20, `track` | read | `{path, source: engine or file, track, tracks, lines, hits: [{i, start, end, text, before, after}]}` |
| `jump_to_line` | `query` and `n` = 1 (the n-th hit), or `i` (a line index); `lead` = 0.5; `track` | control | seeks to `lead` seconds before the line and plays; undo goes back |
| `script_lines` | `offset` = -1 (around the line said now), `count` = 40, `track` | read | `{total, current, offset, lines: [...]}`, the whole script a page at a time |

```
python tools/listener.py send find_line query="open the door"
python tools/listener.py send jump_to_line query=door n=2
```

From the phone remote, `find_line` and `jump_to_line` work as they are (read and control levels).

## For the pane (app-shell)

A Files-tab-style list: a search field, then the hits or the whole script, with the line being said highlighted.

```
const Director := preload("res://scripts/director/director.gd")
var idx: Dictionary = await Director.index(main)        # {path, source, track, tracks, count, error}
var hits := Director.search(idx, field.text, 50)         # [{i, start, end, text, before, after}]
var page := Director.lines(idx, offset, 40)              # the whole script
var now := Director.line_at(idx, main.player.get_position())
Director.jump(main, hit)                                 # 0.5 s before the line, playing
```

`idx.count == 0` means there is no text; `idx.error` says why. Call `Director.clear_cache()` when the subtitle tracks
change (a file was added).

While an index is read, `Director.building(main)` gives `{seconds, source}`, else `{}`. `source` is `engine` when the
whole film is read. Show it, for example "Reading the film for its subtitles: 12 s", because that read can take 20 s.

## Tested

On the desktop only, with the stock 4.7.2 Windows build, on 2026-10-31.

- **`tests/test_director.gd`**: SubRip with CRLF and hours, WebVTT with cue settings and voice tags, ASS with a
  Format line, commas in the text, a Comment line and override tags. Also search by words, phrases, punctuation and
  apostrophes, the limit, the context lines, `line_at` and paging. With a fake engine source it also checks that two
  callers share one read, the `building()` state, that a stopped read is not kept, and that a track with no lines is
  kept. All pass.
- **Over the link**, with a file and `Subs/film.en.srt` of 40 lines (the stock build plays the test pattern for the
  file): `find_line` found the lines, a quoted phrase found 10, `jump_to_line n=2` went to 49.5 s and played,
  `script_lines` gave the page around the line said, and an unknown word gave "0 matches".

Not tested: the real engine dump, which needs the arm64 player build, so embedded text tracks and subtitle files on a
share are untested too. Nothing was tested on the device.
