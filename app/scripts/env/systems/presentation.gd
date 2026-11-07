extends "res://scripts/env/systems/env_system.gd"

## The presentation chain (docs/environments.md, "The presentation system"): the stages between the film and the
## viewer's eyes, each optional.
##   source         film (gate weave, a slight tilt, flicker, dust, scratches, the lamp's hotspot), tape (tracking
##                  wobble, chroma bleed, head-switch noise at the bottom), broadcast (interlace)
##   transmission   aerial noise (snow), a ghost, a weak signal
##   display        mechanical (a 1930 mechanical-scan set's few orange lines), crt (curvature, round corners, a mask,
##                  scanlines, the glass's reflection), panel (a flat panel's grid and backlight bleed)
##   speaker        the sound through a small speaker: a drive-in's window speaker, a telly's, a radio cabinet's, a
##                  flat panel's
## A preset (PRESETS: the TV eras, a worn print, a drive-in's) fills every parameter the document leaves out; the
## document's own values and bindings win. To move a preset's value by a cue, give it in the document.
##
## The picture: while a picture stage is on, the screen's flat mesh draws the film with this system's material
## (shaders/env_presentation.gdshader: the screen's own picture, its uniforms copied each frame, then the stages), and
## the film layer steps aside (film_layer.gd request_scene()): an OpenXR layer would skip the scene's shaders. With
## every picture stage off nothing changes and the film layer stays. Flat screens only.
## The sound: a bus of its own, "Film speaker", just before Film; while a speaker is on, Film sends to it and it to
## Master. The binaural renderer and the film's analysis (on Film) are not touched, and the duck stays keyed from Film.
##
##   picture_on() -> bool, attached, material(), value(param), speaker_now, static PRESETS, static SPEAKERS

const SHADER := preload("res://shaders/env_presentation.gdshader")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

const SOURCES: Array[String] = ["none", "film", "tape", "broadcast"]
const DISPLAYS: Array[String] = ["none", "mechanical", "crt", "panel"]
const MASKS: Array[String] = ["none", "shadow", "grille", "slot"]
## The speakers: the band (high-pass and low-pass, Hz; slope 1..4 = 6..24 dB an octave), an EQ6's six bands (dB at
## 32, 100, 320, 1000, 3200 and 10000 Hz), a little drive (0..1), and the stereo width (0: mono).
const SPEAKERS := {
	"window": {"high": 320.0, "low": 3400.0, "slope": 4, "eq": [0, 0, 1, 4, 2, 0], "drive": 0.12, "width": 0.0,
			"description": "a drive-in's window speaker: a tinny band, a little rattle, mono"},
	"telly": {"high": 150.0, "low": 6500.0, "slope": 2, "eq": [0, 0, 0, 2.5, 1, 0], "drive": 0.0, "width": 0.0,
			"description": "a telly's small speaker, mono"},
	"cabinet": {"high": 110.0, "low": 4200.0, "slope": 3, "eq": [0, 0, 3, 1, 0, 0], "drive": 0.04, "width": 0.0,
			"description": "a wooden radio cabinet's speaker, warm and boxy, mono"},
	"panel": {"high": 200.0, "low": 12000.0, "slope": 2, "eq": [0, 0, 0, 0, 1.5, 0], "drive": 0.0, "width": 0.4,
			"description": "a flat panel's thin speakers, narrow stereo"},
}
## The bus the speaker's filters sit on (just before Film, which sends to it while a speaker is on).
const SPEAKER_BUS := &"Film speaker"
## Gate weave at weave 1, as a fraction of the picture's height (real projectors: about 0.1-0.3 %).
const WEAVE_MAX := 0.003
## The flicker's depth at flicker 1 (the picture's light, up or down), and how fast it may waver: a new target this
## often (seconds), followed with this time constant: well under the photosensitivity ceiling (room_schema MAX_HZ).
const FLICKER_DEPTH := 0.035
const FLICKER_STEP := 0.25
const FLICKER_TAU := 0.15
## Film frames a second for the dust and the scratches.
const FILM_FPS := 24.0

## The presets: the TV eras and two of the cinema set's screens. Names are pastiche, never a real mark.
const PRESETS := {
	"worn_print": {"title": "Worn Print", "description": "a 1980s print near the end of its run: gate weave, a "
			+ "slight tilt, dust, scratches and a lamp's flicker",
			"params": {"source": "film", "weave": 0.7, "tilt": 0.35, "flicker": 0.5, "dust": 0.5, "scratches": 0.4,
					"hotspot": 0.4}},
	"starlight_lot_1958": {"title": "Starlight Lot, 1958", "description": "a drive-in: a print with a little "
			+ "weave and dust, a strong lamp's hotspot, the sound from the window speaker",
			"params": {"source": "film", "weave": 0.5, "flicker": 0.4, "dust": 0.3, "scratches": 0.2, "hotspot": 0.6,
					"speaker": "window"}},
	"glowbox_1930": {"title": "Glowbox Thirty, 1930", "description": "a mechanical-scan set: thirty lines "
			+ "glowing orange in a small window, a faint hiss of noise, the sound from a radio cabinet",
			"params": {"display": "mechanical", "mech_lines": 30, "snow": 0.08, "weak": 0.2, "flicker": 0.3,
					"lines": 240, "speaker": "cabinet"}},
	"fireside_1953": {"title": "Fireside, 1953", "description": "a black and white set on a rooftop aerial: a "
			+ "small round-cornered tube, 405-line interlace, snow and a ghost",
			"params": {"source": "broadcast", "interlace": 0.6, "lines": 377, "snow": 0.22, "ghost": 0.25,
					"ghost_shift": 0.035, "display": "crt", "curvature": 0.9, "corner": 0.6, "mask": "none",
					"scanlines": 0.45, "glass": 0.7, "colour": 0.0, "tint": [0.92, 0.96, 1.0], "speaker": "telly"}},
	"colourstar_1972": {"title": "Colourstar, 1972", "description": "an early colour set: a curved tube with a "
			+ "shadow mask, warm and rich colours, interlace, a faint ghost",
			"params": {"source": "broadcast", "interlace": 0.5, "lines": 576, "snow": 0.06, "ghost": 0.12,
					"display": "crt", "curvature": 0.7, "corner": 0.45, "mask": "shadow", "mask_pitch": 380.0,
					"mask_strength": 0.35, "scanlines": 0.3, "glass": 0.6, "colour": 1.15, "tint": [1.0, 0.97, 0.9],
					"speaker": "telly"}},
	"sirclive_1983": {"title": "Sirclive, 1983", "description": "a portable telly on a home computer's aerial "
			+ "lead: 240 bold lines, a little RF noise, bright colours on a shadow mask",
			"params": {"source": "broadcast", "interlace": 0.0, "lines": 240, "snow": 0.05, "ghost": 0.06,
					"ghost_shift": 0.012, "display": "crt", "curvature": 0.8, "corner": 0.5, "mask": "shadow",
					"mask_pitch": 300.0, "mask_strength": 0.4, "scanlines": 0.65, "glass": 0.6, "colour": 1.2,
					"speaker": "telly"}},
	"rewinder_1987": {"title": "Rewinder, 1987", "description": "a rented tape on the family telly: tracking "
			+ "wobble, chroma bleed, the head-switch tear at the bottom, a slot mask",
			"params": {"source": "tape", "tracking": 0.5, "head_switch": 0.7, "chroma_bleed": 0.6, "tape_noise": 0.4,
					"lines": 576, "display": "crt", "curvature": 0.55, "corner": 0.35, "mask": "slot",
					"mask_pitch": 420.0, "mask_strength": 0.3, "scanlines": 0.3, "glass": 0.5, "speaker": "telly"}},
	"nightowl_1993": {"title": "Nightowl, 1993", "description": "a bedroom telly with a flatter tube and an "
			+ "aperture grille, playing a tape that has been watched a few times",
			"params": {"source": "tape", "tracking": 0.25, "head_switch": 0.5, "chroma_bleed": 0.4,
					"tape_noise": 0.25, "lines": 576, "display": "crt", "curvature": 0.35, "corner": 0.25,
					"mask": "grille", "mask_pitch": 480.0, "mask_strength": 0.3, "scanlines": 0.25, "glass": 0.45,
					"speaker": "telly"}},
	"freedtv_2005": {"title": "FreeDTV, 2005", "description": "a free digital broadcast on an early flat panel: a "
			+ "clean picture, a faint pixel grid, the backlight glowing through the dark scenes",
			"params": {"display": "panel", "panel_grid": 0.4, "panel_pixels": 1366, "panel_bleed": 0.5,
					"glass": 0.3, "speaker": "panel"}},
}


static func spec() -> Dictionary:
	var presets: Array[String] = ["none"]
	var preset_text := []
	for k: String in PRESETS:
		presets.append(k)
		preset_text.append("%s (%s: %s)" % [k, PRESETS[k]["title"], PRESETS[k]["description"]])
	var speakers: Array[String] = ["none"]
	var speaker_text := []
	for k: String in SPEAKERS:
		speakers.append(k)
		speaker_text.append("%s (%s)" % [k, SPEAKERS[k]["description"]])
	return {
		"kind": "screen",
		"description": "The chain of stages between the film and the viewer: a source (a film print's weave, "
				+ "tilt, dust and flicker; a tape's wobble, bleed and tear; a broadcast's interlace), the "
				+ "transmission (snow, a ghost, a weak signal), the display (a mechanical-scan set, a CRT with "
				+ "curvature, round corners, a mask and glass, a flat panel) and the sound through a small "
				+ "speaker. A preset sets a whole era. With a picture stage on, the film is drawn in the room "
				+ "instead of the headset's film layer: one per room.",
		"params": {
			"preset": {"type": "enum", "values": presets, "default": "none", "live": true,
					"description": "a whole chain at once; the document's own values win: " + "; ".join(preset_text)},
			"source": {"type": "enum", "values": SOURCES, "default": "none", "live": true,
					"description": "where the picture comes from: none, film (a print), tape, broadcast"},
			"weave": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "motion": {"max": 1.0},
					"description": "film: gate weave, the picture's unsteady drift (1: about 0.3 % of its height)"},
			"tilt": {"type": "float", "min": -2.0, "max": 2.0, "default": 0.0, "live": true, "motion": {"max": 2.0},
					"description": "film: the picture turned this many degrees on the screen (a crooked projector)"},
			"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"flicker": true, "steady": 0.0, "description": "the lamp's flicker: the light wavers by up "
					+ "to 3.5 %, slower than 3 times a second (off with Flickering lights off)"},
			"dust": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: specks of dust, a new few each frame"},
			"scratches": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: thin scratches running down the print"},
			"hotspot": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: the lamp's bright middle, the corners darker"},
			"tracking": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"motion": {"max": 1.0}, "description": "tape: the lines' slow sideways wobble"},
			"head_switch": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: the torn, noisy last lines at the bottom"},
			"chroma_bleed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: the colour smeared and late, to the right"},
			"tape_noise": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: noise in the picture and paler colour"},
			"interlace": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "broadcast: the two fields' lines, one after the other"},
			"lines": {"type": "int", "min": 30, "max": 1200, "default": 576, "live": true,
					"description": "the picture's lines (scanlines, interlace, the grain of the snow)"},
			"snow": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: aerial noise, the snow of a weak channel"},
			"ghost": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: a faint second picture to the right (the signal's echo)"},
			"ghost_shift": {"type": "float", "min": 0.005, "max": 0.08, "default": 0.03, "live": true,
					"description": "how far right the ghost is, as a fraction of the width"},
			"weak": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: a weak signal (paler, flatter, more snow)"},
			"display": {"type": "enum", "values": DISPLAYS, "default": "none", "live": true,
					"description": "the set: none, mechanical (a 1930 mechanical-scan set's few glowing lines), "
					+ "crt (a picture tube), panel (a flat panel)"},
			"curvature": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"description": "crt: how much the tube's face bulges"},
			"corner": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35, "live": true,
					"description": "crt: the round corners (1: a radius of half the height)"},
			"mask": {"type": "enum", "values": MASKS, "default": "shadow", "live": true,
					"description": "crt: the phosphors' mask: none (black and white), shadow (dot triads), grille "
					+ "(an aperture grille's stripes), slot"},
			"mask_pitch": {"type": "float", "min": 100.0, "max": 1200.0, "default": 420.0, "live": true,
					"description": "crt: the mask's triads across the width (fades out where finer than the "
					+ "headset can show)"},
			"mask_strength": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "crt: how much the mask shows"},
			"scanlines": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "crt: the dark gaps between the lines"},
			"glass": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"description": "crt and panel: the glass's reflection, a soft light that moves as the head moves"},
			"mech_lines": {"type": "int", "min": 12, "max": 120, "default": 30, "live": true,
					"description": "mechanical: the lines across the picture"},
			"panel_grid": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "panel: the gaps between the pixels (fades out where finer than the headset "
					+ "can show)"},
			"panel_pixels": {"type": "int", "min": 320, "max": 3840, "default": 1366, "live": true,
					"description": "panel: its pixels across"},
			"panel_bleed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "panel: the backlight through the dark scenes, most at the corners"},
			"colour": {"type": "float", "min": 0.0, "max": 1.5, "default": 1.0, "live": true,
					"description": "the picture's colour: 0 black and white, 1 as it is, more richer"},
			"tint": {"type": "color", "default": [1.0, 1.0, 1.0], "live": true,
					"description": "the set's tint (a black and white tube's blue-white, a warm one)"},
			"gain": {"type": "float", "min": 0.5, "max": 1.5, "default": 1.0, "live": true, "brightness": true,
					"description": "the picture's brightness"},
			"speaker": {"type": "enum", "values": speakers, "default": "none", "live": true,
					"description": "the film's sound through a small speaker: " + "; ".join(speaker_text)},
		},
		"actions": {"glitch": "a moment's trouble: a tape's tracking tears, a broadcast's snow swells, a print "
				+ "jumps in the gate (args: seconds, default 0.6, at most 3)"},
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0},
	}


var attached := false
## The speaker in use now ("none" or one of SPEAKERS).
var speaker_now := "none"
var _material: ShaderMaterial
## The screen's uniforms copied: name -> the value last copied.
var _names: Array[String] = []
var _copied := {}
var _given := {}
var _flat: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _weave := Vector2.ZERO
var _weave_target := Vector2.ZERO
var _flick := 0.0
var _flick_target := 0.0
var _flick_t := 0.0
var _frame := -1.0
var _clock := 0.0
## [x, strength, seconds left] per scratch.
var _scratches: Array = []
var _field := 0.0
var _glitch := 0.0
var _glitch_len := 0.6
var _film_send_was := &"Master"


func setup() -> void:
	_rng.seed = hash(id)
	_given = _document_params()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	for u: Dictionary in SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		if not n.begins_with("pr_"):
			_names.append(n)
	for i in 4:
		_scratches.append([-1.0, 0.0, 0.0])
	_material.set_shader_parameter("pr_aspect", 16.0 / 9.0)
	_apply()


## The parameters the document gives this system (a value or a binding): they win over the preset.
func _document_params() -> Dictionary:
	if host == null:
		return {}
	for entry: Dictionary in host.doc.get("systems", []):
		if str(entry.get("id", entry["system"])) == id and entry.get("params") is Dictionary:
			return (entry["params"] as Dictionary).duplicate()
	return {}


## A parameter as it acts now: the document's (or its binding's, or a cue's on it), else the preset's (with the
## room's Motion and Flickering lights settings), else the default.
func value(param: String) -> Variant:
	if _given.has(param) or param == "preset":
		return params[param]
	var preset: Dictionary = PRESETS.get(str(params.get("preset", "none")), {}).get("params", {})
	if not preset.has(param):
		return params[param]
	var v: Variant = preset[param]
	var ps := param_spec(param)
	if ps.has("motion") and host != null:
		v = float(v) * clampf(float(host.setting("motion") if host.setting("motion") != null else 1.0), 0.0, 1.0)
	if bool(ps.get("flicker", false)) and host != null and host.setting("flicker") == false:
		v = ps.get("steady", 0.0)
	if ps["type"] == "color":
		return RoomSchemaRef.to_color(v)
	return v


static var _spec_cache := {}


## One parameter's spec (spec() built once).
static func param_spec(param: String) -> Dictionary:
	if _spec_cache.is_empty():
		_spec_cache = spec()
	return _spec_cache["params"].get(param, {})


func _f(param: String) -> float:
	return float(value(param))


## Whether a picture stage is on (the film is then drawn in the room).
func picture_on() -> bool:
	return str(value("source")) != "none" or str(value("display")) != "none" or _f("snow") > 0.0 \
			or _f("ghost") > 0.0 or _f("weak") > 0.0 or not is_equal_approx(_f("colour"), 1.0) \
			or not color_value("tint").is_equal_approx(Color.WHITE) or not is_equal_approx(_f("gain"), 1.0)


func color_value(param: String) -> Color:
	var v: Variant = value(param)
	return v if v is Color else RoomSchemaRef.to_color(v)


func material() -> ShaderMaterial:
	return _material


func _param_changed(_param: String, _value: Variant) -> void:
	if _material != null:
		_apply()


func act(action: String, args: Dictionary) -> void:
	if action == "glitch":
		_glitch_len = clampf(float(args.get("seconds", 0.6)), 0.1, 3.0)
		_glitch = _glitch_len


## Every uniform of the stages from the parameters as they act now (the per-frame ones in tick()).
func _apply() -> void:
	var m := _material
	var source := SOURCES.find(str(value("source")))
	var display := DISPLAYS.find(str(value("display")))
	m.set_shader_parameter("pr_source", maxi(source, 0))
	m.set_shader_parameter("pr_display", maxi(display, 0))
	m.set_shader_parameter("pr_dust", _f("dust"))
	m.set_shader_parameter("pr_hotspot", _f("hotspot"))
	m.set_shader_parameter("pr_bleed", _f("chroma_bleed"))
	m.set_shader_parameter("pr_tape_noise", _f("tape_noise"))
	m.set_shader_parameter("pr_interlace", _f("interlace"))
	m.set_shader_parameter("pr_lines", float(value("lines")))
	m.set_shader_parameter("pr_ghost_shift", _f("ghost_shift"))
	m.set_shader_parameter("pr_weak", _f("weak"))
	m.set_shader_parameter("pr_curvature", _f("curvature"))
	m.set_shader_parameter("pr_corner", _f("corner"))
	m.set_shader_parameter("pr_mask", maxi(MASKS.find(str(value("mask"))), 0))
	m.set_shader_parameter("pr_mask_pitch", _f("mask_pitch"))
	m.set_shader_parameter("pr_mask_strength", _f("mask_strength"))
	m.set_shader_parameter("pr_scanlines", _f("scanlines"))
	m.set_shader_parameter("pr_glass", _f("glass"))
	m.set_shader_parameter("pr_mech_lines", float(value("mech_lines")))
	m.set_shader_parameter("pr_panel_grid", _f("panel_grid"))
	m.set_shader_parameter("pr_panel_pixels", float(value("panel_pixels")))
	m.set_shader_parameter("pr_panel_bleed", _f("panel_bleed"))
	m.set_shader_parameter("pr_colour", _f("colour"))
	var t := color_value("tint")
	m.set_shader_parameter("pr_tint", Vector3(t.r, t.g, t.b))
	m.set_shader_parameter("pr_gain", _f("gain"))
	_apply_turn()
	_apply_glitch()


## The tilt and the overscan that keeps its corners off the screen (film only).
func _apply_turn(aspect := -1.0) -> void:
	if aspect <= 0.0:
		aspect = float(_material.get_shader_parameter("pr_aspect"))
	var a := deg_to_rad(_f("tilt")) if str(value("source")) == "film" else 0.0
	var fill := cos(absf(a)) + maxf(aspect, 1.0 / maxf(aspect, 0.01)) * sin(absf(a))
	_material.set_shader_parameter("pr_turn", Vector4(cos(a), sin(a), -sin(a), cos(a)) / fill)


## The parameters a glitch swells, now.
func _apply_glitch() -> void:
	var g := clampf(_glitch / maxf(_glitch_len, 0.01), 0.0, 1.0)
	var source := str(value("source"))
	_material.set_shader_parameter("pr_tracking", minf(_f("tracking") + (3.0 * g if source == "tape" else 0.0), 4.0))
	_material.set_shader_parameter("pr_head_switch", minf(_f("head_switch") + (g if source == "tape" else 0.0), 2.0))
	_material.set_shader_parameter("pr_snow", minf(_f("snow") + (0.5 * g if source == "broadcast" else 0.0), 1.0))
	_material.set_shader_parameter("pr_ghost", _f("ghost"))


func tick(delta: float) -> void:
	if _material == null:
		return
	var main := main_node()
	_attach(main, picture_on())
	_apply_speaker(str(value("speaker")))
	if not attached and main != null:
		return
	_clock += delta
	if _glitch > 0.0:
		_glitch = maxf(_glitch - delta, 0.0)
		_apply_glitch()
	var source := str(value("source"))
	# The film frame: from the film's position while one plays (the dust holds still on a pause), else the clock.
	var frame := floorf(_clock * FILM_FPS)
	if main != null and main.player.has_source():
		frame = floorf(float(main.player.get_position()) * FILM_FPS)
	var new_frame := frame != _frame
	_frame = frame
	_material.set_shader_parameter("pr_frame", fmod(frame, 997.0))
	if source == "film":
		_step_weave(new_frame)
		if new_frame:
			_step_scratches(1.0 / FILM_FPS)
	else:
		_material.set_shader_parameter("pr_weave", Vector2.ZERO)
	_step_flicker(delta)
	if _f("interlace") > 0.0:
		_field = 1.0 - _field
		_material.set_shader_parameter("pr_field", _field)
	if main != null:
		_copy_uniforms(main)


func _step_weave(new_frame: bool) -> void:
	var w := _f("weave")
	var g := clampf(_glitch / maxf(_glitch_len, 0.01), 0.0, 1.0)
	if w <= 0.0 and g <= 0.0:
		_weave = Vector2.ZERO
	elif new_frame:
		# A slow random walk towards a new target a few times a second, a little jitter each frame (as the
		# projector feature's weave, scripts/env/projector.gd); a glitch jumps it up for a moment.
		var amp := WEAVE_MAX * maxf(w, 3.0 * g)
		if _weave.distance_to(_weave_target) < amp * 0.05 or _rng.randf() < 3.0 / FILM_FPS:
			_weave_target = Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * amp
		_weave = _weave.lerp(_weave_target, 0.3)
		_weave +=Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amp * 0.1
	_material.set_shader_parameter("pr_weave", _weave)


func _step_scratches(dt: float) -> void:
	var s := _f("scratches")
	var xs := Vector4(-1, -1, -1, -1)
	var amps := Vector4.ZERO
	for i in 4:
		var sc: Array = _scratches[i]
		sc[2] = float(sc[2]) - dt
		if float(sc[2]) <= 0.0:
			sc[1] = 0.0
			if s > 0.0 and _rng.randf() < s * 0.03:
				sc[0] = _rng.randf_range(0.05, 0.95)
				sc[1] = _rng.randf_range(0.3, 0.8) * s
				sc[2] = _rng.randf_range(0.5, 4.0)
		else:
			sc[0] = clampf(float(sc[0]) + _rng.randf_range(-0.0004, 0.0004), 0.0, 1.0)
		xs[i] = float(sc[0])
		amps[i] = float(sc[1])
	_material.set_shader_parameter("pr_scratch_x", xs)
	_material.set_shader_parameter("pr_scratch_a", amps)


func _step_flicker(delta: float) -> void:
	var f := _f("flicker")
	if f <= 0.0:
		_flick = 0.0
		_material.set_shader_parameter("pr_flicker", 1.0)
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick_t = FLICKER_STEP
		_flick_target = _rng.randf_range(-1.0, 1.0)
	_flick = lerpf(_flick, _flick_target, 1.0 - exp(-delta / FLICKER_TAU))
	_material.set_shader_parameter("pr_flicker", 1.0 + f * FLICKER_DEPTH * _flick)


## The flicker's gain now (tests).
func flicker_gain() -> float:
	return float(_material.get_shader_parameter("pr_flicker"))


# --- The screen -------------------------------------------------------------------------------------------------------

## The screen's flat mesh draws with this material while a picture stage is on; the film layer steps aside.
func _attach(main: Node, on: bool) -> void:
	if main == null or main.get("screen") == null:
		return
	if on == attached:
		return
	var screen: Node3D = main.screen
	var flat := screen.get_node_or_null("Flat") as MeshInstance3D
	if flat == null:
		return
	var layer: Node = main.features.get("film_layer") if main.get("features") != null else null
	if on:
		_flat = flat
		_copied.clear()
		_copy_uniforms(main)
		flat.material_override = _material
		if layer != null and layer.has_method("request_scene"):
			layer.call("request_scene", _request_key(), true)
	else:
		_detach_screen(main)
	attached = on


func _detach_screen(main: Node) -> void:
	if _flat != null and is_instance_valid(_flat) and _flat.material_override == _material:
		_flat.material_override = main.screen.material if main != null else null
	_flat = null
	var layer: Node = null
	if main != null and is_instance_valid(main) and main.get("features") != null and is_instance_valid(main.features):
		layer = main.features.get("film_layer")
	if layer != null and is_instance_valid(layer) and layer.has_method("request_scene"):
		layer.call("request_scene", _request_key(), false)
	attached = false


## Whether the picture has noise of its own (a tape, a broadcast, snow, a mechanical set): the deband stays off.
func noisy() -> bool:
	return str(value("source")) in ["tape", "broadcast"] or str(value("display")) == "mechanical" \
			or _f("snow") > 0.0 or _f("weak") > 0.0


func _request_key() -> String:
	return "presentation:%d" % get_instance_id()


## The screen's own uniforms (the picture, the projection, the controls) that changed since the last frame, and the
## picture's aspect. The deband stays off under noise (the noise hides the bands, and it saves eight samples).
func _copy_uniforms(main: Node) -> void:
	var src: ShaderMaterial = main.screen.material
	var no_deband := noisy()
	for n in _names:
		var v: Variant = src.get_shader_parameter(n)
		if n == "pc_deband" and no_deband:
			v = 0.0
		if _copied.has(n) and typeof(_copied[n]) == typeof(v) and _copied[n] == v:
			continue
		_copied[n] = v
		_material.set_shader_parameter(n, v)
	var size: Vector2 = main.screen.get_flat_size()
	var aspect := size.x / maxf(size.y, 0.001)
	if not is_equal_approx(aspect, float(_material.get_shader_parameter("pr_aspect"))):
		_material.set_shader_parameter("pr_aspect", aspect)
		_apply_turn(aspect)


# --- The speaker ------------------------------------------------------------------------------------------------------

## The film's sound through `speaker` ("none": straight to Master, as always).
func _apply_speaker(speaker: String) -> void:
	if not SPEAKERS.has(speaker):
		speaker = "none"
	if speaker == speaker_now:
		return
	EnvAudio.ensure_buses()
	var bus := speaker_bus()
	var film := AudioServer.get_bus_index(EnvAudio.FILM)
	if bus < 0 or film < 0:
		return
	while AudioServer.get_bus_effect_count(bus) > 0:
		AudioServer.remove_bus_effect(bus, 0)
	if speaker == "none":
		AudioServer.lock()
		AudioServer.set_bus_send(film, _film_send_was)
		AudioServer.unlock()
		speaker_now = speaker
		return
	var s: Dictionary = SPEAKERS[speaker]
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = float(s["high"])
	hp.db = (int(s["slope"]) - 1) as AudioEffectFilter.FilterDB
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = float(s["low"])
	lp.db = (int(s["slope"]) - 1) as AudioEffectFilter.FilterDB
	var eq := AudioEffectEQ6.new()
	for i in 6:
		eq.set_band_gain_db(i, float(s["eq"][i]))
	var fx: Array[AudioEffect] = [hp, lp, eq]
	if float(s["drive"]) > 0.0:
		var d := AudioEffectDistortion.new()
		d.mode = AudioEffectDistortion.MODE_WAVESHAPE
		d.drive = float(s["drive"])
		fx.append(d)
	if float(s["width"]) < 1.0:
		var w := AudioEffectStereoEnhance.new()
		w.pan_pullout = float(s["width"])
		fx.append(w)
	for e in fx:
		AudioServer.add_bus_effect(bus, e)
	if speaker_now == "none":
		var was := AudioServer.get_bus_send(film)
		_film_send_was = was if was != SPEAKER_BUS else &"Master"
	AudioServer.lock()
	AudioServer.set_bus_send(film, SPEAKER_BUS)
	AudioServer.unlock()
	speaker_now = speaker


## The speaker's bus, made once just before Film (a bus sends only to one before it); -1 without a Film bus.
static func speaker_bus() -> int:
	var i := AudioServer.get_bus_index(SPEAKER_BUS)
	if i >= 0:
		return i
	var film := AudioServer.get_bus_index(EnvAudio.FILM)
	if film < 1:
		return -1
	AudioServer.lock()
	AudioServer.add_bus(film)
	AudioServer.set_bus_name(film, SPEAKER_BUS)
	AudioServer.set_bus_send(film, &"Master")
	AudioServer.unlock()
	return AudioServer.get_bus_index(SPEAKER_BUS)


func _exit_tree() -> void:
	_apply_speaker("none")
	var main := main_node()
	if attached or _flat != null:
		_detach_screen(main)
