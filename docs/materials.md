# The material library

Textured surfaces for rooms: 42 CC0 texture sets (wood floors and parquet, carpet, velvet and upholstery, leather,
plaster and paint, concrete, brick, marble and tiles, metals, felt and acoustic foam, wicker), drawn with the rooms'
own fake light. The built-in rooms use them for floors, walls, seats and curtains; any code can put one on a mesh.

## Sources and licence

Every texture set is from [Poly Haven](https://polyhaven.com) or [ambientCG](https://ambientcg.com), under CC0 1.0
(public domain). The build script read each asset's page and stopped unless it said CC0; `app/materials/CREDITS.md`
lists each material's page, the authors the site gives (Poly Haven names them; ambientCG doesn't per asset), the
licence and the date it was checked. Only the processed files are in the repository; the downloads stay outside it.
CC0 needs no attribution and puts no condition on the MIT licence of the rest; the credits are a courtesy.

## What is in the repository

```
app/materials/<id>.json              one catalogue entry per material
app/materials/textures/<id>_<map>.mtex   albedo, normal, orm: ASTC 8 x 8, every mip level
app/materials/CREDITS.md             the source of every material
app/scripts/env/material_library.gd  the loader and the API
app/shaders/room_material.gdshader(inc), room_material_triplanar.gdshader, room_material_lit(_triplanar).gdshader,
                                     room_material_house.gdshader (the cinema: lit, ready for a lightmap)
tools/materials/                     build_materials.py, mtex_pack.cpp, make-packer.sh
app/tools/material_sheet.gd, material_bench.gd   a contact sheet, the cost benchmark
```

A catalogue entry:

| Key | What |
|---|---|
| `id` | snake_case, the file name |
| `name`, `tags` | for lists and search: floor, wall, seat, curtain, fabric, carpet, wood, leather, metal, stone, ... |
| `size` | 1024, or 2048 where a viewer gets close (five floors) |
| `tiling` | metres per repeat of the pattern (Poly Haven's real sizes; set by eye for ambientCG) |
| `tint`, `roughness_scale`, `normal_strength`, `specular`, `sheen` | tunables, the shader's defaults for this material |
| `swatch` | the mean colour of the base colour map (lists, and the `colour` option) |
| `maps` | `albedo`, `normal`, `orm` paths, relative to `app/materials` |
| `source` | site, asset, title, page, author, licence, the date the licence was checked |

## Size budget

About 52 MB for the 42 materials: 37 at 1K (1.05 MB each: three maps of 0.35 MB) and 5 floors at 2K (3.15 MB: base
colour and normal at 2K, the packed map at 1K). The budget is 60 MB (`test_materials` checks it). ASTC 8 x 8 is 2 bits
a texel, a quarter of ETC2's RGBA and an eighth of ASTC 4 x 4; at room distances the GPU samples the first or second
mip level, where the larger block hardly shows. Each map is in GPU memory as the file's size.

## How the headset loads them, and why this way

The app runs as a project folder (`docs/packaging.md`, "Why the app is a folder"): no PCK, no `.import` files, no
`.godot` import cache, and the export templates have no texture compressor. Imported textures (`.ctex`) would need
the editor's import step and an editor build of the fork; PNG or JPG would load uncompressed (5.6 MB of GPU memory
per 1K map with mipmaps) or need a compressor on the device.

So the maps are compressed on the PC, ahead of time, into the GPU's own format: ASTC 8 x 8 blocks with every mip
level, in the layout the engine's `Image` keeps them (`.mtex`: a 32-byte header and the blocks). The loader reads the
file (`FileAccess.get_file_as_bytes`), checks the header and size, and hands the bytes to
`Image.create_from_data(..., FORMAT_ASTC_8x8)` and `ImageTexture.create_from_image()`: no decode, no conversion, the
blocks go to the GPU as they are. The headset's Adreno samples ASTC LDR (ETC2 too; ASTC gives the better quality at
this size). Albedo is encoded for an sRGB view, normals in the encoder's normal mode (X in RGB, Y in alpha), the
packed map as linear data. A GPU without ASTC (a PC; lavapipe) gets the image decompressed once on load.

Each map is read once and cached by path; materials with the same id and options are one shared `ShaderMaterial`.
On a PC (WSL, /mnt/c) reading and decoding all 126 maps took 0.94 s, about 22 ms per material; a room uses about
five.

## The shader

`room_material.gdshader` (all in `room_material.gdshaderinc`) keeps `env_unlit.gdshader`'s look: unshaded, the
room's ambient level (`env_light`) plus the screen's fall-off spill (`env_spill.gdshaderinc`, the bias light's
colour included), darker towards the floor (`floor_darkening`), with `spill` as each surface's catch. No lights, no
shadows, no light pass. On top:

- **Normal map:** the tilt of each texel against the flat surface changes how much it catches: towards the screen,
  more of the spill; upwards, more of the ambient. A flat texel gets exactly env_unlit's light (`relief` 0.8).
- **Ambient occlusion** (R of the packed map) darkens grooves and grout.
- **Highlight:** a soft lobe around the screen's reflection, in the picture's colour, sharper on smooth surfaces
  (roughness from G, `roughness_scale`; `specular`). Metals (B) show their colour dimmer and their highlight tinted.
- **Sheen** at grazing angles for velvet and pile fabrics (`sheen`).
- **Pleats** (`pleats` folds per metre, `pleat_depth`): curtains fold and shade without geometry.

Texture coordinates: by default each face uses the two object axes across it, in metres with the instance's scale
("box": one fetch per map, exact on boxes and planes, MultiMesh instances included). `uv: true` uses the mesh's UVs
(`repeat` times). `room_material_triplanar.gdshader` blends three projections for meshes with neither (spheres,
scans): three times the fetches, so only where the box projection shows seams. All maps sample with mipmaps and
anisotropic filtering (the project's default level), so floors don't shimmer.

## Cost

`app/tools/material_bench.gd` draws one surface over a whole 1728 x 1728 view (one eye of the headset), facing and as
a floor seen low, with each shader. On the PC's software renderer (lavapipe, 2026-11-03), over an empty view:

| Shader | Facing | Floor |
|---|---|---|
| env_unlit | 2.4 ms | 1.1 ms |
| room_material, box | 20.0 ms (8.4x) | 11.1 ms (10.3x) |
| room_material, mesh UVs | 24.3 ms (10.2x) | 10.4 ms (9.7x) |
| room_material_triplanar | 62.1 ms (26x) | 35.0 ms (33x) |

The software renderer filters textures on the CPU, so the ratios overstate what a GPU pays for the fetches.
Estimate for the headset (not yet measured there): about 100 arithmetic operations and 3 anisotropic fetches of
2-bit-per-texel ASTC a pixel. Both eyes are 6 Mpixel; at the Adreno's few TFLOPS that is roughly 0.3-0.5 ms of
arithmetic and 0.3-0.8 ms of texturing if every pixel of both eyes were a library surface, against roughly 0.1 ms for
env_unlit; a room with the screen in view covers about half of that. So about 0.3-0.7 ms of the 11.1 ms frame at
90 Hz (13.9 at 72). Triplanar costs about three times the texturing: keep it to small parts. To measure on the
headset: `perf` before and after a room change (`docs/assistant.md`, "Performance"), or this benchmark.

## Rooms that use it

| Room | Surfaces |
|---|---|
| Cinema | lit for real (the house form, below): walls and wall panels `felt`, ceiling and its clouds `acoustic_foam`, tiers, aisle steps and walkways `woven_carpet`, seats `velvet` (a tint per seat) with `black_leather` arms and standards, stage `red_hardwood`, pleated `velvet` curtains and valance, panel rails and doors `walnut_veneer`, door frames and push bars `brushed_steel`, sconce plates and handrails `brass` |
| Home theatre | walls `smooth_plaster`, floor `herringbone_parquet`, rug `woven_carpet`, cabinet and table `walnut_veneer`, panels and speaker cloth `felt`, sofa `herringbone_upholstery` |
| Dim room | walls and ceiling `smooth_plaster` (the grid floor stays) |
| Planetarium | seats `velvet`, floor `plush_carpet` |
| Dome | platform `rustic_planks`, rail `brushed_steel` |

Each keeps its colours (the `colour` option: the material's mean colour becomes the room's old colour) and its light.
The drive-in and the passthrough room are unchanged. Before (above) and after (below), left eye, from the screenshot
tour (`--shots=DIR --shots-only=env_`, lavapipe): `docs/shots/materials/env_*.png`; every material on a box
and a floor (`app/tools/material_sheet.gd`): `docs/shots/materials/catalogue.jpg`.

In an assistant's room with real lighting (`docs/assistant.md`, "Lighting") the built-in rooms keep their library
materials in their lit form: that room relights `env_unlit` surfaces as `room_lit` ones and library surfaces with
`MaterialLibrary.lit_variant()` (below).

## In the assistant's rooms and the Objects tab

A room document's material object may name a library material (`"library_material": "velvet"`, with `color`, `tint`,
`tiling`, `triplanar`; `docs/assistant.md`, "Library materials"): on a part, a whole placed object, one part of it or
a base room surface. `recolour {match, material: "<id>"}` puts one there; the Objects tab's parts editor has a
**Material** picker (each material's swatch and name, by kind; `docs/USAGE.md`, "The Objects tab"). Every surface
with the same material and options shares one `ShaderMaterial`. `room_state` reports each surface's material id and
its mean colour (`MaterialLibrary.id_of()`, `shown_colour()`).

### The lit form

`room_material_lit.gdshader` and `room_material_lit_triplanar.gdshader` are the same include with `LIT` defined, for
an assistant's room with real lighting (a key light, a sky fill, the screen's light, point lights): not unshaded, the
engine's lights and shadows fall on the maps' colour, roughness (`roughness_scale`), metalness (half: there is
nothing to reflect) and normals (`normal_strength`, pleats included), and room_lit.gdshader's hemisphere fill, film
light and contact darkening are added as emission, times ambient occlusion; sheen at grazing angles from the fill.
`get_material(id, {"lit": {sky_top, sky_bottom, screen}})` makes one directly (the assistant's parts);
`lit_variant(material, lighting)` turns an unlit library material into its lit form with every setting copied (a
built-in room's surfaces when that room is lit), one per material and lighting, shared. Not yet measured on the
headset: it adds the engine's per-light work to the three fetches.

### The house form

`room_material_house.gdshader` is the lit form with `HOUSE` defined too, for a built-in room lit for real and ready
for a baked lightmap: the cinema (`app/environments/cinema.gd`). `get_material(id, {"house": {sky_top,
sky_bottom}})` makes one; the room sets the rest on its own copy:

- **The house lights' level** is the room light (`env_light` over `house_reference`, the room's ambient level),
  squared: 1 as designed, 12 % while the film plays (room light 0.35). It scales what the engine lights (`ALBEDO`:
  a baked lightmap, a light) and the fill, so the house lights go down with a lightmap too.
- **The screen's light** is the unlit rooms' spill (`screen_glow`, the bias light's colour, `spill`), facing as the
  lit form's film light; not `screen_light`.
- **Lamps** stand in for the room's lights until a lightmap is baked: up to 8 soft point lights without shadows
  (`lamp_count`, `lamp_position` xyz and range in the world, `lamp_colour` rgb times energy, w > 0 for a light that
  shines only up and down: a wall sconce's scallops), added as emission. No light pass.
- **`instance_tint`** multiplies the base colour by the MultiMesh instance's colour (the cinema's seats).
- **`vertex_light`** (rgb; 0, nothing, by default) adds light worked out in code and carried in the vertex colours'
  alpha: the surface's colour times it times the alpha, as bright as the house level, and in the bake as an emitter
  so its light bounces on. Since 2026-11-08, for Reclaimed's Moon: its shadows through the open roof, the walls and
  the trusses traced as the room is built (`kit/reclaimed.gd`), as the run-time lightmapper gave none.
- **`bake_pass`** is what the lightmapper renders of the surface: its colour at level 1, no fill, spill or lamps
  (they would bake in as light).

A `vec3` uniform set with a `Color` comes back as a zero `Vector3` from `ShaderMaterial.duplicate()`: the cinema sets
the fill again as `Vector3`s on its copies.

## Using it

```
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
MaterialLibrary.list()                       # [{id, name, tags, tiling, swatch, size, source, user}], by name
MaterialLibrary.entry("velvet")              # the catalogue entry
MaterialLibrary.get_material("velvet", {"colour": Color(0.4, 0.05, 0.08)})   # a shared ShaderMaterial, or null
MaterialLibrary.apply(mesh_instance, "oak_planks", {"tiling": 1.5})          # material_override
MaterialLibrary.apply(mesh_instance, "felt", {}, 2)                          # one surface's override
```

Options: `colour`, `tint`, `tiling`, `turn` (degrees), `offset`, `uv`, `repeat`, `triplanar`, `roughness_scale`, `normal_strength`,
`specular`, `sheen`, `pleats`, `pleat_depth`, `spill`, `floor_darkening`, `emission` (added on top), `lit` (the lit
form, above). A primitive room has
`textured(id, colour, spill, floor_darkening, options)`, which falls back to its plain material. The returned
material is shared: `duplicate()` it before changing it for one surface.

The `materials` command (dev link and assistant, `read`): the list, `tag` to filter.

## User materials

Materials the viewer imports on the headset, in **Objects → Surfaces** or with `material_import`, from Quixel
Megascans (through Fab), Poly Haven or ambientCG (`docs/features.md`, "Surfaces"; `app/scripts/env/surface_import.gd`).
None is in the repository or a release.

```
user://materials/<id>.json                 the entry, as a bundled one, with "user": true
user://materials/textures/<id>_albedo.jpg  base colour, the ambient occlusion multiplied in
user://materials/textures/<id>_normal.png  RGBA: X in RGB, Y in alpha (as the shader reads .mtex)
user://materials/textures/<id>_orm.png     R 1 (no occlusion: it is in the colour), G roughness, B metal; half size
```

- **The id:** the site's prefix and the asset (`ph_`, `acg_`, `ms_`), so the same asset is imported once.
- **The entry's `source`:** `site`, `name`, `asset`, `title`, `page`, `author`, `licence` (CC0 1.0, or "Fab Standard
  License (the viewer's own)" for Megascans), `listing` (Fab's) and `imported` (the date). Also `tiling_from`
  (`size`: the scan's real size; `default`: 1 m), `format` and `gpu_bytes`.
- **The library:** `MaterialLibrary.list()` and `entry()` have them beside the bundled ones (`source`: the site, else
  `bundled`; `user`: true). `get_material()`, `apply()` and the rooms' `library_material` take them as any other.
  `forget_user()` reads the folder again after an import or a delete.
- **Loading:** a JPEG or PNG map is decoded, gets its mipmaps and goes to the GPU uncompressed (RGBA8).

### ASTC on the headset: the encoder in the export templates (PLAYER_ASTC)

`surface_import.gd` tries `Image.compress(COMPRESS_ASTC, ..., ASTC_FORMAT_8x8)` once at start. Upstream's export
templates can't: `modules/astcenc/SCsub` builds astcenc with `ASTCENC_DECOMPRESS_ONLY` unless `env.editor_build`, and
`modules/astcenc/register_types.cpp` sets `Image::_image_compress_astc_func` only under `#ifdef TOOLS_ENABLED`, so
they decode ASTC but don't encode it. On such an engine user materials are 1K, uncompressed.

The fork (`95e9090166`, "astcenc: the encoder in the export templates too") builds the encoder in every build and
registers the hook outside `TOOLS_ENABLED`. The engine with it is PLAYER_ASTC (`docs/BUILD.md`), on the headset
since 2026-11-07. Measured there: `material_status` says `2K ASTC 8x8`; a Poly Haven material (8.4 MB download)
imported in about 20 s, all three maps 2048 x 2048 as `.mtex` with every mip level, 1.4 MB each. The import code did
not change: it writes `.mtex` files, and takes 2K maps, when the probe succeeds. Materials imported before keep their
1K PNG maps until imported again.

### Memory, each material

| | Colour | Normal | Packed | All three |
|---|---|---|---|---|
| Bundled, 1K, ASTC 8 x 8 | 0.35 MB | 0.35 MB | 0.35 MB | 1.05 MB |
| User, 1K, uncompressed (now) | 5.6 MB | 5.6 MB | 1.4 MB (512) | 12.6 MB |
| User, 2K, ASTC 8 x 8 (PLAYER_ASTC, measured) | 1.4 MB | 1.4 MB | 1.4 MB (2K) | 4.2 MB |

With mipmaps. A room with five user materials takes about 21 MB of GPU memory with ASTC (63 MB at 1K uncompressed)
against 5 MB for bundled ones.
`material_status` gives the sum on disk, the sum if all were loaded and what is loaded now
(`MaterialLibrary.memory()`).

### Making a CC0 import a bundled one

A Poly Haven or ambientCG material (CC0) that should ship goes through the usual path (below, "Adding a
material"): write `app/materials/<id>.json` with `"source": {"site": ..., "asset": ...}` from the user entry's
`source`, and `build_materials.py --only <id>` downloads it again, checks the licence and packs it. The user entry's
`tiling` is a good start. Never copy the files from `user://`, and never a Megascans one: it is under the viewer's
Fab licence, not CC0.

## Adding a material

1. Find a CC0 texture set on Poly Haven or ambientCG with a base colour, an OpenGL normal map and roughness (ambient
   occlusion and metallic are optional).
2. Write `app/materials/<id>.json` with `id`, `name`, `tags`, `size` (1024 unless a viewer gets close), `tiling`
   (leave it out for Poly Haven: the asset's real size is used), the tunables, and
   `"source": {"site": "polyhaven" or "ambientcg", "asset": "<the site's id>"}`.
3. Once: `wsl -d Ubuntu -- bash tools/materials/make-packer.sh` (builds the packer from the engine tree's encoder).
4. `python tools/materials/build_materials.py --only <id>` (Python 3 with Pillow and NumPy; on Windows the packer
   runs through WSL). It downloads, checks the licence, packs, fills in the entry and rewrites `CREDITS.md`.
5. Look at it: `xvfb-run -a godot --xr-mode off --path app --script res://tools/material_sheet.gd -- --out=DIR
   --only=<id>` (with `VK_ICD_FILENAMES` for lavapipe, `docs/BUILD.md`), and tune `tiling` and the tunables.
6. Run `test_materials` (the budget, the files, the credits).
