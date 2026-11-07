extends RefCounted

## The room document (docs/assistant.md, "Rooms"): the data an assistant sends to build or change the room. Data only:
## nothing in it is run, evaluated or loaded as a script; models are glTF binaries read with the engine's GLTFDocument
## and checked (assistant_room.gd). Schema 3: rooms are made of objects (docs/decisions.md, "Rooms are made of
## objects"). A kept room's every part is a placement of an object from the object library (object_library.gd):
##
##   placement: {"name": "Poster", "object": "<library id>", "position": [x, y, z], "rotation": [x, y, z],
##               "scale": s or [x, y, z], "material": material without a picture (an override: color, self_lit,
##               emission, emission_strength, alpha, library_material and its options, effect), "widget",
##               "widget_options", "motion"; object "text": "text", "text_options"; object "particles": "particles";
##               object physics (docs/physics.md): "home" {position, rotation, mounted?}: where it was placed, kept
##               once it has been moved by hand or thrown (Put back and Tidy up return it there); "mounted": false, a
##               wall object pulled off its wall; a text or particles area: "attach" (another placement's name) and
##               "offset" [x, y, z] (metres in that object's frame): it follows that object, its rotation then
##               relative to it}
##
## The built-in primitives (object_builtins.gd) are a 1 m box, a 1 m sphere, a cylinder 1 m across and 1 m tall and a
## 1 x 1 m plane facing up: a placement's scale is their size (box [w, h, d], sphere s, cylinder [d, h, d], plane
## [w, 1, d]). "text" is a line 0.1 m high at scale 1, "particles" an area of 1 m a side at scale 1. Any other object is
## a model (a .glb in the library). build_form() turns a placement into the part the room is built from.
##
## A part may still be sent as a shape (the schema-2 way below: type, size, model, texture): room_editor.gd keeps it as
## a placement when the change is applied (room_keep.gd): an inline model and a part with a picture become user objects
## in the library, a plain shape a placement of a built-in primitive. Schemas 1 and 2 are still read; a kept room of
## either is converted once when it is loaded. A part as sent in schema 2 (schema 1 is schema 2 without objects and part
## addressing):
##
##   {"schema": 2,
##    "name": "Lounge at dusk",                    what the kept room is called (letters, digits, space, - _; <= 40)
##    "base": "dim_room",                          new_room: a stock room id (room_state lists them), or
##    "base_model": "<base64 .glb>",               new_room: a whole room as glTF (app/docs/rooms.md convention)
##    "light": {"ambient": 0.2, "screen_glow": 0.6},
##    "sky": {"color": "#0a1020"} or {"image": "<base64 PNG/JPEG>"} or {} (none); "effect": {"name": "sky_aurora",
##           ...options}: a sky from the effect library (docs/effects.md; effects surface=sky),
##    "parts": [part, ...],                        added, or replaced when the name exists
##    "recolour": [{"match": "Wall*", "material": material}, ...],   the base room's own parts, by name pattern;
##                 "Shelf/Board" (schema 2): the part Board inside the placed model Shelf (both sides patterns);
##                 "material": null in a change takes an entry out again (the part shows its own colours)
##    "remove": ["lamp"],                          patch: parts the assistant added before
##    "lights": []}                                always empty: the rooms are unlit (use emission)
##   part: {"name": "lamp", "type": "box" | "sphere" | "cylinder" | "plane" | "model" | "text",
##          "size": [w, h, d] (box) / [diameter] (sphere) / [diameter, height] (cylinder) / [width, depth] (plane)
##                  / [line height] (text, default 0.1),
##          "model": "<base64 .glb>" (type model),
##          "object": "shelf" (type model, schema 2): the object library's id it was placed from (object_library.gd),
##          "text": "Now showing", "text_options": {color, background, weight, align, max_width} (type text),
##          "position": [x, y, z] metres (the room frame: the seat at the origin facing -Z, the floor at y = 0),
##          "rotation": [x, y, z] degrees, "scale": s or [x, y, z],
##          "material": material, "widget": "clock", "widget_options": {...}}
##   material: {"color": "#rrggbb" or [r, g, b], "emission": "#rrggbb", "emission_strength": 0..10,
##              "texture": "<base64 PNG/JPEG>", "self_lit": bool (default: true with a texture),
##              "uv": "atlas" | "each_face" | "front_only" (box only; how the picture lies on it),
##              "roughness": 0..1 (accepted; the rooms are unlit),
##              "library_material": "oak_planks" (schema 2): a textured material from the material library
##                                  (scripts/env/material_library.gd; the materials command lists the ids); with it
##                                  "color" is the colour it shows on average (its pattern kept), "tint": "#rrggbb"
##                                  multiplies it, "tiling": metres per repeat (0.02..20), "triplanar": true for
##                                  curved meshes without usable UVs; not with texture; with an effect only one
##                                  that layers (a layered look); an id the app doesn't know is left out with a
##                                  warning (the rest applies),
##              "effect": {"name": "plasma", ...options}: a look from the effect library (docs/effects.md; the
##                        effects command lists them, effect_info gives the options)}
##   shown = color x texture x (self_lit ? 1 : the room's light) + emission x emission_strength (assistant_room.gd)
##
## validate(doc, mode) checks a whole document and returns every problem with its JSON path, so an assistant can fix
## them all at once. Modes: "new" (a whole room), "patch" (changes to the room on show), "saved" (a kept room read
## back from disk, where pictures are files next to it: texture_file in a recolour entry, image_file, base_model_file;
## a kept room of schema 1 or 2 also model_file and a part's texture_file). A kept room of schema 3 has placements only,
## without pictures.

const VERSION := 3
## The versions read: 1 is 2 without objects ("object"), part addressing ("Shelf/Board") and library materials; 2 is 3
## without placements (a part without type).
const VERSIONS: Array[int] = [1, 2, 3, 4]
## Version 4: version 3 with the environments engine's sections (docs/environments.md; scripts/env/env_doc.gd checks
## them): room, acoustics, systems, settings, cues, timeline, audio, credits. Kept rooms are still written as VERSION.
const SYSTEMS_VERSION := 4
const ENV_DOC := "res://scripts/env/env_doc.gd"
## The built-in primitive objects (object_builtins.gd): a placement's scale is their size.
const PRIMITIVES: Array[String] = ["box", "sphere", "cylinder", "plane"]
## The built-in objects made per placement from its options (object_builtins.gd GENERATORS): their node is generated
## (a text's words, a particles area), not read from a .glb.
const GENERATORS: Array[String] = ["text", "particles"]
## A placement's keys (a kept room's parts).
const PLACEMENT_KEYS: Array[String] = ["name", "object", "position", "rotation", "scale", "material", "widget",
		"widget_options", "motion", "text", "text_options", "particles", "home", "mounted", "attach", "offset"]
## A placement's object physics keys (docs/physics.md): checked by the placement, not by the part it is built as.
const PHYSICS_KEYS: Array[String] = ["home", "mounted", "attach", "offset"]
## A text object at scale 1: one line this high (metres).
const TEXT_OBJECT_LINE := 0.1
## An object library id (object_library.gd) or a library material's: lower-case letters, digits, - and _.
const ID_MAX := 64
## A library material's own options in a material object (only with library_material), and its tiling's range.
const LIBRARY_OPTIONS: Array[String] = ["tint", "tiling", "triplanar", "turn"]
const TILING_MIN := 0.02
const TILING_MAX := 20.0
const PART_TYPES: Array[String] = ["box", "sphere", "cylinder", "plane", "model", "text", "particles"]
const PARTICLES_SCRIPT := "res://scripts/assistant/room_particles.gd"
const NAME_MAX := 40
## How a picture lies on a box (assistant_room.gd): atlas (the engine's BoxMesh layout: one picture cut into six
## pieces, one per face), each_face (the whole picture on every face), front_only (the whole picture on the +Z face,
## the other faces plain).
const UV_MODES: Array[String] = ["atlas", "each_face", "front_only"]
## How a material treats transparency (assistant_room.gd alpha_mode()): opaque; cutout (a pixel is drawn or not, by
## its alpha: silhouettes, cut-out cards; the default for a picture with transparent pixels); blend (see-through by
## alpha: glass, haze; the default for a colour with alpha below 1).
const ALPHA_MODES: Array[String] = ["opaque", "cutout", "blend"]

## Brightness may change no faster than this (Hz) and by no more than MAX_SWING of the surface's own brightness:
## every effect and widget stays under it (the photosensitivity ceiling; the shaders clamp too).
const MAX_HZ := 3.0
const MAX_SWING := 0.4
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
## Material effects (docs/effects.md): {name: {description, options}}, the effect library's surface effects; the
## sky's (sky.effect) are SKY_EFFECTS.
static var EFFECTS: Dictionary = EffectLibrary.schema_effects(false)
static var SKY_EFFECTS: Dictionary = EffectLibrary.schema_effects(true)

## What each thing costs the headset's frame, in the units of LIMITS.cost (the room's total is capped so the film keeps
## its frame rate: 72 Hz on the Frame). Relative weights, set from what each draws per frame.
const COSTS := {
	# A shape: one draw call. Measured on the Frame (2026-11-01, a film playing, room_perf.calibrate with 0.4 m boxes):
	# 100 in a grid +1.3 ms GPU, 400 in a grid or scattered within the noise (+-1.5 ms), +0.15 to 0.5 ms CPU; so
	# about 0.003 to 0.013 ms each, not the 0.05 one cost stands for (it was 1.0). What a part costs is its area on
	# screen, its effect and the lights, priced separately; the measured guard (room_perf.gd) catches the rest.
	"part": 0.2,
	"model": 2.0,              # a model's draws, plus model_per_10k_triangles
	"model_per_10k_triangles": 1.0,
	"model_part": 0.2,         # each part of a model past the first: a draw call, as a shape
	"part_recolour": 0.05,     # a part-level recolour: one more material (its draw call is counted already)
	"text": 1.0,               # a Label3D
	"widget": 2.0,             # a canvas redrawn now and then, and its quad
	"blend": 1.0,              # see-through: drawn in the transparent pass, over what is behind
	"motion": 0.25,            # moved every frame: a few multiplies on the CPU
	"effect": 1.0,             # a shader with more arithmetic than the plain one
	"effect_second_pass": 1.0, # toon_outline: the part drawn twice
	# A library material (docs/materials.md, "Cost"): three texture fetches and about 100 operations a pixel, some
	# 8-10x env_unlit on the software renderer; triplanar three times the fetches.
	"library_material": 0.5,
	"library_triplanar": 1.0,
	# Lighting, from the GPU time measured on the Frame (2026-11-01: both eyes, a 4K film playing, 150 lit boxes):
	# one cost is about 0.05 ms. A directional light 0.8 ms, its orthogonal shadows 0.5-0.6 ms more, a point light
	# about 0.25 ms when its range (8 m) covers the room. Change these when the measurements change.
	"key_light": 16.0,
	"key_shadows": 12.0,
	"point_light": 5.0,        # at POINT_LIGHT_COST_RANGE metres of range, scaled with the range (0.25x..2x)
	"screen_light": 1.0,       # the film's light: arithmetic in the lit shader
	"contact_shadow": 0.1,     # a multiplied quad under a part on the floor
	"glow_react": 1.0,         # screen_glow with react: noise in the shader, the picture's copy kept fresh
	"sky_stars": 1.0,          # the sky's whole sphere: a hash and a soft dot a pixel
	"sky_clouds": 2.0,         # four octaves of noise a pixel over the sky
	"fog_layer": 0.6,          # a blended layer over the floor (FOG_LAYERS of them)
	"particles_emitter": 1.0,  # one draw of many quads, moved on the GPU
	"particles_per_100": 1.0,  # their fill: soft sprites overlap
}
const TEXT_LINE_DEFAULT := 0.1
const TEXT_LINE_MIN := 0.005
const TEXT_LINE_MAX := 5.0
## A text part's options (type text), checked as widget options are.
const TEXT_OPTIONS := {
	"color": {"type": "color", "default": "#f2f2f2"},
	"background": {"type": "color", "default": null, "description": "a panel behind the text; none when left out"},
	"weight": {"type": "enum", "values": ["regular", "bold"], "default": "regular"},
	"align": {"type": "enum", "values": ["left", "center", "right"], "default": "center"},
	"max_width": {"type": "float", "min": 0.0, "max": 50.0, "default": 0.0,
			"description": "metres; longer lines wrap at word breaks; 0: no wrapping"},
}

## Limits per room (what the assistant added; the stock room is not counted). A refusal names the limit and its value.
const LIMITS := {
	"parts": 512,  # was 64; parts measured cheap on the Frame (COSTS["part"])
	"triangles": 300000,
	"model_triangles": 150000,
	"model_bytes": 20 * 1024 * 1024,
	"image_bytes": 8 * 1024 * 1024,
	"texture_size": 4096,
	"textures": 32,
	"widgets": 8,
	"texts": 16,
	"text_chars": 1000,
	"cost": 120,
	"emitters": 6,
	"particles_per_emitter": 600,
	"particles": 2000,
	"lights": 4,
	"extent_m": 200.0,
	"seats": 12,
	# A model's parts (its mesh nodes, each addressable as "<name>/<part>") and the room's recolour entries: each part
	# is a draw call of its own, and each recolour a material.
	"model_parts": 128,
	"recolours": 256,
}

## The room's screen, as seen from each seat's eyes (the seat's floor point + NOMINAL_EYE_HEIGHT): its width at least
## SCREEN_MIN_DEG and at most SCREEN_MAX_DEG across, its height at most SCREEN_MAX_TALL_DEG, at least
## SCREEN_MIN_DISTANCE away and in front of it (the seat on the screen's facing side).
const SCREEN_MIN_DEG := 12.0
const SCREEN_MAX_DEG := 100.0
const SCREEN_MAX_TALL_DEG := 75.0
const SCREEN_MIN_DISTANCE := 1.0
## The screen stays where the room puts it, facing its own way: a seat further off its axis than this sees it squashed.
const SCREEN_MAX_OFF_AXIS_DEG := 45.0
const SCREEN_WIDTH := [0.3, 60.0]
const NOMINAL_EYE_HEIGHT := 1.2

## The widgets the app draws on a part, with their options: {type, default, values | min/max, description}.
const WIDGETS := {
	"clock": {"description": "the time of day, on the part's front", "options": {
		"style": {"type": "enum", "values": ["analog", "digital"], "default": "analog"},
		"hours_24": {"type": "bool", "default": true, "description": "digital: 24-hour; default the app's setting"},
		"color": {"type": "color", "default": "#f2f2f2"},
		"background": {"type": "color", "default": "#1c1c1c"}}},
	"film_progress": {"description": "how far the film is, as a bar or a ring", "options": {
		"style": {"type": "enum", "values": ["bar", "ring"], "default": "bar"},
		"color": {"type": "color", "default": "#e8a33c"},
		"background": {"type": "color", "default": "#1c1c1c"}}},
	"now_playing": {"description": "the title of what plays", "options": {
		"color": {"type": "color", "default": "#f2f2f2"},
		"background": {"type": "color", "default": "#1c1c1c"}}},
	"end_time": {"description": "when the film ends (\"ends 23:20\")", "options": {
		"color": {"type": "color", "default": "#f2f2f2"},
		"background": {"type": "color", "default": "#1c1c1c"}}},
	"battery": {"description": "the headset's battery, and the controllers'", "options": {
		"controllers": {"type": "bool", "default": true},
		"color": {"type": "color", "default": "#f2f2f2"},
		"background": {"type": "color", "default": "#1c1c1c"}}},
	"screen_glow": {"description": "the part glows in the colour of the picture (the bias light's colour)",
		"options": {"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0},
			"react": {"type": "enum", "values": ["none", "brightness", "loudness"], "default": "none",
				"description": "the glow moves with the film's brightness or loudness"},
			"style": {"type": "enum", "values": ["shimmer", "ripple"], "default": "shimmer",
				"description": "shimmer: light drifting over it like caustics; ripple: soft rings from its centre"},
			"amount": {"type": "float", "min": 0.0, "max": MAX_SWING, "default": 0.25,
				"description": "how far the brightness moves, at most 0.4"}}},
}

## The sky's named options (shaders/room_sky.gdshader) and the room's atmosphere (shaders/room_fog.gdshader).
const SKY_OPTIONS := {
	"stars": {
		"density": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
			"description": "how many: 1 a clear night"},
		"twinkle": {"type": "float", "min": 0.0, "max": MAX_SWING, "default": 0.25,
			"description": "how far each star's brightness wanders, slowly, each at its own pace; at most 0.4"},
		"color": {"type": "color", "default": "#ffffff"}},
	"clouds": {
		"cover": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "description": "how much of the sky"},
		"speed": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.5, "description": "how fast they drift"},
		"color": {"type": "color", "default": "#cdd3de"}},
}
const ATMOSPHERE_OPTIONS := {
	"fog": {
		"density": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5},
		"height": {"type": "float", "min": 0.1, "max": 1.5, "default": 0.5, "description": "metres above the floor"},
		"speed": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.3, "description": "how fast it drifts"},
		"color": {"type": "color", "default": "#c0c8d2"}},
}
## Real lighting (room_lit.gdshader; docs/assistant.md "Lighting"). Bounds keep a lit surface under 1.0 (no tone
## mapping: the film's colours must stay exact) and every flicker under the photosensitivity ceiling.
const LIGHT_OPTIONS := {
	"key": {
		"direction": {"type": "vec3", "default": null, "description": "the way the light travels (down and across); "
			+ "or elevation and azimuth"},
		"elevation": {"type": "float", "min": 0.0, "max": 90.0, "default": 50.0, "description": "degrees above the "
			+ "horizon the light comes from"},
		"azimuth": {"type": "float", "min": -360.0, "max": 360.0, "default": 30.0, "description": "degrees round "
			+ "from the front (-Z) towards the right (+X) where the light comes from"},
		"color": {"type": "color", "default": "#fff2e0"},
		"energy": {"type": "float", "min": 0.0, "max": 1.5, "default": 0.8},
		"shadows": {"type": "bool", "default": true}},
	"sky": {
		"top": {"type": "color", "default": "#4a5878"},
		"bottom": {"type": "color", "default": "#2a2420"},
		"energy": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35}},
	"screen": {
		"energy": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6, "description": "the film's light on the "
			+ "room; follows the picture's colour, smoothed (never faster than 3 Hz)"}},
}
const FLICKER_OPTIONS := {
	"rate": {"type": "float", "min": 0.1, "max": MAX_HZ, "default": 1.2, "description": "Hz, at most 3"},
	"swing": {"type": "float", "min": 0.0, "max": MAX_SWING, "default": 0.25},
}
const POINT_LIGHT_OPTIONS := {
	"name": {"type": "string", "default": ""},
	"type": {"type": "enum", "values": ["point", "spot"], "default": "point"},
	"position": {"type": "vec3", "default": null, "description": "the room frame; or attach"},
	"attach": {"type": "string", "default": "", "description": "a part's name: the light moves with it"},
	"offset": {"type": "vec3", "default": [0, 0, 0], "description": "from the attached part's centre, its frame"},
	"color": {"type": "color", "default": "#ffb060"},
	"energy": {"type": "float", "min": 0.0, "max": 6.0, "default": 1.5},
	"range": {"type": "float", "min": 0.5, "max": 16.0, "default": 5.0, "description": "metres; the cost grows with it"},
	"direction": {"type": "vec3", "default": [0, -1, 0], "description": "spot: where it points"},
	"angle": {"type": "float", "min": 5.0, "max": 80.0, "default": 35.0, "description": "spot: its cone, degrees"},
	"flicker": {"type": "flicker", "default": null, "description": "{rate, swing}: firelight, under the "
		+ "photosensitivity ceiling"},
}
## A point light costs COSTS.point_light at this range (metres), scaled with its range.
const POINT_LIGHT_COST_RANGE := 8.0
## The key light's shadow map while a room uses it (the project's own is coarse); set back when the room goes.
const KEY_SHADOW_ATLAS := 2048

## The fog's layers: drawn over one another, so each costs.
const FOG_LAYERS := 5

const IMAGE_KEYS := ["texture", "image"]


## {"ok": bool, "errors": [{"path": "$.parts[2].size", "error": "..."}]}
static func validate(doc: Variant, mode: String) -> Dictionary:
	var errors: Array = []
	if not (doc is Dictionary):
		return {"ok": false, "errors": [{"path": "$", "error": "the room must be a JSON object"}]}
	var d: Dictionary = doc
	var known := ["schema", "name", "base", "base_model", "light", "sky", "atmosphere", "seats", "default_seat",
			"screen", "parts", "recolour", "remove", "lights"]
	if mode == "saved":
		known.append("base_model_file")
	var v4 := is_finite(_num(d.get("schema", 0))) and int(_num(d.get("schema", 0))) == SYSTEMS_VERSION
	if v4:
		known.append_array((load(ENV_DOC) as GDScript).get("SECTIONS"))
	for k: Variant in d:
		if not (str(k) in known):
			errors.append(_e("$.%s" % k, "unknown key (known: %s)" % ", ".join(known)))
	var version := int(_num(d.get("schema", 0))) if is_finite(_num(d.get("schema", 0))) else 0
	if not (version in VERSIONS):
		errors.append(_e("$.schema", "must be %d (%s are still read)" % [VERSION, ", ".join(VERSIONS.slice(0, -1))]))
	else:
		if version < 2:
			for p: String in _schema2_paths(d):
				errors.append(_e(p, "needs \"schema\": 2 (objects, \"name/part\" matches and library materials)"))
		if version < 3:
			for p: String in _schema3_paths(d):
				errors.append(_e(p, "needs \"schema\": 3 (a part placed as an object: object without type)"))
	if v4:
		(load(ENV_DOC) as GDScript).call("validate_sections", d, errors)
	if d.has("name") and not _name_ok(d["name"]):
		errors.append(_e("$.name", "letters, digits, space, - and _, at most %d" % NAME_MAX))
	if mode == "patch" and (d.has("base") or d.has("base_model")):
		errors.append(_e("$.base", "a change can't swap the base; use new_room"))
	if d.has("base") and not (d["base"] is String):
		errors.append(_e("$.base", "a room id (room_state lists bases)"))
	if d.has("base_model"):
		_b64(d["base_model"], "$.base_model", LIMITS["model_bytes"], errors)
	if d.has("light"):
		_light(d["light"], errors)
	if d.has("sky"):
		_sky(d["sky"], mode, errors)
	if d.has("atmosphere"):
		if not (d["atmosphere"] is Dictionary):
			errors.append(_e("$.atmosphere", "{fog: {...}} or {}"))
		else:
			for k: Variant in d["atmosphere"]:
				if not ATMOSPHERE_OPTIONS.has(str(k)):
					errors.append(_e("$.atmosphere.%s" % k, "unknown (known: %s)"
							% ", ".join(ATMOSPHERE_OPTIONS.keys())))
				else:
					_options(ATMOSPHERE_OPTIONS[str(k)], str(k), d["atmosphere"][k], "$.atmosphere.%s" % k, errors)
	if d.has("seats"):
		_seats(d["seats"], errors)
	if d.has("default_seat") and not (d["default_seat"] is String or d["default_seat"] == null):
		errors.append(_e("$.default_seat", "a seat's name (or null: the room's own spot)"))
	if d.has("screen"):
		_screen(d["screen"], errors)
	if d.has("lights"):
		_lights(d["lights"], errors)
	var names := {}
	if d.has("parts"):
		if not (d["parts"] is Array):
			errors.append(_e("$.parts", "a list of parts"))
		else:
			var parts: Array = d["parts"]
			if parts.size() > LIMITS["parts"]:
				errors.append(_e("$.parts", "parts: at most %d" % LIMITS["parts"]))
			for i in parts.size():
				if parts[i] is Dictionary and not (parts[i] as Dictionary).has("type") \
						and (parts[i] as Dictionary).has("object"):
					_placement(parts[i], "$.parts[%d]" % i, mode, names, errors)
				elif mode == "saved" and version >= 3:
					errors.append(_e("$.parts[%d]" % i, "a kept room of schema 3 has placements only: {name, object, "
							+ "...}, no type"))
				else:
					_part(parts[i], "$.parts[%d]" % i, mode, names, errors)
	if d.has("recolour"):
		if not (d["recolour"] is Array):
			errors.append(_e("$.recolour", "a list of {match, material}"))
		else:
			var rs: Array = d["recolour"]
			if rs.size() > int(LIMITS["recolours"]):
				errors.append(_e("$.recolour", "recolours: %d, at most %d" % [rs.size(), LIMITS["recolours"]]))
			for i in rs.size():
				var p := "$.recolour[%d]" % i
				if not (rs[i] is Dictionary):
					errors.append(_e(p, "an object {match, material}"))
					continue
				var r: Dictionary = rs[i]
				for k: Variant in r:
					if not (str(k) in ["match", "material"]):
						errors.append(_e("%s.%s" % [p, k], "unknown key"))
				if not (r.get("match") is String) or str(r.get("match")).strip_edges() == "":
					errors.append(_e(p + ".match", "a part name or pattern (* and ?)"))
				elif str(r["match"]).contains("/") and split_match(str(r["match"])).is_empty():
					errors.append(_e(p + ".match", "\"<placed name>/<part name>\": one / with a pattern on each side "
							+ "(object_info lists a placed object's parts)"))
				if r.has("material") and r["material"] == null and mode != "patch":
					errors.append(_e(p + ".material", "null takes an entry out: only in a change to the room on show"))
				# A part-level entry changes what the part shows (its object's library material too): tint and tiling
				# without library_material are fine there.
				_material(r.get("material"), p + ".material", mode, errors, not split_match(str(r.get("match",
						""))).is_empty())
	if d.has("remove"):
		if mode != "patch":
			errors.append(_e("$.remove", "only in a change to the room on show"))
		elif not (d["remove"] is Array) or not (d["remove"] as Array).all(func(x: Variant) -> bool: return x is String):
			errors.append(_e("$.remove", "a list of part names"))
	return {"ok": errors.is_empty(), "errors": errors}


static func _e(path: String, error: String) -> Dictionary:
	return {"path": path, "error": error}


## A part-level match ("Shelf*/Board") as [object pattern, part pattern]; [] for a bare name or a malformed one.
static func split_match(match: String) -> Array:
	var bits := match.split("/")
	if bits.size() != 2 or bits[0].strip_edges() == "" or bits[1].strip_edges() == "":
		return []
	return [bits[0], bits[1]]


## A library id (an object's, a material's): lower-case letters, digits, - and _, at most ID_MAX.
static func id_ok(v: Variant) -> bool:
	if not (v is String) or (v as String).is_empty() or (v as String).length() > ID_MAX:
		return false
	for c in v as String:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c in "-_"):
			return false
	return true


## Where a document uses what schema 1 lacks: a part's "object", a "name/part" match, "library_material".
static func _schema2_paths(d: Dictionary) -> Array:
	var out: Array = []
	var parts: Array = d.get("parts", []) if d.get("parts") is Array else []
	for i in parts.size():
		if parts[i] is Dictionary:
			if (parts[i] as Dictionary).has("object"):
				out.append("$.parts[%d].object" % i)
			if parts[i].get("material") is Dictionary and (parts[i]["material"] as Dictionary).has("library_material"):
				out.append("$.parts[%d].material.library_material" % i)
	var rs: Array = d.get("recolour", []) if d.get("recolour") is Array else []
	for i in rs.size():
		if rs[i] is Dictionary:
			if str(rs[i].get("match", "")).contains("/"):
				out.append("$.recolour[%d].match" % i)
			if rs[i].get("material") is Dictionary and (rs[i]["material"] as Dictionary).has("library_material"):
				out.append("$.recolour[%d].material.library_material" % i)
	return out


## Where a document uses what schema 2 lacks: a part placed as an object (object without type).
static func _schema3_paths(d: Dictionary) -> Array:
	var out: Array = []
	var parts: Array = d.get("parts", []) if d.get("parts") is Array else []
	for i in parts.size():
		if parts[i] is Dictionary and (parts[i] as Dictionary).has("object") \
				and not (parts[i] as Dictionary).has("type"):
			out.append("$.parts[%d].object" % i)
	return out


static func _num(v: Variant) -> float:
	return float(v) if v is float or v is int else NAN


static func _name_ok(v: Variant) -> bool:
	if not (v is String):
		return false
	var s: String = v
	if s.strip_edges() == "" or s.length() > NAME_MAX:
		return false
	for c in s:
		if not (c.is_valid_identifier() or c.is_valid_int() or c in " -_"):
			return false
	return true


## seats: [{name, position: [x, y, z] (the floor point under the viewer), facing: [x, y, z] (optional; level)}].
static func _seats(v: Variant, errors: Array) -> void:
	if not (v is Array):
		errors.append(_e("$.seats", "a list of seats: [{name, position, facing}]"))
		return
	if (v as Array).size() > LIMITS["seats"]:
		errors.append(_e("$.seats", "seats: %d (at most %d)" % [(v as Array).size(), LIMITS["seats"]]))
	var seen := {}
	for i in (v as Array).size():
		var path := "$.seats[%d]" % i
		var st: Variant = v[i]
		if not (st is Dictionary):
			errors.append(_e(path, "{name, position, facing}"))
			continue
		for k: Variant in st:
			if not (str(k) in ["name", "position", "facing"]):
				errors.append(_e("%s.%s" % [path, k], "unknown key (name, position, facing)"))
		if not _name_ok(st.get("name")):
			errors.append(_e(path + ".name", "a name: letters, digits, space, - and _; up to 40"))
		elif seen.has(str(st["name"])):
			errors.append(_e(path + ".name", "a second seat called %s" % st["name"]))
		else:
			seen[str(st["name"])] = true
		if not _vec(st.get("position"), 3):
			errors.append(_e(path + ".position", "[x, y, z] metres: the floor point under the viewer"))
		elif absf(_num(st["position"][0])) > LIMITS["extent_m"] or absf(_num(st["position"][2])) > LIMITS["extent_m"]:
			errors.append(_e(path + ".position", "within %s m" % LIMITS["extent_m"]))
		if st.has("facing"):
			if not _vec(st["facing"], 3) or Vector2(_num(st["facing"][0]), _num(st["facing"][2])).length() < 0.01:
				errors.append(_e(path + ".facing", "[x, y, z]: a direction with some x or z (y is ignored: seats "
						+ "face level)"))


## screen: {center: [x, y, z], size: [w, h], facing: [x, y, z] (optional; level), curve: 0..1, home: bool}.
static func _screen(v: Variant, errors: Array) -> void:
	if v == null:
		return
	if not (v is Dictionary):
		errors.append(_e("$.screen", "{center, size, facing, curve, home} (or null: the base room's screen)"))
		return
	for k: Variant in v:
		if not (str(k) in ["center", "size", "facing", "curve", "home"]):
			errors.append(_e("$.screen.%s" % k, "unknown key (center, size, facing, curve, home)"))
	if not _vec(v.get("center"), 3):
		errors.append(_e("$.screen.center", "[x, y, z] metres, the room frame"))
	if not _vec(v.get("size"), 2):
		errors.append(_e("$.screen.size", "[width, height] metres"))
	elif not (_num(v["size"][0]) >= SCREEN_WIDTH[0] and _num(v["size"][0]) <= SCREEN_WIDTH[1]) \
			or not (_num(v["size"][1]) > 0.0 and _num(v["size"][1]) <= SCREEN_WIDTH[1]):
		errors.append(_e("$.screen.size", "width %s..%s m, height above 0" % SCREEN_WIDTH))
	if v.has("facing") and (not _vec(v["facing"], 3)
			or Vector2(_num(v["facing"][0]), _num(v["facing"][2])).length() < 0.01):
		errors.append(_e("$.screen.facing", "[x, y, z]: the way the picture faces, with some x or z"))
	if v.has("curve") and not (_num(v["curve"]) >= 0.0 and _num(v["curve"]) <= 1.0):
		errors.append(_e("$.screen.curve", "0..1 (0 flat, 1 wrapped evenly round the seat)"))
	if v.has("home") and not (v["home"] is bool):
		errors.append(_e("$.screen.home", "true or false"))


## A level direction from [x, y, z] (y dropped), or `fallback`.
static func level_dir(v: Variant, fallback: Vector3) -> Vector3:
	if not _vec(v, 3):
		return fallback
	var d := Vector3(_num(v[0]), 0.0, _num(v[2]))
	return d.normalized() if d.length() > 0.01 else fallback


static func vec3(v: Variant) -> Vector3:
	return Vector3(_num(v[0]), _num(v[1]), _num(v[2]))


## The screen's facing: given, else towards the room's own spot (the origin), else +Z.
static func screen_facing(screen: Dictionary) -> Vector3:
	var c := vec3(screen["center"])
	return level_dir(screen.get("facing"), Vector3(-c.x, 0.0, -c.z).normalized() if Vector2(c.x, c.z).length() > 0.05
			else Vector3.BACK)


## A seat's facing: given, else towards the screen's centre (screen may be {}), else -Z.
static func seat_facing(seat: Dictionary, screen: Dictionary) -> Vector3:
	var fallback := Vector3.FORWARD
	if screen.has("center"):
		var to := vec3(screen["center"]) - vec3(seat["position"])
		to.y = 0.0
		if to.length() > 0.05:
			fallback = to.normalized()
	return level_dir(seat.get("facing"), fallback)


## The seats and the screen against each other, in a whole (merged) room document: the default seat is one of the
## seats, and from every seat (or the room's own spot when there are none) the screen is in front, far enough, and
## neither too small nor too large to watch. [{path, error}]
static func layout_errors(doc: Dictionary) -> Array:
	var errors: Array = []
	var seats: Array = doc.get("seats", []) if doc.get("seats") is Array else []
	var names: Array = seats.map(func(s: Variant) -> String: return str(s.get("name", "")) if s is Dictionary else "")
	var dflt: Variant = doc.get("default_seat")
	if dflt != null and dflt is String and not (dflt in names):
		errors.append(_e("$.default_seat", "no seat called %s (the seats: %s)" % [dflt, ", ".join(names)]))
	var screen: Variant = doc.get("screen")
	if not (screen is Dictionary) or not _vec(screen.get("center"), 3) or not _vec(screen.get("size"), 2):
		return errors
	var c := vec3(screen["center"])
	var size := Vector2(_num(screen["size"][0]), _num(screen["size"][1]))
	var normal := screen_facing(screen)
	var from: Array = []
	for i in seats.size():
		if seats[i] is Dictionary and _vec(seats[i].get("position"), 3):
			from.append(["$.seats[%d]" % i, "seat %s" % seats[i].get("name", i), vec3(seats[i]["position"])])
	if from.is_empty():
		from.append(["$.screen", "the room's own spot", Vector3.ZERO])
	for f: Array in from:
		var eye: Vector3 = f[2] + Vector3(0, NOMINAL_EYE_HEIGHT, 0)
		var to := c - eye
		var d := to.length()
		if (eye - c).dot(normal) <= 0.0:
			errors.append(_e(f[0], "%s is behind the screen (the picture faces %s): put it on the side the screen "
					% [f[1], _r(normal)] + "faces, or turn the screen"))
			continue
		var off := rad_to_deg((eye - c).normalized().angle_to(normal))
		if off > SCREEN_MAX_OFF_AXIS_DEG:
			errors.append(_e(f[0], "%s is %.0f degrees off the screen's axis (from its eyes, 1.2 m up, to the "
					% [f[1], off] + "screen's centre, against the way the picture faces); at most %.0f: the picture "
					% SCREEN_MAX_OFF_AXIS_DEG + "would look squashed. Move the seat towards the middle or turn the "
					+ "screen"))
			continue
		if d < SCREEN_MIN_DISTANCE:
			errors.append(_e(f[0], "%s is %.2f m from the screen; at least %.1f m" % [f[1], d, SCREEN_MIN_DISTANCE]))
			continue
		var wide := rad_to_deg(2.0 * atan(size.x * 0.5 / d))
		var tall := rad_to_deg(2.0 * atan(size.y * 0.5 / d))
		if wide < SCREEN_MIN_DEG:
			errors.append(_e("$.screen.size", "from %s the screen is %.0f degrees wide (%.1f m at %.1f m): too small "
					% [f[1], wide, size.x, d] + "to watch; at least %.0f degrees (%.1f m wide there)"
					% [SCREEN_MIN_DEG, 2.0 * d * tan(deg_to_rad(SCREEN_MIN_DEG) * 0.5)]))
		elif wide > SCREEN_MAX_DEG or tall > SCREEN_MAX_TALL_DEG:
			errors.append(_e("$.screen.size", "from %s the screen is %.0f x %.0f degrees (%.1f m at %.1f m): too large "
					% [f[1], wide, tall, size.x, d] + "to take in; at most %.0f degrees wide (%.1f m there) "
					% [SCREEN_MAX_DEG, 2.0 * d * tan(deg_to_rad(SCREEN_MAX_DEG) * 0.5)]
					+ "and %.0f tall" % SCREEN_MAX_TALL_DEG))
	return errors


static func _r(v: Vector3) -> String:
	return "[%s, %s, %s]" % [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _vec(v: Variant, n: int) -> bool:
	if not (v is Array) or (v as Array).size() != n:
		return false
	for x: Variant in v:
		if not (x is float or x is int) or not is_finite(float(x)):
			return false
	return true


static func is_color(v: Variant) -> bool:
	if v is String:
		return Color.html_is_valid(v)
	if v is Array and (v as Array).size() in [3, 4]:
		for x: Variant in v:
			if not (x is float or x is int) or float(x) < 0.0 or float(x) > 1.0:
				return false
		return true
	return false


static func to_color(v: Variant, fallback := Color.WHITE) -> Color:
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if (v as Array).size() > 3 else 1.0)
	return fallback


static func _b64(v: Variant, path: String, max_bytes: int, errors: Array) -> void:
	if not (v is String) or (v as String).is_empty():
		errors.append(_e(path, "base64 data"))
		return
	# base64 is 4 characters per 3 bytes.
	if (v as String).length() / 4 * 3 > max_bytes:
		errors.append(_e(path, "at most %d bytes (%d MB)" % [max_bytes, max_bytes / (1024 * 1024)]))


static func _file(v: Variant, path: String, errors: Array) -> void:
	if not (v is String) or (v as String).is_empty() or (v as String).contains("/") or (v as String).contains("\\") \
			or (v as String).contains(".."):
		errors.append(_e(path, "a file name in the room's own folder"))


static func _light(v: Variant, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e("$.light", "{ambient, screen_glow, key, sky, screen}"))
		return
	for k: Variant in v:
		if str(k) in ["key", "sky", "screen"]:
			if v[k] != null:
				_options(LIGHT_OPTIONS[str(k)], str(k), v[k], "$.light.%s" % k, errors)
			continue
		if str(k) == "contact_shadows":
			if not (v[k] is bool):
				errors.append(_e("$.light.contact_shadows", "true or false"))
			continue
		var x := _num(v[k])
		if str(k) == "ambient":
			if not (x >= 0.0 and x <= 1.0):
				errors.append(_e("$.light.ambient", "0..1"))
		elif str(k) == "screen_glow":
			if not (x >= 0.0 and x <= 2.0):
				errors.append(_e("$.light.screen_glow", "0..2"))
		else:
			errors.append(_e("$.light.%s" % k, "unknown key (ambient, screen_glow, key, sky, screen, "
					+ "contact_shadows)"))


## lights: [{name, type, position or attach (+ offset), color, energy, range, direction, angle, flicker}].
static func _lights(v: Variant, errors: Array) -> void:
	if not (v is Array):
		errors.append(_e("$.lights", "a list of lights: [{type, position, color, energy, range}]"))
		return
	if (v as Array).size() > LIMITS["lights"]:
		errors.append(_e("$.lights", "lights: %d (at most %d: each one costs the headset's frame; give a part an "
				% [(v as Array).size(), LIMITS["lights"]] + "emission for more glowing things)"))
	for i in (v as Array).size():
		var path := "$.lights[%d]" % i
		_options(POINT_LIGHT_OPTIONS, "a light", v[i], path, errors)
		if v[i] is Dictionary and not (v[i] as Dictionary).has("position") and not (v[i] as Dictionary).has("attach"):
			errors.append(_e(path, "a position, or attach: a part's name"))


## What lighting costs: the key light, its shadows, the point lights (by how far they reach) and the contact shadows.
static func lighting_cost(doc: Dictionary) -> float:
	var c := 0.0
	var light: Dictionary = doc.get("light", {}) if doc.get("light") is Dictionary else {}
	if light.get("key") is Dictionary:
		c += COSTS["key_light"]
		if bool((light["key"] as Dictionary).get("shadows", LIGHT_OPTIONS["key"]["shadows"]["default"])):
			c += COSTS["key_shadows"]
	if light.get("screen") is Dictionary:
		c += COSTS["screen_light"]
	if bool(light.get("contact_shadows", true)):
		for p: Variant in doc.get("parts", []) if doc.get("parts") is Array else []:
			if p is Dictionary and stands_on_floor(p):
				c += COSTS["contact_shadow"]
	for l: Variant in doc.get("lights", []) if doc.get("lights") is Array else []:
		if l is Dictionary:
			var r := clampf(_num(l.get("range", POINT_LIGHT_OPTIONS["range"]["default"])) / POINT_LIGHT_COST_RANGE,
					0.25, 2.0)
			c += COSTS["point_light"] * r
	return c


## A solid part that may stand on the floor (a contact shadow under it): a box, sphere, cylinder or model, not
## see-through, no widget, its bottom (as far as the document says) within 0.3 m of the floor.
static func stands_on_floor(p: Dictionary) -> bool:
	p = build_form(p)
	if not (str(p.get("type", "")) in ["box", "sphere", "cylinder", "model"]) or str(p.get("widget", "")) != "":
		return false
	var m: Dictionary = p.get("material", {}) if p.get("material") is Dictionary else {}
	if str(m.get("alpha", "")) == "blend" or (m.has("color") and is_color(m["color"]) and to_color(m["color"]).a < 0.999
			and str(m.get("alpha", "")) != "opaque"):
		return false
	if str(p["type"]) == "model":
		# A placement of a wall or ceiling object (a poster kept from a plane) hangs; anything else may stand.
		if p.has("object"):
			var obj: Dictionary = (load("res://scripts/assistant/object_library.gd") as GDScript).call("get_object",
					str(p["object"]))
			return not (str(obj.get("mount", "")) in ["wall", "ceiling"])
		return true
	var size: Array = p.get("size", [1.0]) if p.get("size") is Array else [1.0]
	var h := _num(size[1]) if str(p["type"]) in ["box", "cylinder"] and size.size() > 1 else _num(size[0])
	var s: Variant = p.get("scale", 1.0)
	var k := _num(s) if (s is float or s is int) else (_num(s[1]) if s is Array and s.size() == 3 else 1.0)
	var y := _num(p["position"][1]) if _vec(p.get("position"), 3) else 0.0
	return y - h * k * 0.5 <= 0.3


## A room is lit (real lights, room_lit.gdshader) when it has a key light, a sky fill, a screen light or lights.
static func is_lit(doc: Dictionary) -> bool:
	var light: Dictionary = doc.get("light", {}) if doc.get("light") is Dictionary else {}
	return light.get("key") is Dictionary or light.get("sky") is Dictionary or light.get("screen") is Dictionary \
			or (doc.get("lights") is Array and not (doc["lights"] as Array).is_empty())


static func _sky(v: Variant, mode: String, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e("$.sky", "{color} or {image} or {}, and stars, clouds"))
		return
	var s: Dictionary = v
	if s.has("color") and (s.has("image") or s.has("image_file")):
		errors.append(_e("$.sky", "one of color, image"))
	for k: Variant in s:
		match str(k):
			"color":
				if not is_color(s[k]):
					errors.append(_e("$.sky.color", "#rrggbb or [r, g, b] 0..1"))
			"image":
				_b64(s[k], "$.sky.image", LIMITS["image_bytes"], errors)
			"image_file":
				if mode == "saved":
					_file(s[k], "$.sky.image_file", errors)
				else:
					errors.append(_e("$.sky.image_file", "unknown key"))
			"stars", "clouds":
				_options(SKY_OPTIONS[str(k)], str(k), s[k], "$.sky.%s" % k, errors)
			"effect":
				# A sky from the effect library (effects surface=sky), drawn on the sky sphere.
				var opts: Dictionary = (s[k] as Dictionary).duplicate() if s[k] is Dictionary else {}
				var fx_name := str(opts.get("name", ""))
				opts.erase("name")
				if EffectLibrary.has(fx_name) and str(EffectLibrary.entry(fx_name)["surfaces"]) != "sky":
					errors.append(_e("$.sky.effect.name", "%s is for parts (material.effect); the sky's: %s"
							% [fx_name, ", ".join(SKY_EFFECTS.keys())]))
				elif not EffectLibrary.has(fx_name):
					errors.append(_e("$.sky.effect.name", "{name, ...options}: name one of %s"
							% ", ".join(SKY_EFFECTS.keys())))
				else:
					errors.append_array(EffectLibrary.validate(fx_name, opts, "$.sky.effect").map(
							func(x: Dictionary) -> Dictionary: return _e(x["path"], x["error"])))
			_:
				errors.append(_e("$.sky.%s" % k, "unknown key (color, image, stars, clouds, effect)"))


static func _material(v: Variant, path: String, mode: String, errors: Array, layered := false) -> void:
	if v == null:
		return
	if not (v is Dictionary):
		errors.append(_e(path, "{color, emission, emission_strength, texture, self_lit, alpha, uv, effect, "
				+ "roughness, library_material, tint, tiling, triplanar}"))
		return
	var m: Dictionary = v
	for k: Variant in m:
		var p := "%s.%s" % [path, k]
		match str(k):
			"color", "emission":
				if not is_color(m[k]):
					errors.append(_e(p, "#rrggbb or [r, g, b] 0..1"))
			"emission_strength":
				var x := _num(m[k])
				if not (x >= 0.0 and x <= 10.0):
					errors.append(_e(p, "0..10"))
			"self_lit":
				if not (m[k] is bool):
					errors.append(_e(p, "true or false"))
			"uv":
				if not (m[k] is String and m[k] in UV_MODES):
					errors.append(_e(p, "one of %s" % ", ".join(UV_MODES)))
			"alpha":
				if not (m[k] is String and m[k] in ALPHA_MODES):
					errors.append(_e(p, "one of %s" % ", ".join(ALPHA_MODES)))
			"effect":
				# The effect library checks it (docs/effects.md), in this schema's words.
				var fx: Variant = m[k]
				var opts: Dictionary = (fx as Dictionary).duplicate() if fx is Dictionary else {}
				var fx_name := str(opts.get("name", ""))
				opts.erase("name")
				if EffectLibrary.has(fx_name) and str(EffectLibrary.entry(fx_name)["surfaces"]) == "sky":
					errors.append(_e(p + ".name", "%s is for the sky (sky.effect)" % fx_name))
				else:
					errors.append_array(EffectLibrary.validate(fx_name, opts, p).map(
							func(x: Dictionary) -> Dictionary: return _e(x["path"], x["error"])))
					if m.has("library_material") and EffectLibrary.has(fx_name) \
							and not bool(EffectLibrary.entry(fx_name)["layers"]):
						errors.append(_e(p + ".name", "%s draws its own surface: it does not layer over a material "
								% fx_name + "(effects lists those that do: layers true)"))
			"roughness":
				var x := _num(m[k])
				if not (x >= 0.0 and x <= 1.0):
					errors.append(_e(p, "0..1"))
			"texture":
				_b64(m[k], p, LIMITS["image_bytes"], errors)
			"texture_file":
				if mode == "saved":
					_file(m[k], p, errors)
				else:
					errors.append(_e(p, "unknown key"))
			"library_material":
				if not id_ok(m[k]):
					errors.append(_e(p, "a library material's id (the materials command lists them): lower-case "
							+ "letters, digits, - and _"))
				elif m.has("texture") or m.has("texture_file"):
					errors.append(_e(p, "one of library_material, texture"))
			"tint":
				if not is_color(m[k]):
					errors.append(_e(p, "#rrggbb or [r, g, b] 0..1"))
			"tiling":
				var x := _num(m[k])
				if not (x >= TILING_MIN and x <= TILING_MAX):
					errors.append(_e(p, "metres per repeat, %s..%s" % [TILING_MIN, TILING_MAX]))
			"triplanar":
				if not (m[k] is bool):
					errors.append(_e(p, "true or false"))
			"turn":
				var x := _num(m[k])
				if not (x >= -360.0 and x <= 360.0):
					errors.append(_e(p, "degrees the pattern is turned, -360..360"))
			_:
				errors.append(_e(p, "unknown key (color, emission, emission_strength, texture, self_lit, alpha, uv, "
						+ "effect, roughness, library_material, tint, tiling, triplanar, turn)"))
	for k in LIBRARY_OPTIONS:
		if m.has(k) and not m.has("library_material") and not layered:
			errors.append(_e("%s.%s" % [path, k], "only with library_material"))


static func _part(v: Variant, path: String, mode: String, names: Dictionary, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e(path, "a part object"))
		return
	var p: Dictionary = v
	var known := ["name", "type", "size", "model", "text", "text_options", "position", "rotation", "scale",
			"material", "widget", "widget_options", "motion", "particles", "object"]
	if mode == "saved":
		known.append("model_file")
	if p.has("object") and (str(p.get("type", "")) != "model" or not id_ok(p["object"])):
		errors.append(_e(path + ".object", "type model only: the object library's id it was placed from "
				+ "(object_library lists them)"))
	for k: Variant in p:
		if not (str(k) in known):
			errors.append(_e("%s.%s" % [path, k], "unknown key (known: %s)" % ", ".join(known)))
	if not _name_ok(p.get("name")):
		errors.append(_e(path + ".name", "required: letters, digits, space, - and _, at most %d" % NAME_MAX))
	elif names.has(p["name"]):
		errors.append(_e(path + ".name", "another part has this name"))
	else:
		names[p["name"]] = true
	var type := str(p.get("type", ""))
	if not (type in PART_TYPES):
		errors.append(_e(path + ".type", "one of %s" % ", ".join(PART_TYPES)))
	var sizes := {"box": 3, "sphere": 1, "cylinder": 2, "plane": 2, "particles": 3}
	if sizes.has(type):
		if not _vec(p.get("size"), sizes[type]):
			errors.append(_e(path + ".size", "%d numbers (%s)" % [sizes[type], {"box": "width, height, depth",
					"sphere": "diameter", "cylinder": "diameter, height", "plane": "width, depth",
					"particles": "the area's width, height, depth"}[type]]))
		else:
			for x: Variant in p["size"]:
				if float(x) <= 0.0 or float(x) > LIMITS["extent_m"]:
					errors.append(_e(path + ".size", "each between 0 and %d m" % int(LIMITS["extent_m"])))
					break
	if type == "model":
		if p.has("model"):
			_b64(p["model"], path + ".model", LIMITS["model_bytes"], errors)
		elif mode == "saved" and p.has("model_file"):
			_file(p["model_file"], path + ".model_file", errors)
		else:
			errors.append(_e(path + ".model", "a model part needs model: the .glb file, base64"))
	elif p.has("model"):
		errors.append(_e(path + ".model", "only for type model"))
	if type == "text":
		var t: Variant = p.get("text")
		if not (t is String) or (t as String).strip_edges() == "":
			errors.append(_e(path + ".text", "a text part needs text: the words to show"))
		elif (t as String).length() > int(LIMITS["text_chars"]):
			errors.append(_e(path + ".text", "text_chars: %d, at most %d" % [(t as String).length(),
					LIMITS["text_chars"]]))
		if p.has("size") and not (_vec(p["size"], 1) and float(p["size"][0]) >= TEXT_LINE_MIN
				and float(p["size"][0]) <= TEXT_LINE_MAX):
			errors.append(_e(path + ".size", "[line height] in metres, %s..%s" % [TEXT_LINE_MIN, TEXT_LINE_MAX]))
		if p.has("text_options"):
			_options(TEXT_OPTIONS, "text", p["text_options"], path + ".text_options", errors)
		if p.has("material"):
			errors.append(_e(path + ".material", "a text part takes text_options (color, background), not material"))
		if p.has("widget"):
			errors.append(_e(path + ".widget", "a text part can't carry a widget; put the widget on another part"))
	else:
		for k in ["text", "text_options"]:
			if p.has(k):
				errors.append(_e("%s.%s" % [path, k], "only for type text"))
	if type == "particles":
		if not p.has("particles"):
			errors.append(_e(path + ".particles", "a particles part needs particles: {preset, rate, color, size, "
					+ "speed}"))
		else:
			# Loaded, not preloaded: room_particles.gd preloads this file.
			(load(PARTICLES_SCRIPT) as GDScript).call("validate", p["particles"], path + ".particles", errors)
		if _vec(p.get("size"), 3) and (p["size"] as Array).any(func(x: Variant) -> bool: return float(x) > 30.0):
			errors.append(_e(path + ".size", "a particles area is at most 30 m a side"))
		for k in ["material", "widget"]:
			if p.has(k):
				errors.append(_e("%s.%s" % [path, k], "a particles part takes its look from particles (color, size)"))
	elif p.has("particles"):
		errors.append(_e(path + ".particles", "only for type particles"))
	var mat: Variant = p.get("material")
	if mat is Dictionary and str((mat as Dictionary).get("uv", "atlas")) != "atlas" and type != "box":
		errors.append(_e(path + ".material.uv", "each_face and front_only are for boxes; a %s maps the picture one "
				% type + "way (the guide says how)"))
	if p.has("position"):
		if not _vec(p["position"], 3):
			errors.append(_e(path + ".position", "[x, y, z] in metres"))
		else:
			for x: Variant in p["position"]:
				if absf(float(x)) > float(LIMITS["extent_m"]):
					errors.append(_e(path + ".position", "within %d m of the viewer" % int(LIMITS["extent_m"])))
					break
	if p.has("rotation") and not _vec(p["rotation"], 3):
		errors.append(_e(path + ".rotation", "[x, y, z] in degrees"))
	if p.has("scale"):
		var s: Variant = p["scale"]
		var ok: bool = (s is float or s is int) and float(s) > 0.0 and float(s) <= 100.0
		if not ok and _vec(s, 3):
			ok = true
			for x: Variant in s:
				if float(x) <= 0.0 or float(x) > 100.0:
					ok = false
		if not ok:
			errors.append(_e(path + ".scale", "a number or [x, y, z], each above 0 and at most 100"))
	_material(p.get("material"), path + ".material", mode, errors)
	if p.has("motion"):
		# Loaded, not preloaded: room_motion.gd preloads this file.
		(load("res://scripts/assistant/room_motion.gd") as GDScript).call("validate", p["motion"], path + ".motion",
				errors)
	if p.has("widget"):
		var w := str(p["widget"])
		if not WIDGETS.has(w):
			errors.append(_e(path + ".widget", "unknown widget %s; supported: %s" % [w, ", ".join(WIDGETS.keys())]))
		else:
			_widget_options(w, p.get("widget_options", {}), path + ".widget_options", errors)
	elif p.has("widget_options"):
		errors.append(_e(path + ".widget_options", "only with a widget"))


## A placement (schema 3): an object from the library put in the room. What it is made of comes from the library
## (room_editor.gd refuses an id the library doesn't have); its material is an override. The checks a shape's part has
## that still apply (a text's words, a particles area, the widget, motion, position) are made on its build form.
static func _placement(p: Dictionary, path: String, mode: String, names: Dictionary, errors: Array) -> void:
	for k: Variant in p:
		if not (str(k) in PLACEMENT_KEYS):
			errors.append(_e("%s.%s" % [path, k], "unknown key (a placement: %s; a shape is sent with type)"
					% ", ".join(PLACEMENT_KEYS)))
	if not id_ok(p.get("object")):
		errors.append(_e(path + ".object", "an object library id (object_library lists them): lower-case letters, "
				+ "digits, - and _"))
		return
	var kind := kind_of(p)
	var max_scale := float(LIMITS["extent_m"]) if kind in PRIMITIVES else 100.0
	if kind == "particles":
		max_scale = 30.0
	if p.has("scale"):
		var s: Variant = p["scale"]
		var ok: bool = (s is float or s is int) and float(s) > 0.0 and float(s) <= max_scale
		if not ok and _vec(s, 3):
			ok = (s as Array).all(func(x: Variant) -> bool: return float(x) > 0.0 and float(x) <= max_scale)
		if not ok:
			errors.append(_e(path + ".scale", "a number or [x, y, z], each above 0 and at most %s%s" % [max_scale,
					" (a primitive's scale is its size in metres)" if kind in PRIMITIVES else ""]))
	var m: Variant = p.get("material")
	if m is Dictionary:
		# A picture sent on a placement (recolour with texture) becomes a picture object when the change is applied;
		# a kept room's placements have none.
		var refused: Array = ["texture_file"]
		if mode == "saved":
			refused.append_array(["texture", "uv"])
		for k: String in refused:
			if (m as Dictionary).has(k):
				errors.append(_e("%s.material.%s" % [path, k], "a placement's material has no picture of its own: "
						+ "the object carries it (a part sent with material.texture becomes a picture object)"))
	_physics_keys(p, kind, path, errors)
	# The rest is checked as the part it is built as (its size from its scale).
	var f := build_form(p)
	f.erase("object")
	for k: String in PHYSICS_KEYS:
		f.erase(k)
	if kind == "text":
		f.erase("size")
	var sub: Array = []
	_part(f, path, "new" if mode == "saved" else mode, names, sub)
	for e: Dictionary in sub:
		# Its size comes from its scale (checked above); a model's data from the library.
		if str(e["path"]).ends_with(".size") or str(e["path"]).ends_with(".model") or str(e["path"]).ends_with(".type"):
			continue
		errors.append(e)


## Object physics' keys on a placement: home {position, rotation, mounted?} (where it was placed, once moved),
## mounted (false: a wall object pulled off its wall), attach and offset (a text or particles area following another
## placement).
static func _physics_keys(p: Dictionary, kind: String, path: String, errors: Array) -> void:
	if p.has("home"):
		var h: Variant = p["home"]
		var placed: Dictionary = h if h is Dictionary else {}
		if placed.is_empty() or not _vec(placed.get("position"), 3) or not _vec(placed.get("rotation"), 3):
			errors.append(_e(path + ".home", "where it was placed: {position: [x, y, z], rotation: [x, y, z]}"))
		else:
			for k: Variant in h:
				if not (str(k) in ["position", "rotation", "mounted"]):
					errors.append(_e("%s.home.%s" % [path, k], "unknown key (position, rotation, mounted)"))
			if (h as Dictionary).has("mounted") and not ((h as Dictionary)["mounted"] is bool):
				errors.append(_e(path + ".home.mounted", "true or false"))
	if p.has("mounted") and not (p["mounted"] is bool):
		errors.append(_e(path + ".mounted", "true or false (false: a wall object pulled off its wall)"))
	if p.has("attach"):
		if not (kind in GENERATORS):
			errors.append(_e(path + ".attach", "a text or particles area only: the placement it follows"))
		elif not _name_ok(p["attach"]) or str(p["attach"]) == str(p.get("name", "")):
			errors.append(_e(path + ".attach", "another placement's name (room_state's objects)"))
	if p.has("offset"):
		if not p.has("attach"):
			errors.append(_e(path + ".offset", "only with attach"))
		elif not _vec(p["offset"], 3) or (p["offset"] as Array).any(func(x: Variant) -> bool:
				return absf(float(x)) > float(LIMITS["extent_m"])):
			errors.append(_e(path + ".offset", "[x, y, z] metres in the attached object's frame"))


## An attached part's place in its object's frame (object physics; assistant_room.gd places it there, and
## scripts/play/object_physics.gd moves it with the object): its offset, and its rotation (degrees) relative to it.
static func attach_offset(p: Dictionary) -> Transform3D:
	var rot: Array = p.get("rotation", [0, 0, 0]) if _vec(p.get("rotation"), 3) else [0, 0, 0]
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])),
			deg_to_rad(float(rot[2])))), vec3(p.get("offset", [0, 0, 0])) if _vec(p.get("offset"), 3) else Vector3.ZERO)


## What a part is built as: its type ("box", "text", "model", ...), from its object when it is a placement.
static func kind_of(p: Dictionary) -> String:
	if p.has("type"):
		return str(p["type"])
	var id := str(p.get("object", ""))
	return id if id in PRIMITIVES or id in GENERATORS else "model"


## A part as the room is built from it (assistant_room.gd _part): a shape's part as it is; a placement with the type
## its object makes, a primitive's scale as its size (a node scale only for what the size can't say: an ellipsoid, an
## oval cylinder), a text's scale as its line height, a particles area's as its size. Keeps "object".
static func build_form(p: Dictionary) -> Dictionary:
	if p.has("type") or not p.has("object"):
		return p
	var f := p.duplicate()
	var kind := kind_of(p)
	f["type"] = kind
	var s: Variant = p.get("scale", 1.0)
	var v := Vector3.ONE * float(s) if (s is float or s is int) else (Vector3(float(s[0]), float(s[1]), float(s[2]))
			if _vec(s, 3) else Vector3.ONE)
	match kind:
		"box":
			f["size"] = [v.x, v.y, v.z]
			f.erase("scale")
		"sphere":
			f["size"] = [v.x]
			_rest_scale(f, Vector3(1.0, v.y / v.x, v.z / v.x))
		"cylinder":
			f["size"] = [v.x, v.y]
			_rest_scale(f, Vector3(1.0, 1.0, v.z / v.x))
		"plane":
			f["size"] = [v.x, v.z]
			f.erase("scale")
		"text":
			if s is float or s is int:
				f["size"] = [TEXT_OBJECT_LINE * float(s)]
				f.erase("scale")
			else:
				f["size"] = [TEXT_OBJECT_LINE]
		"particles":
			f["size"] = [v.x, v.y, v.z]
			f.erase("scale")
	return f


static func _rest_scale(f: Dictionary, k: Vector3) -> void:
	if k.is_equal_approx(Vector3.ONE):
		f.erase("scale")
	else:
		f["scale"] = [k.x, k.y, k.z]


## A shape's part (type box, sphere, cylinder, plane, text or particles) as a placement's object and scale, the reverse
## of build_form(): {object, scale} (a number when it is the same on every axis). {} for a model.
static func placement_scale(p: Dictionary) -> Dictionary:
	var kind := str(p.get("type", ""))
	var s: Variant = p.get("scale", 1.0)
	var k := Vector3.ONE * float(s) if (s is float or s is int) else (Vector3(float(s[0]), float(s[1]), float(s[2]))
			if _vec(s, 3) else Vector3.ONE)
	var size: Array = p.get("size", []) if p.get("size") is Array else []
	var v := Vector3.ONE
	match kind:
		"box", "particles":
			v = Vector3(float(size[0]), float(size[1]), float(size[2])) if size.size() == 3 else Vector3.ONE
		"sphere":
			v = Vector3.ONE * (float(size[0]) if size.size() >= 1 else 1.0)
		"cylinder":
			var d := float(size[0]) if size.size() >= 1 else 1.0
			v = Vector3(d, float(size[1]) if size.size() >= 2 else 1.0, d)
		"plane":
			v = Vector3(float(size[0]) if size.size() >= 1 else 1.0, 1.0, float(size[1]) if size.size() >= 2 else 1.0)
		"text":
			v = Vector3.ONE * (float(size[0]) if size.size() >= 1 else TEXT_LINE_DEFAULT) / TEXT_OBJECT_LINE
		_:
			return {}
	v *= k
	if kind == "plane":
		v.y = k.y
	var out: Variant = [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
	if is_equal_approx(v.x, v.y) and is_equal_approx(v.x, v.z):
		out = snappedf(v.x, 0.0001)
	return {"object": kind, "scale": out}


static func _widget_options(w: String, v: Variant, path: String, errors: Array) -> void:
	_options(WIDGETS[w]["options"], w, v, path, errors)


## Options against a spec ({name: {type, default, values | min/max}}): each problem with its path.
static func _options(spec: Dictionary, w: String, v: Variant, path: String, errors: Array) -> void:
	if not (v is Dictionary):
		errors.append(_e(path, "an object"))
		return
	for k: Variant in v:
		var p := "%s.%s" % [path, k]
		if not spec.has(str(k)):
			errors.append(_e(p, "unknown option for %s (known: %s)" % [w, ", ".join(spec.keys())]))
			continue
		var o: Dictionary = spec[str(k)]
		var x: Variant = v[k]
		match str(o["type"]):
			"enum":
				if not (x is String and x in o["values"]):
					errors.append(_e(p, "one of %s" % ", ".join(o["values"])))
			"bool":
				if not (x is bool):
					errors.append(_e(p, "true or false"))
			"color":
				if not is_color(x):
					errors.append(_e(p, "#rrggbb or [r, g, b] 0..1"))
			"vec3":
				if not _vec(x, 3):
					errors.append(_e(p, "[x, y, z]"))
			"string":
				if not (x is String and (x as String).length() <= 40):
					errors.append(_e(p, "a name"))
			"flicker":
				_options(FLICKER_OPTIONS, "flicker", x, p, errors)
			"float":
				var f := _num(x)
				if not (f >= float(o["min"]) and f <= float(o["max"])):
					var why := ""
					if str(k) == "rate" and f > MAX_HZ:
						why = " (the photosensitivity ceiling: brightness may change at most %d times a second)" \
							% int(MAX_HZ)
					elif float(o["max"]) == MAX_SWING and f > MAX_SWING:
						why = " (the photosensitivity ceiling: no larger brightness swings)"
					errors.append(_e(p, "%s..%s%s" % [o["min"], o["max"], why]))


## What the room's own options cost (sky, atmosphere; parts are counted with part_cost).
static func room_cost(doc: Dictionary) -> float:
	var c := lighting_cost(doc)
	var sky: Variant = doc.get("sky")
	if sky is Dictionary:
		if (sky as Dictionary).has("stars"):
			c += COSTS["sky_stars"]
		if (sky as Dictionary).has("clouds"):
			c += COSTS["sky_clouds"]
		if (sky as Dictionary).get("effect") is Dictionary:
			c += EffectLibrary.cost_units(str(sky["effect"].get("name", ""))) * COSTS["effect"]
	var atmosphere: Variant = doc.get("atmosphere")
	if atmosphere is Dictionary and (atmosphere as Dictionary).has("fog"):
		c += COSTS["fog_layer"] * FOG_LAYERS
	return c


## An option set with its defaults filled in (SKY_OPTIONS["stars"], ...).
static func with_defaults(spec: Dictionary, given: Variant) -> Dictionary:
	var out := {}
	for k: String in spec:
		out[k] = (given as Dictionary).get(k, spec[k]["default"]) if given is Dictionary else spec[k]["default"]
	return out


## What a part costs (COSTS); model_triangles and model_parts: the model's, once read. picture: the model is a picture
## object kept from a shape (room_keep.gd): one mesh, priced as the shape it was.
static func part_cost(p: Dictionary, model_triangles := 0, model_parts := 1, picture := false) -> float:
	p = build_form(p)
	var c: float = COSTS["part"]
	match str(p.get("type", "")):
		"model":
			if not picture:
				c = COSTS["model"] + COSTS["model_per_10k_triangles"] * model_triangles / 10000.0 \
						+ COSTS["model_part"] * maxi(model_parts - 1, 0)
		"text":
			c = COSTS["text"]
		"particles":
			var n := int((load(PARTICLES_SCRIPT) as GDScript).call("amount", p))
			c = COSTS["particles_emitter"] + COSTS["particles_per_100"] * n / 100.0
	if p.has("motion"):
		c += COSTS["motion"]
	if p.has("widget") and str(p["widget"]) != "screen_glow":
		c += COSTS["widget"]
	if str(p.get("widget", "")) == "screen_glow" and str(p.get("widget_options", {}).get("react", "none")) != "none":
		c += COSTS["glow_react"]
	var m: Variant = p.get("material")
	if m is Dictionary:
		var a := str((m as Dictionary).get("alpha", ""))
		var col: Variant = (m as Dictionary).get("color")
		var fx: Variant = (m as Dictionary).get("effect")
		var fx_name := str(fx.get("name", "")) if fx is Dictionary else ""
		# The effect's units (its measured tier, a second pass, see-through) replace the fixed costs; they come out
		# the same for the first eight (glass and hologram 2, toon_outline 2, the rest 1).
		var transparent_fx := fx_name != "" and str(EffectLibrary.entry(fx_name).get("blend", "")) in ["alpha", "add"]
		if not transparent_fx and (a == "blend" or (a == "" and col != null and to_color(col).a < 0.999)):
			c += COSTS["blend"]
		if fx_name != "":
			c += EffectLibrary.cost_units(fx_name) * COSTS["effect"]
		if (m as Dictionary).has("library_material"):
			c += COSTS["library_material"]
			if bool((m as Dictionary).get("triplanar", false)):
				c += COSTS["library_triplanar"]
	return c


## A text part's options with the defaults filled in (background null: none).
static func text_options(given: Dictionary) -> Dictionary:
	var out := {}
	for k: String in TEXT_OPTIONS:
		out[k] = given.get(k, TEXT_OPTIONS[k]["default"])
	return out


## A widget's options with the defaults filled in.
static func widget_options(w: String, given: Dictionary) -> Dictionary:
	var out := {}
	var spec: Dictionary = WIDGETS.get(w, {}).get("options", {})
	for k: String in spec:
		out[k] = given.get(k, spec[k]["default"])
	return out


## The widgets for room_state and the guide: [{name, description, options: {name: {type, default, ...}}}].
static func supported_widgets() -> Array:
	var out: Array = []
	var names: Array = WIDGETS.keys()
	names.sort()
	for n: String in names:
		out.append({"name": n, "description": WIDGETS[n]["description"], "options": WIDGETS[n]["options"]})
	return out


static func supported_effects() -> Array:
	var out: Array = []
	for n: String in EFFECTS:
		out.append({"name": n, "description": EFFECTS[n]["description"], "options": EFFECTS[n]["options"]})
	return out


## A material object with a change's fields on top. A library material and a picture exclude each other, and a
## library material goes under an effect only when the effect layers (EffectLibrary entry "layers"): a change naming
## a library material drops the old picture, an effect that doesn't layer, and the old library material's colour and
## options (a new material shows as itself unless the change gives a colour); a picture, or an effect that doesn't
## layer, drops the library material. Everything else (colour, tint, tiling, emission, a layering effect) changes
## what is there.
static func merge_material(old: Dictionary, change: Dictionary) -> Dictionary:
	var out := old.duplicate(true)
	var drop: Array = []
	if change.has("library_material"):
		drop = ["texture", "texture_file", "uv", "color"]
		drop.append_array(LIBRARY_OPTIONS)
		if not _layers(change.get("effect", out.get("effect"))):
			drop.append("effect")
	elif change.has("texture") or change.has("texture_file") or (change.has("effect")
			and not _layers(change["effect"])):
		drop = ["library_material"]
		drop.append_array(LIBRARY_OPTIONS)
	for k: String in drop:
		out.erase(k)
	out.merge(change.duplicate(true), true)
	return out


## Whether an effect object ({name, ...}) keeps the surface under it, so it goes over a library material.
static func _layers(fx: Variant) -> bool:
	var fx_name := str(fx.get("name", "")) if fx is Dictionary else ""
	return EffectLibrary.has(fx_name) and bool(EffectLibrary.entry(fx_name)["layers"])


## The version a room is kept as: SYSTEMS_VERSION when it has any of the environments engine's sections, else VERSION.
static func version_for(doc: Dictionary) -> int:
	for k: String in (load(ENV_DOC) as GDScript).get("SECTIONS"):
		if doc.has(k):
			return SYSTEMS_VERSION
	return VERSION


## The room after a patch: parts replaced or added by name, removed ones gone, light / sky / recolour merged.
static func merge(current: Dictionary, patch: Dictionary) -> Dictionary:
	var out := current.duplicate(true)
	# The environments engine's sections (version 4): a patch replaces each one it names; null takes it out.
	for k: String in (load(ENV_DOC) as GDScript).get("SECTIONS"):
		if patch.has(k) and patch[k] == null:
			out.erase(k)
		elif patch.has(k):
			out[k] = patch[k].duplicate(true) if patch[k] is Dictionary or patch[k] is Array else patch[k]
	out["schema"] = version_for(out)
	for k in ["name", "light", "sky", "atmosphere", "seats", "default_seat", "screen", "lights"]:
		if patch.has(k) and patch[k] == null:
			out.erase(k)
		elif k == "light" and patch.get(k) is Dictionary and out.get(k) is Dictionary:
			# light merges key by key (a patch with only key keeps the sky); a key set to null goes.
			var l: Dictionary = (out[k] as Dictionary).duplicate(true)
			for lk: Variant in patch[k]:
				if patch[k][lk] == null:
					l.erase(lk)
				else:
					l[lk] = patch[k][lk].duplicate(true) if patch[k][lk] is Dictionary else patch[k][lk]
			out[k] = l
		elif patch.has(k):
			out[k] = patch[k].duplicate(true) if patch[k] is Dictionary or patch[k] is Array else patch[k]
	var parts: Array = out.get("parts", []).duplicate()
	for name: Variant in patch.get("remove", []):
		parts = parts.filter(func(p: Dictionary) -> bool: return p["name"] != name)
	for np: Dictionary in patch.get("parts", []):
		var at := -1
		for i in parts.size():
			if parts[i]["name"] == np["name"]:
				at = i
		if at >= 0:
			parts[at] = np.duplicate(true)
		else:
			parts.append(np.duplicate(true))
	out["parts"] = parts
	var rec: Array = out.get("recolour", []).duplicate()
	for r: Dictionary in patch.get("recolour", []):
		rec = rec.filter(func(x: Dictionary) -> bool: return x["match"] != r["match"])
		# "material": null takes the entry out (the part shows its own colours again).
		if not (r.has("material") and r["material"] == null):
			rec.append(r.duplicate(true))
	# A removed part's own part-level entries ("Shelf/Board" when Shelf goes) go with it.
	for name: Variant in patch.get("remove", []):
		rec = rec.filter(func(x: Dictionary) -> bool:
			var s := split_match(str(x["match"]))
			return s.is_empty() or s[0] != str(name))
	out["recolour"] = rec
	return out


## The document without its big data (base64 replaced by a size), for room_state.
static func summary(doc: Dictionary) -> Dictionary:
	return _strip(doc)


static func _strip(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			if str(k) in ["model", "texture", "image", "base_model"] and v[k] is String:
				out[k] = {"bytes": (v[k] as String).length() / 4 * 3}
			else:
				out[k] = _strip(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _strip(x))
	return v
