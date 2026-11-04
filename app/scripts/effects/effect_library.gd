extends RefCounted

## The effect library (docs/effects.md): the catalogue of procedural looks any surface can name by id (a room's
## surfaces, an object's parts, the sky), each with a description written for an assistant to choose by, tags,
## bounded options, the surfaces it suits, a measured cost tier, how it animates, and a preview. Data and the
## shaders' wiring only; the room document names an effect (material.effect = {name, ...options}) and the room builder
## calls apply().
##
## The entries live in one file per group under scripts/effects/catalogue/ (GROUPS), each `const EFFECTS := {id:
## entry}` and the group's shader `const SHADER`. Each effect is its group shader compiled with its own define
## (FX_<NAME>): one lean variant per effect, as room_effect.gdshader. The eight first effects (catalogue/classic.gd)
## keep room_effect.gdshader exactly as before.
##
## An entry:
##   name         what people call it ("Plasma")
##   description  one line, for an assistant choosing a look: what it looks like, where it suits
##   tags         [words] to filter by (effects tag=...)
##   surfaces     "any" (parts, room surfaces) or "sky" (the sky sphere only)
##   blend        "opaque", "cutout" (alpha-tested), "alpha" (see-through) or "add" (light added); the last two are
##                drawn in the transparent pass, over what is behind: overdraw (cost)
##   layers       true when it keeps the surface's own colour and picture under it, so it layers over a library
##                material ("wood with a slow rim glow"); false when it draws its own surface
##   passes       1, or 2 with a second pass (second_pass: its shader; options with "pass": 1 go to it)
##   cost         the measured tier, "light", "medium" or "heavy" (TIERS: what the room's cost cap counts); cost_ratio
##                the measured fragment time over the plain surface's on a surface filling the view (tools/fx_lab.gd)
##   animation    {} for a still effect, else {hz: [slowest, fastest], swing}: the fastest a pixel's brightness changes
##                at the fastest options and how far it swings then (1: all the way), so hz[1] <= MAX_HZ and
##                hz[1] x swing <= MAX_HZ x MAX_SWING (no steeper than a 3 Hz wave of the full swing)
##   define       the shader's define, FX_<NAME>
##   options      {name: {type: float | int | color | enum | bool, min, max, default, values (enum), description,
##                uniform (the shader's), pass (1: the second pass's)}}
##   react        optional: "loudness" or "brightness", the film's path the room builder keeps fresh for it
##   preview_options  optional: options for its preview (a transition half way)
##   photo_test   optional: the options its photosensitivity clip uses instead of the fast ones at their maximum
##                (effect_lab.gd fastest_options)
##
##   EffectLibrary.ids() -> Array                 every id, by group
##   EffectLibrary.entry(id) -> Dictionary        the whole entry ({} when unknown)
##   EffectLibrary.validate(id, options) -> Array [{path, error}], [] when fine (the room schema's wording)
##   EffectLibrary.apply(mat, id, options, seed)  sets mat's shader and uniforms (and next_pass)
##   EffectLibrary.apply_layered(mat, id, options, seed, base) -> String
##                                                the effect over a colour or a library material's picture
##   EffectLibrary.cost_units(id) -> float        what the room's cost cap counts for it
##   EffectLibrary.schema_effects() -> Dictionary {id: {description, options}}: room_schema EFFECTS' shape

const GROUPS: Array[String] = [
	"res://scripts/effects/catalogue/classic.gd",
	"res://scripts/effects/catalogue/energy.gd",
	"res://scripts/effects/catalogue/nature.gd",
	"res://scripts/effects/catalogue/materials.gd",
	"res://scripts/effects/catalogue/stylised.gd",
	"res://scripts/effects/catalogue/transitions.gd",
	"res://scripts/effects/catalogue/reactive.gd",
	"res://scripts/effects/catalogue/skies.gd",
]
## The photosensitivity ceiling (RoomSchema.MAX_HZ, MAX_SWING; the shaders' FX_MAX_HZ, FX_MAX_SWING).
const MAX_HZ := 3.0
const MAX_SWING := 0.4
## What each cost tier counts against the room's cost cap (RoomSchema.COSTS, LIMITS.cost); see cost_units().
const TIERS := {"light": 1.0, "medium": 2.0, "heavy": 3.0}
## Measured cost_ratio up to this is light, up to MEDIUM_RATIO medium, else heavy.
const LIGHT_RATIO := 2.75
const MEDIUM_RATIO := 4.5
const SURFACES: Array[String] = ["any", "sky"]
const BLENDS: Array[String] = ["opaque", "cutout", "alpha", "add"]
const NOISE_VALUE := "res://textures/fx/fx_value.png"
const NOISE_FBM := "res://textures/fx/fx_fbm.png"
## Where the previews are (tools/fx_lab.gd --previews makes them).
const PREVIEWS := "docs/shots/effects"
## Keys an assistant does not need (effects, effect_info leave them out).
const PRIVATE_KEYS: Array[String] = ["define", "shader", "second_pass", "uniform", "pass", "photo_test",
		"preview_options"]

static var _entries := {}
static var _order: Array[String] = []
static var _shaders := {}
static var _noise := {}


## Every entry by id, read once from the group files; each gets its group and shader filled in.
static func catalogue() -> Dictionary:
	if _order.is_empty():
		for path in GROUPS:
			if not FileAccess.file_exists(path):
				continue
			var consts: Dictionary = (load(path) as GDScript).get_script_constant_map()
			var group := path.get_file().get_basename()
			for id: String in consts.get("EFFECTS", {}):
				var e: Dictionary = (consts["EFFECTS"][id] as Dictionary).duplicate(true)
				e["group"] = group
				e["shader"] = e.get("shader", consts.get("SHADER", ""))
				for k: String in ["layers", "passes", "blend", "surfaces", "animation"]:
					if not e.has(k):
						e[k] = {"layers": false, "passes": 1, "blend": "opaque", "surfaces": "any", "animation": {}}[k]
				_entries[id] = e
				_order.append(id)
	return _entries


static func ids() -> Array[String]:
	catalogue()
	return _order.duplicate()


static func has(id: String) -> bool:
	return catalogue().has(id)


static func entry(id: String) -> Dictionary:
	return catalogue().get(id, {})


static func groups() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if not str(entry(id)["group"]) in out:
			out.append(str(entry(id)["group"]))
	return out


## An entry as the assistant sees it: without the shader's wiring, with its cost and preview.
static func public_entry(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return {}
	var out := _public(e) as Dictionary
	out["id"] = id
	out["cost_units"] = cost_units(id)
	out["animates"] = not (e["animation"] as Dictionary).is_empty()
	out["transparent"] = str(e["blend"]) in ["alpha", "add"]
	out["preview"] = "%s/%s.png" % [PREVIEWS, id]
	return out


static func _public(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			if not str(k) in PRIVATE_KEYS:
				out[k] = _public(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _public(x))
	return v


## What the room's cost cap counts for an effect: its tier, one more for a second pass, one more when it is drawn
## over what is behind it (RoomSchema.COSTS blend).
static func cost_units(id: String) -> float:
	var e := entry(id)
	if e.is_empty():
		return 0.0
	var c: float = TIERS.get(str(e.get("cost", "light")), 1.0)
	c += float(int(e.get("passes", 1)) - 1)
	if str(e["blend"]) in ["alpha", "add"]:
		c += 1.0
	return c


## The tier a measured cost ratio falls in.
static func tier_of(ratio: float) -> String:
	if ratio <= LIGHT_RATIO:
		return "light"
	return "medium" if ratio <= MEDIUM_RATIO else "heavy"


## room_schema.gd's EFFECTS, derived: {id: {description, options}} for the surfaces' effects (sky: false) or the
## sky's (sky: true). Options keep only what the schema checks (type, min, max, values, default, description).
static func schema_effects(sky := false) -> Dictionary:
	var out := {}
	for id in ids():
		var e := entry(id)
		if (str(e["surfaces"]) == "sky") != sky:
			continue
		out[id] = {"description": e["description"], "options": _public(e["options"])}
	return out


## An effect's options with the defaults filled in (unknown keys dropped).
static func with_defaults(id: String, given: Dictionary) -> Dictionary:
	var out := {}
	var spec: Dictionary = entry(id).get("options", {})
	for k: String in spec:
		out[k] = given.get(k, spec[k]["default"])
	return out


## Every problem with an effect and its options, [{path, error}], in the room schema's words (path: where the
## options sit, as "$.parts[0].material.effect").
static func validate(id: String, options: Dictionary, path := "$.effect") -> Array:
	var errors: Array = []
	if not has(id):
		errors.append({"path": path + ".name", "error": "{name, ...options}: name one of %s" % ", ".join(ids())})
		return errors
	var spec: Dictionary = entry(id)["options"]
	for k: Variant in options:
		var p := "%s.%s" % [path, k]
		if str(k) == "name":
			continue
		if not spec.has(str(k)):
			errors.append({"path": p, "error": "unknown option for %s (known: %s)" % [id, ", ".join(spec.keys())]})
			continue
		var o: Dictionary = spec[str(k)]
		var x: Variant = options[k]
		match str(o["type"]):
			"enum":
				if not (x is String and x in o["values"]):
					errors.append({"path": p, "error": "one of %s" % ", ".join(o["values"])})
			"bool":
				if not (x is bool):
					errors.append({"path": p, "error": "true or false"})
			"color":
				if not _is_color(x):
					errors.append({"path": p, "error": "#rrggbb or [r, g, b] 0..1"})
			"float", "int":
				var f := float(x) if (x is float or x is int) else NAN
				if not (f >= float(o["min"]) and f <= float(o["max"])) or (str(o["type"]) == "int" and f != floorf(f)):
					var why := ""
					if str(k) == "rate" and f > MAX_HZ:
						why = " (the photosensitivity ceiling: brightness may change at most %d times a second)" \
							% int(MAX_HZ)
					elif float(o["max"]) == MAX_SWING and f > MAX_SWING:
						why = " (the photosensitivity ceiling: no larger brightness swings)"
					errors.append({"path": p, "error": "%s..%s%s" % [o["min"], o["max"], why]})
	return errors


static func _is_color(v: Variant) -> bool:
	if v is String:
		return Color.html_is_valid(v as String)
	if v is Array and ((v as Array).size() == 3 or (v as Array).size() == 4):
		return (v as Array).all(func(x: Variant) -> bool: return (x is float or x is int) and x >= 0.0 and x <= 1.0)
	return false


static func to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.html(v as String)
	if v is Array:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return Color.WHITE


## The effect's shader: its group shader with its define (and FX_TEST_CLOCK for the tests' clock, FX_BASE_TRIPLANAR
## for a library material mapped by the part's own space, FX_PRINT for our controller model's printed legends over it,
## scripts/xr/controller_look.gd), compiled once and kept.
static func shader(id: String, test_clock := false, triplanar := false, with_print := false) -> Shader:
	var e := entry(id)
	if e.is_empty():
		return null
	var key := "%s|%s|%s|%s" % [id, test_clock, triplanar, with_print]
	if not _shaders.has(key):
		var defines := "#define %s" % e["define"]
		if test_clock:
			defines += "\n#define FX_TEST_CLOCK"
		if triplanar:
			defines += "\n#define FX_BASE_TRIPLANAR"
		if with_print:
			defines += "\n#define FX_PRINT"
		var s := Shader.new()
		s.code = (load(str(e["shader"])) as Shader).code.replace("shader_type spatial;", "shader_type spatial;\n"
				+ defines)
		_shaders[key] = s
	return _shaders[key]


## Puts an effect on a material: its shader, its options (defaults for those not given) on their uniforms, the noise
## textures, a seed (0..1, from the part's name, so copies are out of step) and, for a two-pass effect, its second
## pass. The material's own colour, picture, emission and self_lit are the caller's (the room builder sets them as for
## any surface). flags: test_clock, triplanar, print (shader()).
static func apply(mat: ShaderMaterial, id: String, options: Dictionary, seed_value: float, flags := {}) -> void:
	var e := entry(id)
	if e.is_empty():
		return
	mat.shader = shader(id, bool(flags.get("test_clock", false)), bool(flags.get("triplanar", false)),
			bool(flags.get("print", false)))
	var second: ShaderMaterial = null
	if e.has("second_pass"):
		second = ShaderMaterial.new()
		second.shader = load(str(e["second_pass"])) as Shader
		mat.next_pass = second
	var o := with_defaults(id, options)
	var spec: Dictionary = e["options"]
	for k: String in o:
		var s: Dictionary = spec[k]
		if not s.has("uniform"):
			continue
		var target: ShaderMaterial = second if int(s.get("pass", 0)) == 1 and second != null else mat
		target.set_shader_parameter(str(s["uniform"]), _uniform_value(k, s, o[k]))
	if not str(e["shader"]).ends_with("room_effect.gdshader"):
		mat.set_shader_parameter("fx_value_noise", noise_texture(NOISE_VALUE))
		mat.set_shader_parameter("fx_fbm", noise_texture(NOISE_FBM))
	mat.set_shader_parameter("fx_seed", seed_value)


## A layered look: an effect that keeps the surface under it (layers: true) over a base, which is a colour, or a
## library material's picture (the material library's albedo texture) repeating by UV or, with triplanar (metres a
## repeat), by the part's own space on all three axes, for parts whose UVs don't suit a texture. base: {color:
## "#rrggbb" or Color, texture: Texture2D, uv_scale: Vector2 (repeats across the UV), triplanar: metres (0: by UV)}.
## Returns "" or why it can't (an effect that draws its own surface, or the first eight with triplanar: their
## shader has no such mapping).
static func apply_layered(mat: ShaderMaterial, id: String, options: Dictionary, seed_value: float, base: Dictionary,
		flags := {}) -> String:
	var e := entry(id)
	if e.is_empty():
		return "no effect %s" % id
	if not bool(e["layers"]):
		return "%s draws its own surface: it does not layer over a material" % id
	var triplanar := float(base.get("triplanar", 0.0))
	var classic := str(e["shader"]).ends_with("room_effect.gdshader")
	if triplanar > 0.0 and classic:
		return "%s maps a picture by UV only" % id
	var f := flags.duplicate()
	f["triplanar"] = triplanar > 0.0
	apply(mat, id, options, seed_value, f)
	var colour := to_color(base.get("color", Color.WHITE))
	mat.set_shader_parameter("albedo", colour)
	mat.set_shader_parameter("alpha", colour.a)
	if base.get("texture") is Texture2D:
		mat.set_shader_parameter("albedo_texture", base["texture"])
		mat.set_shader_parameter("use_texture", true)
		if not classic:
			mat.set_shader_parameter("uv_scale", base.get("uv_scale", Vector2.ONE))
			mat.set_shader_parameter("base_scale", maxf(triplanar, 0.01))
	return ""


## An option's value as its uniform takes it: a colour as a Color, an enum as its index, a rate or swing under the
## ceiling.
static func _uniform_value(k: String, s: Dictionary, v: Variant) -> Variant:
	match str(s["type"]):
		"color":
			return to_color(v)
		"enum":
			return maxi((s["values"] as Array).find(v), 0)
		"bool":
			return bool(v)
		"int":
			return int(v)
	var f := float(v)
	if k == "rate":
		f = minf(f, MAX_HZ)
	elif k == "swing":
		f = minf(f, MAX_SWING)
	return f


## The seed the room builder gives a part (assistant_room.gd: from its name), so the same part keeps its phase.
static func seed_of(key: String) -> float:
	return float(key.md5_text().substr(0, 4).hex_to_int()) / 65535.0


## A noise texture, read once (the app runs from its folder: the PNGs are not imported). fx_fbm is mipmapped.
static func noise_texture(path: String) -> Texture2D:
	if not _noise.has(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			push_error("effect library: can't read %s" % path)
			img = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 0.5, 0.5))
		if path == NOISE_FBM:
			img.generate_mipmaps()
		_noise[path] = ImageTexture.create_from_image(img)
	return _noise[path]


## A short line per effect, for the effects command: filtered by group, tag or surface ("" for all).
static func summaries(group := "", tag := "", surface := "") -> Array:
	var out: Array = []
	for id in ids():
		var e := entry(id)
		if group != "" and str(e["group"]) != group:
			continue
		if tag != "" and not tag in (e.get("tags", []) as Array):
			continue
		if surface != "" and str(e["surfaces"]) != surface:
			continue
		var p := public_entry(id)
		out.append({"id": id, "name": p["name"], "group": p["group"], "description": p["description"],
				"tags": p["tags"], "surfaces": p["surfaces"], "transparent": p["transparent"], "layers": p["layers"],
				"cost": p["cost"], "cost_units": p["cost_units"], "animates": p["animates"],
				"options": (p["options"] as Dictionary).keys()})
	return out


## The read commands (scripts/dev/command_host.gd registers them): effects and effect_info.
static func register_commands(_host: Node) -> void:
	var DevCommands := load("res://scripts/dev/dev_commands.gd")
	DevCommands.register("effects", func(a: Dictionary, _ctx: RefCounted) -> Variant:
			return listing(str(a.get("group", "")), str(a.get("tag", "")), str(a.get("surface", ""))), {
		"description": "The effect library: procedural looks a surface can name (energy, natural, materials, "
				+ "stylised, transitions, reactive, skies), each with a one-line description, tags, the surfaces it "
				+ "suits, whether it is see-through, whether it keeps the surface's own colour (layers), its cost "
				+ "tier and whether it animates. effect_info gives one effect's options and bounds.",
		"assistant": "read",
		"params": [
			{"name": "group", "type": "string", "description": "only this group: classic, energy, nature, "
				+ "materials, stylised, transitions, reactive or skies"},
			{"name": "tag", "type": "string", "description": "only effects with this tag, e.g. glow, water, calm"},
			{"name": "surface", "type": "string", "enum": ["any", "sky"], "description": "any: for parts and room "
				+ "surfaces; sky: for the sky only"}],
		"returns": "{effects: [{id, name, group, description, tags, surfaces, transparent, layers, cost, cost_units, "
				+ "animates, options}], groups, tiers, photosensitivity}"})
	DevCommands.register("effect_info", func(a: Dictionary, ctx: RefCounted) -> Variant:
			var id := str(a.get("id", ""))
			if not has(id):
				return ctx.call("fail", "no effect %s (effects lists them)" % id)
			return public_entry(id), {
		"description": "One effect of the library in full: its description, tags, the surfaces it suits, blend, "
				+ "whether it layers over the surface's own colour, cost tier and units, how it animates (the "
				+ "slowest and fastest rate, the swing), and every option with its type, bounds, default and meaning.",
		"assistant": "read",
		"params": [{"name": "id", "type": "string", "required": true, "description": "an effect's id, from effects"}],
		"returns": "{id, name, group, description, tags, surfaces, blend, transparent, layers, passes, cost, "
				+ "cost_ratio, cost_units, animates, animation, options, preview}"})


## The effects command's reply.
static func listing(group := "", tag := "", surface := "") -> Dictionary:
	return {"effects": summaries(group, tag, surface), "groups": groups(), "tiers": TIERS,
			"photosensitivity": {"max_hz": MAX_HZ, "max_swing": MAX_SWING, "rule": "no brightness change faster than "
			+ "3 times a second, no swing larger than 0.4 of the surface's brightness; a moving pattern no steeper "
			+ "than a 3 Hz wave of that swing"}}
