extends SceneTree

## The vista system (scripts/env/systems/vista.gd; docs/environments.md, "The vista"): each shape (hills, mesas, an
## acropolis, birches, cypresses, a pool) builds from its defaults as one mesh, one draw, far out or where it was put;
## an unknown shape or a far item is refused; the scenery takes the sky system's light and follows dusk; without a sky
## it takes its own `light`; the pool's light is placed where the pool is, and again when the room moves; the live
## lights reach the shader; the grounds keep clear of the room's floor; a test room (a hall open to the sky, cypresses
## over its walls) passes the checks. Under a renderer (lavapipe): the floodlit ruins, the pool's glow, the snow, and
## the silhouettes against the twilight. No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_vista.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const Vista := preload("res://scripts/env/systems/vista.gd")

const VIEW := Vector2i(320, 320)

var _failures := 0
var _checks := 0
var _shots := 0


func _init() -> void:
	_run.call_deferred()


static func test_doc() -> Dictionary:
	return {"schema": 4, "name": "Courtyard test", "room": {"ambient": 0.05, "screen_glow": 1.0},
		"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
		"systems": [{"system": "light"},
			{"system": "auditorium", "id": "hall", "params": {"ceiling_cover": 0.0}},
			{"system": "screen_frame"},
			{"system": "sky", "params": {"dusk": 0.4, "clouds": 0.3}},
			{"system": "vista", "params": {"items": [
				{"shape": "cypresses", "azimuth": -60.0, "spread": 50.0, "distance": 26.0, "count": 6},
				{"shape": "cypresses", "azimuth": 60.0, "spread": 50.0, "distance": 26.0, "count": 6, "seed": 2},
				{"shape": "hills", "colour": "#10141c"}]}}]}


static func _doc_of(items: Array, with_sky := false, extra := {}) -> Dictionary:
	var systems: Array = []
	if with_sky:
		systems.append({"system": "sky", "params": {"dusk": 0.0}})
	var p := {"items": items}
	p.merge(extra, true)
	systems.append({"system": "vista", "params": p})
	return {"schema": 4, "name": "Vista test", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": systems}


func _build(doc: Dictionary, parent: Node = null) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	(parent if parent != null else root).add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(6.0, 3.0))
	return room


func _run() -> void:
	var s := Registry.spec("vista")
	_check("registered, kind sky", Registry.has("vista") and s["kind"] == "sky")
	# Each shape alone, from its defaults.
	var tri_total := 0
	for shape: String in Vista.SHAPES:
		var doc := _doc_of([{"shape": shape}])
		var v := EnvDoc.validate(doc)
		_check("%s validates (%s)" % [shape, v["errors"]], v["ok"])
		var room := _build(doc)
		await process_frame
		var vista: Node = room.host.system("vista")
		var mi: MeshInstance3D = vista.mesh_instance()
		var m := EnvChecks.measure(room)
		print("  %s: %s" % [shape, m])
		tri_total += int(m["triangles"])
		_check("%s: built, one draw (%d)" % [shape, m["draws"]], mi != null and m["draws"] == 1 and m["triangles"] > 0)
		_check("%s: its defaults filled in" % shape, (vista.built as Array).size() == 1
				and float(vista.built[0]["distance"]) == float(Vista.DEFAULTS[shape]["distance"]))
		var near := INF
		var far := 0.0
		for f: Vector3 in mi.mesh.get_faces():
			var flat := Vector2(f.x, f.z).length()
			near = minf(near, flat)
			far = maxf(far, flat)
		_check("%s: where it was put (%.1f to %.1f m), inside the far plane" % [shape, near, far], far < 185.0
				and near >= (Vista.CLEAR - 0.01 if shape == "pool" else 2.0))
		_check("%s: out of the bake, no shadow" % shape, mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED
				and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		room.queue_free()
		await process_frame
	# Everything at once.
	var all: Array = []
	for shape: String in Vista.SHAPES:
		all.append({"shape": shape})
	var room := _build(_doc_of(all))
	await process_frame
	var every := EnvChecks.measure(room)
	print("  every shape at once: %s (spec: %s)" % [every, s["cost"]])
	_check("every shape at once: still one draw", every["draws"] == 1)
	_check("the spec's cost covers every shape at its defaults (%d)" % every["triangles"],
			int(s["cost"]["triangles"]) >= every["triangles"] and int(s["cost"]["draws"]) >= every["draws"]
			and float(s["cost"]["texture_mb"]) + 0.01 >= float(every["texture_mb"]))
	room.queue_free()
	await process_frame
	# Refusals.
	_check("an unknown shape refused", not EnvDoc.validate(_doc_of([{"shape": "castle"}]))["ok"])
	_check("an item past 170 m refused", not EnvDoc.validate(_doc_of([{"shape": "hills", "distance": 300.0}]))["ok"])
	_check("a field it does not know refused", not EnvDoc.validate(_doc_of([{"shape": "hills", "height": 3}]))["ok"])
	var too_many: Array = []
	for i in 13:
		too_many.append({"shape": "hills"})
	_check("at most 12 items", not EnvDoc.validate(_doc_of(too_many))["ok"])
	# The sky's light.
	room = _build(_doc_of([{"shape": "mesas"}], true))
	await process_frame
	var vista: Node = room.host.system("vista")
	var sky: Node = room.host.system("sky")
	room.host.step(0.1)
	var l0: Array = vista.light_now()
	var sl: Dictionary = sky.sky_light()
	_check("lit by the sky: its colours overhead and at the horizon", (l0[0] as Color).is_equal_approx(sl["zenith"])
			and (l0[1] as Color).is_equal_approx(sl["horizon"]))
	sky.set_param("dusk", 1.0)
	room.host.step(0.1)
	var l1: Array = vista.light_now()
	_check("dusk falls on the mesas too (%s to %s)" % [l0[0], l1[0]],
			(l1[0] as Color).get_luminance() < (l0[0] as Color).get_luminance()
			and (vista.material().get_shader_parameter("sky_top") as Color).is_equal_approx(l1[0]))
	room.queue_free()
	await process_frame
	room = _build(_doc_of([{"shape": "hills"}], false, {"light": "#203050"}))
	await process_frame
	vista = room.host.system("vista")
	_check("no sky: its own light", (vista.light_now()[0] as Color).is_equal_approx(Color("#203050")))
	vista.set_param("light", Color("#405060"))
	_check("which is live", (vista.material().get_shader_parameter("sky_top") as Color).is_equal_approx(
			Color("#405060")))
	room.queue_free()
	await process_frame
	# The pool and the live lights.
	room = _build(_doc_of([{"shape": "pool", "azimuth": 90.0, "distance": 16.0},
			{"shape": "acropolis", "azimuth": -30.0}]))
	await process_frame
	vista = room.host.system("vista")
	room.host.step(0.1)
	var mat: ShaderMaterial = vista.material()
	var pc: Vector3 = mat.get_shader_parameter("pool_centre")
	_check("the pool's light where the pool is: 16 m to the right (%s)" % pc, pc.is_equal_approx(Vector3(16, 0, 0)))
	room.position = Vector3(2.0, 0.0, -3.0)
	room.host.on_room_moved()
	pc = mat.get_shader_parameter("pool_centre")
	_check("and again when the room moves (%s)" % pc, pc.is_equal_approx(Vector3(18, 0, -3)))
	var t0 := float(mat.get_shader_parameter("water_time"))
	for i in 8:
		room.host.step(0.25)
	var tm := float(mat.get_shader_parameter("water_time"))
	_check("the water's light ripples slowly (%.2f in 2 s)" % (tm - t0), is_equal_approx(tm - t0, 1.0))
	room.host.set_setting("motion", 0.0)
	room.host.step(1.0)
	_check("and holds still with Motion off", is_equal_approx(float(mat.get_shader_parameter("water_time")), tm))
	for k: String in ["floodlight", "town_lights", "pool_glow", "snow"]:
		vista.set_param(k, 0.25)
		_check("%s is live" % k, is_equal_approx(float(mat.get_shader_parameter(k)), 0.25))
	room.queue_free()
	await process_frame
	# The courtyard test room.
	var doc := test_doc()
	var v := EnvDoc.validate(doc)
	_check("the courtyard validates (%s)" % [v["errors"]], v["ok"])
	var st := EnvChecks.static_checks(doc)
	for k: String in st:
		_check("static check %s %s" % [k, st[k]], (st[k] as Array).is_empty())
	room = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(12.0, 5.0))
	await process_frame
	room.host.step(0.1)
	var stats := EnvChecks.measure(room)
	print("  courtyard test room: %s" % [stats])
	if DisplayServer.get_name() == "headless":
		_check("within the headset's budget %s" % [EnvChecks.budget(stats)], EnvChecks.budget(stats).is_empty())
	var holder := Node3D.new()
	for sid: String in ["sky", "vista"]:
		for n: Node in room.host.system(sid).owned():
			holder.add_child(n.duplicate())
	var own := EnvChecks.measure(holder)
	holder.free()
	print("  the sky and the vista's own: %s" % [own])
	_check("the sky and the vista: 3 draws (%s)" % [own], own["draws"] == 3)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line from every seat %s" % [blocked.slice(0, 2)], blocked.is_empty())
	_check("no sound of its own", room.host.sounds.is_empty())
	room.queue_free()
	await process_frame
	await _render()
	print("test_env_vista: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


# --- Render (lavapipe) --------------------------------------------------------------------------------------------------

func _viewport(room: Node3D, fov := 60.0) -> Array:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	vp.add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(6.0, 3.0))
	return [vp, cam]


func _shot(vc: Array, at: Vector3, look: Vector3) -> Image:
	(vc[1] as Camera3D).look_at_from_position(at, look)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := (vc[0] as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out := OS.get_environment("ENV_SHOTS")
	if out != "":
		_shots += 1
		img.save_png("%s/vista_%02d.png" % [out, _shots])
	return img


## The mean colour of a rectangle of the picture (fractions of its size).
static func _mean(img: Image, r: Rect2) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for y in range(int(r.position.y * img.get_height()), int(r.end.y * img.get_height())):
		for x in range(int(r.position.x * img.get_width()), int(r.end.x * img.get_width())):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	sum /= maxf(n, 1)
	return Color(sum.x, sum.y, sum.z)


## A direction's look-at point from the eye: azimuth from the room's front (degrees, + right), elevation (degrees).
static func _at(eye: Vector3, azimuth: float, elevation: float) -> Vector3:
	var a := deg_to_rad(azimuth)
	var e := deg_to_rad(elevation)
	return eye + Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)) * 10.0


func _render() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		return
	RenderingServer.global_shader_parameter_set("screen_center", Vector3(0.0, 1.6, -8.0))
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	RenderingServer.global_shader_parameter_set("screen_tint", 0.0)
	RenderingServer.global_shader_parameter_set("env_light", 0.0)
	var room: Node3D = EnvRoom.new()
	room.doc = {"schema": 4, "name": "Vista render", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": [{"system": "sky", "params": {"dusk": 0.35, "glow_bearing": 180.0, "stars": 0.0}},
			{"system": "vista", "params": {"items": [
				{"shape": "mesas", "azimuth": 0.0, "spread": 100.0},
				{"shape": "acropolis", "azimuth": 90.0},
				{"shape": "pool", "azimuth": 180.0, "distance": 16.0},
				{"shape": "birches", "azimuth": -90.0, "distance": 30.0, "spread": 60.0},
				{"shape": "cypresses", "azimuth": -150.0, "distance": 22.0, "spread": 30.0, "count": 5}]}}]}
	var vc := _viewport(room)
	var eye := Vector3(0, 1.2, 0)
	var vista: Node = room.host.system("vista")
	room.host.step(0.1)
	# The mesas against the twilight: darker than the sky over them.
	var img: Image = await _shot(vc, eye, _at(eye, 0.0, 3.0))
	var mesa_sky := _mean(img, Rect2(0.0, 0.05, 1.0, 0.2))
	var mesa_rock := _mean(img, Rect2(0.0, 0.53, 1.0, 0.03))
	print("  mesas: sky %s, rock %s" % [mesa_sky, mesa_rock])
	_check("the mesas stand dark against the twilight (%.3f under %.3f)" % [mesa_rock.get_luminance(),
			mesa_sky.get_luminance()], mesa_rock.get_luminance() < mesa_sky.get_luminance() * 0.5)
	# The acropolis, close up: the floodlit ruins warm and bright over the dark hill.
	(vc[1] as Camera3D).fov = 10.0
	img = await _shot(vc, eye, _at(eye, 90.0, 2.5))
	var lit := _mean(img, Rect2(0.0, 0.0, 1.0, 1.0))
	var stone := _most(img, func(c: Color) -> float: return c.get_luminance() + (c.r - c.b),
			Rect2(0.0, 0.3, 1.0, 0.25))
	vista.set_param("floodlight", 0.0)
	img = await _shot(vc, eye, _at(eye, 90.0, 2.5))
	var unlit := _mean(img, Rect2(0.0, 0.0, 1.0, 1.0))
	print("  acropolis: floodlit %s (brightest %s), not %s" % [lit, stone, unlit])
	_check("the floodlit stone shows, warm (%s)" % [stone], stone.get_luminance() > 0.4 and stone.r > stone.b * 1.3)
	_check("the floodlights add warm light (%s to %s)" % [unlit, lit], lit.r - unlit.r > 0.01
			and lit.r - unlit.r > (lit.b - unlit.b) * 1.5)
	vista.set_param("floodlight", 1.0)
	(vc[1] as Camera3D).fov = 60.0
	# The pool glows in the garden behind.
	img = await _shot(vc, eye, _at(eye, 180.0, -8.0))
	var pool := _most(img, func(c: Color) -> float: return c.b - c.r)
	print("  pool: the most cyan %s" % [pool])
	_check("the pool glows, cyan (%s)" % [pool], pool.b > pool.r * 2.0 and pool.g > pool.r * 2.0
			and pool.get_luminance() > 0.3)
	vista.set_param("pool_glow", 0.0)
	img = await _shot(vc, eye, _at(eye, 180.0, -8.0))
	var off := _most(img, func(c: Color) -> float: return c.b - c.r)
	_check("its lights off: no glow (%s)" % [off], off.b - off.r < (pool.b - pool.r) * 0.4)
	# Birches in snow: the ground pale under the dark sky; no snow, darker.
	img = await _shot(vc, eye, _at(eye, -90.0, -4.0))
	var snow := _mean(img, Rect2(0.0, 0.445, 1.0, 0.04))
	vista.set_param("snow", 0.0)
	img = await _shot(vc, eye, _at(eye, -90.0, -4.0))
	var bare := _mean(img, Rect2(0.0, 0.445, 1.0, 0.04))
	print("  birches: snow %s, bare %s" % [snow, bare])
	_check("snow under the birches, brighter than bare ground (%.3f, %.3f)" % [snow.get_luminance(),
			bare.get_luminance()], snow.get_luminance() > bare.get_luminance() * 1.5)
	# The cypresses: dark spires against the sky.
	img = await _shot(vc, eye, _at(eye, -150.0, 12.0))
	var sky := _mean(img, Rect2(0.0, 0.0, 1.0, 0.15))
	var spire := _most(img, func(c: Color) -> float: return -c.get_luminance(), Rect2(0.0, 0.15, 1.0, 0.3))
	print("  cypresses: sky %s, darkest %s" % [sky, spire])
	_check("the cypresses stand dark against the sky (%.3f, %.3f)" % [spire.get_luminance(), sky.get_luminance()],
			spire.get_luminance() < sky.get_luminance() * 0.4)
	(vc[0] as Node).queue_free()
	await process_frame
	# The courtyard from a seat: the sky and the cypresses over the hall's walls.
	var court: Node3D = EnvRoom.new()
	court.doc = test_doc()
	vc = _viewport(court, 90.0)
	court.host.on_screen_changed(court.get_screen_anchor(), Vector2(12.0, 5.0))
	court.host.step(0.1)
	img = await _shot(vc, Vector3(0, 1.2, 0), Vector3(0.0, 9.0, -14.0))
	var over := _mean(img, Rect2(0.0, 0.0, 1.0, 0.12))
	print("  the courtyard, over the walls: %s" % [over])
	_check("from a seat the open sky shows over the walls (%s)" % [over], over.get_luminance() > 0.05)
	(vc[0] as Node).queue_free()
	await process_frame


## The pixel with the highest score (in a rectangle of the picture, fractions of its size).
static func _most(img: Image, score: Callable, r := Rect2(0.0, 0.0, 1.0, 1.0)) -> Color:
	var best := Color(0, 0, 0)
	var top := -INF
	for y in range(int(r.position.y * img.get_height()), int(r.end.y * img.get_height())):
		for x in range(int(r.position.x * img.get_width()), int(r.end.x * img.get_width())):
			var c := img.get_pixel(x, y)
			var v := float(score.call(c))
			if v > top:
				top = v
				best = c
	return best


static func _brightest(img: Image) -> Color:
	var best := Color(0, 0, 0)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.get_luminance() > best.get_luminance():
				best = c
	return best


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
