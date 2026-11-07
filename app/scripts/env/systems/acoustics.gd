extends "res://scripts/env/systems/env_system.gd"

## The room's own sound character (docs/environments.md, "Sound and music"): a reverb for the room's sounds, so the
## piano rings in a shopfront's tin box, a concrete hall answers with an echo and a stone nave holds a long tail.
##
## The room's sounds (sound_bed, music) play on BUS ("Environment room"), which sends to Environment: they are ducked
## under the film and follow the Environment sound slider like every room sound. This system sets the reverb on BUS
## (an AudioEffectReverb: room size from rt60, damping, wet, predelay and its echo). Without it, BUS is dry.
##
## The film is never coloured by it unless the room asks: with `film` on (off by default), sound_room() gives spatial
## audio (scripts/play/spatial_audio.gd, the binaural renderer's room) the same rt60, wet and wall reflection, so the
## film's speakers in the room ring with it too. The document's own `acoustics` section still goes over it
## (env_host.gd sound_room()). Spatial audio reads the room again as it changes; its renderer is not changed here.
##
##   Acoustics.ensure_bus() -> StringName     static: BUS, made once under Environment
##   reverb() -> AudioEffectReverb            the effect on BUS (tests)
##   values() -> Dictionary                   {rt60, damping, wet, predelay_ms, echo, reflect, film_wet} in use

const EnvAudio := preload("res://scripts/env/env_audio.gd")

const BUS := "Environment room"
## The engine's reverb measured (test_env_acoustics.gd's tail, T30 of a tick, wet only, damping 0.5): the tail's
## rt60 in seconds at room size 0, 0.1 .. 1. It can't be shorter than about 0.5 s or longer than about 6 s.
const TAIL_SECONDS: Array[float] = [0.52, 0.59, 0.65, 0.74, 0.87, 0.99, 1.17, 1.43, 1.89, 2.81, 6.07]
## Damping lengthens the measured tail a little (the highs go first, so the peak is lower): x (1 + this x (d - 0.5)).
const DAMPING_TAIL := 0.32
## The engine's predelay is at least this (ms).
const PREDELAY_MIN := 20.0
## The presets: rt60 (s), damping, wet (the room's sounds), predelay (ms), echo (the predelay's feedback), reflect
## (the walls for the film's spatial audio), film_wet (its reverb's share).
const PRESETS := {
	"neutral": {"rt60": 0.3, "damping": 0.6, "wet": 0.0, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.2,
			"film_wet": 0.3},
	"small_room": {"rt60": 0.35, "damping": 0.7, "wet": 0.12, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.25,
			"film_wet": 0.3},
	"cinema": {"rt60": 0.7, "damping": 0.6, "wet": 0.18, "predelay_ms": 25.0, "echo": 0.0, "reflect": 0.3,
			"film_wet": 0.5},
	"shopfront": {"rt60": 0.9, "damping": 0.3, "wet": 0.25, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.45,
			"film_wet": 0.5},
	"concrete_hall": {"rt60": 2.4, "damping": 0.25, "wet": 0.32, "predelay_ms": 60.0, "echo": 0.35, "reflect": 0.6,
			"film_wet": 0.6},
	"stone_nave": {"rt60": 5.0, "damping": 0.45, "wet": 0.4, "predelay_ms": 80.0, "echo": 0.1, "reflect": 0.55,
			"film_wet": 0.7},
	"ice": {"rt60": 1.1, "damping": 0.1, "wet": 0.25, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.6,
			"film_wet": 0.5},
	"hull": {"rt60": 1.4, "damping": 0.2, "wet": 0.3, "predelay_ms": 20.0, "echo": 0.15, "reflect": 0.7,
			"film_wet": 0.5},
	"vehicle": {"rt60": 0.15, "damping": 0.85, "wet": 0.06, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.2,
			"film_wet": 0.2},
	"outdoors": {"rt60": 0.2, "damping": 0.5, "wet": 0.04, "predelay_ms": 90.0, "echo": 0.0, "reflect": 0.0,
			"film_wet": 0.15},
	"vacuum": {"rt60": 0.05, "damping": 1.0, "wet": 0.0, "predelay_ms": 20.0, "echo": 0.0, "reflect": 0.0,
			"film_wet": 0.1},
}
const KEYS: Array[String] = ["rt60", "damping", "wet", "predelay_ms", "echo", "reflect", "film_wet"]

## The system that set the reverb last (the room on show): another's leaving does not take it off.
static var _active: Object = null


static func spec() -> Dictionary:
	return {
		"kind": "sound",
		"description": "The room's own sound character: a reverb for the room's sounds (beds, instruments) from a "
				+ "preset (a shopfront's tin box, an echoey concrete hall, a stone nave's long tail, ice, a steel "
				+ "hull, open air, the silence of a vacuum) with its numbers to change. The film keeps its own mix "
				+ "unless film is on.",
		"params": {
			"preset": {"type": "enum", "values": PRESETS.keys(), "default": "neutral",
					"description": "the room's character; the numbers below at -1 take the preset's"},
			"rt60": {"type": "float", "min": -1.0, "max": 6.0, "default": -1.0, "live": true,
					"description": "seconds the reverb takes to die away by 60 dB (the engine's reverb: 0.5 to 6); -1: "
					+ "the preset's"},
			"damping": {"type": "float", "min": -1.0, "max": 1.0, "default": -1.0, "live": true,
					"description": "how much the walls soak up the highs (0 bright stone or ice, 1 soft); -1: the "
					+ "preset's"},
			"wet": {"type": "float", "min": -1.0, "max": 1.0, "default": -1.0, "live": true,
					"description": "how much reverb the room's sounds take; -1: the preset's"},
			"predelay_ms": {"type": "float", "min": -1.0, "max": 300.0, "default": -1.0, "live": true,
					"description": "milliseconds before the first reflection (a big hall's distance); -1: the "
					+ "preset's"},
			"echo": {"type": "float", "min": -1.0, "max": 0.9, "default": -1.0, "live": true,
					"description": "a distinct echo (the first reflection fed back); -1: the preset's"},
			"film": {"type": "bool", "default": false, "live": true,
					"description": "the film's own sound takes this room too (spatial audio's room: rt60, wet, the "
					+ "walls). Off by default: the film keeps its own mix"},
			"reflect": {"type": "float", "min": -1.0, "max": 1.0, "default": -1.0, "live": true,
					"description": "with film on: how much the walls reflect the film's speakers; -1: the preset's"},
			"film_wet": {"type": "float", "min": -1.0, "max": 1.0, "default": -1.0, "live": true,
					"description": "with film on: the film's reverb share; -1: the preset's"},
		},
		"actions": {},
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0, "voices": 0},
		"provides": ["sound_room"],
	}


## BUS under Environment (made once, dry until an acoustics system sets it).
static func ensure_bus() -> StringName:
	EnvAudio.ensure_buses()
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, StringName(EnvAudio.ENVIRONMENT))
		var r := AudioEffectReverb.new()
		r.dry = 1.0
		r.wet = 0.0
		AudioServer.add_bus_effect(i, r, 0)
		AudioServer.set_bus_effect_enabled(i, 0, false)
	return StringName(BUS)


static func _bus_reverb() -> AudioEffectReverb:
	var i := AudioServer.get_bus_index(BUS)
	if i < 0:
		return null
	return AudioServer.get_bus_effect(i, 0) as AudioEffectReverb


## The engine's room size for a reverb time at this damping, from the measured tails (between two, on a log scale).
static func room_size_for(rt60: float, damping := 0.5) -> float:
	var t := maxf(rt60, 0.01) / (1.0 + DAMPING_TAIL * (clampf(damping, 0.0, 1.0) - 0.5))
	if t <= TAIL_SECONDS[0]:
		return 0.0
	var n := TAIL_SECONDS.size()
	for i in range(1, n):
		if t <= TAIL_SECONDS[i]:
			var f := log(t / TAIL_SECONDS[i - 1]) / log(TAIL_SECONDS[i] / TAIL_SECONDS[i - 1])
			return (i - 1 + f) / float(n - 1)
	return 1.0


func setup() -> void:
	ensure_bus()
	_apply()


func values() -> Dictionary:
	var p: Dictionary = PRESETS.get(str(params.get("preset", "neutral")), PRESETS["neutral"])
	var out := {}
	for k: String in KEYS:
		var v := float(params.get(k, -1.0))
		out[k] = v if v >= 0.0 else float(p[k])
	return out


func reverb() -> AudioEffectReverb:
	return _bus_reverb()


func _param_changed(_param: String, _value: Variant) -> void:
	_apply()


func _apply() -> void:
	var r := _bus_reverb()
	if r == null:
		return
	var v := values()
	r.damping = clampf(float(v["damping"]), 0.0, 1.0)
	r.room_size = room_size_for(float(v["rt60"]), r.damping)
	r.wet = clampf(float(v["wet"]), 0.0, 1.0)
	r.dry = 1.0
	r.spread = 1.0
	r.hipass = 0.1
	r.predelay_msec = maxf(float(v["predelay_ms"]), PREDELAY_MIN)
	r.predelay_feedback = clampf(float(v["echo"]), 0.0, 0.9)
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(BUS), 0, r.wet > 0.0)
	_active = self


## Spatial audio's room for the film: only with film on.
func sound_room() -> Dictionary:
	if not bool(params.get("film", false)):
		return {}
	var v := values()
	var reflect := float(v["reflect"])
	return {"rt60": maxf(float(v["rt60"]), 0.05), "wet": float(v["film_wet"]),
			"reflect": [reflect, reflect, reflect, reflect, reflect, reflect]}


func _exit_tree() -> void:
	if _active == self:
		_active = null
		var i := AudioServer.get_bus_index(BUS)
		if i >= 0:
			AudioServer.set_bus_effect_enabled(i, 0, false)
