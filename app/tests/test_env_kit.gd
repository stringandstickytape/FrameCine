extends "res://tests/env_builder_harness.gd"

## The kit (scripts/env/systems/kit.gd, kit/pieces.gd; docs/environments.md, "The kit"): every piece placed in test
## rooms passes the room checks (budget, a clear sight line from every seat, licences, names, no people). An
## atmospheric hall (the auditorium open to the sky, slots worked out from its parameters): courtyard façades, niches
## with a lion and an urn, columns in the front corners, an obelisk, a castle gate round the screen, curved bands, a
## swirling carpet over its floor, a plasterboard partition behind the rows, a balcony's front. A shopfront with a tin
## booth. A drive-in: the lot, a car, a screen tower, a neon snack bar. A rooftop with bougainvillea along every
## parapet. A nave with ivy and ferns, and a piece on a slot the nave lacks (reported, not placed). The pieces share
## a few meshes; their boxes are there for object physics; the glow is live. A sitting room with every piece of
## furniture: the video recorder in the tv unit's shelf, its clock flashing 12:00; the standard lamp's shade dims with
## the house lights.
## godot --headless --xr-mode off --path app --script res://tests/test_env_kit.gd

const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const Terrace := preload("res://scripts/env/systems/terrace.gd")
const CINEMA_SCREEN := {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]}


func run_tests() -> void:
	test_name = "test_env_kit"
	# An atmospheric hall.
	var hall := {"ceiling_cover": 0.0, "proscenium": "none", "wall_treatment": "plain"}
	var pieces := [
		{"piece": "facade", "slot": "side_walls", "index": 2, "size": [2.4, 5.5, 0.5]},
		{"piece": "facade", "slot": "side_walls", "index": 3, "size": [2.4, 5.5, 0.5]},
		{"piece": "niche", "slot": "side_walls", "index": 4, "holds": "lion", "at": [0, 1.0, 0]},
		{"piece": "niche", "slot": "side_walls", "index": 5, "holds": "urn", "at": [0, 1.0, 0]},
		{"piece": "curves", "slot": "side_walls", "index": 6, "size": [18.0, 7.0, 0.1], "colour": [0.9, 0.5, 0.65]},
		{"piece": "curves", "slot": "side_walls", "index": 7, "size": [18.0, 7.0, 0.1], "colour": [0.9, 0.5, 0.65]},
		{"piece": "column", "slot": "corners", "index": -1, "size": [0.7, 5.0, 0.7]},
		{"piece": "obelisk", "at": [-8.8, -1.4, 4.8]},
		{"piece": "castle_gate"},
		{"piece": "carpet", "colour": [0.45, 0.1, 0.18]},
		{"piece": "partition", "at": [0.0, 1.05, 5.9], "size": [19.0, 3.0, 0.1]},
		{"piece": "balcony_front", "slot": "rear_wall", "at": [0.0, 3.2, 0.0], "size": [12.0, 1.0, 0.25]},
	]
	var doc := room_doc("Atmospheric test", [{"system": "auditorium", "id": "hall", "params": hall},
			{"system": "kit", "id": "kit", "params": {"pieces": pieces}}], CINEMA_SCREEN)
	var room := await check_room("kit atmospheric", doc)
	var kit: Node = room.host.system("kit")
	check("atmospheric: everything placed (%s)" % [kit.problems()], kit.problems().is_empty())
	check("atmospheric: the pieces in two shared meshes and a glow", room.get_node_or_null("PieceStatic") != null
			and room.get_node_or_null("PieceSoft") != null and room.get_node_or_null("PieceWindows") != null)
	var floor_mi := room.get_node_or_null("Floor") as MeshInstance3D
	var fm: ShaderMaterial = floor_mi.mesh.surface_get_material(0) if floor_mi != null else null
	check("atmospheric: the swirling carpet on the hall's floor", fm != null
			and fm.get_shader_parameter("normal_map") == Procedural.maps("swirl_carpet")["normal"])
	check("atmospheric: the pieces' boxes for object physics (%d)" % kit.collision_shapes().size(),
			kit.collision_shapes().size() >= 10)
	var slots: Dictionary = kit.builder_slots()
	check("atmospheric: the auditorium's slots worked out (%s)" % [slots.keys()], slots.has_all(["side_walls",
			"proscenium", "rear_wall", "corners", "ceiling"]))
	var draws := 0
	for n: String in ["PieceStatic", "PieceSoft"]:
		draws += (room.get_node(n) as MeshInstance3D).mesh.get_surface_count()
	check("atmospheric: draws by material, not by piece (%d for 13 placed)" % draws, draws < 13)
	await done(room)

	# A shopfront with its tin booth.
	doc = room_doc("Booth test", [{"system": "shopfront", "id": "hall"}, {"system": "kit", "id": "kit",
			"params": {"pieces": [{"piece": "booth", "slot": "booth"}]}}], screen_of("shopfront"))
	room = await check_room("kit shopfront booth", doc, "hall")
	kit = room.host.system("kit")
	var booth := room.get_node_or_null("PieceBooth") as MeshInstance3D
	check("booth: placed, its window lit", kit.problems().is_empty() and booth != null)
	kit.set_param("glow", 0.0)
	check("booth: the glow is live", booth != null and is_zero_approx(float(booth.mesh.surface_get_material(0)
			.get_shader_parameter("energy"))))
	await done(room)

	# A drive-in.
	var lot: Dictionary = Terrace.STYLES["lot"].duplicate()
	lot["screen"] = "none"
	doc = room_doc("Drive-in kit test", [{"system": "terrace", "id": "lot", "params": lot},
			{"system": "vehicle", "id": "car"},
			{"system": "kit", "id": "kit", "params": {"builder": "lot", "pieces": [{"piece": "screen_tower"},
					{"piece": "snack_bar", "at": [0.0, -0.5, 16.0], "yaw": 180.0}]}}], screen_of("terrace", lot))
	room = await check_room("kit drive-in", doc, "car")
	kit = room.host.system("kit")
	check("drive-in: a neon sign", room.get_node_or_null("Sign0") != null and kit.problems().is_empty())
	await done(room)

	# A rooftop with bougainvillea along every parapet.
	doc = room_doc("Rooftop kit test", [{"system": "terrace", "id": "roof"}, {"system": "kit", "id": "kit",
			"params": {"pieces": [{"piece": "bougainvillea", "slot": "parapet", "index": -1}]}}], screen_of("terrace"))
	room = await check_room("kit rooftop", doc, "roof")
	kit = room.host.system("kit")
	var soft := room.get_node_or_null("PieceSoft") as MeshInstance3D
	check("rooftop: leaves and bracts (%d triangles)" % (soft.mesh.get_faces().size() / 3 if soft != null else 0),
			soft != null and soft.mesh.get_surface_count() == 2 and kit.problems().is_empty())
	await done(room)

	# A nave with ivy and ferns; a slot it lacks.
	doc = room_doc("Nave kit test", [{"system": "nave", "id": "nave"}, {"system": "kit", "id": "kit",
			"params": {"pieces": [{"piece": "ivy", "slot": "niches", "index": -1},
					{"piece": "ferns", "at": [2.0, 0.0, 3.0]}, {"piece": "ferns", "at": [-2.2, 0.0, 3.4], "scale": 1.3},
					{"piece": "booth", "slot": "booth"}]}}], screen_of("nave"))
	room = await check_room("kit nave", doc, "nave")
	kit = room.host.system("kit")
	check("nave: the missing slot reported (%s)" % [kit.problems()], kit.problems().size() == 1
			and str(kit.problems()[0]).contains("no slot booth"))
	await done(room)

	# A sitting room furnished: every piece of furniture, the computer on the desk telly's stand, the video recorder
	# in the tv unit's shelf.
	var sitting := {"style": "plain", "screen": "telly", "screen_size": [0.54, 0.405], "screen_bottom": 0.72,
			"telly_stand": "tv_unit", "rows_back": 0}
	doc = room_doc("Furniture kit test", [{"system": "domestic", "id": "room", "params": sitting},
			{"system": "kit", "id": "kit", "params": {"pieces": [
				{"piece": "video_recorder", "slot": "telly_shelf"},
				{"piece": "desk", "at": [-2.1, 0.0, 0.0], "yaw": 90.0},
				{"piece": "computer", "at": [-2.2, 0.74, 0.0], "yaw": 90.0},
				{"piece": "sideboard", "at": [2.35, 0.0, 0.2], "yaw": -90.0},
				{"piece": "standard_lamp", "at": [1.6, 0.0, -3.1]},
				{"piece": "rug", "at": [0.0, 0.0, -1.2], "size": [2.0, 0.012, 1.4], "accent": [0.3, 0.1, 0.05]},
				{"piece": "coffee_table", "at": [0.0, 0.0, -1.3]}]}}], screen_of("domestic", sitting))
	room = await check_room("kit furniture", doc, "room")
	kit = room.host.system("kit")
	check("furniture: everything placed (%s)" % [kit.problems()], kit.problems().is_empty())
	check("furniture: one baked mesh, the lamp's shade, the clock", room.get_node_or_null("PieceStatic") != null
			and room.get_node_or_null("PieceLamps") != null and room.get_node_or_null("PieceDisplay") != null)
	# Boxes for every piece but the rug (flat on the floor): a desk 2, a computer 3, the rest 1 or 2.
	check("furniture: boxes for object physics (%d)" % kit.collision_shapes().size(), kit.collision_shapes().size() >= 10)
	var shade := room.get_node("PieceLamps") as MeshInstance3D
	var lamp_m: ShaderMaterial = shade.mesh.surface_get_material(0)
	room.host.system("light").set_param("house_lamps", 0.2)
	check("furniture: the lamp's shade dims with the house lights (%.2f)" % float(lamp_m.get_shader_parameter("energy")),
			float(lamp_m.get_shader_parameter("energy")) < 0.5)
	await clock_flashes("furniture", room)
	await done(room)
