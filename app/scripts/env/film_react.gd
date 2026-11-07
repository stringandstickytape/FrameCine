extends Node

## The environment reacts to the film (ideas #81): the sound drives two subtle effects.
##   bass        the low end (20-120 Hz) above a threshold sends short pulses to both controllers, like a seat
##               shaker: stronger bass, stronger pulse, at most PULSE_HZ a second
##   transients  a sudden loud jump (a thunderclap, an explosion) flashes the room light briefly, in rooms that opt in
##               (an environment's `reacts_to_film`; the drive-in under its open sky)
## Off by default ([react] enabled); `strength` scales both. The sound is read from an AudioEffectSpectrumAnalyzer
## added to the Film bus (scripts/env/env_audio.gd; Master when there is none) while it is on or a room's film
## signals ask for it (request_analysis; removed when neither), so it hears the film, whatever plays it: the stereo
## player or the cinema speakers (#21), and never the room's own sounds. With the PC audio sink (#9) the headset is
## silent and nothing reacts. The controllers' haptics setting (#32) must be on for the pulses.
##
##   enabled, set_enabled(on), strength, set_strength(v)
##   feed(bass_db, broad_db, delta)   one step with levels in dBFS (from the analyzer; tests call it directly)
##   levels() -> [bass_db, broad_db]  the last levels read (the film signals, scripts/env/env_signals.gd)
##   request_analysis(who, on)        keep the analyser on for `who` with [react] off (no pulses, no flashes)
##   pulses, flashes                  counts (tests, the overlay)
##   signal pulsed(amplitude), signal flashed(amount)

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

signal pulsed(amplitude: float)
signal flashed(amount: float)

const BUS := "Film"
const FALLBACK_BUS := "Master"
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
var _bus := ""
var _requests := {}
var _levels: Array = [-120.0, -120.0]


func _ready() -> void:
	enabled = bool(main.settings.get_value("react", "enabled", false))
	strength = clampf(float(main.settings.get_value("react", "strength", 0.5)), 0.0, 1.0)
	_attach(enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("react", "enabled", true if on else null)
	_attach(on or _requested())


## Keep the analyser on for `who` (a room's film signals) even with [react] off: levels() then has the film's levels.
func request_analysis(who: Object, on: bool) -> void:
	var was := _requested()
	if on:
		_requests[who.get_instance_id()] = true
	else:
		_requests.erase(who.get_instance_id())
	if _requested() != was:
		_attach(enabled or _requested())


func _requested() -> bool:
	for id: int in _requests.keys():
		if not is_instance_id_valid(id):
			_requests.erase(id)
	return not _requests.is_empty()


## [bass_db, broad_db]: the last levels read from the analyser.
func levels() -> Array:
	return _levels


static func bus_name() -> String:
	return BUS if AudioServer.get_bus_index(BUS) >= 0 else FALLBACK_BUS


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	main.settings.set_value("react", "strength", null if is_equal_approx(strength, 0.5) else strength)


func room_opts_in() -> bool:
	return main.env != null and bool(main.env.get("reacts_to_film"))


func _attach(on: bool) -> void:
	if on and _effect_index < 0:
		_bus = bus_name()
		var bus := AudioServer.get_bus_index(_bus)
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(bus, fx)
		_effect_index = AudioServer.get_bus_effect_count(bus) - 1
		_analyzer = AudioServer.get_bus_effect_instance(bus, _effect_index) as AudioEffectSpectrumAnalyzerInstance
	elif not on and _effect_index >= 0:
		_detach()
		_unflash()


## Takes the analyser off its bus (found by its instance: another feature's effect may have moved it).
func _detach() -> void:
	var bus := AudioServer.get_bus_index(_bus)
	if bus >= 0:
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect_instance(bus, i) == _analyzer:
				AudioServer.remove_bus_effect(bus, i)
				break
	_effect_index = -1
	_analyzer = null


func _unflash() -> void:
	var rl: Node = main.features.get("room_light")
	if rl != null:
		rl.set_factor(FACTOR, 1.0, 0.0)


func _process(delta: float) -> void:
	if _analyzer == null or not main.player.is_playing():
		return
	var bass := _db(_analyzer.get_magnitude_for_frequency_range(BASS.x, BASS.y))
	var broad := _db(_analyzer.get_magnitude_for_frequency_range(BROAD.x, BROAD.y))
	_levels = [bass, broad]
	if enabled:
		feed(bass, broad, delta)


static func _db(m: Vector2) -> float:
	return linear_to_db(maxf(maxf(m.x, m.y), 1e-6))


func feed(bass_db: float, broad_db: float, delta: float) -> void:
	_levels = [bass_db, broad_db]
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
		_detach()
