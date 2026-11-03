extends Node

## The environment reacts to the film (ideas #81): the sound drives two subtle effects.
##   bass        the low end (20-120 Hz) above a threshold sends short pulses to both controllers, like a seat
##               shaker: stronger bass, stronger pulse, at most PULSE_HZ a second
##   transients  a sudden loud jump (a thunderclap, an explosion) flashes the room light briefly, in rooms that opt in
##               (an environment's `reacts_to_film`; the drive-in under its open sky)
## Off by default ([react] enabled); `strength` scales both. The sound is read from an AudioEffectSpectrumAnalyzer
## added to the Master bus while it is on (removed when off), so it hears what the viewer hears, whatever plays it:
## the stereo player or the cinema speakers (#21). With the PC audio sink (#9) the headset is silent and nothing
## reacts. The controllers' haptics setting (#32) must be on for the pulses.
##
##   enabled, set_enabled(on), strength, set_strength(v)
##   feed(bass_db, broad_db, delta)   one step with levels in dBFS (from the analyzer; tests call it directly)
##   pulses, flashes                  counts (tests, the overlay)
##   signal pulsed(amplitude), signal flashed(amount)

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

signal pulsed(amplitude: float)
signal flashed(amount: float)

const BUS := "Master"
const BASS := Vector2(20.0, 120.0)
const BROAD := Vector2(120.0, 8000.0)
## Bass level (dBFS) where pulses start, and where they reach full amplitude.
const BASS_FLOOR_DB := -30.0
const BASS_FULL_DB := -10.0
const PULSE_HZ := 8.0
const PULSE_SECONDS := 0.06
const MAX_PULSE := 0.45
## A transient: the broadband level this far above its slow average, and at least this loud.
const JUMP_DB := 14.0
const LOUD_DB := -24.0
const AVERAGE_SECONDS := 2.0
## A flash raises the room light by at most the photosensitivity ceiling every assistant room keeps to
## (RoomSchema.MAX_SWING of its brightness; it was 2.5 times), then fades back over FLASH_FADE. FLASH_COOLDOWN keeps
## flashes far under RoomSchema.MAX_HZ.
const FLASH_FADE := 0.35
const FLASH_COOLDOWN := 1.2
const FACTOR := "film_flash"

var main: Node3D
var enabled := false
var strength := 0.5
var pulses := 0
var flashes := 0
var _avg_db := -60.0
var _since_pulse := 1.0
var _since_flash := 10.0
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _effect_index := -1


func _ready() -> void:
	enabled = bool(main.settings.get_value("react", "enabled", false))
	strength = clampf(float(main.settings.get_value("react", "strength", 0.5)), 0.0, 1.0)
	_attach(enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("react", "enabled", true if on else null)
	_attach(on)


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	main.settings.set_value("react", "strength", null if is_equal_approx(strength, 0.5) else strength)


func room_opts_in() -> bool:
	return main.env != null and bool(main.env.get("reacts_to_film"))


func _attach(on: bool) -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if on and _effect_index < 0:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(bus, fx)
		_effect_index = AudioServer.get_bus_effect_count(bus) - 1
		_analyzer = AudioServer.get_bus_effect_instance(bus, _effect_index) as AudioEffectSpectrumAnalyzerInstance
	elif not on and _effect_index >= 0:
		AudioServer.remove_bus_effect(bus, _effect_index)
		_effect_index = -1
		_analyzer = null
		_unflash()


func _unflash() -> void:
	var rl: Node = main.features.get("room_light")
	if rl != null:
		rl.set_factor(FACTOR, 1.0, 0.0)


func _process(delta: float) -> void:
	if not enabled or _analyzer == null or not main.player.is_playing():
		return
	feed(_db(_analyzer.get_magnitude_for_frequency_range(BASS.x, BASS.y)),
			_db(_analyzer.get_magnitude_for_frequency_range(BROAD.x, BROAD.y)), delta)


static func _db(m: Vector2) -> float:
	return linear_to_db(maxf(maxf(m.x, m.y), 1e-6))


func feed(bass_db: float, broad_db: float, delta: float) -> void:
	_since_pulse += delta
	_since_flash += delta
	# Bass -> a pulse to both hands, scaled between the floor and full.
	if bass_db > BASS_FLOOR_DB and _since_pulse >= 1.0 / PULSE_HZ:
		var a := clampf((bass_db - BASS_FLOOR_DB) / (BASS_FULL_DB - BASS_FLOOR_DB), 0.0, 1.0) * MAX_PULSE * strength
		var haptics: Node = main.features.get("haptics")
		if a > 0.01 and (haptics == null or bool(haptics.enabled)):
			_since_pulse = 0.0
			var scale: float = float(haptics.strength) if haptics != null else 1.0
			for hand: XRController3D in [main.left_hand, main.right_hand]:
				if hand != null:
					hand.trigger_haptic_pulse(&"haptic", 0.0, a * scale, PULSE_SECONDS, 0.0)
			pulses += 1
			pulsed.emit(a)
	# A transient against the slow average -> a flash in rooms that opt in.
	if broad_db - _avg_db > JUMP_DB and broad_db > LOUD_DB and _since_flash > FLASH_COOLDOWN and room_opts_in():
		_since_flash = 0.0
		var amount := 1.0 + RoomSchema.MAX_SWING * clampf(strength, 0.0, 1.0)
		var rl: Node = main.features.get("room_light")
		if rl != null:
			rl.set_factor(FACTOR, amount, 0.0)
			rl.set_factor(FACTOR, 1.0, FLASH_FADE)
		flashes += 1
		flashed.emit(amount)
	var k := 1.0 - exp(-delta / AVERAGE_SECONDS)
	_avg_db = lerpf(_avg_db, broad_db, k)


func _exit_tree() -> void:
	if _effect_index >= 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index(BUS), _effect_index)
