extends Node

## Screen-reactive glows (docs/assistant.md, "Effects"): screen_glow parts with "react". One node per room that has
## any. For "loudness" it reads the Master bus's peak level (no analyser, nothing added to the bus), smooths it and
## hands it to the glows' materials as react_level; for "brightness" the shader reads the bias light's copy of the
## picture on the GPU, and this node only asks the bias light to keep that copy fresh while the room is on show.
##
## Photosensitivity ceiling: the level follows the sound through two low-pass stages (TAU_S each), then may change
## by at most SLEW a second: no steeper than a sine swinging over the whole range at RoomSchema.MAX_HZ. A slow
## average (AVERAGE_S) scales it, so a quiet film reacts as much as a loud one.
##
##   add(material, source)   source "loudness" or "brightness"
##   step(peak, delta) -> level   one step with a linear peak level (tests call it directly)
##   level

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const BUS := "Master"
const FILM_BUS := "Film"
const TAU_S := 0.1
const SLEW := PI * RoomSchema.MAX_HZ
const AVERAGE_S := 3.0

var level := 0.0
var _loud: Array[ShaderMaterial] = []
var _bright := false
var _a := 0.0
var _b := 0.0
var _avg := 0.05


func add(mat: ShaderMaterial, source: String) -> void:
	if source == "loudness":
		_loud.append(mat)
	elif source == "brightness":
		_bright = true


func count() -> int:
	return _loud.size() + (1 if _bright else 0)


func _enter_tree() -> void:
	_sampling(true)
	set_process(not _loud.is_empty())


func _exit_tree() -> void:
	_sampling(false)


func _sampling(on: bool) -> void:
	if not _bright:
		return
	var tree := get_tree()
	var m: Node = tree.current_scene if tree != null else null
	if m != null and "features" in m and m.features != null and m.features.bias != null:
		m.features.bias.request_sampling(self, on)


func _process(delta: float) -> void:
	# The film's own bus (scripts/env/env_audio.gd) when there is one: the room's sounds never drive the glow.
	var bus := AudioServer.get_bus_index(FILM_BUS)
	if bus < 0:
		bus = AudioServer.get_bus_index(BUS)
	var peak := maxf(db_to_linear(AudioServer.get_bus_peak_volume_left_db(bus, 0)),
			db_to_linear(AudioServer.get_bus_peak_volume_right_db(bus, 0)))
	step(peak, delta)
	for m in _loud:
		m.set_shader_parameter("react_level", level)


func step(peak: float, delta: float) -> float:
	_avg = lerpf(_avg, peak, 1.0 - exp(-delta / AVERAGE_S))
	var target := clampf(peak / maxf(_avg * 2.0, 0.02), 0.0, 1.0)
	var k := 1.0 - exp(-delta / TAU_S)
	_a += (target - _a) * k
	_b += (_a - _b) * k
	level = move_toward(level, _b, SLEW * delta)
	return level
