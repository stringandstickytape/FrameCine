extends ScrollContainer

## The Room tab (docs/ui-design.md): environment (with photo rooms and glTF rooms, #18 / #53, "use this picture as
## the room", and the showrooms in a group of their own, docs/showrooms.md), seat (#19), floor reflection (#62), the
## room's effects (bias light #29, reacting to the film #81, the projector beam #92, time of day #84), room light (and
## whether it dims while the film plays), screen placement reset, recentre, the showing (curtains #37, up next #34,
## intermission #39), the sleep timer (#17), and the watch party (#51, scripts/party/watch_party.gd): host, join,
## leave, who is in it, and "the host plays a file that isn't open here". Each control is also a command
## (scripts/dev/room_tab_commands.gd), which calls the same code and then sync().

const W := preload("res://ui/pane_widgets.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")
const SearchForm := preload("res://ui/search_form.gd")
const WatchParty := preload("res://scripts/party/watch_party.gd")

## Find it: the Files tab searches for the host's file by name.
signal find_requested(query: String)

const SLEEP_WORDS := ["Off", "15 min", "30 min", "60 min", "90 min", "End of file"]

var app: Node
var box: VBoxContainer
## One row per environment, rebuilt when the list changes (photo rooms and glTF rooms come and go).
var _envs: VBoxContainer
var _env_ids: Array[String] = []
## The showrooms (scripts/env/showrooms.gd), the list's last rows: their own group under the rooms, one row each.
var _showroom_box: VBoxContainer
var _showrooms: VBoxContainer
## Every environment row, the rooms' then the showrooms', in _env_ids' order.
var _env_rows: Array[Button] = []
var _use_picture: Button
var _seat_box: VBoxContainer
var _seat_label: Label
var _point_seat: Button
## An assistant moved the viewer's seat: goes there (faded).
var _seat_moved: Button
var _reflection_box: VBoxContainer
var _reflection: Button
var _reflection_strength: HBoxContainer
var _bias: Button
var _bias_strength: HBoxContainer
var _react: Button
var _react_strength: HBoxContainer
var _react_note: Label
var _beam: Button
var _time_box: VBoxContainer
var _time_mode: HBoxContainer
var _latitude: HBoxContainer
var _curtains: Button
var _curtains_note: Label
var _up_next: Button
var _up_next_seconds: HBoxContainer
var _intermission: Button
var _intermission_minutes: HBoxContainer
var _intermission_note: Label
var _crossfade_music: HBoxContainer
var _crossfade_video: HBoxContainer
var _light: HBoxContainer
var _follow: Button
var _play_level: HBoxContainer
var _sleep: HBoxContainer
var _sleep_status: Label
var _party: Node
var _party_status: Label
var _party_start: HBoxContainer
var _party_leave: HBoxContainer
var _party_people: VBoxContainer
var _party_file: HBoxContainer
var _party_file_label: Label
var _party_name: Button
var _party_pin: Button
var _party_form: SearchForm
## "name" or "pin": what the form is asking.
var _party_asking := ""
var _party_ended := ""
var _needed: Dictionary = {}


func _init() -> void:
	name = "Room"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	box.add_child(W.section("Environment"))
	_envs = VBoxContainer.new()
	_envs.add_theme_constant_override("separation", 0)
	box.add_child(_envs)
	_use_picture = W.button("Use this picture as the room", _use_picture_as_room)
	box.add_child(W.hbox([_use_picture]))
	_showroom_box = W.vbox()
	box.add_child(_showroom_box)
	_showroom_box.add_child(W.section("Showrooms"))
	_showrooms = VBoxContainer.new()
	_showrooms.add_theme_constant_override("separation", 0)
	_showroom_box.add_child(_showrooms)

	# Seats (#19): rooms that have them.
	_seat_box = W.vbox()
	box.add_child(_seat_box)
	_seat_box.add_child(W.section("Seat"))
	var seat: Node = app.features.seat
	_seat_label = W.label("", &"MutedLabel")
	_seat_box.add_child(_seat_label)
	_seat_box.add_child(W.hbox([W.button("Previous seat", func() -> void: seat.next_seat(-1)),
			W.button("Next seat", func() -> void: seat.next_seat(1)),
			W.button("Room's own spot", func() -> void: seat.go_to_seat(-1))]))
	# In the headset: the laser picks one (the layer's seat picking).
	_point_seat = W.button("Pick a seat", func() -> void: app.ui.start_seat_pick())
	_seat_moved = W.button("", func() -> void: seat.go_to_seat(int(seat.seat)))
	_seat_moved.visible = false
	_seat_box.add_child(W.hbox([_point_seat, _seat_moved]))
	seat.changed.connect(func(_s: int) -> void: _sync_room_parts())

	# Floor reflection (#62): rooms with a floor for it.
	_reflection_box = W.vbox()
	box.add_child(_reflection_box)
	var reflection: Node = app.features.reflection
	_reflection = W.toggle("Floor reflection", func(on: bool) -> void: reflection.set_enabled(on))
	_reflection_box.add_child(W.hbox([_reflection]))
	_reflection_strength = W.slider_row("Reflection", 0.0, 0.6, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: reflection.set_strength(v))
	_reflection_box.add_child(_reflection_strength)
	reflection.changed.connect(_sync_room_parts)

	# The room's effects.
	box.add_child(W.section("Effects"))
	var bias: Node = app.features.bias
	_bias = W.toggle("Bias light", func(on: bool) -> void:
		bias.set_enabled(on)
		_sync_room_parts())
	var react: Node = app.features.react
	_react = W.toggle("React to the film", func(on: bool) -> void:
		react.set_enabled(on)
		_sync_room_parts())
	var projector: Node = app.features.projector
	_beam = W.toggle("Projector beam", func(on: bool) -> void:
		projector.set_beam(on)
		_sync_room_parts())
	box.add_child(W.hbox([_bias, _react, _beam]))
	_bias_strength = W.slider_row("Bias light", 0.0, 1.0, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: bias.set_strength(v))
	box.add_child(_bias_strength)
	_react_strength = W.slider_row("Reaction", 0.0, 1.0, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: react.set_strength(v))
	box.add_child(_react_strength)
	_react_note = W.label("", &"MutedLabel")
	_react_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_react_note)
	bias.changed.connect(_sync_room_parts)
	projector.changed.connect(_sync_room_parts)

	# Time of day (#84): outdoor rooms only.
	_time_box = W.vbox()
	box.add_child(_time_box)
	var time_of_day: Node = app.features.time_of_day
	_time_box.add_child(W.label("Time of day"))
	_time_mode = W.choices(["Night", "Now", "Dusk", "Day"], func(i: int) -> void:
		time_of_day.set_mode(time_of_day.MODES[i])
		_sync_room_parts())
	_time_box.add_child(_time_mode)
	_latitude = W.slider_row("Latitude", -90.0, 90.0, 1.0, func(v: float) -> String: return "%+d°" % roundi(v),
			func(v: float) -> void: time_of_day.set_latitude(v))
	_time_box.add_child(_latitude)
	_light = W.slider_row("Room light", 0.0, 2.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: app.set_room_light(v))
	box.add_child(_light)
	var follow: Node = app.features.light_follow
	_follow = W.toggle("Dim while playing", func(on: bool) -> void: follow.set_enabled(on))
	box.add_child(W.hbox([_follow]))
	_play_level = W.slider_row("Dimmed to", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: follow.set_play_level(v))
	box.add_child(_play_level)

	box.add_child(W.section("Placement"))
	# "Reset room" replaces "Recentre", which recentred the view and turned the screen to the gaze in the same frame,
	# before the recentre had moved the camera: the screen swung away from the room, into a wall (headset, 2026-10-31).
	box.add_child(W.hbox([W.button("Reset room", func() -> void: app.reset_room()),
			W.button("Reset screen", func() -> void: app.reset_screen())]))
	box.add_child(W.help("Reset room: back to the room's own seat, facing the screen, view recentred."))

	box.add_child(W.section("The showing"))
	var preshow: Node = app.features.preshow
	_curtains = W.toggle("Curtains", func(on: bool) -> void: preshow.set_enabled(on))
	var up_next: Node = app.features.up_next
	_up_next = W.toggle("Up next countdown", func(on: bool) -> void: up_next.set_enabled(on))
	var intermission: Node = app.features.intermission
	_intermission = W.toggle("Intermission", func(on: bool) -> void: intermission.set_enabled(on))
	box.add_child(W.hbox([_curtains, _up_next, _intermission]))
	_curtains_note = W.label("", &"MutedLabel")
	_curtains_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_curtains_note)
	_up_next_seconds = W.slider_row("Up next in", 3.0, 30.0, 1.0, func(v: float) -> String: return "%d s" % roundi(v),
			func(v: float) -> void: up_next.set_seconds(v))
	box.add_child(_up_next_seconds)
	_intermission_minutes = W.slider_row("Intermission", 1.0, 20.0, 1.0,
			func(v: float) -> String: return "%d min" % roundi(v), func(v: float) -> void: intermission.set_minutes(v))
	box.add_child(_intermission_minutes)
	_intermission_note = W.label("", &"MutedLabel")
	_intermission_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_intermission_note)
	# Crossfade into the next file (#94): 0 is a plain cut (the default).
	var crossfade: Node = app.features.crossfade
	var fade_text := func(v: float) -> String: return "off" if v <= 0.0 else "%d s" % roundi(v)
	_crossfade_music = W.slider_row("Crossfade music", 0.0, 12.0, 1.0, fade_text,
			func(v: float) -> void: crossfade.set_music_seconds(v))
	box.add_child(_crossfade_music)
	_crossfade_video = W.slider_row("Crossfade films", 0.0, 10.0, 1.0, fade_text,
			func(v: float) -> void: crossfade.set_video_seconds(v))
	box.add_child(_crossfade_video)

	box.add_child(W.section("Sleep timer"))
	var sleep: Node = app.features.sleep
	_sleep = W.choices(SLEEP_WORDS, func(i: int) -> void:
		match i:
			0:
				sleep.cancel()
			5:
				sleep.start_end_of_file()
			_:
				sleep.start(float(sleep.CHOICES[i - 1]))
		_sync_sleep())
	box.add_child(_sleep)
	_sleep_status = W.label("", &"MutedLabel")
	box.add_child(_sleep_status)
	sleep.changed.connect(func(_a: bool, _r: float) -> void: _sync_sleep())
	_build_party()
	app.environment_changed.connect(func(_id: String, _l: float) -> void: sync())
	sync()


func sync() -> void:
	_sync_envs()
	_sync_room_parts()
	_sync_showing()
	W.set_slider(_light, app.room_light)
	var follow: Node = app.features.light_follow
	W.set_on(_follow, follow.enabled)
	W.set_slider(_play_level, follow.play_level)
	_play_level.visible = follow.enabled
	_sync_sleep()
	check_party()
	_sync_party()


func _sync_sleep() -> void:
	var sleep: Node = app.features.sleep
	var choice := 0
	if sleep.active:
		if sleep.end_of_file:
			choice = 5
		else:
			var minutes := int(app.settings.get_value("sleep", "last_minutes", 0))
			choice = maxi(1, (sleep.CHOICES as Array).find(minutes) + 1)
	W.set_choice(_sleep, choice)
	_sleep_status.text = sleep.status_text() if sleep.active else ""


## A few times a second while the tab shows: the countdown, and the party's people and sync.
func tick() -> void:
	var sleep: Node = app.features.sleep
	if sleep.active:
		_sleep_status.text = sleep.status_text()
	_sync_showing()
	if _party_live() and not _party_form.visible:
		_sync_party()


## The environment rows: rebuilt when the list changed (a photo room or a glTF room added), else only the mark moves.
## The showrooms go in their own group (Showrooms), one mark for both.
func _sync_envs() -> void:
	if _form_open():
		return
	var list: Array = app.get_environment_list()
	var ids: Array[String] = []
	for e: Array in list:
		ids.append(str(e[0]))
	if ids != _env_ids:
		_env_ids = ids
		_env_rows.clear()
		for holder: VBoxContainer in [_envs, _showrooms]:
			for c in holder.get_children():
				holder.remove_child(c)
				c.queue_free()
		var group := ButtonGroup.new()
		for e: Array in list:
			var id := str(e[0])
			var b := W.button(str(e[1]), func() -> void: app.set_environment(id), &"RowButton")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_group = group
			(_showrooms if Showrooms.is_showroom(id) else _envs).add_child(b)
			_env_rows.append(b)
		_showroom_box.visible = _showrooms.get_child_count() > 0
	for i in _env_rows.size():
		_env_rows[i].set_pressed_no_signal(_env_ids[i] == str(app.env_id))
	_use_picture.visible = bool(app.features.slideshow.is_picture()) and not str(app.current_path).begins_with("smb://")


## The name or PIN form has the tab: the other rows stay hidden until it closes (sync() then shows them right).
func _form_open() -> bool:
	return _party_form != null and _party_form.visible


## A photo room from the picture on show (#18): copied into the photo rooms and shown at once.
func _use_picture_as_room() -> void:
	var id := EnvLibrary.add_skybox(app.current_path)
	if id == "":
		app.ui.notify("This picture can't be a room (only local pictures).")
		return
	app.set_environment(id)
	sync()


## Seats, the floor reflection and the effects: only what this room has.
func _sync_room_parts() -> void:
	if _form_open():
		return
	var seat: Node = app.features.seat
	var seats: Array = seat.seats()
	_seat_box.visible = not seats.is_empty()
	_point_seat.visible = bool(app.use_xr)
	var names: Array = seat.names()
	var at := int(seat.seat)
	if at >= 0 and at < names.size():
		_seat_label.text = "%s%s (%d of %d)" % [names[at], " (moved)" if seat.moved else "", at + 1, seats.size()]
	elif seat.moved:
		_seat_label.text = "Where %s was (%d seats)" % [seat.moved_name, seats.size()]
	else:
		_seat_label.text = "The room's own spot (%d seats)" % seats.size()
	_seat_moved.visible = bool(seat.moved) and at >= 0
	_seat_moved.text = "Go to %s" % names[at] if at >= 0 and at < names.size() else ""
	var reflection: Node = app.features.reflection
	_reflection_box.visible = bool(reflection.available())
	W.set_on(_reflection, bool(reflection.enabled))
	W.set_slider(_reflection_strength, float(reflection.strength))
	_reflection_strength.visible = bool(reflection.enabled)
	var f: Node = app.features
	W.set_on(_bias, bool(f.bias.enabled))
	W.set_slider(_bias_strength, float(f.bias.strength))
	_bias_strength.visible = bool(f.bias.enabled)
	W.set_on(_react, bool(f.react.enabled))
	W.set_slider(_react_strength, float(f.react.strength))
	_react_strength.visible = bool(f.react.enabled)
	_react_note.text = "Flashes only in rooms that react, such as the drive-in; the room pulses with the bass." \
			if bool(f.react.enabled) and not bool(f.react.room_opts_in()) else ""
	_react_note.visible = _react_note.text != ""
	W.set_on(_beam, bool(f.projector.beam))
	_time_box.visible = app.env != null and app.env.has_method("set_time_of_day")
	W.set_choice(_time_mode, (f.time_of_day.MODES as Array).find(str(f.time_of_day.mode)))
	W.set_slider(_latitude, float(f.time_of_day.latitude))
	_latitude.visible = str(f.time_of_day.mode) == "clock"


## Curtains, up next and intermission (cheap: also each tick while the tab shows, for the countdowns).
func _sync_showing() -> void:
	if _form_open():
		return
	var f: Node = app.features
	W.set_on(_curtains, bool(f.preshow.enabled))
	_curtains_note.text = "" if f.preshow.available() else "Curtains: in the cinema and the home theatre, flat screen."
	_curtains_note.visible = _curtains_note.text != ""
	W.set_on(_up_next, bool(f.up_next.enabled))
	_up_next_seconds.visible = bool(f.up_next.enabled)
	W.set_slider(_up_next_seconds, float(f.up_next.seconds))
	W.set_on(_intermission, bool(f.intermission.enabled))
	_intermission_minutes.visible = bool(f.intermission.enabled)
	W.set_slider(_intermission_minutes, float(f.intermission.minutes))
	var note := ""
	if bool(f.intermission.active):
		note = "Intermission: %s left. Play ends it." % W.short_clock(float(f.intermission.remaining))
	elif bool(f.intermission.enabled):
		var at: float = f.intermission.point()
		note = "This film stops at %s." % W.clock(at) if at >= 0.0 \
				else "Films over %d min with chapters stop once, near the middle." % roundi(float(f.intermission.min_film_minutes))
	_intermission_note.text = note
	_intermission_note.visible = note != ""
	W.set_slider(_crossfade_music, float(f.crossfade.music_seconds))
	W.set_slider(_crossfade_video, float(f.crossfade.video_seconds))

# --- Watch party (#51) ----------------------------------------------------------------------------------------------

func _build_party() -> void:
	box.add_child(W.section("Watch party"))
	_party_status = W.label("", &"MutedLabel")
	_party_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_party_status)
	_party_start = W.hbox([W.button("Host", _host), W.button("Join", _join)])
	box.add_child(_party_start)
	_party_leave = W.hbox([W.button("Leave", func() -> void: WatchParty.leave())])
	box.add_child(_party_leave)
	_party_people = VBoxContainer.new()
	_party_people.add_theme_constant_override("separation", 0)
	box.add_child(_party_people)
	_party_file_label = W.label("", &"MutedLabel")
	_party_file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_file = W.hbox([_party_file_label, W.button("Find it", func() -> void:
		find_requested.emit(str(_needed.get("name", "")).get_basename()))])
	box.add_child(_party_file)
	_party_name = W.button("", func() -> void: _ask("name"))
	_party_pin = W.button("", func() -> void: _ask("pin"))
	box.add_child(W.hbox([_party_name, _party_pin]))
	_party_form = SearchForm.new()
	_party_form.visible = false
	_party_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_party_form.search_requested.connect(_answered)
	_party_form.cancelled.connect(_hide_form)
	box.add_child(_party_form)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and _party_form.visible:
			_hide_form())
	app.file_opened.connect(func(_p: String) -> void:
		_needed = {}
		_sync_party())


## The name the others see under this headset's avatar: the saved one, else "Headset" (never the login name: it
## would show in the others' rooms and in screenshots).
func party_name() -> String:
	return WatchParty.saved_name(app)


func party_pin() -> String:
	return WatchParty.saved_pin(app)


func _host() -> void:
	_party_ended = ""
	_watch(WatchParty.host(app, party_name(), party_pin()))


func _join() -> void:
	_party_ended = ""
	_watch(WatchParty.join(app, party_name(), "", party_pin()))


## Called once a second by the layer (and on sync): a party started elsewhere (command line, PC link, phone) is
## picked up too, so its prompts show.
func check_party() -> void:
	var p := WatchParty.instance()
	if p != null and p != _party and str(p.get("role")) != "":
		_watch(p)


func _watch(p: Node) -> void:
	if p == null or p == _party:
		return
	_party = p
	_needed = {}
	p.peers_changed.connect(func(_l: Array) -> void: _sync_party())
	p.file_needed.connect(_on_file_needed)
	p.ended.connect(func(reason: String) -> void:
		if _party == p:
			_party = null
			_party_ended = reason
			_needed = {}
			_sync_party()
			app.ui.notify("Watch party ended: %s" % reason))
	_sync_party()


## The host plays a file that isn't open here (and isn't at the same path): say so once per file, and offer a search.
func _on_file_needed(f: Dictionary) -> void:
	if str(f.get("name", "")) == str(_needed.get("name", "")):
		return
	_needed = f
	_sync_party()
	app.ui.notify("The host plays %s. It isn't open here." % f.get("name", "a file"))


func _party_live() -> bool:
	return _party != null and is_instance_valid(_party) and str(_party.get("role")) != ""


func _sync_party() -> void:
	if _party_status == null:
		return
	var live := _party_live()
	var st: Dictionary = _party.status() if live else {}
	var people: Array = []
	if live:
		for p: Dictionary in st.get("peers", []):
			people.append(p)
	if not live:
		_party_status.text = ("Ended: %s. " % _party_ended if _party_ended != "" else "") \
				+ "Host plays one file on every headset on this network, on one clock; Join finds the first host."
	elif str(st.get("role")) == "host":
		_party_status.text = "Hosting as %s. %s" % [st.get("name", ""),
				"Nobody has joined yet." if people.is_empty() else "%d joined." % people.size()]
	elif not bool(st.get("joined", false)):
		_party_status.text = "Looking for a host..."
	else:
		_party_status.text = "Joined, seat %d. %s" % [int(st.get("seat", 0)), _sync_text(st.get("sync", {}))]
	_party_start.visible = not live
	_party_leave.visible = live
	(_party_leave.get_child(0) as Button).text = "End party" if live and str(st.get("role")) == "host" else "Leave"
	for c in _party_people.get_children():
		_party_people.remove_child(c)
		c.queue_free()
	if live:
		var rows: Array = [{"name": "%s (you)" % st.get("name", ""), "seat": int(st.get("seat", 0))}]
		rows.append_array(people)
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seat"]) < int(b["seat"]))
		for p: Dictionary in rows:
			_party_people.add_child(W.label("Seat %d   %s" % [int(p["seat"]), p["name"]]))
	_party_file.visible = live and not _needed.is_empty()
	_party_file_label.text = "The host plays %s, which isn't open here." % _needed.get("name", "") \
			if not _needed.is_empty() else ""
	_party_name.text = "Name: %s" % party_name()
	_party_pin.text = "PIN: %s" % ("set" if party_pin() != "" else "none")
	_party_name.disabled = live
	_party_pin.disabled = live


static func _sync_text(sync: Dictionary) -> String:
	if sync.is_empty():
		return ""
	if not bool(sync.get("same_file", true)):
		return "Waiting for the host's file."
	return "In step within %d ms." % roundi(absf(float(sync.get("error_ms", 0.0))))


## The name or PIN form takes the tab's place, like the Subtitles tab's Find a line.
func _ask(what: String) -> void:
	_party_asking = what
	if what == "name":
		_party_form.set_texts("Your name in the watch party", "Save", "a name", false)
	else:
		_party_form.set_texts("The party's PIN (the host sets it, guests give the same; empty for none)", "Save",
				"digits", true)
	for c in box.get_children():
		(c as Control).visible = c == _party_form
	scroll_vertical = 0
	_party_form.edit(party_name() if what == "name" else party_pin())
	(app.ui.ui as Node).call("set_form_mode", true)


func _answered(text: String) -> void:
	app.settings.set_value("party", _party_asking, text)
	_hide_form()


func _hide_form() -> void:
	for c in box.get_children():
		(c as Control).visible = c != _party_form
	sync()
	(app.ui.ui as Node).call("set_form_mode", false)
