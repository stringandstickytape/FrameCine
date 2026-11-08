extends "res://tests/env_builder_harness.gd"

## The domestic builder (scripts/env/systems/domestic.gd; docs/environments.md, "The builders"): a test room for each
## style passes the checks and the builder's conventions. The plain sitting room (a pull-down screen, a radiator under
## the window); the 1962 screening room (walnut, club chairs, the painting that rises into the ceiling: live, and over
## the screen when down; the fire flickers slowly and holds steady with Flickering lights off); the 1993 bedroom (the
## pillow fort round the viewer's cushion, fairy lights, the telly on a chest; with opening_screen the telly fills the
## fort's opening); the ice room (the ice-block pattern on the walls, a vault, hides, candles, an open doorway); every
## telly (cabinet, portable, flat panel) on every stand (chest, radiogram, desk, tv unit, wall), its picture on its glass;
## the eras' sets: an OLED panel (16:9, thin, on a stand or the wall), a 1960s console on legs (with and without its
## doors), a big rear projection (4:3 and 16:9, about 50 inches, deep, on the floor), each picture on its glass; the
## 1937 mirror-lid set, whose picture is the tube's reflection in its lid and is seen inside the mirror from every seat.
## godot --headless --xr-mode off --path app --script res://tests/test_env_domestic.gd

const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")
const MirrorView := preload("res://scripts/env/mirror_view.gd")


func run_tests() -> void:
	test_name = "test_env_domestic"
	var doc := room_doc("Sitting room test", [{"system": "domestic", "id": "room"}], screen_of("domestic"))
	var room := await check_room("domestic plain", doc, "room")
	check("plain: a window of glass, a radiator, a pull-down screen", room.get_node_or_null("Window") != null
			and room.get_node("Window").is_in_group("env_see_through") and room.get_node_or_null("Radiator") != null
			and room.get_node_or_null("Screen") != null)
	var slots: Dictionary = room.host.system("room").slots()
	check("plain: window and vista slots", slots.has("window") and slots.has("vista"))
	await done(room)

	var walnut := {"style": "walnut_1962"}
	doc = room_doc("Screening room test", [{"system": "domestic", "id": "room", "params": walnut}],
			screen_of("domestic", walnut))
	room = await check_room("domestic walnut_1962", doc, "room")
	var r: Node = room.host.system("room")
	var painting := room.get_node_or_null("Painting") as MeshInstance3D
	check("walnut: the painting, risen", painting != null and painting.position.y > 1.5)
	r.set_param("painting_open", 0.0)
	var sc: Dictionary = r.screen()
	var aabb := painting.global_transform * painting.get_aabb() if painting != null else AABB()
	check("walnut: the painting down covers the screen (%s)" % aabb, aabb.has_point(Vector3(0.0,
			float(sc["center"][1]), aabb.get_center().z)) and aabb.get_center().z > float(sc["center"][2]))
	r.set_param("painting_open", 1.0)
	check("walnut: a fireplace, its fire, brass lamps", room.get_node_or_null("Fireplace") != null
			and room.get_node_or_null("Fire") != null and room.get_node_or_null("Lamps") != null)
	check("walnut: club chairs, two rows of three", r.seat_slots().size() == 6
			and str(r.seat_slots()[0]["style"]) == "club")
	check("walnut: a mantel slot", (r.slots() as Dictionary).has("mantel"))
	room.host.auto = false
	var values: Array[float] = []
	for i in 90:
		room.host.step(1.0 / 30.0)
		values.append(r.flicker_factor())
	var lo: float = values.min()
	var hi: float = values.max()
	check("walnut: the fire flickers (%.3f..%.3f)" % [lo, hi], hi - lo > 0.02 and hi - lo < 0.4)
	var fastest := 0.0
	for i in range(1, values.size()):
		fastest = maxf(fastest, absf(values[i] - values[i - 1]) * 30.0)
	check("walnut: slowly (%.2f a second)" % fastest, fastest < 2.0)
	room.host.set_setting("flicker", false)
	room.host.step(0.5)
	check("walnut: Flickering lights off, steady (%.3f)" % r.flicker_factor(), is_equal_approx(r.flicker_factor(), 1.0))
	await done(room)

	var bedroom := {"style": "bedroom_1993"}
	doc = room_doc("Bedroom test", [{"system": "domestic", "id": "room", "params": bedroom}],
			screen_of("domestic", bedroom))
	room = await check_room("domestic bedroom_1993", doc, "room")
	r = room.host.system("room")
	check("bedroom: the fort, its sheet, fairy lights, the telly, the bed", room.get_node_or_null("Fort") != null
			and room.get_node_or_null("FortSheet") != null and room.get_node_or_null("FairyLights") != null
			and room.get_node_or_null("Telly") != null and room.get_node_or_null("Bed") != null)
	check("bedroom: three cushions in the fort", r.seat_slots().size() == 3
			and str(r.seat_slots()[0]["style"]) == "cushion")
	var small: Dictionary = r.screen()
	await done(room)
	var filled := {"style": "bedroom_1993", "opening_screen": true}
	doc = room_doc("Bedroom filled", [{"system": "domestic", "id": "room", "params": filled}],
			screen_of("domestic", filled))
	room = await check_room("domestic bedroom opening_screen", doc, "room")
	var big: Dictionary = room.host.system("room").screen()
	check("the telly fills the opening: bigger and nearer (%s, %s)" % [small["size"], big["size"]],
			float(big["size"][0]) > float(small["size"][0]) * 1.8 and float(big["center"][2]) > float(small["center"][2])
			and float(big["center"][2]) < Domestic.FORT_FRONT)
	await done(room)

	var ice := {"style": "ice"}
	doc = room_doc("Ice test", [{"system": "domestic", "id": "room", "params": ice}], screen_of("domestic", ice))
	room = await check_room("domestic ice", doc, "room")
	var walls := room.get_node_or_null("Walls") as MeshInstance3D
	var m: ShaderMaterial = walls.mesh.surface_get_material(0) if walls != null else null
	check("ice: the ice-block pattern on the walls", m != null
			and m.get_shader_parameter("normal_map") == Procedural.maps("ice_blocks")["normal"])
	check("ice: candles, an open doorway, hides", room.get_node_or_null("Candles") != null
			and room.get_node_or_null("Doorway") != null and room.get_node_or_null("Cushions") != null)
	check("ice: no window", room.get_node_or_null("Window") == null)
	await done(room)

	await _tellies()
	await _era_sets()

	# Auto: a parameter the document gives wins over the style's.
	var p := Domestic.resolved({"style": "ice", "half_width": 4.0, "rows_front": 0, "walls": {}, "screen": "auto"})
	check("auto: given values kept, the rest the style's", is_equal_approx(float(p["half_width"]), 4.0)
			and int(p["rows_front"]) == 0 and str(p["screen"]) == "wall" and str(p["walls"]["library"]) == "white_marble")


## Every telly (a cabinet, a portable, a flat panel) on every stand (a chest, a radiogram, a desk, a tv unit, the wall):
## each room passes the checks; the builder's screen (screen_for: what the room's screen follows) sits on the set's
## glass; a flat panel is 16:9 and thin, a portable small; the stand is as tall as the space under the set (a flat
## panel's pedestal between them); the slots for what goes on the stand and under the set.
func _tellies() -> void:
	for form: String in ["cabinet", "portable", "flat_panel"]:
		for stand: String in ["chest", "radiogram", "desk", "tv_unit", "wall"]:
			var given := {"style": "plain", "screen": "telly", "telly": form, "telly_stand": stand,
					"screen_bottom": 0.78, "lamps": 0}
			if form == "cabinet":
				given["screen_size"] = [0.5, 0.375]
			var label := "telly %s on a %s" % [form, stand]
			var doc := room_doc(label, [{"system": "domestic", "id": "room", "params": given}],
					screen_of("domestic", given))
			var room := await check_room(label, doc, "room")
			var r: Node = room.host.system("room")
			var sc: Dictionary = r.screen()
			var why := telly_glass(room, sc)
			check("%s: the screen on the set's glass %s" % [label, why], why == "")
			var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
			var t: Dictionary = Domestic._telly(Domestic.resolved(r.params))
			var depth := float((t["body"] as Array)[1].z)
			match form:
				"flat_panel":
					check("%s: 16:9 and thin (%s, %.2f m deep)" % [label, size, depth],
							absf(size.aspect() - 16.0 / 9.0) < 0.001 and depth < 0.1)
				"portable":
					check("%s: small (%s), deep for its size (%.2f)" % [label, size, depth], size.x <= 0.35
							and depth >= 0.24)
				_:
					check("%s: the cabinet's own shape (%s)" % [label, size], absf(size.aspect() - 4.0 / 3.0) < 0.001)
			var slots: Dictionary = r.slots()
			check("%s: telly_stand and telly_shelf slots" % label, slots.has("telly_stand") and slots.has("telly_shelf"))
			var top := float(t["top"])
			var foot := float(t["foot"])
			if stand == "wall":
				var c_z := float(sc["center"][2])
				var wall := float(Domestic.resolved(r.params)["front_z"])
				check("%s: the set's back at the wall (%.3f, the wall %.3f)" % [label, c_z - depth,
						wall], absf(c_z - depth - 0.03 - wall) < 0.001)
			else:
				var sb: Array = t["stand_box"]
				var stand_top := (sb[0] as Vector3).y + (sb[1] as Vector3).y * 0.5 if not sb.is_empty() else -1.0
				check("%s: the stand as tall as the space under the set (%.3f, %.3f)" % [label, stand_top, top],
						absf(stand_top - top) < 0.001 and absf(foot - top - (Domestic.PEDESTAL if form == "flat_panel"
						else 0.0)) < 0.001)
				var on: Transform3D = slots["telly_stand"][0]["transform"]
				check("%s: telly_stand at the stand's top (%.3f)" % [label, on.origin.y], absf(on.origin.y - top) < 0.001)
			var shelf: Transform3D = slots["telly_shelf"][0]["transform"]
			check("%s: telly_shelf no higher than the set's foot (%.3f, %.3f)" % [label, shelf.origin.y, foot],
					shelf.origin.y < foot + 0.001)
			if stand == "tv_unit":
				check("%s: the tv unit's shelf under its top (%.3f, top %.3f)" % [label, shelf.origin.y, top],
						shelf.origin.y > 0.1 and absf(shelf.origin.y - (top - Furniture.TOP_T - Furniture.SHELF_H)) < 0.001)
			await done(room)
	# The stand's width and its move sideways; the picture stays put.
	var moved := {"style": "plain", "screen": "telly", "telly": "portable", "telly_stand": "desk",
			"stand_width": 1.6, "stand_shift": -0.3, "screen_bottom": 0.84}
	var t := Domestic._telly(Domestic.resolved(moved))
	var still := Domestic.screen_for({"style": "plain", "screen": "telly", "telly": "portable", "telly_stand": "desk",
			"screen_bottom": 0.84})
	check("stand_width and stand_shift move the desk, not the picture (%s)" % [t["stand_box"]],
			is_equal_approx((t["stand_box"][1] as Vector3).x, 1.6) and is_equal_approx((t["stand_box"][0] as Vector3).x,
			-0.3) and Domestic.screen_for(moved) == still)
	var shelf: Array = t["shelf"]
	check("a desk with room beside the set: the shelf on its top (%s)" % [shelf], is_equal_approx((shelf[0] as Vector3).y,
			float(t["top"])) and (shelf[0] as Vector3).x < -0.3)


## The eras' sets: an OLED on three stands, a console with and without doors, a rear projection 4:3 and 16:9, and the
## mirror-lid set. A small room like the TV rooms' (the set 1.5 m from the viewer).
func _era_sets() -> void:
	var cases: Array = [
		["oled", {"telly_stand": "tv_unit"}], ["oled", {"telly_stand": "chest"}], ["oled", {"telly_stand": "wall"}],
		["console", {}], ["console", {"telly_doors": true}],
		["rear_projection", {}], ["rear_projection", {"telly_aspect": "wide"}],
		["mirror_lid", {}],
	]
	for cs: Array in cases:
		var form: String = cs[0]
		var given := {"style": "plain", "screen": "telly", "telly": form, "lamps": 0, "half_width": 2.4,
				"front_z": -2.2 if form == "rear_projection" else -1.6, "back_z": 2.8, "rows_back": 0}
		given.merge(cs[1], true)
		var label := "telly %s" % form
		for v: Variant in (cs[1] as Dictionary).values():
			label += " %s" % (str(v) if not v is bool else "doors")
		var doc := room_doc(label, [{"system": "domestic", "id": "room", "params": given}], screen_of("domestic", given))
		var room := await check_room(label, doc, "room")
		var r: Node = room.host.system("room")
		var sc: Dictionary = r.screen()
		var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
		var t: Dictionary = Domestic._telly(Domestic.resolved(r.params))
		var body: Array = t["body"]
		var depth := float((body[1] as Vector3).z)
		var slots: Dictionary = r.slots()
		check("%s: telly_stand and telly_shelf slots" % label, slots.has("telly_stand") and slots.has("telly_shelf"))
		if form != "mirror_lid":
			var why := telly_glass(room, sc)
			check("%s: the screen on the set's glass %s" % [label, why], why == "")
		match form:
			"oled":
				check("%s: 16:9 and very thin (%s, %.3f m deep)" % [label, size, depth],
						absf(size.aspect() - 16.0 / 9.0) < 0.001 and depth <= 0.03 and size.x > 1.1)
				if given["telly_stand"] != "wall":
					check("%s: on a slim pedestal (foot %.3f, the stand's top %.3f)" % [label, t["foot"], t["top"]],
							absf(float(t["foot"]) - float(t["top"]) - Domestic.PEDESTAL) < 0.001)
			"console":
				check("%s: 4:3, on legs (%.2f m under the body)" % [label, t["foot"]],
						absf(size.aspect() - 4.0 / 3.0) < 0.001 and float(t["foot"]) > 0.2 and t.has("legs"))
				check("%s: no stand of its own" % label, (t["stand_box"] as Array).is_empty())
			"rear_projection":
				var wide := str(given.get("telly_aspect", "auto")) == "wide"
				var diag := size.length() / 0.0254
				check("%s: %s, about 50 inches (%.0f)" % [label, "16:9" if wide else "4:3", diag],
						absf(size.aspect() - (16.0 / 9.0 if wide else 4.0 / 3.0)) < 0.002 and diag > 47.0 and diag < 53.0)
				var bottom := (body[0] as Vector3).y - (body[1] as Vector3).y * 0.5
				check("%s: deep and on the floor (%.2f m, its bottom %.3f)" % [label, depth, bottom], depth > 0.5
						and absf(bottom) < 0.001)
			"mirror_lid":
				var why := _on_the_mirror(room, sc, t)
				check("%s: the picture is the tube's reflection, seen in the mirror from every seat %s" % [label, why],
						why == "")
				var lid := room.get_node_or_null("Lid")
				check("%s: the lid in front of the picture for the film layer, see-through for the sight line" % label,
						lid != null and lid.is_in_group("env_in_front") and lid.is_in_group("env_see_through"))
				# A true mirror (scripts/env/mirror_view.gd; tests/test_mirror_view.gd checks it reflects).
				var mirror := room.get_node_or_null("Mirror")
				check("%s: a true mirror in the lid, in its plane, its glass see-through for the sight line" % label,
						mirror != null and mirror.get_script() == MirrorView
						and mirror.glass().is_in_group("env_see_through")
						and absf((mirror.centre - (t["lid"]["hinge"] as Vector3)).dot(
								Vector3(0.0, -sqrt(0.5), sqrt(0.5)))) < 0.0001)
				check("%s: 5:4 by default (%s)" % [label, size], absf(size.aspect() - 1.25) < 0.001)
		if DisplayServer.get_name() != "headless":
			await _picture_of(room, sc, label.replace(" ", "_"))
		await done(room)


## With a renderer: the set from the viewer's eyes, a stand-in picture (a test card's bars) on the room's screen.
## user://env_domestic/<label>.png, to look at.
func _picture_of(room: Node3D, sc: Dictionary, label: String) -> void:
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var s := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var card := Image.create_empty(64, 48, false, Image.FORMAT_RGB8)
	var bars: Array[Color] = [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
			Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	for j in 48:
		for i in 64:
			card.set_pixel(i, j, bars[mini(i * 7 / 64, 6)] if j < 32 else Color(i / 64.0, i / 64.0, i / 64.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(card)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = s
	quad.mesh = qm
	quad.material_override = m
	quad.position = c
	room.add_child(quad)
	var cam := Camera3D.new()
	cam.fov = 50.0
	room.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, EnvChecks.EYE_HEIGHT, 0.0), c)
	cam.current = true
	root.size = Vector2i(640, 400)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://env_domestic")
	img.save_png("user://env_domestic/%s.png" % label)
	cam.queue_free()
	quad.queue_free()


## Whether the mirror-lid set's picture is the tube's face reflected in the lid's mirror, and from every seat's eyes
## each corner of the picture is seen through the mirror (the line to it crosses the lid's plane inside the mirror's
## frame, before the picture). "" when it is.
func _on_the_mirror(room: Node3D, sc: Dictionary, t: Dictionary) -> String:
	var lid: Dictionary = t["lid"]
	var hinge: Vector3 = lid["hinge"]
	var length := float(lid["length"])
	var half := float(lid["width"]) * 0.5
	var along := Vector3(0.0, sqrt(0.5), sqrt(0.5))
	var under := Vector3(0.0, -sqrt(0.5), sqrt(0.5))
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var s := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var tube: Vector3 = (t["tube"] as Array)[0]
	var seen := tube - 2.0 * (tube - hinge).dot(under) * under
	if seen.distance_to(c) > 0.002:
		return "(the tube's face %s in the mirror is at %s, the picture at %s)" % [tube, seen, c]
	var fw := Domestic.LID_FRAME
	var eyes: Array[Vector3] = []
	for st: Transform3D in room.room_seat_transforms():
		eyes.append(st.origin + Vector3.UP * EnvChecks.EYE_HEIGHT)
	if eyes.is_empty():
		eyes.append(Vector3(0.0, EnvChecks.EYE_HEIGHT, 0.0))
	for eye in eyes:
		for sx: float in [-0.98, 0.98]:
			for sy: float in [-0.98, 0.98]:
				var p := c + Vector3(sx * s.x * 0.5, sy * s.y * 0.5, 0.0)
				var d := p - eye
				var k := (hinge - eye).dot(under) / d.dot(under)
				if k <= 0.0 or k >= 1.0:
					return "(from %s the corner %s is not behind the mirror)" % [eye, p]
				var x := eye + d * k
				var l := (x - hinge).dot(along)
				if absf(x.x - hinge.x) > half - fw or l < fw or l > length - fw:
					return "(from %s the corner %s is seen outside the mirror: across %.3f, along %.3f of %.3f)" % [eye,
							p, x.x - hinge.x, l, length]
	return ""
