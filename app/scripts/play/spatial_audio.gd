extends Node

## Spatial audio (ideas #21 virtual cinema speakers, #47 world-locked sound; docs/features.md #21): the film's
## sound from speakers in the room, heard through a head-related transfer function, so it comes from in front,
## behind, above, outside the head, and stays where it is when the head turns.
##
## How: the engine keeps the audio's own channels (MediaSource.discrete_channels, set before the file opens) and,
## with a BinauralRenderer on the source (MediaSource.set_spatial_renderer, fork branch frame/binaural), plays the
## renderer's binaural mix of them as the film's stereo stream: the same player, the same clock, no added latency.
## Here: which channel stands where (scripts/play/speaker_layouts.gd, the room's VREnvironment.get_sound_room()),
## the head's pose every frame, the room's reflections and reverb, the HRTF set and the output profile.
##   flat screen   the screen channels behind the picture, the rest where the room has them (walls, a ring)
##   180 / 360     a ring round the head facing the picture's front (#47); ambisonics turned the same way
##   ambisonics    the sound field of a 360 file (AmbiX: an SA3D box or Opus channel mapping 2), decoded by the
##                 engine to virtual speakers; a head-locked stereo pair plays straight
##   LFE           no direction; left out unless lfe is on (as in the stereo mix)
## At a speed other than 1 the engine plays the stereo mix (it time-stretches that only). With the sound on a PC
## (#9) the renderer is taken off, so the PC's speakers get the plain mix.
##
##   enabled, set_enabled(on)    [speakers] enabled (DEFAULT_ON); turning it on reopens the open file at its place
##   lfe, set_lfe(on)            [speakers] lfe (default off)
##   hrtf, set_hrtf(id)          the current output profile's HRTF set (hrtf_sets())
##   reverb, set_reverb(x)       [spatial] reverb: the room's reflections and reverb times x (0-2, default 1)
##   output, set_output(mode)    [spatial] output: "auto" (the sound device decides), "speakers", "headphones"
##   profile() -> String         the output profile in use: "speakers" (the headset's own) or "headphones"
##   active                      the binaural mix plays now
##   channels() -> Array[String] the placed channels, e.g. ["FL", "FR", "FC", "SL", "SR"]
##   speaker_position(name)      where a channel stands (world; 180 / 360 and ambisonics: a direction), or null
##   sources() -> Array          what the renderer was given: [{name, input, kind, position, gain, at_infinity}]
##   sound_field() -> int        the ambisonic order playing (0: channels)
##   hrtf_sets(), hrtf_file(id)  the sets (bundled, fetched, to fetch, with licences); a set's file or ""
##   profile_settings(), set_profile_eq(bands), set_profile_tuning(t)   per output profile
##   renderer                    the BinauralRenderer (null on an engine without one)
##   download_hrtf(id)           fetches a set that is not bundled (its licence: hrtf_sets()), converts it, keeps it
##   signal changed(active)

const HWVideoSource := preload("res://scripts/video/hw_video_source.gd")
const Layouts := preload("res://scripts/play/speaker_layouts.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")
const VREnv := preload("res://environments/vr_environment.gd")

signal changed(active: bool)
signal download_finished(id: String, error: String)

## Opt-in until the headset check (docs/features.md, #21, "On the headset") has passed; then this becomes true and
## spatial audio is on by default.
const DEFAULT_ON := false
const DEFAULT_HRTF := "sadie2_d1"
const PROFILES := ["speakers", "headphones"]
## The binaural mix against the stereo downmix: about the same loudness (tests/test_spatial_audio.gd measures it).
const GAIN := 0.7
## The standard layout's room (no room, an assistant's room): late reverb only, a small neutral room.
const STANDARD_ROOM := {"box": AABB(Vector3(-2.5, 0, -3), Vector3(5, 2.6, 5.5)), "ring": true, "distance": 2.5,
		"reflect": 0.0, "rt60": 0.35, "wet": 0.35}
## 180 / 360: the picture is the room; a little late reverb keeps the sound out of the head.
const SPHERE_ROOM := {"reflect": 0.0, "rt60": 0.3, "wet": 0.25}
const DETECT_SECONDS := 10.0

## Bundled sets (app/audio/hrtf, credits there): SADIE II, University of York, Apache License 2.0.
const BUNDLED := [
	{"id": "sadie2_d1", "name": "Dummy head A", "file": "res://audio/hrtf/sadie2_d1.fhrtf"},
	{"id": "sadie2_d2", "name": "Dummy head B", "file": "res://audio/hrtf/sadie2_d2.fhrtf"},
	{"id": "sadie2_h3", "name": "Listener H3", "file": "res://audio/hrtf/sadie2_h3.fhrtf"},
	{"id": "sadie2_h4", "name": "Listener H4", "file": "res://audio/hrtf/sadie2_h4.fhrtf"},
	{"id": "sadie2_h5", "name": "Listener H5", "file": "res://audio/hrtf/sadie2_h5.fhrtf"},
	{"id": "sadie2_h6", "name": "Listener H6", "file": "res://audio/hrtf/sadie2_h6.fhrtf"},
]
const BUNDLED_LICENCE := "SADIE II database, University of York: Apache License 2.0"
## Sets fetched on request (not in the repository: their licences differ, and they are large), with the licence
## shown before the download.
const DOWNLOADS := [
	{"id": "mit_dummy", "name": "Dummy head, MIT (normal ear)",
		"url": "https://sofacoustics.org/data/database/mit/mit_kemar_normal_pinna.sofa",
		"licence": "MIT Media Lab dummy head HRTF measurements (Gardner and Martin, 1994): free to use; cite the "
				+ "authors."},
	{"id": "hutubs_pp1", "name": "HUTUBS listener 1",
		"url": "https://sofacoustics.org/data/database/hutubs/pp1_HRIRs_measured.sofa",
		"licence": "HUTUBS, TU Berlin (Brinkmann et al., 2019): Creative Commons Attribution 4.0 (CC BY 4.0)."},
	{"id": "ari_nh2", "name": "ARI listener NH2",
		"url": "https://sofacoustics.org/data/database/ari/dtf_nh2.sofa",
		"licence": "ARI HRTF database, Acoustics Research Institute, Austrian Academy of Sciences: Creative Commons "
				+ "Attribution-ShareAlike 4.0 (CC BY-SA 4.0)."},
	{"id": "cipic_003", "name": "CIPIC subject 003",
		"url": "https://sofacoustics.org/data/database/cipic/subject_003.sofa",
		"licence": "CIPIC HRTF database, University of California, Davis (Algazi et al., 2001): the database's own "
				+ "terms, copyright The Regents of the University of California; cite the authors."},
]
const DOWNLOAD_DIR := "user://hrtf"

var main: Node3D
var enabled := false
var lfe := false
var hrtf := DEFAULT_HRTF
var reverb := 1.0
var output := "auto"
var detected := "" # What the sound device looks like: "speakers", "headphones", "" (unknown).
var active := false
var renderer: Object = null
var downloading := ""
var _source: Object = null
var _placed: Array = [] # [{name, input, kind, position, gain, at_infinity}]
var _given: Array = [] # The last set_sources() list.
var _room_given := {}
var _ambisonic := -1
var _ambisonic_frame := Basis()
var _reopen_at := -1.0
var _loaded_hrtf := ""
var _tuning_given := {}
var _eq_given: Array = []
var _detect_at := 0.0
var _detecting := false
var _http: HTTPRequest


func _ready() -> void:
	enabled = bool(main.settings.get_value("speakers", "enabled", DEFAULT_ON))
	lfe = bool(main.settings.get_value("speakers", "lfe", false))
	reverb = clampf(float(main.settings.get_value("spatial", "reverb", 1.0)), 0.0, 2.0)
	output = str(main.settings.get_value("spatial", "output", "auto"))
	if not output in ["auto", "speakers", "headphones"]:
		output = "auto"
	HWVideoSource.discrete_channels = enabled
	if ClassDB.class_exists("BinauralRenderer"):
		renderer = ClassDB.instantiate("BinauralRenderer")
	hrtf = _profile_hrtf()
	_apply_profile()
	main.file_opened.connect(_on_file_opened)
	main.player.audio_track_selected.connect(func(_i: int) -> void: _attach(true))


## Available: the engine has the renderer and an HRTF loaded.
func available() -> bool:
	return renderer != null and renderer.is_ready()


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("speakers", "enabled", on if on != DEFAULT_ON else null)
	HWVideoSource.discrete_channels = on
	var src: Object = main.player.source
	if on and src != null and src.has_method("has_discrete_channels") and not src.has_discrete_channels() \
			and main.current_path != "":
		# The channels are chosen when the file opens: open it again where it was.
		_reopen_at = main.player.get_position()
		main.open_path(main.current_path, false)
		changed.emit(active)
		return
	_attach(true)
	changed.emit(active)


func set_lfe(on: bool) -> void:
	lfe = on
	main.settings.set_value("speakers", "lfe", on if on else null)
	_given = []
	_update(true)


func set_reverb(amount: float) -> void:
	reverb = clampf(snappedf(amount, 0.05), 0.0, 2.0)
	main.settings.set_value("spatial", "reverb", reverb if not is_equal_approx(reverb, 1.0) else null)
	_room_given = {}
	_update(true)


func set_output(mode: String) -> void:
	output = mode if mode in ["auto", "speakers", "headphones"] else "auto"
	main.settings.set_value("spatial", "output", output if output != "auto" else null)
	_detect_at = 0.0
	hrtf = _profile_hrtf()
	_apply_profile()
	changed.emit(active)


## The output profile in use.
func profile() -> String:
	if output != "auto":
		return output
	return detected if detected in PROFILES else "speakers"


## The HRTF set for the current profile; remembered per profile.
func set_hrtf(p_id: String) -> bool:
	var id := p_id
	if hrtf_file(id) == "":
		return false
	hrtf = id
	main.settings.set_value("spatial", "hrtf_" + profile(), id if id != DEFAULT_HRTF else null)
	_apply_profile()
	changed.emit(active)
	return true


## Every set: [{id, name, licence, bundled, downloaded}].
func hrtf_sets() -> Array:
	var out: Array = []
	for s: Dictionary in BUNDLED:
		out.append({"id": s.id, "name": s.name, "licence": BUNDLED_LICENCE, "bundled": true, "downloaded": true})
	for s: Dictionary in DOWNLOADS:
		out.append({"id": s.id, "name": s.name, "licence": s.licence, "bundled": false,
				"downloaded": hrtf_file(s.id) != ""})
	return out




## The output profile's settings: {hrtf, eq: [{type, freq, gain_db, q}], tuning: {itd_scale, pinna_warp, concha_db}}.
## The EQ is the hook for a measured correction of the headset's speakers or of headphones; the tuning comes from
## the "Tune spatial sound" step (scripts/play/spatial_tune.gd).
func profile_settings(p := "") -> Dictionary:
	var name := p if p != "" else profile()
	var tuning: Variant = main.settings.get_value("spatial", "tuning_" + name, {})
	var eq: Variant = main.settings.get_value("spatial", "eq_" + name, [])
	return {"hrtf": str(main.settings.get_value("spatial", "hrtf_" + name, DEFAULT_HRTF)),
			"eq": eq if eq is Array else [], "tuning": tuning if tuning is Dictionary else {}}


func set_profile_eq(bands: Array, p := "") -> void:
	main.settings.set_value("spatial", "eq_" + (p if p != "" else profile()), bands if not bands.is_empty() else null)
	_apply_profile()


func set_profile_tuning(tuning: Dictionary, p := "") -> void:
	main.settings.set_value("spatial", "tuning_" + (p if p != "" else profile()),
			tuning if not tuning.is_empty() else null)
	_apply_profile()


func channels() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in _placed:
		if not str(s.name) in out:
			out.append(str(s.name))
	return out


func speaker_position(channel_name: String) -> Variant:
	for s: Dictionary in _placed:
		if s.name == channel_name:
			return s.position
	return null


func sources() -> Array:
	return _placed.duplicate(true)


## The ambisonic order of the sound field playing (a 360 file's), 0 for channels.
func sound_field() -> int:
	return maxi(_ambisonic, 0) if active else 0


## The renderer's CPU use while it plays: {load (share of one core), max_usec, sources, latency_frames}.
func stats() -> Dictionary:
	return renderer.get_stats() if renderer != null else {}


func _on_file_opened(_path: String) -> void:
	_attach(true)
	if _reopen_at >= 0.0:
		var t := _reopen_at
		_reopen_at = -1.0
		if main.player.can_seek():
			main.player.seek(t)
		changed.emit(active) # The pane refreshes after the switch, whether or not the file has channels.


## Puts the renderer on the open file's source (or takes it off), and the speakers where they go.
func _attach(force := false) -> void:
	var was := active
	var src: Object = main.player.source
	var want: bool = enabled and available() and src != null and src.has_method("has_discrete_channels") \
			and src.has_discrete_channels() and src.has_method("set_spatial_renderer") and PCAudio.instance() == null
	if src != _source and _source != null and is_instance_valid(_source) and _source.has_method("set_spatial_renderer"):
		_source.set_spatial_renderer(null)
	_source = src
	if src != null and src.has_method("set_spatial_renderer"):
		var on_source: Object = src.get_spatial_renderer() if src.has_method("get_spatial_renderer") else null
		if want and on_source != renderer:
			src.set_spatial_renderer(renderer)
		elif not want and on_source != null:
			src.set_spatial_renderer(null)
	active = want
	if not active:
		_placed = []
		_given = []
	else:
		_update(force)
	if active != was or force:
		changed.emit(active)


func _process(_delta: float) -> void:
	var src: Object = main.player.source
	var want: bool = enabled and available() and src != null and src.has_method("has_discrete_channels") \
			and src.has_discrete_channels() and PCAudio.instance() == null
	if src != _source or want != active:
		_attach()
		return
	if output == "auto" and enabled:
		_detect_output()
	if not active:
		return
	var cam: Node3D = main.camera
	if cam != null:
		renderer.set_listener(cam.global_transform)
	_update()


## The channel layout of the open file, its speakers in the room or round the head, and the room: given to the
## renderer when they change.
func _update(force := false) -> void:
	if not active or renderer == null:
		return
	var layout: Dictionary = _source.get_audio_layout() if _source.has_method("get_audio_layout") else {}
	var names: Array = Array(layout.get("names", PackedStringArray()))
	var spherical: bool = main.mode.is_spherical()
	var order := int(layout.get("ambisonic_order", -1))
	var ambi_channels := int(layout.get("ambisonic_channels", 0))
	var front := _front(spherical)
	var placed: Array = []
	var frame := Basis(Vector3.UP, -atan2(front.x, -front.z))
	if order >= 1:
		# The sound field: decoded by the engine, turned to face the picture's front. A head-locked pair after it.
		for i in range(ambi_channels, names.size()):
			placed.append({"name": "HL" if i == ambi_channels else "HR", "input": i, "index": i,
					"kind": "head_left" if i == ambi_channels else "head_right", "position": Vector3.ZERO, "gain": 1.0})
	elif spherical:
		placed = Layouts.ring(names, front, lfe)
	else:
		placed = _room_layout(names)
	for s: Dictionary in placed:
		s["input"] = int(s.get("index", 0))
	var given: Array = []
	for s: Dictionary in placed:
		given.append({"input": s.input, "kind": s.kind, "position": s.position, "gain": s.gain,
				"at_infinity": bool(s.get("at_infinity", false)), "reflections": not bool(s.get("at_infinity", false))})
	_placed = placed
	if force or given != _given:
		_given = given
		renderer.set_sources(given)
	var ambi := order if order >= 1 else 0
	if force or ambi != _ambisonic or not frame.is_equal_approx(_ambisonic_frame):
		_ambisonic = ambi
		_ambisonic_frame = frame
		renderer.set_ambisonics(ambi, 0, frame, 1.0)
	var room := _room(spherical or order >= 1)
	if force or room != _room_given:
		_room_given = room
		renderer.set_room(room)


func _front(spherical: bool) -> Vector3:
	if spherical:
		return Vector3(sin(main.screen_yaw), 0.0, -cos(main.screen_yaw))
	var cam: Node3D = main.camera
	var seat: Vector3 = cam.global_position if cam != null else Vector3(0, main.eye_height, 0)
	var f: Vector3 = main.screen.global_position - seat
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _sound_room() -> Dictionary:
	var env: Node = main.env
	var r: Dictionary = env.get_sound_room() if env != null and env.has_method("get_sound_room") else {}
	return r if not r.is_empty() else STANDARD_ROOM


## A flat screen: the room's layout, in the world.
func _room_layout(names: Array) -> Array:
	var env: Node3D = main.env
	var to_world: Transform3D = env.global_transform if env != null else Transform3D()
	var to_room := to_world.affine_inverse()
	var room := _sound_room()
	var seat := Vector3(0, VREnv.NOMINAL_EYE_HEIGHT, 0)
	var screen := {
		"center": to_room * (main.screen.global_position as Vector3),
		"right": (to_room.basis * (main.screen.global_transform.basis.x as Vector3)).normalized(),
		"width": float(main.screen.get_flat_size().x) if main.screen.has_method("get_flat_size") else 2.0,
	}
	var out := Layouts.place(names, room, seat, screen, lfe)
	for s: Dictionary in out:
		if s.kind == "point":
			s.position = to_world * (s.position as Vector3)
	return out


## The renderer's room: the walls in the world, scaled by the reverb amount.
func _room(no_walls: bool) -> Dictionary:
	var room := _sound_room()
	var wet := float(room.get("wet", 0.3)) * reverb
	if no_walls:
		# Only the late reverb: the box sizes it, nothing reflects.
		var sphere_wet := float(SPHERE_ROOM.wet) * reverb
		return {"min": Vector3(-3, 0, -3), "max": Vector3(3, 2.8, 3), "reflect": 0.0, "rt60": SPHERE_ROOM.rt60,
				"wet": sphere_wet, "enabled": sphere_wet > 0.0}
	var env: Node3D = main.env
	var box: AABB = room.get("box", STANDARD_ROOM.box)
	if env != null:
		box = env.global_transform * box
	var reflect: Variant = room.get("reflect", 0.4)
	return {"min": box.position, "max": box.end, "reflect": reflect, "rt60": float(room.get("rt60", 0.4)), "wet": wet,
			"enabled": wet > 0.0}


func _profile_hrtf() -> String:
	var id := str(main.settings.get_value("spatial", "hrtf_" + profile(), DEFAULT_HRTF))
	return id if hrtf_file(id) != "" else DEFAULT_HRTF


func hrtf_file(p_id: String) -> String:
	var id := p_id
	for s: Dictionary in BUNDLED:
		if s.id == id:
			return s.file
	for s: Dictionary in DOWNLOADS:
		if s.id != id:
			continue
		var path := DOWNLOAD_DIR.path_join(id + ".fhrtf")
		if FileAccess.file_exists(path):
			return path
	return ""


## The profile's HRTF set, EQ and tuning to the renderer.
func _apply_profile() -> void:
	if renderer == null:
		return
	var file := hrtf_file(hrtf)
	if file != "" and file != _loaded_hrtf:
		if renderer.load_hrtf(file) == OK:
			_loaded_hrtf = file
		else:
			push_warning("Spatial audio: can't load %s (%s)" % [file, renderer.get_last_error()])
	var ps := profile_settings()
	var tuning: Dictionary = ps.tuning
	var t := {"itd_scale": float(tuning.get("itd_scale", 1.0)), "pinna_warp": float(tuning.get("pinna_warp", 1.0)),
			"concha_db": float(tuning.get("concha_db", 0.0))}
	if t != _tuning_given:
		_tuning_given = t
		renderer.set_tuning(t.itd_scale, t.pinna_warp, t.concha_db)
	if ps.eq != _eq_given:
		_eq_given = (ps.eq as Array).duplicate(true)
		renderer.set_eq(ps.eq)
	renderer.set_gain(GAIN)
	_attach(true)


# --- The output device ----------------------------------------------------------------------------------------------

## Every DETECT_SECONDS: asks PulseAudio / PipeWire (pactl) what the default output is, on a worker thread.
func _detect_output() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _detecting or now < _detect_at:
		return
	_detect_at = now + DETECT_SECONDS
	if OS.get_name() != "Linux":
		return
	_detecting = true
	WorkerThreadPool.add_task(func() -> void:
		var out: Array = []
		var kind := ""
		if OS.execute("pactl", ["get-default-sink"], out, false) == 0 and not out.is_empty():
			var sink := str(out[0]).strip_edges()
			var list: Array = []
			OS.execute("pactl", ["list", "sinks"], list, false)
			kind = classify_sink(sink, str(list[0]) if not list.is_empty() else "")
		_detected.call_deferred(kind))


func _detected(kind: String) -> void:
	_detecting = false
	if kind == detected:
		return
	var before := profile()
	detected = kind
	if profile() != before:
		print("Spatial audio: output looks like %s; the %s profile" % [kind if kind != "" else "unknown", profile()])
		hrtf = _profile_hrtf()
		_apply_profile()
		changed.emit(active)


## "headphones" for a Bluetooth, USB or headphone-jack output, "speakers" otherwise, "" when pactl gave nothing.
## sink: the default sink's name; listing: `pactl list sinks`.
static func classify_sink(sink: String, listing: String) -> String:
	if sink == "":
		return ""
	var s := sink.to_lower()
	if s.contains("bluez") or s.contains("usb") or s.contains("headset") or s.contains("headphone"):
		return "headphones"
	# The default sink's active port: analog-output-headphones and the like.
	var block := ""
	for part in listing.split("Sink #"):
		if part.contains("Name: " + sink):
			block = part
	for line in block.split("\n"):
		var l := line.strip_edges().to_lower()
		if l.begins_with("active port:"):
			return "headphones" if l.contains("headphone") or l.contains("headset") else "speakers"
	return "speakers"


# --- Sets fetched on request ----------------------------------------------------------------------------------------

## Downloads a set of DOWNLOADS (SOFA), converts it to a pack in user://hrtf and deletes the SOFA file. The caller
## shows its licence first. download_finished(id, error) when done ("" on success).
func download_hrtf(p_id: String) -> String:
	var id := p_id
	var entry := {}
	for s: Dictionary in DOWNLOADS:
		if s.id == id:
			entry = s
	if entry.is_empty():
		return "no such set: %s" % id
	if renderer == null:
		return "this engine has no spatial audio"
	if downloading != "":
		return "already fetching %s" % downloading
	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	downloading = id
	_http = HTTPRequest.new()
	add_child(_http)
	_http.download_file = DOWNLOAD_DIR.path_join(id + ".sofa")
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_downloaded(id, result, code))
	var err := _http.request(str(entry.url))
	if err != OK:
		_http.queue_free()
		downloading = ""
		return "can't start the download (%s)" % error_string(err)
	return ""


func _downloaded(id: String, result: int, code: int) -> void:
	_http.queue_free()
	downloading = ""
	var sofa := DOWNLOAD_DIR.path_join(id + ".sofa")
	var error := ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		error = "the download failed (result %d, HTTP %d)" % [result, code]
	else:
		var r: Object = ClassDB.instantiate("BinauralRenderer")
		if r.load_hrtf(sofa) != OK:
			error = "not a usable HRTF file: %s" % r.get_last_error()
		else:
			var licence := ""
			var name := id
			for s: Dictionary in DOWNLOADS:
				if s.id == id:
					licence = s.licence
					name = s.name
			if r.save_hrtf(DOWNLOAD_DIR.path_join(id + ".fhrtf"), name, licence) != OK:
				error = "can't write the converted set"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sofa))
	download_finished.emit(id, error)
