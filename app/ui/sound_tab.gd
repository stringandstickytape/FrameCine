extends ScrollContainer

## The Sound tab (docs/ui-design.md): audio track (with commentary and description flags when the engine gives them),
## volume, A/V offset, playback speed (#69, pitch kept), and playing the sound on a PC (#9, scripts/dev/pc_audio.gd:
## the headset goes silent and holds its picture back to match the PC's speakers), and speakers in the room (#21, #47:
## each channel from its place; world-locked sound for 180 / 360), night mode and dialogue boost (#26, when the engine
## has them), and a Calibrate button for the A/V offset (#24, the test lab's lab://av_sync card).

const W := preload("res://ui/pane_widgets.gd")
const HelpTexts := preload("res://ui/help_texts.gd")
const SearchForm := preload("res://ui/search_form.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")

var app: Node
var box: VBoxContainer
var _tracks: VBoxContainer
var _volume: HBoxContainer
var _offset: HBoxContainer
var _speed: HBoxContainer
var _live_delay: HBoxContainer
var _night_box: VBoxContainer
var _night: Button
var _night_strength: HBoxContainer
var _boost: HBoxContainer
var _speakers: Button
var _lfe: Button
var _speakers_status: Label
var _pc_toggle: Button
var _pc_address: Button
var _pc_status: Label
var _pc_form: SearchForm


func _init() -> void:
	name = "Sound"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	box.add_child(W.section("Audio track"))
	_tracks = VBoxContainer.new()
	_tracks.add_theme_constant_override("separation", 0)
	box.add_child(_tracks)
	box.add_child(W.section("Level and timing"))
	_volume = W.slider_row("Volume", 0.0, 100.0, 1.0, func(v: float) -> String: return "%d %%" % roundi(v),
			func(v: float) -> void: app.set_volume(v / 100.0))
	box.add_child(_volume)
	_offset = W.slider_row("A/V offset", -300.0, 300.0, 5.0, func(v: float) -> String: return "%+d ms" % roundi(v),
			func(v: float) -> void: app.set_av_offset(v / 1000.0))
	box.add_child(_offset)
	box.add_child(W.hbox([W.button("Calibrate", func() -> void: app.open_path("lab://av_sync", false))]))
	# Live streams (udp://, http live): how far behind live to play; a change reopens a live stream.
	var live: Node = app.features.live
	_live_delay = W.slider_row("Live delay", 0.1, 2.5, 0.1, func(v: float) -> String: return "%.1f s" % v,
			func(v: float) -> void: live.set_latency(v))
	box.add_child(_live_delay)
	var speed: Node = app.features.speed
	box.add_child(W.section("Speed"))
	var words: Array = []
	for st: float in speed.STEPS:
		words.append(("%.2fx" % st).replace(".00x", "x").replace("0x", "x"))
	_speed = W.choices(words, func(i: int) -> void: speed.set_speed(speed.STEPS[i]))
	box.add_child(_speed)
	speed.changed.connect(func(_s: float) -> void: sync())

	# Night mode and dialogue boost (#26): only when the engine has them.
	var night: Node = app.features.night
	_night_box = W.vbox()
	box.add_child(_night_box)
	_night_box.add_child(W.section("Night mode"))
	_night = W.toggle("Night mode", func(on: bool) -> void: night.set_night(on))
	_night_box.add_child(W.hbox([_night]))
	_night_strength = W.slider_row("Evening out", 0.0, 1.0, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: night.set_strength(v))
	_night_box.add_child(_night_strength)
	_boost = W.slider_row("Dialogue boost", 0.0, 12.0, 0.5, func(v: float) -> String: return "+%.1f dB" % v,
			func(v: float) -> void: night.set_dialogue_boost(v))
	_night_box.add_child(_boost)
	night.changed.connect(_sync_night)

	# Speakers in the room (#21, #47): turning them on reopens the file at its place.
	box.add_child(W.section("Speakers"))
	var speakers: Node = app.features.speakers
	_speakers = W.toggle("Speakers in the room", func(on: bool) -> void:
		speakers.set_enabled(on)
		_sync_speakers())
	_lfe = W.toggle("Bass channel", func(on: bool) -> void:
		speakers.set_lfe(on)
		_sync_speakers())
	box.add_child(W.hbox([_speakers, _lfe]))
	_speakers_status = W.label("", &"MutedLabel")
	_speakers_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_speakers_status)
	speakers.changed.connect(func(_a: bool) -> void: _sync_speakers())
	_build_pc_audio()
	app.audio_settings_changed.connect(sync)
	app.file_opened.connect(func(_p: String) -> void:
		sync_tracks()
		_sync_night.call_deferred())
	app.player.audio_track_selected.connect(func(_i: int) -> void: sync_tracks())
	sync()
	sync_tracks()
	# A plain-words line under each control whose name does not say what it does (ui/help_texts.gd).
	HelpTexts.attach(box, "sound")


func sync() -> void:
	W.set_slider(_volume, app.volume * 100.0)
	W.set_slider(_offset, app.player.av_offset * 1000.0)
	var speed: Node = app.features.speed
	W.set_choice(_speed, (speed.STEPS as Array).find(speed.speed))
	W.set_slider(_live_delay, float(app.features.live.latency))
	_sync_night()
	_sync_speakers()
	_sync_pc_audio()


## One row per track: title, language, codec, channels. The selected track is marked.
func sync_tracks() -> void:
	for c in _tracks.get_children():
		_tracks.remove_child(c)
		c.queue_free()
	var src = app.player.source
	var tracks: Array = src.get_audio_tracks() if src != null else []
	if tracks.is_empty():
		_tracks.add_child(W.label("No audio tracks", &"MutedLabel"))
		return
	var selected := int(src.get_audio_track()) if src.has_method("get_audio_track") else 0
	var group := ButtonGroup.new()
	for t: Dictionary in tracks:
		var parts: Array[String] = []
		for key: String in ["title", "language", "codec"]:
			if str(t.get(key, "")) != "":
				parts.append(str(t[key]))
		if int(t.get("channels", 0)) > 0:
			parts.append("%d ch" % int(t["channels"]))
		parts.append_array(track_flags(t))
		var index := int(t.get("index", 0))
		var b := W.button(" / ".join(parts) if not parts.is_empty() else "Track %d" % index,
				func() -> void: app.player.select_audio_track(index), &"RowButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.set_pressed_no_signal(index == selected)
		_tracks.add_child(b)


## Words for a track's flags, when the engine's track dictionary has them (PLAYER_FEATURES builds).
static func track_flags(t: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in [["default", "default"], ["commentary", "commentary"], ["visual_impaired", "description"],
			["hearing_impaired", "SDH"], ["forced", "forced"], ["original", "original"]]:
		if bool(t.get(pair[0], false)):
			out.append(pair[1])
	return out


## Night mode: hidden on engines without it; the boost greyed for files without a centre channel.
func _sync_night() -> void:
	if _night_box == null:
		return
	var night: Node = app.features.night
	_night_box.visible = bool(night.available())
	W.set_on(_night, bool(night.night))
	W.set_slider(_night_strength, float(night.strength))
	_night_strength.visible = bool(night.night)
	W.set_slider(_boost, float(night.boost_db))
	W.slider_of(_boost).editable = bool(night.boost_applies())


## The speakers' state: which channels play from where, or why the stereo mix plays instead.
func _sync_speakers() -> void:
	if _speakers == null:
		return
	var speakers: Node = app.features.speakers
	W.set_on(_speakers, bool(speakers.enabled))
	W.set_on(_lfe, bool(speakers.lfe))
	_lfe.visible = bool(speakers.enabled)
	if not bool(speakers.enabled):
		_speakers_status.text = "Each channel from its place in the room: dialogue from the screen, surrounds beside " \
				+ "and behind you."
	elif bool(speakers.active):
		_speakers_status.text = "Playing from the room: %s." % ", ".join(speakers.channels())
	else:
		_speakers_status.text = "The stereo mix plays for now (another speed than 1x, PC sound on, or no file open)."


# --- Sound on a PC (#9) ---------------------------------------------------------------------------------------------

func _build_pc_audio() -> void:
	box.add_child(W.section("Play on a PC"))
	_pc_toggle = W.toggle("Play sound on a PC", func(on: bool) -> void:
		if not on:
			PCAudio.stop()
		elif pc_host() == "":
			_ask_address()
		else:
			PCAudio.start(app, pc_host())
		_sync_pc_audio.call_deferred())
	_pc_address = W.button("", _ask_address)
	box.add_child(W.hbox([_pc_toggle, _pc_address]))
	_pc_status = W.label("", &"MutedLabel")
	_pc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pc_status)
	_pc_form = SearchForm.new()
	_pc_form.set_texts("The PC running tools/audio_sink.py: its address, or address:port", "Save", "192.168.1.10",
			false)
	_pc_form.visible = false
	_pc_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pc_form.search_requested.connect(func(text: String) -> void:
		app.settings.set_value("pc_audio", "host", text)
		# Asked for by the switch (still on) or by the address button with the stream running: (re)start.
		var wanted := _pc_toggle.button_pressed
		if wanted:
			PCAudio.start(app, text)
		_hide_form()
		_sync_pc_audio.call_deferred())
	_pc_form.cancelled.connect(_hide_form)
	box.add_child(_pc_form)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and _pc_form.visible:
			_hide_form())


## The PC's address: the saved one, else the running stream's.
func pc_host() -> String:
	var h := str(app.settings.get_value("pc_audio", "host", ""))
	var n := PCAudio.instance()
	if h == "" and n != null:
		h = str(n.get("host"))
	return h


func _sync_pc_audio() -> void:
	if _pc_toggle == null or _pc_form.visible:
		return
	var n := PCAudio.instance()
	if n != null and n.is_queued_for_deletion():
		n = null
	W.set_on(_pc_toggle, n != null)
	_pc_address.text = "PC: %s" % (pc_host() if pc_host() != "" else "none set")
	if n == null:
		_pc_status.text = "The headset goes silent and holds its picture back to match the PC's speakers."
		return
	var st: Dictionary = n.status()
	if bool(st.get("connected", false)):
		_pc_status.text = "Playing on %s; the picture is held back %d ms." % [st.get("host", ""),
				roundi(float(st.get("delay_ms", 0.0)))]
	else:
		var err := str(st.get("error", ""))
		_pc_status.text = "Connecting to %s...%s" % [st.get("host", ""), (" (%s)" % err) if err != "" else ""]


## A few times a second while the tab shows: the connection and the delay.
func tick() -> void:
	_sync_pc_audio()


## The address form takes the tab's place, like the Subtitles tab's Find a line.
func _ask_address() -> void:
	for c in box.get_children():
		(c as Control).visible = c == _pc_form
	scroll_vertical = 0
	_pc_form.edit(pc_host())
	(app.ui.ui as Node).call("set_form_mode", true)


func _hide_form() -> void:
	for c in box.get_children():
		(c as Control).visible = c != _pc_form
	(app.ui.ui as Node).call("set_form_mode", false)
	sync()
