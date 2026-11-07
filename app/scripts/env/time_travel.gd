extends Node

## Time travel through television (docs/environments.md, "Time travel"): one film, and while it plays the room moves
## forward through the history of television, an era at a time, from the oldest set to the newest. Each era is a
## shipped TV room (EnvLibrary.category_of() "tv" whose id starts "tv_"), in the order of its year (tv_1930 ...
## tv_2005, then tv_today, then tv_future); the Pillow Fort and the other rooms are not eras.
##
##   start(minutes)   on: minutes between eras (0: spread over the rest of the film); in a room that is not an era,
##                    the first era at once
##   stop()           off; the room stays as it is
##   advance()        the next era now (the last era turns it off)
##   active, minutes, remaining() (seconds to the next era, -1 when off), eras()
##   signal changed(active)
## The countdown runs only while the film plays; a pause holds it. It turns itself off on a new file, at the end of
## the film and when the viewer picks a room that is not an era. The film plays on through each change: only the room
## changes. Setting: [time_travel] minutes (the last choice).

signal changed(active: bool)

## The choices: 0 spreads the eras over the film.
const CHOICES: Array[int] = [0, 5, 10, 15]
const PREFIX := "tv_"
## The shortest time in an era when spread over a short film.
const MIN_SECONDS := 60.0

const EnvLibrary := preload("res://scripts/env/env_library.gd")

var main: Node3D
var active := false
var minutes := 0
var _left := 0.0
## Set while this changes the room, so its own change doesn't turn it off.
var _moving := false


func _ready() -> void:
	minutes = int(main.settings.get_value("time_travel", "minutes", 0))
	if not (minutes in CHOICES):
		minutes = 0
	main.file_opened.connect(func(_p: String) -> void: stop())
	main.player.ended.connect(stop)
	if main.has_signal("environment_changed"):
		main.environment_changed.connect(_on_environment_changed)


## The eras, oldest first.
func eras() -> Array[String]:
	var out: Array[String] = []
	for e: Array in main.get_environment_list():
		var id := str(e[0])
		if id.begins_with(PREFIX) and EnvLibrary.category_of(id) == "tv":
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return year_of(a) < year_of(b))
	return out


## An era's year from its id: tv_1953 1953; tv_today (or tv_present) after every year, tv_future after that.
static func year_of(id: String) -> int:
	var rest := id.trim_prefix(PREFIX)
	if rest.is_valid_int():
		return int(rest)
	if rest in ["present", "today", "now"]:
		return 3000
	if rest == "future":
		return 4000
	var digits := ""
	for c in rest:
		if c >= "0" and c <= "9":
			digits += c
	return int(digits) if digits != "" else 5000


func start(p_minutes: int) -> void:
	minutes = p_minutes if p_minutes in CHOICES else 0
	main.settings.set_value("time_travel", "minutes", minutes)
	var list := eras()
	if list.is_empty():
		stop()
		return
	active = true
	if not (str(main.env_id) in list):
		_go(list[0])
	_left = _interval()
	changed.emit(true)


func stop() -> void:
	if not active:
		return
	active = false
	_left = 0.0
	changed.emit(false)


## The next era now; the last era turns time travel off (the room stays).
func advance() -> void:
	var list := eras()
	var i := list.find(str(main.env_id))
	if i < 0 or i + 1 >= list.size():
		stop()
		return
	_go(list[i + 1])
	if i + 2 >= list.size():
		# The newest era: time travel has arrived.
		stop()
	else:
		_left = _interval()


func remaining() -> float:
	return _left if active else -1.0


## Seconds in each era: the choice, or the rest of the film shared by the eras still to come.
func _interval() -> float:
	if minutes > 0:
		return minutes * 60.0
	var list := eras()
	var left_eras := maxi(list.size() - 1 - list.find(str(main.env_id)), 1)
	var rest := float(main.player.get_duration()) - float(main.player.get_position()) \
			if main.player.has_method("get_duration") else 0.0
	if rest <= 0.0:
		return 10.0 * 60.0
	return maxf(rest / float(left_eras + 1), MIN_SECONDS)


func _go(id: String) -> void:
	_moving = true
	main.set_environment(id)
	_moving = false


func _on_environment_changed(_id: String, _light_scale: float) -> void:
	if active and not _moving and not (str(main.env_id) in eras()):
		stop()


func _process(delta: float) -> void:
	if not active or not bool(main.player.is_playing()):
		return
	_left -= delta
	if _left <= 0.0:
		advance()
