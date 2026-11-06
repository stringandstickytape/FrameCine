extends RefCounted

## The controllers' look (docs/features.md, "Controller look"): what the shell of both controllers is made of, from a
## short list of presets: the black plastic they come in (the default), plain plastics, metals from the material
## library (scripts/env/material_library.gd) and a few effects from the effect library (scripts/effects/
## effect_library.gd) that suit a held object. One setting for both hands ([controllers] look and look_options, main.gd);
## the System tab's Controllers section and the assistant's controller_look command set it.
##
## The look goes on the shell only (the body and the battery door, controller_visual.gd SHELL_PARTS): the buttons,
## stick, trigger and grip stay black with their moulded art white, so their letters read as before.
##
## The printed legends stay legible on every look (print_style()). On one colour (the plastics, the metals) the ink is
## white or near-black, whichever stands out more against the darkest and the brightest the shell gets under the
## controllers' fake light; when neither reaches MIN_CONTRAST against both, the letters also get a backing in the
## other one. On an effect the shell has no one colour, so the letters always get the backing: white ink, a near-black
## outline. Ink against backing is INK_CONTRAST or more, so a letter's edge always meets a colour it stands out from.
## The print on the runtime's model draws the backing as an outline from its distance field (controller_label.gdshader);
## our model's legends, which are in its texture, as a halo from a coarser mip of it (controller_print.gdshaderinc).
##
## Cost: the look replaces the shell's material, so no draw call or pass is added and nothing runs per frame in
## GDScript (an effect animates by the shader's clock). A plastic is the default shader with its colour; a metal adds
## three texture reads; an effect costs its measured tier (the effect library's cost_ratio, against a plain surface),
## over the few per cent of the view the controllers cover.
##
##   ControllerLook.ids() -> Array[String]             every preset, in the picker's order
##   ControllerLook.entry(id) -> Dictionary            the preset ({} when unknown)
##   ControllerLook.validate(id, options) -> Array     [{path, error}], [] when fine
##   ControllerLook.material(id, options, target, ...) -> ShaderMaterial   the shell's (null: the model's own)
##   ControllerLook.print_style(id, options) -> Dictionary   {ink, backing, backing_on, contrast}
##   ControllerLook.listing() -> Array                 the presets as the assistant reads them (controller_looks)

const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const MODEL_SHADER := preload("res://shaders/controller_model.gdshader")

const DEFAULT := "black"
## A preset:
##   name, description   what the picker and the assistant show
##   kind                "plastic" (a colour), "metal" (a library material's picture, reflecting) or "effect"
##   color               the plastic's colour, or the colour under a layering effect; a metal's from its swatch
##   lift, rim, sheen    controller_model.gdshader's lift, rim_gain and sheen (the plastic's shape in a dark room)
##   material, tiling, reflection   a metal: its library id, metres a repeat of its picture, how much it reflects
##   effect, options     an effect: its id and the options it starts from (the user's go over them)
## The default's numbers are only for print_style(): controller_visual.gd keeps the model's own black.
## The names are keys of the menus' languages (the System tab's buttons translate them; docs/i18n.md).
# i18n: begin name
const LOOKS := {
	"black": {"name": "Black", "kind": "plastic", "color": "#191919", "lift": 0.003, "rim": 0.07, "sheen": 0.014,
			"description": "the black plastic the controllers come in (the default)"},
	"white": {"name": "White", "kind": "plastic", "color": "#e4e4e0",
			"description": "white plastic with a soft sheen; dark print"},
	"graphite": {"name": "Graphite", "kind": "plastic", "color": "#3a3d42",
			"description": "dark grey plastic"},
	"red": {"name": "Red", "kind": "plastic", "color": "#8e1a15", "description": "deep red plastic"},
	"blue": {"name": "Blue", "kind": "plastic", "color": "#1b4590", "description": "deep blue plastic"},
	"colour": {"name": "Any colour", "kind": "plastic", "color": "#1f6f5a",
			"description": "plastic in a colour of your choice (option color); the print picks its ink to match"},
	"steel": {"name": "Brushed steel", "kind": "metal", "material": "brushed_steel", "tiling": 0.12, "reflection": 0.5,
			"description": "brushed steel from the material library, reflecting a soft studio"},
	"dark_metal": {"name": "Dark metal", "kind": "metal", "material": "dark_metal", "tiling": 0.12, "reflection": 0.4,
			"description": "dark worn metal from the material library"},
	"brass": {"name": "Brass", "kind": "metal", "material": "brass", "tiling": 0.12, "reflection": 0.55,
			"description": "polished brass from the material library"},
	"plasma": {"name": "Plasma", "kind": "effect", "effect": "plasma", "options": {"size": 0.12, "speed": 0.35},
			"description": "slowly flowing plasma, pink and deep violet"},
	"cold_plasma": {"name": "Cold plasma", "kind": "effect", "effect": "plasma",
			"options": {"size": 0.12, "speed": 0.3, "color": "#7fe0ff", "color2": "#0a1f5c"},
			"description": "slowly flowing plasma, ice blue and deep navy"},
	"embers": {"name": "Embers", "kind": "effect", "effect": "embers", "options": {"size": 0.03, "rate": 0.3},
			"description": "a charred shell with glowing seams and specks that brighten and dim slowly"},
	"circuit": {"name": "Circuit", "kind": "effect", "effect": "circuit", "color": "#16181c",
			"options": {"size": 0.02, "speed": 0.4}, "description": "faint circuit traces with soft pulses on dark plastic"},
	"neon": {"name": "Neon", "kind": "effect", "effect": "neon", "options": {"color": "#ff2d95", "core": 0.4},
			"description": "a glowing neon tube, white where it faces you"},
	"starfield": {"name": "Starfield", "kind": "effect", "effect": "starfield",
			"options": {"size": 0.02, "density": 0.6, "twinkle": 0.2},
			"description": "a night-blue shell with small stars twinkling gently"},
	"liquid_chrome": {"name": "Liquid chrome", "kind": "effect", "effect": "liquid_chrome",
			"options": {"size": 0.1, "speed": 0.3}, "description": "a mirror whose reflection slowly flows"},
	"iridescent": {"name": "Iridescent", "kind": "effect", "effect": "iridescent", "color": "#17181c",
			"options": {"size": 0.1}, "description": "dark plastic with a thin-film rainbow sheen that turns with the angle"},
	"carbon_fibre": {"name": "Carbon fibre", "kind": "effect", "effect": "carbon_fibre",
			"options": {"size": 0.004, "coat": 0.3},
			"description": "woven carbon fibre under a glossy clear coat"},
}
# i18n: end
## The plastics' shape in a dark room, unless the preset says otherwise.
const LIFT := 0.01
const RIM := 0.1
const SHEEN := 0.03
## Print inks: white, and a near-black that is not a hole in the picture.
const INK_LIGHT := Color(1.0, 1.0, 1.0)
const INK_DARK := Color(0.08, 0.08, 0.08)
## Contrast ratios ((lighter + 0.05) / (darker + 0.05), relative luminance): the ink against the shell, without a
## backing (the usual minimum for body text), and the ink against its backing.
const MIN_CONTRAST := 4.5
const INK_CONTRAST := 7.0
## How much of the rim term a legend sees: legends are read within about 60 degrees of square on, where
## controller_model.gdshader's rim ((1 - cos)^3) is about an eighth.
const RIM_SEEN := 0.15
## The backing's reach past the letters' edge, in the label shader's field units (controller_label.gdshader).
const BACKING_WIDTH := 0.35


static func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(LOOKS.keys())
	return out


static func has(id: String) -> bool:
	return LOOKS.has(id)


static func entry(id: String) -> Dictionary:
	return LOOKS.get(id, {})


## The options a look may take: a plastic its colour, a metal none, an effect its own (effect_info's, with their
## bounds). {name: {type, min, max, default, description}}.
static func option_specs(id: String) -> Dictionary:
	var e := entry(id)
	match str(e.get("kind", "")):
		"plastic":
			return {"color": {"type": "color", "default": str(e["color"]), "description": "the plastic's colour"}}
		"effect":
			var spec: Dictionary = EffectLibrary.entry(str(e["effect"])).get("options", {})
			var out := {}
			for k: String in spec:
				var o: Dictionary = (spec[k] as Dictionary).duplicate()
				for private in ["uniform", "pass"]:
					o.erase(private)
				o["default"] = (e["options"] as Dictionary).get(k, o.get("default"))
				out[k] = o
			return out
	return {}


## Every problem with a look and its options, [{path, error}] ([] when fine): an unknown look, an option it doesn't
## take, a value outside its bounds (an effect's are the effect library's, the photosensitivity ceiling among them).
static func validate(id: String, options: Variant) -> Array:
	if not has(id):
		return [{"path": "$.look", "error": "one of %s" % ", ".join(ids())}]
	if not options is Dictionary:
		return [{"path": "$.options", "error": "an object"}]
	var e := entry(id)
	match str(e["kind"]):
		"effect":
			return EffectLibrary.validate(str(e["effect"]), options as Dictionary, "$.options")
		"plastic":
			var errors: Array = []
			for k: Variant in options:
				if str(k) != "color":
					errors.append({"path": "$.options.%s" % k, "error": "a plastic takes only color"})
				elif not _is_colour(options[k]):
					errors.append({"path": "$.options.color", "error": "#rrggbb or [r, g, b] 0..1"})
			return errors
	var none: Array = []
	for k: Variant in options:
		none.append({"path": "$.options.%s" % k, "error": "%s takes no options" % id})
	return none


static func _is_colour(v: Variant) -> bool:
	if v is Color:
		return true
	return EffectLibrary._is_color(v)


## The preset's options with the user's over them: what the shell shows.
static func options_of(id: String, given: Dictionary) -> Dictionary:
	var out: Dictionary = (entry(id).get("options", {}) as Dictionary).duplicate(true)
	out.merge(given, true)
	return out


## The colour a plastic or a metal shows on average (a metal's is its library swatch), Color.BLACK for an effect.
static func body_colour(id: String, options := {}) -> Color:
	var e := entry(id)
	match str(e.get("kind", "")):
		"plastic":
			return EffectLibrary.to_color(options.get("color", e["color"]))
		"metal":
			return Color.html(str(MaterialLibrary.entry(str(e["material"])).get("swatch", "#808080")))
	return Color.BLACK


## The shell's material for one target, or null for the default (the model keeps its own black):
##   "ours"      our model (models/controllers): its texture holds the legends, drawn over the look in the print
##               style's ink; texture is the texture on show (its print state)
##   "runtime"   the runtime's model: the print is meshes over it (controller_visual.gd styles them)
##   "fallback"  the hand-built body
## unit: metres per unit of the shell mesh's own space (1 normally), so an effect's sizes and a metal's repeat stay
## in metres. seed_value: an effect's phase (0..1), so the two hands are out of step.
static func material(id: String, options: Dictionary, target: String, texture: Texture2D = null, unit := 1.0,
		seed_value := 0.0) -> ShaderMaterial:
	var e := entry(id)
	if e.is_empty() or id == DEFAULT:
		return null
	var o := options_of(id, options)
	var mat := ShaderMaterial.new()
	match str(e["kind"]):
		"plastic", "metal":
			mat.shader = MODEL_SHADER
			mat.set_shader_parameter("use_finish", true)
			mat.set_shader_parameter("finish", body_colour(id, o))
			mat.set_shader_parameter("lift", float(e.get("lift", LIFT)))
			mat.set_shader_parameter("rim_gain", float(e.get("rim", RIM)))
			mat.set_shader_parameter("sheen", float(e.get("sheen", SHEEN)))
			if str(e["kind"]) == "metal":
				var maps := MaterialLibrary.textures(str(e["material"]))
				if maps.get("albedo") is Texture2D:
					# The picture carries the colour; its swatch was only the average.
					mat.set_shader_parameter("finish", Color.WHITE)
					mat.set_shader_parameter("use_pattern", true)
					mat.set_shader_parameter("pattern", maps["albedo"])
					mat.set_shader_parameter("pattern_scale", float(e["tiling"]) / unit)
				mat.set_shader_parameter("reflection", float(e["reflection"]))
		"effect":
			var fx := str(e["effect"])
			EffectLibrary.apply(mat, fx, o, seed_value, {"print": target == "ours"})
			var base := EffectLibrary.to_color(e.get("color", "#1a1b1f"))
			mat.set_shader_parameter("albedo", base)
			mat.set_shader_parameter("alpha", 1.0)
			# The controllers carry their own light, as the default does: an effect shows the same in a dark room.
			mat.set_shader_parameter("self_lit", true)
			if unit != 1.0:
				var spec: Dictionary = EffectLibrary.entry(fx)["options"]
				if spec.has("size") and (spec["size"] as Dictionary).has("uniform"):
					mat.set_shader_parameter(str(spec["size"]["uniform"]), float(o.get("size", spec["size"]["default"])) / unit)
	if target == "ours":
		set_print(mat, print_style(id, options), texture)
	mat.set_meta(&"controller_look", id)
	return mat


## Our model's printed legends on a look's material: the texture they are in, their ink and backing.
static func set_print(mat: ShaderMaterial, style: Dictionary, texture: Texture2D) -> void:
	mat.set_shader_parameter("use_print", texture != null)
	mat.set_shader_parameter("print_texture", texture)
	mat.set_shader_parameter("print_ink", style["ink"])
	mat.set_shader_parameter("print_backing", style["backing"])
	mat.set_shader_parameter("print_backing_on", 1.0 if bool(style["backing_on"]) else 0.0)


## How the legends are printed on a look: {ink, backing (Colors), backing_on, contrast: the worst contrast of the ink
## with what is right behind it (the backing when it is on)}. See the top of this file.
static func print_style(id: String, options := {}) -> Dictionary:
	var e := entry(id)
	if e.is_empty() or str(e["kind"]) == "effect":
		return {"ink": INK_LIGHT, "backing": INK_DARK, "backing_on": true, "contrast": contrast(INK_LIGHT, INK_DARK)}
	var span := body_range(id, options_of(id, options))
	var best := INK_LIGHT
	var worst := 0.0
	for ink: Color in [INK_LIGHT, INK_DARK]:
		var c := minf(_contrast_lum(luminance(ink), span.x), _contrast_lum(luminance(ink), span.y))
		if c > worst:
			worst = c
			best = ink
	if worst >= MIN_CONTRAST:
		return {"ink": best, "backing": INK_DARK if best == INK_LIGHT else INK_LIGHT, "backing_on": false,
				"contrast": worst}
	var backing := INK_DARK if best == INK_LIGHT else INK_LIGHT
	return {"ink": best, "backing": backing, "backing_on": true, "contrast": contrast(best, backing)}


## The darkest and brightest relative luminance a plastic or metal shell shows where a legend is read, as
## controller_model.gdshader draws it: the key light from 0.45 to 1.2 of the colour, the rim as RIM_SEEN of it, the
## sheen at most; a metal's reflection from 0.05 to 1.45 of its colour (its studio's floor and the bright band).
static func body_range(id: String, options := {}) -> Vector2:
	var e := entry(id)
	var base := luminance(body_colour(id, options)) + float(e.get("lift", LIFT))
	var sheen := float(e.get("sheen", SHEEN))
	var lo := base * 0.45
	var hi := base * 1.2 + float(e.get("rim", RIM)) * RIM_SEEN + sheen
	var r := float(e.get("reflection", 0.0))
	if r > 0.0:
		lo = lerpf(lo, base * 0.05 * 1.3, r)
		hi = lerpf(hi, base * 1.45 * 1.3 + sheen, r)
	return Vector2(lo, hi)


## Relative luminance of a colour given in sRGB.
static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func contrast(a: Color, b: Color) -> float:
	return _contrast_lum(luminance(a), luminance(b))


static func _contrast_lum(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## What a look costs: {tier: light | medium | heavy, cost_ratio: the fragment time over the plain surface's, as the
## effect library measures it, passes, animates}. A plastic is the default shader (ratio 1); a metal adds three
## texture reads (about the library's light tier).
static func cost(id: String) -> Dictionary:
	var e := entry(id)
	match str(e.get("kind", "")):
		"effect":
			var fx := EffectLibrary.entry(str(e["effect"]))
			return {"tier": str(fx.get("cost", "light")), "cost_ratio": float(fx.get("cost_ratio", 1.0)),
					"passes": int(fx.get("passes", 1)), "animates": not (fx.get("animation", {}) as Dictionary).is_empty()}
		"metal":
			return {"tier": "light", "cost_ratio": 1.5, "passes": 1, "animates": false}
	return {"tier": "light", "cost_ratio": 1.0, "passes": 1, "animates": false}


## The presets as the assistant reads them (the controller_looks command).
static func listing() -> Array:
	var out: Array = []
	for id in ids():
		var e := entry(id)
		var item := {"id": id, "name": e["name"], "kind": e["kind"], "description": e["description"],
				"options": option_specs(id), "cost": cost(id)}
		if e.has("effect"):
			item["effect"] = e["effect"]
		if e.has("material"):
			item["material"] = e["material"]
		out.append(item)
	return out


## The look as the settings and the assistant report it: {look, name, kind, options (the user's), effect or material}.
static func describe(id: String, options: Dictionary) -> Dictionary:
	var e := entry(id)
	var out := {"look": id, "name": e.get("name", id), "kind": e.get("kind", ""), "options": options.duplicate(true)}
	for k in ["effect", "material"]:
		if e.has(k):
			out[k] = e[k]
	var style := print_style(id, options)
	out["print"] = {"ink": "#" + (style["ink"] as Color).to_html(false), "backing": bool(style["backing_on"])}
	out["cost"] = cost(id)
	return out
