extends Node

## Haptic ticks (ideas #32): a short, light pulse on seek steps and on menu hover, through the action map's "haptic"
## output (XRController3D.trigger_haptic_pulse). Rate-limited per hand so a held stick or a fast sweep across a list
## doesn't buzz.
##
##   tick(hand, kind)     kind: "hover", "seek", "chapter", "click"; each has its own strength and length (KINDS)
##   hover(hand)          for the pane: call when the pointer moves onto a new target
##   seek_step(hand)      for callers that seek on a hand's input
##   enabled, strength    on / off and a scale on every pulse
##   pulses               count of pulses sent (tests, the stats overlay)
## Seek steps are found without a hook in the core: after every seek, the hand whose stick is past the seek threshold
## gets the tick. The d-pad's chapter and replay buttons tick on the press.
## Settings: [haptics] enabled (default on), [haptics] strength (0..1, default 1).

const KINDS := {
	"hover": [0.18, 0.012],
	"seek": [0.35, 0.02],
	"chapter": [0.5, 0.035],
	"click": [0.35, 0.03],
}
const MIN_INTERVAL_MS := 45
const SEEK_STICK := 0.75

var main: Node3D
var enabled := true
var strength := 1.0
var pulses := 0
## hand -> last pulse msec
var _last := {}


func _ready() -> void:
	enabled = bool(main.settings.get_value("haptics", "enabled", true))
	strength = clampf(float(main.settings.get_value("haptics", "strength", 1.0)), 0.0, 1.0)
	main.player.seeked.connect(_on_seeked)
	for hand: XRController3D in [main.left_hand, main.right_hand]:
		hand.button_pressed.connect(func(action: String) -> void:
			if action in ["chapter_next", "chapter_prev", "replay"]:
				tick(hand, "chapter"))


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("haptics", "enabled", on)


func set_strength(s: float) -> void:
	strength = clampf(s, 0.0, 1.0)
	main.settings.set_value("haptics", "strength", strength)


func hover(hand: XRController3D) -> void:
	tick(hand, "hover")


func seek_step(hand: XRController3D) -> void:
	tick(hand, "seek")


## Returns true when a pulse was sent.
func tick(hand: XRController3D, kind := "click") -> bool:
	if not enabled or hand == null or strength <= 0.0:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last.get(hand, -100000)) < MIN_INTERVAL_MS:
		return false
	_last[hand] = now
	var k: Array = KINDS.get(kind, KINDS["click"])
	hand.trigger_haptic_pulse(&"haptic", 0.0, float(k[0]) * strength, float(k[1]), 0.0)
	pulses += 1
	return true


func _on_seeked(_t: float) -> void:
	var jog: Node = main.features.get("jog")
	for hand: XRController3D in [main.left_hand, main.right_hand]:
		# A jog-wheel scrub (#63) ticks by the angle turned, not per seek.
		if jog != null and jog.jogging(hand):
			continue
		if absf((hand as Object).call("get_stick").x) > SEEK_STICK:
			tick(hand, "seek")
