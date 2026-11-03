# Development tools

Tools for working on the app while it runs in the headset. All of them are off unless switched on, and none of them
listens on the headset: the headset connects out to a listener on the PC.

| Page | Idea | What |
|---|---|---|
| `hot-reload.md` | #3 | `--dev`: changed shaders, environments, resources and scripts reload in place. `tools/push-app.sh` copies the app to the device. |
| `control-protocol.md` | #5, #56 | `--listener=HOST`: the link to `tools/listener.py` on the PC. Events out, commands in, newline-delimited JSON. `describe` lists every command. |
| `screenshots.md` | #16 | the `screenshot` command: each eye and a third-person camera, sent to the PC |
| `scene-control.md` | #10 | list the scene, spawn nodes, set properties, load glTF, run snippets |
| `permission-ring.md` | #23 | what the PC may change, the toast and undo |
| `stats.md` | #57 | frame times, decoder queue, bitrate, GPU, power, thermals |
| `voice.md` | #14, #41 | push-to-talk clips to the listener, the voice grammar |
| `watch-along.md` | #54 | `ask` a question with the film's context, `answer` it on a card beside the screen |

The code is in `app/scripts/dev/`. `dev_host.gd` is the entry point that `main.gd` calls. It loads `dev_tools.gd` and
the rest only when dev mode is on.

A typical session:

```
# PC, terminal 1
python tools/listener.py serve
# PC, terminal 2
tools/push-app.sh --watch
# headset (ssh frame)
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 ./godot_player --path app --display-driver x11 --xr-mode on \
    -- --dev --listener=<PC address> --dev-allow=120
# PC, terminal 3, or an AI session
python tools/listener.py describe
python tools/listener.py send screenshot
```

## Before you push: the privacy check

`tools/privacy-check.sh` looks for personal data in the tracked files (no argument), in a revision (`--tree REV`) or in
the lines and commit messages of a range (`A..B`): scene release names of films, user names in paths, home network
addresses outside the example ranges and e-mail addresses. It also reads your own patterns, one regex per line, from
`~/.config/vrvp/private-patterns` (or `$VRVP_PRIVATE_PATTERNS`): put the titles of your library, your share and host
names there, never in the repository. It prints each hit masked, as file and line, and exits 1. Test media in the
repository and its docs use made-up names; tests that need real films read them from a local folder of links with
those names (`$VRVP_LIBRARY`, default `~/media-tests/library`). To run the check on every push, copy
`tools/pre-push.sample` to the clone's hooks folder (see its header).
