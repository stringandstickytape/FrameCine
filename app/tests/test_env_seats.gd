extends SceneTree

## The seats system (docs/environments.md, "The seats system"): every model builds, low-poly, in two surfaces, with its
## forms (tipped up, broken); a small room of each model passes the checks (budget, a clear sight line from every
## seat, comfort, licences, names, no people); the seats are listed for seat choice and picking, with boxes for object
## physics where the seats stand; the viewer's own chair folds away and comes back, a pew stays; tip-up seats tipped
## up by share; a broken seat over the auditorium's own; pews in a builder's slots, with their ends at each run's ends
## and the slots not listed twice; the auditorium's seat slot takes the models, its stadium seat unchanged.
## godot --headless --xr-mode off --path app --script res://tests/test_env_seats.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Seats := preload("res://scripts/env/systems/seats.gd")
const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")

## A model's seat: at most this many triangles.
const LOW_POLY := 800

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_models()
	await _rooms()
	await _fold_and_tip()
	await _auditorium()
	await _slots()
	print("test_env_seats: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _models() -> void:
	_check("registered, kind seats", Registry.has("seats") and str(Registry.spec("seats")["kind"]) == "seats")
	_check("every model in the enum", Seats.MODEL_NAMES.all(func(m: String) -> bool:
			return m in Registry.spec("seats")["params"]["model"]["values"]))
	var u := _mat(Color.RED)
	var f := _mat(Color.BLACK)
	for m: String in Seats.MODEL_NAMES:
		for form: String in [""] + Array(Seats.MODELS[m]["forms"]):
			var mesh := Seats.model_mesh(m, u, f, 0.0, form)
			var tris := EnvChecks._triangles(mesh)
			var aabb := mesh.get_aabb()
			if form == "":
				print("  %s: %d triangles" % [m, tris])
			_check("%s %s: builds, %d triangles (at most %d), %d surfaces" % [m, form, tris, LOW_POLY,
					mesh.get_surface_count()], tris > 0 and tris <= LOW_POLY and mesh.get_surface_count() <= 2)
			# A pew's segment stands on its ends (end_piece()), so it starts above the floor.
			var low := 0.5 if bool(Seats.MODELS[m]["segment"]) else 0.12
			_check("%s %s: stands on the floor, about a seat's size (%s)" % [m, form, aabb],
					aabb.position.y > -0.01 and aabb.position.y < low and aabb.size.y > 0.1 and aabb.size.y < 1.3
					and aabb.size.x < 1.1 and aabb.size.z < 1.1)
		for part: String in ["upholstery", "frame"]:
			var lib := str(Seats.default_material(m, part)["library"])
			var lic := str((MaterialLibrary.entry(lib).get("source", {}) as Dictionary).get("licence", ""))
			_check("%s: its %s %s is a CC0 library material (%s)" % [m, part, lib, lic], lic.begins_with("CC0"))
	var stadium := Seats.model_mesh("stadium", u, f)
	var hall := Auditorium.seat_mesh(u, f)
	_check("the stadium seat is the auditorium's own", EnvChecks._triangles(stadium) == EnvChecks._triangles(hall)
			and stadium.get_aabb().is_equal_approx(hall.get_aabb()))
	_check("the stadium seat broken: its back slumped (taller box behind)",
			Seats.model_mesh("stadium", u, f, 0.0, "broken").get_aabb().end.z > hall.get_aabb().end.z + 0.1)
	_check("tipped up: the cushion stands up (shallower)",
			Seats.model_mesh("plush", u, f, 0.0, "up").get_aabb().position.z
			> Seats.model_mesh("plush", u, f).get_aabb().position.z + 0.03)


func _doc(model: String, extra := {}) -> Dictionary:
	var p := {"model": model, "per_row": 5, "rows_front": 1, "rows_back": 1, "row_rise": 0.3, "row_depth": 1.3}
	p.merge(extra, true)
	return {"schema": 4, "name": "Seats test", "screen": {"center": [0.0, 1.8, -7.0], "size": [5.0, 2.8]},
			"systems": [{"system": "light"}, {"system": "seats", "params": p}]}


func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	return room


func _rooms() -> void:
	for m: String in Seats.MODEL_NAMES:
		var doc := _doc(m)
		var r := EnvDoc.validate(doc)
		_check("%s room: schema %s" % [m, r["errors"]], r["ok"])
		var s := EnvChecks.static_checks(doc)
		for k: String in s:
			_check("%s room: %s %s" % [m, k, s[k]], (s[k] as Array).is_empty())
		var room := _build(doc)
		await process_frame
		var stats := EnvChecks.measure(room)
		var over := EnvChecks.budget(stats)
		_check("%s room: within the budget %s %s" % [m, stats, over], over.is_empty())
		if m == "plush":
			print("  plush room, 15 seats: %s" % [stats])
		var seats: Array[Vector3] = room.get_seats()
		_check("%s room: 15 seats listed (%d), the viewer's at the origin" % [m, seats.size()], seats.size() == 15
				and seats.any(func(p: Vector3) -> bool: return p.is_zero_approx()))
		var blocked: Array = await EnvChecks.sight_line(self, room)
		_check("%s room: a clear sight line from every seat %s" % [m, blocked], blocked.is_empty())
		# Seat picking points at a seat's floor point: the model stands there (its boxes hold the point over it).
		var shapes: Array = room.collision_shapes()
		var per := (Seats.MODELS[m]["boxes"] as Array).size()
		_check("%s room: %d boxes for object physics (%d)" % [m, 15 * per, shapes.size()], shapes.size() == 15 * per)
		var all_held := true
		for p: Vector3 in seats:
			var held := false
			for sh: Array in shapes:
				var box: BoxShape3D = sh[0]
				var local: Vector3 = (sh[1] as Transform3D).affine_inverse() * (p + Vector3.UP * 0.12)
				if absf(local.x) <= box.size.x * 0.5 and absf(local.y) <= box.size.y * 0.5 \
						and absf(local.z) <= box.size.z * 0.5:
					held = true
			all_held = all_held and held
		_check("%s room: a seat at every listed point (picking finds it)" % m, all_held)
		room.queue_free()
		await process_frame
	# Places of its own, an aisle, a facing.
	var doc := _doc("club_chair", {"per_row": 0, "places": [{"at": [0.0, 0.0, 0.0]},
			{"at": [1.4, 0.0, 0.3], "turn": -15.0, "model": "bean_bag"}]})
	var room := _build(doc)
	await process_frame
	var sys: Node = room.host.system("seats")
	var drawn: Array = sys.drawn()
	_check("places: a club chair and a bean bag", drawn.size() == 2 and drawn[0]["model"] == "club_chair"
			and drawn[1]["model"] == "bean_bag")
	_check("places: a turn", absf((drawn[1]["xf"] as Transform3D).basis.get_euler().y - deg_to_rad(-15.0)) < 0.01)
	room.queue_free()
	await process_frame
	var e := Seats.own_entries(EnvDoc.with_defaults(Seats.PARAMS, {"per_row": 4, "aisle": 1.2, "model": "pew"}))
	_check("an aisle: the middle gap is the pitch and the aisle (%.2f)" % [(e[2]["xf"] as Transform3D).origin.x
			- (e[1]["xf"] as Transform3D).origin.x], is_equal_approx((e[2]["xf"] as Transform3D).origin.x
			- (e[1]["xf"] as Transform3D).origin.x, Seats.model_width("pew") + 1.2))
	var bad := EnvDoc.validate(_doc("throne"))
	_check("a model it doesn't have", not bad["ok"])
	bad = EnvDoc.validate(_doc("pew", {"broken": [1, 2, 3, 4, 5, 6, 7, 8, 9]}))
	_check("at most 8 broken seats", not bad["ok"])


func _fold_and_tip() -> void:
	var room := _build(_doc("plush"))
	await process_frame
	var sys: Node = room.host.system("seats")
	var i: int = sys.folded()
	var mm: MultiMesh = sys.node_of(i).multimesh if i >= 0 else null
	_check("the viewer's chair folded away", i >= 0 and (sys.drawn()[i]["xf"] as Transform3D).origin.is_zero_approx()
			and _scale(mm, sys.instance_of(i), sys.shown(i)) < 1e-6)
	# The viewer moves to the next seat: the room moves so it comes to them.
	var next: Vector3 = room.get_seats()[0]
	room.position = -next
	await process_frame
	var j: int = sys.folded()
	_check("the next chair folded, the first back (%d)" % j, j != i and j >= 0
			and is_equal_approx(_scale(mm, sys.instance_of(i), sys.shown(i)), 1.0)
			and _scale(sys.node_of(j).multimesh, sys.instance_of(j), sys.shown(j)) < 1e-6)
	room.queue_free()
	await process_frame
	room = _build(_doc("pew"))
	await process_frame
	_check("a pew stays where the viewer sits", room.host.system("seats").folded() == -1)
	_check("own rows of pews: their ends drawn", room.get_node_or_null("SeatEnds") != null)
	room.queue_free()
	await process_frame
	room = _build(_doc("multiplex", {"tipped": 0.5, "per_row": 9, "rows_back": 4}))
	await process_frame
	var forms: Array = room.host.system("seats").drawn().map(func(d: Dictionary) -> String: return d["form"])
	var up := forms.count("up")
	_check("tipped 0.5: about half tipped up (%d of %d), in its own MultiMesh" % [up, forms.size()],
			up > forms.size() * 0.3 and up < forms.size() * 0.7 and room.get_node_or_null("SeatsUp") != null)
	room.queue_free()
	await process_frame


func _auditorium() -> void:
	# The auditorium's own seat slot: a model of the seats system, rows unchanged.
	var doc := {"schema": 4, "name": "Hall", "screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
			"systems": [{"system": "light"}, {"system": "auditorium", "id": "hall", "params": {"seat_model": "plush",
			"seat_pitch": 0.62, "seats_per_row": 21}}]}
	_check("auditorium seat_model plush: schema %s" % [EnvDoc.validate(doc)["errors"]], EnvDoc.validate(doc)["ok"])
	var room := _build(doc)
	await process_frame
	var mmi := room.get_node("Seats") as MultiMeshInstance3D
	var u := _mat(Color.RED)
	var f := _mat(Color.BLACK)
	_check("the hall's seats are plush", EnvChecks._triangles(mmi.multimesh.mesh)
			== EnvChecks._triangles(Seats.model_mesh("plush", u, f, 0.62)))
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("plush hall: a clear sight line %s" % [blocked], blocked.is_empty())
	room.queue_free()
	await process_frame
	# Screen 3's broken seat: a multiplex hall with one seat broken by the seats system.
	doc["systems"][1]["params"] = {"seat_model": "multiplex", "seats_per_row": 21}
	doc["systems"].append({"system": "seats", "params": {"broken": [5]}})
	_check("a broken seat over the hall: schema %s" % [EnvDoc.validate(doc)["errors"]], EnvDoc.validate(doc)["ok"])
	room = _build(doc)
	await process_frame
	var hall: Node = room.host.system("hall")
	var sys: Node = room.host.system("seats")
	mmi = room.get_node("Seats") as MultiMeshInstance3D
	var d: Array = sys.drawn()
	_check("one broken multiplex seat drawn (%s)" % [d.map(func(x: Dictionary) -> String: return x["model"] + x["form"])],
			d.size() == 1 and d[0]["model"] == "multiplex" and d[0]["form"] == "broken")
	_check("where the hall's seat 5 was", (d[0]["xf"] as Transform3D).is_equal_approx(hall.seats()[5]))
	var cov: Array = sys.covered()
	_check("the hall's own seat 5 folded away", cov.size() == 1 and cov[0][0] == mmi and int(cov[0][1]) == 5
			and (not _rendered() or mmi.multimesh.get_instance_transform(5).basis.get_scale().is_zero_approx()))
	var hides: int = sys.hides
	_check("the seats system lists none of its own: the room's seats are the hall's", room.get_seats().size()
			== hall.seats().size())
	# The viewer sits in seat 5 and moves on: the hall gives its seat back, the broken one keeps it away.
	room.position = -hall.seats()[5].origin
	await process_frame
	room.position = -hall.seats()[6].origin
	await process_frame
	await process_frame
	_check("after the viewer sat there, still broken (folded again after the hall: %d)" % (sys.hides - hides),
			sys.hides >= hides + 2 and (not _rendered()
			or mmi.multimesh.get_instance_transform(5).basis.get_scale().is_zero_approx()))
	var stats := EnvChecks.measure(room)
	_check("the hall with its broken seat within budget %s" % [stats], EnvChecks.budget(stats).is_empty())
	room.queue_free()
	await process_frame


## A builder with seat slots (agent F's interface: seat_slots(), seats() the slots), made here as a stand-in.
const FAKE_BUILDER := """extends "res://scripts/env/systems/env_system.gd"
static func spec() -> Dictionary:
	return {"kind": "builder", "params": {}}
func seat_slots() -> Array:
	var out: Array = []
	for row in 2:
		for k in 8:
			var x := (k - 3.5) * 0.55 + (0.9 if k >= 4 else -0.9)
			out.append({"transform": Transform3D(Basis(), Vector3(x, 0.0, row * 1.1)), "row": row, "style": "pew",
					"width": 0.55, "builder": id})
	return out
func seats() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for s: Dictionary in seat_slots():
		out.append(s["transform"])
	return out
"""


func _slots() -> void:
	var room := _build({"schema": 4, "name": "Nave test", "screen": {"center": [0.0, 2.5, -8.0], "size": [5.0, 2.8]},
			"systems": [{"system": "light"}]})
	await process_frame
	var host: Node = room.host
	var script := GDScript.new()
	script.source_code = FAKE_BUILDER
	script.reload()
	var builder: Node = script.new()
	builder.set("host", host)
	builder.set("room", room)
	builder.set("id", "nave")
	builder.name = "nave"
	host.add_child(builder)
	host.systems["nave"] = builder
	host.order.append(builder)
	var seats: Node = (load("res://scripts/env/systems/seats.gd") as GDScript).new()
	seats.set("host", host)
	seats.set("room", room)
	seats.set("id", "seats")
	seats.set("params", EnvDoc.with_defaults(Seats.PARAMS, {}))
	seats.name = "seats"
	host.add_child(seats)
	host.systems["seats"] = seats
	host.order.append(seats)
	seats.setup()
	host.on_room_moved()
	var d: Array = seats.drawn()
	_check("a pew in each of the builder's 16 slots (auto: by style)", d.size() == 16
			and d.all(func(x: Dictionary) -> bool: return x["model"] == "pew"))
	_check("the slots are listed once, by the builder", room.get_seats().size() == 16 and seats.seats().is_empty())
	var ends := room.get_node_or_null("SeatEnds") as MeshInstance3D
	# Two rows, each split by the aisle: four pews, eight ends; a pew end is three boxes of five faces.
	var tris := EnvChecks._triangles(ends.mesh) if ends != null else 0
	_check("the ends at each run's two ends: 4 pews, 8 ends (%d triangles)" % tris, tris == 8 * 3 * 5 * 2)
	_check("their boxes for object physics", host.collision_shapes().size() == 16 * 2)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("pews: a clear sight line %s" % [blocked], blocked.is_empty())
	room.queue_free()
	await process_frame


## Headless, a MultiMesh keeps no instances: the system's own record of what it set.
func _rendered() -> bool:
	return DisplayServer.get_name() != "headless"


func _scale(mm: MultiMesh, inst: int, shadow: Transform3D) -> float:
	return (mm.get_instance_transform(inst) if _rendered() else shadow).basis.get_scale().x


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
