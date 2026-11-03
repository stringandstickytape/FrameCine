extends Node

## Intermission (ideas #39): a long film with chapters stops once at the chapter boundary nearest its middle, like a
## roadshow presentation: the curtains close (rooms that have them, #37), the room lights come up (paused), and a
## plain card in front of the screen says "Intermission" and the time left; then the curtains open and the film goes
## on. Pressing play (or resume_now()) ends it early. No logos, no music: a quiet pause. Off by default.
##
##   enabled, minutes, min_film_minutes   [intermission] enabled (off), minutes (1..20, default 10),
##                                        min_film_minutes (default 100: shorter films never stop)
##   point() -> seconds or -1             where this film would stop (the chapter start nearest half way, within
##                                        35..65 % of the film)
##   active, remaining, done (this showing already had its intermission)
##   begin(), resume_now()
##   signal changed(active, remaining)

const ScreenCard := preload("res://scripts/play/screen_card.gd")

signal changed(active: bool, remaining: float)

var main: Node3D
var enabled := false
var minutes := 10.0
var min_film_minutes := 100.0
var active := false
var remaining := 0.0
var done := false
var card: ScreenCard
var _last_pos := -1.0


func _ready() -> void:
	enabled = bool(main.settings.get_value("intermission", "enabled", false))
	minutes = clampf(float(main.settings.get_value("intermission", "minutes", 10.0)), 1.0, 20.0)
	min_film_minutes = float(main.settings.get_value("intermission", "min_film_minutes", 100.0))
	card = ScreenCard.new()
	card.name = "IntermissionCard"
	card.main = main
	add_child(card)
	main.file_opened.connect(func(_p: String) -> void:
		_end(false)
		done = false
		_last_pos = -1.0)
	main.player.playing_changed.connect(func(playing: bool) -> void:
		if playing and active:
			_end(true))


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("intermission", "enabled", on)


func set_minutes(m: float) -> void:
	minutes = clampf(m, 1.0, 20.0)
	main.settings.set_value("intermission", "minutes", minutes)


func point() -> float:
	var duration: float = main.player.get_duration()
	if duration < min_film_minutes * 60.0:
		return -1.0
	var best := -1.0
	for c: Dictionary in main.features.chapters.chapters:
		var s := float(c.get("start", 0.0))
		if s < duration * 0.35 or s > duration * 0.65:
			continue
		if best < 0.0 or absf(s - duration * 0.5) < absf(best - duration * 0.5):
			best = s
	return best


func begin() -> void:
	if active:
		return
	active = true
	done = true
	remaining = minutes * 60.0
	main.player.pause()
	var preshow: Node = main.features.get("preshow")
	if preshow != null and preshow.enabled and preshow.available():
		preshow.close_curtains()
	card.show_card("Intermission", _line(), "centre")
	changed.emit(true, remaining)


func resume_now() -> void:
	if active:
		_end(true)


func _end(play: bool) -> void:
	if not active:
		return
	active = false
	card.hide_card()
	var preshow: Node = main.features.get("preshow")
	if preshow != null and preshow.enabled and preshow.available():
		preshow.open_curtains()
	if play and not main.player.is_playing():
		main.player.play()
	changed.emit(false, 0.0)


func _line() -> String:
	var s := maxi(ceili(remaining), 0)
	return "The film continues in %d:%02d" % [s / 60, s % 60]


func _process(delta: float) -> void:
	if active:
		remaining -= delta
		card.set_line(_line())
		if remaining <= 0.0:
			_end(true)
		return
	if not enabled or done or not main.player.has_source() or not main.player.is_playing():
		_last_pos = -1.0
		return
	var pos: float = main.player.get_position()
	var p := point()
	# Crossed while playing on (a seek over it doesn't count).
	if p > 0.0 and _last_pos >= 0.0 and _last_pos < p and pos >= p and pos - _last_pos < 2.0:
		begin()
	_last_pos = pos
