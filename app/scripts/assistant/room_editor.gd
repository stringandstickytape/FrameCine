extends Node

## The assistant's room changes on the headset (docs/assistant.md, "Rooms"). A change is a room document
## (room_schema.gd): validated with the JSON path of every problem, its models and pictures read on a worker thread
## (room_model.gd), checked against the room's limits, built as a new room (assistant_room.gd) and shown at once.
## Every change is kept: saved as a recipe (user://recipes/<name>.room.json, listed in the Room tab) so it survives a
## restart. There is no Keep or Undo: the assistant can always change it back, and Reset room returns the stock room
## the room was built on. One change loads at a time.
##
##   state() -> room_state                     apply(mode, doc, summary) -> {ok, result | error, errors}   (await it)
##   signal changed(summary, name)             a change is on show (and saved)

signal changed(summary: String, name: String)

const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Recipes := preload("res://scripts/dev/recipes.gd")
const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const VREnvironment := preload("res://environments/vr_environment.gd")
const RoomBounds := preload("res://scripts/assistant/room_bounds.gd")
const RoomParticles := preload("res://scripts/assistant/room_particles.gd")
const RoomPerf := preload("res://scripts/assistant/room_perf.gd")
## Stock parts listed in room_state (a glTF room can have hundreds); stock_parts_total says how many there are.
const STOCK_LISTED := 100
const LOAD_TIMEOUT := 60.0
const DEFAULT_NAME := "Assistant room"
## A seat this far inside the walls at least (metres).
const SEAT_MARGIN := 0.2
const FRAME := "Room frame (every position here and in room documents): metres, the floor at y = 0, the room's own " \
		+ "seat at the origin facing -Z (x to the right, y up)."

## Read models by the md5 of their base64 text: a change that keeps a model does not read it again.
var _cache := {}
var _busy := false
## Each change's reply waits about RoomPerf.AFTER_CHANGE s for the measured cost (perf) and the guard's warnings.
## The tests turn it off where they don't look at it.
var perf_after_change := true


func _main() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


func _exit_tree() -> void:
	for k: Variant in _cache.keys():
		free_assets({"models": {"x": _cache[k]}})
	_cache.clear()


# --- The room on show ------------------------------------------------------------------------------------------------

## The ids a new room may start from: the stock rooms, photo and glTF rooms, recipes (not other assistant rooms).
static func bases() -> Array:
	var main_script := load("res://scripts/main.gd") as GDScript
	var stock: Array = main_script.get_script_constant_map()["ENVIRONMENTS"]
	var out: Array = []
	for e: Array in stock + EnvLibrary.environments() + Recipes.environments():
		if not str(e[2]).ends_with(Recipes.ROOM_SUFFIX):
			out.append(e)
	return out


## The document of the room on show: an assistant's room's own, or a stock room with nothing added.
func current_doc() -> Dictionary:
	var m := _main()
	var env: Node = m.env if m != null else null
	if env != null and env.get_script() == AssistantRoom:
		return (env.get("doc") as Dictionary).duplicate(true)
	return {"schema": RoomSchema.VERSION, "base": str(m.env_id) if m != null else "void", "parts": [],
			"recolour": []}


func state() -> Dictionary:
	var m := _main()
	var env: Node = m.env
	var doc := current_doc()
	var stock: Array = []
	var base := _base(env)
	var geom := RoomBounds.geometry(base, to_room(m))
	var colours := {}
	if base != null:
		for n in base.find_children("*", "GeometryInstance3D", true, false):
			colours[str(n.name)] = AssistantRoom._colour_of(n as GeometryInstance3D)
	for s: Dictionary in RoomBounds.describe(geom).slice(0, STOCK_LISTED):
		s["color"] = colours.get(s["name"], "")
		stock.append(s)
	var key := base_key(m)
	var inside := RoomBounds.interior(geom, key, base)
	var base_ids: Array = []
	for e: Array in bases():
		var known: Variant = RoomBounds.cached(e[0])
		base_ids.append({"id": e[0], "name": e[1], "interior": known if known != null
				else "measured once it has been on show"})
	return {
		"frame": FRAME,
		"room": m.env_id, "name": str(env.get("display_name")),
		"made_by_assistant": env.get_script() == AssistantRoom,
		"document": RoomSchema.summary(doc),
		"objects": AssistantRoom.placed_objects(env),
		"base": {"id": key, "interior": inside},
		"stock_parts": stock,
		"stock_parts_total": geom.size(),
		"light": {"ambient": float(env.get("ambient_level")), "screen_glow": float(env.get("screen_glow")),
				"viewer_light_scale": m.room_light},
		"screen": screen_state(m),
		"viewer": viewer_state(m),
		"seats": seats_state(m),
		"lighting": {"lit": RoomSchema.is_lit(doc), "key": (doc.get("light", {}) as Dictionary).get("key")
				if doc.get("light") is Dictionary else null,
				"lights": (doc.get("lights", []) as Array).size() if doc.get("lights") is Array else 0,
				"options": {"key": RoomSchema.LIGHT_OPTIONS["key"], "sky": RoomSchema.LIGHT_OPTIONS["sky"],
					"screen": RoomSchema.LIGHT_OPTIONS["screen"], "lights": RoomSchema.POINT_LIGHT_OPTIONS},
				"display": "no tone mapping (the film's colours stay exact): keep a lit surface under 1.0; the "
						+ "guide's Lighting recipe stays there"},
		"bases": base_ids,
		"limits": RoomSchema.LIMITS,
		"used": _used_now(env, doc),
		"costs": RoomSchema.COSTS,
		"supported_widgets": RoomSchema.supported_widgets(),
		"effects": RoomSchema.supported_effects(),
		"photosensitivity": {"max_hz": RoomSchema.MAX_HZ, "max_swing": RoomSchema.MAX_SWING, "rule": "no brightness "
				+ "change faster than max_hz, no swing larger than max_swing of the surface's own brightness"},
		"part_types": RoomSchema.PART_TYPES,
		"schema": RoomSchema.VERSION,
	}


## The room's seats and the one in use: {list: [{name, position, facing}], in_use: name or null (the room's own
## spot), default: name or null, screen_home: the room's own screen {center, size, facing, curve} or null (the base's
## anchor)}. The viewer chooses; an assistant can only suggest (suggest_seat).
static func seats_state(m: Node) -> Dictionary:
	var env: Node = m.env
	var seat: Node = m.features.seat if m.get("features") != null else null
	var list: Array = []
	var names: Array = seat.names() if seat != null else []
	var points: Array = seat.seats() if seat != null else []
	var yaws: Array = env.get_seat_yaws() if env != null and env.has_method("get_seat_yaws") else []
	for i in points.size():
		var e := {"name": names[i] if i < names.size() else "Seat %d" % (i + 1), "position": _v(points[i])}
		if i < yaws.size() and not is_nan(float(yaws[i])):
			e["facing"] = _v(Basis(Vector3.UP, float(yaws[i])) * Vector3.FORWARD)
		list.append(e)
	var at: int = int(seat.seat) if seat != null else -1
	var dflt: int = env.get_default_seat() if env != null and env.has_method("get_default_seat") else -1
	var home: Variant = null
	if env != null and env.get_script() == AssistantRoom and (env.get("doc") as Dictionary).get("screen") is Dictionary:
		home = (env.get("doc") as Dictionary)["screen"]
	var out := {"list": list, "in_use": list[at]["name"] if at >= 0 and at < list.size() else null,
			"moved": bool(seat.moved) if seat != null else false,
			"default": list[dflt]["name"] if dflt >= 0 and dflt < list.size() else null, "screen_home": home}
	if out["moved"] and out["in_use"] == null:
		out["was"] = seat.moved_name
	return out


## The base's interior (RoomBounds.interior) in its own frame: cached, else measured on the base for a moment in the
## tree (hidden; rooms built from primitives build themselves when they enter it). key: as base_key() will give.
func interior_of(base: Node3D, key: String) -> Dictionary:
	var known: Variant = RoomBounds.cached(key)
	if known is Dictionary:
		return known
	var holder := Node3D.new()
	holder.visible = false
	get_tree().root.add_child(holder)
	holder.add_child(base)
	var inside := RoomBounds.interior(RoomBounds.geometry(base, holder.global_transform.affine_inverse()), key, base)
	holder.remove_child(base)
	holder.free()
	return inside


## Seats whose floor point is outside the room's interior (walls, floor). [{path, error}]
static func seats_outside(doc: Dictionary, _base_node: Node3D, inside: Dictionary) -> Array:
	var out: Array = []
	if not (inside.get("min") is Array):
		return out
	var lo := Vector3(inside["min"][0], inside["min"][1], inside["min"][2])
	var hi := Vector3(inside["max"][0], inside["max"][1], inside["max"][2])
	var seats: Array = doc.get("seats", []) if doc.get("seats") is Array else []
	for i in seats.size():
		var p := RoomSchema.vec3(seats[i]["position"])
		var open: Array = inside.get("open", [])
		var floor_ok := "floor" in open or (p.y >= lo.y - 0.3 and p.y <= hi.y - 1.0)
		if p.x < lo.x + SEAT_MARGIN or p.x > hi.x - SEAT_MARGIN or p.z < lo.z + SEAT_MARGIN \
				or p.z > hi.z - SEAT_MARGIN or not floor_ok:
			out.append({"path": "$.seats[%d].position" % i, "error": "seat %s at %s is outside the room: its floor is "
					% [seats[i]["name"], RoomSchema._r(p)] + "x %s..%s, z %s..%s at y %s (a seat at least %s m from "
					% [lo.x, hi.x, lo.z, hi.z, lo.y, SEAT_MARGIN] + "the walls)"})
	return out


## The base room's node: the "Base" child of an assistant's room, or the stock room itself.
static func _base(env: Node) -> Node3D:
	if env == null:
		return null
	return env.get_node_or_null("Base") if env.get_script() == AssistantRoom else env as Node3D


## What the base room is, for its cached interior: a stock room's id, or the glTF room an assistant sent.
static func base_key(m: Node) -> String:
	var env: Node = m.env
	if env != null and env.get_script() == AssistantRoom:
		var id := str(env.get("base_id"))
		return id if id != "" else "base_model:" + str(m.env_id)
	return str(m.env_id)


## From the world to the room frame: the room node's own frame (it moves when the viewer picks another seat).
static func to_room(m: Node) -> Transform3D:
	var env: Node3D = m.env
	return env.global_transform.affine_inverse() if env != null and env.is_inside_tree() else Transform3D()


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


## The screen in the room frame: its centre, size and the way its picture faces (towards the viewer).
static func screen_state(m: Node) -> Dictionary:
	var xf: Transform3D = to_room(m) * (m.screen as Node3D).global_transform
	var size: Vector2 = m.screen.get_flat_size()
	return {"center": _v(xf.origin), "size": [snappedf(size.x, 0.001), snappedf(size.y, 0.001)],
			"facing": _v(xf.basis.z.normalized()), "spherical": bool(m.mode.is_spherical()),
			"relative_to_eye": {"distance": snappedf(m.screen_distance, 0.001),
					"height_above_eye": snappedf(m.screen_height_offset, 0.001),
					"yaw_degrees": snappedf(rad_to_deg(m.screen_yaw), 0.1)}}


## The viewer in the room frame: the floor point they sit over, the eye height a room is designed for, their eyes as
## measured, and the head now (it moves).
static func viewer_state(m: Node) -> Dictionary:
	var r := to_room(m)
	var head: Node3D = m.camera
	var out := {"seat": _v(r * Vector3.ZERO), "seated_eye_height": VREnvironment.NOMINAL_EYE_HEIGHT,
			"eye": _v(r * Vector3(0, float(m.eye_height), 0))}
	if head != null and head.is_inside_tree():
		out["head"] = _v(r * head.global_position)
		out["head_facing"] = _v((r.basis * -head.global_basis.z).normalized())
	return out


## The room on show's use of the limits: its cost as measured when it was built (with its models' triangles).
func _used_now(env: Node, doc: Dictionary) -> Dictionary:
	var u := _used(doc)
	if env != null and env.has_meta("used_cost"):
		u["cost"] = env.get_meta("used_cost")
	return u


## What the document uses of the limits; assets (when read) give the models' triangles for the cost.
func _used(doc: Dictionary, assets := {}) -> Dictionary:
	var widgets := 0
	var texts := 0
	var emitters := 0
	var particles := 0
	var cost := RoomSchema.room_cost(doc)
	for p: Dictionary in doc.get("parts", []):
		if p.has("widget"):
			widgets += 1
		if str(p.get("type", "")) == "text":
			texts += 1
		if str(p.get("type", "")) == "particles":
			emitters += 1
			particles += RoomParticles.amount(p)
		var model: Dictionary = assets.get("models", {}).get(str(p["name"]), {})
		cost += RoomSchema.part_cost(p, int(model.get("triangles", 0)), (model.get("parts", [0]) as Array).size())
	var recolours: Array = doc.get("recolour", []) if doc.get("recolour") is Array else []
	for r: Variant in recolours:
		if r is Dictionary and not RoomSchema.split_match(str(r.get("match", ""))).is_empty():
			cost += RoomSchema.COSTS["part_recolour"]
	return {"parts": (doc.get("parts", []) as Array).size(), "widgets": widgets, "texts": texts,
			"emitters": emitters, "particles": particles, "recolours": recolours.size(), "cost": snappedf(cost, 0.1)}


# --- Changes ---------------------------------------------------------------------------------------------------------

## mode "new" (a whole room) or "patch" (changes to the room on show). On success the change is on show and kept.
func apply(mode: String, patch: Dictionary, summary: String) -> Dictionary:
	if _busy:
		return {"ok": false, "refused": true, "error": "another room change is still loading"}
	var v := RoomSchema.validate(patch, mode)
	if not v["ok"]:
		return {"ok": false, "error": "the room document has %d problem%s" % [v["errors"].size(),
				"" if v["errors"].size() == 1 else "s"], "errors": v["errors"]}
	var cur := current_doc()
	var doc: Dictionary
	if mode == "new":
		doc = patch.duplicate(true)
		if not doc.has("base") and not doc.has("base_model"):
			doc["base"] = "void"
		doc["parts"] = doc.get("parts", [])
		doc["recolour"] = doc.get("recolour", [])
	else:
		var names: Array = (cur.get("parts", []) as Array).map(func(p: Dictionary) -> String: return p["name"])
		for n: Variant in patch.get("remove", []):
			if not (n in names):
				return {"ok": false, "error": "remove: no part %s (only parts the assistant added can go: %s)"
						% [n, ", ".join(names) if not names.is_empty() else "none yet"]}
		doc = RoomSchema.merge(cur, patch)
	doc["schema"] = RoomSchema.VERSION
	if doc.has("base"):
		var ids: Array = bases().map(func(e: Array) -> String: return e[0])
		if not (str(doc["base"]) in ids):
			return {"ok": false, "error": "base %s is not a room here (bases: %s)" % [doc["base"], ", ".join(ids)]}
	var layout := RoomSchema.layout_errors(doc)
	if not layout.is_empty():
		return {"ok": false, "refused": true, "error": "the seats and the screen have %d problem%s" % [layout.size(),
				"" if layout.size() == 1 else "s"], "errors": layout}
	var used := _used(doc)
	if int(used["parts"]) > int(RoomSchema.LIMITS["parts"]):
		return _limit("parts", used["parts"])
	if int(used["widgets"]) > int(RoomSchema.LIMITS["widgets"]):
		return _limit("widgets", used["widgets"])
	if int(used["texts"]) > int(RoomSchema.LIMITS["texts"]):
		return _limit("texts", used["texts"])
	if int(used["emitters"]) > int(RoomSchema.LIMITS["emitters"]):
		return _limit("emitters", used["emitters"])
	if int(used["particles"]) > int(RoomSchema.LIMITS["particles"]):
		return _limit("particles", used["particles"])
	if int(used["recolours"]) > int(RoomSchema.LIMITS["recolours"]):
		return _limit("recolours", used["recolours"])
	_busy = true
	var cache := _cache
	var r: Dictionary = await WorkerTask.run(get_tree(), func() -> Variant: return load_assets_now(doc, cache),
			LOAD_TIMEOUT)
	_busy = false
	if not r["done"]:
		return {"ok": false, "error": "reading the models took over %d s; send smaller ones" % int(LOAD_TIMEOUT)}
	var assets: Dictionary = r["result"]
	if assets.has("error"):
		return {"ok": false, "error": assets["error"], "refused": assets.has("limit")}
	if int(assets["triangles"]) > int(RoomSchema.LIMITS["triangles"]):
		return _limit("triangles", assets["triangles"])
	if int(assets["textures"]) > int(RoomSchema.LIMITS["textures"]):
		return _limit("textures", assets["textures"])
	used = _used(doc, assets)
	if float(used["cost"]) > float(RoomSchema.LIMITS["cost"]):
		return _limit("cost", used["cost"])
	_trim_cache(doc)
	var m := _main()
	var base := make_base(doc, assets)
	if base == null:
		return {"ok": false, "error": "the base room could not be built"}
	var name := Recipes.clean_name(str(doc.get("name", "")))
	if name == "":
		name = DEFAULT_NAME
	doc["name"] = name
	var outside := seats_outside(doc, base, interior_of(base, str(doc["base"]) if doc.has("base")
			else "base_model:" + Recipes.PREFIX + name))
	if not outside.is_empty():
		base.free()
		return {"ok": false, "refused": true, "error": "%d seat%s outside the room" % [outside.size(),
				" is" if outside.size() == 1 else "s are"], "errors": outside}
	var err := AssistantRoom.save(doc, name)
	if err != "":
		push_warning("Assistant room: %s" % err)
	var room := AssistantRoom.build(doc, base, assets, str(doc.get("base", "")))
	room.set_meta("used_cost", used["cost"])
	# The viewer stays where they are: a room the assistant changed never moves them to its default seat.
	room.set_meta("assistant_apply", true)
	var id: String = Recipes.PREFIX + name
	var screen_changed: bool = patch.has("screen") or (mode == "new" and doc.has("screen"))
	var seat: Node = m.features.seat if m.get("features") != null else null
	# The screen goes to the room's new home only if the viewer hasn't moved it this session.
	var screen_home: bool = seat == null or bool(seat.screen_at_home())
	m.use_environment(room, id, true)
	m.adopt_environment_id(id)
	if screen_changed and screen_home and seat != null:
		seat.home_screen()
	changed.emit(summary, name)
	used["triangles"] = assets["triangles"]
	used["textures"] = assets["textures"]
	var result := {"state": "kept", "name": name, "room": id, "used": used, "limits": RoomSchema.LIMITS,
			"removed_from_models": assets["removed"],
			"turned_in_models": assets.get("turned", []), "warnings": warnings(doc)}
	var ss := seats_state(m)
	result["viewer"] = {"seat_in_use": ss["in_use"], "moved": ss["moved"]}
	if ss.has("was"):
		result["viewer"]["was"] = ss["was"]
	if bool(ss["moved"]):
		result["viewer"]["note"] = "the viewer stays where they were; their seat moved (suggest_seat if you want " \
				+ "them there)"
	if screen_changed:
		result["screen"] = "shown at its new home" if screen_home else "kept where the viewer put it this session " \
				+ "(Reset room shows the new home)"
	if err != "":
		result["save_error"] = err
	if perf_after_change and is_inside_tree():
		# Measured with the change on show; the reply waits for it (about 2 s), so it carries the numbers.
		var perf: Dictionary = await RoomPerf.ensure(get_tree()).after_change()
		for w: String in perf.get("warnings", []):
			(result["warnings"] as Array).append(w)
		result["perf"] = perf
	return {"ok": true, "result": result, "summary": summary}


## What may not look as meant, in plain words (the change is applied anyway): about the room on show, built from doc.
func warnings(doc: Dictionary) -> Array:
	var out: Array = []
	var m := _main()
	var env: Node3D = m.env if m != null else null
	var layer: Node = env.get_node_or_null(AssistantRoom.LAYER) if env != null else null
	if layer != null:
		var parts: Array = []
		for n in layer.get_children():
			if n is Node3D and n.has_meta("local_aabb"):
				parts.append({"name": str(n.name), "aabb": (n as Node3D).transform * (n.get_meta("local_aabb") as AABB)})
		var base := _base(env)
		var geom := RoomBounds.geometry(base, to_room(m))
		var inside := RoomBounds.interior(geom, base_key(m), base)
		AssistantRoom.fit_fog(layer.get_node_or_null("Fog") as Node3D, inside)
		var seats: Array = doc.get("seats", []) if doc.get("seats") is Array else []
		if seats.is_empty():
			var v := viewer_state(m)
			out.append_array(RoomBounds.warnings(parts, geom, inside, Vector3(v["eye"][0], v["eye"][1], v["eye"][2]),
					screen_state(m)))
		else:
			# From every seat, against the room's own screen (else the screen as it is now): what one seat sees is
			# said once per seat; what is so from anywhere (outside the walls, inside a stock part) once.
			var screen: Dictionary = screen_state(m)
			if doc.get("screen") is Dictionary:
				var s: Dictionary = doc["screen"]
				screen = {"center": s["center"], "size": s["size"],
						"facing": RoomBounds._v(RoomSchema.screen_facing(s)),
						"spherical": false}
			var said := {}
			for st: Dictionary in seats:
				var eye := RoomSchema.vec3(st["position"]) + Vector3(0, VREnvironment.NOMINAL_EYE_HEIGHT, 0)
				for w: Dictionary in RoomBounds.warnings(parts, geom, inside, eye, screen):
					if w["kind"] in ["outside_room", "inside_stock_part"]:
						if said.has(w["warning"]):
							continue
						said[w["warning"]] = true
					else:
						w["seat"] = st["name"]
						w["warning"] = "from seat %s, %s" % [st["name"], w["warning"]]
					out.append(w)
	for p: Dictionary in doc.get("parts", []):
		var mat: Dictionary = p.get("material", {}) if p.get("material") is Dictionary else {}
		if (mat.has("texture") or mat.has("texture_file")) and mat.has("emission"):
			out.append({"part": p["name"], "kind": "emission_on_picture", "warning": "emission adds light on top of "
					+ "the picture and washes it out (white makes it white); a picture already shows at its own "
					+ "brightness, so leave emission out"})
		_material_warnings(mat, str(p["name"]), out)
	for r: Dictionary in doc.get("recolour", []):
		var mat: Dictionary = r.get("material", {}) if r.get("material") is Dictionary else {}
		_material_warnings(mat, str(r["match"]), out)
		var split := RoomSchema.split_match(str(r["match"]))
		if not split.is_empty() and layer != null and AssistantRoom.part_targets(layer, str(r["match"])).is_empty():
			out.append({"part": r["match"], "kind": "no_such_part", "warning": "%s matches no part of a placed model "
					% r["match"] + "(object_info with placed lists them); kept, and applied if one comes"})
	return out


## A library material the app does not know (yet): left out, said once.
static func _material_warnings(mat: Dictionary, where: String, out: Array) -> void:
	if mat.has("library_material") and AssistantRoom.library_material(str(mat["library_material"])).is_empty():
		out.append({"part": where, "kind": "unknown_material", "warning": "no library material %s here; the rest "
				% mat["library_material"] + "of the material applies without it"})


static func _limit(name: String, value: Variant) -> Dictionary:
	return {"ok": false, "refused": true, "limit": name, "error": "%s: %s, at most %s; send fewer or smaller" % [
			name, value, RoomSchema.LIMITS[name]]}


func _trim_cache(doc: Dictionary) -> void:
	var keep_keys := {}
	for p: Dictionary in doc.get("parts", []):
		if p.has("model"):
			keep_keys[str(p["model"]).md5_text()] = true
	for k: Variant in _cache.keys():
		if not keep_keys.has(k):
			free_assets({"models": {"x": _cache[k]}})
			_cache.erase(k)


## Frees the read models (templates, never in the tree; rooms hold duplicates).
static func free_assets(assets: Dictionary) -> void:
	var nodes: Array = (assets.get("models", {}) as Dictionary).values()
	if assets.has("base_model"):
		nodes.append(assets["base_model"])
	for r: Dictionary in nodes:
		var n: Variant = r.get("node")
		if n is Node and is_instance_valid(n) and not (n as Node).is_inside_tree():
			(n as Node).free()
		r.erase("node")


# --- Loading (also used by assistant_room.gd for kept rooms) ------------------------------------------------------

## Reads a document's models and pictures. Safe on a worker thread. {models, images, base_model, triangles,
## textures, removed} or {error, limit?}.
static func load_assets_now(doc: Dictionary, cache := {}) -> Dictionary:
	var out := {"models": {}, "images": {}, "alpha": {}, "triangles": 0, "textures": 0, "removed": [], "turned": []}
	var lim := RoomSchema.LIMITS
	if doc.has("base_model"):
		var r := _model(str(doc["base_model"]), cache)
		if r.has("error"):
			return {"error": "base_model: " + str(r["error"])}
		out["base_model"] = r
	var sky: Dictionary = doc.get("sky", {})
	if sky.has("image"):
		var r := RoomModel.decode_image(Marshalls.base64_to_raw(str(sky["image"])))
		if r.has("error"):
			return {"error": "$.sky.image: " + str(r["error"])}
		out["images"]["sky"] = r["image"]
	var parts: Array = doc.get("parts", [])
	for i in parts.size():
		var p: Dictionary = parts[i]
		if p.has("model"):
			var r := _model(str(p["model"]), cache)
			if r.has("error"):
				return {"error": "$.parts[%d].model: %s" % [i, r["error"]]}
			if int(r["triangles"]) > int(lim["model_triangles"]):
				return {"error": "$.parts[%d].model: model_triangles: %d, at most %d" % [i, r["triangles"],
						lim["model_triangles"]], "limit": "model_triangles"}
			if int(r["texture_size"]) > int(lim["texture_size"]):
				return {"error": "$.parts[%d].model: texture_size: %d px, at most %d" % [i, r["texture_size"],
						lim["texture_size"]], "limit": "texture_size"}
			if (r.get("parts", []) as Array).size() > int(lim["model_parts"]):
				return {"error": "$.parts[%d].model: model_parts: %d, at most %d (join meshes that need no colour "
						% [i, (r["parts"] as Array).size(), lim["model_parts"]] + "of their own)",
						"limit": "model_parts"}
			out["models"][p["name"]] = r
			out["triangles"] += int(r["triangles"])
			out["textures"] += int(r["textures"])
			for x: String in r["removed"]:
				out["removed"].append("%s: %s" % [p["name"], x])
			if int(r.get("turned", 0)) > 0:
				out["turned"].append("%s: %d closed shape(s) were inside out (normals in, triangles wound the wrong way) "
						% [p["name"], r["turned"]] + "and were turned the right way; fix the exporter's winding")
		var m: Dictionary = p.get("material", {}) if p.get("material") is Dictionary else {}
		if m.has("texture"):
			var r := RoomModel.decode_image(Marshalls.base64_to_raw(str(m["texture"])))
			if r.has("error"):
				return {"error": "$.parts[%d].material.texture: %s" % [i, r["error"]]}
			out["images"]["part:" + str(p["name"])] = r["image"]
			out["alpha"]["part:" + str(p["name"])] = r["alpha"]
	var rec: Array = doc.get("recolour", [])
	for i in rec.size():
		var m: Dictionary = rec[i].get("material", {}) if rec[i].get("material") is Dictionary else {}
		if m.has("texture"):
			var r := RoomModel.decode_image(Marshalls.base64_to_raw(str(m["texture"])))
			if r.has("error"):
				return {"error": "$.recolour[%d].material.texture: %s" % [i, r["error"]]}
			out["images"]["recolour:" + str(rec[i]["match"])] = r["image"]
			out["alpha"]["recolour:" + str(rec[i]["match"])] = r["alpha"]
	out["textures"] += (out["images"] as Dictionary).size()
	return out


static func _model(b64: String, cache: Dictionary) -> Dictionary:
	var key := b64.md5_text()
	if cache.has(key):
		return cache[key]
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.is_empty():
		return {"error": "not base64"}
	var r := RoomModel.load_glb(bytes)
	if not r.has("error"):
		cache[key] = r
	return r


## The base room node: a stock room by id, or the document's glTF room.
static func make_base(doc: Dictionary, assets: Dictionary) -> Node3D:
	if assets.has("base_model"):
		var room: Node3D = (load("res://scripts/env/gltf_room.gd") as GDScript).new()
		room.name = "GltfRoom"
		room.set("ambient_level", 0.15)
		room.set("screen_glow", 0.6)
		room.set("default_screen_width", 3.0)
		var scene: Node = (assets["base_model"]["node"] as Node).duplicate()
		room.add_child(scene)
		room.call("_settle", scene, "")
		return room
	var id := str(doc.get("base", "void"))
	for e: Array in bases():
		if e[0] == id:
			return EnvLibrary.instantiate(e)
	return null
