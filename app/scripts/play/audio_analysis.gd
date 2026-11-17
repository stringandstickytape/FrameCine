extends Node

## One analysis of the film's sound for everything that reacts to it (docs/visualisers.md, "The audio frame"): the
## room's reactions (scripts/env/film_react.gd, #81, and through it the rooms' film signals) and the music card's
## visualisers (scripts/visualisers/visualiser_host.gd, #64). One AudioEffectSpectrumAnalyzer on the Film bus
## (scripts/env/env_audio.gd; Master when there is none) while anyone asks for it, and an AudioEffectCapture beside
## it while anyone asks for the waveform. Both come off the bus when the last one lets go. The room's own sounds are
## on another bus and never move anything.
##
## Each frame while on, it reads one snapshot of the sound (dBFS levels, BINS log-spaced bands, the waveform), keeps
## it in a short history, and publishes the snapshot heard now: the sound reaches the ears after the output latency,
## and after the A/V offset the viewer set for films ([audio] av_offset; negative for slow earbuds), so the visuals
## wait for it (delay(), at most MAX_DELAY). Then it smooths and maps it (the published fields below).
##
##   AudioAnalysis.shared              the one in the main scene (null in tests without it)
##   request(who, on, wave := false)   keep it on for `who` (any Object; dropped when freed); wave: the capture too
##   active() -> bool, analyzer() -> AudioEffectSpectrumAnalyzerInstance (null when off), bus
##   bass_db, broad_db                 dBFS now (20-120 Hz and 120 Hz-8 kHz, film_react's bands; not delayed)
##   fast, smooth                      PackedFloat32Array(BINS), 0..1: the bands now, and rising at once, falling
##                                     at FALL a second (the old music bars)
##   wave                              PackedFloat32Array(WAVE), -1..1, mono, from a rising zero crossing if any
##   bass, mid, treble, level          0..1, smoothed as `smooth`
##   beat                              1 at a beat (a jump in the bass), falling to 0 over BEAT_FALL; beats: the count
##   feed(snapshot, delta)             one step with a snapshot (tests; snapshot() makes one from levels)
##   spectrum_texture(), wave_texture() the bands (R fast, G smooth; BINS x 1) and the waveform (WAVE x 1) as half-float
##                                     textures, updated each frame while on once someone has asked for them

const BUS := "Film"
const FALLBACK_BUS := "Master"
const BINS := 128
## The bands' span, log-spaced: bin i covers BAND.x * (BAND.y / BAND.x) ^ (i / BINS) up to the next.
const BAND := Vector2(30.0, 16000.0)
## film_react.gd's two levels (dBFS).
const BASS_BAND := Vector2(20.0, 120.0)
const BROAD_BAND := Vector2(120.0, 8000.0)
## The summary bands.
const LOW := Vector2(20.0, 250.0)
const MID := Vector2(250.0, 2000.0)
const HIGH := Vector2(2000.0, 12000.0)
## dBFS to 0..1: FLOOR_DB is 0, FLOOR_DB + RANGE_DB is 1 (the old music bars: -60 and 54).
const FLOOR_DB := -60.0
const RANGE_DB := 54.0
## The smoothed values fall at most this fast (per second, the lerp rate the music bars had).
const FALL := 6.0
const WAVE := 512
## A beat: the low band (BEAT_BAND) this far over its slow average (BEAT_AVERAGE seconds), at least BEAT_LOUD_DB, and
## at least BEAT_GAP after the last (240 a minute at most). A simple onset, not a tempo tracker.
const BEAT_BAND := Vector2(40.0, 150.0)
const BEAT_JUMP_DB := 6.0
const BEAT_LOUD_DB := -40.0
const BEAT_AVERAGE := 0.5
const BEAT_GAP := 0.25
const BEAT_FALL := 0.3
const MAX_DELAY := 0.5

static var shared: Node

var main: Node3D
var bus := ""
var bass_db := -120.0
var broad_db := -120.0
var fast := PackedFloat32Array()
var smooth := PackedFloat32Array()
var wave := PackedFloat32Array()
var bass := 0.0
var mid := 0.0
var treble := 0.0
var level := 0.0
var beat := 0.0
var beats := 0
## Seconds of history the published snapshot is behind (delay()); tests may set delay_override.
var delay_override := -1.0

var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _spectrum_fx: AudioEffectSpectrumAnalyzer
var _capture: AudioEffectCapture
var _requests := {}
var _wave_requests := {}
var _history: Array[Dictionary] = []
var _beat_avg := -60.0
var _since_beat := 10.0
var _raw_wave := PackedFloat32Array()
var _spectrum_img: Image
var _spectrum_tex: ImageTexture
var _wave_img: Image
var _wave_tex: ImageTexture
var _edges := PackedFloat32Array()
var _since_purge := 0.0


func _init() -> void:
	fast.resize(BINS)
	smooth.resize(BINS)
	wave.resize(WAVE)
	_raw_wave.resize(WAVE * 2)
	_edges.resize(BINS + 1)
	for i in BINS + 1:
		_edges[i] = BAND.x * pow(BAND.y / BAND.x, float(i) / BINS)


func _enter_tree() -> void:
	shared = self


func _exit_tree() -> void:
	if shared == self:
		shared = null
	_set_spectrum(false)
	_set_capture(false)


static func bus_name() -> String:
	return BUS if AudioServer.get_bus_index(BUS) >= 0 else FALLBACK_BUS


## Keeps the analysis on for `who` (and the waveform with `wave`); off again when everyone has let go or been freed.
func request(who: Object, on: bool, want_wave := false) -> void:
	var id := who.get_instance_id()
	if on:
		_requests[id] = true
		if want_wave:
			_wave_requests[id] = true
		else:
			_wave_requests.erase(id)
	else:
		_requests.erase(id)
		_wave_requests.erase(id)
	_apply()


func active() -> bool:
	return _spectrum_fx != null


## The analyser's instance now, found again by its effect each time: any change to the bus's effects (the capture
## going on, another feature's effect) makes the engine build every instance on the bus afresh, and an old one hears
## nothing.
func analyzer() -> AudioEffectSpectrumAnalyzerInstance:
	if _spectrum_fx == null:
		return null
	var b := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(b) if b >= 0 else 0:
		if AudioServer.get_bus_effect(b, i) == _spectrum_fx:
			_spectrum = AudioServer.get_bus_effect_instance(b, i)
			return _spectrum
	return null


func _apply() -> void:
	for d: Dictionary in [_requests, _wave_requests]:
		for id: int in d.keys():
			if not is_instance_id_valid(id):
				d.erase(id)
	_set_spectrum(not _requests.is_empty())
	_set_capture(not _wave_requests.is_empty())


func _set_spectrum(on: bool) -> void:
	if on and _spectrum_fx == null:
		bus = bus_name()
		_spectrum_fx = AudioEffectSpectrumAnalyzer.new()
		_spectrum_fx.buffer_length = 0.1
		_spectrum_fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		var b := AudioServer.get_bus_index(bus)
		AudioServer.add_bus_effect(b, _spectrum_fx)
		_history.clear()
	elif not on and _spectrum_fx != null:
		_remove(_spectrum_fx)
		_spectrum = null
		_spectrum_fx = null
		_rest()


func _set_capture(on: bool) -> void:
	if on and _capture == null and _spectrum_fx != null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.1
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), _capture)
	elif not on and _capture != null:
		_remove(_capture)
		_capture = null
		wave.fill(0.0)


## Takes an effect off our bus, found by identity: another feature's effect may have moved it.
func _remove(fx: AudioEffect) -> void:
	var b := AudioServer.get_bus_index(bus)
	if b < 0:
		return
	for i in AudioServer.get_bus_effect_count(b):
		if AudioServer.get_bus_effect(b, i) == fx:
			AudioServer.remove_bus_effect(b, i)
			return


## Everything back to silence (off, or nothing playing).
func _rest() -> void:
	bass_db = -120.0
	broad_db = -120.0
	fast.fill(0.0)
	smooth.fill(0.0)
	wave.fill(0.0)
	bass = 0.0
	mid = 0.0
	treble = 0.0
	level = 0.0
	beat = 0.0
	_history.clear()
	if _spectrum_tex != null:
		_update_textures()


## Seconds the published snapshot waits behind the analysis: the output latency less the films' A/V offset.
func delay() -> float:
	if delay_override >= 0.0:
		return delay_override
	var offset := 0.0
	if main != null and main.get("player") != null:
		offset = float(main.player.av_offset)
	return clampf(AudioServer.get_output_latency() - offset, 0.0, MAX_DELAY)


func _process(delta: float) -> void:
	if _spectrum_fx == null:
		return
	# Holders freed without letting go are dropped once a second (and the effects come off when none is left).
	_since_purge += delta
	if _since_purge >= 1.0:
		_since_purge = 0.0
		_apply()
		if _spectrum_fx == null:
			return
	var sp := analyzer()
	# Paused, the bus carries silence and reads as such: no need to ask the player.
	var snap := _read(sp) if sp != null else snapshot(-120.0, -120.0, PackedFloat32Array())
	bass_db = snap["bass_db"]
	broad_db = snap["broad_db"]
	var now := Time.get_ticks_usec() / 1e6
	snap["t"] = now
	_history.append(snap)
	# The newest snapshot at least delay() old; older ones are dropped.
	var due := now - delay()
	var pick := _history[0]
	while _history.size() > 1 and float(_history[1]["t"]) <= due:
		_history.pop_front()
		pick = _history[0]
	feed(pick, delta)


## A snapshot from the analyser (its instance now) and the capture.
func _read(sp: AudioEffectSpectrumAnalyzerInstance) -> Dictionary:
	var mags := PackedFloat32Array()
	mags.resize(BINS)
	for i in BINS:
		mags[i] = _db(sp.get_magnitude_for_frequency_range(_edges[i], _edges[i + 1]))
	var snap := {
		"bass_db": _db(sp.get_magnitude_for_frequency_range(BASS_BAND.x, BASS_BAND.y)),
		"broad_db": _db(sp.get_magnitude_for_frequency_range(BROAD_BAND.x, BROAD_BAND.y)),
		"low_db": _db(sp.get_magnitude_for_frequency_range(LOW.x, LOW.y)),
		"mid_db": _db(sp.get_magnitude_for_frequency_range(MID.x, MID.y)),
		"high_db": _db(sp.get_magnitude_for_frequency_range(HIGH.x, HIGH.y)),
		"beat_db": _db(sp.get_magnitude_for_frequency_range(BEAT_BAND.x, BEAT_BAND.y)),
		"bins_db": mags,
	}
	if _capture != null:
		snap["wave"] = _read_wave()
	return snap


## The newest WAVE samples (mono), from the first rising zero crossing in the older half when there is one, so a
## steady tone stands still.
func _read_wave() -> PackedFloat32Array:
	var n := _capture.get_frames_available()
	if n > 0:
		var buf := _capture.get_buffer(n)
		var keep := mini(n, WAVE * 2)
		var shift := keep
		# Slide the window along by `keep` and append the newest `keep` frames.
		for i in WAVE * 2 - shift:
			_raw_wave[i] = _raw_wave[i + shift]
		for i in keep:
			var f := buf[n - keep + i]
			_raw_wave[WAVE * 2 - keep + i] = (f.x + f.y) * 0.5
	var start := WAVE
	for i in range(1, WAVE):
		if _raw_wave[i - 1] < 0.0 and _raw_wave[i] >= 0.0:
			start = i
			break
	return _raw_wave.slice(start, start + WAVE)


## A snapshot from levels in dBFS (tests): the summary bands at `level_db`, every bin at `level_db` or from `bins_db`.
static func snapshot(level_db: float, beat_db: float, bins_db: PackedFloat32Array) -> Dictionary:
	var bins := bins_db
	if bins.size() != BINS:
		bins = PackedFloat32Array()
		bins.resize(BINS)
		bins.fill(level_db)
	return {"bass_db": beat_db, "broad_db": level_db, "low_db": level_db, "mid_db": level_db, "high_db": level_db,
			"beat_db": beat_db, "bins_db": bins}


## One step with a snapshot: maps, smooths and finds beats.
func feed(snap: Dictionary, delta: float) -> void:
	var bins: PackedFloat32Array = snap["bins_db"]
	var k := clampf(delta * FALL, 0.0, 1.0)
	for i in BINS:
		var v := to_unit(bins[i])
		fast[i] = v
		smooth[i] = v if v > smooth[i] else lerpf(smooth[i], v, k)
	bass = _follow(bass, to_unit(snap["low_db"]), k)
	mid = _follow(mid, to_unit(snap["mid_db"]), k)
	treble = _follow(treble, to_unit(snap["high_db"]), k)
	level = _follow(level, to_unit(snap["broad_db"]), k)
	if snap.has("wave"):
		wave = snap["wave"]
	# Beats: the low band jumping over its slow average.
	var b: float = snap["beat_db"]
	_since_beat += delta
	beat = maxf(beat - delta / BEAT_FALL, 0.0)
	if b - _beat_avg > BEAT_JUMP_DB and b > BEAT_LOUD_DB and _since_beat >= BEAT_GAP:
		_since_beat = 0.0
		beat = 1.0
		beats += 1
	_beat_avg = lerpf(_beat_avg, b, 1.0 - exp(-delta / BEAT_AVERAGE))
	if _spectrum_tex != null:
		_update_textures()


static func to_unit(db: float) -> float:
	return clampf((db - FLOOR_DB) / RANGE_DB, 0.0, 1.0)


static func _follow(was: float, v: float, k: float) -> float:
	return v if v > was else lerpf(was, v, k)


static func _db(m: Vector2) -> float:
	return linear_to_db(maxf(maxf(m.x, m.y), 1e-6))


## The bands as a BINS x 1 texture: R the bands now (fast), G smoothed.
func spectrum_texture() -> Texture2D:
	if _spectrum_tex == null:
		_update_textures()
	return _spectrum_tex


## The waveform as a WAVE x 1 texture: R the sample, -1..1.
func wave_texture() -> Texture2D:
	if _wave_tex == null:
		_update_textures()
	return _wave_tex


func _update_textures() -> void:
	var rg := PackedFloat32Array()
	rg.resize(BINS * 2)
	for i in BINS:
		rg[i * 2] = fast[i]
		rg[i * 2 + 1] = smooth[i]
	_spectrum_img = Image.create_from_data(BINS, 1, false, Image.FORMAT_RGF, rg.to_byte_array())
	_spectrum_img.convert(Image.FORMAT_RGH)
	_wave_img = Image.create_from_data(WAVE, 1, false, Image.FORMAT_RF, wave.to_byte_array())
	_wave_img.convert(Image.FORMAT_RH)
	if _spectrum_tex == null:
		_spectrum_tex = ImageTexture.create_from_image(_spectrum_img)
		_wave_tex = ImageTexture.create_from_image(_wave_img)
	else:
		_spectrum_tex.update(_spectrum_img)
		_wave_tex.update(_wave_img)
