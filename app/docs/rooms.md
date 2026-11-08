# Your own rooms (glTF and photos)

The player has built-in environments, and it can also use rooms you make. Put the files on the device, pick the room
in the environment list, and the screen goes where the room says.

## A glTF room

Put a `.glb` (or `.gltf` with its files) in the app's `rooms` folder:
`~/.local/share/godot/app_userdata/Frame VR Video/rooms/` on the device. Its name in the list is the file name.

The convention is the same as the built-in rooms:

- **Units:** metres. Y is up, and the floor is at y = 0.
- **The viewer** sits at the origin and looks along -Z. Eye height is about 1.2 m when seated. The app keeps the
  screen's height relative to the viewer's real eyes.
- **The screen** goes at a node named `ScreenAnchor`, such as an empty in Blender. Its position is the screen's
  centre, and the screen faces +Z (toward the viewer). Only the position is used: the screen always stands upright
  and faces the viewer. Scale the empty along X to the screen's width in metres (for example, X scale 4 for a 4 m
  screen); otherwise the width is 3 m. Without a ScreenAnchor, the screen goes 3 m ahead at eye height.
- **Materials:** the app has no lights. It draws every surface unlit: the base colour and its texture, lit by the
  room's ambient level and a soft glow from the screen. Emission is added as it is, so lamps and signs glow.
  Transparent materials show unshaded. Normal maps, roughness, metallic and lights in the file are not used.
- **Keep it light:** the headset draws the room twice per frame at up to 120 Hz on a battery. A few thousand
  triangles and a few textures of at most 2048 pixels are plenty. Use one material per kind of surface.

Optional settings go in a JSON file with the same name (`my_room.glb` and `my_room.json`):

```json
{
  "name": "My room",
  "ambient_level": 0.15,
  "screen_glow": 0.6,
  "screen_width": 3.5,
  "reflection_floor_y": 0.0
}
```

- `ambient_level` (0 to 1): how bright the surfaces are with a dark screen. A dark room is about 0.05, a dim one 0.15.
- `screen_glow` (0 to 2): how much the screen lights the surfaces near it. With the bias light on (off by default),
  that light takes the picture's colour and brightness.
- `screen_width`: the default screen width in metres, used in place of the anchor's scale.
- `reflection_floor_y`: the floor's height, if it should show the screen's reflection (floor reflection setting).

A room that can't be read shows the void instead, and the log says why.

## A photo as the room

Put a 360 photo (equirectangular JPEG, PNG or WebP, 2:1) in the app's `skyboxes` folder:
`~/.local/share/godot/app_userdata/Frame VR Video/skyboxes/`. It shows in the list as "<name> (photo)". The photo
surrounds the viewer with its horizon at eye level. The middle of the photo is straight ahead. Phone photo spheres
work, including partial ones. For a 3D panorama, the left eye is used. A narrower picture is centred ahead, with
black around it. The room light setting sets the photo's brightness.

From the app, `EnvLibrary.add_skybox(path)` copies a picture into that folder and returns its environment id
(`main.set_environment(id)` shows it).

## An object for the object library

An object (a shelf, a lamp, a sign) is a `.glb` too, imported into the object library (`docs/assistant.md`,
"Objects"): the Room tab places it on a wall or the floor, and each of its parts can take a colour or a picture of its
own. The same units as a room, and:

- **Front:** +Z. A wall object hangs with its back (its lowest z) on the wall; a floor object stands on its lowest y;
  a ceiling object hangs from its highest y. Where its origin is does not matter.
- **Parts:** each mesh node is a part, named by the node's name (else its mesh's, else `part_1`, `part_2`, ...).
  Name the meshes you want to recolour on their own (`Board`, `Brackets`), and join the ones that never need a
  colour of their own: each part is a draw call, and a model has at most 128.
- An SVG drawing can be imported as it is: the app makes it solid, each top-level path or group a part.
