extends RefCounted

## Test signals for working on a visualiser with no music (docs/visualisers.md, "Tinkering"): WAV files the app makes
## once, on a worker thread, in user://visualisers/.test-signals-<VERSION>/, and opens as music like any other file.
## Static; preload to use.
##
##   drums     120 beats a minute: a kick on each beat, a hat between, a bass line and a chord pad; no drums from 20
##             to 30 s (how a visualiser rests)
##   sweep     one tone gliding from 30 Hz to 15 kHz and back down, 10 s each way
##   tones     a pure tone every 2 s, an octave higher each time from 55 Hz to 14 kHz, then again
##   silence   nothing (how a visualiser looks at rest)
##
##   path(which) -> String          where its file is (made or not)
##   make(which, seconds) -> PackedByteArray   the WAV's bytes (any thread; tests use a short `seconds`)
##   ensure(which) -> String        the file, made first if it is not there (blocks; call it from a worker)

const SIGNALS: Array[String] = ["drums", "sweep", "tones", "silence"]
const VERSION := 1
const RATE := 32000
const SECONDS := 40.0
const BEAT := 0.5


static func folder() -> String:
	return "user://visualisers/.test-signals-%d" % VERSION


static func path(which: String) -> String:
	return folder().path_join("test signal %s.wav" % which)


static func ensure(which: String) -> String:
	var p := path(which)
	if FileAccess.file_exists(p):
		return p
	DirAccess.make_dir_recursive_absolute(folder())
	var tmp := p + ".part"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(make(which, SECONDS))
	f.close()
	DirAccess.rename_absolute(tmp, p)
	return p


## A 16-bit mono WAV of the signal.
static func make(which: String, seconds: float) -> PackedByteArray:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(44 + n * 2)
	_header(data, n)
	var phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		match which:
			"drums":
				v = _drums(t, noise)
			"sweep":
				# Log glide up for 10 s, down for 10 s; the phase is summed so the glide is smooth.
				var u := fmod(t, 20.0)
				var k := u / 10.0 if u < 10.0 else (20.0 - u) / 10.0
				phase += TAU * 30.0 * pow(500.0, k) / RATE
				v = 0.5 * sin(phase)
			"tones":
				var step := int(t / 2.0) % 9
				var local := fmod(t, 2.0)
				var env := minf(minf(local / 0.02, 1.0), minf((2.0 - local) / 0.05, 1.0))
				v = 0.5 * env * sin(TAU * 55.0 * pow(2.0, step) * t)
		data.encode_s16(44 + i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return data


static func _drums(t: float, noise: RandomNumberGenerator) -> float:
	var on := not (t >= 20.0 and t < 30.0)
	var b := fmod(t, BEAT)
	var kick := exp(-b * 9.0) * sin(TAU * (45.0 + 120.0 * exp(-b * 25.0)) * b) if on else 0.0
	var off := fmod(t + BEAT * 0.5, BEAT)
	var hat := 0.18 * exp(-off * 40.0) * noise.randf_range(-1.0, 1.0) if on else 0.0
	var bass := 0.22 * sin(TAU * (55.0 if fmod(t, 4.0) < 2.0 else 73.42) * t)
	var swell := 0.6 + 0.4 * sin(TAU * 0.1 * t)
	var pad := 0.08 * (sin(TAU * 220.0 * t) + sin(TAU * 277.18 * t) + sin(TAU * 329.63 * t)
			+ 0.5 * (0.5 + 0.5 * sin(TAU * 0.5 * t)) * sin(TAU * 1318.5 * t)) * swell
	return 0.55 * (kick + hat + bass + pad)


static func _header(d: PackedByteArray, frames: int) -> void:
	var bytes := frames * 2
	for i in 4:
		d[i] = "RIFF".unicode_at(i)
		d[8 + i] = "WAVE".unicode_at(i)
		d[12 + i] = "fmt ".unicode_at(i)
		d[36 + i] = "data".unicode_at(i)
	d.encode_u32(4, 36 + bytes)
	d.encode_u32(16, 16)
	d.encode_u16(20, 1)
	d.encode_u16(22, 1)
	d.encode_u32(24, RATE)
	d.encode_u32(28, RATE * 2)
	d.encode_u16(32, 2)
	d.encode_u16(34, 16)
	d.encode_u32(40, bytes)
