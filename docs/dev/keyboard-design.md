# The keyboard: design (2026-11-10)

A full PC keyboard in the headset, in a window of its own, that types into whatever has the focus: a field in the
menu, a PC window (docs/pc-windows.md), an agent's terminal (docs/assistant.md, "Agents on the headset") and the
browser on the big screen. Keys are pressed with the lasers and triggers, or by poking them with the controllers'
tips; words can be swiped. The user chose each of these (2026-11-10). Steam's own keyboard (`steam://open/keyboard`)
was tried and rejected: it drops you into SteamVR's screen view.

## Layout

- **Full 104 keys, ANSI US**: Esc, F1-F12, Print Screen, Scroll Lock, Pause; the number row, Backspace; Tab, the
  letters, the brackets and backslash; Caps Lock, Enter; both Shifts; both Ctrls, both Windows/Super keys, both Alts,
  Menu, Space; Insert, Home, Page Up, Delete, End, Page Down; the four arrows; the number pad (Num Lock, / * - +,
  0-9, the dot, its Enter). Usual key widths (1u keys; Tab 1.5u, Caps 1.75u, left Shift 2.25u, Space 6.25u...), the
  usual gaps between blocks.
- **Legends** as on a real keyboard: both characters on the number row and the symbol keys (the shifted one above);
  the letters in capitals; words on the wide keys. They follow Shift and Caps Lock (the letters' case). Big, plain,
  high-contrast, in the menu's theme (ui/pane_style.gd, the KeyButton look in ui/themes/default.tres), readable at
  the size the keyboard is used at. The menu's language does not change the legends.
- Each key is **its physical key**: Godot's `Key` code (`KEY_A`, `KEY_F5`, `KEY_KP_7`, `KEY_LEFT`...) plus its
  location where Godot tells them apart (left/right Shift, Ctrl, Alt, Meta; the pad's Enter). That is what the
  targets take (below), so shortcuts work (Ctrl+C, Alt+Tab in a PC window, Ctrl+R in a shell).
- **Lights**: Caps Lock, Num Lock and Scroll Lock show whether they are on; a modifier that is latched or locked
  shows that too.

## The window

- Its own floating window, like a PC window's pane (scripts/pc/pc_pane.gd, pc_windows.gd): world-locked, made the
  first time in front of the viewer and a little below eye level, tilted up toward the head.
- **Move**: squeeze and hold on it (on its frame or on a key), and it follows the laser at the distance it was taken,
  as a PC pane does. **Resize**: the stick while holding: left / right smaller or bigger (the keys keep their
  shape), up / down further or nearer. Limits: about 0.35 m to 1.6 m wide.
- A thin **bar** above the keys: the target's name ("Typing into: Claude Code", "Typing into: the search field",
  "Nothing to type into"), and Close. The bar is part of what can be grabbed.
- **Open and close**: a Keyboard button in the menu (where the PC windows row and the agents' rows are: System or
  the menu's own bar; choose the place that fits ui/), and a dev command `keyboard` {show: bool} for tests and the
  assistant. Opening a text field in the menu does not need it (the on-pane keyboard, ui/onscreen_keyboard.gd,
  stays for now), but when this keyboard is open and a field has the focus, it types there.
- Where it was and how big it was are kept in the settings (`[keyboard] transform`, `width`), and it opens there
  again. Recentring (the menu's recentre) brings it back in front of the viewer.
- The picture of the keyboard is ordinary (not the private layer): it shows no content. What is typed is never
  logged or sent to an assistant (keys count as content when they go to a PC window or a terminal).

## Pressing keys

Both ways at once; each hand on its own, so two hands can type together.

- **Laser and trigger**: a hand's laser over the keyboard lights the key under it (a hover look). Trigger down is
  the key down, trigger up is the key up; a key held repeats as a real keyboard does (about 500 ms, then 30 a
  second) for the targets that need the app to repeat (a menu field), and is held down for the targets that repeat
  it themselves (an X window, a PC window: they get the down, then the up). A short haptic tick on each press. While
  a laser is over the keyboard, its trigger and stick are the keyboard's (as with a PC pane: owns_laser()).
- **Poking**: each controller's tip (its front end, from the runtime's render model or the aim pose; see
  ui/watch_card.gd for how the controller's shape is read) presses a key it pushes through the keyboard's face. Down
  when the tip passes a few millimetres into the key moving inward, up when it comes back out past the face (some
  hysteresis, so a tip resting on the face doesn't chatter); a stronger haptic tick. A key pressed by poking can't
  be pressed by the other hand's poke at the same moment. Poking works only within reach; the laser works at any
  distance. The keyboard's face is solid for poking but no physics body (no collisions with the room).
- **Modifiers** (Shift, Ctrl, Alt, Super): a tap latches it for the next key (one-shot); a second tap locks it until
  tapped again; holding it while pressing another key works as on a real keyboard. Caps Lock and Num Lock toggle.
  What the target receives is the real modifier down and up around the key, so a target sees exactly what a USB
  keyboard would send.

## Swipe typing

- Hold the trigger on a letter and draw across the letters (the laser's point leaves a fading trail on the keys);
  let go on the word's last letter. A tap types one letter as usual; a swipe is a press that crosses two or more
  other letter keys.
- The path is matched against a word list: the shape decoder of SHARK2 (Kristensson and Zhai) or a simpler
  equivalent: resample the path and each candidate word's ideal path (the key centres in order) to the same number
  of points; score by location distance and shape distance; keep only words whose first and last letters are near
  the path's ends; weight by the word's frequency. Precompute the words' ideal paths once (on a thread at start, or
  lazily) so that a swipe is decoded in well under 100 ms on the headset (arm64, GDScript; measure it).
- The best word is typed with a space after it (no space before it at the start of a field or after an opening
  bracket); the next best three show on a strip above the keys, and touching one replaces the word just typed.
  Backspace straight after a swiped word deletes the whole word.
- With Shift latched the word gets a capital; with Caps Lock it is all capitals.
- **The word list** must have a licence that lets it ship in an MIT app free of charge with only a credit: public
  domain, CC0, Unlicense, MIT or BSD style. About 30 000-60 000 English words with frequencies. Put it under
  app/keyboard/ (or a folder that fits), and its source, version and licence in LICENSES/THIRD-PARTY.md (and the
  package's LICENSES folder if tools/package.sh needs telling). No word list that forbids redistribution or needs
  share-alike.

## Where the keys go: the targets

One small router decides, every time a key goes down, where it goes, in this order:

1. A text field in the menu that has the focus (a LineEdit or TextEdit in the panel): Godot input events for it
   (an InputEventKey with keycode, physical keycode, unicode and modifiers, echo for repeats), so the field behaves
   as with a real keyboard.
2. The floating window that has the focus: a PC window pane (scripts/pc/pc_windows.gd: focused, and its key path,
   _key()/send_text(); keys go as Godot's names for the physical keys, down and up) or an agent's terminal
   (scripts/agents/local_agents.gd: the X11 window's send_godot_key / send_unicode, as its keyboard path does).
3. The browser on the big screen, if one is open (scripts/video/browser_*.gd and how a paired keyboard reaches it
   today).
4. Nothing: the bar says "Nothing to type into", and keys light but send nothing.

Find how a keyboard paired with the headset reaches each of these today (ui_layer on_key(), pc_windows _key(),
local_agents' keyboard path, the browser's), and send the virtual keys down the same paths, so there is one way in
for each target. The router is its own small script with a clear interface (target_name(), key(event_down/up)),
so that a later floating terminal window (the agent's terminal moving off the controller into a window like a PC
window's) only has to register as a target.

## Tests and docs

- A headless test, app/tests/test_keyboard.gd, run like the others (`--script res://tests/test_keyboard.gd`):
  all 104 keys there with the right Godot codes and locations; a laser press is a down then an up at a fake target;
  repeat; one-shot, lock and held modifiers wrap the key in the real modifier events; Caps Lock and Num Lock; the
  router's order; the field target gets the right InputEventKey; move and resize keep the limits and are saved; a
  synthetic swipe over "hello", "the", "keyboard", "frame" decodes to that word first; the decode time is printed.
- The UI test (`-- --ui-test`) still passes, and the other tests that touch the menu.
- docs/keyboard.md for the user (what it is, opening it, pressing, poking, swiping, moving, resizing, what it types
  into), and a line in docs/USAGE.md and the menu's help where the other features are listed.
- Menu strings through tr(), added to app/locale/messages.pot and app/locale/zh_CN.po (tools/i18n.py extract and
  merge, then the Chinese filled in; tools/i18n.py check clean; any new Chinese characters must be in the font
  subset, app/ui/fonts/NotoSansSC-Medium-subset.woff2, see tools/i18n.py font).
