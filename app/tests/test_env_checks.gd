extends SceneTree

## Each check (docs/environments.md, "The checks"; scripts/env/env_checks.gd) catching a bad document: a schema error,
## a room over the headset's budget, a wall between the seats and the screen, a brightness that flickers and a motion
## over its limit, an asset that isn't CC0 or isn't credited, a real mark in a name (pastiche passes), a crowd.
## godot --headless --xr-mode off --path app --script res://tests/test_env_checks.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _doc(systems: Array, extra := {}) -> Dictionary:
	var d := {"schema": 4, "name": "Check", "systems": systems,
			"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]}}
	d.merge(extra, true)
	return d


func _build(doc: Dictionary) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	return room


func _run() -> void:
	# Schema.
	var bad := _doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": -1}}])
	_check("schema: a bad parameter (%s)" % [EnvChecks.schema(bad)], EnvChecks.schema(bad).size() == 1)
	# Budget: a hall of 61 x 61 seats.
	var huge := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 30,
			"rows_back": 30, "seats_per_row": 61, "block_x": 20.0, "room_min": [-21, -11, -60],
			"room_max": [21, 25, 90]}}]))
	await process_frame
	var stats := EnvChecks.measure(huge)
	var over := EnvChecks.budget(stats)
	_check("budget: 3721 seats over it (%s)" % [over], over.any(func(s: String) -> bool: return s.begins_with("triangles")))
	huge.queue_free()
	_check("budget: a live light counts", not EnvChecks.budget({"lights": 3}).is_empty())
	# Sight line: a wall across the hall between the seats and the screen; the hall without it is clear.
	var walled := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"partition_z": -6.0,
			"rows_front": 2, "rows_back": 1, "seats_per_row": 5}}]))
	await process_frame
	var blocked: Array = await EnvChecks.sight_line(self, walled)
	_check("sight line: the wall in the way (%d reports: %s)" % [blocked.size(), blocked.slice(0, 1)],
			blocked.size() >= 8)
	walled.queue_free()
	var open := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"rows_front": 2,
			"rows_back": 1, "seats_per_row": 5}}]))
	await process_frame
	blocked = await EnvChecks.sight_line(self, open)
	_check("sight line: without it, clear (%s)" % [blocked], blocked.is_empty())
	open.queue_free()
	# A steep enough rake that the row in front's backs block the screen's bottom.
	var flat := _build(_doc([{"system": "light"}, {"system": "auditorium", "params": {"row_rise": 0.0,
			"rows_front": 7, "rows_back": 0, "seats_per_row": 3}}],
			{"screen": {"center": [0.0, 0.0, -13.8], "size": [12.0, 5.0]}}))
	await process_frame
	blocked = await EnvChecks.sight_line(self, flat)
	_check("sight line: flat rows with a low screen, seat backs in the way (%d)" % blocked.size(), not blocked.is_empty())
	flat.queue_free()
	# Comfort.
	var flicker := _doc([{"system": "light", "params": {"house_lamps": {"bind": "film.transient"}}}])
	_check("comfort: a brightness following a channel unsmoothed (%s)" % [EnvChecks.comfort(flicker)],
			EnvChecks.comfort(flicker).size() == 1)
	var smooth := _doc([{"system": "light", "params": {"house_lamps": {"bind": "film.transient", "smooth": 0.2}}}])
	_check("comfort: smoothed, fine", EnvChecks.comfort(smooth).is_empty())
	var snap := _doc([{"system": "light"}], {"cues": [{"name": "snap", "when": {"state": "playing"},
			"steps": [{"set": "light.house_lamps", "to": 0.0, "seconds": 0.0}]}]})
	_check("comfort: a cue's fade too quick (%s)" % [EnvChecks.comfort(snap)], EnvChecks.comfort(snap).size() == 1)
	var fake := func(n: String) -> Dictionary:
		return {"kind": "motion", "moves_viewer": n == "camera_crane", "params": {"tilt": {"type": "float",
				"min": 0.0, "max": 10.0, "default": 0.5, "motion": {"max": 1.5}}}}
	var tilted := _doc([{"system": "sway", "params": {"tilt": 4.0}}, {"system": "camera_crane"}])
	var c: Array = EnvChecks.comfort(tilted, fake)
	_check("comfort: a motion over its limit and a system moving the viewer (%s)" % [c], c.size() == 2)
	# Licences.
	var cinema_doc: Dictionary = preload("res://scripts/env/env_doc.gd").load_file("res://environments/cinema.env.json")["doc"]
	_check("licences: the cinema's library materials, CC0 and credited (%s)" % [EnvChecks.materials_of(cinema_doc)],
			EnvChecks.licences(cinema_doc).is_empty() and EnvChecks.materials_of(cinema_doc).size() >= 8)
	var uncredited := _doc([], {"credits": [{"asset": "textures/poster.png", "title": "Poster", "source": "made here",
			"licence": "CC0 1.0"}]})
	_check("licences: an asset not bundled and not credited (%s)" % [EnvChecks.licences(uncredited)],
			EnvChecks.licences(uncredited).size() == 2)
	var byline := _doc([], {"credits": [{"asset": "x.ogg", "title": "X", "source": "a site", "licence": "CC-BY 4.0"}]})
	_check("licences: CC-BY refused (%s)" % [EnvChecks.licences(byline)], EnvChecks.licences(byline).any(
			func(s: String) -> bool: return s.contains("not CC0")))
	# Names.
	_check("names: a real mark caught", EnvChecks.names(_doc([], {"name": "The Odeon"})).size() == 1)
	var marks := ["Nickelodeon", "Regal", "Omnimax", "Atmos", "Compton", "Tron", "Quality Street", "Kia-Ora",
			"Trinitron", "Baird Televisor", "HD Ready", "Sinclair", "Freeview"]
	var caught := marks.filter(func(m: String) -> bool: return not EnvChecks.names(
			{"settings": [{"label": "Our %s mode" % m.to_lower()}]}).is_empty())
	_check("names: every example caught, any case (%d of %d)" % [caught.size(), marks.size()], caught.size() == marks.size())
	var pastiche := {"name": "Sirclive", "settings": [{"label": "FreeDTV box", "description": "The atmosphere of a "
			+ "regalia-free electron gun on a Trinitronic set"}]}
	_check("names: pastiche passes, and so do words that hold a mark (%s)" % [EnvChecks.names(pastiche)],
			EnvChecks.names(pastiche).is_empty())
	# No people.
	var crowd := _doc([], {"parts": [{"name": "Crowd", "object": "box"}, {"name": "Usher_1", "object": "box"},
			{"name": "Popcorn", "object": "mannequin"}, {"name": "Stand", "object": "box"}]})
	var p: Array = EnvChecks.no_people(crowd)
	_check("no people: a crowd, an usher and a mannequin (%s)" % [p], p.size() == 3)
	_check("no people: the cinema and the Void have none",
			EnvChecks.no_people(cinema_doc).is_empty())
	_tracks()
	_blends()
	await _layers()
	await _shipped_layers()
	_pace()
	_rays()
	await _flow()
	_plain()
	print("test_env_checks: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## Comfort reads the film-time tracks: one on a brightness needs `smooth` (a seek moves it in one frame).
func _tracks() -> void:
	var track := {"target": "sky.dusk", "by": "film.minutes", "keys": [[0, 0], [10, 1]]}
	var c: Array = EnvChecks.comfort(_doc([{"system": "sky"}], {"timeline": {"tracks": [track]}}))
	_check("tracks: one on a brightness, unsmoothed (%s)" % [c], c.size() == 1 and str(c[0]).contains("track sky.dusk"))
	var smoothed := track.duplicate(true)
	smoothed["smooth"] = 0.5
	c = EnvChecks.comfort(_doc([{"system": "sky"}], {"timeline": {"tracks": [smoothed]}}))
	_check("tracks: smoothed, fine (%s)" % [c], c.is_empty())
	var hour := track.duplicate(true)
	hour["target"] = "sky.hour"
	c = EnvChecks.comfort(_doc([{"system": "sky"}], {"timeline": {"tracks": [hour]}}))
	_check("tracks: one on a parameter that is no brightness, fine (%s)" % [c], c.is_empty())


## Which materials are blended over what is behind them (glass, haze, a glow), and which are not (a cut-out).
func _blends() -> void:
	_check("blends: a plain material, no", not EnvChecks.blends(StandardMaterial3D.new()))
	var alpha := StandardMaterial3D.new()
	alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_check("blends: alpha transparency, yes", EnvChecks.blends(alpha))
	var add := StandardMaterial3D.new()
	add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_check("blends: an added blend, yes", EnvChecks.blends(add))
	var scissor := StandardMaterial3D.new()
	scissor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_check("blends: alpha scissor (a cut-out), no", not EnvChecks.blends(scissor))
	_check("blends: a shader with blend_add, yes",
			EnvChecks.blends(_shader_material("shader_type spatial;\nrender_mode unshaded, blend_add;\n")))
	var fragment := "shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n\tALPHA = 0.5;\n}\n"
	_check("blends: a shader that writes ALPHA, yes", EnvChecks.blends(_shader_material(fragment)))
	_check("blends: the same with an alpha scissor threshold, no", not EnvChecks.blends(_shader_material(
			fragment.replace("\tALPHA = 0.5;\n", "\tALPHA = 0.5;\n\tALPHA_SCISSOR_THRESHOLD = 0.5;\n"))))
	_check("blends: a shader with no ALPHA, no", not EnvChecks.blends(_shader_material(
			"shader_type spatial;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n")))
	_check("blends: a shader material with no shader, no", not EnvChecks.blends(ShaderMaterial.new()))
	_check("blends: no material, no", not EnvChecks.blends(null))


func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## The blended layers over the view: none in the Void; a glass pane before the eyes is one layer over all of it, two
## panes two; a solid pane in front hides the one behind it.
func _layers() -> void:
	var room := _build(EnvDoc.load_file("res://environments/void.env.json")["doc"])
	await process_frame
	var l: Dictionary = await EnvChecks.blend_layers(self, room)
	_check("layers: the Void has none (%s)" % [l], float(l["mean"]) == 0.0 and int(l["peak"]) == 0)
	var eye := Vector3(0.0, EnvChecks.EYE_HEIGHT, 0.0)
	var ahead: Vector3 = ((room.call("get_screen_anchor") as Transform3D).origin - eye).normalized()
	var first := _pane(room, eye + ahead * 2.0, ahead)
	l = await EnvChecks.blend_layers(self, room)
	_check("layers: a glass pane 2 m off fills the view, one layer (%s)" % [l], absf(float(l["mean"]) - 1.0) <= 0.03
			and int(l["peak"]) == 1 and absf(float(l["share"]) - 1.0) <= 0.03)
	_pane(room, eye + ahead * 3.0, ahead)
	l = await EnvChecks.blend_layers(self, room)
	_check("layers: a second behind it, two (%s)" % [l], absf(float(l["mean"]) - 2.0) <= 0.06 and int(l["peak"]) == 2)
	first.material_override = StandardMaterial3D.new()
	l = await EnvChecks.blend_layers(self, room)
	_check("layers: the first made solid hides the second (%s)" % [l], float(l["mean"]) == 0.0 and int(l["peak"]) == 0)
	room.queue_free()
	await process_frame


## A glass pane 40 m by 40 m in the room at `at`, turned to face the eyes (ahead: from the eyes to it).
func _pane(room: Node3D, at: Vector3, ahead: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(40.0, 40.0)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = glass
	room.add_child(mi)
	# A quad faces +z: -z away from the eyes turns its face to them.
	mi.transform = Transform3D(Basis.looking_at(ahead), at)
	return mi


## A room that ships: the Bathysphere's glass dome, as measured when the check came in.
func _shipped_layers() -> void:
	var room := _build(EnvDoc.load_file("res://environments/bathysphere.env.json")["doc"])
	await process_frame
	var l: Dictionary = await EnvChecks.blend_layers(self, room)
	# UNDECIDED (brief): "peak at least 1, and at most EnvChecks.BLEND_BUDGET": read as the mean at most the budget
	# (the budget is a mean), not the peak.
	_check("layers: the Bathysphere's dome (%s)" % [l], float(l["mean"]) >= 0.4 and float(l["mean"]) <= 0.75
			and int(l["peak"]) >= 1 and float(l["mean"]) <= EnvChecks.BLEND_BUDGET)
	room.queue_free()
	await process_frame


## The machine's pace and a build time counted in it.
func _pace() -> void:
	var p := EnvChecks.pace()
	_check("pace: over 0 (%.1f ms)" % p, p > 0.0)
	_check("pace: measured once, the same again (%.1f)" % EnvChecks.pace(), EnvChecks.pace() == p)
	_check("build units: the pace is 1 (%.1f)" % EnvChecks.build_units(EnvChecks.pace()),
			EnvChecks.build_units(EnvChecks.pace()) == 1.0)
	_check("build units: 0 ms is 0 (%.1f)" % EnvChecks.build_units(0.0), EnvChecks.build_units(0.0) == 0.0)


## Where a ray enters a box (flow_clear's test of the scenery's boxes).
func _rays() -> void:
	var box := AABB(Vector3(-1.0, -1.0, -5.0), Vector3(2.0, 2.0, 2.0))
	var t := EnvChecks._ray_enters(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), box)
	_check("rays: into a box 3 m off (%.2f)" % t, is_equal_approx(t, 3.0))
	t = EnvChecks._ray_enters(Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, -1.0), box)
	_check("rays: from inside it, 0 (%.2f)" % t, t == 0.0)
	t = EnvChecks._ray_enters(Vector3.ZERO, Vector3(0.0, 1.0, -1.0).normalized(), box)
	_check("rays: one that misses, -1 (%.2f)" % t, t == -1.0)
	t = EnvChecks._ray_enters(Vector3(0.0, 5.0, 0.0), Vector3(0.0, 0.0, -1.0), box)
	_check("rays: parallel to a face, outside its slab, -1 (%.2f)" % t, t == -1.0)
	t = EnvChecks._ray_enters(Vector3.ZERO, Vector3(0.0, 0.0, 1.0), box)
	_check("rays: pointing away, -1 (%.2f)" % t, t == -1.0)


## Scenery that goes by kept clear of the picture: a box of it beyond a solid wall, beside the picture, behind the
## viewer.
func _flow() -> void:
	var screen: Dictionary = Registry.script_of("shopfront").call("screen_for",
			EnvDoc.with_defaults(Registry.spec("shopfront")["params"], {}))
	var room := _build(_doc([{"system": "shopfront", "id": "hall"}], {"screen": screen}))
	await process_frame
	var f: Array = await EnvChecks.flow_clear(self, room)
	_check("flow: nothing goes by, nothing to report (%s)" % [f], f.is_empty())
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar id := \"stub\"\nvar boxes: Array = []\nfunc flow_volumes() -> Array:\n" \
			+ "\treturn boxes\n"
	gs.reload()
	var stub: Node = gs.new()
	var host: Node = room.get("host")
	host.order.append(stub)
	stub.boxes = [AABB(Vector3(20.0, 0.0, -40.0), Vector3(10.0, 10.0, 80.0))]
	f = await EnvChecks.flow_clear(self, room)
	_check("flow: beyond the hall's solid side wall, fine (%s)" % [f], f.is_empty())
	var c := Vector3(float(screen["center"][0]), float(screen["center"][1]), float(screen["center"][2]))
	var middle := c + Vector3(float(screen["size"][0]) * 0.5 + 0.6, 0.0, 0.5)
	stub.boxes = [AABB(middle - Vector3.ONE * 0.25, Vector3.ONE * 0.5)]
	f = await EnvChecks.flow_clear(self, room)
	_check("flow: 0.6 m beside the picture (%s)" % [f.slice(0, 1)], not f.is_empty()
			and str(f[0]).contains("scenery that goes by"))
	stub.boxes = [AABB(Vector3(-1.0, 0.0, 2.0), Vector3(2.0, 2.0, 2.0))]
	f = await EnvChecks.flow_clear(self, room)
	_check("flow: behind the viewer, fine (%s)" % [f], f.is_empty())
	host.order.erase(stub)
	stub.free()
	room.queue_free()
	await process_frame


## A system's parameters with each binding at its strongest, for its comfort_for(): one with no range, keys or map
## is left out.
func _plain() -> void:
	var p: Dictionary = EnvChecks._plain({"a": 1.0, "b": {"bind": "film.bass", "range": [0.2, 3.0]},
			"c": {"bind": "film.colour"}})
	_check("plain: bindings at their strongest (%s)" % [p], p == {"a": 1.0, "b": 3.0})


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
