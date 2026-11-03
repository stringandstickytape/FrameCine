extends SceneTree

## Proves the controller labels on the PC, before they go to the headset. It draws the dumped runtime models with the
## app's own ControllerVisual and print, on the Mobile renderer, into a picture the size of the headset's eye image, with
## the app's MSAA and render scale, so one pixel here is one pixel of what the headset renders. It shows and measures each
## legend from the poses a controller is lifted to when someone reads it, and exits non-zero when one breaks a limit, so it
## can gate a deploy. Further off is reported and never fails the run: people bring the controller close to read it. Never
## commit the output: it shows the runtime's model.
##
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --xr-mode off \
##       --path app --script res://tools/label_proof.gd -- --model-dir=DIR --out=DIR [--eye=1728] [--tan=2.872,2.903]
##       [--states=normal,menu,window,terminal] [--frames=5]
##
## tools/label-proof.sh does that. Writes <out>/<state>/<side>/<pose>_<input>.png (actual size), <out>/sheet_<side>.png
## (per hand, magnified, each with its figures), <out>/normal/<side>/view_<pose>.png (the whole of the print in that pose,
## actual size) and <out>/report.json. The sparkle on the right controller's Y cap is measured in the face poses of the
## normal state: <pose>_mark.png and <pose>_bare_cap.png, which is the cap with the sparkle off.
##
## --tan is the eye image's whole field as tangents, across and down: with --eye it sets the pixels per degree. The
## defaults are the figures measured live on the Frame; `--labels-debug` on the device logs them. The controller is put at
## the centre of the image, where a perspective image has the fewest pixels per degree, so the figures are the worst case
## for where the eye looks. The picture is square and uses the larger figure, the 1 % fewer pixels of the two.
##
## What it cannot prove: the lens and the panel (the compositor resamples this image onto the display, so nothing is
## sharper than this and it may be softer), the runtime's fragment density map if it reaches the app's passes (it can
## only lower the density away from where the eye looks), the panel's real contrast and gamma, and stereo.

const ControllerVisual := preload("res://scripts/xr/controller_visual.gd")
const LabelFont := preload("res://scripts/xr/label_font.gd")
const LabelLayout := preload("res://scripts/xr/label_layout.gd")
const LabelSurface := preload("res://scripts/xr/label_surface.gd")
const Main := preload("res://scripts/main.gd")
const MenuDirection := preload("res://tools/menu_direction.gd")

## The limits. stem: pixels from the top to the foot of a capital, as seen. A capital needs about that many rows to be
## told from its neighbours: below it, letters merge however good the edges are.
const MIN_STEM := 5.0
## The print's longest patch edge over its flat length.
const MAX_STRETCH := 1.12
## Text over plastic, in luminance, on the brightest tenth of the legend's pixels (WCAG's 4.5:1 for small text).
const MIN_CONTRAST := 4.5
## Share of the legend's ink that reaches the eye: the rest is behind a control or over the horizon.
const MIN_VISIBLE := 0.9
## How much the legend's total ink changes over the small wrist motion: more is shimmer.
const MAX_SHIMMER := 0.1
## The alignment limits, on the print as laid, flattened onto the plane it is read on. Degrees between a legend's baseline
## and its reference: on the face, that hand's menu or view button, measured from the button; on a wall, the front.
const MAX_BASELINE := 1.0
## The sparkle on the Y cap: its contrast against its cap is held to MIN_CONTRAST, as the print is. It stands apart from the
## white letters in colour, so no share of theirs applies. And what is left of the letter on the bare cap, against the
## pixels round it.
const MAX_GHOST := 1.05
## Height of the sparkle, as of the letter it replaces (metres), and its reach from its centre across.
const MARK_HEIGHT := 0.00418
## Metres between what should match: a pair's offsets from their buttons, a legend and its mirror on the other hand, and
## a row's legends.
const MAX_MISMATCH := 0.0005

## One size and one offset from the button.
const PAIRS := [["a", "b"]]
## The right hand's input and the left's that mirrors it.
const MIRRORED := [["thumbstick", "thumbstick"], ["menu", "view"], ["trigger", "trigger"], ["bumper", "bumper"], ["squeeze", "squeeze"]]
## One above the other, centred on one point along the wall.
const ROWS := [["bumper", "trigger"]]

const DEFAULT_EYE := 1728
## Measured live on the Frame: across, down.
const DEFAULT_TAN := "2.872,2.903"
const CROP_MARGIN := 10
## The ink is measured closer in than the crop: a wider box takes in a neighbouring legend, which slides past with the
## wrist and reads as shimmer.
const INK_MARGIN := 5
const SHEET_SCALE := 3
const WRIST_DEGREES := 0.6
## From the aim pose to the wrist, which the small motion turns about.
const WRIST := Vector3(0.0, -0.05, 0.1)
const MODEL_LAYER := 1
const PRINT_LAYER := 2
const BACKGROUND := Color(0.1, 0.1, 0.12)

## name -> {distance from the eye, degrees above the face plane, degrees round to the inner side, camera roll, what it
## judges, and "report" when it is only there to report}. The read_ and wall poses are a controller lifted to the face to
## read it. "face" and "wall": the legends it is the view of, all limits. "shimmer": the legends it is an extra test of,
## only the limits a legend must meet however it is held.
const POSES := {
	"read_15": {"at": [0.15, 65.0, 0.0, 0.0], "judge": "face"},
	"read_20": {"at": [0.20, 65.0, 15.0, 0.0], "judge": "face"},
	"read_20_rolled": {"at": [0.20, 60.0, 0.0, 15.0], "judge": "face"},
	"read_25": {"at": [0.25, 55.0, 0.0, 0.0], "judge": "face"},
	"wall_15": {"at": [0.15, 15.0, -75.0, 0.0], "judge": "wall"},
	"wall_20": {"at": [0.20, 15.0, -75.0, 0.0], "judge": "wall"},
	"wall_25": {"at": [0.25, 15.0, -75.0, 0.0], "judge": "wall"},
	"inner_15": {"at": [0.15, 15.0, 75.0, 0.0], "judge": "wall"},
	"inner_25": {"at": [0.25, 15.0, 75.0, 0.0], "judge": "wall"},
	"held_30": {"at": [0.30, 40.0, 0.0, 0.0], "judge": "face", "report": true},
	"held_45": {"at": [0.45, 40.0, 0.0, 0.0], "judge": "face", "report": true},
	"beside_45": {"at": [0.45, 40.0, 25.0, 0.0], "judge": "face", "report": true},
	"rolled_45": {"at": [0.45, 40.0, 0.0, 20.0], "judge": "face", "report": true},
	"wall_45": {"at": [0.45, 15.0, -75.0, 0.0], "judge": "wall", "report": true},
	"grazing_45": {"at": [0.45, 20.0, 0.0, 0.0], "judge": "shimmer", "report": true},
}

var _viewport: SubViewport
var _camera: Camera3D
var _size := Vector2i.ONE * DEFAULT_EYE
var _linear := PackedFloat64Array()
var _failures: Array[String] = []
var _report: Array[Dictionary] = []
var _alignment: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _mark := {}
## side -> the face legends' axes: {"button": its measurement, "u", "v", "centre": the button's, in the model}.
var _axes := {}


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var dir := str(args.get("model-dir", ""))
	var out := str(args.get("out", ""))
	if dir == "" or out == "":
		push_error("--model-dir=DIR and --out=DIR are required")
		quit(2)
		return
	_linear.resize(256)
	for i in 256:
		var c := i / 255.0
		_linear[i] = c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
	var eye := int(args.get("eye", DEFAULT_EYE))
	var tan_size := str(args.get("tan", DEFAULT_TAN)).split_floats(",")
	_size = Vector2i(eye, eye)
	await _set_up(tan_size)
	var per_degree := eye / tan_size[0] * PI / 180.0
	var msaa: int = _viewport.msaa_3d
	print("Proof: eye image %d px, field %.3f x %.3f tangent, %.1f pixels per degree at its centre, MSAA %d, render scale %.2f, %s" % [
			eye, tan_size[0], tan_size[1], per_degree, msaa, _viewport.scaling_3d_scale,
			RenderingServer.get_current_rendering_method()])
	print("Proof: limits: stem at least %.1f px, stretch at most %.2f, contrast at least %.1f:1, visible at least %.0f%%, shimmer at most %.0f%%, baseline within %.1f degrees of the button or the wall's axis, matches within %.1f mm" % [
			MIN_STEM, MAX_STRETCH, MIN_CONTRAST, MIN_VISIBLE * 100.0, MAX_SHIMMER * 100.0, MAX_BASELINE, MAX_MISMATCH * 1000.0])
	var frames := int(args.get("frames", 5))
	var right_aim := _model_in_aim(dir.path_join("right_controller.json"))
	var sheets := {}
	var places := {}
	for side: String in ["right", "left"]:
		var hand := Node3D.new()
		hand.name = side
		_viewport.add_child(hand)
		var visual: Node3D = ControllerVisual.new()
		hand.add_child(visual)
		visual.configure(side)
		var model := _load_model(dir, side)
		# The left dump was written untracked: its pose relative to the hand is the right one's, mirrored.
		var mirror := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
		model.transform = right_aim if side == "right" else Transform3D(mirror * right_aim.basis * mirror,
				right_aim.origin * Vector3(-1, 1, 1))
		hand.add_child(model)
		visual.attach_render_model(model)
		_axes[side] = _measure_button(model, side)
		sheets[side] = []
		if side == "right":
			_prepare_mark(model)
		for state: String in str(args.get("states", "normal,menu,window,terminal")).split(","):
			visual.set_texts(Main.controller_labels(Main.PREVIEW_PROFILE, side, state == "menu", state == "window", state == "terminal"))
			for i in 3:
				await process_frame
			for printed: MeshInstance3D in hand.find_children("Print", "MeshInstance3D", true, false):
				printed.layers = PRINT_LAYER
			var folder := out.path_join(state).path_join(side)
			DirAccess.make_dir_recursive_absolute(folder)
			var placed := {}
			for legend: Dictionary in visual.printed_legends():
				placed[legend["input"]] = _place_of(legend, side)
			(places.get_or_add(state, {}) as Dictionary)[side] = placed
			for pose: String in POSES:
				if state == "normal" or not POSES[pose].get("report", false):
					await _prove_pose(hand, visual, side, state, pose, frames, folder, sheets[side])
					if state == "normal" and side == "right" and POSES[pose]["judge"] == "face":
						await _prove_mark(pose, folder, sheets[side])
		hand.visible = false
	for state: String in places:
		_prove_alignment(state, places[state])
	for side: String in sheets:
		await _write_sheet(sheets[side], out.path_join("sheet_%s.png" % side), side)
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	var buttons := {}
	for side: String in _axes:
		buttons[side] = {"lines_degrees": _axes[side]["button"]["angle"], "edge_degrees": _axes[side]["button"]["edge_angle"],
				"rise_degrees": _axes[side]["button"]["rise"]}
	f.store_string(JSON.stringify({"eye": eye, "tan": tan_size, "pixels_per_degree": per_degree, "msaa": msaa, "failures": _failures,
			"buttons": buttons, "alignment": _alignment, "mark": _marks, "legends": _report}, "  ", false))
	f.close()
	print("Proof: %d measurements, %d failures. Sheets and crops in %s" % [_report.size(), _failures.size(), out])
	for failure in _failures:
		print("FAIL " + failure)
	print("Proof: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)


## The picture, set as the app's XR view is: the project's MSAA and render scale, no foveation of its own.
func _set_up(tan_size: PackedFloat64Array) -> void:
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)) as Viewport.MSAA
	_viewport.scaling_3d_scale = float(ProjectSettings.get_setting("rendering/scaling_3d/scale", 1.0))
	root.add_child.call_deferred(_viewport)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BACKGROUND
	_viewport.add_child(env)
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = rad_to_deg(2.0 * atan(tan_size[1] * 0.5))
	_viewport.add_child(_camera)


## One view of one hand: the frames of the small wrist motion, each drawn with the print, without it, and alone (nothing
## in front of it), and each legend measured over them.
func _prove_pose(hand: Node3D, visual: Node3D, side: String, state: String, pose: String, frames: int, folder: String,
		sheet: Array) -> void:
	var at: Array = POSES[pose]["at"]
	var judge: String = POSES[pose]["judge"]
	var report_only: bool = POSES[pose].get("report", false)
	var reference: Dictionary = _axes[side]
	var sign := -1.0 if side == "left" else 1.0
	var centre: Vector3 = visual.get_face_frame()["centre"]
	var up_angle := deg_to_rad(float(at[1]))
	var round_angle := deg_to_rad(float(at[2]))
	# The aim pose's up is square to the face; round to the controller's inner side, seen from behind.
	var around := Vector3.BACK * cos(round_angle) + Vector3.LEFT * sign * sin(round_angle)
	var eye: Vector3 = centre + (Vector3.UP * sin(up_angle) + around * cos(up_angle)) * float(at[0])
	var look := Basis.looking_at(centre - eye, Vector3.UP)
	_camera.global_transform = Transform3D(look.rotated(look.z, deg_to_rad(float(at[3]))), eye)
	var judged: Array[String] = []
	for legend: Dictionary in visual.printed_legends():
		if _judged(legend, judge):
			judged.append(legend["input"])
	if judged.is_empty():
		return
	var seen := {}
	var whole := Rect2i()
	var last: Image
	for k in frames:
		var phase := TAU * k / maxi(frames, 1)
		var turn := Basis(Vector3.UP, deg_to_rad(WRIST_DEGREES * sin(phase))) * Basis(Vector3.RIGHT,
				deg_to_rad(WRIST_DEGREES * 0.7 * cos(phase)))
		hand.transform = Transform3D(turn, WRIST - turn * WRIST)
		var with_print := await _draw(MODEL_LAYER | PRINT_LAYER)
		var without := await _draw(MODEL_LAYER)
		var alone := await _draw(PRINT_LAYER)
		last = with_print
		for legend: Dictionary in visual.printed_legends():
			var input: String = legend["input"]
			var box := _legend_box(legend)
			if not input in judged or box.size.x <= 0 or box.size.y <= 0:
				continue
			whole = box if whole.size == Vector2i.ZERO else whole.merge(box)
			var ink := _measure_ink(with_print, without, alone, _legend_box(legend, INK_MARGIN))
			if not seen.has(input):
				seen[input] = {"legend": legend, "crop": with_print.get_region(box), "ink": [], "contrast": [], "visible": []}
			seen[input]["ink"].append(ink["ink"])
			seen[input]["contrast"].append(ink["contrast"])
			seen[input]["visible"].append(ink["visible"])
	hand.transform = Transform3D()
	if state == "normal" and whole.size != Vector2i.ZERO:
		last.get_region(whole.grow(30).intersection(Rect2i(Vector2i.ZERO, _size))).save_png(folder.path_join("view_%s.png" % pose))
	for input: String in seen:
		var s: Dictionary = seen[input]
		var legend: Dictionary = s["legend"]
		var text: String = legend["text"]
		var shaped := LabelFont.shape(text)
		var scale := LabelLayout.metres_per_em(legend["line"])
		var stem := _stem_pixels(legend, scale)
		var stretch := LabelSurface.stretch(legend["laid"], shaped["quads"], scale)
		var shimmer := _spread(s["ink"])
		var contrast: float = (s["contrast"] as Array).min()
		var visible: float = (s["visible"] as Array).min()
		var fails := PackedStringArray()
		if judge != "shimmer":
			if stem < MIN_STEM:
				fails.append("stem %.1f px" % stem)
			if visible < MIN_VISIBLE:
				fails.append("visible %.0f%%" % (visible * 100.0))
		if stretch > MAX_STRETCH:
			fails.append("stretch %.2f" % stretch)
		if contrast < MIN_CONTRAST:
			fails.append("contrast %.1f:1" % contrast)
		if shimmer > MAX_SHIMMER:
			fails.append("shimmer %.0f%%" % (shimmer * 100.0))
		var tilt := _seen_tilt(legend)
		var off_button := _seen_off_button(legend, reference)
		var name := "%s %s %s %s \"%s\"" % [state, side, pose, input, text.replace("\n", " | ")]
		var verdict := "ok" if fails.is_empty() else ("report only" if report_only else "FAIL")
		print("%-60s stem %4.1f px, stroke %3.1f px, stretch %.2f, contrast %4.1f:1, visible %3.0f%%, shimmer %2.0f%%, seen tilt %4.1f, seen off the button %4.1f  %s" % [
				name, stem, _stroke_pixels(legend, scale), stretch, contrast, visible * 100.0, shimmer * 100.0, tilt, off_button, verdict])
		if not fails.is_empty() and not report_only:
			_failures.append("%s: %s" % [name, ", ".join(fails)])
		_report.append({"state": state, "side": side, "pose": pose, "report_only": report_only, "input": input, "text": text,
				"line_mm": float(legend["line"]) * 1000.0, "stem_px": stem, "stretch": stretch, "contrast": contrast, "visible": visible,
				"shimmer": shimmer, "seen_tilt": tilt, "seen_off_button": off_button, "fails": fails})
		var crop: Image = s["crop"]
		crop.save_png(folder.path_join("%s_%s.png" % [pose, input]))
		if state == "normal":
			sheet.append({"crop": crop, "title": "%s %s%s" % [pose, input, " (report only)" if report_only else ""],
					"figures": "stem %.1f  c %.1f  vis %.0f%%  shim %.0f%%  tilt %.1f" % [stem, contrast, visible * 100.0, shimmer * 100.0, tilt],
					"ok": fails.is_empty(), "report": report_only})


## Whether a pose has a say on a legend. The grazing view comes from behind: the walls are out of its sight, and a wall
## view sees one wall.
func _judged(legend: Dictionary, judge: String) -> bool:
	var kind: String = ControllerVisual.PLACEMENT.get(legend["input"], ["face"])[0]
	if judge == "shimmer":
		return kind == "face"
	if judge != kind:
		return false
	var frame: Transform3D = (legend["to_global"] as Transform3D) * (legend["laid"]["frame"] as Transform3D)
	return kind == "face" or frame.basis.y.dot(_camera.global_position - frame.origin) > 0.0


## This hand's menu or view button, measured here and not taken from the layout, and the axes it gives the face.
func _measure_button(model: Node3D, side: String) -> Dictionary:
	var button := model.find_child("button_menu" if side == "right" else "button_view", true, false) as MeshInstance3D
	var n := ControllerVisual.FACE_NORMAL_MODEL
	var seen := MenuDirection.measure(button, model.global_transform.affine_inverse() * button.global_transform, n, Vector3.RIGHT)
	print("Proof: %s hand's button: its lines run %.2f degrees from the old baseline direction, its long edge %.2f, rising %.2f off the face plane" % [
			side, seen["angle"], seen["edge_angle"], seen["rise"]])
	var u: Vector3 = seen["lines"]
	var box := button.get_aabb()
	var centre := model.global_transform.affine_inverse() * button.global_transform * box.get_center()
	return {"button": seen, "u": u, "v": n.cross(u).normalized(), "centre": centre}


## Where a legend lies, as printed, in the model's space, flattened onto the plane it is read on (u along its reference, v
## square to it): "baseline", the degrees from the reference; "centre"; "offset", from its control's centre; "dropped", the
## glyphs that had no surface under them.
func _place_of(legend: Dictionary, side: String) -> Dictionary:
	var wall: bool = ControllerVisual.PLACEMENT.get(legend["input"], ["face"])[0] == "wall"
	var u: Vector3 = ControllerVisual.FACE_FORWARD_MODEL if wall else _axes[side]["u"]
	var v: Vector3 = ControllerVisual.FACE_NORMAL_MODEL if wall else _axes[side]["v"]
	var points := PackedVector2Array()
	for p: Vector3 in legend["laid"]["vertices"]:
		points.append(Vector2(p.dot(u), p.dot(v)))
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	var control: Vector3 = legend["control"]
	return {"text": str(legend["text"]).replace("\n", " | "), "line": float(legend["line"]), "baseline": absf(_slope_degrees(points)),
			"centre": box.get_center(), "offset": box.get_center() - Vector2(control.dot(u), control.dot(v)),
			"dropped": (LabelFont.shape(legend["text"])["quads"] as Array).size() - (legend["laid"]["kept"] as Array).size()}


## The angle of the line that best fits the points.
static func _slope_degrees(points: PackedVector2Array) -> float:
	var mean := Vector2.ZERO
	for p in points:
		mean += p
	mean /= points.size()
	var across := 0.0
	var both := 0.0
	for p in points:
		across += (p.x - mean.x) * (p.x - mean.x)
		both += (p.x - mean.x) * (p.y - mean.y)
	return rad_to_deg(atan(both / maxf(across, 1e-12)))


## The print's measurements, which no view changes: each legend's baseline and glyphs, then what should match.
func _prove_alignment(state: String, places: Dictionary) -> void:
	for side: String in places:
		for input: String in places[side]:
			var p: Dictionary = places[side][input]
			var name := "%s %s %s \"%s\"" % [state, side, input, p["text"]]
			var fails := PackedStringArray()
			if p["baseline"] > MAX_BASELINE:
				fails.append("baseline %.2f degrees" % p["baseline"])
			if p["dropped"] > 0:
				fails.append("%d glyphs dropped" % p["dropped"])
			print("%-60s line %.1f mm, baseline %.2f degrees, off its control by %.1f, %.1f mm  %s" % [name, p["line"] * 1000.0, p["baseline"],
					p["offset"].x * 1000.0, p["offset"].y * 1000.0, "ok" if fails.is_empty() else "FAIL"])
			_alignment.append({"state": state, "side": side, "input": input, "text": p["text"], "line_mm": p["line"] * 1000.0,
					"baseline_degrees": p["baseline"], "offset_mm": [p["offset"].x * 1000.0, p["offset"].y * 1000.0]})
			if not fails.is_empty():
				_failures.append("%s: %s" % [name, ", ".join(fails)])
	var right: Dictionary = places.get("right", {})
	var left: Dictionary = places.get("left", {})
	for pair: Array in PAIRS:
		if right.has(pair[0]) and right.has(pair[1]):
			var a: Dictionary = right[pair[0]]
			var b: Dictionary = right[pair[1]]
			_match("%s pair %s %s: offsets" % [state, pair[0], pair[1]], a["offset"], b["offset"])
			_match("%s pair %s %s: sizes" % [state, pair[0], pair[1]], Vector2(a["line"], 0.0), Vector2(b["line"], 0.0))
	for row: Array in ROWS:
		for side: String in places:
			if places[side].has(row[0]) and places[side].has(row[1]):
				var a: Vector2 = places[side][row[0]]["centre"]
				var b: Vector2 = places[side][row[1]]["centre"]
				_match("%s %s row %s %s: centres" % [state, side, row[0], row[1]], Vector2(a.x, 0.0), Vector2(b.x, 0.0))
	for mirrored: Array in MIRRORED:
		if right.has(mirrored[0]) and left.has(mirrored[1]):
			var r: Dictionary = right[mirrored[0]]
			var l: Dictionary = left[mirrored[1]]
			var wall: bool = ControllerVisual.PLACEMENT.get(mirrored[0], ["face"])[0] == "wall"
			var flip := Vector2.ONE if wall else Vector2(-1.0, 1.0)
			# A wall legend's centre moves a little with its length, as the wall curves: like with like.
			if not wall or r["text"] == l["text"]:
				_match("%s mirror %s %s: centres" % [state, mirrored[0], mirrored[1]], r["centre"], (l["centre"] as Vector2) * flip)
			if not wall:
				_match("%s mirror %s %s: offsets" % [state, mirrored[0], mirrored[1]], r["offset"], (l["offset"] as Vector2) * flip)


func _match(name: String, a: Vector2, b: Vector2) -> void:
	var apart := a.distance_to(b)
	print("%-60s %.2f mm apart  %s" % [name, apart * 1000.0, "ok" if apart <= MAX_MISMATCH else "FAIL"])
	_alignment.append({"match": name, "mm_apart": apart * 1000.0})
	if apart > MAX_MISMATCH:
		_failures.append("%s: %.2f mm apart" % [name, apart * 1000.0])


## The Y cap and its neighbour, and where the sparkle's top and foot lie in the model.
func _prepare_mark(model: Node3D) -> void:
	var y := model.find_child("button_y", true, false) as MeshInstance3D
	var to_model := model.global_transform.affine_inverse() * y.global_transform
	var map := MenuDirection.cap_map(y, to_model, ControllerVisual.FACE_NORMAL_MODEL)
	var at := func(uv: Vector2) -> Vector3:
		var d: Vector2 = uv - (map[3] as Vector2)
		return (map[0] as Vector3) * d.x + (map[1] as Vector3) * d.y + (map[2] as Vector3)
	var half: float = MARK_HEIGHT * 500.0 / ControllerVisual.MARK_MM_PER_UV
	var centre: Vector2 = ControllerVisual.MARK_CENTRE_UV
	_mark = {"model": model, "y": y, "x": model.find_child("button_x", true, false), "material": y.get_active_material(0),
			"top": at.call(centre - Vector2(half, 0.0)), "foot": at.call(centre + Vector2(half, 0.0))}


## The sparkle in one pose of the normal state: its height in pixels, against the capitals' limit; its contrast against
## the print's limit, with the X's beside it; how much is in sight, from the cap drawn on its own; and on the bare cap, what is left of the letter.
func _prove_mark(pose: String, folder: String, sheet: Array) -> void:
	var report_only: bool = POSES[pose].get("report", false)
	var mat: ShaderMaterial = _mark["material"]
	var y: MeshInstance3D = _mark["y"]
	var to_world: Transform3D = (_mark["model"] as Node3D).global_transform
	var height := _camera.unproject_position(to_world * (_mark["top"] as Vector3)).distance_to(
			_camera.unproject_position(to_world * (_mark["foot"] as Vector3)))
	var box := _mesh_box(y)
	var marked := await _draw(MODEL_LAYER | PRINT_LAYER)
	# The caps alone: a legend beside one would count as its letter.
	var no_print := await _draw(MODEL_LAYER)
	mat.set_shader_parameter("mark_ink", 0.0)
	var bare := await _draw(MODEL_LAYER | PRINT_LAYER)
	mat.set_shader_parameter("use_mark", false)
	var letter := await _draw(MODEL_LAYER | PRINT_LAYER)
	mat.set_shader_parameter("use_mark", true)
	y.layers = MODEL_LAYER | PRINT_LAYER
	var bare_alone := await _draw(PRINT_LAYER)
	mat.set_shader_parameter("mark_ink", 1.0)
	var marked_alone := await _draw(PRINT_LAYER)
	y.layers = MODEL_LAYER
	var visible := _ink_between(marked, bare, box) / maxf(_ink_between(marked_alone, bare_alone, box), 0.001)
	var contrast := _top_over_middle(no_print, box)
	var beside := _top_over_middle(no_print, _mesh_box(_mark["x"]))
	var ghost := _ghost(letter, bare, box)
	var form := _plastic(no_print)
	print("%-60s median %.4f (%.0f of 255 as shown), tenths %.4f to %.4f, top 1%% of the plastic %.4f, pixels %d" % ["body %s" % pose, form["median"],
			form["shown"], form["low"], form["high"], form["top"], form["pixels"]])
	var fails := PackedStringArray()
	if height < MIN_STEM:
		fails.append("height %.1f px" % height)
	if contrast < MIN_CONTRAST:
		fails.append("contrast %.2f:1" % contrast)
	if visible < MIN_VISIBLE:
		fails.append("visible %.0f%%" % (visible * 100.0))
	if ghost > MAX_GHOST:
		fails.append("letter left %.3f:1" % ghost)
	var verdict := "ok" if fails.is_empty() else ("report only" if report_only else "FAIL")
	print("%-60s height %4.1f px, contrast %.2f:1 (the X %.2f:1), visible %3.0f%%, letter left %.3f:1  %s" % ["mark %s" % pose, height, contrast,
			beside, visible * 100.0, ghost, verdict])
	if not fails.is_empty() and not report_only:
		_failures.append("mark %s: %s" % [pose, ", ".join(fails)])
	_marks.append({"pose": pose, "report_only": report_only, "height_px": height, "contrast": contrast, "x_contrast": beside,
			"visible": visible, "letter_left": ghost, "body": form, "fails": fails})
	var crop := marked.get_region(box)
	crop.save_png(folder.path_join("%s_mark.png" % pose))
	bare.get_region(box).save_png(folder.path_join("%s_bare_cap.png" % pose))
	sheet.append({"crop": crop, "title": "%s Y mark%s" % [pose, " (report only)" if report_only else ""], "figures": "height %.1f  c %.2f (X %.2f)  vis %.0f%%  left %.3f" % [
			height, contrast, beside, visible * 100.0, ghost], "ok": fails.is_empty(), "report": report_only})


## The controller's own pixels, no background: how dark its plastic is, in linear luminance, and how much shape shows on it.
func _plastic(image: Image) -> Dictionary:
	var box := Rect2i(Vector2i.ZERO, _size)
	var all := _luminance(image, box)
	var data := image.get_data()
	var back := BACKGROUND.linear_to_srgb() if false else BACKGROUND
	var r := int(back.r * 255.0 + 0.5)
	var g := int(back.g * 255.0 + 0.5)
	var b := int(back.b * 255.0 + 0.5)
	var own := PackedFloat64Array()
	for i in all.size():
		if absi(data[i * 3] - r) > 1 or absi(data[i * 3 + 1] - g) > 1 or absi(data[i * 3 + 2] - b) > 1:
			own.append(all[i])
	own.sort()
	var at := func(share: float) -> float: return own[int((own.size() - 1) * share)]
	var median: float = at.call(0.5)
	var shown := 12.92 * median if median <= 0.0031308 else 1.055 * pow(median, 1.0 / 2.4) - 0.055
	return {"median": median, "shown": shown * 255.0, "low": at.call(0.1), "high": at.call(0.9), "top": at.call(0.95), "pixels": own.size()}


## The picture's box round a mesh.
func _mesh_box(mi: MeshInstance3D) -> Rect2i:
	var aabb := mi.get_aabb()
	var box := Rect2(_camera.unproject_position(mi.global_transform * aabb.position), Vector2.ZERO)
	for i in 8:
		box = box.expand(_camera.unproject_position(mi.global_transform * aabb.get_endpoint(i)))
	return Rect2i(box).intersection(Rect2i(Vector2i.ZERO, _size))


func _luminance(image: Image, box: Rect2i) -> PackedFloat64Array:
	var data := image.get_region(box).get_data()
	var out := PackedFloat64Array()
	out.resize(data.size() / 3)
	for i in out.size():
		out[i] = 0.2126 * _linear[data[i * 3]] + 0.7152 * _linear[data[i * 3 + 1]] + 0.0722 * _linear[data[i * 3 + 2]]
	return out


func _ink_between(a: Image, b: Image, box: Rect2i) -> float:
	var la := _luminance(a, box)
	var lb := _luminance(b, box)
	var ink := 0.0
	for i in la.size():
		ink += maxf(la[i] - lb[i], 0.0)
	return ink


## A cap's brightest 1 % over its middle, in the same terms as the legends' contrast. Its mark or letter covers about 4 to
## 7 % of the box: a share nearer that falls on the mark's edges and measures its share, not its colour.
func _top_over_middle(image: Image, box: Rect2i) -> float:
	var l := _luminance(image, box)
	l.sort()
	return (l[int(l.size() * 0.99)] + 0.05) / (l[l.size() / 2] + 0.05)


## On the bare cap, the pixels the letter would light: how far they stand out of the pixels round them, in the top 3 %.
## Against their surroundings, as the cap's own shading runs across it: the sum is 1:1 with nothing of the letter left.
func _ghost(letter: Image, bare: Image, box: Rect2i) -> float:
	var with_letter := _luminance(letter, box)
	var without := _luminance(bare, box)
	var w := box.size.x
	var above := PackedFloat64Array()
	var total := 0.0
	for i in without.size():
		if with_letter[i] - without[i] <= 0.01:
			continue
		var sum := 0.0
		var count := 0
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x := i % w + dx
				var at := i + dy * w + dx
				if x >= 0 and x < w and at >= 0 and at < without.size():
					sum += without[at]
					count += 1
		above.append(without[i] - sum / count)
		total += without[i]
	if above.is_empty():
		return 1.0
	above.sort()
	var plastic := total / above.size() + 0.05
	return (plastic + above[int(above.size() * 0.97)]) / plastic


## How far the legend's baseline leans in the picture. It leans there with the view, however square it lies on the
## controller, so it is only reported. A rolled pose adds its roll.
func _seen_tilt(legend: Dictionary) -> float:
	return absf(_slope_degrees(_seen_points(legend)))


## The degrees between a face legend's baseline and its button's lines, as the picture shows them. The legends lie on a
## dome, so they rise and fall differently from the button's cap and part from it off the plan view: reported only.
func _seen_off_button(legend: Dictionary, reference: Dictionary) -> float:
	if ControllerVisual.PLACEMENT.get(legend["input"], ["face"])[0] == "wall":
		return 0.0
	var to_world: Transform3D = legend["to_global"]
	var centre: Vector3 = reference["centre"]
	var along: Vector3 = reference["u"]
	var rise: float = reference["button"]["rise"]
	var lines: Vector3 = along.rotated(ControllerVisual.FACE_NORMAL_MODEL.cross(along).normalized(), deg_to_rad(-rise))
	var a := _camera.unproject_position(to_world * (centre - lines * 0.004))
	var b := _camera.unproject_position(to_world * (centre + lines * 0.004))
	var button := rad_to_deg(atan2(b.y - a.y, b.x - a.x))
	var off := wrapf(_slope_degrees(_seen_points(legend)) - button, -90.0, 90.0)
	return absf(off)


func _seen_points(legend: Dictionary) -> PackedVector2Array:
	var to_world: Transform3D = legend["to_global"]
	var points := PackedVector2Array()
	for p: Vector3 in legend["laid"]["vertices"]:
		points.append(_camera.unproject_position(to_world * p))
	return points


func _draw(mask: int) -> Image:
	_camera.cull_mask = mask
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## The legend's pixels: the box round its vertices as drawn, with a margin, inside the picture.
func _legend_box(legend: Dictionary, margin := CROP_MARGIN) -> Rect2i:
	var to_world: Transform3D = legend["to_global"]
	var vertices: PackedVector3Array = legend["laid"]["vertices"]
	if vertices.is_empty():
		return Rect2i()
	var first := _camera.unproject_position(to_world * vertices[0])
	var box := Rect2(first, Vector2.ZERO)
	for v in vertices:
		if _camera.is_position_behind(to_world * v):
			return Rect2i()
		box = box.expand(_camera.unproject_position(to_world * v))
	return Rect2i(box.grow(margin)).intersection(Rect2i(Vector2i.ZERO, _size))


## Over a legend's box: "ink", how much print reaches the eye, in full pixels; "visible", that over the ink with nothing in
## front of it; "contrast", the brightest tenth of the print over the plastic behind it.
func _measure_ink(with_print: Image, without: Image, alone: Image, box: Rect2i) -> Dictionary:
	var a := with_print.get_region(box).get_data()
	var b := without.get_region(box).get_data()
	var c := alone.get_region(box).get_data()
	var background := _linear[c[0]]
	var ink := 0.0
	var free_ink := 0.0
	var printed := PackedFloat64Array()
	var plastic := PackedFloat64Array()
	for i in range(0, a.size(), 3):
		var la := 0.2126 * _linear[a[i]] + 0.7152 * _linear[a[i + 1]] + 0.0722 * _linear[a[i + 2]]
		var lb := 0.2126 * _linear[b[i]] + 0.7152 * _linear[b[i + 1]] + 0.0722 * _linear[b[i + 2]]
		var lc := 0.2126 * _linear[c[i]] + 0.7152 * _linear[c[i + 1]] + 0.0722 * _linear[c[i + 2]]
		var cover := clampf((la - lb) / maxf(1.0 - lb, 0.01), 0.0, 1.0)
		ink += cover
		free_ink += clampf((lc - background) / (1.0 - background), 0.0, 1.0)
		plastic.append(lb)
		if cover > 0.05:
			printed.append(la)
	if printed.is_empty():
		return {"ink": 0.0, "visible": 0.0, "contrast": 0.0}
	printed.sort()
	plastic.sort()
	var bright := printed[int(printed.size() * 0.9)]
	var behind := plastic[plastic.size() / 2]
	return {"ink": ink, "visible": ink / maxf(free_ink, 0.001), "contrast": (bright + 0.05) / (behind + 0.05)}


## Pixels from the top to the foot of a capital as seen, on the legend's plane: the least along the text, since a legend
## is only as readable as its smallest letter.
func _stem_pixels(legend: Dictionary, scale: float) -> float:
	return _across_text_pixels(legend, LabelFont.CAP_HEIGHT * scale, Vector3(0.0, 0.0, 1.0))


## Pixels across a stroke as seen. The font's strokes are about an eighth of its size.
func _stroke_pixels(legend: Dictionary, scale: float) -> float:
	return _across_text_pixels(legend, 0.125 * scale, Vector3(1.0, 0.0, 0.0))


func _across_text_pixels(legend: Dictionary, length: float, along: Vector3) -> float:
	var to_world: Transform3D = legend["to_global"]
	var frame: Transform3D = to_world * (legend["laid"]["frame"] as Transform3D)
	var width: float = legend["size"].x
	var least := INF
	for x: float in [-0.5, 0.0, 0.5]:
		var middle := Vector3(width * x, 0.0, 0.0)
		var p0 := _camera.unproject_position(frame * (middle - along * length * 0.5))
		var p1 := _camera.unproject_position(frame * (middle + along * length * 0.5))
		least = minf(least, p0.distance_to(p1))
	return least


## How far the values stray from each other, over their mean.
static func _spread(values: Array) -> float:
	var total := 0.0
	for v: float in values:
		total += v
	if total <= 0.0:
		return 0.0
	return ((values.max() as float) - (values.min() as float)) / (total / values.size())


## One sheet per hand: every crop of the normal state, magnified without smoothing, under its figures; red when it failed.
func _write_sheet(cells: Array, path: String, side: String) -> void:
	var sheet := SubViewport.new()
	sheet.disable_3d = true
	sheet.size = Vector2i(1680, 200)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.06, 0.07)
	back.size = Vector2(1680, 8000)
	sheet.add_child(back)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(8, 34)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sheet.add_child(grid)
	var heading := Label.new()
	heading.text = "%s hand, normal state: each pixel of the eye image is %d pixels here. stem, contrast, visible, shimmer, seen tilt. Amber: over a limit, report only" % [side, SHEET_SCALE]
	heading.position = Vector2(8, 6)
	sheet.add_child(heading)
	for cell: Dictionary in cells:
		var box := VBoxContainer.new()
		var title := Label.new()
		title.text = "%s\n%s" % [cell["title"], cell["figures"]]
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75) if cell["ok"] else (Color(0.95, 0.8, 0.45) if cell["report"] else
				Color(1.0, 0.45, 0.4)))
		box.add_child(title)
		var crop: Image = (cell["crop"] as Image).duplicate()
		crop.resize(crop.get_width() * SHEET_SCALE, crop.get_height() * SHEET_SCALE, Image.INTERPOLATE_NEAREST)
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(crop)
		box.add_child(picture)
		grid.add_child(box)
	await process_frame
	await process_frame
	sheet.size = Vector2i(1680, int(grid.size.y) + 44)
	for i in 3:
		await RenderingServer.frame_post_draw
	print("Sheet %s: %s" % [path, error_string(sheet.get_texture().get_image().save_png(path))])
	sheet.queue_free()


## The dumped model's glTF scene; parts the runtime hides (the status light) stay hidden.
func _load_model(dir: String, side: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(dir.path_join("%s_controller.glb" % side), state)
	if err != OK:
		push_error("Can't read the %s model in %s: %s" % [side, dir, error_string(err)])
		quit(2)
	var scene := doc.generate_scene(state) as Node3D
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("%s_controller.json" % side)))
	for e: Dictionary in info.get("nodes", []):
		if not bool(e.get("visible", true)):
			var hidden := scene.find_child(str(e["name"]), true, false) as Node3D
			if hidden != null:
				hidden.visible = false
	var model := Node3D.new()
	model.name = "Model"
	model.add_child(scene)
	return model


static func _model_in_aim(json_path: String) -> Transform3D:
	var d: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(json_path)) as Dictionary)["model_in_aim"]
	var v := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])
	return Transform3D(Basis(v.call(d["x"]), v.call(d["y"]), v.call(d["z"])), v.call(d["origin"]))
