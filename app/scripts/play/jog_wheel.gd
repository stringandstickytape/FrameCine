extends Node

## Jog-wheel scrub (ideas #63): circle a thumbstick round its rim to scrub, like a jog wheel: clockwise forward,
## anticlockwise back, `seconds_per_turn` per full turn; a light haptic tick every TICK_DEGREES; a card under the screen
## shows where you are. Let the stick go back to the middle to stop.
## It shares the stick with the flick-seek and the distance push (main._update_sticks): when the stick reaches the rim
## it waits up to DECIDE_SECONDS; if the stick sweeps round by ENGAGE_DEGREES meanwhile it is a jog and the jog keeps
## the stick until it is let go, otherwise the stick goes to main's actions as before (a flick then seeks a beat
## later). Not while the pane is in the way (main asks the pane first).
##
##   enabled, seconds_per_turn       [jog] enabled (default on), seconds_per_turn (10..600, default 60)
##   on_stick(hand, stick, delta) -> bool   main calls this per hand per frame; true: the jog has the stick
##   jogging(hand) -> bool, target   (seconds, the position being scrubbed to)
##   signal changed(jogging, target)

const ScreenCard := preload("res://scripts/play/screen_card.gd")

signal changed(jogging: bool, target: float)

const RIM := 0.8
const RELEASE := 0.35
const DECIDE_SECONDS := 0.15
const ENGAGE_DEGREES := 25.0
const TICK_DEGREES := 15.0
## Seeks while scrubbing at most this often (the decoder seeks from a keyframe each time).
const SEEK_INTERVAL := 0.12

var main: Node3D
var enabled := true
var seconds_per_turn := 60.0
var target := 0.0
var card: ScreenCard
## hand -> {state: "idle" | "deciding" | "passed" | "jog", t, start, last, swept, tick, since_seek}
var _hands := {}


func _ready() -> void:
	enabled = bool(main.settings.get_value("jog", "enabled", true))
	seconds_per_turn = clampf(float(main.settings.get_value("jog", "seconds_per_turn", 60.0)), 10.0, 600.0)
	card = ScreenCard.new()
	card.name = "JogCard"
	card.main = main
	add_child(card)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("jog", "enabled", on)


func set_seconds_per_turn(s: float) -> void:
	seconds_per_turn = clampf(s, 10.0, 600.0)
	main.settings.set_value("jog", "seconds_per_turn", seconds_per_turn)


func jogging(hand: Variant) -> bool:
	return _hands.has(hand) and _hands[hand]["state"] == "jog"


func on_stick(hand: Variant, stick: Vector2, delta: float) -> bool:
	if not enabled or not main.player.has_source() or not main.player.can_seek():
		_hands.erase(hand)
		return false
	var s: Dictionary = _hands.get(hand, {"state": "idle"})
	var mag := stick.length()
	# Stick angle, clockwise from up (y up = forward on the stick).
	var angle := atan2(stick.x, stick.y)
	match str(s["state"]):
		"idle":
			if mag < RIM:
				return false
			s = {"state": "deciding", "t": 0.0, "start": angle, "last": angle, "swept": 0.0, "tick": 0.0, "since_seek": 0.0,
					"flick": stick.x}
			_hands[hand] = s
			return true
		"passed":
			# A flick or a push: main has it until the stick comes back to the middle.
			if mag < RELEASE:
				_hands.erase(hand)
			return false
		"deciding":
			if mag < RELEASE:
				# Back to the middle before deciding: a quick flick, which main didn't see. Do its seek for it.
				_hands.erase(hand)
				if absf(float(s["flick"])) > 0.75:
					main.player.seek_relative(main.SEEK_STEP * signf(float(s["flick"])))
				return false
			if absf(stick.x) > absf(float(s["flick"])):
				s["flick"] = stick.x
			var d := wrapf(angle - float(s["last"]), -PI, PI)
			s["last"] = angle
			s["swept"] = float(s["swept"]) + d
			s["t"] = float(s["t"]) + delta
			if absf(rad_to_deg(float(s["swept"]))) >= ENGAGE_DEGREES:
				s["state"] = "jog"
				target = main.player.get_position()
				_scrub(hand, s, float(s["swept"]), delta)
				return true
			if float(s["t"]) > DECIDE_SECONDS:
				s["state"] = "passed"
				return false
			return true
		"jog":
			if mag < RELEASE:
				_hands.erase(hand)
				main.player.seek(target)
				card.hide_card()
				changed.emit(false, target)
				return true
			if mag < RIM * 0.75:
				return true
			var d := wrapf(angle - float(s["last"]), -PI, PI)
			s["last"] = angle
			_scrub(hand, s, d, delta)
			return true
	return false


func _scrub(hand: Variant, s: Dictionary, d_angle: float, delta: float) -> void:
	var duration: float = main.player.get_duration()
	target += d_angle / TAU * seconds_per_turn
	target = clampf(target, 0.0, duration if duration > 0.0 else INF)
	s["tick"] = float(s["tick"]) + absf(rad_to_deg(d_angle))
	if float(s["tick"]) >= TICK_DEGREES:
		s["tick"] = fmod(float(s["tick"]), TICK_DEGREES)
		if hand is XRController3D:
			main.features.haptics.tick(hand, "seek")
	s["since_seek"] = float(s["since_seek"]) + delta
	if float(s["since_seek"]) >= SEEK_INTERVAL:
		s["since_seek"] = 0.0
		main.player.seek(target)
	card.show_card(_clock(target), "%s%d s per turn" % ["" if duration <= 0.0 else _clock(duration) + "  |  ",
			roundi(seconds_per_turn)], "below")
	changed.emit(true, target)


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]
