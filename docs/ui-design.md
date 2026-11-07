# UI design: the pane

## Revision 3 (2026-11-06): the tablet

Status: current. The menu is on the tablet (`ui/tablet.gd`): a landscape panel below and in front of the eyes,
tilted up towards them, placed from the head's heading when the menu button opens it and then fixed in the room.
Its top pane has a small header line (the chapter; the clock, time left and end, battery, low controllers,
Listening), the title, the time (LIVE, the trick play speed) and the time bar with chapter ticks and the seek bar's
picture, and under them a band: the transport as icons on the left (previous, -10 s, play / pause, stop, +10 s, next, 4x
and 8x held) and the picture's switches on the right (Steady detail, Smooth banding); the menu's panel reaches up
over the gap into the band, so they are its own buttons. The main pane has the tabs as a rail down the left (in a scroll of its own, for larger text) with each tab's places or sections beside it, the section
picked filling the rest, and the footer. It all fits the main pane's 961 x 463 layout pixels at the default text
size (tests/test_tablet.gd); a keyboard form takes the whole pane, the rail and transport hidden meanwhile. The front
panel below (Revision 2) is gone (the user, 2026-11-06): its size, distance and head follow (`[pane] scale`,
`distance`, `world_locked`, System's Size, Distance and Follow my head) and the switch between the two (`[pane]
tablet`, System's Tablet menu) went with it. Revision 2 stays below for its reasons.

## Revision 2 (2026-10-31): a front panel

Status: replaced by Revision 3. It replaces the hand-held pane below (decision D11 in `decisions.md`). The headset run on
2026-10-31 showed that the pane on the left controller, with its glance state and the hand-position rules, is not
usable. One controller must be enough.

**The object.** The same pane (the same 740 × 600 px contents, halo, tokens and fades), now a standard panel in
front of the headset. By default it is 38 × 31 cm at 0.6 m from the eyes (about 35° wide). The headset run gave these
values: at 0.9 m the docked pane was not readable, and at 0.6 m with `[pane] scale` 1.4 it was "better, maybe a little
bigger". Thus the defaults are 0.6 m and scale 1.6 (1.0 is the theme's 24 cm).

**Opening and closing.** The menu button on either controller opens the panel. The panel appears about 0.6 m in front
of the head, at eye height, and faces the head. Its position comes from the direction of the head at that moment.
A short press of the menu button closes the panel.

**Always level.** The top edge of the panel is always horizontal (world up). The panel does not roll with the head,
also when you look up or down. Only when the head looks nearly straight up or down (more than about 64°, for example
when you lie back and look at the ceiling) the panel uses the up direction of the head, so it appears above you, the
correct way up for your face.

**Recentre.** Hold the menu button for 0.6 s while the panel is open. The panel moves to the front of the head again.

**World-locked.** After the panel opens, it stays at its position in the world. It does not follow the head and it
does not move. For persons who prefer a panel that follows the head, set `[pane] world_locked = false` (System,
Panel, "Follow my head"). Then the panel stays still until the head turns about 25° away from it, and it then moves
smoothly back to the front of the head.

**The pointer.** The controller whose menu button opened the panel is the pointer. If you then push the menu button
on the other controller, the panel closes. When you open the panel again with that controller, it becomes the
pointer. The laser of the pointer shows only while it points at the panel. The trigger clicks. The stick scrolls the
list below the laser. If a slider is below the laser, the stick moves the slider (up or right increases the value).
When the laser is not on the panel, the stick of the pointer moves a focus highlight and the trigger activates the
focused control, so you do not have to aim. The other controller keeps its usual functions (trigger: play / pause,
stick: seek and distance, grip: move the screen). The position of the other controller has no effect. If the pointer
controller has no tracking and the other controller has tracking, the other controller becomes the pointer.

**At launch** the panel is open in front of you, and the right controller is the pointer (the left controller if
Left-handed is set). `--no-ui` starts with the panel closed.

**The header** has the clock, the time left with the end time, and the headset battery, where the glance state had
them. When a controller battery is low, or push-to-talk is recording, the header shows that too. The info overlay
(`--overlay`, the left stick click) gives the quick look while the panel is closed.

**Readability.** With the defaults (38 cm at 0.6 m), the 740 px panel gives about 21 px per degree, which is about
the same as the display (about 20 px per degree): one panel pixel for each display pixel. Thus 15 px body text is
about 0.7°, 11 px labels are about 0.5°, and 40 px rows are about 1.9°. This is less than the targets in "Numbers"
below (body text about 1°, targets not less than about 2.5°), but it is the size that read well in the headset, and
it is two times the angle of the docked pane at 0.9 m. The pixel size stays the same. For larger text, increase
`scale` (the text gets larger and slightly softer) or decrease `distance`.

**Settings** (`[pane]` in `user://settings.cfg`, and System, Panel):

| Key | Default | Meaning |
|---|---|---|
| `distance` | 0.6 | metres from the eyes when the panel opens or recentres (0.4 to 3.0) |
| `scale` | 1.6 | size multiplier: 1.0 is the theme's 24 cm wide, 1.6 is 38 cm (times Accessibility, Larger panel) |
| `recentre_hold` | 0.6 | seconds to hold the menu button for a recentre |
| `world_locked` | true | false: the panel follows the head with a lazy catch-up |

**Help lines.** The user found many controls unclear. Under each control whose name does not say what it does, the
panel shows one short line in plain words, in the muted label style of the theme (no new colour or font). Examples:
"Gate weave": "Adds the small sideways wobble of film in an old projector."; "Dialogue boost": "Makes voices louder.
Only for 5.1 sound and more." Under a slider the line is the text only. Under a row of buttons the line starts with
the button's name. A line shows and hides with its control. The lines do not wrap, so each text must fit one line of
the panel (about 80 characters with the name; `tests/test_pane.gd` checks). The texts are in `app/ui/help_texts.gd`,
one dictionary for each tab, keyed by the visible name of the control. The Picture and Sound tabs have their texts
now. The Files, Subtitles, Room and System tabs get theirs when the user names what is unclear. Later, if the lines
take too much space: a smaller "HelpLabel" theme variation (made by `tools/make_pane_theme.gd`), or a System
setting to hide them.

**Curvature** (Picture tab) is 0 to 100 %, not a radius. 100 % is a radius equal to the screen distance (the screen
wraps evenly around the viewer); the radius is never smaller than the distance, and it follows the distance so the
percentage stays (`docs/features.md`, #31).

**Removed** (the text below the line is the history of these): the attachment to the left controller, the hidden /
glance / open states, the reading pose with its 45° / 55° cones and hysteresis, the freeze while pointed at, the
slide from the dock to the hand, the "Docked" tag and the difference between docked and not docked (the panel is
always what "docked" was), and the `[pane] dock_distance` and `glance_opacity` settings. The controller labels did
not depend on the hand-held pane. On the headset's controller profile, the left view button is now a menu button,
and the info overlay moves to the left stick click.

**Tests.** `tests/test_pane.gd` checks the front pose (level, looking down, lying back), the head follow and the
menu button's press, hold and release. `--ui-test` opens and closes the panel with either controller's menu button,
recentres it with a hold, turns the head (world-locked), lies back, and checks the head follow and the slider nudge.

---

## History: the hand-held pane (superseded by Revision 2)

Everything from here to the end describes the first design, which was built, tried in the headset and replaced. The
tabs, the contents of the pane, the style, the tokens and the theming still apply. The object, its states, the
reading pose, the freeze and the dock do not.

Status: approved 2026-10-31, until it is coded and we change our minds. Mockups (private canvas, four frames):
https://claude.ai/artifact/FYDVQ4ardGLY2ZDvJezChP

The app launches straight into the selected environment. There is no main menu. The whole interface is one object,
the pane, carried by the left controller and operated by the right. Everything below is that object.

## Principles

1. **Intuitive first, stylish second.** The thing you hold is the menu, the other hand is the pointer. Nothing to learn.
2. **Nothing moves under the pointer.** Targets are still while you aim at them (see Freeze).
3. **It is a normal application inside.** Tabs, lists, sliders, buttons. No spatial gimmicks for choosing files.
4. **Quiet hardware, slightly sci-fi.** A lit pane, not a tablet, not a hologram. Matte, opaque, one accent.
5. **Themed from one token set.** No colour or font is ever written inline in menu code.
6. **The screen is for the film.** The pane never covers it unless you hold the pane up in front of it yourself.
7. **No trademarks** anywhere in the interface.

## The object

A borderless near-black pane, about 24 cm wide and 20 cm tall, with a faint lit edge and a soft halo. No bezel, no
thickness, no frame. It floats about 15 cm above the left controller's grip pose, tilted toward the face, and is never
closer than 0.5 m to the eyes, because focusing nearer than that for a minute hurts on this headset.

It has three states.

| State | When | Shows |
|---|---|---|
| Hidden | left controller down or out of view | nothing; the controller model only |
| Glance | raised into a reading pose, not pointed at | time, time left and end time, battery, film name, a thin progress line; nothing clickable; pane at reduced opacity |
| Open | raised and the right laser is on it, or docked | the full interface |

**Reading pose:** the controller is above about chest height, inside the view, and its face points within about 40° of
the head. Enter and leave thresholds differ (hysteresis) so it does not flicker at the boundary. Fade in and out over
150 ms. The pane follows the grip pose with light smoothing so it feels held, not welded.

**Freeze while pointed at:** the moment the right laser enters the pane, the pane stops following the left hand and
holds its world pose. It stays frozen until the laser has been off it for about 0.5 s, or the left hand moves more than
a few centimetres, then eases back to the hand over 150 ms. The same rule applies while a stick is scrolling it. Only the
glance state follows the hand freely. This is the rule that makes the pane usable: a hand-held panel with moving targets
is unusable.

**Dock:** the menu button pins the pane in world space, about 0.9 m ahead and slightly below eye level, facing the head,
with a small "Docked" tag in its corner. Docked, the right stick moves a focus highlight and the trigger activates it,
so you never need to aim. This is the lying-down mode. Press menu again to hide it. At launch the pane starts docked in
front of you; raising the left controller into the reading pose takes it into the hand (a short slide from the dock to
the hand, never toward the face).

## The pointer

The right controller's laser appears only while it is aimed at the pane, white with a dot at the hit point. Hover gives a
highlight and one haptic tick. Trigger clicks. Either stick scrolls the list under the laser. Poking the pane with the
controller's tip also clicks, because people will try it. Left-handed swap is a setting.

While the pane is hidden the controllers keep their direct bindings as today: trigger play/pause, stick seek, grip
moves the screen, A/B next/previous.

## Inside the pane

Top to bottom:

1. **Header:** "Now playing" label, the film's title, and the time as `0:42:17 / 2:06:33` in tabular numerals.
2. **Seek bar:** a 2 px track, the played part in the accent, chapter ticks, a 12 px knob. Later: thumbnails above it.
3. **Transport:** previous, −10 s, play/pause (ringed, 52 px), +10 s, next. 44 px targets.
4. **Tabs:** Files, Picture, Sound, Subtitles, Room, System. Uppercase, letter-spaced, accent underline on the active tab.
5. **Body:** the tab's content.
6. **Footer:** one line of context, for example the mode guess and its reason, and the item count.

| Tab | Holds |
|---|---|
| Files | the existing browser: places column (device, SD card, saved shares, test patterns), breadcrumb, list rows with name, duration, resume marker and a mode chip; add-host form and on-pane keyboard slide up over the list |
| Picture | mode as small layout diagrams (mono, SBS, TB, 180, 360, fisheye, dual 360) with Auto and its reason, half and swap, 3D depth, screen size, distance, height, curvature, picture controls |
| Sound | audio track, volume, A/V offset, night mode, output (headset or PC sync when it exists) |
| Subtitles | track, on/off, size, depth, delay, external files |
| Room | environment, room light, seat, screen placement reset, recentre |
| System | stats overlay, test patterns and calibration cards, network hosts, hot-reload, about |

List rows are 40 px tall on a 740 px wide pane, which is just under 3° at 0.55 m. Names clip with an ellipsis. The
resume marker on the last-played file is a small accent time, for example `0:42 ▸`. There is no artwork, no library
and no metadata scraping. The filename is the poster.

## Numbers

| | |
|---|---|
| Pane size | 24 × 20 cm, 740 × 600 px in the SubViewport (about 3080 px/m) |
| Distance from eyes | 0.5 m minimum when held, 0.9 m docked |
| Body text | 15 px, about 1° at 0.55 m (9.6 mm) |
| Labels | 11 px uppercase, 0.14 em tracking |
| Title | 22 px semibold; glance clock 96 px light |
| Targets | rows 40 px, buttons 44 px, play 52 px; nothing under about 2.5° |
| Fades | 150 ms, in place, from the object's own anchor |
| Freeze release | laser off the pane 0.5 s, or left hand moved a few cm |
| Reading pose | above chest height, in view, face within about 40° of the head, with hysteresis |

All of these are to be tuned in the headset, not on a monitor.

## Style

One set of tokens, nothing else:

| Token | Default | Used for |
|---|---|---|
| surface | #0C0F13 at 94 % | the pane |
| edge | accent at 28 % | the 1 px pane edge and the halo |
| text | #E6EAEE | body text, titles, numerals |
| muted | #8B95A1 | labels, metadata, inactive tabs |
| accent | #9CCBE8 (pale ice) | focus bar, seek progress and knob, mode chips, active tab, laser tint |
| font | one neutral sans, 400/500/600, tabular numerals | everything |

Hairline rules at 9 % white separate regions. Corner radius 8 px on the pane, 6 px on rows. Focus is a 2 px accent bar
at the row's left edge plus a 10 % accent fill; docked focus adds a 1 px accent outline. Hover on buttons is a 14 %
accent fill with a 1 px accent inset ring. Sounds, if any: a tick, a confirm, an error, all soft.

Not allowed: blur or glass, glow on text, scanlines, 3D buttons, curved panels, head-locked anything, continuous follow
while pointed at, hint text telling you how to use it, icons where a word does, sci-fi sounds, flying panels.

### Theming

Every colour, size and font above comes from one Theme resource plus a small dictionary for the custom parts (laser,
pane edge, chips). Menu code never sets a colour or font inline. A theme later is a new resource and nothing else.
Multiple themes are a much-later feature; the discipline starts with the first restyle.

## What this replaces

The current panel (1.5 m ahead, 0.3 m below eye level, summoned by the menu button, follows after 65° for 1 s) becomes
the docked state. Its tabs Files / Mode / Screen / Audio become Files / Picture / Sound / Subtitles / Room / System. The
info overlay stays a separate debug layer under System. The on-pane keyboard stays, for hosts and passwords, and gets a
phone-remote code when that exists.

## Later, on this object

Chapter thumbnails above the seek bar; the battery-versus-film-end line in the glance state; PC audio sync state in the
glance state and the Sound tab; subtitle rendering on its own quad below the picture, not on the pane; the AI listener
and phone remote as views of the same app state as the pane. See `ideas.md`.

## Corrections from implementation

Found while building the pane (2026-10-31). The approved text above is unchanged; these say how the code differs and
why.

1. **Alpha is mapped for linear blending.** The renderer blends in linear light, so the surface at 94 % let a bright
   film show through at about a quarter of its brightness, and the glance state's reduced opacity looked almost
   clear. The pane quad uses 1 - (1 - a)^2.2 for its alpha (fades and glance included), which gives about what the
   same alpha gives composited in sRGB, as the mockups were.
2. **The view cone of the reading pose is 45° to enter and 55° to leave**, not 40°. A controller held at the chest
   while looking straight ahead is about 41° below the line of sight, so 40° missed the natural reading pose. The face
   test stays at about 40° (40° to enter, 55° to leave); the chest height is 40 cm below the eyes to enter and 50 cm to
   leave.
3. **Size versus angles is open.** At 740 px on 24 cm (3080 px/m), 15 px body text is about 0.5° at 0.55 m, not
   1°, and 40 px rows are about 1.4°. The code uses the size as written; `[pane] scale` (System, Pane, Size) scales it
   for the headset test.
4. **No card between the tabs and the body.** The hardware 10-bit setup's card, which asked once for the headset's
   password and sat above the tab body, was removed with the setup (`docs/decisions.md` D21). Hardware 10-bit video is
   a read-only row in the System tab (`docs/features.md`, "Hardware 10-bit video").
