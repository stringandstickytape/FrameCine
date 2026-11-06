extends SceneTree

## Windows to the real room (scripts/play/real_windows.gd) in the real main scene, without a headset (`force`): the
## swept box (upright, turned, the margin, the size limits), marking through the UI layer's trigger and B, the window
## kept in tracking space (it stays put when the reference frame moves, as recentring moves it), kept across a reload,
## On and Delete with undo, the blend handling (the viewport's alpha and the backstop on while a window is on, back as
## they were after), the film layer stepping aside while marking, the Objects tab's section.
## godot --headless --xr-mode off --path app --script res://tests/test_real_windows.gd

const RealWindows := preload("res://scripts/play/real_windows.gd")

var _failures := 0
var _checks := 0
var main: Node3D
var _kept := ""


func _init() -> void:
	if FileAccess.file_exists(RealWindows.FILE):
		_kept = FileAccess.get_file_as_string(RealWindows.FILE)
		DirAccess.remove_absolute(RealWindows.FILE)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await process_frame
	_test_box()
	await _test_mark()
	await _test_kept()
	_restore_file()
	print("test_real_windows: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _test_box() -> void:
	var pts := PackedVector3Array([Vector3(0, 0.5, -1), Vector3(0.6, 0.55, -1.4), Vector3(0.3, 0.8, -1.2)])
	var b := RealWindows.box_of(pts, 0.0)
	var size: Vector3 = b["size"]
	_check("box: round the points, the margin added (%s)" % size,
			size.is_equal_approx(Vector3(0.6, 0.3, 0.4) + Vector3.ONE * RealWindows.MARGIN * 2.0))
	_check("box: centred on them (%s)" % b["center"], (b["center"] as Vector3).is_equal_approx(Vector3(0.3, 0.65, -1.2)))
	var one := RealWindows.box_of(PackedVector3Array([Vector3(1, 1, 1)]), 0.0)
	_check("box: one point gives the least size", (one["size"] as Vector3).is_equal_approx(Vector3.ONE * RealWindows.MIN_SIDE))
	var far := RealWindows.box_of(PackedVector3Array([Vector3.ZERO, Vector3(9, 0, 0)]), 0.0)
	_check("box: a side at most %.0f m" % RealWindows.MAX_SIDE, (far["size"] as Vector3).x == RealWindows.MAX_SIDE)
	# A line along a 45-degree yaw: in the box's own frame it is long one way and thin the other.
	var d := Vector3(-sin(PI / 4.0), 0, -cos(PI / 4.0))
	var turned := RealWindows.box_of(PackedVector3Array([Vector3.ZERO, d]), PI / 4.0)
	var ts: Vector3 = turned["size"]
	_check("box: turned with the viewer (%s)" % ts, absf(ts.z - (1.0 + RealWindows.MARGIN * 2.0)) < 0.001
			and ts.x < 0.1)


func _test_mark() -> void:
	var rw: Node = main.features.real_windows
	rw.force = true
	var ui: Node = main.ui
	var vp := main.get_viewport()
	var was_transparent := vp.transparent_bg
	_check("none at first", rw.windows.is_empty() and not rw.any_on())
	_check("Mark an area starts marking", ui.start_window_mark() and ui.is_marking_window())
	await process_frame
	_check("marking: the whole view the cameras' (alpha kept, backstop on)", vp.transparent_bg
			and rw.get_node("Backstop").visible and rw.get_node("MarkView").visible)
	_check("marking: the film layer steps aside", main.features.film_layer.held or main.features.film_layer.kind == "")
	_check("B cancels", ui.on_back(null) and not ui.is_marking_window() and rw.windows.is_empty())
	await process_frame
	_check("cancelled with none: as before", vp.transparent_bg == was_transparent and not rw.get_node("Backstop").visible)

	ui.start_window_mark()
	var hand: Node = ui.pointer_hand
	rw.sweep(true)
	for p: Vector3 in [Vector3(-0.2, 0.45, -0.8), Vector3(0.3, 0.5, -1.1), Vector3(0.1, 0.7, -0.9)]:
		rw.add_point(p)
	_check("sweeping: the box shows", rw.get_node("MarkPreview").visible)
	var w: Dictionary = rw.finish()
	await process_frame
	_check("let go: an area kept (%s)" % [w], not w.is_empty() and rw.windows.size() == 1 and w["name"] == "Area 1")
	_check("not marking after", not rw.marking and not rw.get_node("MarkView").visible)
	_check("a window on: alpha kept and the backstop on", vp.transparent_bg and rw.get_node("Backstop").visible)
	var box: MeshInstance3D = rw.get_node("Window_%s" % w["id"])
	_check("its box drawn with the window shader", box != null and box.material_override is ShaderMaterial)
	var at := box.global_position
	# Recentring moves the reference frame; the window keeps its place in the real room, so in the scene it moves with
	# the frame, as the controllers do.
	var moved := Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.3, 0, 0.2))
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	rw.set_process(true)
	main.xr_origin.global_transform = moved
	await process_frame
	var expect: Vector3 = moved * XRServer.get_reference_frame() * box.position
	_check("fixed to the tracking space (origin x reference frame)", rw.global_transform.is_equal_approx(
			moved * XRServer.get_reference_frame()) and box.global_position.is_equal_approx(expect))
	main.xr_origin.global_transform = Transform3D()
	await process_frame
	_check("back with the origin", box.global_position.is_equal_approx(at))

	rw.set_on(w["id"], false)
	await process_frame
	_check("off: none on, opaque again", not rw.any_on() and vp.transparent_bg == was_transparent
			and not rw.get_node("Backstop").visible and not rw.has_node("Window_%s" % w["id"]))
	rw.set_on(w["id"], true)
	var gone: Dictionary = rw.remove(w["id"])
	_check("delete", rw.windows.is_empty() and gone["id"] == w["id"])
	rw.restore(gone)
	_check("undo puts it back", rw.windows.size() == 1)
	_check("trigger and release through the UI layer", await _ui_sweep(ui, rw, hand))


func _ui_sweep(ui: Node, rw: Node, hand: Node) -> bool:
	if hand == null:
		return true
	ui.start_window_mark()
	ui.on_trigger(hand, true)
	rw.add_point(Vector3(1, 1, -1))
	rw.add_point(Vector3(1.2, 1.1, -1.3))
	ui.on_trigger(hand, false)
	await process_frame
	return rw.windows.size() == 2 and not ui.is_marking_window() and rw.windows[1]["name"] == "Area 2"


func _test_kept() -> void:
	var rw: Node = main.features.real_windows
	var before: Array = rw.windows.duplicate(true)
	var again := RealWindows.new()
	again._load()
	_check("kept across a restart (%d)" % again.windows.size(), again.windows.size() == before.size()
			and RealWindows._vec(again.windows[0]["center"]).is_equal_approx(RealWindows._vec(before[0]["center"]))
			and is_equal_approx(float(again.windows[0]["yaw"]), float(before[0]["yaw"])))
	again.free()
	var tab: Node = main.ui.ui.get("objects")
	_check("the Objects tab's section exists", tab != null and _has_text(tab, "Windows to the real room")
			and _has_text(tab, "Mark an area"))
	for w: Dictionary in rw.windows.duplicate():
		rw.remove(w["id"])
	await process_frame


func _has_text(n: Node, text: String) -> bool:
	if (n is Label and (n as Label).text == text) or (n is Button and (n as Button).text == text):
		return true
	for c in n.get_children():
		if _has_text(c, text):
			return true
	return false


func _restore_file() -> void:
	if _kept != "":
		var f := FileAccess.open(RealWindows.FILE, FileAccess.WRITE)
		f.store_string(_kept)
		f.close()
	elif FileAccess.file_exists(RealWindows.FILE):
		DirAccess.remove_absolute(RealWindows.FILE)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
