# Surfaces: one way to point, select and type (2026-11-11)

Agreed with the user on 2026-11-11, point by point. It replaces the per-mode control tables of `docs/USAGE.md`
as each step lands. Branch `surfaces`.

## Why

The same controls meant different things in about five modes, several of them chosen by where the viewer happened
to look: the trigger was play or pause, a menu click, Enter in a terminal, a web click, or nothing. The user:
reusing buttons for different modes is confusing and needs extreme care. Since those rules were made the player
has also gained several screens at once (PC windows, an agent's terminal, the keyboard, the browser), which they
never allowed for.

## The model

**Everything the viewer can point at is a surface**: the film screen, the menu, each PC window, an agent's
terminal. The floating keyboard is a tool for the selected surface, not a surface to type into.

- **Pointing** is a laser or the mouse. Both follow the same rules. The nearest surface a ray meets has it.
- **The trigger clicks** what the laser is on, and nothing else. **The stick scrolls** it.
- **Gaze never changes what a control does.** It may hint, at most.
- **Selection** is where typing and voice go. It is explicit and it stays put. It changes only when the viewer:
  1. clicks a surface's title bar (selects, and sends the surface nothing);
  2. clicks inside a surface (selects, and the click is delivered);
  3. presses the reserved chord on a keyboard, which goes to the next surface (proposed: Super+Tab; a keyboard
     otherwise passes everything to the selected surface).
  Focus that follows the pointer was considered and rejected: with hands on a paired keyboard there is no pointer,
  and a controller that was put down still points somewhere.
- A controller that has been still for a few seconds stops being a pointer until it moves.

## The buttons (right controller; the left is not decided)

| Control | Meaning, always |
|---|---|
| Trigger | Click what the laser is on |
| Stick | Scroll what the laser is on; on the film or on nothing: seek |
| A | Play or pause |
| B, tap | The floating keyboard, open or closed |
| B, hold | Talk: speech becomes text in the selected surface. Recording starts at button down and is thrown away if it was a tap, so the first word is not cut |
| X | The UI, shown or hidden |
| Y | The AI |
| Menu, press | The menu pane, shown or hidden |
| Menu, hold | The menu pane comes back in front of the viewer |
| Grip | Pick up an object, in either state |

Next and previous are not worth buttons (the user: this is for films, not music). They are on the film's bar.
X as Enter, and the stick, A and B turning into arrows, Space and Escape for a terminal, go: the terminal's side
stack has those as buttons, and the keyboard has the keys. The spoken command words ("one" to "four", "yes",
"no", "enter", "escape") go too: voice is dictation only, which is also what lets it work in other languages.

## The UI: shown or hidden (X)

| | Hidden (watching) | Shown (arranging) |
|---|---|---|
| Title bars, side stacks, glow | Hidden | Shown |
| Click and scroll inside a surface | Works | Works |
| Typing and voice | To the selected surface | The same |
| Move, size, close | Not possible: there is no bar to take | By the bar |
| Which surface is selected | A brief glow when it changes | Always shown |
| The floating keyboard | Not affected | Not affected |
| Objects | Can be picked up | Can be picked up |

No automatic switching: the viewer presses X. Hiding the UI hides the menu pane with the rest; Menu while it is
hidden shows the UI with the menu.

## What a surface looks like

- **Title bar.** Its height is a share of the surface's own height (minimums may come later; sizing by angle was
  rejected: it looks wrong). It must be big enough to hit with a laser. It has the surface's name, which is the
  target that selects it, and Close. **Dragging the bar moves the surface**; the stick while dragging makes it
  bigger or smaller (left, right) and further or nearer (up, down). With a mouse: drag, and the wheel.
- **Side stack.** The surface's other controls, as a column beside it. It has a background of its own and is
  joined to the surface: never words floating in the room.
- **Glow.** Outside the surface, never over its picture. Soft and luminous, not a hard coloured border. Faint for
  pointed at, stronger for selected. One halo goes round the surface, its bar and its stack, which also shows they
  are one thing.
- **The menu** is a surface like the others. The only difference: Menu shows and hides it, and holding Menu
  brings it back.

## Voice

Dictation into the selected surface, in the language of the setting (default: the menus' language). English keeps
the English-only model; other languages use the multilingual one. Tried by a person: English, and French when it
is done. The others are offered and said to be untried.

## Build order

1. **One answer to "what is this hand on"** (`app/scripts/pointing/pointing.gd`; "surfaces" already names a room's materials in the code): every surface answers a ray with
   a distance, the nearest has the hand, and a surface that holds a hand (a drag, a held key) keeps it. This
   replaces the hand-ordered checks each part made of the others. It also holds the selection.
2. Title bar, side stack, glow and selection on PC windows, the terminal and the keyboard's target.
3. X shows and hides the UI. A, B as above.
4. The menu as a surface.
5. The film screen as a surface (it has the most existing behaviour: the browser's gaze cursor goes here).
6. Voice as dictation only, with the language setting.

## State

Step 1 is in progress. Until step 4 the menu's own extras (the card, the tablet, placing an object, picking a
seat, marking a window) still take the pointer hand whole, as before.
