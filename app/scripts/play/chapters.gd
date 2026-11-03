extends Node

## Chapters (ideas #15): the file's chapter list, chapter skip, titles for the overlay and tick positions for the seek
## bar. The list comes from the source's get_chapters(): MediaSource.get_chapters() once the engine has it (requested
## from the engine fork; until then real files have none), and five chapters on every test pattern.
##
##   chapters                [{index, start, end, title}] sorted, ends filled in from the next start or the duration,
##                           empty titles named "Chapter N"
##   current                 index of the chapter playing now, -1 when none
##   next_chapter()          to the start of the next chapter (nothing after the last)
##   previous_chapter()      to the start of this chapter when more than RESTART_SECONDS into it, else the previous one
##   go_to(index)            to a chapter's start
##   index_at(t), title_text() ("3/12 Title"), tick_positions() (chapter starts as fractions of the duration, the
##                           first chapter's 0 left out: the seek bar's ticks)
##   signals chapters_changed(chapters), chapter_changed(index, title)
## Controls: the left d-pad, left / right (only with the opt-in action map xr/openxr_action_map_dpad.tres, see
## tools/make_action_map.gd), and PageUp / PageDown on a keyboard (menu hidden).

signal chapters_changed(chapters: Array)
signal chapter_changed(index: int, title: String)

const RESTART_SECONDS := 3.0

var main: Node3D
var chapters: Array[Dictionary] = []
var current := -1
var _timer := 0.0


func _ready() -> void:
	main.file_opened.connect(func(_p: String) -> void: reload())
	main.player.seeked.connect(func(_t: float) -> void: _timer = 1.0)
	for hand: XRController3D in [main.left_hand, main.right_hand]:
		hand.button_pressed.connect(_on_button)


## Re-reads the list from the source (also when the duration becomes known later).
func reload() -> void:
	chapters = normalise(main.player.source.get_chapters() if main.player.has_source() else [],
			main.player.get_duration())
	current = -1
	chapters_changed.emit(chapters)
	_update_current()


## Sorted by start, ends from the next start (or the duration), titles filled in, re-indexed.
static func normalise(raw: Array, duration: float) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for c: Dictionary in raw:
		list.append({"start": maxf(float(c.get("start", 0.0)), 0.0), "end": float(c.get("end", -1.0)),
				"title": str(c.get("title", "")).strip_edges()})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start"] < b["start"])
	for i in list.size():
		var c := list[i]
		c["index"] = i
		var next_start: float = list[i + 1]["start"] if i + 1 < list.size() else (duration if duration > 0.0 else -1.0)
		if c["end"] <= c["start"] or (next_start > 0.0 and c["end"] > next_start):
			c["end"] = next_start
		if c["title"] == "":
			c["title"] = "Chapter %d" % (i + 1)
	return list


func index_at(t: float) -> int:
	var found := -1
	for c in chapters:
		if float(c["start"]) <= t + 0.01:
			found = int(c["index"])
		else:
			break
	return found


func next_chapter() -> void:
	var i := index_at(main.player.get_position())
	if i + 1 < chapters.size():
		go_to(i + 1)


func previous_chapter() -> void:
	var t: float = main.player.get_position()
	var i := index_at(t)
	if i < 0:
		return
	if t - float(chapters[i]["start"]) > RESTART_SECONDS or i == 0:
		go_to(i)
	else:
		go_to(i - 1)


func go_to(index: int) -> void:
	if index < 0 or index >= chapters.size() or not main.player.can_seek():
		return
	main.player.seek(float(chapters[index]["start"]))
	_update_current()


## "3/12 Title" for the chapter playing now, or "".
func title_text() -> String:
	if current < 0:
		return ""
	return "%d/%d %s" % [current + 1, chapters.size(), chapters[current]["title"]]


## Chapter starts as fractions of the duration (the first chapter's start at 0 left out).
func tick_positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d: float = main.player.get_duration()
	if d <= 0.0:
		return out
	for c in chapters:
		var f := float(c["start"]) / d
		if f > 0.001 and f < 1.0:
			out.append(f)
	return out


func _process(delta: float) -> void:
	if chapters.is_empty():
		return
	_timer += delta
	if _timer >= 0.25:
		_timer = 0.0
		_update_current()


func _update_current() -> void:
	var i := index_at(main.player.get_position()) if main.player.has_source() else -1
	if i != current:
		current = i
		chapter_changed.emit(i, str(chapters[i]["title"]) if i >= 0 else "")


func _on_button(action: String) -> void:
	match action:
		"chapter_next":
			next_chapter()
		"chapter_prev":
			previous_chapter()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	match key.keycode:
		KEY_PAGEDOWN:
			next_chapter()
		KEY_PAGEUP:
			previous_chapter()
		_:
			return
	print("Chapter %s" % title_text())
