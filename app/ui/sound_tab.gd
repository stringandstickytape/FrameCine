extends ScrollContainer

## The Sound tab (docs/ui-design.md): audio track (with commentary and description flags when the engine gives them),
## volume, A/V offset, playback speed (#69, pitch kept), and playing the sound on a PC (#9, scripts/dev/pc_audio.gd:
## the headset goes silent and holds its picture back to match the PC's speakers), and speakers in the room (#21, #47:
## each channel from its place; world-locked sound for 180 / 360), night mode and dialogue boost (#26, when the engine
## has them), and a Calibrate button for the A/V offset (#24, the test lab's lab://av_sync card).
##
## Languages (docs/i18n.md): the status lines are built with tr() in _sync_speakers() / _sync_pc_audio(), so again on
## a language switch (sync()). A track's title, language and codec come from the file and are content; so are the PC's
## address and the HRTF sets' licences. The HRTF sets' names are keys (scripts/play/spatial_audio.gd).

const W := preload("res://ui/pane_widgets.gd")
const HelpTexts := preload("res://ui/help_texts.gd")
const SearchForm := preload("res://ui/search_form.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")
## A track's flags (the engine's track dictionary, PLAYER_FEATURES builds) and their words, in order.
const TRACK_FLAGS := ["default", "commentary", "visual_impaired", "hearing_impaired", "forced", "original"]
# i18n: begin
const TRACK_FLAG_WORDS := {"default": "default", "commentary": "commentary", "visual_impaired": "description",
		"hearing_impaired": "SDH", "forced": "forced", "original": "original"}
# i18n: end

var app: Node
var box: VBoxContainer
var _tracks: VBoxContainer
var _volume: VBoxContainer
var _env_sound: VBoxContainer
var _offset: VBoxContainer
var _speed: HFlowContainer
var _live_delay: VBoxContainer
var _night_box: VBoxContainer
var _night: Button
var _night_strength: VBoxContainer
var _boost: VBoxContainer
var _speakers: Button
var _lfe: Button
var _speakers_status: Label
var _spatial_box: VBoxContainer
var _reverb: VBoxContainer
var _output: HFlowContainer
var _hrtf_list: VBoxContainer
var _hrtf_get: Button
var _hrtf_offer := "" # A set not downloaded yet, its licence shown: _hrtf_get fetches it.
## A line after the status (fetching, fetched, a licence, an error), made when it shows: in the language of that moment.
var _hrtf_note := Callable()
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
	# The room's own sound (scripts/env/env_audio.gd): off to full, 18 dB under the film by default, and always ducked
	# under it.
	var env_audio: Node = app.features.env_audio
	_env_sound = W.slider_row("Environment sound", env_audio.MIN_DB, 0.0, 1.0,
			func(v: float) -> String: return tr("off") if v <= env_audio.MIN_DB + 0.01 else tr("%+d dB") % roundi(v),
			func(v: float) -> void: env_audio.set_environment_db(v))
	box.add_child(_env_sound)
	box.add_child(W.help("The room's own sound: rain, birds, the projector. It always stays under the film."))
	_offset = W.slider_row("A/V offset", -300.0, 300.0, 5.0, func(v: float) -> String: return tr("%+d ms") % roundi(v),
			func(v: float) -> void: app.set_av_offset(v / 1000.0))
	box.add_child(_offset)
	box.add_child(W.flow([W.button("Calibrate", func() -> void: app.open_path("lab://av_sync", false))]))
	# Live streams (udp://, http live): how far behind live to play; a change reopens a live stream.
	var live: Node = app.features.live
	_live_delay = W.slider_row("Live delay", 0.1, 2.5, 0.1, func(v: float) -> String: return tr("%.1f s") % v,
			func(v: float) -> void: live.set_latency(v))
	box.add_child(_live_delay)
	var speed: Node = app.features.speed
	box.add_child(W.section("Speed"))
	var words: Array = []
	for st: float in speed.STEPS:
		words.append(("%.2fx" % st).replace(".00x", "x").replace("0x", "x"))
	_speed = W.choices(words, func(i: int) -> void: speed.set_speed(speed.STEPS[i]))
	# Numbers ("1.5x").
	W.content(_speed)
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
	_boost = W.slider_row("Dialogue boost", 0.0, 12.0, 0.5, func(v: float) -> String: return tr("+%.1f dB") % v,
			func(v: float) -> void: night.set_dialogue_boost(v))
	_night_box.add_child(_boost)
	night.changed.connect(_sync_night)

	# Spatial sound (#21, #47; docs/features.md #21): turning it on reopens the file at its place.
	box.add_child(W.section("Spatial sound"))
	var speakers: Node = app.features.speakers
	_speakers = W.toggle("Spatial sound", func(on: bool) -> void:
		speakers.set_enabled(on)
		_sync_speakers())
	_lfe = W.toggle("Bass channel", func(on: bool) -> void:
		speakers.set_lfe(on)
		_sync_speakers())
	box.add_child(W.hbox([_speakers, _lfe]))
	_spatial_box = W.vbox()
	box.add_child(_spatial_box)
	# 0: no room at all (no reflections, no reverb), shown as Off; 100 %: the room as built.
	_reverb = W.slider_row("Room echo and reverb", 0.0, 200.0, 5.0,
			func(v: float) -> String: return tr("Off") if roundi(v) == 0 else "%d %%" % roundi(v),
			func(v: float) -> void: speakers.set_reverb(v / 100.0))
	_spatial_box.add_child(_reverb)
	_spatial_box.add_child(W.label("Sound plays on", &"MutedLabel"))
	_output = W.choices(["Auto", "Headset speakers", "Headphones"], func(i: int) -> void:
		speakers.set_output(["auto", "speakers", "headphones"][i])
		_sync_speakers())
	_spatial_box.add_child(_output)
	_spatial_box.add_child(W.label("Head measurements (HRTF)", &"MutedLabel"))
	_hrtf_list = VBoxContainer.new()
	_hrtf_list.add_theme_constant_override("separation", 0)
	_spatial_box.add_child(_hrtf_list)
	_hrtf_get = W.button("", func() -> void:
		var error: String = speakers.download_hrtf(_hrtf_offer)
		# A download's error as the engine says it.
		_hrtf_note = func() -> String: return error if error != "" else tr("Fetching...")
		_sync_speakers())
	# "Download <set>", built in _sync_hrtf_list().
	W.content(_hrtf_get)
	_spatial_box.add_child(W.hbox([_hrtf_get]))
	if "spatial_tune" in app.features:
		_spatial_box.add_child(W.flow([W.button("Tune spatial sound", func() -> void:
			app.features.spatial_tune.start())]))
	_speakers_status = W.label("", &"MutedLabel")
	W.content(_speakers_status)
	_speakers_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_speakers_status)
	speakers.changed.connect(func(_a: bool) -> void: _sync_speakers())
	speakers.download_finished.connect(func(id: String, error: String) -> void:
		_hrtf_note = func() -> String:
			return tr("Fetched; choose it above.") if error == "" else tr("Could not fetch %s: %s") % [id, error]
		_hrtf_offer = ""
		_sync_speakers())
	# "Play on a PC" (#9) is not in the menu (2026-11-09): a dev tool, started with --pc-audio=HOST instead.
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
	W.set_slider(_env_sound, float(app.features.env_audio.environment_db))
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
			parts.append(tr("%d ch") % int(t["channels"]))
		for flag in track_flags(t):
			parts.append(tr(flag))
		var index := int(t.get("index", 0))
		var b := W.button(" / ".join(parts) if not parts.is_empty() else tr("Track %d") % index,
				func() -> void: app.player.select_audio_track(index), &"RowButton")
		# The file's own title and language, and words translated above.
		W.content(b)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.set_pressed_no_signal(index == selected)
		_tracks.add_child(b)


## Words for a track's flags, when the engine's track dictionary has them (PLAYER_FEATURES builds). English, the
## keys: the menus translate each (tr()).
static func track_flags(t: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for flag: String in TRACK_FLAGS:
		if bool(t.get(flag, false)):
			out.append(TRACK_FLAG_WORDS[flag])
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


## Spatial sound's state: the settings, the HRTF sets, which channels play from where, or why the stereo mix plays.
func _sync_speakers() -> void:
	if _speakers == null:
		return
	var speakers: Node = app.features.speakers
	var on := bool(speakers.enabled)
	W.set_on(_speakers, on)
	W.set_on(_lfe, bool(speakers.lfe))
	_lfe.visible = on
	_spatial_box.visible = on
	W.set_slider(_reverb, float(speakers.reverb) * 100.0)
	W.set_choice(_output, ["auto", "speakers", "headphones"].find(str(speakers.output)))
	_sync_hrtf_list()
	var speed_one := is_equal_approx(float(app.features.speed.speed), 1.0)
	var lines: Array[String] = []
	if not on:
		lines.append(tr("Sound from speakers in the room, in front, behind and above you, outside your "
				+ "head; dialogue from the screen. It stays put when you turn your head."))
	elif not bool(speakers.available()):
		lines.append(tr("This player has no spatial sound (an older engine): the stereo mix plays."))
	elif bool(speakers.active):
		# The channels' short names (FL, FR, C...) as the engine gives them.
		var names: Array[String] = speakers.channels()
		var what := tr("the 360 sound field") if int(speakers.sound_field()) > 0 else ", ".join(names)
		lines.append((tr("From the room: %s. Headphones.") if speakers.profile() == "headphones"
				else tr("From the room: %s. The headset's speakers.")) % what)
		if not speed_one:
			lines.append(tr("At this speed the stereo mix plays."))
	else:
		lines.append(tr("The stereo mix plays for now (PC sound on, or no file open)."))
	var tuned: Dictionary = speakers.profile_settings().tuning
	if on and tuned.has("tuned_at"):
		lines.append(tr("Tuned to your ears: head size %d %%.") % roundi(float(tuned.get("itd_scale", 1.0)) * 100.0))
	if _hrtf_note.is_valid():
		lines.append(str(_hrtf_note.call()))
	_speakers_status.text = " ".join(lines)


## The HRTF sets: bundled and fetched ones to choose, the others to fetch (their licence shown first).
func _sync_hrtf_list() -> void:
	var speakers: Node = app.features.speakers
	for c in _hrtf_list.get_children():
		_hrtf_list.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for s: Dictionary in speakers.hrtf_sets():
		var id := str(s.id)
		var ready := bool(s.downloaded)
		var hrtf_name := tr(str(s.name))
		var licence := str(s.licence)
		var b := W.button(hrtf_name if ready else tr("Fetch: %s") % hrtf_name, func() -> void:
			if ready:
				_hrtf_offer = ""
				_hrtf_note = Callable()
				speakers.set_hrtf(id)
			else:
				_hrtf_offer = id
				# The licence as its authors wrote it.
				_hrtf_note = func() -> String: return tr("Licence: %s") % licence
			_sync_speakers(), &"RowButton")
		W.content(b)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if ready:
			b.toggle_mode = true
			b.button_group = group
			b.set_pressed_no_signal(id == str(speakers.hrtf))
		_hrtf_list.add_child(b)
	_hrtf_get.visible = _hrtf_offer != "" and str(speakers.downloading) == ""
	for s: Dictionary in speakers.hrtf_sets():
		if str(s.id) == _hrtf_offer:
			_hrtf_get.text = tr("Download %s") % tr(str(s.name))


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
	W.content(_pc_address)
	box.add_child(W.flow([_pc_toggle, _pc_address]))
	_pc_status = W.label("", &"MutedLabel")
	W.content(_pc_status)
	_pc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pc_status)
	_pc_form = SearchForm.new()
	# The form's title and button translate themselves (keys); the example address is a number.
	_pc_form.set_texts("The PC running tools/audio_sink.py: its address, or address:port", "Save", # i18n
			"192.168.1.10")
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
	_pc_address.text = tr("PC: %s") % (pc_host() if pc_host() != "" else tr("none set"))
	if n == null:
		_pc_status.text = tr("The headset goes silent and holds its picture back to match the PC's speakers.")
		return
	var st: Dictionary = n.status()
	if bool(st.get("connected", false)):
		_pc_status.text = tr("Playing on %s; the picture is held back %d ms.") % [st.get("host", ""),
				roundi(float(st.get("delay_ms", 0.0)))]
	else:
		# The connection's error as the stream says it.
		var err := str(st.get("error", ""))
		_pc_status.text = (tr("Connecting to %s... (%s)") % [st.get("host", ""), err]) if err != "" \
				else tr("Connecting to %s...") % st.get("host", "")


## A few times a second while the tab shows: the connection and the delay.
func tick() -> void:
	_sync_pc_audio()


## The address form takes the tab's place, like the Subtitles tab's Find a line.
func _ask_address() -> void:
	W.show_form(box, _pc_form, true)
	scroll_vertical = 0
	_pc_form.edit(pc_host())
	(app.ui.ui as Node).call("set_form_mode", true)


func _hide_form() -> void:
	W.show_form(box, _pc_form, false)
	(app.ui.ui as Node).call("set_form_mode", false)
	sync()
