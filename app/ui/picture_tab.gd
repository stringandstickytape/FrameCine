extends ScrollContainer

## The Picture tab (docs/ui-design.md): the mode as small layout diagrams (mono, side by side, top / bottom; flat,
## 180°, 360°, fisheye, dual fisheye 360) with Auto and its reason, half and swap, 2D from 3D, 3D depth (with "this
## file only") and edge fade, screen size, distance, height, curvature and zoom, horizon trim for 180 / 360, the picture controls, and frame
## step and the A-B loop (#80). Also: a mode per folder (#83), the fisheye lens profile (#73), the dual fisheye 360
## lens (profile, field of view, seam nudge; scripts/play/dual_fisheye.gd), size in degrees and its
## presets (#55), head follow and lying down (#33, #12), deinterlace (#95), sharpen (#90), HDR tone mapping (#85),
## auto crop of letterbox bars (#42), the projector's grain and gate weave (#92), and a stereo screenshot (#66).
## Talks to the app (scripts/main.gd) and its features hub (docs/features.md) directly.

const VideoMode := preload("res://scripts/video_mode.gd")
const ModeDiagram := preload("res://ui/mode_diagram.gd")
const W := preload("res://ui/pane_widgets.gd")
const HelpTexts := preload("res://ui/help_texts.gd")

const LAYOUT_KINDS := ["mono", "sbs", "tb"]
const LAYOUT_WORDS := ["Mono", "SBS", "TB"]
const PROJECTION_KINDS := ["flat", "180", "360", "fisheye", "dualfisheye"]
const PROJECTION_WORDS := ["Flat", "180°", "360°", "Fisheye", "Dual 360"]
const PICTURE_NAMES := {"brightness": "Brightness", "contrast": "Contrast", "saturation": "Saturation",
		"gamma": "Gamma", "lift": "Dark-scene lift", "sharpen": "Sharpen"}
const LENS_WORDS := ["Equidistant", "Equisolid", "Stereographic", "Polynomial"]
const DEINTERLACE_WORDS := ["Off", "Bob", "Edge", "Auto"]

var app: Node
var box: VBoxContainer
var _mode: VideoMode = VideoMode.new()
var _layout_buttons: Array[ModeDiagram] = []
var _projection_buttons: Array[ModeDiagram] = []
var _auto_label: Label
var _half: Button
var _swap: Button
var _two_d: HFlowContainer
var _fov_row: VBoxContainer
var _depth_row: VBoxContainer
var _depth_file: Button
var _edge: Button
var _stereo_box: VBoxContainer
var _rows := {}
var _horizon_box: VBoxContainer
var _flat_box: VBoxContainer
var _loop_label: Label
var _folder_label: Label
var _clear_folder: Button
var _use_folder: Button
var _lens_box: VBoxContainer
var _lens: HFlowContainer
## Dual fisheye 360: the lens profile, its field of view and the seam nudge.
var _dual_box: VBoxContainer
var _dual_profile: HFlowContainer
var _presets: HFlowContainer
var _preset_ids: Array = []
var _follow: Button
var _lying: Button
var _deinterlace: HFlowContainer
var _hdr_box: VBoxContainer
var _hdr_label: Label
var _tone_map: Button
var _auto_crop: Button
## Picture in picture (#87): shown while a film plays in the corner (Files, "In corner").
var _pip_box: VBoxContainer
var _pip_label: Label
var _pip_corner: HFlowContainer
var _crop_grow: Button
var _slideshow: Button
var _slide_seconds: VBoxContainer
var _crossfade: VBoxContainer


func _init() -> void:
	name = "Picture"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	box = W.vbox()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)


func bind(p_app: Node) -> void:
	app = p_app
	_build()
	# A plain-words line under each control whose name does not say what it does (ui/help_texts.gd).
	HelpTexts.attach(box, "picture")
	app.mode_changed.connect(func(m: VideoMode, auto_text: String) -> void: set_mode(m, auto_text))
	app.screen_changed.connect(func(_w: float, _d: float, _h: float) -> void: _sync_screen())
	var f: Node = app.features
	f.depth.changed.connect(func(_v: float, _ff: bool) -> void: _sync_stereo())
	f.two_d.changed.connect(func(_e: int) -> void: _sync_stereo())
	f.edge_fade.changed.connect(func(_w: float) -> void: _sync_stereo())
	f.zoom.changed.connect(func(_z: float, _p: Vector2) -> void: _sync_screen())
	f.curve.changed.connect(func(_r: float) -> void: _sync_screen())
	f.horizon.changed.connect(func(_p: float, _r: float) -> void: _sync_horizon())
	f.picture.changed.connect(func(_v: Dictionary) -> void: _sync_picture())
	f.folder_modes.changed.connect(_sync_folder)
	f.lens.changed.connect(func(_p: String) -> void: _sync_lens())
	f.dual_fisheye.changed.connect(func(_p: String) -> void: _sync_lens())
	f.angle.changed.connect(func(_a: float) -> void: _sync_screen())
	f.pose.changed.connect(_sync_screen)
	f.deinterlace.changed.connect(func(_m: String) -> void: _sync_picture())
	f.hdr.changed.connect(func(_v: Dictionary) -> void: _sync_hdr())
	f.auto_crop.changed.connect(_sync_crop)
	f.projector.changed.connect(_sync_picture)
	f.pip.changed.connect(func(_s: String, _p: String) -> void: _sync_pip())
	app.file_opened.connect(func(_p: String) -> void:
		_sync_folder.call_deferred()
		_sync_hdr.call_deferred())
	set_mode(app.mode, "")
	sync()


func sync() -> void:
	_sync_stereo()
	_sync_screen()
	_sync_horizon()
	_sync_picture()
	_sync_slideshow()
	_sync_folder()
	_sync_lens()
	_sync_hdr()
	_sync_crop()
	_sync_pip()


func _build() -> void:
	box.add_child(W.section("Mode"))
	# Two rows: the layouts, then the projections (eight diagrams in one row are wider than the panel); each wraps
	# where it is narrower still (a card on the tablet).
	var diagrams := W.flow()
	box.add_child(diagrams)
	var layout_group := ButtonGroup.new()
	for i in LAYOUT_KINDS.size():
		var b := ModeDiagram.new(LAYOUT_KINDS[i], LAYOUT_WORDS[i])
		b.button_group = layout_group
		var l := i
		b.pressed.connect(func() -> void: _edit(func(m: VideoMode) -> void: m.layout = l as VideoMode.Layout))
		diagrams.add_child(b)
		_layout_buttons.append(b)
	var projections := W.flow()
	box.add_child(projections)
	var projection_group := ButtonGroup.new()
	for i in PROJECTION_KINDS.size():
		var b := ModeDiagram.new(PROJECTION_KINDS[i], PROJECTION_WORDS[i])
		b.button_group = projection_group
		var p := i
		b.pressed.connect(func() -> void: _edit(func(m: VideoMode) -> void: m.projection = p as VideoMode.Proj))
		projections.add_child(b)
		_projection_buttons.append(b)
	_auto_label = W.ellipsis(W.label("", &"MutedLabel"))
	box.add_child(W.hbox([W.button("Auto", func() -> void: app.auto_mode()), _auto_label]))
	_half = W.toggle("Half", func(on: bool) -> void: _edit(func(m: VideoMode) -> void: m.half = on))
	_swap = W.toggle("Swap eyes", func(on: bool) -> void: _edit(func(m: VideoMode) -> void: m.swap = on))
	box.add_child(W.hbox([_half, _swap]))
	# A folder's mode (#83): files there without their own mode open in it.
	var folder_modes: Node = app.features.folder_modes
	_clear_folder = W.button("Clear folder rule", func() -> void:
		var rule: Dictionary = folder_modes.rule_for(app.current_path)
		if not rule.is_empty():
			folder_modes.clear_rule(rule["folder"]))
	_use_folder = W.button("Use for this folder", func() -> void: folder_modes.use_current_for_folder())
	box.add_child(W.flow([_use_folder, _clear_folder]))
	_folder_label = W.ellipsis(W.label("", &"MutedLabel"))
	box.add_child(_folder_label)
	_fov_row = W.slider_row("Fisheye field", 120.0, 240.0, 5.0, func(v: float) -> String: return "%d°" % roundi(v),
			func(v: float) -> void: _edit(func(m: VideoMode) -> void: m.fisheye_fov = v))
	box.add_child(_fov_row)
	# The fisheye lens's model (#73), for this file.
	_lens_box = W.vbox()
	box.add_child(_lens_box)
	var lens: Node = app.features.lens
	_lens = W.choices(LENS_WORDS, func(i: int) -> void: lens.set_profile(lens.PROFILES[i], true))
	_lens_box.add_child(W.label("Lens"))
	_lens_box.add_child(_lens)
	# Dual fisheye 360: which camera, its lenses' field of view (both), and the seam nudge (the back lens turned a
	# little sideways, so the two pictures meet). Kept per camera profile, for all its files.
	_dual_box = W.vbox()
	box.add_child(_dual_box)
	var dual: Node = app.features.dual_fisheye
	_dual_profile = W.choices(dual.PROFILE_NAMES, func(i: int) -> void: dual.set_profile(dual.PROFILES[i], true))
	_dual_box.add_child(W.label("Camera"))
	_dual_box.add_child(_dual_profile)
	_rows["dual_fov"] = W.slider_row("Lens field", 170.0, 220.0, 0.5, func(v: float) -> String: return "%.1f°" % v,
			func(v: float) -> void: dual.set_value("fov", v))
	_rows["dual_seam"] = W.slider_row("Seam", -dual.SEAM_RANGE, dual.SEAM_RANGE, 0.1,
			func(v: float) -> String: return "%+.1f°" % v, func(v: float) -> void: dual.set_value("seam", v))
	_dual_box.add_child(_rows["dual_fov"])
	_dual_box.add_child(_rows["dual_seam"])
	_dual_box.add_child(W.flow([W.button("Reset lens", func() -> void: dual.reset())]))

	_stereo_box = W.vbox()
	box.add_child(_stereo_box)
	_stereo_box.add_child(W.section("3D"))
	_two_d = W.choices(["3D", "Left eye", "Right eye"], func(i: int) -> void: app.features.two_d.set_eye(i - 1))
	_stereo_box.add_child(W.hbox([W.label("Show"), _two_d]))
	var depth: Node = app.features.depth
	_depth_row = W.slider_row("Depth", -depth.MAX, depth.MAX, depth.STEP,
			func(v: float) -> String: return "%+.1f %%" % (v * 100.0),
			func(v: float) -> void: depth.set_depth(v, _depth_file.button_pressed))
	_stereo_box.add_child(_depth_row)
	_depth_file = W.toggle("This file only", func(on: bool) -> void:
		if on:
			depth.set_depth(depth.value, true)
		else:
			depth.clear_file())
	var edge_fade: Node = app.features.edge_fade
	_edge = W.toggle("Soft edges", func(on: bool) -> void: edge_fade.set_width(edge_fade.DEFAULT_ON if on else 0.0))
	_stereo_box.add_child(W.hbox([_depth_file, _edge]))

	box.add_child(W.section("Screen"))
	var emit_screen := func(_v: float) -> void:
		app.set_screen(W.slider_of(_rows["width"]).value, W.slider_of(_rows["distance"]).value,
				W.slider_of(_rows["height"]).value)
	_rows["width"] = W.slider_row("Size", 0.5, 30.0, 0.1, _metres, emit_screen)
	_rows["distance"] = W.slider_row("Distance", 0.5, 30.0, 0.1, _metres, emit_screen)
	_rows["height"] = W.slider_row("Height", -3.0, 6.0, 0.05, func(v: float) -> String: return "%+.2f m" % v, emit_screen)
	_flat_box = W.vbox()
	var curve: Node = app.features.curve
	# 0 % flat, 100 %: the screen wraps evenly around you (radius = the distance; scripts/play/curved_screen.gd).
	_rows["curve"] = W.slider_row("Curvature", 0.0, 100.0, 1.0,
			func(v: float) -> String: return "flat" if v < 1.0 else "%d %%" % roundi(v),
			func(v: float) -> void: curve.set_amount(v / 100.0))
	var zoom: Node = app.features.zoom
	_rows["zoom"] = W.slider_row("Zoom", 1.0, zoom.MAX_ZOOM, 0.05, func(v: float) -> String: return "%.2fx" % v,
			func(v: float) -> void: zoom.set_zoom(v))
	# Size in degrees (#55): how wide the screen looks, at the distance it is; presets set both.
	var angle: Node = app.features.angle
	_rows["angle"] = W.slider_row("Size in degrees", angle.MIN_ANGLE, angle.MAX_ANGLE, 1.0,
			func(v: float) -> String: return "%d°" % roundi(v), func(v: float) -> void: angle.set_angle(v))
	var preset_names: Array = []
	for id: String in angle.preset_ids():
		_preset_ids.append(id)
		preset_names.append(str(angle.PRESETS[id]["name"]))
	_presets = W.choices(preset_names, func(i: int) -> void: angle.apply_preset(_preset_ids[i]))
	for key in ["width", "distance", "height"]:
		box.add_child(_rows[key])
	box.add_child(_flat_box)
	_flat_box.add_child(_rows["angle"])
	_flat_box.add_child(_presets)
	# Head follow (#33; off = pinned) and lying down (#12; this session only).
	var pose: Node = app.features.pose
	_follow = W.toggle("Follow my head", func(on: bool) -> void: pose.set_follow(on))
	_lying = W.toggle("Lying down", func(on: bool) -> void: pose.set_lying(on))
	box.add_child(W.hbox([_follow, _lying]))
	_flat_box.add_child(_rows["curve"])
	_flat_box.add_child(_rows["zoom"])
	_flat_box.add_child(W.flow([W.button("Reset zoom", func() -> void: zoom.reset())]))
	# Letterbox bars (#42): turning it on reopens the file at its place; the footer says what it found.
	var auto_crop: Node = app.features.auto_crop
	_auto_crop = W.toggle("Auto crop bars", func(on: bool) -> void: auto_crop.set_enabled(on))
	_crop_grow = W.toggle("Grow the screen to keep its height", func(on: bool) -> void: auto_crop.set_grow(on))
	_flat_box.add_child(W.hbox([_auto_crop]))
	_flat_box.add_child(W.hbox([_crop_grow]))

	_horizon_box = W.vbox()
	box.add_child(_horizon_box)
	_horizon_box.add_child(W.section("Horizon"))
	var horizon: Node = app.features.horizon
	var set_trim := func(_v: float) -> void:
		horizon.set_trim(W.slider_of(_rows["pitch"]).value, W.slider_of(_rows["roll"]).value)
	var degrees := func(v: float) -> String: return "%+.1f°" % v
	_rows["pitch"] = W.slider_row("Pitch", -horizon.MAX, horizon.MAX, 0.5, degrees, set_trim)
	_rows["roll"] = W.slider_row("Roll", -horizon.MAX, horizon.MAX, 0.5, degrees, set_trim)
	_horizon_box.add_child(_rows["pitch"])
	_horizon_box.add_child(_rows["roll"])
	_horizon_box.add_child(W.flow([W.button("Level", func() -> void: horizon.reset())]))

	box.add_child(W.section("Picture"))
	var picture: Node = app.features.picture
	for key: String in picture.RANGES:
		var r: Array = picture.RANGES[key]
		var k := key
		_rows["pc_" + key] = W.slider_row(PICTURE_NAMES.get(key, key.capitalize()), r[0], r[1], r[3],
				func(v: float) -> String: return "%.2f" % v, func(v: float) -> void: picture.set_value(k, v))
		box.add_child(_rows["pc_" + key])
	var deinterlace: Node = app.features.deinterlace
	_deinterlace = W.choices(DEINTERLACE_WORDS, func(i: int) -> void: deinterlace.set_mode(deinterlace.MODES[i]))
	box.add_child(W.hbox([W.label("Deinterlace"), _deinterlace]))
	# The projector's film look (#92); the beam itself is in the Room tab.
	var projector: Node = app.features.projector
	_rows["grain"] = W.slider_row("Film grain", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: projector.set_grain(v))
	_rows["weave"] = W.slider_row("Gate weave", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0),
			func(v: float) -> void: projector.set_weave(v))
	box.add_child(_rows["grain"])
	box.add_child(_rows["weave"])
	box.add_child(W.flow([W.button("Reset picture", func() -> void: picture.reset())]))

	# HDR (#85): only for HDR files. Tone map off clips the highlights instead, for comparison.
	_hdr_box = W.vbox()
	box.add_child(_hdr_box)
	_hdr_box.add_child(W.section("HDR"))
	var hdr: Node = app.features.hdr
	_hdr_label = W.label("", &"MutedLabel")
	_hdr_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hdr_box.add_child(_hdr_label)
	_tone_map = W.toggle("Tone map", func(on: bool) -> void: hdr.set_enabled(on))
	_hdr_box.add_child(W.hbox([_tone_map, W.button("Reset HDR", func() -> void: hdr.reset())]))
	var r: Dictionary = hdr.RANGES
	_rows["hdr_exposure"] = W.slider_row("Exposure", r["exposure"][0], r["exposure"][1], r["exposure"][3],
			func(v: float) -> String: return "%+.1f stops" % v, func(v: float) -> void: hdr.set_value("exposure", v))
	_rows["hdr_knee"] = W.slider_row("Knee", r["knee"][0], r["knee"][1], r["knee"][3],
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: hdr.set_value("knee", v))
	_rows["hdr_target"] = W.slider_row("HDR brightness", r["target_nits"][0], r["target_nits"][1], 1.0,
			func(v: float) -> String: return "%d nits" % roundi(v), func(v: float) -> void: hdr.set_value("target_nits", v))
	_hdr_box.add_child(_rows["hdr_exposure"])
	_hdr_box.add_child(_rows["hdr_target"])
	_hdr_box.add_child(_rows["hdr_knee"])

	# Pictures (#22): with the slideshow on, each picture shows this long and then the next in the folder opens.
	box.add_child(W.section("Slideshow"))
	var slideshow: Node = app.features.slideshow
	_slideshow = W.toggle("Slideshow", func(on: bool) -> void: slideshow.set_enabled(on))
	box.add_child(W.hbox([_slideshow]))
	_slide_seconds = W.slider_row("Each picture", 2.0, 60.0, 1.0, func(v: float) -> String: return "%d s" % roundi(v),
			func(v: float) -> void: slideshow.set_seconds(v))
	box.add_child(_slide_seconds)
	_crossfade = W.slider_row("Crossfade", 0.0, 3.0, 0.25,
			func(v: float) -> String: return "cut" if v <= 0.0 else ("%.2f" % v).rstrip("0").rstrip(".") + " s",
			func(v: float) -> void: slideshow.set_crossfade(v))
	box.add_child(_crossfade)
	slideshow.changed.connect(_sync_slideshow)

	box.add_child(W.section("Frame"))
	var step_loop: Node = app.features.step_loop
	box.add_child(W.flow([W.button("Frame back", func() -> void: step_loop.step(-1)),
			W.button("Frame forward", func() -> void: step_loop.step(1)),
			W.button("Mark A / B", func() -> void: step_loop.mark()),
			W.button("Clear loop", func() -> void: step_loop.clear())]))
	box.add_child(W.flow([W.button("Screenshot", _screenshot)]))

	_pip_box = W.vbox()
	box.add_child(_pip_box)
	_pip_box.add_child(W.section("Corner film"))
	var pip: Node = app.features.pip
	_pip_label = W.ellipsis(W.label("", &"MutedLabel"))
	_pip_box.add_child(_pip_label)
	_pip_box.add_child(W.flow([W.button("Swap", func() -> void: pip.swap()),
			W.button("Close corner", func() -> void: pip.close())]))
	_rows["pip_size"] = W.slider_row("Corner size", 0.15, 0.5, 0.05,
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0), func(v: float) -> void: pip.set_size(v))
	_pip_box.add_child(_rows["pip_size"])
	_pip_corner = W.choices(["Top right", "Top left", "Bottom right", "Bottom left"],
			func(i: int) -> void: pip.set_corner(pip.CORNERS[i]))
	_pip_box.add_child(_pip_corner)
	_loop_label = W.label("", &"MutedLabel")
	box.add_child(_loop_label)
	step_loop.loop_changed.connect(func(_on: bool, _a: float, _b: float) -> void: _loop_label.text = step_loop.text())


static func _metres(v: float) -> String:
	return "%.1f m" % v


func _edit(change: Callable) -> void:
	var m: VideoMode = _mode.copy()
	change.call(m)
	_mode = m
	app.set_video_mode(m)


func set_mode(mode: VideoMode, auto_text: String) -> void:
	_mode = mode.copy()
	var dual := mode.projection == VideoMode.Proj.DUAL_FISHEYE
	for i in _layout_buttons.size():
		_layout_buttons[i].set_chosen(i == int(mode.layout))
		# A dual fisheye frame is one picture for both eyes.
		_layout_buttons[i].disabled = dual and i != int(VideoMode.Layout.MONO)
	for i in _projection_buttons.size():
		_projection_buttons[i].set_chosen(i == int(mode.projection))
	W.set_on(_half, mode.half)
	_half.disabled = mode.layout == VideoMode.Layout.MONO or mode.is_spherical()
	W.set_on(_swap, mode.swap)
	_swap.disabled = mode.layout == VideoMode.Layout.MONO
	W.set_slider(_fov_row, mode.fisheye_fov)
	_fov_row.visible = mode.projection == VideoMode.Proj.FISHEYE
	if auto_text != "" or app.mode_source != "auto":
		_auto_label.text = auto_text
	_stereo_box.visible = mode.layout != VideoMode.Layout.MONO
	_flat_box.visible = not mode.is_spherical()
	_horizon_box.visible = mode.is_spherical()
	_lens_box.visible = mode.projection == VideoMode.Proj.FISHEYE
	_dual_box.visible = dual
	for key in ["width", "distance", "height"]:
		(_rows[key] as Control).visible = not mode.is_spherical()


## The footer's line: the mode and how it was chosen.
func mode_text() -> String:
	var source := str(app.mode_source)
	if source in ["auto", "metadata"] and _auto_label.text != "":
		return _auto_label.text
	var how := {"user": "your choice", "arg": "from the command line", "pattern": "test pattern",
			"window": "window", "file": "remembered for this file", "sidecar": "from the file's sidecar",
			"folder": "the folder's rule"}
	return "%s (%s)" % [_mode.describe(), how.get(source, source)]


func _sync_stereo() -> void:
	var f: Node = app.features
	W.set_slider(_depth_row, f.depth.value)
	W.set_on(_depth_file, f.depth.has_file_value())
	W.set_on(_edge, f.edge_fade.width > 0.0)
	W.set_choice(_two_d, int(f.two_d.eye) + 1)


func _sync_screen() -> void:
	W.set_slider(_rows["width"], app.screen_width)
	W.set_slider(_rows["distance"], app.screen_distance)
	W.set_slider(_rows["height"], app.screen_height_offset)
	W.set_slider(_rows["curve"], float(app.features.curve.amount) * 100.0)
	W.set_slider(_rows["zoom"], app.features.zoom.zoom)
	var angle: Node = app.features.angle
	W.set_slider(_rows["angle"], float(angle.angle()))
	W.set_choice(_presets, _preset_ids.find(str(angle.matching_preset())))
	var pose: Node = app.features.pose
	W.set_on(_follow, bool(pose.follow))
	W.set_on(_lying, bool(pose.lying))


func _sync_horizon() -> void:
	W.set_slider(_rows["pitch"], app.features.horizon.pitch)
	W.set_slider(_rows["roll"], app.features.horizon.roll)


func _sync_slideshow() -> void:
	var slideshow: Node = app.features.slideshow
	W.set_on(_slideshow, bool(slideshow.enabled))
	W.set_slider(_slide_seconds, float(slideshow.seconds))
	W.set_slider(_crossfade, float(slideshow.crossfade))
	_slide_seconds.visible = bool(slideshow.enabled)
	_crossfade.visible = bool(slideshow.enabled)


## The folder rule that applies to the open file, if any.
func _sync_folder() -> void:
	var rule: Dictionary = app.features.folder_modes.rule_for(app.current_path)
	_clear_folder.disabled = rule.is_empty()
	# Test patterns, windows, test lab cards and nothing open have no folder.
	var path := str(app.current_path)
	_use_folder.disabled = path == "" or path.begins_with("stub://") or path.begins_with("window://") 			or path.begins_with("browser://") or path.begins_with("lab://")
	_folder_label.text = "Folder rule: %s for %s" % [VideoMode.from_id(str(rule["mode"])).describe(), rule["folder"]] \
			if not rule.is_empty() else ""
	_folder_label.visible = not rule.is_empty()


func _sync_lens() -> void:
	W.set_choice(_lens, (app.features.lens.PROFILES as Array).find(str(app.features.lens.profile)))
	var dual: Node = app.features.dual_fisheye
	W.set_choice(_dual_profile, (dual.PROFILES as Array).find(str(dual.profile)))
	W.set_slider(_rows["dual_fov"], float(dual.fov()))
	W.set_slider(_rows["dual_seam"], float(dual.seam()))


func _sync_hdr() -> void:
	var hdr: Node = app.features.hdr
	_hdr_box.visible = bool(hdr.is_hdr())
	_hdr_label.text = str(hdr.text())
	W.set_on(_tone_map, bool(hdr.enabled))
	var values: Dictionary = hdr.values
	W.set_slider(_rows["hdr_exposure"], float(values.get("exposure", hdr.RANGES["exposure"][2])))
	W.set_slider(_rows["hdr_knee"], float(values.get("knee", hdr.RANGES["knee"][2])))
	W.set_slider(_rows["hdr_target"], float(values.get("target_nits", hdr.RANGES["target_nits"][2])))
	(_rows["hdr_exposure"] as Control).visible = bool(hdr.enabled)
	(_rows["hdr_target"] as Control).visible = bool(hdr.enabled)
	# On the engine's BT.2390 curve the knee does nothing.
	(_rows["hdr_knee"] as Control).visible = bool(hdr.enabled) and not bool(hdr.uses_engine_curve())


func _sync_pip() -> void:
	var pip: Node = app.features.pip
	var st := str(pip.state)
	_pip_box.visible = st != ""
	_pip_label.text = "%s%s" % [str(pip.path).get_file(), "  (opening...)" if st == "opening" else ""]
	W.set_slider(_rows["pip_size"], float(pip.size))
	W.set_choice(_pip_corner, (pip.CORNERS as Array).find(str(pip.corner)))


func _sync_crop() -> void:
	var auto_crop: Node = app.features.auto_crop
	W.set_on(_auto_crop, bool(auto_crop.enabled))
	W.set_on(_crop_grow, bool(auto_crop.grow))
	_crop_grow.visible = bool(auto_crop.enabled)


## The footer's extra: what auto crop found ("Cropped to 2.39:1"), while it is on; else "".
func crop_text() -> String:
	var auto_crop: Node = app.features.auto_crop
	return str(auto_crop.state().get("text", "")) if bool(auto_crop.enabled) else ""


## The frame on screen as a picture in the video's own layout (#66); the pane or the world says where it went.
func _screenshot() -> void:
	var shot: Node = app.features.screenshot
	var path: String = await shot.capture()
	app.ui.notify("Screenshot saved: %s" % path.get_file() if path != "" else "No screenshot: %s" % shot.last_error)


func _sync_picture() -> void:
	var values: Dictionary = app.features.picture.values
	for key: String in app.features.picture.RANGES:
		W.set_slider(_rows["pc_" + key], float(values.get(key, app.features.picture.RANGES[key][2])))
	W.set_choice(_deinterlace, (app.features.deinterlace.MODES as Array).find(str(app.features.deinterlace.mode)))
	W.set_slider(_rows["grain"], float(app.features.projector.grain))
	W.set_slider(_rows["weave"], float(app.features.projector.weave))
