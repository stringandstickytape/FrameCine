extends ScrollContainer

## The Room tab (docs/ui-design.md): environment (with photo rooms and glTF rooms, #18 / #53, "use this picture as
## the room", and the showrooms in a group of their own, docs/showrooms.md), seat (#19), floor reflection (#62), the
## room's effects (bias light #29, reacting to the film #81, the projector beam #92, time of day #84), room light (and
## whether it dims while the film plays), screen placement reset, recentre, the showing (curtains #37, up next #34,
## intermission #39), the sleep timer (#17), and the watch party (#51, scripts/party/watch_party.gd): host, join,
## leave, who is in it, and "the host plays a file that isn't open here". Each control is also a command
## (scripts/dev/room_tab_commands.gd), which calls the same code and then sync().
##
## Languages (docs/i18n.md): the rooms that ship and the showrooms show their names translated (ROOM_NAMES, and the
## showrooms' index.json); the viewer's own rooms, seat names an assistant gave, the party's names and what was typed
## are content. The built lines go through tr() in sync(), so they switch with the language.

const W := preload("res://ui/pane_widgets.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Recipes := preload("res://scripts/dev/recipes.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")
const SearchForm := preload("res://ui/search_form.gd")
const WatchParty := preload("res://scripts/party/watch_party.gd")

## Find it: the Files tab searches for the host's file by name.
signal find_requested(query: String)

const SLEEP_WORDS := ["Off", "15 min", "30 min", "60 min", "90 min", "End of file"] # i18n
## The names of the rooms that ship (main.gd ENVIRONMENTS, scripts/env/env_library.gd BUILT_IN), as keys: their rows
## translate them. test_i18n.gd checks that each built-in room's name is here.
# i18n: begin
const ROOM_NAMES := ["Void", "Dim room", "Cinema", "Passthrough", "Home theatre", "Drive-in", "Planetarium",
		"Dome"]
# i18n: end
## Why a watch party ended (scripts/party/watch_party.gd _end()): the reason, and how the tab says it (a key); a host's
## own refusal is its text.
# i18n: begin
const PARTY_ENDS := {"left": "you left", "no host found": "no host found", "the host went quiet": "the host went quiet",
		"the host ended the party": "the host ended the party"}
# i18n: end

var app: Node
var box: VBoxContainer
## One row per environment, rebuilt when the list changes (photo rooms and glTF rooms come and go).
## The rooms that ship with the app, then the viewer's own (kept rooms, glTF rooms, photo rooms: user data, never
## shipped) under their own heading, as the Objects tab does (the user, 2026-11-05).
var _envs: HFlowContainer
var _yours_box: VBoxContainer
var _yours: HFlowContainer
var _env_ids: Array[String] = []
## The showrooms (scripts/env/showrooms.gd), the list's last rows: their own group under the rooms, one row each.
var _showroom_box: VBoxContainer
var _showrooms: HFlowContainer
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
var _reflection_strength: VBoxContainer
var _bias: Button
var _bias_strength: VBoxContainer
var _react: Button
var _react_strength: VBoxContainer
var _react_note: Label
var _beam: Button
var _time_box: VBoxContainer
var _time_mode: HFlowContainer
var _latitude: VBoxContainer
var _curtains: Button
var _curtains_note: Label
var _up_next: Button
var _up_next_seconds: VBoxContainer
var _intermission: Button
var _intermission_minutes: VBoxContainer
var _intermission_note: Label
var _crossfade_music: VBoxContainer
var _crossfade_video: VBoxContainer
var _light: VBoxContainer
var _follow: Button
var _play_level: VBoxContainer
var _sleep: HFlowContainer
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
	box.add_child(W.label("Built in", &"MutedLabel"))
	_envs = W.flow()
	box.add_child(_envs)
	_yours_box = W.vbox()
	box.add_child(_yours_box)
	_yours_box.add_child(W.label("Yours", &"MutedLabel"))
	_yours = W.flow()
	_yours_box.add_child(_yours)
	_use_picture = W.button("Use this picture as the room", _use_picture_as_room)
	box.add_child(W.hbox([_use_picture]))
	_showroom_box = W.vbox()
	box.add_child(_showroom_box)
	_showroom_box.add_child(W.section("Showrooms"))
	_showrooms = W.flow()
	_showrooms.add_theme_constant_override("separation", 0)
	_showroom_box.add_child(_showrooms)

	# Seats (#19): rooms that have them.
	_seat_box = W.vbox()
	box.add_child(_seat_box)
	_seat_box.add_child(W.section("Seat"))
	var seat: Node = app.features.seat
	_seat_label = W.label("", &"MutedLabel")
	W.content(_seat_label)
	# Wraps: a seat's name and a longer language fit the card.
	_seat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seat_box.add_child(_seat_label)
	_seat_box.add_child(W.flow([W.button("Previous seat", func() -> void: seat.next_seat(-1)),
			W.button("Next seat", func() -> void: seat.next_seat(1)),
			W.button("Room's own spot", func() -> void: seat.go_to_seat(-1))]))
	# In the headset: the laser picks one (the layer's seat picking).
	_point_seat = W.button("Pick a seat", func() -> void: app.ui.start_seat_pick())
	_seat_moved = W.button("", func() -> void: seat.go_to_seat(int(seat.seat)))
	_seat_moved.visible = false
	W.content(_seat_moved)
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
	box.add_child(W.flow([_bias, _react, _beam]))
	_bias_strength = W.slider_row("Bias light", 0.0, 1.0, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: bias.set_strength(v))
	box.add_child(_bias_strength)
	_react_strength = W.slider_row("Reaction", 0.0, 1.0, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: react.set_strength(v))
	box.add_child(_react_strength)
	_react_note = W.label("", &"MutedLabel")
	W.content(_react_note)
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
	box.add_child(W.flow([W.button("Reset room", func() -> void: app.reset_room()),
			W.button("Reset screen", func() -> void: app.reset_screen())]))
	box.add_child(W.help("Reset room: back to the room's own seat, facing the screen, view recentred."))

	box.add_child(W.section("The showing"))
	var preshow: Node = app.features.preshow
	_curtains = W.toggle("Curtains", func(on: bool) -> void: preshow.set_enabled(on))
	var up_next: Node = app.features.up_next
	_up_next = W.toggle("Up next countdown", func(on: bool) -> void: up_next.set_enabled(on))
	var intermission: Node = app.features.intermission
	_intermission = W.toggle("Intermission", func(on: bool) -> void: intermission.set_enabled(on))
	box.add_child(W.flow([_curtains, _up_next, _intermission]))
	_curtains_note = W.label("", &"MutedLabel")
	W.content(_curtains_note)
	_curtains_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_curtains_note)
	_up_next_seconds = W.slider_row("Up next in", 3.0, 30.0, 1.0,
			func(v: float) -> String: return tr("%d s") % roundi(v), func(v: float) -> void: up_next.set_seconds(v))
	box.add_child(_up_next_seconds)
	_intermission_minutes = W.slider_row("Intermission", 1.0, 20.0, 1.0,
			func(v: float) -> String: return tr("%d min") % roundi(v),
			func(v: float) -> void: intermission.set_minutes(v))
	box.add_child(_intermission_minutes)
	_intermission_note = W.label("", &"MutedLabel")
	W.content(_intermission_note)
	_intermission_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_intermission_note)
	# Crossfade into the next file (#94): 0 is a plain cut (the default).
	var crossfade: Node = app.features.crossfade
	var fade_text := func(v: float) -> String: return tr("off") if v <= 0.0 else tr("%d s") % roundi(v)
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
	W.content(_sleep_status)
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
	_sleep_status.text = sleep.status_text(true) if sleep.active else ""


## A few times a second while the tab shows: the countdown, and the party's people and sync.
func tick() -> void:
	var sleep: Node = app.features.sleep
	if sleep.active:
		_sleep_status.text = sleep.status_text(true)
	_sync_showing()
	if _party_live() and not _party_form.visible:
		_sync_party()


## The environment rows: rebuilt when the list changed (a photo room or a glTF room added), else only the mark moves.
## The viewer's own rooms go under Yours, the showrooms in their own group (Showrooms); one mark for all.
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
		for holder: HFlowContainer in [_envs, _yours, _showrooms]:
			for c in holder.get_children():
				holder.remove_child(c)
				c.queue_free()
		var group := ButtonGroup.new()
		for e: Array in list:
			var id := str(e[0])
			var b := W.button(str(e[1]), func() -> void: app.set_environment(id))
			b.toggle_mode = true
			b.button_group = group
			# A room that ships translates its name (a key); the viewer's own is content, a photo room's word aside.
			if is_yours(id):
				W.content(b)
				if id.begins_with(EnvLibrary.SKY_PREFIX):
					b.text = tr("%s (photo)") % id.trim_prefix(EnvLibrary.SKY_PREFIX).get_basename()
					b.set_meta("photo", id.trim_prefix(EnvLibrary.SKY_PREFIX).get_basename())
			var holder := _showrooms if Showrooms.is_showroom(id) else (_yours if is_yours(id) else _envs)
			holder.add_child(b)
			_env_rows.append(b)
		_yours_box.visible = _yours.get_child_count() > 0
		_showroom_box.visible = _showrooms.get_child_count() > 0
	for i in _env_rows.size():
		_env_rows[i].set_pressed_no_signal(_env_ids[i] == str(app.env_id))
		if _env_rows[i].has_meta("photo"):
			_env_rows[i].text = tr("%s (photo)") % _env_rows[i].get_meta("photo")
	_use_picture.visible = bool(app.features.slideshow.is_picture()) and not str(app.current_path).begins_with("smb://")


## A room of the viewer's own: a kept room, a glTF room or a photo room (user data), not one that ships.
static func is_yours(id: String) -> bool:
	return id.begins_with(Recipes.PREFIX) or id.begins_with(EnvLibrary.SKY_PREFIX) or id.begins_with(EnvLibrary.ROOM_PREFIX)


## The name or PIN form has the tab: the other rows stay hidden until it closes (sync() then shows them right).
func _form_open() -> bool:
	return _party_form != null and _party_form.visible


## A photo room from the picture on show (#18): copied into the photo rooms and shown at once.
func _use_picture_as_room() -> void:
	var id := EnvLibrary.add_skybox(app.current_path)
	if id == "":
		app.ui.notify(tr("This picture can't be a room (only local pictures)."))
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
	var n := seats.size()
	if at >= 0 and at < names.size():
		_seat_label.text = (tr("%s (moved) (%d of %d)") if seat.moved else tr("%s (%d of %d)")) \
				% [seat_name(names, at), at + 1, n]
	elif seat.moved:
		_seat_label.text = tr_n("Where %s was (%d seat)", "Where %s was (%d seats)", n) % [seat.moved_name, n]
	else:
		_seat_label.text = tr_n("The room's own spot (%d seat)", "The room's own spot (%d seats)", n) % n
	_seat_moved.visible = bool(seat.moved) and at >= 0
	_seat_moved.text = tr("Go to %s") % seat_name(names, at) if at >= 0 and at < names.size() else ""
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
	_react_note.text = tr("Flashes only in rooms that react, such as the drive-in; the room pulses with the bass.") \
			if bool(f.react.enabled) and not bool(f.react.room_opts_in()) else ""
	_react_note.visible = _react_note.text != ""
	W.set_on(_beam, bool(f.projector.beam))
	_time_box.visible = app.env != null and app.env.has_method("set_time_of_day")
	W.set_choice(_time_mode, (f.time_of_day.MODES as Array).find(str(f.time_of_day.mode)))
	W.set_slider(_latitude, float(f.time_of_day.latitude))
	_latitude.visible = str(f.time_of_day.mode) == "clock"


## A seat's name for the row: one the room gave (content, an assistant's word), or "Seat 2" in the menus' language
## (seat_choice.gd names() keeps the English, as the settings and an assistant read it).
func seat_name(names: Array, i: int) -> String:
	var given := str(names[i])
	return tr("Seat %d") % (i + 1) if given == "Seat %d" % (i + 1) else given


## Curtains, up next and intermission (cheap: also each tick while the tab shows, for the countdowns).
func _sync_showing() -> void:
	if _form_open():
		return
	var f: Node = app.features
	W.set_on(_curtains, bool(f.preshow.enabled))
	_curtains_note.text = "" if f.preshow.available() \
			else tr("Curtains: in the cinema and the home theatre, flat screen.")
	_curtains_note.visible = _curtains_note.text != ""
	W.set_on(_up_next, bool(f.up_next.enabled))
	_up_next_seconds.visible = bool(f.up_next.enabled)
	W.set_slider(_up_next_seconds, float(f.up_next.seconds))
	W.set_on(_intermission, bool(f.intermission.enabled))
	_intermission_minutes.visible = bool(f.intermission.enabled)
	W.set_slider(_intermission_minutes, float(f.intermission.minutes))
	var note := ""
	if bool(f.intermission.active):
		note = tr("Intermission: %s left. Play ends it.") % W.short_clock(float(f.intermission.remaining))
	elif bool(f.intermission.enabled):
		var at: float = f.intermission.point()
		note = tr("This film stops at %s.") % W.clock(at) if at >= 0.0 \
				else tr("Films over %d min with chapters stop once, near the middle.") \
				% roundi(float(f.intermission.min_film_minutes))
	_intermission_note.text = note
	_intermission_note.visible = note != ""
	W.set_slider(_crossfade_music, float(f.crossfade.music_seconds))
	W.set_slider(_crossfade_video, float(f.crossfade.video_seconds))

# --- Watch party (#51) ----------------------------------------------------------------------------------------------

func _build_party() -> void:
	box.add_child(W.section("Watch party"))
	_party_status = W.label("", &"MutedLabel")
	W.content(_party_status)
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
	W.content(_party_file_label)
	_party_file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_file = W.hbox([_party_file_label, W.button("Find it", func() -> void:
		find_requested.emit(str(_needed.get("name", "")).get_basename()))])
	box.add_child(_party_file)
	_party_name = W.button("", func() -> void: _ask("name"))
	_party_pin = W.button("", func() -> void: _ask("pin"))
	W.content(_party_name)
	W.content(_party_pin)
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
			app.ui.notify(tr("Watch party ended: %s") % end_reason(reason)))
	_sync_party()


## Why the party ended, in the menus' language (a host's own refusal stays its text).
func end_reason(reason: String) -> String:
	if PARTY_ENDS.has(reason):
		return tr(str(PARTY_ENDS[reason]))
	if reason.begins_with("the host refused: "):
		return tr("the host refused: %s") % reason.trim_prefix("the host refused: ")
	return reason


## The host plays a file that isn't open here (and isn't at the same path): say so once per file, and offer a search.
func _on_file_needed(f: Dictionary) -> void:
	if str(f.get("name", "")) == str(_needed.get("name", "")):
		return
	_needed = f
	_sync_party()
	app.ui.notify(tr("The host plays %s. It isn't open here.") % f["name"] if str(f.get("name", "")) != ""
			else tr("The host plays a file that isn't open here."))


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
	var about := tr("Host plays one file on every headset on this network, on one clock; Join finds the first host.")
	if not live:
		_party_status.text = tr("Ended: %s. %s") % [end_reason(_party_ended), about] if _party_ended != "" else about
	elif str(st.get("role")) == "host":
		_party_status.text = tr("Hosting as %s. %s") % [st.get("name", ""), tr("Nobody has joined yet.")
				if people.is_empty() else tr("%d joined.") % people.size()]
	elif not bool(st.get("joined", false)):
		_party_status.text = tr("Looking for a host...")
	else:
		_party_status.text = tr("Joined, seat %d. %s") % [int(st.get("seat", 0)), _sync_text(st.get("sync", {}))]
	_party_start.visible = not live
	_party_leave.visible = live
	(_party_leave.get_child(0) as Button).text = "End party" if live and str(st.get("role")) == "host" else "Leave"
	for c in _party_people.get_children():
		_party_people.remove_child(c)
		c.queue_free()
	if live:
		# The names are the party's (what each headset was called): content.
		var rows: Array = [{"name": tr("%s (you)") % st.get("name", ""), "seat": int(st.get("seat", 0))}]
		rows.append_array(people)
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seat"]) < int(b["seat"]))
		for p: Dictionary in rows:
			var row := W.label(tr("Seat %d   %s") % [int(p["seat"]), p["name"]])
			W.content(row)
			_party_people.add_child(row)
	_party_file.visible = live and not _needed.is_empty()
	_party_file_label.text = tr("The host plays %s, which isn't open here.") % _needed.get("name", "") \
			if not _needed.is_empty() else ""
	_party_name.text = tr("Name: %s") % party_name()
	_party_pin.text = tr("PIN: set") if party_pin() != "" else tr("PIN: none")
	_party_name.disabled = live
	_party_pin.disabled = live


static func _sync_text(sync: Dictionary) -> String:
	if sync.is_empty():
		return ""
	if not bool(sync.get("same_file", true)):
		return TranslationServer.translate("Waiting for the host's file.")
	return TranslationServer.translate("In step within %d ms.") % roundi(absf(float(sync.get("error_ms", 0.0))))


## The name or PIN form takes the tab's place, like the Subtitles tab's Find a line.
func _ask(what: String) -> void:
	_party_asking = what
	if what == "name":
		_party_form.set_texts("Your name in the watch party", "Save", "a name", false) # i18n
	else:
		# The form's title, button and hint translate themselves (a Label, a Button, a placeholder).
		# i18n: begin
		_party_form.set_texts("The party's PIN (the host sets it, guests give the same; empty for none)", "Save",
				"digits", true)
		# i18n: end
	W.show_form(box, _party_form, true)
	scroll_vertical = 0
	_party_form.edit(party_name() if what == "name" else party_pin())
	(app.ui.ui as Node).call("set_form_mode", true)


func _answered(text: String) -> void:
	app.settings.set_value("party", _party_asking, text)
	_hide_form()


func _hide_form() -> void:
	W.show_form(box, _party_form, false)
	sync()
	(app.ui.ui as Node).call("set_form_mode", false)
