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
	_test_modes()
	_test_hints()
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
	_check("box: one point gives the margin round it", (one["size"] as Vector3).is_equal_approx(
			Vector3.ONE * maxf(RealWindows.MIN_SIDE, RealWindows.MARGIN * 2.0)))
	var far := RealWindows.box_of(PackedVector3Array([Vector3.ZERO, Vector3(9, 0, 0)]), 0.0)
	_check("box: a side at most %.0f m" % RealWindows.MAX_SIDE, (far["size"] as Vector3).x == RealWindows.MAX_SIDE)
	# A line along a 45-degree yaw: in the box's own frame it is long one way and thin the other.
	var d := Vector3(-sin(PI / 4.0), 0, -cos(PI / 4.0))
	var turned := RealWindows.box_of(PackedVector3Array([Vector3.ZERO, d]), PI / 4.0)
	var ts: Vector3 = turned["size"]
	_check("box: turned with the viewer (%s)" % ts, absf(ts.z - (1.0 + RealWindows.MARGIN * 2.0)) < 0.001
			and ts.x < 0.1)
	# Drawn: a keyboard 0.45 wide and 0.15 deep, the viewer facing along +X (yaw -90 degrees): its long side runs
	# across the view (along Z in the room), not towards the viewer.
	var t := RealWindows.box_transform({"center": Vector3.ZERO, "size": Vector3(0.45, 0.03, 0.15)}, -PI / 2.0)
	var across := t.basis * Vector3(0.5, 0, 0)
	var toward := t.basis * Vector3(0, 0, 0.5)
	_check("drawn: the long side across the view, turned 90 degrees (%s, %s)" % [across, toward],
			absf(absf(across.z) - 0.225) < 0.001 and absf(across.x) < 0.001 and absf(absf(toward.x) - 0.075) < 0.001)


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


func _test_modes() -> void:
	var rw: Node = main.features.real_windows
	var ui: Node = main.ui
	# The sweep fits its turn: points along a line at 45 degrees give a box along it, not one across it.
	var line := PackedVector3Array()
	for i in 20:
		var t := i / 19.0
		line.append(Vector3(t * 0.5, 0.8 + 0.3 * (i % 2), -t * 0.5))
	var yaw: float = RealWindows.fit_yaw(line, 0.0)
	var fitted: Vector3 = RealWindows.box_of(line, yaw)["size"]
	_check("sweep: turned to fit a thing at 45 degrees (%.1f deg, %s)" % [rad_to_deg(yaw), fitted],
			absf(absf(rad_to_deg(yaw)) - 45.0) <= 1.5 and minf(fitted.x, fitted.z) < 0.1)
	var square := PackedVector3Array([Vector3(-0.3, 0.7, -0.6), Vector3(0.3, 0.7, -0.6), Vector3(0.3, 0.7, -1.2),
			Vector3(-0.3, 0.7, -1.2)])
	_check("sweep: a square thing in front stays square to the viewer",
			absf(RealWindows.fit_yaw(square, 0.0)) < 0.001)

	# Edit, a face at a time. The viewer looks along -Z (the desktop camera), the area square to them.
	var id := "edittest"
	rw.restore({"id": id, "name": "Area 9", "center": [0.0, 1.0, -1.0], "size": [0.4, 0.2, 0.3], "yaw": 0.0,
			"on": true})
	var before: Dictionary = rw.window_by_id(id).duplicate(true)
	_check("edit: started on the face towards the viewer", ui.start_window_edit(id) and rw.mode == "edit"
			and rw.face_name() == "front" and rw.get_node("FaceMark").visible)
	rw.on_stick(Vector2(0, 1), 0.4)
	var b: Dictionary = rw._box
	_check("edit: stick up moves the front face away (%s, %s)" % [b["size"], b["center"]],
			absf(b["size"].z - 0.2) < 0.001 and absf(b["center"].z - -1.05) < 0.001 and absf(b["size"].x - 0.4) < 0.001)
	var names := [rw.face_name()]
	for k in 6:
		names.append(rw.next_face())
	_check("edit: the trigger goes round the six faces, then Turn (%s)" % [names], names.size() == 7
			and names[6] == "turn" and names.slice(0, 6).has("top") and names.slice(0, 6).has("right")
			and names.slice(0, 6).has("left") and names.slice(0, 6).has("bottom") and names[5] == "back")
	_check("edit: Turn shows no face", not rw.get_node("FaceMark").visible)
	rw.on_stick(Vector2(1, 0), 1.0)
	_check("edit: Turn turns it (%.1f deg)" % rad_to_deg(rw._yaw), absf(rad_to_deg(rw._yaw) + RealWindows.TURN_RATE) < 0.5)
	_check("B puts it back", ui.on_back(null) and rw.window_by_id(id) == before and rw.mode == "")
	ui.start_window_edit(id)
	while rw.face_name() != "top":
		rw.next_face()
	rw.on_stick(Vector2(0, 1), 0.4)
	_check("edit: stick up raises the top face", absf(rw._box["size"].y - 0.3) < 0.001
			and absf(rw._box["center"].y - 1.05) < 0.001)
	while rw.face_name() != "right":
		rw.next_face()
	rw.on_stick(Vector2(1, 0), 0.4)
	_check("edit: stick right moves the right face right", absf(rw._box["size"].x - 0.5) < 0.001
			and absf(rw._box["center"].x - 0.05) < 0.001)
	rw.on_stick(Vector2(-1, 0), 10.0)
	_check("edit: a face stops at the least size", absf(rw._box["size"].x - RealWindows.MIN_SIDE) < 0.001)
	rw.on_stick(Vector2(1, 0), 0.4)
	var kept: Dictionary = rw.finish()
	_check("edit: kept (%s, %s)" % [kept["size"], kept["center"]], kept["id"] == id
			and absf(float(kept["size"][1]) - 0.3) < 0.002 and absf(float(kept["center"][1]) - 1.05) < 0.002)

	rw.set_size(id, Vector3(0.3, 0.2, 0.1))
	_check("set_size", RealWindows._vec(rw.window_by_id(id)["size"]).is_equal_approx(Vector3(0.3, 0.2, 0.1)))
	rw.set_all(false)
	_check("all off", not rw.any_on())
	rw.set_all(true)
	_check("all on", rw.windows.all(func(w: Dictionary) -> bool: return w["on"]))
	# Draw order: after the room's see-through effects (0, 1), before the tablet (from 4), panel and subtitles.
	var box: MeshInstance3D = rw.get_node("Window_%s" % id)
	var tablet_base: int = load("res://ui/tablet.gd").PRIORITY_BASE
	_check("drawn after the room's effects, before the menu (%d)" % box.material_override.render_priority,
			box.material_override.render_priority == RealWindows.PRIORITY and RealWindows.PRIORITY > 1
			and RealWindows.PRIORITY + 1 < tablet_base)


## The steps' instructions: what hint() says at each step, and the card over the controller (ui/hand_hint.gd).
func _test_hints() -> void:
	var rw: Node = main.features.real_windows
	var ui: Node = main.ui
	ui.start_window_mark()
	var says := [rw.hint()]
	rw.sweep(true)
	says.append(rw.hint())
	ui.on_back(null)
	_check("sweep: says hold, then let go (%s)" % [says], says[0].contains("Hold the trigger") and says[1].contains("Let go"))
	var id := str(rw.windows[0]["id"])
	ui.start_window_edit(id)
	var face: String = rw.hint()
	while rw.face_name() != "turn":
		rw.next_face()
	var turn: String = rw.hint()
	ui.on_back(null)
	_check("edit: the face and the turn, with keep and put back (%s | %s)" % [face, turn],
			face.contains("face") and face.contains("Menu: keep") and face.contains("B: put it back")
			and turn.begins_with("Turn") and rw.hint() == "")
	var card: Node3D = ui.hand_hint
	var hand := Node3D.new()
	root.add_child(hand)
	hand.global_position = Vector3(0.2, 0.9, -0.4)
	card.show_over(hand, main.xr_camera, "Some words")
	_check("the card over the controller (%s)" % card.global_position, card.visible
			and card.global_position.y > hand.global_position.y + 0.05 and card.text == "Some words")
	card.hide_hint()
	_check("and gone after", not card.visible)
	hand.queue_free()


func _test_kept() -> void:
	var rw: Node = main.features.real_windows
	var before: Array = rw.windows.duplicate(true)
	var again := RealWindows.new()
	again._load()
	_check("kept across a restart (%d)" % again.windows.size(), again.windows.size() == before.size()
			and RealWindows._vec(again.windows[0]["center"]).is_equal_approx(RealWindows._vec(before[0]["center"]))
			and is_equal_approx(float(again.windows[0]["yaw"]), float(before[0]["yaw"])))
	again.free()
	var tab: Node = main.ui.ui.get("mixed_reality")
	var pui: Node = main.ui.ui
	_check("the Mixed reality tab, before System", tab != null and _has_text(tab, "Sweep an area")
			and _has_text(tab, "Mark areas to see through to the cameras.") and not _has_text(tab, "Touch corners")
			and not _has_text(tab, "Mark again") and pui.tabs.find(tab) == pui.Tab.MIXED_REALITY
			and pui.Tab.MIXED_REALITY + 1 == pui.Tab.SYSTEM and pui.TAB_NAMES[pui.Tab.MIXED_REALITY] == "Mixed reality")
	_check("its icon", load("res://ui/icons.gd").has("mixed-reality")
			and pui.TABLET_TAB_ICONS[pui.Tab.MIXED_REALITY] == "mixed-reality")
	_check("not in the Objects tab any more", not _has_text(pui.get("objects"), "Windows to the real room"))
	tab.sync()
	_check("each area a row with On, Edit and Delete (%d areas)" % rw.windows.size(), rw.windows.size() > 0
			and tab._rows.get_child_count() == rw.windows.size() and _has_text(tab._rows.get_child(0), "Edit")
			and _has_text(tab._rows.get_child(0), "Delete") and _has_text(tab._rows.get_child(0), "On"))
	_check("Passthrough dimming, 70 %% at first", _has_text(tab, "Passthrough dimming")
			and is_equal_approx(RealWindows.LIGHT_MIN, 0.7))
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
