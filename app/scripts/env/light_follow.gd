extends Node

## Room light follows playback (ideas #20): the room dims while the film plays and comes back up on pause, when
## nothing plays, or while the menu is open. It is a factor on the shared room light (scripts/env/room_light.gd), so
## the user's own room light setting stays as it is and the sleep timer's dimming adds to it.
##
##   enabled      on / off ([room] follow_playback, default on); off puts the light back
##   play_level   the factor while playing ([room] play_level, default 0.35)
##   set_enabled(on), set_play_level(v)
## Fades: DIM_SECONDS down, UP_SECONDS up. The void environment has no light to change; 180 / 360 hide the room.

const DIM_SECONDS := 2.0
const UP_SECONDS := 0.8
const FACTOR := "playback"

var main: Node3D
var enabled := true
var play_level := 0.35
var _target := -1.0


func _ready() -> void:
	enabled = bool(main.settings.get_value("room", "follow_playback", true))
	play_level = clampf(float(main.settings.get_value("room", "play_level", 0.35)), 0.0, 1.0)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("room", "follow_playback", on)
	_target = -1.0


func set_play_level(v: float) -> void:
	play_level = clampf(v, 0.0, 1.0)
	main.settings.set_value("room", "play_level", play_level)
	_target = -1.0


## The factor the room should head for now.
func wanted() -> float:
	if not enabled:
		return 1.0
	# The room's own "Dim during the film" (scripts/env/room_settings.gd), and the level a room dims to (a room built
	# from a document: its light system's dimmed_level; -1 is this one's).
	var rs: Node = main.features.get("room_settings") if main.get("features") != null else null
	if rs != null and not bool(rs.value("dim")):
		return 1.0
	var watching: bool = main.player.has_source() and main.player.is_playing() and not main.menu_shown
	var level := play_level
	if main.env != null and main.env.has_method("dimmed_level") and float(main.env.dimmed_level()) >= 0.0:
		level = float(main.env.dimmed_level())
	return level if watching else 1.0


func _process(_delta: float) -> void:
	var w := wanted()
	if is_equal_approx(w, _target):
		return
	var down := _target < 0.0 or w < _target
	_target = w
	main.features.room_light.set_factor(FACTOR, w, DIM_SECONDS if down else UP_SECONDS)
