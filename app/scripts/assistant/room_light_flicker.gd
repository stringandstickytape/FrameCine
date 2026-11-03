extends Node

## Firelight on an assistant's room's lights (the room document's lights[].flicker {rate, swing}): each light's energy
## wanders on four slow sines at its rate and below (1, 0.71, 0.43, 0.23 times; weights summing to 1), so it flickers
## like a flame and never strobes. The photosensitivity ceiling: rate at most RoomSchema.MAX_HZ, swing at most
## MAX_SWING of the light's own energy (clamped here as well as in the schema). One node per room, one loop.
##
##   add(light, energy, rate, swing, seed)
##   static level(t, rate, swing, seed) -> factor        1 +- swing

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

## [{light, energy, rate, swing, seed}]
var _items: Array[Dictionary] = []
var _t := 0.0


func add(light: Light3D, energy: float, rate: float, swing: float, seed: float) -> void:
	_items.append({"light": light, "energy": energy, "rate": minf(rate, RoomSchema.MAX_HZ),
			"swing": clampf(swing, 0.0, RoomSchema.MAX_SWING), "seed": seed})


func count() -> int:
	return _items.size()


static func level(t: float, rate: float, swing: float, seed: float) -> float:
	var r := minf(rate, RoomSchema.MAX_HZ)
	var s := seed * TAU
	var w := 0.35 * sin(TAU * r * t + s) + 0.3 * sin(TAU * r * 0.71 * t + s * 1.7) \
			+ 0.2 * sin(TAU * r * 0.43 * t + s * 2.3) + 0.15 * sin(TAU * r * 0.23 * t + s * 3.1)
	return 1.0 + clampf(swing, 0.0, RoomSchema.MAX_SWING) * w


func _process(delta: float) -> void:
	_t += delta
	for it in _items:
		var l: Light3D = it["light"]
		if is_instance_valid(l):
			l.light_energy = float(it["energy"]) * level(_t, it["rate"], it["swing"], it["seed"])
