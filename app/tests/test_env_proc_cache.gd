extends SceneTree

## The pictures a room draws, kept on disk between runs (docs/environments/checks.md, "The pictures a room draws";
## scripts/env/proc_cache.gd). Part 1 tries the cache itself. Part 2 builds every room twice, in two processes: a
## generator's own memory hides the disk within one process, so only a second process reads what the first wrote.
## The second process draws every picture again and compares it with the one it read (ProcCache.verify): every
## picture a room keeps is the one it would draw.
## godot --headless --xr-mode off --path app --script res://tests/test_env_proc_cache.gd
## (started again by itself with "-- --child": the second process)

const ProcCache := preload("res://scripts/env/proc_cache.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")

## Where a child leaves each room's build time for the parent (its output is one line).
# UNDECIDED (brief): the child prints one line, but the parent needs each room's time for the five largest savings.
const CHILD_TIMES := "user://test_env_proc_cache_child.json"
const OTHER_STAMP := "user://env_cache/0123456789abcdef0123456789abcdef"

var _failures := 0
var _checks := 0
var _test_keys: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--child"):
		await _child(not args.has("--no-verify"))
		return
	_part_1()
	await _part_2()
	for key in _test_keys:
		DirAccess.remove_absolute(ProcCache.path_of(key))
	print("test_env_proc_cache: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Part 1: the cache itself ----------------------------------------------------------------------------------------

func _part_1() -> void:
	_counts_to_zero()
	# 1. One picture: drawn once, read the second time, the same.
	var key := _fresh("test:one")
	var runs := [0]
	var make := func() -> Image:
		runs[0] += 1
		return _noise_image(64, 32, Image.FORMAT_RGBA8, false, 1)
	var a := ProcCache.image(key, make)
	var b := ProcCache.image(key, make)
	_check("image(): drawn once (%d), the second a hit (%d hits, %d misses)" % [runs[0], ProcCache.hits,
			ProcCache.misses], runs[0] == 1 and ProcCache.hits == 1 and ProcCache.misses == 1)
	_check("image(): the same size, format and data from disk", _same(a, b))

	# 2. Three pictures under one key: each comes back as it went in.
	key = _fresh("test:three")
	var three: Array[Image] = [_noise_image(64, 32, Image.FORMAT_RGBA8, false, 2),
			_noise_image(16, 16, Image.FORMAT_RGB8, true, 3), _noise_image(8, 8, Image.FORMAT_RF, false, 4)]
	var made := ProcCache.images(key, func() -> Array: return three)
	var read := ProcCache.images(key, func() -> Array: return [])
	_check("images(): three pictures kept and read (%d, %d)" % [made.size(), read.size()],
			made.size() == 3 and read.size() == 3)
	for i in mini(read.size(), 3):
		_check("images(): picture %d the same (%s %s, mipmaps %s)" % [i, three[i].get_size(), three[i].get_format(),
				three[i].has_mipmaps()], _same(three[i], read[i]))

	# 3. Off: drawn every time, nothing written.
	key = _fresh("test:off")
	runs = [0]
	var count := func() -> Image:
		runs[0] += 1
		return _noise_image(8, 8, Image.FORMAT_RGB8, false, 5)
	ProcCache.enabled = false
	ProcCache.image(key, count)
	ProcCache.image(key, count)
	ProcCache.enabled = true
	_check("enabled = false: drawn every time (%d)" % runs[0], runs[0] == 2)
	_check("enabled = false: no file written", not FileAccess.file_exists(ProcCache.path_of(key)))

	# 4. A file cut short is drawn again, and whole after.
	key = _fresh("test:cut")
	runs = [0]
	var cut := func() -> Image:
		runs[0] += 1
		return _noise_image(32, 32, Image.FORMAT_RGBA8, false, 6)
	ProcCache.image(key, cut)
	var bytes := FileAccess.get_file_as_bytes(ProcCache.path_of(key))
	var f := FileAccess.open(ProcCache.path_of(key), FileAccess.WRITE)
	f.store_buffer(bytes.slice(0, 20))
	f.close()
	var misses := ProcCache.misses
	ProcCache.image(key, cut)
	_check("a file cut short (%d of %d bytes) is a miss: drawn again" % [20, bytes.size()],
			runs[0] == 2 and ProcCache.misses == misses + 1)
	var hits := ProcCache.hits
	ProcCache.image(key, cut)
	_check("and the file is whole after: the next is a hit", runs[0] == 2 and ProcCache.hits == hits + 1)

	# 5. Verify: what is read is drawn again; a picture that is drawn otherwise now is counted (an error is expected).
	ProcCache.verify = true
	var was := ProcCache.mismatches
	print("  (an error from ProcCache follows: expected)")
	ProcCache.image("test:one", func() -> Image: return _noise_image(64, 32, Image.FORMAT_RGBA8, false, 99))
	_check("verify: a picture drawn otherwise is a mismatch (%d to %d)" % [was, ProcCache.mismatches],
			ProcCache.mismatches == was + 1)
	ProcCache.verify = false

	# 6. The stamp, and other stamps' folders.
	var stamp := ProcCache.stamp()
	_check("stamp(): 32 characters of hex (%s)" % stamp, stamp.length() == 32 and stamp.is_valid_hex_number())
	_check("stamp(): the same on a second call", ProcCache.stamp() == stamp)
	DirAccess.make_dir_recursive_absolute(OTHER_STAMP)
	var other := FileAccess.open(OTHER_STAMP.path_join("a.pic"), FileAccess.WRITE)
	other.store_string("another checkout's picture")
	other.close()
	ProcCache._stamp = ""
	ProcCache.stamp()
	_check("another stamp's folder written just now is kept", DirAccess.dir_exists_absolute(OTHER_STAMP))
	ProcCache.keep_seconds = 0.0
	ProcCache._stamp = ""
	ProcCache.stamp()
	ProcCache.keep_seconds = 86400.0
	_check("with keep_seconds 0 it is gone", not DirAccess.dir_exists_absolute(OTHER_STAMP))
	_check("the stamp is the same after", ProcCache.stamp() == stamp)


## A test key with no file on disk yet (removed at the end).
func _fresh(key: String) -> String:
	DirAccess.remove_absolute(ProcCache.path_of(key))
	_test_keys.append(key)
	return key


## A picture of noise (every pixel its own) in a format, with mipmaps or not.
func _noise_image(w: int, h: int, format: Image.Format, mipmaps: bool, seed_value: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create_empty(w, h, false, format)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	if mipmaps:
		img.generate_mipmaps()
	return img


func _same(a: Image, b: Image) -> bool:
	return a != null and b != null and a.get_size() == b.get_size() and a.get_format() == b.get_format() \
			and a.has_mipmaps() == b.has_mipmaps() and a.get_data() == b.get_data()


func _counts_to_zero() -> void:
	ProcCache.hits = 0
	ProcCache.misses = 0
	ProcCache.mismatches = 0


# --- Part 2: every room, in two processes --------------------------------------------------------------------------

func _part_2() -> void:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	for s: String in ["$", "`", "\\", "\""]:
		if exe.contains(s) or project.contains(s):
			print("  Part 2 skipped: the engine's or the project's path has %s in it (OS.execute passes every " % s
					+ "argument through a shell in double quotes, nothing escaped)")
			return
	# Every room drawn from nothing: this stamp's folder emptied.
	var dir := ProcCache.path_of("x").get_base_dir()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".pic"):
			DirAccess.remove_absolute(dir.path_join(f))
	_counts_to_zero()
	var parent := await _build_all()
	var n := ProcCache.misses
	var parent_ms := _total(parent)
	print("  parent: %d pictures drawn, %d ms building every room" % [n, roundi(parent_ms)])
	_check("the rooms draw at least 20 pictures (%d)" % n, n >= 20)

	# The proof: the child reads every picture and draws it again to compare (verify).
	var proof := _start_child(exe, project, ["--child"])
	_check("child: exit code 0 (%d)" % proof["code"], proof["code"] == 0)
	_check("child: %d hits, 0 misses, 0 mismatches (%s)" % [n, proof["line"]], proof["hits"] == n
			and proof["misses"] == 0 and proof["mismatches"] == 0)
	# The time: verify draws every picture again, so the build time is taken by a child that only reads.
	# UNDECIDED (brief): the brief times the verify child, whose builds draw every picture too; timed here without it.
	var timed := _start_child(exe, project, ["--child", "--no-verify"])
	_check("child without verify: exit code 0 (%d), %d hits (%s)" % [timed["code"], n, timed["line"]],
			timed["code"] == 0 and timed["hits"] == n and timed["misses"] == 0)
	var child: Dictionary = timed["times"]
	var child_ms := _total(child)
	print("  build time: parent %d ms, child %d ms (%d %%); the child with verify %d ms" % [roundi(parent_ms),
			roundi(child_ms), roundi(child_ms * 100.0 / maxf(parent_ms, 1.0)), roundi(float(proof["ms"]))])
	_check("child: under 60 %% of the parent's build time (%d of %d ms)" % [roundi(child_ms), roundi(parent_ms)],
			child_ms < parent_ms * 0.6)
	var saved: Array = []
	for f: String in parent:
		saved.append([f, float(parent[f]) - float(child.get(f, 0.0)), float(parent[f]), float(child.get(f, 0.0))])
	saved.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	print("  the largest savings:")
	for e: Array in saved.slice(0, 5):
		print("    %s: %d ms saved (%d to %d ms)" % [e[0], roundi(e[1]), roundi(e[2]), roundi(e[3])])
	_check("each child's build times came back (%d of %d rooms)" % [child.size(), parent.size()],
			child.size() == parent.size())


## Starts this test as a child: {code, line, hits, misses, mismatches, ms, times}.
func _start_child(exe: String, project: String, extra: Array) -> Dictionary:
	DirAccess.remove_absolute(CHILD_TIMES)
	var output := []
	var code := OS.execute(exe, ["--headless", "--xr-mode", "off", "--path", project, "--script",
			"res://tests/test_env_proc_cache.gd", "--"] + extra, output, true)
	var out := {"code": code, "line": "", "hits": -1, "misses": -1, "mismatches": -1, "ms": 0.0, "times": {}}
	var re := RegEx.create_from_string("child: (\\d+) hits, (\\d+) misses, (\\d+) mismatches, (\\d+) ms")
	var text := "\n".join(PackedStringArray(output))
	var m := re.search(text)
	if m == null:
		print("  the child said:\n", text.right(3000))
		return out
	out["line"] = m.get_string()
	out["hits"] = m.get_string(1).to_int()
	out["misses"] = m.get_string(2).to_int()
	out["mismatches"] = m.get_string(3).to_int()
	out["ms"] = m.get_string(4).to_float()
	var times: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHILD_TIMES))
	if times is Dictionary:
		out["times"] = times
	DirAccess.remove_absolute(CHILD_TIMES)
	return out


## The second process: every room built once, every picture read from disk (and with verify, drawn and compared).
func _child(verify: bool) -> void:
	ProcCache.verify = verify
	_counts_to_zero()
	var times := await _build_all()
	var f := FileAccess.open(CHILD_TIMES, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(times))
		f.close()
	print("child: %d hits, %d misses, %d mismatches, %d ms" % [ProcCache.hits, ProcCache.misses, ProcCache.mismatches,
			roundi(_total(times))])
	quit(ProcCache.mismatches + ProcCache.misses)


## Every room that ships built once, each build timed: {file: ms}.
func _build_all() -> Dictionary:
	var times := {}
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://environments"):
		if f.ends_with(".env.json"):
			files.append(f)
	files.sort()
	for f in files:
		var doc: Dictionary = EnvDoc.load_file("res://environments/" + f)["doc"]
		if doc.is_empty():
			continue
		var room: Node3D = EnvRoom.new()
		room.doc = doc
		var t0 := Time.get_ticks_usec()
		root.add_child(room)
		times[f] = (Time.get_ticks_usec() - t0) / 1000.0
		await process_frame
		root.remove_child(room)
		room.free()
	return times


func _total(times: Dictionary) -> float:
	var sum := 0.0
	for f: String in times:
		sum += float(times[f])
	return sum


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
