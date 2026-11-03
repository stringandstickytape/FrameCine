# VR Video Player: assistant service

You reached a VR video player running on a headset on this network. The person wearing it (the viewer) is watching a
film and cannot see your chat or terminal. Through this API you can see what they watch, hear what they say
(push-to-talk), answer them on a card beside the screen, control playback and change the room around the screen when
they allow it. Everything runs on the headset; you need no other program.

**Now:** <<STATUS>>

**Running on the headset itself?** You are paired already: the file `.assistant-link` in your working folder is a curl
config with your token and the pin. Use `curl -K .assistant-link https://127.0.0.1:47802/state` and skip the pairing
below; never put the token on a command line. Your terminal is on the viewer's controller: answer in the terminal,
not on the card. Network shares go through the player too (`list_dir`, `copy_to_library`, in "The Library"): never mount
one, and never ask for or read a share's password.

Base URL of the API: `<<URL>>`. Every reply is JSON: `{"ok": true, "result": ...}` or `{"ok": false, "error": "..."}`.

### About the headset's certificate (read this before your first HTTPS request)

You may be reading this over plain HTTP on the headset's guide port, which serves only this guide, `/openapi.json`,
`/pin` and two optional client programs. Everything else is HTTPS at `<<URL>>`, with a certificate the headset made
for itself. A device on a home network has no certificate authority to vouch for it, so browsers and curl warn that
the certificate is "self-signed" or "not trusted". **That warning is expected here.** Check the headset directly
instead, by its public-key pin:

    <<PIN>>

The viewer can confirm it: the headset shows the pin's first 8 characters, `<<PINSHORT>>`, in System, Assistant. Ask
them if you want to be sure. Then use curl with both `-k` and `--pinnedpubkey "<<PIN>>"`: `-k` skips the authority
check, and the pin replaces it with a stricter one (curl refuses any other key). Never use `-k` without the pin. A
browser or a fetch tool that can't pin can still read this guide, but use curl (or Python, below) for the API.

The examples use curl and work in PowerShell, cmd, Git Bash and Linux or macOS shells: they avoid JSON on the
command line (bodies are form fields; JSON bodies with `Content-Type: application/json` work too). **On Windows,
write `curl.exe` where they say `curl`** (in PowerShell plain `curl` is another command). Replace TOKEN and the
other capitals with your values.

## 1. Pair (once)

Pairing needs the viewer: they press "Let an assistant find me" in the headset (System, Assistant), which opens
pairing for 60 minutes, and they read you a code.

1. Ask to pair, with a short name the viewer will recognise:

   ```
   curl -s -k --pinnedpubkey "<<PIN>>" <<URL>>/pair/start --data-urlencode "client=Claude Code"
   ```

   The reply has a `pair_id`. The headset now shows a 6-digit code and your name.
2. Ask your user to read you the code shown in the headset. Do not guess: three wrong codes stop the attempt.
3. Send it:

   ```
   curl -s -k --pinnedpubkey "<<PIN>>" <<URL>>/pair -d pair_id=PAIR_ID -d code=123456
   ```

   The reply has `token` (64 hex characters), `pin` (`sha256//...`) and `cert_sha256`. The token does not expire.
   **Keep all three** where you can find them in a later session (for example a file `vrvp-assistant.json` in your
   working folder, not in a public place). The headset keeps only a hash of the token: lost, you pair again.

From now on send the token with every request and check the pin:

```
curl -s --pinnedpubkey "<<PIN>>" -k -H "Authorization: Bearer TOKEN" <<URL>>/status
```

(`-k` is still needed because the certificate is self-signed; `--pinnedpubkey` is what proves it is this headset.)

## 2. Look around

1. `GET /status`: paired assistants, what you may do (`allowed`: each switch, on or off), speech to text
   (`transcriber`).
2. `GET /state`: what plays now.
3. `GET /describe`: every command you may run, with its level and its arguments as a JSON Schema.

## 3. Listening to the viewer

The viewer talks to you by holding a button (push-to-talk); you answer with `POST /answer`, which they read on the
card beside the screen, under their words. To hold a conversation you must keep listening after each answer. Pick
the way your environment allows, and tell your user which one you use:

- **You can run a command in the background and get its output lines as they come** (for example Claude Code's
  Monitor tool, or a background shell task). Follow the event stream; each `data:` line of a `viewer_message` is one
  thing the viewer said:

  ```
  curl -sN -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" "<<URL>>/events?types=viewer_message"
  ```

  In a POSIX shell, add `| grep --line-buffered "^data:"` to keep only the data lines. A comment line (`: keepalive`)
  comes every 15 s. The stream ends if the headset sleeps or the app stops: start it again then (send
  `Last-Event-ID: N` to get what you missed). If your background watch has a time limit, start it again when it
  expires.
- **You can only run commands that finish.** Wait for the next message, answer, then wait again with `since` set to
  the last message's `id`. Leave `since` out the first time, so you get only what is said from now on. Each wait
  returns as soon as the viewer speaks, or with `"timed_out": true` after `timeout` seconds (at most 600):

  ```
  curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" "<<URL>>/messages/wait?timeout=600"
  curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" "<<URL>>/messages/wait?since=7&timeout=600"
  ```

**Acknowledge at once.** The viewer waits in silence while you work, so the headset shows dancing dots under their
words as soon as you are listening. Within a few seconds of a message, before any other work, send a short note
saying what you are doing, with `working=1` so the dots stay after it:

```
curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" <<URL>>/answer --data-urlencode "text=Looking that up" -d working=1
```

Then send the real answer (without `working`): it replaces the note and the dots.

Message and event ids are large numbers that keep growing, also across a restart of the app, so `since` and
`Last-Event-ID` stay right. `GET /status` has `started` (when the app started) and `last_message_id`: if `started`
changed, the app restarted (your pairing still holds; restart your listening).

- **You can only use MCP tools** (a chat app): fetch the adapter and its helper into one folder, keep your token in
  a file only you can read, and add the adapter to your MCP client as a stdio server; its `wait_for_viewer_message`
  and `answer_viewer` tools make the same loop:

  ```
  curl -s -k --pinnedpubkey "<<PIN>>" -o assistant.py <<URL>>/tools/assistant.py
  curl -s -k --pinnedpubkey "<<PIN>>" -o mcp_server.py <<URL>>/tools/mcp_server.py
  python mcp_server.py --config vrvp.json
  ```

  `vrvp.json` is `{"url": "<<URL>>", "token": "TOKEN", "pin": "<<PIN>>"}` (owner-only; `python assistant.py --url
  <<URL>> pair PAIR_ID CODE --save vrvp.json` pairs and writes it for you), or a curl config with the token and the
  pin. Never put the token on a command line, where a process list shows it. `VRVP_ASSISTANT_CONFIG` works instead
  of the argument. `assistant.py` is also a command line for this API: `python assistant.py --help`.

  The adapter's tools are this API's commands, one tool per command in `GET /describe`, under the commands' own
  names (`state`, `card`, `room_apply`, ...; older adapters had `get_state`, `show_card`, `change_room`), plus
  `get_status`, `wait_for_viewer_message`, `get_recent_viewer_messages`, `answer_viewer` and `look_at_room`. A
  command whose switch is off says so in its tool description; the list follows the viewer's switches.

A `viewer_message`:

```
{"id": 7, "text": "who is that man", "heard_at": "2026-10-31T21:04:12", "seconds": 2.1,
 "context": {"file": "film.mkv", "title": "...", "position": 3725.4, "duration": 6120, "playing": true,
             "chapter": {"n": 5, "count": 12, "title": "..."}, "subtitles": [{"start": 3719.0, "text": "..."}]},
 "block": "Viewer said: \"who is that man\"\nWatching: film.mkv\nAt 1:02:05 of 1:42:00 (playing)\n..."}
```

`block` is the same as plain text, ready to read. The headset transcribes speech itself; a message always has its
`text`. A clip that gave no words is not sent to you (the viewer sees "Didn't catch that" and tries again).
`GET /voice/<id>.wav` still returns a message's clip (16 kHz mono WAV, with your token) if you want to check what was
heard; send `heard` with `/answer` to correct the viewer's line on the card.

Python (standard library only) does the same; the pin check is one line:

```python
import hashlib, http.client, json, ssl, urllib.parse

HOST, PORT = "<<HOST>>", <<PORT>>
TOKEN, CERT_SHA256 = "TOKEN", "CERT_SHA256"
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE          # self-signed: the pin below is the check

def call(method, path, body=None, timeout=60):
    c = http.client.HTTPSConnection(HOST, PORT, context=ctx, timeout=timeout)
    c.connect()
    if hashlib.sha256(c.sock.getpeercert(True)).hexdigest() != CERT_SHA256:
        raise SystemExit("this is not the paired headset")
    c.request(method, path, json.dumps(body) if body is not None else None,
              {"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    return json.loads(c.getresponse().read())

since = None
while True:
    q = {"timeout": 600} if since is None else {"timeout": 600, "since": since}
    r = call("GET", "/messages/wait?" + urllib.parse.urlencode(q), timeout=620)
    for m in r.get("result", []):
        since = m["id"]
        print(m["block"])
        call("POST", "/answer", {"text": "..."})   # your answer
```

## Endpoints

| Method and path | Token | What it does |
|---|---|---|
| `GET /` | no | This guide (with the current state when you send your token). |
| `GET /openapi.json` | no | The same API as OpenAPI 3.1. |
| `GET /tools/assistant.py`, `GET /tools/mcp_server.py` | no | A command line and an MCP adapter for this API (Python 3.8+, standard library). |
| `POST /pair/start` | no | `client`: your name. Only while pairing is open; one attempt at a time. Returns `pair_id`. |
| `POST /pair` | no | `pair_id`, `code`. Returns `token`, `pin`, `cert_sha256`, `client_id`. |
| `GET /status` | yes | Paired assistants, permissions, speech to text, pairing. |
| `GET /describe` | yes | The command list with parameter types, and the event names. |
| `GET /state` | yes | What plays: path, title, playing, position, duration, chapter, mode, environment, volume, battery. |
| `GET /places` | yes | The file browser's places. |
| `GET /perf` | yes | The room's measured cost now: GPU and CPU ms per frame (the last 2 s and 60 s), frame rate held, video frames dropped in the last minute, headroom against the frame budget, whether a film plays. |
| `GET /snapshot_clip.png?seconds=2` | yes | A few seconds of the same view, to check motion: one PNG with the frames in a grid, left to right then down (`seconds` at most 4, `fps` 8, at most 12; `width` 320, at most 640; `format=apng` for an animated PNG instead). |
| `GET /snapshot.png?from=viewer` | yes | A PNG of what the viewer sees now (`from=seat`: from the seated eyes, facing the screen). `width` (640, at most 1280), `height` (width x 9 / 16), `fov` (vertical, 60 degrees). |
| `GET /list?path=P` | yes | A folder's entries (folders first, then videos). |
| `POST /command` | yes | `cmd` and its arguments: one command from the table below. |
| `POST /card` | yes | `text`, `title`?, `seconds`?: show text on the card beside the screen. |
| `POST /answer` | yes | `text`; `working` (1: a note while you work, the dots stay), `heard` and `message_id` optional. Goes under the conversation on the card when the viewer spoke in the last 10 min. |
| `GET /messages?since=ID` | yes | What the viewer said (the last 100), each with the film's context. |
| `GET /messages/wait?since=ID&timeout=S` | yes | Waits up to S seconds (at most 600) for the next thing the viewer says. |
| `GET /events?types=a,b` | yes | Server-sent events (below). `Last-Event-ID` resumes. |
| `GET /voice/ID.wav` | yes | The viewer's clip for message ID (the last 20 are kept). |
| `POST /forget` | yes | Forgets you: your token stops working. |

## Commands (`POST /command`)

Form fields: `cmd=NAME` and one field per argument (`-d cmd=seek -d seconds=-30 -d relative=true`). JSON:
`{"cmd": "seek", "args": {"seconds": -30, "relative": true}}`.

Each command has a level. "read" and "card" commands always work; every other level works only while the viewer has
turned its switch on (System, Assistant):

| level | covers | switch |
|---|---|---|
<<LEVELS>>

With a switch off the reply is `{"ok": false, "refused": true, "error": "...", "switch": "Let the assistant ..."}` with
status 409. Do not retry a refused command: tell your user which switch it needs. `GET /status` (`allowed`) and
`GET /describe` (`levels`) say which are on; the `permissions` event says when one changes.

This list is made from the app's own command registry while it runs, as `GET /describe` and the OpenAPI are: what is
here is what the headset can do now. `GET /describe` also gives each command's arguments as a JSON Schema
(`input_schema`).

| cmd | needs | args | what it does |
|---|---|---|---|
<<COMMANDS>>

```
curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" <<URL>>/state
curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" <<URL>>/command -d cmd=seek -d seconds=-30 -d relative=true
curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" <<URL>>/card --data-urlencode "text=Back in five minutes" -d title=Note
```

## Rooms

With the viewer's "Let the assistant change the room" on, you can rebuild the room around the screen, add to it or
recolour it. You send data, never code: a **room document** (JSON, `"schema": 2`; 1 is still read), or the shortcut commands
(`add_shape`, `add_model`, `recolour`, `set_lighting`, `remove`), which make one. Each change shows in the headset at
once and is kept (saved as a room in the viewer's Room tab, under the document's `name`); the reply says
`"state": "kept"`. There is no undo: to go back, send the change that reverses it (the viewer's Reset room returns
the stock room). Start with `POST /command` `cmd=room_state`: it lists the room's own parts (for `recolour`), the
screen, the viewer, the bases, the limits and the supported widgets.

**One coordinate frame.** Every position in `room_state` and in a room document is in the room frame: metres, the
floor at y = 0, the room's own seat at the origin facing -Z (x to the right, y up). A room is designed for seated
eyes at `viewer.seated_eye_height` (1.2 m); `viewer.eye` is where the viewer's eyes are measured to be and
`viewer.head` where the head is now. `screen.center`, `screen.size` and `screen.facing` (the way the picture faces,
towards the viewer) place the screen; `screen.relative_to_eye` gives the same as distance and height from the eyes.

**Look at your change.** After a change, fetch `GET /snapshot.png` (add `?from=seat` for the view from the seat
towards the screen) and look at it before you tell the viewer it is done:

```
curl -s -k --pinnedpubkey "<<PIN>>" -H "Authorization: Bearer TOKEN" -o view.png "<<URL>>/snapshot.png?from=seat"
```

For motion, particles and effects, look at a clip: `GET /snapshot_clip.png?seconds=2` returns one picture with
the frames side by side (8 a second, read left to right, then down).

```
{"schema": 2,
 "name": "Lounge at dusk",                         the name the viewer keeps it under
 "base": "dim_room",                               new_room only: a room id from room_state's bases
 "base_model": "<base64 .glb>",                    new_room only, instead of base: a whole room as glTF
 "light": {"ambient": 0.2, "screen_glow": 0.6},    ambient 0..1, screen_glow 0..2
 "sky": {"color": "#0a1020"},                      or {"image": "<base64 PNG/JPEG>"}, or {} for none;
                                                   with "stars": {...}, "clouds": {...} (below)
 "atmosphere": {"fog": {"density": 0.5}},          low fog near the floor (below)
 "seats": [{"name": "Front row", "position": [0, 0, -1]}],   where a viewer can sit (below)
 "default_seat": "Front row",                      where a viewer opening the room starts
 "screen": {"center": [0, 3, -12], "size": [8, 4.5]},        the room's own screen (below)
 "parts": [{"name": "Clock", "type": "cylinder", "size": [0.4, 0.04],
            "position": [1.6, 1.8, -3], "rotation": [90, 0, 0], "scale": 1,
            "material": {"color": "#202020", "emission": "#ffcc88", "emission_strength": 0.5},
            "widget": "clock", "widget_options": {"style": "analog"}}],
 "recolour": [{"match": "Wall*", "material": {"color": "#3a5a7a"}}],
 "remove": ["Lamp"]}                               room_apply only: parts you added before
```

Send a room document as JSON: write it to a file and post it with
`-H "Content-Type: application/json" --data-binary "@room.json"`, the file holding
`{"cmd": "room_apply", "args": {"room": {...}}}` (`new_room` for a whole new room).

Part types: `box` (size [w, h, d]), `sphere` ([diameter]), `cylinder` ([diameter, height], its round faces up and
down: rotate [90, 0, 0] to face the viewer), `plane` ([w, d], facing up), `model` (`"model": "<base64 .glb>"`),
`text` (words; below).
Metres, in the room frame above. Models: binary glTF with everything embedded; no behaviour extensions;
animations, cameras and lights are removed.

Materials: `color`, `texture` (base64 PNG/JPEG), `self_lit`, `emission`, `emission_strength`. What a surface shows is

    color x texture x light + emission x emission_strength

where light is the room's light or 1 when `self_lit` is true. In a flat room (no `light.key`, `light.sky`,
`light.screen` or `lights`) that is its ambient level and the screen's glow, the same on every side. In a **lit
room** (see Lighting) it is real light, with shading and shadows. **In a flat room a part with a texture is
self_lit by default and its colour defaults to white, so a picture, photo or poster shows exactly as the image**,
whatever the room's light. In a lit room a texture is lit like everything else (stone, wood, a painting on a wall);
give `"self_lit": true` only to things that glow (a sign, neon, a lit window). Do not add emission to make a picture
visible: emission is added on top and washes it out (white turns it white). `"self_lit": false` makes a texture
darken with the room like paint; `"self_lit": true` on a plain colour makes it a flat, even colour. Without a
texture, `color` defaults to grey and follows the room's light; `emission` makes a part glow (a lamp, a sign).

**Lighting.** A room is flat-lit unless you light it: the same brightness on every face, which looks like a
model, not a place. Light it with these (`room_state`'s `lighting` lists the options and their bounds):

- `light.key` {direction, or elevation and azimuth; color; energy 0..1.5; shadows (default true)}: the sun or
  the moon, one directional light. Its shadows fall from solid parts (not from see-through parts, glows, text or
  particles) over the room.
- `light.sky` {top, bottom, energy 0..1}: the fill, a colour from above and one from below, so the shade side is
  not flat. A cool sky over warm ground reads as outdoors.
- `light.screen` {energy 0..2}: the film lights the room: its colour and brightness, from the picture's sides,
  smoothed (it never changes faster than the photosensitivity ceiling).
- `lights`: at most 4 point or spot lights (a torch, a brazier, a lamp), `position` or `attach` (a part's name;
  `offset` from its centre), color, energy 0..6, range 0.5..16 m, `flicker` {rate at most 3 Hz, swing at most
  0.4} for firelight. No shadows. Their cost grows with their range: keep the range to what the light should reach.
- `light.contact_shadows` (default true): a soft darkening under every solid part that stands on the floor, made
  when the room is built, free while it plays.

A recipe for a good-looking lit room (an evening arena):

    "light": {"key": {"elevation": 35, "azimuth": -140, "color": "#9fb4e0", "energy": 0.5},
              "sky": {"top": "#4a5878", "bottom": "#3a3026", "energy": 0.35},
              "screen": {"energy": 0.8}},
    "lights": [{"name": "Torch L", "attach": "Torch flame L", "offset": [0, 0.15, 0], "color": "#ff9a40",
                "energy": 2.2, "range": 6, "flicker": {"rate": 1.4, "swing": 0.3}}, ...]

- The key from behind and to one side (azimuth about ±140), low (elevation 25-45): long shadows, the faces you
  look at lit at an angle. From the front (azimuth near 0) you see the shade side.
- A day: key `#fff2e0` at 0.9-1.1, sky top `#8aa6d0`, bottom `#6a5a48`, 0.35. A night: key `#9fb4e0` at 0.3-0.5,
  the screen light 0.8-1.2 and a couple of warm lights. Indoors: no key or a weak one through a window, sky
  `#504840` / `#2a2420` at 0.3, warm lamps.
- Make the flames themselves `"self_lit": true` with an `emission`, and put the light just above them.
- The display: the picture is not tone mapped (the film's colours must stay exact), so the room is shown as
  lit. Keep the brightest lit surface under white: albedo x (key energy + sky energy + nearby lights) about 1 at
  most. A light colour wall (`#d8d0c0`) under a key of 1.0 is near white already; darker materials (`#8a7a62`
  stone) leave room for the torches. Do not raise energies to brighten a dark room: add fill (sky) instead, or
  the highlights clip to flat white. Keep the darkest corners at least a little lit (sky energy 0.2 or more) or
  the headset's display crushes them to black.
- Look with `GET /snapshot.png` from each seat: the shadows and the film's light show there.

**Transparency.** A PNG's alpha is respected. A picture with any transparent pixels is a **cut-out** by default
(`"alpha": "cutout"`): each pixel is drawn or not, edges smoothed, so a bat silhouette or a cut-out figure on a card
shows only its shape. `"alpha": "blend"` makes it see-through by its alpha instead (glass, haze, a faint ghost); a
colour with alpha below 1 (`"#ffffff40"`, `[1, 1, 1, 0.25]`) is blended by default. `"alpha": "opaque"` ignores
alpha. Blending costs more (see `cost` below); prefer cut-outs for shapes.

**Effects.** A material can name one effect the app draws: `"material": {"color": "#8a6e4b", "effect": {"name":
"rim_glow", "color": "#88ccff", "strength": 1}}`. You never send shader code; `room_state`'s `effects` lists each
with its options and bounds. `rim_glow` (a soft glowing rim where the surface turns away), `hologram` (see-through
light, fine drifting scanlines, brighter edges), `glass` (clear in the middle, reflective at grazing angles, tinted
by `color`), `metal` (polished: reflects a soft made-up surroundings tinted by the room's light, with highlights;
`color` is the metal's, `#d4a84b` brass, `#e8e8ec` chrome), `toon_outline` (cel shading in three tones of `color`
and an outline, `width` in pixels, the same near and far), `dissolve` (eaten away by noise with a glowing edge,
`amount` 0 whole to 1 gone; it holds still at that amount), `pulse` (a glow that swells and fades, `rate` in Hz,
`swing`), `flicker` (candlelight: a glow wandering on several slow waves). Each part's
pulse or flicker starts at its own phase, so a row of candles doesn't beat together. An effect costs 1; glass and
hologram 1 more (see-through), toon_outline 1 more (drawn twice).

Those are the first eight of the effect library: `effects` lists all of them (energy, nature, materials, stylised,
transitions, reactive, skies; `group`, `tag` and `surface` filter), each with a one-line description, whether it is
see-through, whether it keeps the surface under it (`layers`), its cost units and whether it animates;
`effect_info {id}` gives one's options and bounds. A part's effect costs its `cost_units`. One that layers can go over
a library material: `{"library_material": "white_marble", "effect": {"name": "caustics"}}` (one that draws its own
surface can't). wipe and scan_in take their `size`, wind_sway its `base` and `height`, from the part's own extent
when you leave them out. A sky effect (`effects surface=sky`) goes on the sky: `"sky": {"effect": {"name":
"sky_aurora"}}`. `room_state` names each surface's `effect`.

**The photosensitivity ceiling** holds for every effect and widget, and the app enforces it: brightness changes no
faster than 3 times a second (`rate` at most 3) and swings by no more than 0.4 of the surface's own brightness
(`swing` at most 0.4); a document asking for more is refused with the reason. Nothing strobes or flashes. The
screen's glow (`screen_glow`, the bias light) follows the film smoothed, never faster than the ceiling.

**Seats and the screen.** A room can say where people sit and where its screen is. `"seats": [{"name": "Front
row", "position": [0, 0, -2], "facing": [0, 0, -1]}, ...]` (at most 12; `position` is the floor point under the
viewer, `facing` the way they look, level; left out: towards the screen). `"default_seat": "Front row"` is where a
viewer starts when they open the room themselves. `"screen": {"center": [0, 3, -12], "size": [8, 4.5], "facing": [0,
0, 1], "curve": 0.0, "home": true}` is the room's own screen: its centre, its width (the height follows the film's
shape), the way the picture faces (left out: towards the room's middle), curve 0 (flat) to 1 (wrapped evenly round
the seat). It is the screen's home, fixed like a real screen: it stays there facing its own way whichever seat is
in use (seen from a side seat it is seen from the side). The viewer can recentre it to face them for a while, and
Reset room puts it back. `null` for either goes back to the base room's (a base room's screen faces the viewer).
The viewer chooses the seat (the Room tab; the change is a short fade, never a slide). A room change never moves them:
a room you change keeps them where they are, even when you move, rename or remove the seat they are in. Only `seat`
and `recenter` move the viewer or the screen, and only with "Let the assistant control playback" on; use them when
the viewer asks. Then the seat is marked
moved: the reply's `viewer` and `room_state`'s `seats` say `moved: true` (and `was`, the seat's old name, when it
is gone), and the viewer can go to its new place from the Room tab. Likewise a new `screen` is shown at its new home
only if the viewer hasn't moved the screen this session (the reply's `screen` says which); Reset room shows it.
You can suggest a seat with `suggest_seat` {seat, why}: a card asks, they move or stay, and you hear `card_dismissed` with how `go` or `stay`. `room_state`'s `seats` lists them, the one in use and the
screen's home; `GET /snapshot.png?from=seat&seat=Front%20row` shows the view from one.
Refused, with the reason and the size that would work: a screen narrower than 12 degrees or wider than 100 (taller
than 75) from any seat (from the room's own spot when there are no seats), a seat behind the screen, more than 45
degrees off its axis (the picture would look squashed) or closer than 1 m to it, a seat outside the room's walls (0.2 m inside them at least), a default seat that isn't one of the
seats. The eyes are taken 1.2 m above a seat for these. Warnings about parts hidden or behind the viewer are given
per seat ("from seat Back, ...").

**Sky and atmosphere.** The sky (seen where the base room is open: the void, the drive-in, a room without a
ceiling) takes named options beside its colour or picture: `"stars": {"density": 0.6, "twinkle": 0.25, "color":
"#ffffff"}` (density 0..1, twinkle 0..0.4: each star's brightness wanders slowly at its own pace) and `"clouds":
{"cover": 0.4, "speed": 0.5, "color": "#cdd3de"}` (cover 0..1, speed 0..3; a soft layer drifting overhead,
thinning to the horizon). The room's `"atmosphere": {"fog": {"density": 0.5, "height": 0.5, "speed": 0.3,
"color": "#c0c8d2"}}` lays low fog over the floor (height 0.1..1.5 m, density 0..1), wisps drifting slowly, lit by
the room, ending softly short of the walls. Every option has a default; `{"stars": {}}` is a starry sky. Costs:
stars 1, clouds 2, fog 3. Example, a night by the water: `"sky": {"color": "#03060f", "stars": {"density": 0.7},
"clouds": {"cover": 0.3, "color": "#4a5368"}}, "atmosphere": {"fog": {"density": 0.4, "height": 0.4}}`.

**Glows that react to the film.** The `screen_glow` widget (a part that glows in the picture's colour) takes
`"react": "brightness"` or `"loudness"`, `"style": "shimmer"` (light drifting over it like caustics on water) or
`"ripple"` (soft rings spreading from its centre), and `"amount"` (0..0.4, default 0.25): `{"name": "Pool",
"type": "box", "size": [1.2, 0.02, 0.8], "widget": "screen_glow", "widget_options": {"react": "loudness", "style":
"ripple", "amount": 0.3}}`. A loud or bright scene brings the pattern up, a quiet or dark one lets it settle. The app
smooths the film's level so the glow follows scenes, not single beats, and never faster than the ceiling. It costs 1
more than a plain glow.

**How a picture lies on each part type** (u runs left to right across the picture, v top to bottom):

- `box`, `"uv": "atlas"` (the default): **one picture is cut into six pieces, one per face** (the engine's BoxMesh
  layout, 3 columns x 2 rows). Top row, left to right: front (+Z, the face towards the viewer when not rotated),
  right (+X), back (-Z). Bottom row: left (-X), top (+Y), bottom (-Y). The four side faces show their piece upright,
  reading left to right as you look at that face from outside. The top face's piece has its top edge along the
  box's front (+Z) edge and its left edge on the +X side (from the front, looking down, it is upside down); the
  bottom face's piece has its top edge along the front edge and its left edge on the -X side. To show a picture on a
  box, use `"uv": "front_only"` or `"each_face"` instead, or draw the six pieces into one picture.
- `box`, `"uv": "front_only"`: the whole picture on the front (+Z) face only, at its own brightness; the other five
  faces are `color` (default grey), lit like a plain part: a canvas, a framed photo, a poster on a block.
- `box`, `"uv": "each_face"`: the whole picture on every face, oriented as in the atlas.
- `plane` (faces up, +Y): the whole picture; its top edge along the plane's -Z edge, its left edge on the -X side, so
  from above with -Z ahead it is upright. Rotated `[90, 0, 0]` the plane faces the viewer (+Z) with the picture
  upright: the usual way to hang a picture or a poster on a wall in front.
- `sphere`: wrapped around like a globe (equirectangular): the picture's left edge (u = 0) at the front (+Z), u =
  0.25 at +X, 0.5 at the back (-Z), 0.75 at -X; its top at the north pole (+Y). The seam faces the viewer: turn the
  sphere `[0, 180, 0]` to put the picture's middle in front.
- `cylinder`: the side is the picture's top half (v 0..0.5, top edge at the top rim), wrapped from the front (+Z)
  through +X like the sphere. The bottom half holds the caps: the top cap is the circle centred at u 0.25, v 0.75
  (radius 0.25) and the bottom cap the one centred at u 0.75, v 0.75; on the top cap +X is to the right and +Z is
  down the picture.
- `model`: its own UVs, from the file.

**Motion.** A part moves with `"motion"`: one motion or a list of up to 3. The app runs them (all eased, smooth
sines, never a linear back and forth); you name them and their numbers:

- `{"type": "spin", "speed": 30, "axis": [0, 1, 0]}`: turns about its own axis, degrees a second (-180..180).
- `{"type": "bob", "height": 0.05, "period": 4}`: floats up and down, `height` metres top to bottom (at most 1),
  `period` seconds a cycle (0.5..120).
- `{"type": "sway", "angle": 10, "period": 6, "axis": [0, 0, 1]}`: to and fro about its own axis (at most 60 degrees).
- `{"type": "orbit", "center": [0, 2.5, -3], "radius": 1.5, "period": 20, "axis": [0, 1, 0], "face": true}`: goes
  round a point of the room (radius at most 20 m, period 2..600 s); `face` turns it with its path.
- `{"type": "flap", "angle": 40, "period": 0.4, "axis": [0, 0, 1], "hinge": [-0.1, 0, 0], "mirror": false}`: a wing
  beat about a hinge in the part's own frame (at most 80 degrees, period 0.2..20 s). For a pair of wings make two
  parts, the second with `"mirror": true`, and give both the same `"sync": "bat"` so they beat together.
- `{"type": "move_to", "position": [0, 0, -2], "rotation": [0, 0, 0], "duration": 20, "easing": "sine_in_out",
  "at": "end-30"}`: once, from where the part is to there, over `duration` seconds (0.1..600). With `at` it runs on
  the film's clock (seconds, `"end"`, or `"end-30"`: 30 s before the end), so seeking back undoes it; without `at` it
  starts when the room is built. Easings: sine_in_out (default), cubic_in_out, ease_in, ease_out, linear.

Each part gets a small phase and speed difference from its name, so copies never move in lockstep; `sync` puts parts
in step on purpose. Motion costs 0.25 a part.

**Particles.** A `particles` part fills an area with a named effect the app draws (soft sprites that fade in and
out, varied in size and speed, drifting on noise): `{"name": "Snowfall", "type": "particles", "size": [3, 2.5, 2],
"position": [0, 1.25, -2], "particles": {"preset": "snow", "rate": 40, "color": "#ffffff", "size": 0.025,
"speed": 1}}`. `size` (of the part) is the area, a box centred on `position`, at most 30 m a side. Presets:
`snow` (tumbles and drifts down), `rain` (thin fast streaks), `leaves` (flutter and turn as they fall), `embers`
(sparks with a warm halo that rise, cool from yellow to red and shrink), `fireflies` (soft glows that drift and
pulse slowly, each at its own pace), `dust` (faint out-of-focus motes floating; for a projector's beam, make the
area the beam). In the particles object: `rate` a second (at most snow 150, rain 600, leaves 40, embers 120,
fireflies 20, dust 60), `color` (tints the preset's colours), `size` of one particle in metres (0.002..0.3; for
embers and fireflies the whole glow, its bright core about a sixth of it), `speed` (0.25..3 times the preset's).
Falling ones start at the area's top, embers at its bottom, the rest anywhere in it. At most 6 emitters, 600 particles each (rate x life) and 2000 a room; each
costs 1 plus 1 per 100 particles.

**Text.** A `text` part shows words, sharp at any distance, without drawing a picture: `"type": "text", "text":
"Now showing"`, `"size": [0.12]` (the height of one line, metres; default 0.1), and `text_options`: `color`
(default `#f2f2f2`), `background` (a panel behind the text; none when left out; `#rrggbbaa` for see-through),
`weight` (`regular` or `bold`), `align` (`left`, `center`, `right`) and `max_width` (metres; longer lines wrap at
word breaks; 0, the default, never wraps). `\n` starts a new line. The text faces +Z and is centred on `position`:
unrotated in front of the viewer it reads straight on. It is self-lit (no `material`) and can't carry a widget.
`add_text` is the shortcut.

**Objects: the object library and their parts.** The headset keeps a library of things to put in a room:
`object_library` lists them (a few built in, and what the viewer or you imported), `object_info {id}` gives one's
parts (the meshes inside it, by name), size and `mount` (wall, floor, table, ceiling or free). `object_import {name,
data}` adds a `.glb` as it is, or an SVG drawing made solid (`width` and `depth` in metres; each top-level path or
group a part, named by its `id`, else `part_1`, `part_2`, ...; `part_names` renames them in order and joins those
given one name; gradients become one flat colour; strokes, text and pictures are left out, with warnings).
`object_place {id}` puts one in the room: `at` `wall` (the wall the viewer looks at), `floor` (in front of them),
`ceiling`, `front` (at eye height), or `position` and `rotation`; `scale`; `turn` (degrees). It is a `model` part
with `"object": "<id>"`, so `room_state`'s `objects` lists it with its parts. `object_move {name}` moves it
(`at`, `position`, `rotation`, `scale`), `remove {name}` takes it out, `object_delete {id}` deletes an imported
object from the library (placed copies stay).

**Part addressing.** A part inside a placed object is `"<placed name>/<part name>"`, a pattern on each side
(`"Shelf*/Board"`). `recolour {match: "Wall shelf/Board", color: "#c0392b"}` changes that part only and keeps the
rest of the object; `recolour {match: "Wall shelf", ...}` (a bare name) changes the whole object as before, and its
part-level colours go. A part-level change takes the part's colour as it was and puts its fields on top (an
`emission` alone keeps the colour; a `texture` replaces it). `reset: true` puts the part's own colours back.
`material: "<id>"` puts a textured material from the material library on it (wood floors, carpet, velvet, leather,
plaster, brick, marble, metal...; `materials` lists the ids, `tag` filters: floor, wall, fabric, wood, leather,
metal, stone). It shows as itself; with `color` it shows that colour on average, its pattern kept; `tint` multiplies
it, `tiling` sets metres per repeat, `triplanar: true` suits curved models with seams. On a surface that has one,
`color`, `tint`, `tiling` and `emission` change it and `texture` replaces it. In a document it is
`{"library_material": "velvet", "color": "#5a1830", "tiling": 0.25}`; it works on parts, placed objects, their parts
and the base room's surfaces, lit rooms included. `room_state` gives each surface's `material` id. An id the headset
doesn't know is left out, with a warning (`unknown_material`). `effect: "<id>"` puts an effect from the effect library on
it (`effects` lists them, `effect_info` gives the options), with `effect_options` such as `{"color": "#ff40c0"}`; one
that layers keeps the colour or library material under it. In a document these are `recolour` entries; `"material": null` in a
change takes an entry out; one that reaches no part is kept, with a `no_such_part` warning (the `recolour`
command refuses it instead).

Widgets (the app draws them on the part; you only name them):

<<WIDGETS>>

Limits per room: <<LIMITS>>. `cost` is the room's total load on the headset's frame (the film must keep 72 frames a
second): each part and effect adds its weight from `room_state`'s `costs` (a shape 1, a widget 2 more, a
see-through material 1 more, a model 2 plus 1 per 10 000 triangles, ...), and `room_state`'s `used.cost` is the room
on show's total. The cap is a ceiling, not a target: a room that looks good well under it is better. A refusal names the limit and its value; send less and try again.

**Measured cost.** The cap is an estimate; the headset measures the truth. Every change's reply has `perf`,
measured about 2 s after the change is on show (the reply waits for it): `summary` ("after this change: 9.8 ms GPU
of 13.9, 0 drops"), `gpu_ms`, `cpu_ms`, `budget_ms` (one frame: 1000 / the display's rate, 13.9 ms at 72 Hz),
`headroom_ms` (budget minus GPU), `dropped` (video frames dropped since the change), `film_playing` and `notes`.
When the headroom is under 3 ms or frames were dropped, `warnings` says so with the numbers: **simplify the room
then** (fewer or smaller parts, fewer lights or a shorter range, no key shadows, fewer particles or effects) and
look at `perf` again; do not add more. Numbers without a film playing are not representative (the decoder and the
film's texture are missing): `notes` says so; ask the viewer to play one if it matters. `GET /perf` gives the same
now, over the last 2 s and 60 s, with the frame rate held and the drops in the last minute. A document with
problems comes back with `errors: [{path: "$.parts[2].size", error}]`, one per problem. A change that applies
comes back with `warnings: [{part, kind, warning}]`: what may not look as you meant (it is on show anyway). Kinds:
`outside_room` (partly or wholly outside the room's walls, floor or ceiling), `inside_stock_part` (hidden inside one
of the room's own parts), `behind_stock_part` (one of them is between the seat and it), `behind_viewer`,
`behind_screen` (the picture hides it), `too_small` (under half a degree across from the seat), and
`emission_on_picture`. The checks are boxes, so read them as hints and look with `/snapshot.png`.

`room_state` also gives `base.interior` (the room's inside as a box in the room frame, `{min, max, open}`: `open`
lists the sides with nothing there, set to 200 m; or `{known: false}` in the passthrough room), `stock_parts` with
each part's `aabb` (`{min, max}` in the room frame), and for each of `bases` its `interior` once it has been on show.

## Bringing a video from the browser (fetch)

The headset pulls; you never push into it. When the viewer found a video in the headset's Browser source:

1. Read the page: `GET /state`'s `browser` (`{url, title, via}` while a browser is shown, else null) or the
   `browser_page` command (read fresh). `via` says how it was found: `devtools` (the browser the player launched),
   `history` (the browser's history, the visit titled as the window: a browser started otherwise; a `note` says when
   the title didn't match) or `window title` (`url` null: then ask the viewer for the link).
2. Download it on your own machine with your own tools. For YouTube, yt-dlp; pick VP9 8-bit or H.264 up to 2160p
   (the headset decodes these well), not AV1 and not VP9 10-bit / HDR; merge to mkv. For example:
   `yt-dlp -f "bv*[vcodec^=vp09][dynamic_range=SDR][height<=2160]+ba/bv*[vcodec^=avc1][height<=2160]+ba"
   --merge-output-format mkv -o "%(title)s_360.%(ext)s" URL`. For a 360 video add `_360` to the name (or pass
   `mode`: 360, 180_sbs, sbs, 360_tb, ...), and check the projection is equirectangular: YouTube also serves an
   equi-angular cubemap (EAC) layout, which the player does not show as 360 (yt-dlp's format list and ffprobe's
   `spherical` side data say which; convert EAC with ffmpeg's `v360=eac:e` first).
3. Serve the folder over HTTP on the LAN, bound to your LAN address: `python -m http.server 8000 --bind
   192.168.x.y` in that folder. Not on a public address: the headset refuses anything that is not a private address.
4. `fetch {url: "http://192.168.x.y:8000/<file>", name?, open?: true, mode?}` (needs files). The headset downloads
   into `~/Videos/From assistant` (listed in its places), one file at a time, keeping 2 GB of its disk free; the
   card shows the progress and the viewer can cancel. Watch the `download` event: `progress` (at most once a
   second), then `done` (path; it opens when `open`), `failed` (reason) or `cancelled`. `fetch_cancel` stops it.
   `/state`'s `download` shows one in progress.
5. Stop your server when the event says done (or failed / cancelled).

**Running on the headset itself?** Steps 3 to 5 aren't needed: use the format advice of step 2, download straight into
`~/Videos/From assistant` (keep 2 GB of the disk free) and `open` the file by its full path. yt-dlp and get_iplayer are
in `~/.local/bin`, ffmpeg and ffprobe in `/usr/bin`.

Instead of downloading, you can `open` an http URL on the LAN to stream it, if your server answers Range requests
(seeking needs them; `python -m http.server` does not, so use a server that does).

## The Library

<<LIBRARY>>

## Opening a web page

`browse {url}` (needs control) asks the viewer to open a page in the Browser source, public sites too: a card says
"<your name> wants to open www.bbc.co.uk/iplayer" with Open and No, and nothing opens without Open. http and https
only (no javascript:, file:, data: or chrome: URLs, no logins in the URL). The reply comes at once with `pending:
true`; the `browse` event says `opened` (the browser on show went to the page, or the screen switched to the Browser
source at it), `declined` or `timeout`. You get the page's url and title (`browser_page`) and nothing else: never
the browser's cookies, logins, form fields or page content.

## Suggesting a place

`add_place {label, path}` (needs files) suggests a place for the file browser: `smb://host` or
`smb://host/share` on this network, a folder under the home folder, or an http(s) page on this network (it goes
under Browser). A card asks the viewer, "<your name> wants to add TV (smb://192.168.1.20/TV) to your places", with
Add and No; nothing is saved unless they add it. The reply comes at once with `pending: true`; the `place` event
says `added`, `declined` or `timeout`. Never send a login and never ask the viewer for one: a share that needs a login
uses the one saved for the same host, else the viewer is asked in the headset when they first open it. Refused: a
host that isn't on this network, a folder outside the home folder, a folder inside a share, a path that is already a
place (the reason names it). `remove_place {path}` asks the same way for a place the viewer added (not the built-in
ones); the event says `removed`, `declined` or `timeout`.

## Events (`GET /events`)

Each event is `id: N`, `event: NAME`, `data: JSON`, then an empty line. Names:

<<EVENTS>>

## Rules

- There is no code execution and no scene control: only the commands above, each behind its level's switch. Room
  changes are data; each is shown and kept at once, so change the room only as the viewer asked. Settings you change
  stay as if the viewer set them: change one only when asked.
- Keep card text short (a few lines). The viewer is watching a film: speak only when asked or when it matters.
- The headset answers only on its own network (private addresses). The token is yours alone: never put it in a
  shared place. If it leaks, `POST /forget` and pair again; the viewer can also Forget you in the headset.
