# Push-to-talk and voice commands

Ideas #14 and #41 in `docs/ideas.md`. Hold a button on the headset, speak, and let go. The clip goes to the PC over
the dev link. The PC turns the sentence into commands for the headset: "dim the lights and skip to chapter 9".

The headset only talks. It records while the button is held, and it sends the clip on the link it opened to the
listener. Nothing listens on the headset, and nothing goes over the internet unless your own transcriber does that.

## On the headset

`app/scripts/dev/push_to_talk.gd` is made when the dev link is on (`--listener`).

- **Hold F8** on a keyboard. On the controllers, a binding calls `begin()` and `end()` (app-shell: see below).
- **`push_to_talk seconds=3`** records for that long, for tests and a desktop without a button.
- A clip is 0.3 s to 10 min (the upper bound only guards against a stuck button). It is mixed to mono and resampled to 16 kHz, 16-bit WAV, then sent as a `voice_clip` event
  with `seconds`, `rate` and `peak`. A peak near 0 means the microphone gave nothing.
- The microphone records on its own bus, `PushToTalk`. That bus is muted, so you do not hear yourself. The
  microphone opens only while recording. `project.godot` has `[audio] driver/enable_input=true`, which Godot needs
  for any microphone input.
- `voice_state {recording}` goes out when recording starts and stops, for an indicator on the PC.

For the pane or the core (app-shell):

```
var ptt := preload("res://scripts/dev/push_to_talk.gd").instance()   # null without the dev link
ptt.begin()    # on press;  ptt.end() on release
ptt.recording_changed.connect(func(on: bool) -> void: ...)          # an indicator while it records
```

## On the PC

`tools/listener.py serve` saves each clip to `voice/` in its log folder and logs its path instead of the data. Then
it tries a transcriber. These are tried in order; the first that works is used:

1. **A command:** `serve --transcriber "CMD {wav}"`, or the environment variable `VOICE_TRANSCRIBE_CMD`. `{wav}` is
   the clip's path (it is added at the end if the command does not have it). The command's standard output is the
   text. Any local speech-to-text program that prints the text will do.
2. **A Python package**, if one is installed: `faster_whisper` or `whisper` (`VOICE_MODEL` picks the model, default
   `base.en`), or `vosk` (`VOSK_MODEL` is the model folder). `tools/voice.py` never downloads anything itself. A
   package may download its model on first use.
3. **None:** the listener prints the clip's path. Listen to it, then type the sentence:

```
python tools/listener.py say dim the lights and skip to chapter 9
```

You can also type `say <sentence>` in the `serve` terminal. `say --dry-run <sentence>` shows the actions without a
listener or a headset, and so does `python tools/voice.py "<sentence>"`.

## The grammar

`tools/voice.py` is standard library only. It works like this:

- **It splits** a sentence into clauses at "and", "then", "also", commas and semicolons. A "where he says ..."
  clause keeps the rest of the sentence whole, so "find where he says rock and roll" stays one clause.
- **It cleans** the text: number words become digits ("twenty five" is 25), and "%" becomes "percent". Filler words
  ("please", "can you") are dropped.
- **It matches** each clause to one command. It reads the app state once (`get`) when a change is relative ("louder",
  "move the screen up"), and later clauses build on earlier ones ("louder and louder").
- **It runs** the commands in order and reports each one. Clauses it does not understand are listed and skipped.

| Said | Command |
|---|---|
| play, resume / pause, stop, hold on | `play` / `pause` |
| next, skip this video / previous | `next` / `previous` |
| skip to chapter 9, the third chapter, next chapter, previous chapter | `chapter n=9`, `n=3`, `step=1`, `step=-1` |
| skip forward 30 seconds, rewind a minute, back (10 s) | `seek` relative |
| go to 1:20:05, go to 1 hour 20 minutes, go back to the start | `seek` |
| volume to 40 percent, louder, quieter, mute, unmute | `set volume` (steps of 0.15; unmute is 0.7) |
| dim the lights (half), lights off, lights on, lights to 30 percent | `set room_light` |
| move the screen up / down (0.2 m), closer / further (0.5 m), by 50 cm | `set screen_height` / `screen_distance` |
| make it bigger / smaller (x1.25), recenter the screen | `set screen_width`, `recenter` |
| go to the cinema / the room / the void, load recipe lobby | `set environment`, `load_recipe` |
| subtitles on / off, show / hide the menu, show / hide the info, take a screenshot | `subtitles`, `menu`, `set overlay`, `screenshot` |
| find where he says ..., the bit where she says ... | `jump_to_line query=...` (director mode, `../director.md`) |

Commands from voice go through the permission ring like any command from the PC. Every command above is at the
control level, so voice needs no allowed window.

## Tested

On the desktop only, with the stock 4.7.2 Windows build, on 2026-10-31.

- **`python tools/test_voice.py`** passes 10 tests: the three example sentences, several actions in one sentence,
  number words, times, relative changes, rooms, a quoted line with "and" in it, unknown clauses, state read once
  and carried forward, failures reported, and the transcriber command.
- **A typed sentence over the link:** "set the volume to 40 percent and move the screen up then skip to chapter 2"
  gave a volume of 0.4, a screen height of 0.2 and a position of 120 s (a test pattern, with 5 chapters).
- **A recorded clip:** `push_to_talk seconds=1.5` recorded the PC's microphone (peak 0.053). It sent a 1.5 s WAV,
  16 kHz mono 16-bit. A stand-in transcriber command printed "dim the lights and skip to chapter 3", and the light
  went from 1.0 to 0.5 and the position to 243 s.
- "make me a sandwich" was reported as not understood.

Not tested on the device: the Frame's microphone and its permission, a controller binding, a real transcriber.
