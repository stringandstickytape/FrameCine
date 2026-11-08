extends Node3D

## Pre-show (ideas #37): in rooms with curtains, a film that opens at its start sits behind closed curtains; on play
## they open (OPEN_SECONDS) while the lights go down, and at the end they close again. The lights are room light
## following playback (#20, scripts/env/light_follow.gd); with that off, the pre-show dims the room itself (to its
## play level) while the curtains open, and brings it back as they close.
## Curtains: two heavy panels just in front of the flat screen, a little bigger than it, gathering to the sides.
## Rooms with curtains: CURTAIN_ROOMS, or an environment with `has_curtains` true. Not for 180 / 360.
##
##   enabled                [preshow] enabled (default on)
##   openness               0 closed .. 1 open
##   available() -> bool    this room has curtains (and the screen is flat)
##   open_curtains(seconds), close_curtains(seconds)   (the intermission, #39, uses these)
##   signal changed(openness)

signal changed(openness: float)

const ENV_SHADER := preload("res://shaders/env_unlit.gdshader")
const CURTAIN_ROOMS := ["cinema", "home_theatre"]
const OPEN_SECONDS := 4.0
const CLOSE_SECONDS := 3.0
## Each panel gathers to this fraction of its width when open.
const GATHERED := 0.1
const MARGIN := 0.35
const FACTOR := "preshow"
## A room whose cue parts the curtains: the pre-show parts them itself if the cue has not within this long of play.
const CUE_GRACE := 4.0

var main: Node3D
var enabled := true
var openness := 1.0
var _target := 1.0
var _rate := 0.0
var _left: MeshInstance3D
var _right: MeshInstance3D
var _dimmed := false
var _material: ShaderMaterial
## The app's own curtains: red velvet. A room may give its own (env_room.gd curtain_colour, since 2026-11-08).
const CURTAIN_COLOUR := Color(0.42, 0.05, 0.07)
var _playing_for := 0.0


func _ready() -> void:
	top_level = true
	enabled = bool(main.settings.get_value("preshow", "enabled", true))
	var m := ShaderMaterial.new()
	m.shader = ENV_SHADER
	m.set_shader_parameter("albedo", CURTAIN_COLOUR)
	_material = m
	m.set_shader_parameter("spill", 1.4)
	m.set_shader_parameter("floor_darkening", 0.2)
	_left = _panel("CurtainLeft", m)
	_right = _panel("CurtainRight", m)
	visible = false
	main.file_opened.connect(_on_file_opened)
	main.player.ended.connect(func() -> void:
		if enabled and available():
			close_curtains())
	main.environment_changed.connect(func(_id: String, _l: float) -> void:
		openness = 1.0
		_target = 1.0
		_material.set_shader_parameter("albedo", curtain_colour())
		_update())


func _panel(node_name: String, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = BoxMesh.new()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## The curtains' colour in this room: its document's, or the app's red.
func curtain_colour() -> Color:
	var c: Variant = main.env.get("curtain_colour") if main.env != null and "curtain_colour" in main.env else null
	return c if c is Color else CURTAIN_COLOUR


func available() -> bool:
	if main.mode.is_spherical() or main.env == null:
		return false
	# The room's own Pre-show setting (scripts/env/room_settings.gd).
	var rs: Node = main.features.get("room_settings")
	if rs != null and rs.value("ritual") == false:
		return false
	if "has_curtains" in main.env:
		return bool(main.env.get("has_curtains"))
	return main.env_id in CURTAIN_ROOMS


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("preshow", "enabled", on)
	if not on:
		openness = 1.0
		_target = 1.0
		_update()


func open_curtains(seconds := OPEN_SECONDS) -> void:
	_target = 1.0
	_rate = 1.0 / maxf(seconds, 0.01)
	if not main.features.light_follow.enabled:
		main.features.room_light.set_factor(FACTOR, main.features.light_follow.play_level, seconds)
		_dimmed = true


func close_curtains(seconds := CLOSE_SECONDS) -> void:
	_target = 0.0
	_rate = 1.0 / maxf(seconds, 0.01)
	if _dimmed:
		main.features.room_light.set_factor(FACTOR, 1.0, seconds)
		_dimmed = false


## The intermission (#39) keeps them closed while it runs.
func _held() -> bool:
	var i: Node = main.features.get("intermission")
	return i != null and i.active


func _on_file_opened(_path: String) -> void:
	# A film from its start waits behind the curtains; one about to resume in the middle (#7) doesn't.
	var resume: Node = main.features.resume
	var resuming: bool = resume.mode == "auto" and float(resume.position_for(_path)) > 0.0
	var at_start: bool = main.player.get_position() < 2.0 and not resuming
	if enabled and available() and at_start and _path != "":
		openness = 0.0
		_target = 0.0
	else:
		openness = 1.0
		_target = 1.0
	_update()


func _process(delta: float) -> void:
	# On play: the curtains part as the film starts (autoplay included; paused or ended, they wait). In a room whose
	# ritual parts them (its env's curtains_by_cue: scripts/env/systems/showing.gd), the cue does, and this waits for
	# it CUE_GRACE seconds.
	_playing_for = _playing_for + delta if main.player.is_playing() else 0.0
	var by_cue: bool = bool(main.env.get("curtains_by_cue")) if main.env != null and "curtains_by_cue" in main.env \
			else false
	if _target < 1.0 and main.player.is_playing() and available() and not _held() \
			and (not by_cue or _playing_for > CUE_GRACE):
		open_curtains()
	if not is_equal_approx(openness, _target):
		openness = move_toward(openness, _target, _rate * delta)
		changed.emit(openness)
	_update()


func _update() -> void:
	var show := openness < 0.999 and available()
	visible = show
	if not show:
		return
	var screen: Node3D = main.screen
	var size: Vector2 = screen.get_flat_size()
	var half := size.x * 0.5 + MARGIN
	var height := size.y + MARGIN * 2.0
	# Ease in and out: heavy cloth starts and stops slowly.
	var o := openness * openness * (3.0 - 2.0 * openness)
	var w := half * lerpf(1.0, GATHERED, o)
	for side: int in [-1, 1]:
		var p := _left if side < 0 else _right
		(p.mesh as BoxMesh).size = Vector3(w, height, 0.06)
		p.position = Vector3(side * (half - w * 0.5), 0.0, 0.0)
	var t: Transform3D = screen.global_transform
	global_transform = Transform3D(t.basis.orthonormalized(), t * Vector3(0, 0, 0.08))
