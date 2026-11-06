# Object physics

Any object from the object library can be picked up, held, dropped or thrown. It bounces off the seats, the steps,
the walls, the floor and the film's screen, comes to rest, and stays where it lands. The showcase: a cabbage thrown
at the screen from the back row.

Code: `app/scripts/play/object_physics.gd` (the bodies, rest, saving, the cost), `object_grab.gd` (the controllers),
`physics_shapes.gd` (the shapes), `thud.gd` (the sound). Test: `app/tests/test_physics.gd`.

## Design

- **Jolt** is the 3D physics engine (`app/project.godot`, `physics/3d/physics_engine`). It is compiled into the
  device build. Everything goes through `PhysicsServer3D`: no physics nodes.
- **Placed objects stay static.** Each solid placement of a kept room is a static body of its own shapes, made when
  the room comes on. Solid: a model, a box, a sphere, a cylinder, a plane. Not solid: a text, a particles area, a
  screen glow, a part with `motion`.
- **Physics acts only on a picked-up object.** Its body turns rigid, with continuous collision (CCD). When it is
  slower than 6 cm/s and 0.25 rad/s for 0.4 s (or after 15 s), it is static again where it lies.
- **The place is kept.** The room document gets the new `position` and `rotation`. `home` keeps where the object was
  placed (the first time it moves). The kept room is saved 1.5 s later. A showroom becomes a kept room of its own,
  as any change to it does.
- **Put back** returns one object to its home. **Tidy up** returns every object. Each is one room change with Undo.
  What still moves comes to rest first.
- **Wall objects** (manifest mount `wall`: the clock, the picture frame, the shelf) stay on the wall while held.
  When the hand pulls them 8 cm off, they come off and are normal objects. The document then has `mounted: false`.
  Put back puts them on the wall again.
- **Text and particles** have no body. With `attach` (another placement's name) and `offset` (metres in that
  object's frame) they follow that object, as the lights do. Their `rotation` is then relative to the object.
  Unattached, they stay where they are placed.
- **Lost objects** (12 m below the floor, or 120 m away) go back to where they were picked up.
- **No multiplayer.** Nothing is synced.

### The room's shapes

Cheap, simple shapes, built 0.5 s after a room with objects comes on (about 50 ms for the cinema on the desktop).

| Room | Shapes |
|---|---|
| Cinema (`environments/cinema.gd collision_shapes()`) | A slab under the floor, the walls and the ceiling (1 m thick, outside), the stage, each row's tier as 8 solid blocks along its arc, the side aisles' two steps a row, the rear walkway, and two boxes a seat (the cushion with its standards; the tilted back). 734 boxes; the seats share two shapes. |
| Passthrough (`passthrough.gd`) | The floor (a 40 m slab under y = 0), and each Mixed reality area as a box. |
| Any other room, a glTF room, a showroom's base | From its static meshes (`physics_shapes.gd mesh_shapes()`): a BoxMesh, SphereMesh or CylinderMesh as its exact shape, a MultiMesh's instances as boxes, any other mesh as its triangles (both sides). Meshes over 120 m (skies, shells) are left out. |
| The screen | Flat: a 12 cm box behind the picture. Curved: 12 boxes along the arc. 180, 360, fisheye: a low sphere (24 x 12) of triangles round the head, as much of it as the picture covers. Built again when it changes. |
| Placed objects | A built-in primitive as its exact shape (a plane as a 1 cm box). A model as one convex hull per part (at most 48 points; a flat part made 1 cm thick). |

A model's hulls are worked out once (`ObjectLibrary.collision()`) and kept beside it in the library
(`user://objects/<id>/collision.json`, with the md5 of the model). An object imported before physics gets its hulls
the first time it loads. A built-in's hulls are made each session.

### Judder: interpolation, our own

The headset shows 72 Hz (or more; fewer when a frame drops), and physics ticks 60 times a second. A moving object is
drawn between its last two ticks, at the engine's interpolation fraction, in `object_physics.gd _process()`. The
engine's own physics interpolation stays off: it is global, and it would delay every node the app moves in
`_process` (the controllers, the lasers, the tablet, the screen) by a tick unless each one was switched off. A 72 Hz
tick rate was the other choice; it would not follow other refresh rates or dropped frames, and costs a fifth more.

### Sound

One generic thud for every impact, made in code (`thud.gd`): a low sine that falls a little in pitch, with a dull
click of filtered noise on its front, 0.24 s. The impact speed is the velocity's change in one tick, beyond
gravity's. Under 0.5 m/s it is silent; the loudness rises as the square root of the speed up to 12 m/s, times the
square root of the object's size. The pitch is 150 Hz for a 0.3 m object, as the square root of its size (bigger is
lower), a little higher for faster impacts. Each waveform is made once a semitone.

It plays where it happened, through the spatial audio's own renderer: a BinauralRenderer with the output profile's
HRTF set, tuning and EQ, the room's walls and reverb, the listener at the head. Up to four at once. Without the
engine's renderer (or while its set loads, on a worker thread), an AudioStreamPlayer3D at the place.

### Lighting: light probes stay off

Objects only exist in kept rooms (`AssistantRoom`). Kept rooms are never baked today: `room_lightmaps.gd` bakes a
room only when the room node itself has `static_meshes()` and `bake_lights()`, which the cinema has and the kept room
built on it does not. So turning on probes in `room_bake.gd` would light nothing that moves. The placed objects
use the rooms' unlit or `room_lit` shaders, which do not read probes either. Probes also add to the bake time (about
3 s for the cinema on the Frame). Left off; see "Open questions".

## Controls

Either controller; one is enough.

| Input | What it does |
|---|---|
| Point at an object | The laser shows to it. It fades after 2 s of a still controller, so a hand at rest with an object ahead doesn't light a laser through the film. |
| Grip (hold), laser on an object | Picks it up at the laser's end. |
| Grip (hold), controller in an object (or within 8 cm) | Picks it up in the hand. |
| Stick up or down, holding on the laser | Further or nearer (0.3 to 10 m). |
| Stick left or right, holding | Turns it about up (as Place). |
| Let go of the grip | Drops it. Let go while the controller moves, and it is thrown at the speed of the held point (the laser's tip, or the hand) over the last 75 ms, at most 25 m/s, with a third of the controller's spin. |
| B (or Y), holding | Back where it was picked up. |
| Trigger, holding | Nothing: no play or pause, no zoom lens. |

The grip keeps what it did before when it is not on an object: a quick squeeze is a right click on a captured window,
a held one is the zoom lens's modifier in 180 and 360. The grab does not take the laser while Place, seat picking or
marking a window has it, nor where the menu's laser is on the panel, nor on the hand a captured window has.

The printed legends follow: the squeeze says GRAB while the room has objects (menu hidden). A controller holding an
object says LET GO: THROW on the squeeze, NEAR-FAR / TURN on the stick and CANCEL on B; its trigger has no legend.

The Objects tab, **In this room**: **Put back** (an object moved by hand), **Tidy up** (all of them), and for a text
or particles area **Attach** (pick the object it follows) and **Detach**.

## Commands

| Command | Level | What |
|---|---|---|
| `object_put_back` {name} | room | One object back where it was placed |
| `object_tidy_up` | room | Every moved object back |
| `object_attach` {name, to, offset, rotation} | room | A text or particles area follows `to`; empty `to` detaches it where it is. Offset and rotation default to where it is now. |
| `object_throw` {name, velocity, spin} | room | Drops (velocity [0, 0, 0]) or throws an object, room frame, m/s |
| `object_physics` | read | What can be picked up, moving, held, on its wall, moved, attached; the room's shapes; the cost |

The room document's new placement keys (`room_schema.gd`, validated): `home` {position, rotation, mounted?},
`mounted` (bool), `attach` (a placement's name; text and particles only), `offset` [x, y, z] (with attach).

## The numbers

Desktop: WSL, the fork's x86_64 template_debug build, 30 CPUs. `test_physics.gd` measures the step's wall time (from
the last `_physics_process` of a tick to the first `_process` after it: `object_physics.gd state()` reports it as
`cost_ms`; the dev link's `object_physics` shows it on the headset). `Performance.TIME_PHYSICS_PROCESS` is no measure
here: it counts the main loop's wait too (it said 25 ms a tick for a room nobody touched).

| Case | ms a tick |
|---|---|
| The cinema's 734 shapes and 24 placed objects, all at rest | 0.035 |
| 24 objects thrown about at once: the step | 1.4 to 1.5 (most 2.0) |
| 24 thrown about: `object_physics.gd`'s own share | 0.2 |
| Building the cinema's shapes, once | about 50 |

The 1.4 ms is mostly Jolt spreading each step over every worker thread, not work. A probe with nothing else running
(the same shapes and bodies) took 1.54 ms a tick with the pool's 30 threads, 0.38 ms with 4, 0.23 ms with 2 or 1;
one body cost 1.33 ms with 30 threads and 0.09 ms with 1. The Frame has 8 cores, so it should be between. At rest
it costs next to nothing: physics only costs while something moves (a throw lasts a few seconds).

## Tests

`app/tests/test_physics.gd` (66 checks): the shapes (primitives exact, hulls, the cinema's boxes), a box dropped on
the seat in front rests on its cushion, the place in the document and on disk, a ball thrown at the screen bounces
back off the picture (not off the wall behind), the 360 sphere collides, a 20 m/s pellet at a seat back doesn't pass
through, Put back and Tidy up (with objects still moving), the wall clock stays until pulled 0.4 m off and goes back
on the wall, an attached text follows its object in flight and where it lands and stays put when detached, the thud
(louder for faster, lower for bigger, the faster drop louder, where it happened), the grip picks up on the laser and
in the hand, the trigger does nothing while holding, a flick throws at the tip's speed, B cancels, the legends, an
imported object's hulls kept and made again, and the cost with 24 bodies.

## Open questions

- **Jolt's threads.** On many cores the step's wall time is mostly Jolt's job fan-out (above). The engine has no
  setting for Jolt's thread count: it takes the worker pool's. Choices: a fork setting
  `physics/jolt_physics_3d/simulation/max_threads` (two lines in `jolt_job_system.cpp`), or a smaller
  `threading/worker_pool/max_threads` for the whole app. Left as it is until the headset's number is known.
- **Light probes.** Off (above). If kept rooms are baked one day, probes (`LightmapGI.GENERATE_PROBES_SUBDIV_4`) and
  `gi_mode` dynamic on a picked-up object would light it; a moved object would then also leave its baked shadow
  behind until the next bake.
- **Placed objects don't move when hit.** As decided: only what is picked up moves. A thrown cabbage bounces off the
  pot plant.
- **The viewer's own seat** collides though it is folded away: an object dropped in your lap lands on your seat.
- **Contact shadows** under an object hide when it is picked up and come back when the room is built again.
- **Non-uniform scale.** A sphere or cylinder scaled unevenly collides as a hull; when it rests, its rotation is kept
  as the nearest rotation, which is not exact for such a shape turned on its side.
- **Attach targets** are placements by name, not their parts ("Shelf", not "Shelf/Board").
- **A held object** is driven to the hand in one tick and drawn interpolated, so it trails the controller by up to a
  tick. If that shows in the hand, draw a held object at the hand itself.
- **The thud's voices** share one renderer: when one ends, the others' places are given again, which may click.

## The film layer

On the Steam Frame the runtime draws the film layer (`film_layer.gd`) over everything in front of the screen, hole
punch or not: a ham lobbed at the screen vanished behind the picture (2026-11-06). While a room object
(`object_physics.gd solid_nodes()`: placed, held, thrown, or a text or particles area attached to one) is between the
eyes and the picture, the layer hides and the screen's mesh draws the film, as for the menu. The test is the object's
bounds, seen from the eyes, against the picture's rectangle; the layer comes back one second after the view is clear.
An object placed in front of the screen therefore keeps the film on the mesh for as long as it is there.
