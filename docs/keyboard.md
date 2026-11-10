# The floating keyboard

Open **System → Keyboard** in the menu. It is a full 104-key ANSI US keyboard in its own window, below and in
front of you, tilted towards your head. Its legends stay in US English whatever language the menu uses. The small
keyboard inside a menu form is still available too. Close on the keyboard's top bar hides the floating one.

The bar says where typing will go: a focused text field in the menu first, then a focused PC window, then a showing
terminal, then the browser on the big screen. With no target it says **Nothing to type into**. Looking down at the
keyboard leaves the window's focus alone. Keys never become player shortcuts. The board is on the ordinary
render layer, with a solid panel behind the keys; the lights of pressed and pointed-at keys use the private layer,
since they reveal text. Typed text and window pictures are never put in a keyboard command result or a log.

Point either laser at a key and press the trigger, or push either controller's front tip through a key and withdraw
it. Both hands work together. A laser press gives a short haptic tick; a poke gives a stronger one. Hold a key for
repeat: menu fields start after half a second and repeat thirty times a second; windows handle their own repeat.
Moving the laser off the board still releases its key when you let go. Closing or losing tracking releases keys too.

Tap Shift, Ctrl, Alt or Super to use it on the next key. Tap it twice to lock it, and once more to unlock it. You can
also hold a modifier with one hand while pressing keys with the other. The lights show selected modifiers and the
keyboard's Caps Lock, Num Lock and Scroll Lock; two dots mean a locked modifier. Shift reverses Caps Lock for a letter. The target's existing lock
state is not read back: if a window already has Caps or Num Lock set differently, toggle it there to match.

A key goes down as soon as the trigger or the tip does, and comes up when you let go or withdraw.

Squeeze and hold the grip with the laser anywhere on the keys, frame or bar to move the window. It follows the laser
at the distance where you took it; turning the hand turns the board. While holding it, push the stick left or right
to make it smaller or bigger, and up or down to move it further or nearer. Its width stays between 0.35 and 1.6 m,
with the keys' proportions kept. Releasing the grip saves the position, angle and width. Opening it again restores
them. The menu's recentre brings an open keyboard back in front of you.

For local development, `keyboard {"show": true}` opens it and `keyboard {"show": false}` closes it. These commands
return only whether it is shown and its width. They cannot type, read the target name or read what was typed.

The implementation is in `app/keyboard/`: `key_layout.gd` defines the keys; `key_state.gd` balances
physical events and modifiers; `keyboard_router.gd` chooses and captures a target; `floating_keyboard.gd` handles
the hands and placement; `keyboard_surface.gd` draws it. Menu fields receive Godot key events, with Unicode and
echo for repeat. PC windows use their normal physical-key protocol, including location as an optional field.
The updated PC companion maps both modifier locations; older companions treat both as the left key.
The terminal and browser use their normal X11 key path. That engine API distinguishes pad Enter but has no
argument for left and right modifier locations, so those remain equivalent in X11 targets.

The first build also had swipe typing over a word list. On the headset the laser was not steady enough for it to
find the right words, so it was removed (2026-11-10), and its word list with it. Tip placement, haptics and
legibility still need a worn test.
