# The seats system

Part of the environments engine: [`docs/environments.md`](../environments.md) has the design and says where each part is.

`scripts/env/systems/seats.gd`. Seat models outside the builders, and the seats a room draws with them.

### The models

Each model is low-poly (boxes and rounded boxes) in its own frame: the floor point under the seated eyes at the
origin, facing -Z. Each has two library materials (CC0), `upholstery` and `frame`, with its own defaults.

| Model | Triangles | Forms | Folds away | Use |
|---|---|---|---|---|
| `stadium` | 646 | up, broken | yes | the cinema's seat (the auditorium draws it itself) |
| `folding_chair` | 148 | | yes | slatted wooden chair, 1906 |
| `plush` | 644 | up, broken | yes | velvet tip-up seat on cast standards, palaces |
| `multiplex` | 656 | up, broken | yes | moulded shell, fabric insert, cup holder, 1980s |
| `pew` | 48 a place | | no | a segment a place wide; the ends are drawn apart |
| `club_chair` | 556 | | yes | deep leather armchair |
| `director` | 188 | | yes | crossed legs, canvas seat and back |
| `bench_seat` | 384 a place | | no | a convertible's tuck-and-roll bench; side trim drawn apart |
| `cushion` | 322 | | no | a buttoned floor cushion |
| `hide` | 462 | | no | a pelt over a low block (of ice) |
| `bean_bag` | 196 | | no | a squat sack with a dent |
| `civic` | 338 | | yes | a 1970s civic hall's seat: woven upholstery on a moulded oak shell, oak arms and standards (the Palace of Culture; since 2026-11-08) |
| `lounge` | 730 | | yes | a 1962 club chair in saddle leather: a low, deep body on a walnut frame, four tapered and splayed walnut legs with a shoe at each foot, rolled arms with round ends standing proud at the front, a loose seat cushion piped along its edges, a curved back wrapping the sitter a little and a loose back cushion leaning on it (the Screening room 1962; since 2026-11-08) |
| `recliner` | 428 | | yes | a premium recliner without arms: a deep cushion, a reclined back in two pads (lumbar and headrest), a shell to the floor; the room draws the armrests between the seats (the Flagship's kit, `flagship_rows`), so the viewer's own seat folds away and both its arms stay (since 2026-11-08) |
| `settee` | 276 a place, 106 an end | | no | a segment a place wide: the base, a seat cushion and a back cushion each; the padded arms and the feet are its ends. Two or three places in a row make a settee; its places take no tint of their own, so they match |

Forms: `up` is a tip-up seat tipped up (the hall is empty). `broken` is a seat with its back slumped and its cushion
hanging.

### Three ways in

- **The builders' seat slots.** A builder with `seat_slots()` (shopfront, nave, terrace, domestic, vehicle,
  dome_hall) draws no seats of its own when the room has a seats system. The seats system draws a seat in every slot.
  With `model` "auto" the slot's style chooses: chair: folding_chair, pew: pew, bench: bench_seat, cushion and tier:
  cushion, club: club_chair, ring: plush. The builder lists these seats (its `seats()`), so they are listed once.
  A slot is `{transform, row, style, width, builder}`. Slots of one row run left to right; a gap of more than 1.5
  widths starts a new pew. The pews' ends, the benches' trim and the settees' arms go into one static mesh,
  `SeatEnds`. With `model` `settee`, a builder's row of three slots is one settee (set the builder's seat pitch to
  about 0.6 m: the slot's width is the place's).
- **Its own seats.** Rows round `origin` (`per_row`, `rows_front`, `rows_back`, `pitch`, `row_depth`, `row_rise`,
  `aisle`, `facing`), and single `places` (`{at, turn, model}`). These are its `seats()`: seat choice, seat
  picking and the sight-line check use them.
- **Broken seats over a builder's own.** `broken` names room seats by their index in the room's seat list. Over a
  builder that draws its own seats (the auditorium, Screen 3), the seats system folds that seat away in the builder's
  MultiMesh "Seats" and draws a broken one of the builder's `seat_model` in its place. It does this again after every
  room move, so the seat stays away when the viewer has sat there and moved on. The broken seat takes the builder's
  seat materials (unless `upholstery` or `frame` is set). So it matches the seats next to it and adds no textures.
  `up` does the same with the tipped-up form (since 2026-11-08, for Reclaimed's empty stalls).

A builder can also draw any model itself: `seats.gd model_mesh(model, upholstery, frame, width, form)`. The
auditorium's `seat_mesh()` does, for every `seat_model` but the stadium seat.

### Drawing

- One MultiMesh a model and form: `Seats`, `SeatsUp`, `SeatsBroken`. The upholstery takes a slight tint seat by
  seat (`variation`, `seed`), as in the cinema.
- The viewer's own seat folds away (`fold_own`): chairs only. A pew, a bench, a settee, a cushion, a hide or a bean
  bag stays.
- `tipped`: the share of tip-up seats left tipped up.
- `collision_shapes()`: each seat's model boxes (one or two), for object physics.

Measured headless (`test_env_seats.gd`): 15 plush seats are 2 draws and 9 660 triangles. A tipped or broken form
adds two draws. Pews' ends add one or two. Texture memory is the headset's, rendered or not ("The checks").

| Parameter | Default | What |
|---|---|---|
| `model` | auto | the seat; auto: by each slot's style (its own rows: folding chairs) |
| `from_builders` | true | a seat in every seat slot of the room's builders |
| `per_row`, `rows_front`, `rows_back` | 0, 0, 0 | its own rows |
| `pitch`, `row_depth`, `row_rise`, `aisle` | 0 (the model's width), 1.1, 0, 0 | their spacing |
| `origin`, `facing` | [0, 0, 0], 0 | the middle of the row at origin; the rows' turn |
| `places` | [] | single seats: `{at, turn, model}` |
| `upholstery`, `frame` | null (the model's own) | library materials |
| `variation`, `seed` | 1, 1906 | the tint seat by seat |
| `tipped` | 0 | the share of tip-up seats tipped up |
| `broken` | [] | room seats drawn broken (at most 8) |
| `up` | [] | room seats drawn tipped up, a builder's own too (at most 24; tip-up models only) |
| `fold_own` | true | the viewer's own chair folded away |
