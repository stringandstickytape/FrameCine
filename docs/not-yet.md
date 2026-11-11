# Not yet: features wanted, not built

What the user has asked for and what is known to be owed, in one place. Scored ideas that nobody has asked for
yet are in [ideas.md](ideas.md). An entry leaves this list when it is built and a person has tried it.

## Asked for

| What | Detail | State |
|---|---|---|
| **Keyboard layouts for other languages** | The floating keyboard in each language's own layout, not only ANSI US. The default is UK, or the layout that goes with Steam's language if the player can read that. A setting changes it. | Not started. To find out: how to read Steam's language on the headset. To decide: a PC window gets physical keys and applies the PC's own layout, so the legends there are right only when the two layouts match; menu fields, the terminal and the browser get the characters themselves. |
| **Voice in other languages** | Dictation in the language of a setting (default: the menus' language), with the multilingual speech model where it is not English. | Not started. Planned with the surfaces work. A person can try English and French; the others would be offered as untried. |
| **Surfaces: one way to point, select and type** | Every screen is a surface with a title bar, a side stack and a glow; the selection is explicit; A plays, B is the keyboard and voice, X shows and hides the UI, Y is the AI; the menu is one more pane. | In progress on branch `surfaces`: `docs/dev/surfaces-design.md` there. |
| **The left controller** | What its buttons do under the surfaces model. | Put aside by the user for now. |

## Owed from work already done

| What | Detail |
|---|---|
| The terminal at its full size | On the Frame the agents' terminal is 74 x 21 cells again (it was 112 x 32 for an hour, and stuttered). With the engine now copying only what changed, 112 x 32 may be fine: to try, then to choose. |
| A PC window with no terminal open | The compositor crashes of 2026-11-10 had an agent's terminal showing every time. A PC window alone has not been watched for long since. |
| The engine change in the public fork | "x11window: the copy path reads and uploads only the damaged box" is on the build machine only. |
| A release with all of the above | 0.1.9 is the newest release. The keyboard changes, the bias light default, the terminals' own display and the new engine are on the test headset only. |
| Speech to text on the graphics chip | `--whisper-backend=vulkan` exists and has not been proven on the headset. It decides whether a bigger speech model is usable. |
| The agent window's place | It is kept for one run only; its width is kept for good. |
| Updates: "Later" | Nobody has yet answered Later to an update on the headset and seen that it waits. |
| The Journeys rooms on the headset | Motion comfort and the sounds of the Narrowboat and the Showboat have not been judged in the headset. |
| Three checks of `test_pane` | `ui/intro.gd` sets font sizes itself, `ui/seat_plan.gd` draws a colour itself, and the Room tab's echo help text is too long for one line. |

## Longer term

- An installer for Desktop mode (a `.desktop` entry without Steam).
- 120 Hz.
- A version resource in the PC app's exe.
- Builds whose paths do not name the build machine (`-ffile-prefix-map`).
- The Codex install path, tried on the headset.
