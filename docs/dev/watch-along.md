# Watch-along answers, the PC half (#54)

The viewer asks something about the film ("who is that?", "what did he just say?"). An AI session in a terminal on
the PC reads the question with the film's context and answers on a card beside the screen. There is no model call in
our code: the AI session in the terminal is the model. The headset shows the card (app-shell's `card` command,
`app/ui/watch_card.gd`); this page is the PC side.

Nothing listens on the headset. The headset connects out to `tools/listener.py serve` (`--listener=<PC address>`), as
for every dev command.

## Use

```
python tools/listener.py ask who is the man in the hat
python tools/listener.py answer "He is the brother, back from the first scene."
```

`ask` prints one block, and `serve` prints the same block in its own terminal:

```
=== watch-along question (2026-10-31 07:01:31) ===
Question: what did he just say about the car
File: clip.mkv
Position: 0:08 of 2:00 (playing)
Chapter: 7/12 "The Chase" (from 1:00:00)
Mode: flat_mono; environment void
Last 2 subtitle lines (line 2 of 17):
  [0:01] Cue 0 at 1 s
  [0:06] Cue 1 at 6 s
Answer on the headset: python tools/listener.py answer "<text>"  (or type: answer <text>)
=== end ===
```

`answer` shows the text on the card. The card's heading is the last question, if it was asked in the last 30
minutes, else "Answer". Options: `--title T`, `--seconds S` (0: until the viewer dismisses it; default: the
headset's, 20 s). In the `serve` terminal, type `ask <question>` and `answer <text>` directly.

`ask --lines N` sets how many subtitle lines to include (default 8; 0 for none).

## Where the context comes from

| Part | Command on the headset | When it is missing |
|---|---|---|
| File, title, position, duration, playing, mode, environment | `get` (the app state) | no headset: the block says "no state" |
| Chapter | `chapters` (new, read level) | no chapters: the line is left out |
| Last subtitle lines said | `script_lines offset=-1` (director mode, `docs/director.md`) | no subtitle text: a note with the reason |

The lines are the ones whose start is at or before the position, so nothing not yet said is shown. The file name
drops any query part of a URL, so a token in a URL never reaches the log.

## Log

Each `ask` is logged as `{"type": "ask", "question", "context"}` and each `answer` as `{"type": "answer", "text",
"title", "ok"}`, in the listener's `events-<date>.jsonl`, next to the `card` command itself. `events -f` shows them
as they happen.

## Code and tests

- `tools/watch_along.py`: `gather()`, `format_block()`, `card_args()`, `question_title()`. No network code; it uses
  the listener's command function.
- `tools/listener.py`: `Listener.ask()` and `Listener.answer()`, the control operations `ask` and `answer`, the
  `ask` and `answer` subcommands, and the typed commands in `serve`.
- `app/scripts/dev/player_commands.gd`: the `chapters` command.
- `tools/test_watch_along.py`: a fake headset; the full context, missing parts, no headset, before the first line,
  the card arguments.

Tested on the desktop in WSL (the fork, a clip with a sidecar `.srt`): `ask` gives the block with the lines said so
far, `answer --seconds 2` shows the card and the card goes away by timeout, both are logged. Real files have no
chapters until the engine reports them (`MediaSource.get_chapters()`); the test patterns have five.

Not tested on the device.

## Ideas for later

- A question from the headset itself: push-to-talk (`voice.md`) with "question ..." could call `ask`, so the viewer
  never types.
- A screenshot in the context (the `screenshot` command, `screenshots.md`) for "who is that?" questions.
