extends RefCounted

## The room's synthesised sounds (docs/environments.md, "The audio buses" and "Sound and music"): made here from sines
## and noise, so they are ours (no samples, no licence). Each is made at the film's reference level (REFERENCE_DB RMS
## over its sounding part), so the Environment bus's default (-18 dB) puts it 18 dB under the film. Cached per name.
## Static; preload to use.
##   EnvSynth.stream(name) -> AudioStreamWAV     NAMES; the beds (LOOPS) loop without a seam
##   EnvSynth.make(name) -> AudioStreamWAV       the same, made anew and not cached: safe on a worker thread
##   EnvSynth.put(name, stream), cached(name)    the cache (the main thread)
##   EnvSynth.rms_db(stream) -> float            its RMS level (dBFS); loudest_db(stream, seconds): its loudest window
##   EnvSynth.piano_note(midi, detune_cents)     a player piano's note (scripts/env/systems/music.gd), cached
##   EnvSynth.organ_note(midi, stop)             a pipe organ's note: an attack and a looped steady tone, cached
## The first seven (chime .. creak) are the foundation's, made exactly as before: the cinema's chime is unchanged.

const RATE := 44100
## The film's reference level: dialogue in a film mixed for the home is about -20 dBFS RMS.
const REFERENCE_DB := -20.0
const NAMES: Array[String] = ["chime", "gong", "rumble", "tick", "noise", "whale", "creak",
		"projector", "wall_rumble", "cicadas", "moped", "train", "huskies", "hull_creak", "radiator", "rain_glass",
		"rain_leaves", "gas_hiss", "bird", "purr", "crickets", "fire", "drips", "wind", "hum", "deep_hum", "fountain",
		"clock", "tube_whine", "three_bells", "candle", "ice_creak", "vcr", "tape_load", "switch_clunk", "valve_hum",
		"crt_off", "channel_clunk", "sonar", "bubbles", "far_car", "scops_owl"]
## Seconds each lasts (a loop: its loop's length).
const LENGTHS := {"chime": 2.5, "gong": 4.0, "rumble": 3.0, "tick": 0.08, "noise": 4.0, "whale": 5.0, "creak": 1.2,
		"projector": 4.0, "wall_rumble": 8.0, "cicadas": 6.0, "moped": 8.0, "train": 40.0, "huskies": 7.0,
		"hull_creak": 3.5, "radiator": 16.0, "rain_glass": 6.0, "rain_leaves": 6.0, "gas_hiss": 4.0, "bird": 1.2,
		"purr": 4.0, "crickets": 6.0, "fire": 8.0, "drips": 8.0, "wind": 12.0, "hum": 4.0, "deep_hum": 8.0,
		"fountain": 6.0, "clock": 4.0, "tube_whine": 2.0, "three_bells": 3.2, "candle": 0.9, "ice_creak": 2.6,
		"vcr": 4.5, "tape_load": 8.0, "switch_clunk": 0.6, "valve_hum": 8.0, "crt_off": 1.4, "channel_clunk": 0.45,
		"sonar": 3.0, "bubbles": 6.0, "far_car": 34.0, "scops_owl": 9.0}
## The sounds that loop (beds); the rest play once.
const LOOPS: Array[String] = ["noise", "projector", "wall_rumble", "cicadas", "radiator", "rain_glass", "rain_leaves",
		"gas_hiss", "crickets", "fire", "drips", "wind", "hum", "deep_hum", "fountain", "clock", "tube_whine", "bubbles"]
## Sample rates below RATE for the far and low sounds (less to make, nothing lost above their band).
const RATES := {"wall_rumble": 22050, "train": 22050, "huskies": 22050, "radiator": 22050, "moped": 32000,
		"hull_creak": 32000, "purr": 22050, "crickets": 32000, "fire": 32000, "drips": 32000, "wind": 22050,
		"hum": 22050, "deep_hum": 22050, "fountain": 32000, "candle": 32000, "ice_creak": 32000, "vcr": 32000,
		"tape_load": 32000, "switch_clunk": 32000, "valve_hum": 22050, "crt_off": 32000, "channel_clunk": 32000,
		"sonar": 32000, "bubbles": 32000, "far_car": 22050, "scops_owl": 32000}
## The new sounds' peaks stay under this (sparse clicks would clip at the reference RMS).
const PEAK := 0.89
## Seconds of a loop's crossfade (its end into its start).
const CROSSFADE := 0.25
## Music: the piano's notes at these MIDI pitches, the rest by pitch_scale (at most 2 semitones away).
const PIANO_RATE := 32000
const PIANO_STEP := 4
const PIANO_LOW := 33
const PIANO_HIGH := 97
const ORGAN_RATE := 44100
## An organ stop's harmonics (amplitude by harmonic number, from 1).
const STOPS := {
	"flute": [1.0, 0.22, 0.1, 0.42, 0.04, 0.07, 0.0, 0.03],
	"principal": [1.0, 0.55, 0.36, 0.25, 0.18, 0.12, 0.08, 0.06, 0.04, 0.03],
	"full": [1.0, 0.72, 0.38, 0.52, 0.22, 0.32, 0.12, 0.3, 0.08, 0.12, 0.05, 0.16, 0.04, 0.06, 0.03, 0.08],
	"theatre": [1.0, 0.16, 0.07, 0.03],
}

static var _cache := {}
static var _notes := {}


static func stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var w := make(sound)
	if w != null:
		_cache[sound] = w
	return w


static func cached(sound: String) -> bool:
	return _cache.has(sound)


static func put(sound: String, w: AudioStreamWAV) -> void:
	if w != null and not _cache.has(sound):
		_cache[sound] = w


static func make(sound: String) -> AudioStreamWAV:
	if not (sound in NAMES):
		return null
	if NAMES.find(sound) >= 7:
		return _make_new(sound)
	var n := int(RATE * float(LENGTHS[sound]))
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	var lp := 0.0
	var lp2 := 0.0
	var b := [0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		match sound:
			"chime":
				for k: Array in [[523.25, 1.0], [1046.5, 0.4], [1568.0, 0.2], [2637.0, 0.08]]:
					v += sin(TAU * float(k[0]) * t) * float(k[1]) * exp(-t * (1.2 + float(k[0]) / 1500.0))
				v *= minf(t / 0.004, 1.0)
			"gong":
				for k: Array in [[98.0, 1.0], [147.0, 0.6], [233.0, 0.4], [311.0, 0.3], [415.0, 0.2]]:
					v += sin(TAU * float(k[0]) * t + sin(TAU * 0.7 * t) * 0.3) * float(k[1]) * exp(-t * 0.8)
				v *= minf(t / 0.01, 1.0)
			"rumble":
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.01
				lp2 += (lp - lp2) * 0.01
				v = lp2 * 40.0 * sin(PI * t / float(LENGTHS[sound]))
			"tick":
				v = rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) + sin(TAU * 2400.0 * t) * exp(-t * 200.0) * 0.5
			"noise":
				# Pink-ish noise (three one-pole stages), looped: a bed under rain, wind, a far road.
				var wn := rng.randf_range(-1.0, 1.0)
				b[0] = 0.99765 * b[0] + wn * 0.099
				b[1] = 0.963 * b[1] + wn * 0.2965
				b[2] = 0.57 * b[2] + wn * 1.0527
				v = b[0] + b[1] + b[2] + wn * 0.1848
			"whale":
				var f := 180.0 + 120.0 * sin(PI * t / float(LENGTHS[sound]))
				lp += f / RATE
				v = sin(TAU * lp) * sin(PI * t / float(LENGTHS[sound])) + sin(TAU * lp * 2.0) * 0.2
			"creak":
				var pulse := fmod(t * (30.0 + 25.0 * sin(TAU * 0.6 * t)), 1.0)
				v = (exp(-pulse * 18.0) - 0.05) * sin(PI * t / float(LENGTHS[sound]))
		s[i] = v
	# To the reference level, by the RMS of the part that sounds (over a tenth of the peak).
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	var sum := 0.0
	var count := 0
	for v in s:
		if absf(v) > peak * 0.1:
			sum += v * v
			count += 1
	var rms := sqrt(sum / maxf(count, 1))
	var gain := db_to_linear(REFERENCE_DB) / maxf(rms, 1e-9)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(s[i] * gain * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if sound == "noise":
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


## A 16-bit mono stream's RMS level over its whole length (dBFS).
static func rms_db(w: AudioStreamWAV) -> float:
	var data := w.data
	var n := data.size() / 2
	var sum := 0.0
	for i in n:
		var v := data.decode_s16(i * 2) / 32767.0
		sum += v * v
	return linear_to_db(sqrt(sum / maxf(n, 1)))


## Its loudest window of `seconds` (RMS, dBFS): a one-shot's loud part (a train passing).
static func loudest_db(w: AudioStreamWAV, seconds := 1.0) -> float:
	var data := w.data
	var n := data.size() / 2
	var win := maxi(int(w.mix_rate * seconds), 1)
	var best := 0.0
	var i := 0
	while i < n:
		var sum := 0.0
		var end := mini(i + win, n)
		for j in range(i, end):
			var v := data.decode_s16(j * 2) / 32767.0
			sum += v * v
		best = maxf(best, sum / win)
		i += win / 2
	return linear_to_db(sqrt(best)) if best > 0.0 else -120.0


## How loud it plays (dBFS at 0 dB): a loop's RMS over its length, a one-shot's loudest second. The sound_bed
## system sets its players from this, so a bed sits at its designed level whatever its peaks.
static func level_db(w: AudioStreamWAV) -> float:
	return rms_db(w) if w.loop_mode == AudioStreamWAV.LOOP_FORWARD else loudest_db(w, 1.0)


static func peak_db(w: AudioStreamWAV) -> float:
	var data := w.data
	var peak := 0
	for i in data.size() / 2:
		peak = maxi(peak, absi(data.decode_s16(i * 2)))
	return linear_to_db(peak / 32767.0) if peak > 0 else -120.0


# --- The beds and one-shots of the sound_bed system --------------------------------------------------------------------

## Filters, one sample at a time (state in a small array the caller keeps).
static func _lp(st: PackedFloat32Array, k: int, x: float, a: float) -> float:
	st[k] += (x - st[k]) * a
	return st[k]


## One-pole coefficient for a cut-off (Hz) at a rate.
static func _a(fc: float, rate: float) -> float:
	return 1.0 - exp(-TAU * fc / rate)


## A two-pole resonator: state at k, k+1; coefficients [2 r cos w, -r^2].
static func _res_c(f: float, r: float, rate: float) -> PackedFloat32Array:
	return PackedFloat32Array([2.0 * r * cos(TAU * f / rate), -r * r, 1.0 - r])


static func _res(st: PackedFloat32Array, k: int, x: float, c: PackedFloat32Array) -> float:
	var y := c[2] * x + c[0] * st[k] + c[1] * st[k + 1]
	st[k + 1] = st[k]
	st[k] = y
	return y


## The same resonator at a frequency that moves (its coefficients worked out each sample, nothing allocated).
static func _res_f(st: PackedFloat32Array, k: int, x: float, f: float, rr: float, rate: float) -> float:
	var y := (1.0 - rr) * x + 2.0 * rr * cos(TAU * f / rate) * st[k] - rr * rr * st[k + 1]
	st[k + 1] = st[k]
	st[k] = y
	return y


## Adds a small water drop at `at` seconds into s (a bubble's tone whose pitch rises as it rings, and a soft tap).
static func _plink(s: PackedFloat32Array, rate: float, lead: int, at: float, f0: float, amp: float, rise: float,
		decay: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * rate) + lead
	var ph := 0.0
	for j in int(5.0 / decay * rate):
		var i := start + j
		if i < 0:
			continue
		if i >= s.size():
			break
		var dt := float(j) / rate
		ph += f0 * (1.0 + rise * dt) / rate
		s[i] += (sin(TAU * ph) * exp(-dt * decay) + rng.randf_range(-1.0, 1.0) * exp(-dt * 1500.0) * 0.25) * amp


static func _make_new(sound: String) -> AudioStreamWAV:
	var rate := int(RATES.get(sound, RATE))
	var looped := sound in LOOPS
	var n := int(rate * float(LENGTHS[sound]))
	# A loop is made with a lead-in (the filters settle) and a tail for the crossfade.
	var lead := int(rate * 0.3) if looped else 0
	var xf := int(rate * CROSSFADE) if looped else 0
	var total := lead + n + xf
	var raw := _render(sound, rate, total, lead)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[lead + i]
	if looped:
		for i in xf:
			var f := float(i) / xf
			s[i] = s[i] * sqrt(f) + raw[lead + n + i] * sqrt(1.0 - f)
	else:
		# One-shots start and end at rest.
		var edge := mini(int(rate * 0.01), n / 4)
		for i in edge:
			s[i] *= float(i) / edge
			s[n - 1 - i] *= float(i) / edge
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	var sum := 0.0
	var count := 0
	for v in s:
		if absf(v) > peak * 0.1:
			sum += v * v
			count += 1
	var rms := sqrt(sum / maxf(count, 1))
	var gain := minf(db_to_linear(REFERENCE_DB) / maxf(rms, 1e-9), PEAK / maxf(peak, 1e-9))
	return _wav(s, gain, rate, looped)


static func _wav(s: PackedFloat32Array, gain: float, rate: int, looped: bool, loop_begin := 0) -> AudioStreamWAV:
	var n := s.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, clampi(int(s[i] * gain * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = loop_begin
		w.loop_end = n
	return w


static func _render(sound: String, rate: int, total: int, lead: int) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	var st := PackedFloat32Array()
	st.resize(32)
	var r := float(rate)
	match sound:
		"projector":
			# A projector in its booth behind: the claw's pull-down 24 times a second (a sharp click and a knock),
			# its return, the two-blade shutter's whir (48 Hz) and the motor's hum. Every period divides the loop.
			var click := _res_c(2900.0, 0.965, r)
			var body := _res_c(1250.0, 0.94, r)
			var a_whir := _a(700.0, r)
			var amp := PackedFloat32Array()
			for f in 24 * 5:
				amp.append(rng.randf_range(0.75, 1.0))
			for i in total:
				var t := float(i - lead) / r
				var tt := t + 1.0
				var frame := int(floor(tt * 24.0))
				var dt := tt - frame / 24.0
				var k: float = amp[posmod(frame, amp.size())]
				var ex := rng.randf_range(-1.0, 1.0)
				var burst := ex * (exp(-dt * 1100.0) + 0.45 * exp(-maxf(dt - 0.021, 0.0) * 1400.0)
						* (1.0 if dt > 0.021 else 0.0)) * k
				var v := _res(st, 0, burst, click) * 3.0 + _res(st, 2, burst, body) * 1.5
				v += sin(TAU * 190.0 * dt) * exp(-dt * 70.0) * 0.35 * k
				var whir := _lp(st, 4, ex, a_whir) * (0.75 + 0.25 * sin(TAU * 48.0 * tt))
				v += whir * 0.9 + sin(TAU * 100.0 * tt) * 0.05 + sin(TAU * 200.0 * tt) * 0.025
				s[i] = v
		"wall_rumble":
			# The next screen's bass through a wall: low noise under 110 Hz and two low tones that swell slowly
			# (the sound_bed's level follows film.bass).
			var a1 := _a(110.0, r)
			var a2 := _a(70.0, r)
			for i in total:
				var t := float(i - lead) / r
				var x := _lp(st, 1, _lp(st, 0, rng.randf_range(-1.0, 1.0), a1), a2)
				var swell := 0.6 + 0.4 * sin(TAU * t / 8.0) * sin(TAU * t / 4.0 + 0.7)
				s[i] = (x * 9.0 + sin(TAU * 41.0 * t) * 0.18 + sin(TAU * 55.0 * t + 1.0) * 0.12) * swell
		"cicadas":
			# A tree of cicadas on a warm night: three voices, each a buzz (narrow noise near 4-6 kHz) pulsed fast,
			# swelling and falling in turn.
			var voices := [[4300.0, 118.0, 0.0, 1], [5200.0, 92.0, 2.1, 2], [6100.0, 151.0, 4.0, 3]]
			var cs: Array = []
			for vo: Array in voices:
				cs.append(_res_c(float(vo[0]), 0.992, r))
			for i in total:
				var t := float(i - lead) / r
				var x := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				for j in 3:
					var vo: Array = voices[j]
					var pulse := maxf(sin(TAU * float(vo[1]) * t), 0.0)
					pulse *= pulse
					var chorus := 0.5 + 0.5 * sin(TAU * t * float(vo[3]) / 6.0 + float(vo[2]))
					v += _res(st, j * 2, x, cs[j]) * pulse * chorus * chorus
				s[i] = v
		"moped":
			# A small two-stroke passing at about 10 m/s, 15 m away at its closest (half-way): the firing pulses'
			# buzz, its pitch carried up and down by the passing, its brightness by the distance.
			var a_buzz := _a(2200.0, r)
			var nasal := _res_c(1150.0, 0.97, r)
			var phase := 0.0
			var length := float(total) / r
			for i in total:
				var t := float(i) / r
				var x := 10.0 * (t - length * 0.5)
				var radial := -10.0 * x / sqrt(x * x + 225.0)
				var f := (88.0 + 6.0 * sin(TAU * 0.4 * t)) * 343.0 / (343.0 - radial)
				phase = fmod(phase + f / r, 1.0)
				var pulse := 1.0 if phase < 0.18 else -0.22
				var near := 15.0 / sqrt(x * x + 225.0)
				var bright := _lp(st, 0, pulse + rng.randf_range(-0.3, 0.3), a_buzz * (0.3 + 0.7 * near))
				s[i] = (bright + _res(st, 2, pulse, nasal) * 0.6) * (0.25 + 0.75 * near)
		"far_car":
			# A big old car on the highway behind a drive-in (since 2026-11-08), 78 m off at its closest and
			# 25 m/s, crossing over the length: the tyres' roar on concrete (the slabs' joints a soft double knock
			# four times a second), a V8's low, uneven burble at cruise under it. Its pitch rides the passing
			# (Doppler); the air dulls it the farther it is. The level by distance is left to the 3D player (its
			# reach the closest distance), so only the far ends fade here.
			var length := float(total) / r
			var phase := 0.0
			var joint := 0.0
			var since := 10.0
			var a_knock := _a(260.0, r)
			var a_drone := _a(320.0, r)
			for i in total:
				var t := float(i) / r
				var x := 25.0 * (t - length * 0.5)
				var d := sqrt(x * x + 78.0 * 78.0)
				var dop := 343.0 / (343.0 + 25.0 * x / d)
				var near := 78.0 / d
				# The tyres: noise round 500 Hz (a broad resonance) and its low rumble, brighter when near.
				var wn := rng.randf_range(-1.0, 1.0)
				var a_air := _a((550.0 + 2300.0 * near * near) * dop, r)
				var roar := _res_f(st, 0, wn, 480.0 * dop, 0.86, r) * 0.9 + _lp(st, 2, wn, a_air) * 0.6
				roar = _lp(st, 3, roar, a_air)
				# The slab joints: the front then the rear wheels over each, 6 m apart.
				joint += 25.0 / 6.0 / r
				if joint >= 1.0:
					joint -= 1.0
					since = 0.0
				since += 1.0 / r
				var knock := 0.0
				for off: float in [0.0, 0.12]:
					var k := since - off
					if k >= 0.0:
						knock += exp(-k * 38.0) * sin(TAU * 62.0 * dop * k)
				knock += _lp(st, 4, wn, a_knock) * knock * 2.0
				# The V8 at about 2200 rpm: firing at 147 Hz with a lope (cylinders uneven) and its half order.
				phase = fmod(phase + 147.0 * dop / r, 8.0)
				var cyl := int(phase)
				var pulse := (1.0 if fmod(phase, 1.0) < 0.3 else -0.35) * (1.0 + 0.25 * sin(float(cyl) * 2.3))
				var drone := _lp(st, 6, _lp(st, 5, pulse, a_drone), a_drone) * 3.2
				var env := smoothstep(0.0, 8.0, t) * (1.0 - smoothstep(length - 8.0, length, t))
				s[i] = (roar * 1.0 + knock * 0.35 * near + drone * (0.35 + 0.25 * near)) * env
		"train":
			# A freight train far off: a low roll that rises and dies away over the run, the wheels on the rail
			# joints (pairs of knocks), and early on the horn's two notes, dulled by the distance.
			var a_roll := _a(160.0, r)
			var a_far := _a(1100.0, r)
			var a_knock := _a(400.0, r)
			var length := float(total) / r
			var joint := 0.0
			var since := 10.0
			var ph1 := 0.0
			var ph2 := 0.0
			for i in total:
				var t := float(i) / r
				var env := smoothstep(0.0, 12.0, t) * (1.0 - smoothstep(length - 16.0, length, t))
				var roll := _lp(st, 1, _lp(st, 0, rng.randf_range(-1.0, 1.0), a_roll), a_roll) * 7.0
				joint += 1.15 / r
				if joint >= 1.0:
					joint -= 1.0
					since = 0.0
				since += 1.0 / r
				var knock := 0.0
				for off: float in [0.0, 0.13]:
					var d := since - off
					if d >= 0.0:
						knock += exp(-d * 45.0) * (sin(TAU * 68.0 * d) + _lp(st, 2, rng.randf_range(-1.0, 1.0),
								a_knock) * 2.0)
				var horn := 0.0
				var hv := smoothstep(5.0, 5.2, t) * (1.0 - smoothstep(7.4, 7.7, t)) \
						+ smoothstep(8.1, 8.3, t) * (1.0 - smoothstep(9.3, 9.6, t))
				if hv > 0.0:
					ph1 = fmod(ph1 + 233.0 / r, 1.0)
					ph2 = fmod(ph2 + 294.0 / r, 1.0)
					horn = ((ph1 * 2.0 - 1.0) + (ph2 * 2.0 - 1.0)) * hv * 0.5
				var mix := roll * 0.8 + knock * 0.5 + horn * 0.9
				s[i] = _lp(st, 4, _lp(st, 3, mix, a_far), a_far) * env
		"huskies":
			# Huskies far off across the snow: three long howls that overlap, a few yips, an echo off the land.
			var howls := [[0.2, 3.2, 390.0, 610.0, 0.0], [1.6, 2.9, 450.0, 680.0, 1.3], [3.4, 3.0, 360.0, 560.0, 2.2],
					[5.6, 0.16, 720.0, 900.0, 0.0], [5.85, 0.14, 760.0, 940.0, 0.0], [6.2, 0.15, 700.0, 880.0, 0.0]]
			var phases := PackedFloat32Array()
			phases.resize(howls.size())
			var a_far := _a(1500.0, r)
			var delay := int(0.38 * r)
			for i in total:
				var t := float(i) / r
				var v := 0.0
				for j in howls.size():
					var h: Array = howls[j]
					var u := (t - float(h[0])) / float(h[1])
					if u < 0.0 or u > 1.0:
						continue
					var f := lerpf(float(h[2]), float(h[3]), smoothstep(0.0, 0.3, u)) \
							- (float(h[3]) - float(h[2])) * 0.4 * smoothstep(0.8, 1.0, u)
					f += sin(TAU * 5.2 * t + float(h[4])) * 7.0 * smoothstep(0.2, 0.4, u)
					phases[j] = fmod(phases[j] + f / r, 1.0)
					var p := TAU * phases[j]
					var tone := sin(p) + 0.45 * sin(2.0 * p) + 0.22 * sin(3.0 * p) + 0.1 * sin(4.0 * p)
					v += tone * sin(PI * u) * (0.6 if float(h[1]) < 0.5 else 1.0)
				v = _lp(st, 0, v, a_far)
				s[i] = v + (s[i - delay] * 0.3 if i >= delay else 0.0)
		"hull_creak":
			# A steel hull under pressure: stick-slip pulses that speed up and slow down, ringing a low groan and
			# the metal's own bright, unrelated partials; a dull knock at the start.
			var bank := [[150.0, 0.996, 1.0], [235.0, 0.995, 0.7], [610.0, 0.997, 0.35], [1340.0, 0.998, 0.2],
					[2210.0, 0.998, 0.12]]
			var cs: Array = []
			for b: Array in bank:
				cs.append(_res_c(float(b[0]), float(b[1]), r))
			var phase := 0.0
			var length := float(total) / r
			for i in total:
				var t := float(i) / r
				var rate_hz := 11.0 + 34.0 * pow(sin(PI * t / length), 2.0) + 6.0 * sin(TAU * 1.3 * t)
				phase += rate_hz / r
				var ex := 0.0
				if phase >= 1.0:
					phase -= 1.0
					ex = rng.randf_range(0.6, 1.0)
				var v := 0.0
				for j in bank.size():
					v += _res(st, j * 2, ex, cs[j]) * float(bank[j][2])
				v *= pow(sin(PI * t / length), 0.7)
				v += sin(TAU * 42.0 * t) * exp(-t * 6.0) * 0.08
				s[i] = v
		"radiator":
			# A radiator warming up: metal ticks at odd moments (now and then two close together) and the faint
			# trickle of water inside.
			var ticks: Array = []
			var t0 := 0.6
			var length := float(total - lead) / r
			while t0 < length - 0.3:
				ticks.append([t0, rng.randf_range(2600.0, 3600.0), rng.randf_range(0.5, 1.0)])
				if rng.randf() < 0.3:
					ticks.append([t0 + rng.randf_range(0.12, 0.3), rng.randf_range(2400.0, 3400.0),
							rng.randf_range(0.3, 0.7)])
				t0 += rng.randf_range(1.2, 3.6)
			var a_water := _a(900.0, r)
			var bubble := 0.0
			for i in total:
				var t := float(i - lead) / r
				var v := 0.0
				for tk: Array in ticks:
					var d := t - float(tk[0])
					if d >= 0.0 and d < 0.03:
						v += sin(TAU * float(tk[1]) * d) * exp(-d * 260.0) * float(tk[2]) \
								+ sin(TAU * 420.0 * d) * exp(-d * 120.0) * 0.4 * float(tk[2])
				if rng.randf() < 3.0 / r:
					bubble = 1.0
				bubble *= 0.9995
				var water := _lp(st, 0, rng.randf_range(-1.0, 1.0), a_water) - _lp(st, 1, rng.randf_range(-1.0, 1.0),
						_a(300.0, r))
				s[i] = v + water * 0.05 * (0.3 + bubble)
		"rain_glass":
			# Rain on a window pane: many small sharp drops (each rings one of four bright pane modes), now and then
			# a big one lower down, and the soft wash of the rain beyond.
			var modes := [_res_c(2600.0, 0.93, r), _res_c(3700.0, 0.92, r), _res_c(5200.0, 0.9, r),
					_res_c(7000.0, 0.88, r), _res_c(1500.0, 0.97, r)]
			var a_wash := _a(5000.0, r)
			var a_low := _a(900.0, r)
			for i in total:
				var x := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				var drop := rng.randf()
				var hit := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
				if drop < 70.0 / r:
					hit[rng.randi_range(0, 3)] = rng.randf_range(0.2, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
				elif drop < 74.0 / r:
					hit[4] = rng.randf_range(0.6, 1.0)
				for j in 5:
					v += _res(st, j * 2, hit[j] * 40.0, modes[j])
				var wash := _lp(st, 10, x, a_wash) - _lp(st, 11, x, a_low)
				s[i] = v + wash * 0.25
		"rain_leaves":
			# Rain on leaves: a dense soft patter (many small drops on broad, damped leaf modes), heavier drips
			# from the leaves above, the wash of the rain.
			var modes := [_res_c(900.0, 0.95, r), _res_c(1500.0, 0.94, r), _res_c(2300.0, 0.93, r),
					_res_c(3400.0, 0.92, r), _res_c(700.0, 0.985, r)]
			var a_wash := _a(3500.0, r)
			var a_low := _a(400.0, r)
			for i in total:
				var x := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				var drop := rng.randf()
				var hit := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
				if drop < 320.0 / r:
					hit[rng.randi_range(0, 3)] = rng.randf_range(0.1, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
				elif drop < 322.5 / r:
					hit[4] = rng.randf_range(0.5, 1.0)
				for j in 5:
					v += _res(st, j * 2, hit[j] * 18.0, modes[j])
				var wash := _lp(st, 10, x, a_wash) - _lp(st, 11, x, a_low)
				s[i] = v + wash * 0.5
		"gas_hiss":
			# A gas lamp's steady hiss: bright noise with a slight flutter, a soft roar of the flame under it.
			var a_hp := _a(2500.0, r)
			var a_roar := _a(300.0, r)
			var bump := _res_c(6000.0, 0.8, r)
			var flutter_a := _a(4.0, r)
			for i in total:
				var t := float(i - lead) / r
				var x := rng.randf_range(-1.0, 1.0)
				var hp := x - _lp(st, 0, x, a_hp)
				hp = hp - _lp(st, 1, hp, a_hp)
				var flutter := 1.0 + 0.06 * sin(TAU * 3.0 * t) + _lp(st, 2, rng.randf_range(-1.0, 1.0), flutter_a) * 3.0
				s[i] = (hp + _res(st, 4, x, bump) * 0.6) * flutter + _lp(st, 3, x, a_roar) * 0.4
		"bird":
			# A small songbird's call (life.gd's birds): three falling whistles, then a quick trill. Each note
			# glides from f0 to f1 under a smooth swell, with a little of its octave.
			var notes: Array = []
			var at := 0.03
			for k in 3:
				var f0 := rng.randf_range(3600.0, 4400.0) - k * 150.0
				var d := rng.randf_range(0.07, 0.11)
				notes.append([at, d, f0, f0 - rng.randf_range(900.0, 1400.0), 1.0 - k * 0.1])
				at += d + rng.randf_range(0.05, 0.08)
			at += 0.06
			var trill := rng.randf_range(4600.0, 5200.0)
			for k in 7:
				notes.append([at, 0.026, trill + 300.0, trill - 300.0, 0.55])
				at += 0.04
			var phase := PackedFloat32Array()
			phase.resize(notes.size())
			for i in total:
				var t := float(i - lead) / r
				var v := 0.0
				for j in notes.size():
					var nt: Array = notes[j]
					var u := (t - float(nt[0])) / float(nt[1])
					if u < 0.0 or u >= 1.0:
						continue
					var f := lerpf(float(nt[2]), float(nt[3]), u * u * (3.0 - 2.0 * u))
					phase[j] += f / r
					var env := pow(sin(PI * u), 2.0)
					v += (sin(TAU * phase[j]) + 0.15 * sin(TAU * 2.0 * phase[j])) * env * float(nt[4])
				s[i] = v
		"purr":
			# A cat's purr (life.gd's cat): a pulse about 25 times a second, through a low throat and chest,
			# louder on the breath out than on the breath in, two breaths.
			var throat := _res_c(140.0, 0.97, r)
			var chest := _res_c(65.0, 0.985, r)
			var a_lp := _a(500.0, r)
			var breaths := [[0.05, 1.15, 26.0, 1.0], [1.3, 0.75, 23.0, 0.55], [2.15, 1.1, 26.5, 0.95],
					[3.35, 0.6, 23.5, 0.5]]
			var pulse_phase := 0.0
			for i in total:
				var t := float(i - lead) / r
				var amp := 0.0
				var rate_hz := 25.0
				for b: Array in breaths:
					var u := (t - float(b[0])) / float(b[1])
					if u >= 0.0 and u < 1.0:
						amp = pow(sin(PI * u), 0.6) * float(b[3])
						rate_hz = float(b[2])
				pulse_phase = fmod(pulse_phase + rate_hz / r, 1.0)
				var x := rng.randf_range(-1.0, 1.0)
				var burst := x * exp(-pulse_phase * 9.0) * amp
				var v := _lp(st, 0, burst, a_lp)
				v = v * 0.6 + _res(st, 1, v, throat) * 6.0 + _res(st, 3, v, chest) * 8.0
				s[i] = v
		"crickets":
			# Field crickets on a summer night: four, each at its own pitch and steady rate, each chirp three or four
			# short syllables of a pure tone; the near one louder. Every rate divides the loop: no seam.
			var crickets := [[4600.0, 0.5, 0.0, 3, 1.0], [4250.0, 0.375, 0.11, 4, 0.6], [5000.0, 0.6, 0.27, 3, 0.45],
					[4450.0, 0.4, 0.05, 3, 0.3]]
			var syl := 0.016
			var step := 0.026
			var ph := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			for i in total:
				var t := float(i - lead) / r
				var v := 0.0
				for j in 4:
					var c: Array = crickets[j]
					var tc := fposmod(t - float(c[2]), float(c[1]))
					var k := int(tc / step)
					var u := (tc - k * step) / syl
					if k >= int(c[3]) or u >= 1.0:
						continue
					ph[j] = fmod(ph[j] + float(c[0]) * (1.0 - 0.02 * u) / r, 1.0)
					var swell := 0.8 + 0.2 * sin(TAU * t * float(j + 1) / 6.0 + j)
					v += sin(TAU * ph[j]) * pow(sin(PI * u), 2.0) * float(c[4]) * swell
				s[i] = v
		"fire":
			# A wood or coal fire in the grate: the flames' soft roar (low noise that flickers), a little hiss, and the
			# crackles: many small sharp ones and now and then a pop, each ringing one of a few modes.
			var a_roar := _a(260.0, r)
			var a_flick := _a(3.0, r)
			var a_hiss := _a(2500.0, r)
			var modes := [_res_c(1900.0, 0.9, r), _res_c(3300.0, 0.88, r), _res_c(5200.0, 0.85, r),
					_res_c(850.0, 0.95, r)]
			var env := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			var decay := PackedFloat32Array([exp(-900.0 / r), exp(-1100.0 / r), exp(-1300.0 / r), exp(-350.0 / r)])
			for i in total:
				var x := rng.randf_range(-1.0, 1.0)
				var e := rng.randf()
				if e < 14.0 / r:
					var k := rng.randi_range(0, 2)
					env[k] = maxf(env[k], rng.randf_range(0.2, 1.0))
				elif e < 14.8 / r:
					env[3] = maxf(env[3], rng.randf_range(0.6, 1.0))
				var v := 0.0
				for j in 4:
					v += _res(st, j * 2, x * env[j], modes[j]) * (6.0 if j < 3 else 4.0)
					env[j] *= decay[j]
				var flicker := clampf(0.75 + _lp(st, 8, rng.randf_range(-1.0, 1.0), a_flick) * 6.0, 0.3, 1.3)
				var roar := _lp(st, 10, _lp(st, 9, x, a_roar), a_roar) * 3.0 * flicker
				var hiss := (x - _lp(st, 11, x, a_hiss)) * 0.03 * flicker
				s[i] = v + roar + hiss
		"drips":
			# Drips after the rain: drops from leaves and a roof's edge into puddles, each a small plink, at odd
			# moments; two steady leaks among them, whose periods divide the loop.
			var t_end := float(total - lead) / r
			var tt := -float(lead) / r
			while tt < t_end:
				_plink(s, r, lead, tt, rng.randf_range(700.0, 2400.0), rng.randf_range(0.25, 1.0), 16.0, 45.0, rng)
				tt += rng.randf_range(0.08, 0.7)
			for leak: Array in [[1.6, 0.3, 1250.0, 0.7], [2.0, 1.1, 1700.0, 0.5]]:
				var k := -1
				while true:
					var at := float(leak[1]) + k * float(leak[0])
					if at > t_end:
						break
					_plink(s, r, lead, at, float(leak[2]), float(leak[3]), 14.0, 40.0, rng)
					k += 1
		"wind":
			# A soft wind past an opening: noise through a broad band that drifts with the gusts, a faint low roar, and
			# a thin whistle that comes in the strongest gusts. Every swell divides the loop.
			var a_low := _a(180.0, r)
			for i in total:
				var t := float(i - lead) / r
				var gust := 0.55 + 0.22 * sin(TAU * t / 12.0) + 0.15 * sin(TAU * t / 4.0 + 1.3) \
						+ 0.08 * sin(TAU * t / 3.0 + 0.4)
				var x := rng.randf_range(-1.0, 1.0)
				var band := _res_f(st, 0, x, 320.0 + 380.0 * gust, 0.985, r)
				var whistle := _res_f(st, 2, x, 780.0 + 90.0 * sin(TAU * t / 6.0), 0.9985, r)
				var low := _lp(st, 5, _lp(st, 4, x, a_low), a_low)
				s[i] = band * gust * gust * 2.0 + whistle * maxf(gust - 0.6, 0.0) * 6.0 + low * 2.0 * gust
		"hum":
			# A motor's hum through glass (a pool's filter pump, a fridge): the mains' hum and its harmonics, beating
			# with the motor's turning, a little water in the pipe, dulled by the pane. Whole cycles in the loop.
			var a_glass := _a(450.0, r)
			var a_water := _a(700.0, r)
			var a_water_low := _a(150.0, r)
			for i in total:
				var t := float(i - lead) / r
				var turn := 1.0 + 0.25 * sin(TAU * 24.0 * t)
				var v := (sin(TAU * 100.0 * t) + 0.5 * sin(TAU * 200.0 * t + 0.6) + 0.3 * sin(TAU * 300.0 * t + 1.1)
						+ 0.12 * sin(TAU * 400.0 * t)) * turn
				var x := rng.randf_range(-1.0, 1.0)
				var water := _lp(st, 0, x, a_water) - _lp(st, 1, x, a_water_low)
				s[i] = _lp(st, 2, v * 0.6 + water * 0.8, a_glass)
		"deep_hum":
			# The hum of the deep on a hull: low tones beating slowly against each other, with enough of their
			# harmonics to be heard on small speakers, a band of low noise (the water moving), a slow swell. Whole
			# cycles in the loop.
			var a_low := _a(140.0, r)
			for i in total:
				var t := float(i - lead) / r
				var swell := 0.75 + 0.25 * sin(TAU * t / 8.0)
				var v := sin(TAU * 55.0 * t) + sin(TAU * 55.25 * t + 0.4) * 0.8 + sin(TAU * 82.5 * t + 1.0) * 0.35 \
						+ sin(TAU * 110.0 * t + 0.2) * 0.3 + sin(TAU * 165.0 * t + 2.0) * 0.12
				var sea := _lp(st, 1, _lp(st, 0, rng.randf_range(-1.0, 1.0), a_low), a_low) * 8.0
				s[i] = (v * 0.5 + sea) * swell
		"fountain":
			# A small fountain's trickle: water falling into a basin, many small bubbles (short tones whose pitch rises
			# as they ring) over the soft splash of the fall.
			var t_end := float(total - lead) / r
			var tt := -float(lead) / r
			while tt < t_end:
				var f0 := lerpf(500.0, 1900.0, pow(rng.randf(), 1.6))
				_plink(s, r, lead, tt, f0, rng.randf_range(0.1, 0.6), 10.0, rng.randf_range(60.0, 110.0), rng)
				tt += rng.randf_range(0.002, 0.022)
			var a_hi := _a(3000.0, r)
			var a_lo := _a(600.0, r)
			var a_flick := _a(30.0, r)
			for i in total:
				var x := rng.randf_range(-1.0, 1.0)
				var splash := _lp(st, 0, x, a_hi) - _lp(st, 1, x, a_lo)
				s[i] += splash * (0.5 + _lp(st, 2, rng.randf_range(-1.0, 1.0), a_flick) * 4.0) * 0.6
		"clock":
			# A clock on a shelf: the escapement's two beats each second, a tick and a slightly duller, slightly early
			# tock, ringing the wooden case.
			var modes := [_res_c(3100.0, 0.95, r), _res_c(1650.0, 0.96, r), _res_c(430.0, 0.985, r)]
			var a_dull := _a(2000.0, r)
			for i in total:
				var t := float(i - lead) / r
				var two := fposmod(t, 2.0)
				var tock := two >= 0.97
				var dt := two - (0.97 if tock else 0.0)
				var ex := rng.randf_range(-1.0, 1.0) * exp(-dt * 3000.0) if dt < 0.006 else 0.0
				if tock:
					ex = _lp(st, 6, ex, a_dull) * 1.4
				var v := _res(st, 0, ex, modes[0]) * (1.0 if not tock else 0.5) + _res(st, 2, ex, modes[1]) * 1.2 \
						+ _res(st, 4, ex, modes[2]) * 1.5
				s[i] = v
		"tube_whine":
			# A picture tube's line whine (the line scan at 15 625 Hz; at pitch 0.648 a 405-line set's 10 125 Hz) and a
			# faint hum of its valves. Whole cycles in the loop.
			for i in total:
				var t := float(i - lead) / r
				s[i] = sin(TAU * 15625.0 * t) * (1.0 + 0.05 * sin(TAU * 0.5 * t)) + sin(TAU * 100.0 * t) * 0.12 \
						+ sin(TAU * 50.0 * t + 0.3) * 0.06
		"three_bells":
			# A soft house bell of three tones before the show, as struck bars ring (the tone, its fourth and tenth
			# partials, which fade first): up a fifth, then down a minor third. Our own call.
			var notes := [[0.02, 587.33], [0.47, 880.0], [0.92, 739.99]]
			for i in total:
				var t := float(i) / r
				var v := 0.0
				for nt: Array in notes:
					var d := t - float(nt[0])
					if d < 0.0:
						continue
					var f := float(nt[1])
					v += (sin(TAU * f * d) + 0.25 * sin(TAU * f * 4.0 * d) * exp(-d * 6.0)
							+ 0.06 * sin(TAU * f * 10.0 * d) * exp(-d * 14.0)) * exp(-d * 1.6) * minf(d / 0.004, 1.0)
				s[i] = v
		"candle":
			# A candle gutters: a puff of the flame (low noise that wavers about nine times a second) and three or
			# four tiny sputters of wax.
			var a_puff := _a(500.0, r)
			var a_puff_low := _a(120.0, r)
			var spit := _res_c(3400.0, 0.9, r)
			var spits: Array = []
			var at := rng.randf_range(0.12, 0.2)
			while at < 0.75:
				spits.append([at, rng.randf_range(0.4, 1.0)])
				at += rng.randf_range(0.1, 0.22)
			var length := float(total) / r
			for i in total:
				var t := float(i) / r
				var x := rng.randf_range(-1.0, 1.0)
				var puff := (_lp(st, 0, x, a_puff) - _lp(st, 1, x, a_puff_low)) * 3.0
				puff *= pow(sin(PI * t / length), 1.5) * (0.7 + 0.3 * sin(TAU * 9.0 * t))
				var ex := 0.0
				for sp: Array in spits:
					var d := t - float(sp[0])
					if d >= 0.0 and d < 0.004:
						ex += x * exp(-d * 1500.0) * float(sp[1])
				s[i] = puff + _res(st, 2, ex, spit) * 8.0
		"sonar":
			# A sonar's ping (the Bathysphere's pre-show, since 2026-11-08): a soft, round tone at 1.18 kHz that swells
			# in over 15 ms and rings down slowly with a faint beat (two close partials), a lower octave under it, and
			# 1.25 s later its echo off the sea floor: duller (low-passed), a third as loud, smeared. Our own.
			var a_echo := _a(900.0, r)
			for i in total:
				var t := float(i) / r
				var v := 0.0
				for k: Array in [[0.0, 1.0, 1.0], [1.25, 0.33, 2.2]]:
					var d := t - float(k[0])
					if d < 0.0:
						continue
					var env := minf(d / 0.015, 1.0) * exp(-d * 3.2 / float(k[2]) * 1.6)
					var tone := sin(TAU * 1180.0 * d) + 0.6 * sin(TAU * 1183.0 * d + 0.5) + 0.25 * sin(TAU * 590.0 * d)
					var e := tone * env * float(k[1])
					v += _lp(st, 0, e, a_echo) * 1.8 if k[0] > 0.0 else e
				s[i] = v
		"scops_owl":
			# A scops owl somewhere over the roofs (the Atmospheric 1928's pre-show, since 2026-11-08): its call, a soft
			# whistled "tew" about every two and a half seconds, four times. Each a near-pure tone gliding down from
			# 1.25 kHz to 1.17, swelling in over 30 ms and falling away, a breath of air in it, a little of its octave;
			# softened by the distance (low-passed). Our own; no recording.
			var a_air := _a(2200.0, r)
			var a_far := _a(3000.0, r)
			var hoots := [[0.35, 1.0], [2.85, 0.92], [5.4, 1.0], [7.92, 0.85]]
			var ph := 0.0
			for i in total:
				var t := float(i) / r
				var v := 0.0
				for h: Array in hoots:
					var d := t - float(h[0])
					if d < 0.0 or d > 0.24:
						continue
					var u := d / 0.24
					var f := lerpf(1250.0, 1170.0, u)
					ph = fmod(ph + f / r, 1.0)
					var env := minf(d / 0.03, 1.0) * pow(1.0 - u, 1.6) * float(h[1])
					var air := _lp(st, 0, rng.randf_range(-1.0, 1.0), a_air) * 0.35
					v += (sin(TAU * ph) + 0.08 * sin(TAU * 2.0 * ph) + air) * env
				s[i] = _lp(st, 1, v, a_far)
		"bubbles":
			# A vent's bubbles streaming up through deep water: bursts of small bubbles (short tones that rise as they
			# ring, low because they are large and far) between quiet spells, and the water's soft hiss round them.
			var t_end := float(total - lead) / r
			var tt := -float(lead) / r
			while tt < t_end:
				var burst := rng.randf_range(0.25, 0.9)
				var t1 := tt + burst
				while tt < t1:
					var f0 := lerpf(180.0, 720.0, pow(rng.randf(), 1.4))
					_plink(s, r, lead, tt, f0, rng.randf_range(0.15, 0.6), 6.0, rng.randf_range(35.0, 70.0), rng)
					tt += rng.randf_range(0.01, 0.06)
				tt += rng.randf_range(0.1, 0.7)
			var a_hiss := _a(1200.0, r)
			var a_low := _a(250.0, r)
			for i in total:
				var x := rng.randf_range(-1.0, 1.0)
				s[i] += (_lp(st, 0, x, a_hiss) - _lp(st, 1, x, a_low)) * 0.25
		"ice_creak":
			# Ice settling: a crack that sings down (a high ping falling fast, as ice does), then a low groan of
			# stick-slip pulses through the block's dull modes.
			var bank := [[110.0, 0.994, 1.0], [175.0, 0.993, 0.7], [420.0, 0.995, 0.3], [960.0, 0.996, 0.15]]
			var cs: Array = []
			for b: Array in bank:
				cs.append(_res_c(float(b[0]), float(b[1]), r))
			var ph := 0.0
			var slip := 0.0
			for i in total:
				var t := float(i) / r
				var v := 0.0
				var d := t - 0.05
				if d >= 0.0 and d < 0.4:
					ph += (350.0 + 2450.0 * exp(-d * 18.0)) / r
					v += sin(TAU * ph) * exp(-d * 10.0) * 0.6 + rng.randf_range(-1.0, 1.0) * exp(-d * 400.0)
				var u := (t - 0.4) / 2.1
				if u >= 0.0 and u < 1.0:
					slip += (18.0 + 22.0 * sin(PI * u) + 5.0 * sin(TAU * 1.7 * t)) / r
					var ex := 0.0
					if slip >= 1.0:
						slip -= 1.0
						ex = rng.randf_range(0.6, 1.0) * pow(sin(PI * u), 0.8)
					for j in bank.size():
						v += _res(st, j * 2, ex, cs[j]) * float(bank[j][2]) * 0.8
				s[i] = v
		"vcr":
			# A video recorder takes a tape: the tray's clunk, the motor's whirr rising as it threads the tape (the
			# guides' clicks), the heads engaging (a softer clunk), then the drum's steady whirr, fading out.
			var a_thud := _a(800.0, r)
			var a_motor := _a(900.0, r)
			var whirr := _res_c(1400.0, 0.97, r)
			var drum := _res_c(750.0, 0.99, r)
			var clunks := [[0.05, 1.0], [1.75, 0.6]]
			var clicks := [[0.55, 0.4], [0.95, 0.35], [1.35, 0.45], [2.1, 0.25]]
			var click := _res_c(2600.0, 0.93, r)
			var saw := 0.0
			for i in total:
				var t := float(i) / r
				var x := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				for c: Array in clunks:
					var d := t - float(c[0])
					if d >= 0.0 and d < 0.3:
						v += (sin(TAU * 85.0 * d) * exp(-d * 30.0) + _lp(st, 0, x, a_thud) * 3.0 * exp(-d * 120.0)) \
								* float(c[1])
				var ex := 0.0
				for c: Array in clicks:
					var d := t - float(c[0])
					if d >= 0.0 and d < 0.003:
						ex += x * float(c[1])
				v += _res(st, 1, ex, click) * 6.0
				var speed := smoothstep(0.3, 1.0, t) * (1.0 - smoothstep(3.6, 4.5, t))
				saw = fmod(saw + (45.0 + 75.0 * smoothstep(0.3, 1.2, t)) / r, 1.0)
				v += _lp(st, 3, saw * 2.0 - 1.0, a_motor) * 0.3 * speed
				v += _res(st, 4, x, whirr) * 1.5 * speed
				var spin := smoothstep(1.8, 2.4, t) * (1.0 - smoothstep(3.6, 4.5, t))
				v += _res(st, 6, x, drum) * 3.0 * spin * (0.8 + 0.2 * sin(TAU * 25.0 * t))
				s[i] = v
		"tape_load":
			# A home computer loads a program from a cassette: a steady pilot tone, a short gap, then the data's harsh
			# warble (two tones, one for each bit, switching a thousand times a second); the tape's hiss under it.
			var a_tape := _a(3200.0, r)
			var a_hiss := _a(4000.0, r)
			var ph := 0.0
			var bit := 0
			var bit_at := -1
			for i in total:
				var t := float(i) / r
				var wow := 1.0 + 0.004 * sin(TAU * 0.6 * t)
				var on := 0.0
				var f := 800.0
				if t >= 0.1 and t < 2.6:
					on = 1.0
				elif t >= 2.75 and t < 7.7:
					on = 0.9
					var b := int((t - 2.75) * 1000.0)
					if b != bit_at:
						bit_at = b
						bit = rng.randi_range(0, 1)
					f = 2000.0 if bit == 1 else 1000.0
				ph = fmod(ph + f * wow / r, 1.0)
				var sq := (1.0 if ph < 0.5 else -1.0) * on
				var x := rng.randf_range(-1.0, 1.0)
				var hiss := (x - _lp(st, 1, x, a_hiss)) * 0.06 * smoothstep(0.0, 0.05, t) \
						* (1.0 - smoothstep(7.85, 8.0, t))
				s[i] = _lp(st, 2, _lp(st, 0, sq, a_tape), a_tape) + hiss
		"switch_clunk":
			# A telly's mechanical power switch: the toggle's snap (a sharp click through two small resonances), the
			# contacts' bounce a few milliseconds after, the cabinet's wooden knock, and the speaker's soft thump as the
			# amplifier wakes.
			var snap := _res_c(2800.0, 0.95, r)
			var body := _res_c(1150.0, 0.93, r)
			var wood := _res_c(220.0, 0.985, r)
			var a_knock := _a(600.0, r)
			var hits := [[0.02, 1.0], [0.026, 0.45], [0.034, 0.25]]
			for i in total:
				var t := float(i) / r
				var x := rng.randf_range(-1.0, 1.0)
				var ex := 0.0
				for h: Array in hits:
					var d := t - float(h[0])
					if d >= 0.0 and d < 0.002:
						ex += x * float(h[1])
				var v := _res(st, 0, ex, snap) * 5.0 + _res(st, 2, ex, body) * 3.0 + _res(st, 4, ex, wood) * 6.0
				var d0 := t - 0.02
				if d0 >= 0.0:
					v += _lp(st, 6, x, a_knock) * 2.0 * exp(-d0 * 90.0)
				var dp := t - 0.11
				if dp >= 0.0:
					v += sin(TAU * 55.0 * dp) * exp(-dp * 22.0) * 0.35 * minf(dp / 0.01, 1.0)
				s[i] = v
		"valve_hum":
			# A valve set warming up: the mains transformer's hum (100 Hz and its harmonics, a faint 50 Hz) and a little
			# buzz, the speaker's soft rush coming up as the valves warm over five seconds, then settling to a murmur and
			# fading (a tube_whine bed can take over).
			var a_rush := _a(2500.0, r)
			var a_rush_lo := _a(300.0, r)
			for i in total:
				var t := float(i) / r
				var rise := smoothstep(0.3, 5.5, t)
				var settle := (1.0 - 0.6 * smoothstep(5.5, 7.0, t)) * (1.0 - smoothstep(7.2, 8.0, t)) \
						* smoothstep(0.0, 0.3, t)
				var hum := sin(TAU * 50.0 * t) * 0.25 + sin(TAU * 100.0 * t) + sin(TAU * 150.0 * t) * 0.35 \
						+ sin(TAU * 200.0 * t) * 0.3 + sin(TAU * 300.0 * t) * 0.12
				var buzz := (sin(TAU * 400.0 * t) * 0.5 + sin(TAU * 500.0 * t) * 0.35 + sin(TAU * 700.0 * t) * 0.2) * 0.1
				var x := rng.randf_range(-1.0, 1.0)
				var rush := (_lp(st, 0, x, a_rush) - _lp(st, 1, x, a_rush_lo)) * 0.8 * smoothstep(1.5, 6.0, t)
				s[i] = (hum * (0.15 + 0.85 * rise) + buzz * rise + rush) * settle
		"crt_off":
			# A picture tube switched off: a soft thunk as the high voltage lets go, a tiny tick, then the glass's static
			# crackling faintly now and then as it discharges.
			var a_thunk := _a(400.0, r)
			var tick := _res_c(4200.0, 0.9, r)
			var cracks: Array = []
			var at := 0.25
			while at < 1.2:
				cracks.append([at, rng.randf_range(0.2, 0.7)])
				at += rng.randf_range(0.06, 0.25)
			for i in total:
				var t := float(i) / r
				var x := rng.randf_range(-1.0, 1.0)
				var v := 0.0
				var d := t - 0.03
				if d >= 0.0:
					v += sin(TAU * 70.0 * d) * exp(-d * 28.0) * 0.6 + _lp(st, 0, x, a_thunk) * 1.5 * exp(-d * 60.0)
				var ex := 0.0
				if t >= 0.05 and t < 0.052:
					ex += x
				for c: Array in cracks:
					var dc := t - float(c[0])
					if dc >= 0.0 and dc < 0.0015:
						ex += x * float(c[1]) * 0.5
				s[i] = v + _res(st, 1, ex, tick) * 4.0
		"channel_clunk":
			# A rotary channel knob turned one step: the detent's ratchet as it climbs, the spring's snap into the next
			# notch and a softer second snap, the knock through the wooden cabinet.
			var snap := _res_c(2300.0, 0.95, r)
			var tick := _res_c(3800.0, 0.9, r)
			var wood := _res_c(180.0, 0.985, r)
			var a_knock := _a(700.0, r)
			var hits := [[0.012, 0.25, 0], [0.028, 0.3, 0], [0.044, 0.35, 0], [0.09, 1.0, 1], [0.118, 0.5, 1]]
			for i in total:
				var t := float(i) / r
				var x := rng.randf_range(-1.0, 1.0)
				var ex_tick := 0.0
				var ex_snap := 0.0
				for h: Array in hits:
					var dh := t - float(h[0])
					if dh >= 0.0 and dh < 0.0015:
						if int(h[2]) == 0:
							ex_tick += x * float(h[1])
						else:
							ex_snap += x * float(h[1])
				var v := _res(st, 0, ex_snap, snap) * 5.0 + _res(st, 2, ex_tick, tick) * 3.0 \
						+ _res(st, 4, ex_snap, wood) * 7.0
				var d := t - 0.09
				if d >= 0.0:
					v += _lp(st, 6, x, a_knock) * 1.5 * exp(-d * 100.0)
				s[i] = v
	return s


# --- Instruments (scripts/env/systems/music.gd) --------------------------------------------------------------------------

## A single-cycle table (2048 samples) of these harmonics. Not cached: notes are made on worker threads.
static func _table(harm: Array) -> PackedFloat32Array:
	var size := 2048
	var tb := PackedFloat32Array()
	tb.resize(size)
	for i in size:
		var x := TAU * float(i) / size
		var v := 0.0
		for h in harm.size():
			v += sin(x * (h + 1)) * float(harm[h])
		tb[i] = v
	return tb


static func _look(tb: PackedFloat32Array, phase: float) -> float:
	var p := phase * 2048.0
	var i := int(p)
	var f := p - i
	return lerpf(tb[i & 2047], tb[(i + 1) & 2047], f)


## The piano note nearest a pitch (its base pitch: midi rounded to the PIANO_STEP grid).
static func piano_base(midi: int) -> int:
	return clampi(PIANO_LOW + roundi(float(midi - PIANO_LOW) / PIANO_STEP) * PIANO_STEP, PIANO_LOW, PIANO_HIGH)


## A player piano's note at a base pitch: two strings a little out of tune with each other (an upright's honky-tonk),
## bright at the hammer's strike and mellower as it rings, a double decay (fast, then slow), a felt thump. Made at the
## reference level's peak budget; cached. Safe on a worker thread when not cached yet (no shared writes but the end).
static func piano_note(base: int, detune_cents := 6.0) -> AudioStreamWAV:
	var key := piano_key(base, detune_cents)
	if _notes.has(key):
		return _notes[key]
	var w := make_piano_note(base, detune_cents)
	_notes[key] = w
	return w


## The notes' cache by key (piano_key, organ_key): made on a worker (make_*_note), put here on the main thread.
static func piano_key(base: int, detune_cents: float) -> String:
	return "piano:%d:%d" % [base, roundi(detune_cents * 10.0)]


static func organ_key(midi: int, stop: String) -> String:
	return "organ:%d:%s" % [midi, stop]


static func note(key: String) -> AudioStreamWAV:
	return _notes.get(key)


static func put_note(key: String, w: AudioStreamWAV) -> void:
	if w != null and not _notes.has(key):
		_notes[key] = w


static func make_piano_note(base: int, detune_cents := 6.0) -> AudioStreamWAV:
	var r := float(PIANO_RATE)
	var f := 440.0 * pow(2.0, (base - 69) / 12.0)
	# Harmonics under 12 kHz even two semitones up.
	var top := clampi(int(12000.0 / (f * 1.13)), 1, 14)
	var bright: Array = []
	for h in top:
		var n := h + 1
		# A hammer struck an eighth of the way along: the eighth harmonic is weak.
		bright.append(absf(sin(PI * n / 8.0)) / pow(n, 0.9) if n % 8 != 0 else 0.02)
	var mellow: Array = [1.0, 0.3, 0.1, 0.04].slice(0, mini(4, top))
	var tb := _table(bright)
	var tm := _table(mellow)
	var length := clampf(3.4 - (base - 36) * 0.045, 0.9, 3.4)
	var n_samples := int(length * r)
	var s := PackedFloat32Array()
	s.resize(n_samples)
	var d := pow(2.0, detune_cents / 1200.0)
	var p1 := 0.0
	var p2 := 0.37
	var inc1 := f * d / r
	var inc2 := f / d / r
	var low := clampf(float(96 - base) / 60.0, 0.0, 1.0)
	var t_fast := 0.18 + 0.4 * low
	var t_slow := 1.0 + 2.6 * low
	var t_bright := 0.08 + 0.25 * low
	var e_fast := 1.0
	var e_slow := 1.0
	var e_bright := 1.0
	var k_fast := exp(-1.0 / (t_fast * r))
	var k_slow := exp(-1.0 / (t_slow * r))
	var k_bright := exp(-1.0 / (t_bright * r))
	var rng := RandomNumberGenerator.new()
	rng.seed = base
	var thump := 0.0
	var a_thump := _a(500.0, r)
	var attack := int(0.002 * r)
	var release := int(0.05 * r)
	for i in n_samples:
		p1 += inc1
		p1 -= floorf(p1)
		p2 += inc2
		p2 -= floorf(p2)
		var b := _look(tb, p1) + _look(tb, p2)
		var m := _look(tm, p1) + _look(tm, p2)
		var v := (m + (b - m) * e_bright) * (0.62 * e_fast + 0.38 * e_slow) * 0.5
		thump += (rng.randf_range(-1.0, 1.0) - thump) * a_thump
		v += thump * e_bright * e_bright * 0.6
		if i < attack:
			v *= float(i) / attack
		if i > n_samples - release:
			v *= float(n_samples - i) / release
		e_fast *= k_fast
		e_slow *= k_slow
		e_bright *= k_bright
		s[i] = v
	return _wav(s, _note_gain(s), PIANO_RATE, false)


## A note's gain: its first half second at the reference RMS, its peak under PEAK.
static func _note_gain(s: PackedFloat32Array) -> float:
	var n := mini(s.size(), PIANO_RATE / 2)
	var sum := 0.0
	var peak := 0.0
	for i in s.size():
		peak = maxf(peak, absf(s[i]))
	for i in n:
		sum += s[i] * s[i]
	var rms := sqrt(sum / maxf(n, 1))
	return minf(db_to_linear(REFERENCE_DB) / maxf(rms, 1e-9), PEAK / maxf(peak, 1e-9))


## A pipe organ's note: the stop's harmonics (additive synthesis), a breath of wind noise at the speech (the chiff),
## the tone rising over 50 ms, then a steady tone that loops for as long as the key is held. The loop is a whole
## number of cycles, so the pitch is a little off: organ_pitch_scale(midi) puts it right. Cached.
static func organ_note(midi: int, stop := "principal") -> AudioStreamWAV:
	var key := organ_key(midi, stop)
	if _notes.has(key):
		return _notes[key]
	var w := make_organ_note(midi, stop)
	_notes[key] = w
	return w


## Samples in one cycle of an organ note (the loop's period).
static func organ_cycle(midi: int) -> int:
	return maxi(roundi(ORGAN_RATE / (440.0 * pow(2.0, (midi - 69) / 12.0))), 8)


static func organ_pitch_scale(midi: int) -> float:
	var f := 440.0 * pow(2.0, (midi - 69) / 12.0)
	return f / (float(ORGAN_RATE) / organ_cycle(midi))


static func make_organ_note(midi: int, stop := "principal") -> AudioStreamWAV:
	var r := float(ORGAN_RATE)
	var cyc := organ_cycle(midi)
	var f := r / cyc
	var harm: Array = (STOPS.get(stop, STOPS["principal"]) as Array).duplicate()
	while harm.size() > 1 and f * harm.size() > 15000.0:
		harm.pop_back()
	# The attack: whole cycles over about 60 ms; the loop: whole cycles over at least 2048 samples.
	var attack_cycles := maxi(ceili(0.06 * f), 1)
	var loop_cycles := maxi(ceili(2048.0 / cyc), 1)
	var n := (attack_cycles + loop_cycles) * cyc
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = midi * 31 + stop.length()
	var chiff := _res_c(minf(f * 4.0, 6000.0), 0.97, r)
	var st := PackedFloat32Array()
	st.resize(4)
	var attack_n := attack_cycles * cyc
	for i in n:
		var x := TAU * float(i % cyc) / cyc
		var v := 0.0
		for h in harm.size():
			v += sin(x * (h + 1)) * float(harm[h])
		if i < attack_n:
			var t := float(i) / r
			v *= smoothstep(0.0, 0.05, t)
			v += _res(st, 0, rng.randf_range(-1.0, 1.0), chiff) * 6.0 * exp(-t * 60.0)
		s[i] = v
	# Its steady part at the reference RMS.
	var sum := 0.0
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(s[i]))
		if i >= attack_n:
			sum += s[i] * s[i]
	var rms := sqrt(sum / maxf(n - attack_n, 1))
	var gain := minf(db_to_linear(REFERENCE_DB) / maxf(rms, 1e-9), PEAK / maxf(peak, 1e-9))
	return _wav(s, gain, ORGAN_RATE, true, attack_n)
