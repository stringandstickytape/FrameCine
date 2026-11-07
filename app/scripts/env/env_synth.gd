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
		"rain_leaves", "gas_hiss"]
## Seconds each lasts (a loop: its loop's length).
const LENGTHS := {"chime": 2.5, "gong": 4.0, "rumble": 3.0, "tick": 0.08, "noise": 4.0, "whale": 5.0, "creak": 1.2,
		"projector": 4.0, "wall_rumble": 8.0, "cicadas": 6.0, "moped": 8.0, "train": 40.0, "huskies": 7.0,
		"hull_creak": 3.5, "radiator": 16.0, "rain_glass": 6.0, "rain_leaves": 6.0, "gas_hiss": 4.0}
## The sounds that loop (beds); the rest play once.
const LOOPS: Array[String] = ["noise", "projector", "wall_rumble", "cicadas", "radiator", "rain_glass", "rain_leaves",
		"gas_hiss"]
## Sample rates below RATE for the far and low sounds (less to make, nothing lost above their band).
const RATES := {"wall_rumble": 22050, "train": 22050, "huskies": 22050, "radiator": 22050, "moped": 32000,
		"hull_creak": 32000}
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
