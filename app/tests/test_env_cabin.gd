extends "res://tests/env_builder_harness.gd"

## The cabin builder (scripts/env/systems/cabin.gd; docs/environments/cabin.md): four test rooms (the default, a
## narrow boat, a coach with rows of seats, a flat roof with windows on the left and wall lamps) pass the checks and
## the builder's conventions; the windows' openings are open (the walls' area and no wall in a window); windows that
## would cross a bulkhead are left out; the glass is see-through; the viewer's own seat is at the origin in either
## block; the default screen is the rules' size; the slots; the door's glow follows a fade.
## godot --headless --xr-mode off --path app --script res://tests/test_env_cabin.gd

const Cabin := preload("res://scripts/env/systems/cabin.gd")

const BOAT := {"width": 1.9, "lean": 6.0, "roof_rise": 0.12, "window_round": 0.3, "window_width": 0.6,
		"window_height": 0.6, "window_count": 4, "bay_pitch": 1.3, "ledge": 0.12}
# Folding seats: with the default plush ones, whose backs stand 1.12 m, the rows behind do not see the bottom of the
# picture the rules give a coach (0.77 m). The rules' picture is for a cabin with one seat or low ones; a room with
# rows of tall seats sets screen_bottom itself (docs/environments/cabin.md, "Rows and the picture").
const COACH := {"width": 2.4, "front_z": -6.0, "back_z": 4.0, "seating": "rows", "rows_front": 4, "rows_back": 3,
		"window_count": 6, "window_from_z": -5.0, "bay_pitch": 1.5, "seat_model": "folding"}
const FLAT := {"roof": "flat", "window_sides": "left", "lamps": "wall"}


## The parameters with the defaults filled in.
func _p(given: Dictionary) -> Dictionary:
	return EnvDoc.with_defaults(Registry.spec("cabin")["params"], given)


func _room(label: String, given: Dictionary) -> Node3D:
	var doc := room_doc("Cabin test", [{"system": "cabin", "params": given}], screen_of("cabin", given))
	return await check_room(label, doc, "cabin")


func run_tests() -> void:
	test_name = "test_env_cabin"
	var room := await _room("cabin", {})
	_openings("cabin", room, {})
	var glass := room.get_node_or_null("Glass")
	check("the glass is see-through (env_see_through)", glass != null and glass.is_in_group("env_see_through"))
	_door_glow(room)
	check("the default cabin: at most 14 draws (%d)" % int(figures[-1][1]["draws"]), int(figures[-1][1]["draws"]) <= 14)
	await done(room)
	room = await _room("narrow boat", BOAT)
	_openings("narrow boat", room, BOAT)
	check("narrow boat: the ledge outside (Hull)", room.get_node_or_null("Hull") != null)
	await done(room)
	room = await _room("coach", COACH)
	await done(room)
	room = await _room("flat roof", FLAT)
	await done(room)
	_windows_kept()
	_own_seat()
	_screen()
	_slots()
	_rulings()


## What the builder does where its rules run out.
func _rulings() -> void:
	# A sill that leaves a window less than MIN_WINDOW of height: no windows at all.
	var n := Cabin.window_boxes_for(_p({"window_sill": 1.8})).size()
	check("a sill 0.05 under the walls' limit: no windows, not slits (%d)" % n, n == 0)
	n = Cabin.window_boxes_for(_p({"window_sill": 1.6})).size()
	check("a sill that leaves 0.25: windows, lower than asked (%d)" % n, n == 6)
	# One 0 in screen_size: 16:9 from the other.
	var sc: Dictionary = Cabin.screen_for(_p({"screen_size": [1.6, 0.0]}))
	check("screen_size [1.6, 0]: the height follows at 16:9 (%.3f)" % float(sc["size"][1]),
			absf(float(sc["size"][0]) - 1.6) < 0.001 and absf(float(sc["size"][1]) - 0.9) < 0.001)
	sc = Cabin.screen_for(_p({"screen_size": [0.0, 0.9]}))
	check("screen_size [0, 0.9]: the width follows (%.3f)" % float(sc["size"][0]),
			absf(float(sc["size"][0]) - 1.6) < 0.001)
	# Rows with no seats in either block are seating none.
	var p := _p({"seating": "rows", "seats_left": 0, "seats_right": 0, "centre_x": 0.3})
	var slots: Array = Cabin.seat_slots_for(p)
	check("rows of no seats: the viewer's own seat alone, the cabin on centre_x (%d, %.2f)" % [slots.size(),
			float(Cabin.screen_for(p)["center"][0])], slots.size() == 1
			and absf(float(Cabin.screen_for(p)["center"][0]) - 0.3) < 0.001)
	# A bay's mark in a bulkhead or beyond it is left out: nothing stands outside the cabin.
	for given: Dictionary in [{}, BOAT, COACH, FLAT]:
		var q := _p(given)
		var ok := true
		for slot: Dictionary in Cabin.slots_for(q)["side_walls"]:
			var z := (slot["transform"] as Transform3D).origin.z
			if z < float(q["front_z"]) + Cabin.MARK_MARGIN - 0.001 or z > float(q["back_z"]) - Cabin.MARK_MARGIN + 0.001:
				ok = false
		check("every side_walls slot is inside the bulkheads (front %.1f, back %.1f)" % [float(q["front_z"]),
				float(q["back_z"])], ok)


## The walls' surface has the windows' openings: its area is the walls' above the dado less the windows', within 1 %,
## and no triangle of it lies in a window's box (shrunk by 0.02).
func _openings(label: String, room: Node3D, given: Dictionary) -> void:
	var p := _p(given)
	var lining := room.get_node_or_null("Lining") as MeshInstance3D
	if lining == null:
		check("%s: a Lining" % label, false)
		return
	var lean := deg_to_rad(float(p["lean"]))
	var wall_h := float(p["wall_height"])
	var sill := float(p["window_sill"])
	var ww := float(p["window_width"])
	var wh := float(p["window_height"])
	if sill + wh > wall_h - 0.05:
		wh = wall_h - 0.05 - sill
	var r := minf(float(p["window_round"]), minf(ww / 2.0, wh / 2.0))
	var boxes: Array = Cabin.window_boxes_for(p)
	var dado := minf(float(p["dado_height"]), sill) if not boxes.is_empty() else float(p["dado_height"])
	var length := float(p["back_z"]) - float(p["front_z"])
	var expected := 2.0 * length * (wall_h / cos(lean) - dado / cos(lean))
	for b: Dictionary in boxes:
		expected -= ww * wh / cos(lean) - (4.0 - PI) * r * r
	# The walls' surface: after the dado's (both rooms have a dado).
	var arrays := lining.mesh.surface_get_arrays(1 if dado > 0.0 else 0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	var inside := 0
	for k in range(0, idx.size(), 3):
		var a := verts[idx[k]]
		var b := verts[idx[k + 1]]
		var c := verts[idx[k + 2]]
		area += (b - a).cross(c - a).length() * 0.5
		var centroid := (a + b + c) / 3.0
		for box: Dictionary in boxes:
			var s := float(box["side"])
			var centre: Vector3 = box["center"]
			var n: Vector3 = box["normal"]
			var up := Vector3(-s * sin(lean), cos(lean), 0.0)
			var d := centroid - centre
			if absf(d.dot(n)) > 0.01:
				continue
			# Inside the opening: the window's box with its round corners (the corners' fills lie inside the square
			# box by design; the narrow boat's r 0.3 fills half of it). The rounded box's signed distance, under
			# -0.02: more than 0.02 inside the opening.
			var half := Vector2(ww / 2.0, wh / cos(lean) / 2.0)
			var e := Vector2(absf(d.z), absf(d.dot(up))) - (half - Vector2(r, r))
			var sdf := Vector2(maxf(e.x, 0.0), maxf(e.y, 0.0)).length() + minf(maxf(e.x, e.y), 0.0) - r
			if sdf < -0.02:
				inside += 1
	check("%s: the walls' area %.4f m2 is the walls' less %d windows' %.4f, within 1 %%" % [label, area, boxes.size(),
			expected], absf(area - expected) <= 0.01 * expected)
	check("%s: no wall triangle inside a window's opening (%d)" % [label, inside], inside == 0 and not boxes.is_empty())


## window_boxes_for: a box each window on each windowed side; a window that would cross a bulkhead is left out.
func _windows_kept() -> void:
	var n := Cabin.window_boxes_for(_p({})).size()
	check("the default: 3 windows a side, both sides (%d)" % n, n == 6)
	n = Cabin.window_boxes_for(_p({"window_sides": "left"})).size()
	check("windows on the left only (%d)" % n, n == 3)
	# From -2.8 the first window spans -3.25..-2.35, over the front bulkhead's 0.15 (-2.85): left out.
	var crossing: Array = Cabin.window_boxes_for(_p({"window_from_z": -2.8}))
	check("a window that would cross the front bulkhead is left out (%d)" % crossing.size(), crossing.size() == 4
			and crossing.all(func(b: Dictionary) -> bool: return (b["center"] as Vector3).z > -2.0))
	n = Cabin.window_boxes_for(_p({"window_from_z": 0.6})).size()
	check("and one that would cross the rear bulkhead (%d)" % n, n == 2)
	n = Cabin.window_boxes_for(_p({"window_sides": "none"})).size()
	check("no windows with window_sides none (%d)" % n, n == 0)


## With seating rows the viewer's own seat is at the origin, in either block, by the aisle or the next; the screen's
## centre is on the derived centre line.
func _own_seat() -> void:
	for side: String in ["left", "right"]:
		for i: int in [0, 1]:
			var p := _p({"seating": "rows", "own_side": side, "own_index": i})
			var slots: Array = Cabin.seat_slots_for(p)
			var own := slots.any(func(s: Dictionary) -> bool: return (s["transform"] as Transform3D).origin.length() < 0.001)
			var o := float(p["aisle"]) / 2.0 + float(p["seat_pitch"]) * (i + 0.5)
			if side == "left":
				o = -o
			var cx := float(Cabin.screen_for(p)["center"][0])
			check("own seat %s %d: at the origin (%d seats), the screen's centre x %.3f is %.3f" % [side, i, slots.size(),
					cx, -o], own and absf(cx + o) < 0.0001)


## The default screen, worked out here from the parameters by the rules.
func _screen() -> void:
	var p := _p({})
	var lean := deg_to_rad(float(p["lean"]))
	var top_half := float(p["width"]) / 2.0 - float(p["wall_height"]) * tan(lean)
	var headroom := float(p["wall_height"]) + float(p["roof_rise"])
	var w := clampf(top_half * 2.0 - 0.5, 0.6, 3.2)
	var h := w * 9.0 / 16.0
	if h > headroom - 0.95:
		h = headroom - 0.95
		w = h * 16.0 / 9.0
	var bottom := clampf(1.3 - h / 2.0, 0.75, headroom - 0.12 - h)
	var sc: Dictionary = Cabin.screen_for(p)
	var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var got_bottom := float(sc["center"][1]) - size.y / 2.0
	check("the default screen %.3f x %.3f, bottom %.3f (the rules: %.3f x %.3f, %.3f)" % [size.x, size.y, got_bottom,
			w, h, bottom], absf(size.x - w) < 0.001 and absf(size.y - h) < 0.001 and absf(got_bottom - bottom) < 0.001
			and absf(float(sc["center"][2]) - (float(p["front_z"]) + 0.03)) < 0.001)


## The slots: side_walls a bay's mark each side (kept windows + 1 of them where all are inside the bulkheads; the
## default's last, at z 2.55, is behind its rear bulkhead at 2.4 and left out), windows and window_sills one a window.
func _slots() -> void:
	var p := _p({})
	var kept := Cabin.window_boxes_for(p).size()
	var slots: Dictionary = Cabin.slots_for(p)
	var walls := (slots.get("side_walls", []) as Array).size()
	check("side_walls, the default: 3 marks a side inside the bulkheads, both sides (%d)" % walls, walls == 6)
	var long := _p({"back_z": 3.0})
	walls = (Cabin.slots_for(long).get("side_walls", []) as Array).size()
	check("side_walls, a cabin long enough for every mark: (kept windows a side + 1) * 2 (%d)" % walls,
			walls == (Cabin.window_boxes_for(long).size() / 2 + 1) * 2)
	check("windows and window_sills: one a window (%d, %d of %d)" % [(slots.get("windows", []) as Array).size(),
			(slots.get("window_sills", []) as Array).size(), kept], (slots.get("windows", []) as Array).size() == kept
			and (slots.get("window_sills", []) as Array).size() == kept)
	for k: String in ["screen", "proscenium", "rear_wall", "floor", "ceiling", "corners"]:
		check("a %s slot" % k, not (slots.get(k, []) as Array).is_empty())
	check("four corners", (slots.get("corners", []) as Array).size() == 4)


## The door's glow is live: a fade to 1 and a step set its material's energy.
func _door_glow(room: Node3D) -> void:
	var glow := room.get_node_or_null("DoorGlow") as MeshInstance3D
	if glow == null:
		check("a DoorGlow", false)
		return
	var m := glow.mesh.surface_get_material(0) as ShaderMaterial
	var before := float(m.get_shader_parameter("energy"))
	room.host.auto = false
	room.host.fade("cabin.door_glow", 1.0, 0.0)
	room.host.step(0.1)
	var after := float(m.get_shader_parameter("energy"))
	var b: Node = room.host.system("cabin")
	var want := 1.0 * float(b._group_level("accent"))
	check("door_glow: a fade changes the glow's energy (%.3f to %.3f, want %.3f)" % [before, after, want],
			not is_equal_approx(before, after) and is_equal_approx(after, want))
	check("door_glow: the parameter followed (%s)" % [room.host.param("cabin.door_glow")],
			is_equal_approx(float(room.host.param("cabin.door_glow")), 1.0))
	room.host.release("cabin.door_glow", 0.0)
	room.host.step(0.1)
	check("door_glow: released, the glow is back (%.3f)" % float(m.get_shader_parameter("energy")),
			is_equal_approx(float(m.get_shader_parameter("energy")), before))
	room.host.auto = true
