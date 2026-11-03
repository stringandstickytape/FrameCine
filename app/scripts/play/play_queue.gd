extends Node

## Shuffle, repeat and queue editing (ideas #78): the playlist (main.playlist, the folder or what the browser passed)
## as a proper queue. It edits main.playlist in place and keeps main.playlist_index on the current file, so next /
## previous (A / B, N / P) follow it unchanged.
##
##   repeat            "off", "one" (the file again), "all" (back to the first after the last)
##   shuffle           on: the files after the current one are shuffled; off: the original order comes back
##   continuous        play on through the queue at the end of a file (a --dir run does anyway)
##   items()           the queue, [{path, title, current}]
##   play_next(path), append(path), remove(index), move(from, to), clear_upcoming(), jump(index)
##   set_repeat(r), cycle_repeat(), set_shuffle(on), set_continuous(on)
##   signal changed
## End of a file: main._on_ended asks on_ended() first. Repeat "one" restarts; with continuous (or --dir) the next
## file opens, and after the last, repeat "all" starts again from the first. An end-of-file sleep timer (#17) wins.
## Desktop keys (menu hidden): T cycles repeat, U toggles shuffle.
## Settings: [queue] repeat, shuffle, continuous.

signal changed

const REPEATS: Array[String] = ["off", "one", "all"]

var main: Node3D
var repeat := "off"
var shuffle := false
var continuous := false
## The playlist's order before shuffling (to restore), or [].
var _unshuffled: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	repeat = str(main.settings.get_value("queue", "repeat", "off"))
	if repeat not in REPEATS:
		repeat = "off"
	shuffle = bool(main.settings.get_value("queue", "shuffle", false))
	continuous = bool(main.settings.get_value("queue", "continuous", false))
	main.file_opened.connect(_on_file_opened)


func _on_file_opened(_path: String) -> void:
	# A new playlist (another folder) forgets the old order; shuffling applies to it afresh.
	if not _same_items(_unshuffled, main.playlist):
		_unshuffled.clear()
		if shuffle:
			_shuffle_upcoming()
	_sync()


func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in main.playlist.size():
		var p: String = main.playlist[i]
		out.append({"path": p, "title": p.get_file() if not p.begins_with("stub://") else p, "current": i == main.playlist_index})
	return out


func set_repeat(r: String) -> void:
	if r not in REPEATS:
		return
	repeat = r
	main.settings.set_value("queue", "repeat", r)
	changed.emit()


func cycle_repeat() -> void:
	set_repeat(REPEATS[(REPEATS.find(repeat) + 1) % REPEATS.size()])


func set_continuous(on: bool) -> void:
	continuous = on
	main.settings.set_value("queue", "continuous", on)
	changed.emit()


func set_shuffle(on: bool) -> void:
	if on == shuffle:
		return
	shuffle = on
	main.settings.set_value("queue", "shuffle", on)
	if on:
		_shuffle_upcoming()
	elif not _unshuffled.is_empty():
		# The original order, with any files added since kept at the end.
		var extra: Array[String] = []
		for p: String in main.playlist:
			if p not in _unshuffled:
				extra.append(p)
		var restored: Array[String] = []
		for p: String in _unshuffled:
			if p in main.playlist:
				restored.append(p)
		restored.append_array(extra)
		main.playlist = restored
		_unshuffled.clear()
	_sync()


func _shuffle_upcoming() -> void:
	if main.playlist.size() < 3:
		return
	_unshuffled = main.playlist.duplicate()
	var cur: int = maxi(main.playlist_index, -1)
	var head: Array[String] = main.playlist.slice(0, cur + 1)
	var rest: Array[String] = main.playlist.slice(cur + 1)
	# Fisher-Yates with our own generator (tests can seed it).
	for i in range(rest.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := rest[i]
		rest[i] = rest[j]
		rest[j] = t
	head.append_array(rest)
	main.playlist = head


func seed_shuffle(s: int) -> void:
	_rng.seed = s


## Puts `path` right after the current file (moves it there if it is already queued).
func play_next(path: String) -> void:
	var i: int = main.playlist.find(path)
	if i >= 0 and i != main.playlist_index:
		main.playlist.remove_at(i)
	if path == main.current_path and i >= 0:
		return
	_sync()
	main.playlist.insert(main.playlist_index + 1, path)
	_sync()


func append(path: String) -> void:
	if main.playlist.find(path) < 0:
		main.playlist.append(path)
		_sync()


## Removes a queued file (not the one playing).
func remove(index: int) -> void:
	if index < 0 or index >= main.playlist.size() or index == main.playlist_index:
		return
	main.playlist.remove_at(index)
	_sync()


func move(from: int, to: int) -> void:
	var n: int = main.playlist.size()
	if from < 0 or from >= n or to < 0 or to >= n or from == to:
		return
	var p: String = main.playlist[from]
	main.playlist.remove_at(from)
	main.playlist.insert(to, p)
	_sync()


## Drops everything after the current file.
func clear_upcoming() -> void:
	main.playlist = main.playlist.slice(0, main.playlist_index + 1)
	_sync()


func jump(index: int) -> void:
	if index >= 0 and index < main.playlist.size():
		main.open_path(main.playlist[index], false)


## Called by main._on_ended before its own handling; true when the queue took care of it.
func on_ended() -> bool:
	if main.features.sleep.holds_auto_advance():
		return false
	if repeat == "one" and main.player.can_seek():
		main.player.seek(0.0)
		main.player.play()
		return true
	# A picture that ended is the slideshow moving on (scripts/play/slideshow.gd, ideas #22).
	var slideshow: bool = main.player.source != null and main.player.source.get_kind() == "image"
	if not (continuous or main.auto_advance or slideshow):
		return false
	# The up-next countdown (scripts/play/up_next.gd, #34) goes first when it applies; it opens the file at its end.
	var up_next: Node = main.features.get("up_next")
	if main.playlist_index + 1 < main.playlist.size():
		if up_next == null or not up_next.begin(main.playlist[main.playlist_index + 1], main.next_file):
			main.next_file()
		return true
	if repeat == "all" and not main.playlist.is_empty():
		var again := func() -> void:
			if shuffle:
				main.playlist_index = -1
				_shuffle_upcoming()
			main.open_path(main.playlist[0], false)
		if up_next == null or not up_next.begin(main.playlist[0], again):
			again.call()
		return true
	return false


func _sync() -> void:
	main.playlist_index = main.playlist.find(main.current_path)
	changed.emit()


static func _same_items(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for p: Variant in a:
		if p not in b:
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_T:
			cycle_repeat()
			print("Repeat: %s" % repeat)
		KEY_U:
			set_shuffle(not shuffle)
			print("Shuffle: %s" % ("on" if shuffle else "off"))
