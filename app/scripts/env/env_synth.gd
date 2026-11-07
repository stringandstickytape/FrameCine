extends RefCounted

## The room's synthesised sounds (docs/environments.md, "The audio buses"): made here from sines and noise, so they are
## ours (no samples, no licence). Each is made at the film's reference level (REFERENCE_DB RMS over its sounding part),
## so the Environment bus's default (-18 dB) puts it 18 dB under the film. Cached per name. Static; preload to use.
##   EnvSynth.stream(name) -> AudioStreamWAV     NAMES; a looping one for "noise" (a bed)
##   EnvSynth.rms_db(stream) -> float             its RMS level (dBFS)

const RATE := 44100
## The film's reference level: dialogue in a film mixed for the home is about -20 dBFS RMS.
const REFERENCE_DB := -20.0
const NAMES: Array[String] = ["chime", "gong", "rumble", "tick", "noise", "whale", "creak"]
## Seconds each lasts.
const LENGTHS := {"chime": 2.5, "gong": 4.0, "rumble": 3.0, "tick": 0.08, "noise": 4.0, "whale": 5.0, "creak": 1.2}

static var _cache := {}


static func stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	if not (sound in NAMES):
		return null
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
	_cache[sound] = w
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
