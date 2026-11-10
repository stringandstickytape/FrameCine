## A small shape and location decoder for the floating keyboard. Word paths are resampled once on a worker;
## endpoint buckets keep the release-time search small. SCOWL levels are frequency classes, not corpus counts.
extends RefCounted

const Layout := preload("res://keyboard/key_layout.gd")
const SAMPLES := 24
## A letter's farthest corner is under 0.65u from its centre. This admits edge presses while avoiding an entire
## ring of unrelated endpoint buckets when the viewer starts near the middle of a key.
const ENDPOINT_RADIUS := 0.85
## A uniform tip offset should not turn a word into its neighbour just because the first letter is nearer.
const SHAPE_WEIGHT := 8.0
const WORDS := "res://keyboard/words.tsv.gz"
var buckets := {}
var word_count := 0


func build(path := WORDS) -> void:
	var centres := Layout.letters()
	var compressed := FileAccess.get_file_as_bytes(path)
	var bytes := compressed.decompress_dynamic(4 << 20, FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty():
		return
	for line in bytes.get_string_from_utf8().split("\n", false):
		var parts := line.split("\t")
		if parts.size() != 2:
			continue
		var word := parts[0]
		var points := PackedVector2Array()
		for ch in word:
			if centres.has(ch) and (points.is_empty() or points[-1] != centres[ch]):
				points.append(centres[ch])
		if points.is_empty():
			continue
		var samples := resample(points)
		var pair := word[0] + word[-1]
		if not buckets.has(pair):
			buckets[pair] = []
		buckets[pair].append({"word": word, "level": float(parts[1]), "path": samples, "shape": normalise(samples)})
		word_count += 1


static func resample(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[-1] + points[i - 1].distance_to(points[i]))
	var at := 1
	for i in SAMPLES:
		var d := lengths[-1] * i / float(SAMPLES - 1)
		while at < lengths.size() - 1 and lengths[at] < d:
			at += 1
		if points.size() == 1:
			out.append(points[0])
		else:
			var span := lengths[at] - lengths[at - 1]
			out.append(points[at - 1].lerp(points[at], (d - lengths[at - 1]) / span if span > 0.0 else 0.0))
	return out


static func normalise(points: PackedVector2Array) -> PackedVector2Array:
	var centre := Vector2.ZERO
	for p in points:
		centre += p
	centre /= maxf(points.size(), 1)
	var scale := 0.0
	for p in points:
		scale = maxf(scale, p.distance_to(centre))
	var out := PackedVector2Array()
	for p in points:
		out.append((p - centre) / maxf(scale, 0.5))
	return out


func decode(points: PackedVector2Array) -> Array[String]:
	var result: Array[String] = []
	if points.is_empty():
		return result
	var path := resample(points)
	var shape := normalise(path)
	var centres := Layout.letters()
	var scores: Array[Dictionary] = []
	for first: String in centres:
		if points[0].distance_to(centres[first]) > ENDPOINT_RADIUS:
			continue
		for last: String in centres:
			if points[-1].distance_to(centres[last]) > ENDPOINT_RADIUS:
				continue
			for candidate: Dictionary in buckets.get(first + last, []):
				var location := 0.0
				var form := 0.0
				var ideal: PackedVector2Array = candidate.path
				var ideal_shape: PackedVector2Array = candidate.shape
				for i in SAMPLES:
					location += path[i].distance_squared_to(ideal[i])
					form += shape[i].distance_squared_to(ideal_shape[i])
				var score := (location + form * SHAPE_WEIGHT) / SAMPLES + float(candidate.level) * 0.0008
				scores.append({"word": candidate.word, "score": score})
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	for i in mini(4, scores.size()):
		result.append(str(scores[i].word))
	return result
