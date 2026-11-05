extends SceneTree

## The assistant's room changes (scripts/assistant/room_*.gd, docs/assistant.md "Rooms") through the assistant link's
## command whitelist, in the real main scene: the permission off refuses each room command; the document is checked
## with JSON paths; a .glb with a script, an unknown extension, an outside file or too many triangles is refused;
## every change shows at once and is kept as a recipe (no Keep or Undo); remove can't reach the screen; widgets draw;
## room_state reports the screen and the viewer in the room frame; a texture shows at its own brightness; a fresh
## start builds the kept room again; GET /snapshot.png's capture gives a PNG of the size asked while frames go on
## (with a renderer; headless it says there is none, at once).
## godot --headless --xr-mode off --path app --script res://tests/test_assistant_room.gd
## With a renderer (WSL: lavapipe): VK_ICD_FILENAMES=.../lvp_icd.json godot --display-driver x11
##     --rendering-driver vulkan --xr-mode off --path app --script res://tests/test_assistant_room.gd

const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const RoomEditor := preload("res://scripts/assistant/room_editor.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")
const AssistantRoom := preload("res://scripts/assistant/assistant_room.gd")
const RoomSnapshot := preload("res://scripts/assistant/room_snapshot.gd")
const RoomPerf := preload("res://scripts/assistant/room_perf.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ROOM_NAME := "Test assistant room"
const BOUNDS_NAME := "Test assistant bounds"

var _failures := 0
var _checks := 0
var main: Node3D
var commands: AssistantCommands
var editor: RoomEditor
var allow_room := false
## The user objects there before the test: what it kept in the library is deleted at the end.
var _objects_before: Array = []


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_objects_before = ObjectLibrary.list("", "user").map(func(m: Dictionary) -> String: return m["id"])
	_cleanup()
	editor = RoomEditor.new()
	root.add_child(editor)
	commands = AssistantCommands.new()
	commands.allow_control = func() -> bool: return true
	commands.allow_room = func() -> bool: return allow_room
	commands.room = editor
	# The measured cost after each change waits about 2 s with a renderer: only where the tests look at it.
	editor.perf_after_change = DisplayServer.get_name() == "headless"
	main.set_environment("dim_room")
	await _frames(3)

	# --- The permission off refuses every room command; room_state still answers. ---
	var calls := {
		"room_apply": {"room": {"schema": 1}}, "new_room": {"room": {"schema": 1}},
		"add_shape": {"name": "a", "type": "box", "size": [1, 1, 1]}, "add_model": {"name": "m", "model": "AAAA"},
		"recolour": {"match": "*", "color": "#ff0000"}, "set_lighting": {"ambient": 0.5}, "remove": {"name": "a"},
		"add_text": {"name": "t", "text": "hi"}}
	for c: String in calls:
		var r: Dictionary = await commands.run(c, calls[c])
		_check("%s refused while the room permission is off" % c, r.get("ok") == false and r.get("refused") == true
				and "change the room" in str(r.get("error", "")))
	var st: Dictionary = await commands.run("room_state", {})
	_check("room_state answers (%s)" % st.get("result", {}).get("room"), st.get("ok") == true
			and st["result"]["room"] == "dim_room" and st["result"]["allowed"] == false)
	var widgets: Array = st["result"]["supported_widgets"].map(func(w: Dictionary) -> String: return w["name"])
	_check("supported widgets listed (%s)" % [widgets], widgets.has("clock") and widgets.has("film_progress")
			and widgets.has("screen_glow"))
	var stock: Array = st["result"]["stock_parts"]
	_check("the stock room's parts are listed (%d)" % stock.size(), not stock.is_empty())
	allow_room = true

	# --- Validation: every problem with its JSON path. ---
	var r: Dictionary = await commands.run("room_apply", {"room": {"schema": 9, "parts": [
		{"name": "x", "type": "pyramid"}, {"name": "y", "type": "box", "size": [1, 2]},
		{"name": "z", "type": "cylinder", "size": [1, 1], "widget": "weather"},
		{"name": "w", "type": "box", "size": [1, 1, 1], "widget": "clock", "widget_options": {"style": "sundial"}}],
		"lights": [{"type": "omni"}], "sky": {"color": "nope"}}})
	var paths: Array = r.get("errors", []).map(func(e: Dictionary) -> String: return e["path"])
	_check("validation lists each problem (%s)" % [paths], r.get("ok") == false and paths.has("$.schema")
			and paths.has("$.parts[0].type") and paths.has("$.parts[1].size") and paths.has("$.parts[2].widget")
			and paths.has("$.parts[3].widget_options.style") and paths.has("$.lights[0].type") and paths.has("$.sky.color"))
	var unknown_widget := ""
	for e: Dictionary in r.get("errors", []):
		if e["path"] == "$.parts[2].widget":
			unknown_widget = e["error"]
	_check("an unknown widget names the supported ones (%s)" % unknown_widget, "clock" in unknown_widget
			and "film_progress" in unknown_widget)

	# --- Models: checked before reading. ---
	var good := _glb_of(_sphere(8, 4))
	_check("a plain .glb passes the check", RoomModel.precheck(good) == "")
	var scripted := _with_json(good, func(g: Dictionary) -> void:
		g["nodes"][0]["extras"] = {"script": "OS.execute('rm', ['-rf', '/'])"})
	r = await commands.run("add_model", {"name": "bad", "model": Marshalls.raw_to_base64(scripted)})
	_check("a .glb carrying a script is refused (%s)" % r.get("error"), r.get("ok") == false
			and "script" in str(r.get("error")))
	var behaviour := _with_json(good, func(g: Dictionary) -> void: g["extensionsUsed"] = ["KHR_interactivity"])
	r = await commands.run("add_model", {"name": "bad", "model": Marshalls.raw_to_base64(behaviour)})
	_check("a behaviour-graph extension is refused (%s)" % r.get("error"), r.get("ok") == false
			and "KHR_interactivity" in str(r.get("error")))
	var outside := _with_json(good, func(g: Dictionary) -> void: g["buffers"][0]["uri"] = "../../.ssh/id_ed25519")
	r = await commands.run("add_model", {"name": "bad", "model": Marshalls.raw_to_base64(outside)})
	_check("a .glb pointing at an outside file is refused (%s)" % r.get("error"), r.get("ok") == false
			and "outside file" in str(r.get("error")))
	var big := _glb_of(_sphere(400, 200))  # 160 000 triangles
	r = await commands.run("add_model", {"name": "big", "model": Marshalls.raw_to_base64(big)})
	_check("an over-cap mesh is refused, naming the limit (%s)" % r.get("error"), r.get("ok") == false
			and "model_triangles" in str(r.get("error")) and r.get("refused") == true)
	_check("the room is untouched after refusals", main.env_id == "dim_room")

	# --- room_state in the room frame: the screen's centre, size and facing; the viewer. ---
	main.set_screen(2.0, 0.89, -0.15)
	st = await commands.run("room_state", {})
	var scr: Dictionary = st["result"]["screen"]
	var want := Vector3(0, float(main.eye_height) - 0.15, -0.89)
	_check("the screen's centre in the room frame (%s, want %s)" % [scr["center"], want],
			_vec3(scr["center"]).is_equal_approx(want.snapped(Vector3.ONE * 0.001)))
	_check("its size and facing (%s, %s)" % [scr["size"], scr["facing"]], absf(float(scr["size"][0]) - 2.0) < 0.01
			and _vec3(scr["facing"]).is_equal_approx(Vector3(0, 0, 1)))
	_check("the old numbers only as relative_to_eye", not scr.has("distance") and not scr.has("height")
			and is_equal_approx(float(scr["relative_to_eye"]["distance"]), 0.89))
	var viewer: Dictionary = st["result"]["viewer"]
	_check("the viewer: seat, seated eye height, eyes, head (%s)" % viewer, _vec3(viewer["seat"]) == Vector3.ZERO
			and is_equal_approx(float(viewer["seated_eye_height"]), 1.2) and viewer.has("eye") and viewer.has("head")
			and "floor at y = 0" in str(st["result"]["frame"]))
	_check("no pending field", not st["result"].has("pending"))
	main.reset_screen()

	# --- A change shows at once and is kept: no Keep, no Undo. ---
	r = await commands.run("add_shape", {"name": "Lamp", "type": "cylinder", "size": [0.3, 0.05],
			"position": [1.2, 1.5, -2.5], "rotation": [90, 0, 0], "material": {"color": "#303030"},
			"widget": "clock"})
	var res: Dictionary = r.get("result", {})
	_check("add_shape is kept at once (%s)" % r.get("error", res), r.get("ok") == true and res.get("state") == "kept"
			and main.env_id == "recipe:Assistant room"
			and FileAccess.file_exists(AssistantRoom.json_path("Assistant room")))
	_check("the reply has warnings (a list)", res.get("warnings") is Array)
	var layer: Node = main.env.get_node_or_null(AssistantRoom.LAYER)
	_check("the part is in the AssistantLayer", layer != null and layer.get_node_or_null("Lamp") != null)
	_check("a clock widget on it", layer != null and layer.get_node_or_null("Lamp/Widget") != null)
	_check("the screen is not in the layer", layer != null and not layer.is_ancestor_of(main.screen))
	r = await commands.run("add_shape", {"name": "B", "type": "box", "size": [1, 1, 1]})
	_check("a second change right after (%s)" % r.get("error", ""), r.get("ok") == true
			and main.env.get_node_or_null("AssistantLayer/Lamp") != null
			and main.env.get_node_or_null("AssistantLayer/B") != null)
	r = await commands.run("remove", {"name": "B"})
	_check("and changed back by the assistant", r.get("ok") == true
			and main.env.get_node_or_null("AssistantLayer/B") == null)

	# --- A picture shows at its own brightness; emission on it is warned about. ---
	var png := _png_b64(Color(0.2, 0.4, 0.8))
	r = await commands.run("add_shape", {"name": "Poster", "type": "plane", "size": [0.6, 0.9],
			"position": [-1.5, 1.4, -2.9], "rotation": [90, 0, 0], "material": {"texture": png}})
	var poster := _material_of("Poster")
	_check("a textured part is self-lit, colour white (%s)" % r.get("error", ""), poster != null
			and poster.get_shader_parameter("self_lit") == true
			and poster.get_shader_parameter("albedo") == Color.WHITE)
	_check("no warning for a plain picture (%s)" % [r.get("result", {}).get("warnings")],
			(r.get("result", {}).get("warnings", [1]) as Array).is_empty())
	r = await commands.run("add_shape", {"name": "Poster", "type": "plane", "size": [0.6, 0.9],
			"position": [-1.5, 1.4, -2.9], "rotation": [90, 0, 0], "material": {"texture": png, "self_lit": false,
			"emission": "#ffffff", "emission_strength": 0.9}})
	poster = _material_of("Poster")
	var kinds: Array = (r.get("result", {}).get("warnings", []) as Array).map(func(w: Dictionary) -> String:
		return w["kind"])
	_check("self_lit false follows the room's light", poster != null
			and poster.get_shader_parameter("self_lit") == false)
	_check("emission on a picture is warned about (%s)" % [kinds], kinds.has("emission_on_picture"))
	r = await commands.run("add_shape", {"name": "Plain", "type": "box", "size": [0.2, 0.2, 0.2],
			"position": [1, 1, -2]})
	var plain := _material_of("Plain")
	_check("a plain part follows the room's light", plain != null and plain.get_shader_parameter("self_lit") == false)
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [{"name": "x", "type": "box",
			"size": [1, 1, 1], "material": {"self_lit": "yes"}}]}})
	_check("self_lit must be true or false", r.get("ok") == false and str(r.get("errors", [])).contains("self_lit"))

	# --- A model, recolour, light: each kept. ---
	r = await commands.run("add_model", {"name": "Ball", "model": Marshalls.raw_to_base64(good),
			"position": [-1, 1, -2], "scale": 0.5})
	_check("add_model is kept (%s)" % r.get("error", ""), r.get("ok") == true and main.env_id == "recipe:Assistant room")
	r = await commands.run("room_apply", {"room": {"schema": 1, "name": ROOM_NAME,
			"light": {"ambient": 0.3, "screen_glow": 0.8}, "sky": {"color": "#102040"},
			"remove": ["Poster", "Plain", "Lamp"],
			"parts": [{"name": "Progress", "type": "box", "size": [1.2, 0.08, 0.02], "position": [0, 0.4, -2.6],
					"widget": "film_progress", "widget_options": {"style": "bar"}},
				{"name": "Glow", "type": "sphere", "size": [0.3], "position": [1.5, 0.3, -2],
					"widget": "screen_glow"}]}})
	_check("room_apply with a new name (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true
			and r["result"]["name"] == ROOM_NAME)
	r = await commands.run("recolour", {"match": stock[0]["name"], "color": "#884422"})
	_check("recolour a stock part (%s)" % r.get("error", ""), r.get("ok") == true)
	var kept_id: String = main.env_id
	_check("kept as a recipe (%s)" % kept_id, kept_id == "recipe:" + ROOM_NAME
			and FileAccess.file_exists(AssistantRoom.json_path(ROOM_NAME)))
	# Rooms are made of objects: the model is a user object in the library, the room keeps its id.
	var ball := {}
	for p: Dictionary in (main.env.get("doc") as Dictionary)["parts"]:
		if p["name"] == "Ball":
			ball = p
	_check("its model is a library object, no file beside it (%s, %s)" % [DirAccess.get_files_at(
			AssistantRoom.files_dir(ROOM_NAME)), ball], DirAccess.get_files_at(AssistantRoom.files_dir(ROOM_NAME))
			.is_empty() and not ball.has("model") and not ball.has("type")
			and ObjectLibrary.get_object(str(ball.get("object", ""))).get("source") == "user")
	_check("the light applied", is_equal_approx(float(main.env.ambient_level), 0.3))

	# --- remove can't touch the screen, the panel or the stock room. ---
	for name in ["VideoScreen", "Pane", "Base", stock[0]["name"], "Sky"]:
		r = await commands.run("remove", {"name": name})
		_check("remove %s refused (%s)" % [name, r.get("error", "")], r.get("ok") == false)
	_check("the screen is still there", is_instance_valid(main.screen) and main.screen.is_inside_tree())

	# --- The snapshot: a PNG of the size asked, the frames going on meanwhile. ---
	await _snapshot_checks()

	# --- A fresh start builds the kept room from its recipe. ---
	var widget: Node = main.env.get_node_or_null("AssistantLayer/Progress/Widget")
	await _frames(3)
	_check("film_progress draws on its face", widget != null and widget.get_node_or_null("Face") != null)
	var main2 := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main2.settings.read_only = true
	root.remove_child(main)
	main.queue_free()
	root.add_child(main2)
	current_scene = main2
	await _frames(3)
	main2.set_environment(kept_id)
	await _frames(3)
	main = main2
	_check("the kept room after a restart (%s)" % main2.env_id, main2.env_id == kept_id
			and main2.env.get_script() == AssistantRoom)
	_check("with its parts", main2.env.get_node_or_null("AssistantLayer/Ball/Model") != null
			and main2.env.get_node_or_null("AssistantLayer/Progress") != null
			and main2.env.get_node_or_null("AssistantLayer/Sky") != null)
	main2.reset_room()
	await _frames(2)
	_check("Reset room: the stock room again (%s)" % main2.env_id, main2.env_id == "dim_room")
	_uv_layout_checks()
	await _bounds_checks()
	await _text_and_uv_checks()
	await _alpha_checks()
	await _motion_checks()
	await _particle_checks()
	await _effect_checks()
	await _react_checks()
	await _sky_checks()
	await _transparent_snapshot_checks()
	await _seat_checks()
	await _lighting_checks()
	await _perf_checks()
	_cleanup()
	print("test_assistant_room: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _snapshot_checks() -> void:
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	var r: Dictionary = await snap.capture("seat", Vector2i(320, 180))
	process_frame.disconnect(count)
	if DisplayServer.get_name() == "headless":
		_check("headless: no picture, said at once (%s)" % r.get("error"), "renderer" in str(r.get("error", ""))
				and frames[0] <= 1)
		print("test_assistant_room: snapshot pictures need a renderer; run with one to check them")
	else:
		var img := Image.new()
		var ok: bool = r.has("png") and img.load_png_from_buffer(r["png"]) == OK
		_check("a PNG of 320 x 180 from the seat (%s)" % r.get("error", img.get_size()), ok
				and img.get_size() == Vector2i(320, 180))
		_check("the frames went on while it was made (%d)" % frames[0], frames[0] >= 2)
		# ROOM_SNAPSHOT_OUT=/some/dir: the pictures saved there, to look at.
		var out_dir := OS.get_environment("ROOM_SNAPSHOT_OUT")
		if out_dir != "" and ok:
			img.save_png(out_dir.path_join("seat.png"))
		var direct := snap._viewport.get_texture().get_image()
		direct.convert(Image.FORMAT_RGB8)
		var mid := Vector2i(160, 90)
		_check("the pixels as rendered (%s, %s)" % [img.get_pixelv(mid) if ok else "-", direct.get_pixelv(mid)], ok
				and img.get_pixelv(mid).is_equal_approx(direct.get_pixelv(mid)))
		r = await snap.capture("viewer", Vector2i(640, 360))
		ok = r.has("png") and img.load_png_from_buffer(r["png"]) == OK
		_check("from the viewer, 640 x 360", ok and img.get_size() == Vector2i(640, 360))
		if out_dir != "" and ok:
			img.save_png(out_dir.path_join("viewer.png"))
	snap.queue_free()


## The picture layouts the guide describes, measured from the engine's own meshes.
func _uv_layout_checks() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(2, 1, 0.5)
	var a: Array = b.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var cells_ok := true
	var front_top_left := Vector2(-1, -1)
	for i in v.size():
		var cell: Vector2 = AssistantRoom.BOX_CELLS[Vector3i(n[i].round())]
		var d := uv[i] - cell
		if d.x < -0.001 or d.y < -0.001 or d.x > 1.0 / 3.0 + 0.001 or d.y > 0.501:
			cells_ok = false
		if n[i].z > 0.5 and v[i].x < 0 and v[i].y > 0:
			front_top_left = uv[i]
	_check("BoxMesh: one picture in six pieces, 3 x 2, as the guide says", cells_ok)
	_check("BoxMesh: the front's piece is the top-left one, upright (%s)" % front_top_left,
			front_top_left.is_equal_approx(Vector2.ZERO))
	var pl := PlaneMesh.new()
	a = pl.surface_get_arrays(0)
	v = a[Mesh.ARRAY_VERTEX]
	uv = a[Mesh.ARRAY_TEX_UV]
	var plane_ok := true
	for i in v.size():
		if v[i].x < 0 and v[i].z < 0 and not uv[i].is_equal_approx(Vector2.ZERO):
			plane_ok = false
	_check("PlaneMesh: the picture's top-left at the -X, -Z corner", plane_ok)
	var sp := SphereMesh.new()
	a = sp.surface_get_arrays(0)
	v = a[Mesh.ARRAY_VERTEX]
	uv = a[Mesh.ARRAY_TEX_UV]
	var sphere_ok := true
	for i in v.size():
		var d := v[i].normalized()
		if d.x > 0.9999 and absf(uv[i].x - 0.25) > 0.01:
			sphere_ok = false
		if d.z > 0.9999 and not (uv[i].x < 0.01 or uv[i].x > 0.99):
			sphere_ok = false
		if d.y > 0.999 and uv[i].y > 0.01:
			sphere_ok = false
	_check("SphereMesh: u 0 at the front, 0.25 at +X, the top at the pole", sphere_ok)
	var cy := CylinderMesh.new()
	a = cy.surface_get_arrays(0)
	v = a[Mesh.ARRAY_VERTEX]
	n = a[Mesh.ARRAY_NORMAL]
	uv = a[Mesh.ARRAY_TEX_UV]
	var cyl_ok := true
	for i in v.size():
		if absf(n[i].y) < 0.1 and uv[i].y > 0.501:
			cyl_ok = false
		if n[i].y > 0.9 and v[i].x == 0 and v[i].z == 0 and not uv[i].is_equal_approx(Vector2(0.25, 0.75)):
			cyl_ok = false
		if n[i].y < -0.9 and v[i].x == 0 and v[i].z == 0 and not uv[i].is_equal_approx(Vector2(0.75, 0.75)):
			cyl_ok = false
	_check("CylinderMesh: the side in the top half, the caps centred at (0.25, 0.75) and (0.75, 0.75)", cyl_ok)


func _kinds(r: Dictionary) -> Dictionary:
	var out := {}
	for w: Dictionary in r.get("result", {}).get("warnings", []):
		if not out.has(w["part"]):
			out[w["part"]] = []
		out[w["part"]].append(w["kind"])
	return out


func _bounds_checks() -> void:
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"parts": [{"name": "Fine", "type": "box", "size": [0.4, 0.4, 0.4], "position": [2.6, 1.2, -3]},
			{"name": "InWall", "type": "box", "size": [0.5, 0.5, 0.5], "position": [4.1, 1.2, -2]},
			{"name": "Gone", "type": "box", "size": [0.5, 0.5, 0.5], "position": [9, 1.2, -2]},
			{"name": "BehindScreen", "type": "box", "size": [0.3, 0.3, 0.3], "position": [0, 1.3, -4.2]},
			{"name": "Behind", "type": "box", "size": [0.3, 0.3, 0.3], "position": [0, 1.2, 2]},
			{"name": "Tiny", "type": "box", "size": [0.004, 0.004, 0.004], "position": [1, 1.2, -3.5]}]}})
	var k := _kinds(r)
	_check("dim room: the new room is kept (%s)" % r.get("error", ""), r.get("ok") == true)
	_check("a part well placed has no warning (%s)" % [k.get("Fine")], not k.has("Fine"))
	_check("partly in the wall: outside_room (%s)" % [k.get("InWall")], k.get("InWall", []).has("outside_room"))
	_check("wholly outside: outside_room (%s)" % [k.get("Gone")], k.get("Gone", []).has("outside_room"))
	_check("behind the screen (%s)" % [k.get("BehindScreen")], k.get("BehindScreen", []).has("behind_screen"))
	_check("behind the viewer (%s)" % [k.get("Behind")], k.get("Behind", []).has("behind_viewer"))
	_check("too small to see (%s)" % [k.get("Tiny")], k.get("Tiny", []).has("too_small"))
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	var inside: Dictionary = st["base"]["interior"]
	_check("dim room's interior: x -4..4, y 0..3, z -4.6..3.4 (%s)" % inside, inside.has("min")
			and _vec3(inside["min"]).is_equal_approx(Vector3(-4, 0, -4.6))
			and _vec3(inside["max"]).is_equal_approx(Vector3(4, 3, 3.4)) and (inside["open"] as Array).is_empty())
	var room_box: Dictionary = {}
	for s: Dictionary in st["stock_parts"]:
		if s["name"] == "Room":
			room_box = s["aabb"]
	_check("stock parts carry their boxes (%s)" % room_box, not room_box.is_empty()
			and _vec3(room_box["min"]).is_equal_approx(Vector3(-4, 0, -4.6)))
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "home_theatre",
			"parts": [{"name": "InCabinet", "type": "box", "size": [0.1, 0.1, 0.1], "position": [0, 0.25, -4.05]},
			{"name": "UnderTable", "type": "box", "size": [0.1, 0.1, 0.1], "position": [0, 0.2, -1.6]}]}})
	k = _kinds(r)
	_check("home theatre (%s)" % r.get("error", ""), r.get("ok") == true)
	_check("inside the cabinet (%s)" % [r.get("result", {}).get("warnings")], k.get("InCabinet", [])
			.has("inside_stock_part") and "Cabinet" in str(r["result"]["warnings"]))
	_check("behind the table (%s)" % [k.get("UnderTable")], k.get("UnderTable", []).has("behind_stock_part"))
	st = (await commands.run("room_state", {}))["result"]
	inside = st["base"]["interior"]
	_check("home theatre's interior (%s)" % inside, inside.has("min")
			and _vec3(inside["min"]).is_equal_approx(Vector3(-3, 0, -4.3))
			and _vec3(inside["max"]).is_equal_approx(Vector3(3, 2.8, 2.2)))
	var listed := {}
	for e: Dictionary in st["bases"]:
		listed[e["id"]] = e["interior"]
	_check("bases seen list their interiors; others say when (%s)" % [listed.get("cinema")],
			listed.get("dim_room") is Dictionary and listed.get("home_theatre") is Dictionary
			and listed.get("cinema") is String)
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "passthrough"}})
	st = (await commands.run("room_state", {}))["result"]
	_check("passthrough: the walls are not known (%s)" % st["base"]["interior"],
			st["base"]["interior"].get("known") == false)


func _text_and_uv_checks() -> void:
	var png := _png_b64(Color(0.9, 0.2, 0.1))
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"parts": [
			{"name": "Sign", "type": "text", "text": "Now showing", "size": [0.2], "position": [0, 2.3, -3],
				"text_options": {"color": "#ffcc66", "background": "#101010", "weight": "bold"}},
			{"name": "Note", "type": "text", "text": "A long line of words that has to wrap at one metre wide",
				"position": [-2, 1.2, -3], "text_options": {"max_width": 1.0, "align": "left"}},
			{"name": "Canvas", "type": "box", "size": [0.8, 0.6, 0.05], "position": [2, 1.4, -3.5],
				"material": {"texture": png, "uv": "front_only", "color": "#402010"}},
			{"name": "Cube", "type": "box", "size": [0.3, 0.3, 0.3], "position": [1, 0.5, -2],
				"material": {"texture": png, "uv": "each_face"}}]}})
	_check("text and box pictures (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var layer: Node = main.env.get_node_or_null(AssistantRoom.LAYER)
	var sign := layer.get_node_or_null("Sign/Text") as Label3D if layer != null else null
	_check("the text is a Label3D", sign != null and sign.text == "Now showing")
	_check("in a sharp (MSDF) font, bold", sign != null and sign.font is FontVariation
			and ((sign.font as FontVariation).base_font as FontFile).multichannel_signed_distance_field)
	_check("its colour", sign != null and sign.modulate.is_equal_approx(Color("#ffcc66")))
	_check("a line is 0.2 m high (%.3f)" % (sign.pixel_size * sign.font.get_height(sign.font_size) if sign else 0.0),
			sign != null and absf(sign.pixel_size * sign.font.get_height(sign.font_size) - 0.2) < 0.001)
	_check("a panel behind it", layer.get_node_or_null("Sign/Background") != null)
	var note := layer.get_node_or_null("Note/Text") as Label3D
	var note_box: AABB = layer.get_node("Note").get_meta("local_aabb")
	_check("max_width wraps (%s)" % note_box, note != null and note.autowrap_mode != TextServer.AUTOWRAP_OFF
			and is_equal_approx(note_box.size.x, 1.0) and note_box.size.y > 0.15
			and note.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT)
	# A box with a picture is kept as a picture object (room_keep.gd): the box_mesh() surfaces in its .glb.
	var canvas := _mesh_of("Canvas")
	var cm: Mesh = canvas.mesh if canvas != null else null
	_check("front_only: two surfaces, the picture on the front", cm != null and cm.get_surface_count() == 2
			and (canvas.get_active_material(0) as ShaderMaterial).get_shader_parameter("use_texture") == true
			and (canvas.get_active_material(1) as ShaderMaterial).get_shader_parameter("use_texture") != true
			and (canvas.get_active_material(1) as ShaderMaterial).get_shader_parameter("albedo")
					.is_equal_approx(Color("#402010")))
	var front_ok := cm != null
	if cm != null:
		var fa := cm.surface_get_arrays(0)
		var fi: PackedInt32Array = fa[Mesh.ARRAY_INDEX]
		var fuv: PackedVector2Array = fa[Mesh.ARRAY_TEX_UV]
		var fn: PackedVector3Array = fa[Mesh.ARRAY_NORMAL]
		var lo := Vector2.ONE
		var hi := Vector2.ZERO
		for i in fi:
			front_ok = front_ok and fn[i].z > 0.5
			lo = lo.min(fuv[i])
			hi = hi.max(fuv[i])
		front_ok = front_ok and fi.size() == 6 and lo.is_equal_approx(Vector2.ZERO) and hi.is_equal_approx(Vector2.ONE)
	_check("the front face shows the whole picture", front_ok)
	var cube := _mesh_of("Cube")
	var each_ok := cube != null and cube.mesh.get_surface_count() == 1
	if each_ok:
		var ca := cube.mesh.surface_get_arrays(0)
		var cn: PackedVector3Array = ca[Mesh.ARRAY_NORMAL]
		var cuv: PackedVector2Array = ca[Mesh.ARRAY_TEX_UV]
		for face: Vector3i in AssistantRoom.BOX_CELLS:
			var lo := Vector2.ONE
			var hi := Vector2.ZERO
			for i in cn.size():
				if Vector3i(cn[i].round()) == face:
					lo = lo.min(cuv[i])
					hi = hi.max(cuv[i])
			# Read back from the picture object's .glb: the engine keeps UVs in 16 bits (within 1/65536).
			each_ok = each_ok and lo.distance_to(Vector2.ZERO) < 0.001 and hi.distance_to(Vector2.ONE) < 0.001
	_check("each_face: the whole picture on every face", each_ok)
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [
			{"name": "a", "type": "sphere", "size": [1], "material": {"uv": "front_only"}},
			{"name": "b", "type": "text"},
			{"name": "c", "type": "text", "text": "x", "material": {"color": "#fff"}, "text_options": {"weight": "heavy"}},
			{"name": "d", "type": "box", "size": [1, 1, 1], "text": "no"}]}})
	var paths: Array = r.get("errors", []).map(func(e: Dictionary) -> String: return e["path"])
	_check("the schema refuses misuse (%s)" % [paths], paths.has("$.parts[0].material.uv") and paths.has("$.parts[1].text")
			and paths.has("$.parts[2].material") and paths.has("$.parts[2].text_options.weight")
			and paths.has("$.parts[3].text"))
	r = await commands.run("add_text", {"name": "Hello", "text": "Hello", "size": 0.15, "position": [0, 1.6, -2.5]})
	_check("add_text (%s)" % r.get("error", ""), r.get("ok") == true
			and main.env.get_node_or_null("AssistantLayer/Hello/Text") != null)
	r = await commands.run("recolour", {"match": "Hello", "color": "#00ff00"})
	_check("recolour reaches a text's colour (%s)" % r.get("error", ""), r.get("ok") == true
			and (main.env.get_node("AssistantLayer/Hello/Text") as Label3D).modulate == Color("#00ff00"))
	if DisplayServer.get_name() != "headless":
		var snap: RoomSnapshot = RoomSnapshot.new()
		root.add_child(snap)
		var s: Dictionary = await snap.capture("seat", Vector2i(640, 360))
		var out_dir := OS.get_environment("ROOM_SNAPSHOT_OUT")
		if out_dir != "" and s.has("png"):
			var f := FileAccess.open(out_dir.path_join("text.png"), FileAccess.WRITE)
			f.store_buffer(s["png"])
			f.close()
		_check("a snapshot of the text room", s.has("png"))
		snap.queue_free()


## A 64 x 64 picture: transparent blue everywhere (blue shows only if alpha is ignored), an opaque red disc inside.
func _cutout_b64() -> String:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 1, 0))
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length()
			if d < 16.0:
				img.set_pixel(x, y, Color(1, 0, 0, clampf(16.0 - d, 0.0, 1.0)))
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


## A snapshot from the viewer (the flat camera at the eyes, looking -Z), 640 x 360, as an Image; null headless.
func _look(size := Vector2i(640, 360), fov := 60.0) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	var s: Dictionary = await snap.capture("viewer", size, fov)
	snap.queue_free()
	var img := Image.new()
	if not s.has("png") or img.load_png_from_buffer(s["png"]) != OK:
		return null
	return img


func _save_shot(img: Image, file: String) -> void:
	var out_dir := OS.get_environment("ROOM_SNAPSHOT_OUT")
	if out_dir != "" and img != null:
		img.save_png(out_dir.path_join(file))


func _alpha_checks() -> void:
	if main.ui != null and main.ui.has_method("hide_panel"):
		main.ui.hide_panel()
		await _frames(40)  # it fades out
	var bat := _cutout_b64()
	var card := {"name": "Bat", "type": "plane", "size": [1, 1], "position": [0, 1.2, -1.5], "rotation": [90, 0, 0],
			"material": {"texture": bat}}
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"parts": [card, {"name": "Haze", "type": "box", "size": [0.4, 0.4, 0.4], "position": [1.5, 1.2, -2.5],
			"material": {"color": "#ffffff60"}}]}})
	var bat_mat := _material_of("Bat")
	var haze_mat := _material_of("Haze")
	_check("a picture with transparent pixels is a cut-out (%s)" % r.get("error", ""), bat_mat != null
			and bat_mat.shader.code.contains("#define ALPHA_CUT"))
	_check("a colour with alpha is see-through", haze_mat != null and haze_mat.shader.code.contains("#define ALPHA_BLEND")
			and is_equal_approx(float(haze_mat.get_shader_parameter("alpha")), 0x60 / 255.0))
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("room_state: the cost used, the cap and the weights (%s of %s)" % [st["used"].get("cost"),
			st["limits"].get("cost")], is_equal_approx(float(st["used"]["cost"]),
			2 * RoomSchema.COSTS["part"] + RoomSchema.COSTS["blend"])
			and st["limits"].has("cost") and st["costs"].has("blend"))
	var cut := await _look()
	_save_shot(cut, "alpha-cutout.png")
	var opaque_card := card.duplicate(true)
	opaque_card["material"]["alpha"] = "opaque"
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [opaque_card]}})
	bat_mat = _material_of("Bat")
	_check("alpha opaque ignores it", bat_mat != null and not bat_mat.shader.code.contains("#define ALPHA"))
	var opaque := await _look()
	if cut != null and opaque != null:
		var corner := Vector2i(403, 97)
		var mid := Vector2i(320, 180)
		var c_cut := cut.get_pixelv(corner)
		var c_opq := opaque.get_pixelv(corner)
		_check("cut-out: the transparent corner shows the room, not the picture's blue (%s, opaque %s)" % [c_cut, c_opq],
				c_opq.b > 0.8 and c_opq.r < 0.2 and c_cut.b < 0.5)
		_check("cut-out: the disc is drawn (%s)" % cut.get_pixelv(mid), cut.get_pixelv(mid).r > 0.8
				and cut.get_pixelv(mid).b < 0.2)
	var parts: Array = []
	# Enough see-through parts to pass the cost cap, whatever a part is priced at.
	var over := ceili(RoomSchema.LIMITS["cost"] / (RoomSchema.COSTS["part"] + RoomSchema.COSTS["blend"])) + 1
	for i in over:
		parts.append({"name": "g%d" % i, "type": "box", "size": [0.1, 0.1, 0.1],
				"position": [float(i % 30) * 0.1 - 1.5, 1.5 + float(i / 30) * 0.15, -3],
				"material": {"color": "#ffffff80"}})
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room", "parts": parts}})
	_check("over the cost cap: refused, naming it (%s)" % r.get("error", ""), r.get("ok") == false
			and r.get("limit") == "cost")


func _motion_checks() -> void:
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"parts": [
			{"name": "BobA", "type": "sphere", "size": [0.2], "position": [-1, 1, -2.5],
				"motion": {"type": "bob", "height": 0.2, "period": 4}},
			{"name": "BobB", "type": "sphere", "size": [0.2], "position": [-0.5, 1, -2.5],
				"motion": {"type": "bob", "height": 0.2, "period": 4}},
			{"name": "WingL", "type": "box", "size": [0.3, 0.02, 0.1], "position": [0.3, 2, -2.5],
				"motion": {"type": "flap", "angle": 40, "period": 0.5, "hinge": [-0.15, 0, 0], "sync": "bat"}},
			{"name": "WingR", "type": "box", "size": [0.3, 0.02, 0.1], "position": [-0.3, 2, -2.5],
				"motion": {"type": "flap", "angle": 40, "period": 0.5, "hinge": [0.15, 0, 0], "sync": "bat",
				"mirror": true}},
			{"name": "Top", "type": "box", "size": [0.2, 0.2, 0.2], "position": [1, 1, -2.5],
				"motion": [{"type": "spin", "speed": 90}, {"type": "orbit", "center": [1, 1, -3], "radius": 0.5,
				"period": 10}]},
			{"name": "Foot", "type": "box", "size": [0.5, 0.3, 0.8], "position": [0, 3, -2.5],
				"motion": {"type": "move_to", "position": [0, 0.15, -2.5], "duration": 10, "at": "end-30"}}]}})
	_check("parts with motion (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var motion: Node = main.env.get_node_or_null("Motion")
	_check("one motion loop for the room (%d parts)" % (motion.count() if motion else 0), motion != null
			and motion.count() == 6)
	if motion == null:
		return
	var layer: Node = main.env.get_node(AssistantRoom.LAYER)
	var y := func(n: String) -> float: return (layer.get_node(n) as Node3D).position.y
	var ys: Array = []
	for i in 9:
		motion.step(i * 0.5, 0.0, 100.0)
		ys.append(y.call("BobA"))
	_check("bob: up and down within its height (%s)" % [ys], ys.max() - ys.min() > 0.1 and ys.max() <= 1.1001
			and ys.min() >= 0.8999)
	motion.step(1.3, 0.0, 100.0)
	_check("copies are not in lockstep (%.3f, %.3f)" % [y.call("BobA"), y.call("BobB")],
			absf(y.call("BobA") - y.call("BobB")) > 0.005)
	var wl: Basis = (layer.get_node("WingL") as Node3D).basis
	var wr: Basis = (layer.get_node("WingR") as Node3D).basis
	_check("a synced pair of wings beats mirrored, together (%.2f, %.2f)" % [wl.get_euler().z, wr.get_euler().z],
			absf(wl.get_euler().z + wr.get_euler().z) < 0.001 and absf(wl.get_euler().z) > 0.01)
	var top := layer.get_node("Top") as Node3D
	_check("orbit: on its circle (%.3f m from the centre)" % Vector2(top.position.x - 1, top.position.z + 3).length(),
			absf(Vector2(top.position.x - 1, top.position.z + 3).length() - 0.5) < 0.001)
	var foot := layer.get_node("Foot") as Node3D
	motion.step(5.0, 60.0, 100.0)
	var before := foot.position.y
	motion.step(5.0, 75.0, 100.0)
	var half := foot.position.y
	motion.step(5.0, 95.0, 100.0)
	var after := foot.position.y
	_check("move_to on the film's clock: still before, halfway eased, then there (%.2f, %.2f, %.2f)" % [before, half,
			after], is_equal_approx(before, 3.0) and is_equal_approx(half, (3.0 + 0.15) / 2.0)
			and is_equal_approx(after, 0.15))
	motion.step(5.0, 10.0, 100.0)
	_check("and seeking back undoes it", is_equal_approx(foot.position.y, 3.0))
	motion.step(1.1, 85.0, 100.0)
	_save_shot(await _look(), "motion.png")
	await _clip_checks()
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [
			{"name": "a", "type": "box", "size": [1, 1, 1], "motion": {"type": "spin", "speed": 500}},
			{"name": "b", "type": "box", "size": [1, 1, 1], "motion": {"type": "wobble"}},
			{"name": "c", "type": "box", "size": [1, 1, 1], "motion": {"type": "move_to", "duration": 5,
				"position": [0, 0, 0], "at": "middle"}},
			{"name": "d", "type": "box", "size": [1, 1, 1], "motion": [{"type": "bob", "height": 0.1, "period": 2},
				{"type": "bob", "height": 0.1, "period": 2}, {"type": "bob", "height": 0.1, "period": 2},
				{"type": "bob", "height": 0.1, "period": 2}]}]}})
	var paths: Array = r.get("errors", []).map(func(e: Dictionary) -> String: return e["path"])
	_check("motion bounds are enforced (%s)" % [paths], paths.has("$.parts[0].motion.speed")
			and paths.has("$.parts[1].motion.type") and paths.has("$.parts[2].motion.at")
			and paths.has("$.parts[3].motion"))


## A clip of the moving room: a sheet of frames that differ, and an animated PNG whose chunks check out.
func _clip_checks() -> void:
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	var frames := [0]
	var count := func() -> void: frames[0] += 1
	process_frame.connect(count)
	var r: Dictionary = await snap.capture_clip("viewer", Vector2i(160, 90), 60.0, 1.0, 8, "sheet")
	process_frame.disconnect(count)
	if DisplayServer.get_name() == "headless":
		_check("clip, headless: no renderer, said at once", "renderer" in str(r.get("error", "")) and frames[0] <= 1)
		snap.queue_free()
		return
	var img := Image.new()
	var ok: bool = r.has("png") and img.load_png_from_buffer(r["png"]) == OK
	_check("a sheet of 8 frames, 3 columns (%s, %s)" % [r.get("error", ""), img.get_size()], ok
			and int(r["frames"]) == 8 and int(r["columns"]) == 3 and img.get_size() == Vector2i(3 * 160 + 4, 3 * 90 + 4))
	_check("the frames went on while it was taken (%d)" % frames[0], frames[0] >= 8)
	if ok:
		_save_shot(img, "motion-clip-sheet.png")
		var diff := 0.0
		for y in range(0, 90, 3):
			for x in range(0, 160, 3):
				var a := img.get_pixel(x, y)
				var b := img.get_pixel(x + 2 * 162, y)
				diff += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		_check("the motion shows: frame 1 and frame 3 differ (%.2f)" % diff, diff > 1.0)
	r = await snap.capture_clip("seat", Vector2i(160, 90), 60.0, 0.5, 8, "apng")
	var png: PackedByteArray = r.get("png", PackedByteArray())
	var chunks := RoomSnapshot._chunks(png) if png.size() > 8 else {}
	var crc_ok := png.size() > 8
	var pos := 8
	while crc_ok and pos + 12 <= png.size():
		var n := (png[pos] << 24) | (png[pos + 1] << 16) | (png[pos + 2] << 8) | png[pos + 3]
		var want := (png[pos + 8 + n] << 24) | (png[pos + 9 + n] << 16) | (png[pos + 10 + n] << 8) | png[pos + 11 + n]
		crc_ok = RoomSnapshot._crc32(png.slice(pos + 4, pos + 8 + n)) == want
		pos += 12 + n
	_check("an animated PNG: acTL, 4 fcTL, fdAT for frames 2 to 4, every CRC right (%s)" % [chunks.keys()],
			chunks.has("acTL") and (chunks.get("fcTL", []) as Array).size() == 4 and chunks.has("fdAT") and crc_ok)
	var first := Image.new()
	_check("its first frame reads as a plain PNG", first.load_png_from_buffer(png) == OK
			and first.get_size() == Vector2i(160, 90))
	snap.queue_free()


## An open arena at night, as the user's colosseum: a stone floor, a ring of arches, two torches, stars, the screen.
func _arena(lit: bool) -> Dictionary:
	var parts: Array = [{"name": "Arena floor", "type": "cylinder", "size": [34, 0.1], "position": [0, -0.05, -4],
			"material": {"color": "#8a7a62"}}]
	var n := 14
	for i in n:
		var a := PI * 0.15 + (PI * 0.7) * i / (n - 1)
		var c := Vector3(cos(a) * -11.0, 0, -4.0 - sin(a) * 11.0)
		var yaw := rad_to_deg(-a) + 90.0
		parts.append({"name": "Pier %d" % i, "type": "box", "size": [1.0, 5.0, 1.2], "position": [c.x, 2.5, c.z],
				"rotation": [0, yaw, 0], "material": {"color": "#b8a585"}})
		if i < n - 1:
			var a2 := PI * 0.15 + (PI * 0.7) * (i + 0.5) / (n - 1)
			var m := Vector3(cos(a2) * -11.0, 0, -4.0 - sin(a2) * 11.0)
			parts.append({"name": "Arch %d" % i, "type": "box", "size": [2.6, 0.8, 1.2], "position": [m.x, 5.4, m.z],
					"rotation": [0, rad_to_deg(-a2) + 90.0, 0], "material": {"color": "#a8967a"}})
	for side in [-1, 1]:
		var tx: float = 3.2 * side
		parts.append({"name": "Torch pole %d" % side, "type": "cylinder", "size": [0.12, 1.6], "position": [tx, 0.8, -3.0],
				"material": {"color": "#3a2a1c"}})
		parts.append({"name": "Torch flame %d" % side, "type": "sphere", "size": [0.22], "position": [tx, 1.72, -3.0],
				"material": {"color": "#ffb050", "emission": "#ff9a30", "emission_strength": 1.2, "self_lit": true}})
	# A stand-in for the film (no video plays in the tests): a dusk picture where the screen is.
	parts.append({"name": "Film stand-in", "type": "plane", "size": [8, 4.5], "position": [0, 3.2, -10.02],
			"rotation": [90, 0, 0], "material": {"texture": _film_b64(), "self_lit": true}})
	var room := {"schema": 1, "name": BOUNDS_NAME, "base": "void",
			"sky": {"color": "#05070f", "stars": {"density": 0.6}},
			"screen": {"center": [0, 3.2, -10], "size": [8, 4.5], "facing": [0, 0, 1]}, "parts": parts}
	if lit:
		# The guide's recipe: a moon from behind and to the left, a cool sky over warm ground, the film's light,
		# two warm torches.
		room["light"] = {"key": {"elevation": 35, "azimuth": -140, "color": "#9fb4e0", "energy": 0.5},
				"sky": {"top": "#4a5878", "bottom": "#3a3026", "energy": 0.35}, "screen": {"energy": 0.8}}
		room["lights"] = [
				{"name": "Torch L", "attach": "Torch flame -1", "offset": [0, 0.15, 0], "color": "#ff9a40", "energy": 2.2,
					"range": 6, "flicker": {"rate": 1.4, "swing": 0.3}},
				{"name": "Torch R", "attach": "Torch flame 1", "offset": [0, 0.15, 0], "color": "#ff9a40", "energy": 2.2,
					"range": 6, "flicker": {"rate": 1.1, "swing": 0.3}}]
	else:
		room["light"] = {"ambient": 0.3, "screen_glow": 0.6}
	return room


## The film stand-in: dusk, warm on the left, blue on the right (and its 4 x 2 copy for the screen's light).
func _film_image() -> Image:
	var img := Image.create_empty(64, 36, false, Image.FORMAT_RGB8)
	for y in 36:
		for x in 64:
			var t := x / 63.0
			img.set_pixel(x, y, Color("#e8823a").lerp(Color("#3a6ad0"), t).darkened(0.35 * y / 35.0))
	return img


func _film_b64() -> String:
	return Marshalls.raw_to_base64(_film_image().save_png_to_buffer())


## The screen's light as if the stand-in were playing: the bias light's copy replaced by the picture's 4 x 2.
func _fake_film(on: bool) -> void:
	if on:
		var small := _film_image()
		small.resize(4, 2, Image.INTERPOLATE_BILINEAR)
		RenderingServer.global_shader_parameter_set("screen_thumb", ImageTexture.create_from_image(small))
	else:
		RenderingServer.global_shader_parameter_set("screen_thumb", main.features.bias._vp.get_texture())


func _lighting_checks() -> void:
	var bad := [
		[{"lights": [{"position": [0, 1, 0]}, {"position": [0, 1, 0]}, {"position": [0, 1, 0]}, {"position": [0, 1, 0]},
				{"position": [0, 1, 0]}]}, "at most 4"],
		[{"lights": [{"position": [0, 1, 0], "flicker": {"rate": 5}}]}, "3 times a second"],
		[{"lights": [{"position": [0, 1, 0], "flicker": {"swing": 0.8}}]}, "no larger brightness swings"],
		[{"lights": [{"color": "#ffffff"}]}, "a position, or attach"],
		[{"light": {"key": {"energy": 3}}}, "0.0..1.5"]]
	for b: Array in bad:
		var room: Dictionary = {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room"}
		room.merge(b[0])
		var rr: Dictionary = await commands.run("new_room", {"room": room})
		var said := str(rr.get("errors", rr.get("error", "")))
		_check("lighting refused: %s (%s)" % [b[1], said.left(140)], rr.get("ok") != true and said.contains(b[1]))
	var r: Dictionary = await commands.run("new_room", {"room": _arena(true)})
	_check("a lit arena (%s %s)" % [r.get("error", ""), str(r.get("errors", "")).left(200)], r.get("ok") == true)
	var env: Node3D = main.env
	var key := env.get_node_or_null("KeyLight") as DirectionalLight3D
	_check("a key light with orthogonal shadows fitted to the room (%s)" % (key.directional_shadow_max_distance
			if key != null else -1.0), key != null and key.shadow_enabled
			and key.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
			and key.directional_shadow_max_distance >= 20.0 and env.has_meta("key_shadows"))
	var torch := env.get_node_or_null("%s/Torch flame -1/Torch L" % AssistantRoom.LAYER) as OmniLight3D
	_check("a torch light on its torch, no shadows", torch != null and not torch.shadow_enabled
			and is_equal_approx(torch.omni_range, 6.0))
	var flick := env.get_node_or_null("LightFlicker")
	_check("the torches flicker", flick != null and flick.count() == 2)
	var lo := 9.0
	var hi := 0.0
	var steepest := 0.0
	var prev := 1.0
	for i in 72 * 10:
		var v: float = flick.level(i / 72.0, 1.4, 0.3, 0.37)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		if i > 0:
			steepest = maxf(steepest, absf(v - prev))
		prev = v
	_check("firelight within the ceiling (%.2f..%.2f, largest step %.3f a frame)" % [lo, hi, steepest], lo >= 0.6
			and hi <= 1.4 and steepest <= 0.4 * TAU * RoomSchema.MAX_HZ / 72.0)
	var pier := _material_of("Pier 0")
	_check("parts are lit (room_lit.gdshader)", pier != null and pier.shader.resource_path.ends_with("room_lit.gdshader"))
	var flame := _material_of("Torch flame -1")
	_check("self_lit parts still glow on their own", flame != null and flame.shader == AssistantRoom.UNLIT_TEX)
	_check("solid parts cast shadows, glows don't", (env.get_node("%s/Pier 0/Mesh" % AssistantRoom.LAYER)
			as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_check("contact shadows under the piers, none under the flames",
			env.get_node_or_null("%s/Contact_Pier 0" % AssistantRoom.LAYER) != null
			and env.get_node_or_null("%s/Contact_Torch flame 1" % AssistantRoom.LAYER) == null)
	_check("the film lights the room: the bias light's copy is kept fresh", main.features.bias._requested())
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	var want := RoomSchema.COSTS["key_light"] + RoomSchema.COSTS["key_shadows"] + 2 * RoomSchema.COSTS["point_light"] \
			* 6.0 / RoomSchema.POINT_LIGHT_COST_RANGE
	_check("lighting costs (%s, at least %s)" % [st["used"]["cost"], want], float(st["used"]["cost"]) >= want - 0.1
			and st.has("lighting"))
	if DisplayServer.get_name() != "headless":
		_fake_film(true)
		await _seconds(1.0)
		_save_shot(await _look(Vector2i(1280, 720), 60.0), "arena-lit.png")
	r = await commands.run("new_room", {"room": _arena(false)})
	_check("the same arena, flat (the old look)", r.get("ok") == true and main.env.get_node_or_null("KeyLight") == null)
	if DisplayServer.get_name() != "headless":
		await _seconds(1.0)
		_save_shot(await _look(Vector2i(1280, 720), 60.0), "arena-flat.png")
		_fake_film(false)
	# A stock room lit: its own surfaces become lit too.
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"light": {"key": {"elevation": 60, "shadows": false}, "sky": {}}}})
	var lit_base := 0
	var lit_library := 0
	for g in (main.env.get_node("Base") as Node).find_children("*", "MeshInstance3D", true, false):
		var m := (g as MeshInstance3D).material_override
		if m == null and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (g as MeshInstance3D).get_surface_override_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("room_lit.gdshader"):
			lit_base += 1
		if m is ShaderMaterial and (m as ShaderMaterial).shader == AssistantRoom.MaterialLibrary.SHADER_LIT:
			lit_library += 1
	_check("a stock room's own surfaces are lit too (%d plain, %d library)" % [lit_base, lit_library],
			r.get("ok") == true and lit_base + lit_library > 0)
	_check("its library surfaces (the plaster walls) in their lit form", lit_library > 0)
	await _true_to_life_check()


## A picture under neutral light at full energy keeps its colours: a painting of four colours, the key light white at
## energy 1 straight onto it, nothing else; each quarter's pixel against the picture's own colour.
func _true_to_life_check() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var colours := [Color("#c0392b"), Color("#2e86c1"), Color("#f4d03f"), Color("#7d6650")]
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, colours[(1 if x >= 32 else 0) + (2 if y >= 32 else 0)])
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "void",
			"light": {"key": {"direction": [0, 0, -1], "color": "#ffffff", "energy": 1.0, "shadows": false},
				"contact_shadows": false},
			"parts": [{"name": "Painting", "type": "box", "size": [1.6, 1.6, 0.02], "position": [0, 1.2, -2.2],
				"material": {"texture": b64, "uv": "front_only"}}]}})
	_check("a painting under a neutral key light (%s)" % r.get("error", ""), r.get("ok") == true)
	await _seconds(0.5)
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	var s: Dictionary = await snap.capture("viewer", Vector2i(640, 360), 60.0)
	var shot := Image.new()
	shot.load_png_from_buffer(s.get("png", PackedByteArray()))
	var worst := 0.0
	var said := []
	var painting := main.env.get_node("%s/Painting" % AssistantRoom.LAYER) as Node3D
	for q in 4:
		var local := Vector3(-0.4 if q % 2 == 0 else 0.4, 0.4 if q < 2 else -0.4, 0.011)
		var px := Vector2i(snap._camera.unproject_position(painting.global_transform * local))
		var got := shot.get_pixelv(px) if not shot.is_empty() else Color.BLACK
		var d := maxf(absf(got.r - colours[q].r), maxf(absf(got.g - colours[q].g), absf(got.b - colours[q].b)))
		worst = maxf(worst, d)
		said.append("#%s for #%s" % [got.to_html(false), colours[q].to_html(false)])
	snap.queue_free()
	_save_shot(shot, "painting-under-key-light.png")
	_check("true to life: every colour within 3 %% (worst %.3f: %s)" % [worst, ", ".join(said)], worst <= 0.03)


func _perf_checks() -> void:
	var r: Dictionary = await commands.run("perf", {})
	var p: Dictionary = r.get("result", {})
	_check("perf answers (%s)" % str(p).left(200), r.get("ok") == true and p.has("budget_ms") and p.has("windows")
			and p.get("film_playing") == false and str(p.get("notes", "")).contains("not representative"))
	# The guard.
	var tight := {"gpu_ms": 11.4, "budget_ms": 13.89, "headroom_ms": 2.49, "film_playing": true, "dropped": 0}
	var w := RoomPerf.verdict(tight)
	_check("the guard: under the margin is a warning with the numbers (%s)" % [w], w.size() == 1
			and w[0].contains("11.4 ms") and w[0].contains("2.5 ms left") and w[0].contains("simplify"))
	w = RoomPerf.verdict({"gpu_ms": 6.0, "budget_ms": 13.89, "headroom_ms": 7.89, "film_playing": true, "dropped": 3})
	_check("and dropped frames since the change (%s)" % [w], w.size() == 1 and w[0].begins_with("3 video frames"))
	w = RoomPerf.verdict({"gpu_ms": 6.0, "budget_ms": 13.89, "headroom_ms": 7.89, "film_playing": true, "dropped": 0})
	_check("a room with room to spare: no warning", w.is_empty())
	# Each change's reply carries the measured cost.
	editor.perf_after_change = true
	var t0 := Time.get_ticks_msec()
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [{"name": "Perf box", "type": "box",
			"size": [0.5, 0.5, 0.5], "position": [1.5, 0.25, -3]}]}})
	var waited := (Time.get_ticks_msec() - t0) / 1000.0
	var pf: Dictionary = r.get("result", {}).get("perf", {})
	if DisplayServer.get_name() == "headless":
		_check("headless: the reply says there is nothing to measure, at once (%.1f s)" % waited, r.get("ok") == true
				and str(pf.get("notes", "")).contains("no renderer") and waited < 1.5)
	else:
		_check("the reply's perf, measured after the change (%s; %.1f s)" % [pf.get("summary", pf), waited],
				r.get("ok") == true and str(pf.get("summary", "")).begins_with("after this change: ")
				and pf.has("headroom_ms") and pf.has("dropped") and waited >= RoomPerf.AFTER_CHANGE
				and waited < RoomPerf.AFTER_CHANGE + 1.5)
		_check("its warnings are the guard's", (r["result"]["warnings"] as Array).filter(func(x: String) -> bool:
				return x.contains("margin") or x.contains("dropped since")).size() == RoomPerf.verdict(pf).size())
	if DisplayServer.get_name() == "headless":
		editor.perf_after_change = true
	else:
		editor.perf_after_change = false
	# The measuring switch: what it costs, and off when nobody wants it.
	var perf: Node = RoomPerf.ensure(main.get_tree())
	if DisplayServer.get_name() != "headless":
		var on_ms := 0.0
		var off_ms := 0.0
		# Alternating, in both orders, so drift doesn't count as cost. Only said here: the software renderer's
		# timestamps are not the headset's; the measuring is on only while wanted either way.
		for round in 8:
			for on: bool in ([false, true] if round % 2 == 0 else [true, false]):
				RenderingServer.viewport_set_measure_render_time(main.get_tree().root.get_viewport_rid(), on)
				await _frames(5)
				var t := Time.get_ticks_usec()
				await _frames(40)
				var ms := (Time.get_ticks_usec() - t) / 40000.0
				if on:
					on_ms += ms / 8.0
				else:
					off_ms += ms / 8.0
		RenderingServer.viewport_set_measure_render_time(main.get_tree().root.get_viewport_rid(), perf.measuring())
		print("test_assistant_room: a frame with the measuring on %.2f ms, off %.2f ms (lavapipe)" % [on_ms, off_ms])
		_check("measuring on and off both run (on %.2f ms, off %.2f ms a frame)" % [on_ms, off_ms], on_ms > 0.0
				and off_ms > 0.0)
		print("test_assistant_room: after a change: %s; calibrate follows" % pf.get("summary", ""))
	perf._holds.clear()
	perf._keep_until = 0.0
	await _frames(3)
	_check("measuring stops when nobody wants it", not perf.measuring())
	# Calibration: N copies built by the room builder, measured, removed; the room document untouched.
	var before: Dictionary = editor.current_doc().duplicate(true)
	var c: Dictionary = await RoomPerf.calibrate(main, {"type": "box", "size": [0.6, 1.2, 0.6],
			"material": {"color": "#a08060", "effect": {"name": "rim_glow"}}}, 24, "grid", {"seconds": 0.8})
	_check("calibrate: measured with and without (%s)" % str(c).left(300), not c.has("error")
			and int(c["count"]) == 24 and int(c["loaded"].get("frames", 0)) > 0 and int(c["baseline"].get("frames", 0)) > 0
			and c.has("delta_gpu_ms") and float(c["cost"]) > 0.0)
	print("test_assistant_room: calibrate 24 boxes: %s ms GPU (%s -> %s), cost %s" % [c.get("delta_gpu_ms"),
			c.get("baseline", {}).get("gpu_ms"), c.get("loaded", {}).get("gpu_ms"), c.get("cost")])
	_check("calibrate: the copies are gone and the room document is untouched",
			main.env.find_children("PerfCalibration", "", true, false).is_empty() and editor.current_doc() == before)
	c = await RoomPerf.calibrate(main, {"type": "box", "size": [0.6, 1.2, 0.6]}, 5, "spiral")
	_check("calibrate: a bad arrangement is said", str(c.get("error", "")).contains("grid"))
	var pts: Array = []
	for i in 8:
		pts.append(RoomPerf.place(i, 8, "ring", 1.0, {"radius": 5.0}))
	_check("a ring goes round the seat", pts.all(func(v: Vector3) -> bool: return is_equal_approx(v.length(), 5.0)))


func _seat_checks() -> void:
	var screen := {"center": [0, 1.6, -3.5], "size": [4.0, 2.25], "facing": [0, 0, 1], "curve": 0.3}
	var seats := [{"name": "Front row", "position": [0, 0, -1]}, {"name": "Back", "position": [1.0, 0, 1.5]}]
	var bad := [
		[{"screen": {"center": [0, 1.6, -9], "size": [0.6, 0.34]}}, "too small"],
		[{"screen": {"center": [0, 1.6, -2.5], "size": [12, 6.75]}}, "too large"],
		[{"screen": {"center": [0, 1.6, -3.5], "size": [4, 2.25], "facing": [0, 0, -1]}}, "behind the screen"],
		[{"seats": seats, "default_seat": "Balcony", "screen": screen}, "no seat called Balcony"],
		[{"seats": [{"name": "Car park", "position": [0, 0, -30]}]}, "outside the room"],
		[{"seats": [{"name": "A", "position": [0, 0, 0]}, {"name": "A", "position": [1, 0, 0]}]}, "a second seat"],
		[{"seats": [{"name": "Far side", "position": [4, 0, -2]}], "screen": screen}, "degrees off the screen"]]
	for b: Array in bad:
		var room: Dictionary = {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room"}
		room.merge(b[0])
		var rr: Dictionary = await commands.run("new_room", {"room": room})
		var said := str(rr.get("errors", rr.get("error", "")))
		_check("refused: %s (%s)" % [b[1], said.left(160)], rr.get("ok") != true and said.contains(b[1]))
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"seats": seats, "default_seat": "Back", "screen": screen,
			"parts": [{"name": "Behind", "type": "box", "size": [0.3, 0.3, 0.3], "position": [0, 1.2, 0.3]}]}})
	_check("a room with its seats and screen (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var seat: Node = main.features.seat
	_check("the assistant's room does not move the viewer (seat %d)" % seat.seat, int(seat.seat) == -1)
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	var ss: Dictionary = st.get("seats", {})
	_check("room_state lists the seats (%s)" % str(ss).left(200), (ss.get("list", []) as Array).size() == 2
			and ss["list"][0]["name"] == "Front row" and ss.get("in_use") == null and ss.get("default") == "Back"
			and ss.get("screen_home") is Dictionary)
	var c: Vector3 = (main.env as Node3D).global_transform * Vector3(0, 1.6, -3.5)
	var at: Vector3 = (main.screen as Node3D).global_position
	_check("the screen is at the room's home (%s, want %s; %s m wide)" % [at, c, main.screen_width],
			Vector2(at.x - c.x, at.z - c.z).length() < 0.01 and is_equal_approx(main.screen_width, 4.0)
			and absf(float(main.features.curve.amount) - 0.3) < 0.01)
	var per_seat := (r["result"]["warnings"] as Array).filter(func(w: Dictionary) -> bool:
		return w["kind"] == "behind_viewer")
	_check("occlusion warnings per seat (%s)" % str(per_seat).left(200), per_seat.size() == 1
			and per_seat[0].get("seat") == "Front row"
			and str(per_seat[0]["warning"]).begins_with("from seat Front row"))
	r = await commands.run("suggest_seat", {"seat": "Nowhere"})
	_check("suggesting a seat the room lacks is refused", r.get("ok") != true and str(r.get("error")).contains("Back"))
	r = await commands.run("suggest_seat", {"seat": "Front row", "why": "Closer, for the subtitles."})
	var card: Node = main.ui.card
	_check("a suggestion is a card with the choice (%s)" % r.get("error", ""), r.get("ok") == true
			and card.is_showing() and card.action_point("go") != null and card.action_point("stay") != null)
	_check("and moves nobody by itself", int(seat.seat) == -1)
	await process_frame
	await process_frame
	var how: String = card.click(card.action_point("go"))
	await process_frame
	_check("the viewer took it: in the front row, facing the screen (%s, seat %d, yaw %.1f)" % [how, seat.seat,
			rad_to_deg(main.screen_yaw)], how == "go" and int(seat.seat) == 0 and absf(main.screen_yaw) < 0.01)
	r = await commands.run("suggest_seat", {"seat": "Back"})
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _seconds(0.6)
		_save_shot(await _look(Vector2i(1280, 720), 70.0), "seat-suggestion-card.png")
	how = card.click(card.action_point("stay"))
	_check("or stays (%s)" % how, how == "stay" and int(seat.seat) == 0)
	if DisplayServer.get_name() != "headless":
		var snap: RoomSnapshot = RoomSnapshot.new()
		root.add_child(snap)
		var s: Dictionary = await snap.capture("seat:Back", Vector2i(640, 360), 90.0)
		var img := Image.new()
		_check("a snapshot from a named seat", s.has("png") and img.load_png_from_buffer(s["png"]) == OK)
		_save_shot(img, "seat-back-snapshot.png")
		var eye: Vector3 = snap._camera.global_position
		var want: Vector3 = (main.env as Node3D).global_transform * Vector3(1.0, float(main.eye_height), 1.5)
		_check("taken at that seat (%s, want %s)" % [eye, want], eye.distance_to(want) < 0.01)
		snap.queue_free()
	# The assistant moves the seat the viewer is in: they stay exactly where they are; the seat is marked moved.
	var env_before: Transform3D = (main.env as Node3D).transform
	r = await commands.run("room_apply", {"room": {"schema": 1, "seats": [
			{"name": "Front row", "position": [0, 0, -1.6]}, {"name": "Back", "position": [1.0, 0, 1.5]}]}})
	var v: Dictionary = r.get("result", {}).get("viewer", {})
	_check("moving the viewer's seat moves nobody (%s, seat %d, moved %s)" % [v, seat.seat, seat.moved],
			r.get("ok") == true and (main.env as Node3D).transform.is_equal_approx(env_before) and int(seat.seat) == 0
			and seat.moved and v.get("seat_in_use") == "Front row" and v.get("moved") == true)
	st = (await commands.run("room_state", {}))["result"]
	_check("room_state says the seat moved", st["seats"].get("in_use") == "Front row"
			and st["seats"].get("moved") == true)
	seat.go_to_seat(0)
	_check("choosing it goes to its new place", not seat.moved and (main.env as Node3D).transform.is_equal_approx(
			seat.seat_transform(0).affine_inverse()))
	# Renamed (or removed): still where they were; the seat they had is gone.
	env_before = (main.env as Node3D).transform
	r = await commands.run("room_apply", {"room": {"schema": 1, "seats": [
			{"name": "Stalls", "position": [0, 0, -1.6]}, {"name": "Back", "position": [1.0, 0, 1.5]}]}})
	st = (await commands.run("room_state", {}))["result"]
	_check("renaming it moves nobody (%s)" % str(st["seats"]).left(160), (main.env as Node3D).transform.is_equal_approx(
			env_before) and int(seat.seat) == -1 and seat.moved and st["seats"].get("was") == "Front row")
	seat.choose_seat(0)
	# The screen: moved by the viewer this session, an assistant's new screen leaves it there; else it goes home.
	main.screen_yaw = 0.3
	main.set_screen(main.screen_width, main.screen_distance, main.screen_height_offset)
	r = await commands.run("room_apply", {"room": {"schema": 1,
			"screen": {"center": [0, 1.7, -3.8], "size": [4.4, 2.5]}}})
	_check("a new screen while the viewer moved theirs: kept (%s, yaw %.2f)" % [r.get("result", {}).get("screen"),
			main.screen_yaw], r.get("ok") == true and is_equal_approx(main.screen_yaw, 0.3)
			and str(r["result"].get("screen")).begins_with("kept"))
	seat.home_screen()
	r = await commands.run("room_apply", {"room": {"schema": 1,
			"screen": {"center": [0, 1.6, -3.5], "size": [4.0, 2.25], "curve": 0.3}}})
	_check("and at home it goes to the new home (%s, %.1f m)" % [r.get("result", {}).get("screen"), main.screen_width],
			str(r.get("result", {}).get("screen")).begins_with("shown") and is_equal_approx(main.screen_width, 4.0))
	r = await commands.run("room_apply", {"room": {"schema": 1, "seats": seats}})
	_check("the seats back (%s)" % r.get("error", ""), r.get("ok") == true)
	main.reset_room()
	_check("Reset room: the room's default seat and its screen (seat %d, %s)" % [seat.seat, main.env_id],
			int(seat.seat) == 1 and str(main.env_id) == "recipe:" + BOUNDS_NAME
			and is_equal_approx(main.screen_width, 4.0))
	# The room's screen stays where the room puts it, facing its own way, from any seat.
	var faces := func() -> float:
		var want: Vector3 = (main.env as Node3D).global_basis * Vector3.BACK
		return rad_to_deg((main.screen as Node3D).global_basis.z.angle_to(want))
	var spot := func() -> float:
		return (main.screen as Node3D).global_position.distance_to((main.env as Node3D).global_transform
				* Vector3(0, 1.6 - 1.2 + float(main.eye_height), -3.5))
	_check("from the back seat the screen faces its own way (%.1f degrees off), at its place (%.3f m)"
			% [faces.call(), spot.call()], faces.call() < 0.5 and spot.call() < 0.01)
	seat.choose_seat(0)
	_check("and from the front row too (%.1f, %.3f)" % [faces.call(), spot.call()], faces.call() < 0.5
			and spot.call() < 0.01)
	seat.choose_seat(1)
	main.recenter_screen_to_gaze()
	var to_viewer: Vector3 = -(main.screen as Node3D).global_position
	to_viewer.y = 0.0
	_check("the viewer's recentre turns it to them (%.1f degrees)" % rad_to_deg((main.screen as Node3D).global_basis.z
			.angle_to(to_viewer)), is_nan(main.screen_turn) and (main.screen as Node3D).global_basis.z.angle_to(
			to_viewer) < 0.01)
	main.reset_room()
	_check("and Reset room puts it back (%.1f)" % faces.call(), faces.call() < 0.5 and spot.call() < 0.01)
	# Opened by the viewer (from the rooms list), with no seat remembered: the default seat.
	main.settings.set_value("seat_names", main.env_id, null)
	main.settings.set_value("seats", main.env_id, null)
	main.set_environment("recipe:" + BOUNDS_NAME)
	await process_frame
	_check("opened by the viewer: the default seat (%d)" % seat.seat, int(seat.seat) == 1)
	seat.choose_seat(-1)


## The see-through things in a snapshot, the way the headset takes one: one long-lived snapshot node (as the service
## keeps), from the seat at fov 110, several captures and a clip in a row. Each part's pixels must change when it
## is hidden.
func _transparent_snapshot_checks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "void",
			"light": {"ambient": 0.25, "screen_glow": 0.6}, "sky": {"color": "#101828", "stars": {}},
			"atmosphere": {"fog": {"density": 0.3, "height": 0.4}}, "parts": [
				{"name": "Sign", "type": "text", "text": "HELLO", "size": [0.25], "position": [-1.1, 1.5, -2.5],
					"text_options": {"color": "#ffd080", "background": "#000000a0"}},
				{"name": "Bare", "type": "text", "text": "WORLD", "size": [0.25], "position": [-1.1, 0.9, -2.5],
					"text_options": {"color": "#ffffff"}},
				{"name": "Holo", "type": "box", "size": [0.5, 0.5, 0.5], "position": [0.0, 1.2, -2.5],
					"material": {"color": "#66ddff", "effect": {"name": "hologram"}}},
				{"name": "Flies", "type": "particles", "size": [0.8, 0.8, 0.6], "position": [1.1, 1.2, -2.5],
					"particles": {"preset": "fireflies", "rate": 20}}]}})
	_check("a room of see-through things (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var snap: RoomSnapshot = RoomSnapshot.new()
	root.add_child(snap)
	await _seconds(2.0)
	var names := ["Sign", "Bare", "Holo", "Flies"]
	for round_i in 2:
		var with: Dictionary = await snap.capture("seat", Vector2i(640, 360), 110.0)
		var at := {}
		for n: String in names:
			var node := main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]) as Node3D
			at[n] = Vector2i(snap._camera.unproject_position(node.global_position))
		var without := {}
		for n: String in names:
			main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]).visible = false
		without = await snap.capture("seat", Vector2i(640, 360), 110.0)
		for n: String in names:
			main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]).visible = true
		var a := Image.new()
		var b := Image.new()
		var ok := with.has("png") and without.has("png") and a.load_png_from_buffer(with["png"]) == OK \
				and b.load_png_from_buffer(without["png"]) == OK
		if round_i == 0 and ok:
			_save_shot(a, "snapshot-see-through-seat.png")
		for n: String in names:
			var diff := _window_diff(a, b, at[n], 12) if ok else 0.0
			_check("snapshot %d from the seat shows %s (%.3f)" % [round_i + 1, n, diff], diff > 0.02)
	# The clip the same way: its first frame with and without them.
	var clips: Array[Image] = []
	for shown in [true, false]:
		for n: String in names:
			main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]).visible = shown
		var clip: Dictionary = await snap.capture_clip("seat", Vector2i(320, 180), 110.0, 0.5, 2, "sheet")
		var sheet := Image.new()
		clips.append(sheet if clip.has("png") and sheet.load_png_from_buffer(clip["png"]) == OK else null)
	for n: String in names:
		main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]).visible = true
	if clips[0] != null:
		_save_shot(clips[0], "snapshot-see-through-clip.png")
	for n: String in names:
		var node := main.env.get_node("%s/%s" % [AssistantRoom.LAYER, n]) as Node3D
		var p := Vector2i(snap._camera.unproject_position(node.global_position))
		var diff := _window_diff(clips[0], clips[1], p, 6) if clips[0] != null and clips[1] != null else 0.0
		_check("the clip from the seat shows %s (%.3f)" % [n, diff], diff > 0.02)
	snap.queue_free()


## Mean absolute difference of two images over a square window around p.
func _window_diff(a: Image, b: Image, p: Vector2i, half: int) -> float:
	var sum := 0.0
	var count := 0
	for y in range(p.y - half, p.y + half + 1):
		for x in range(p.x - half, p.x + half + 1):
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height():
				continue
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			count += 1
	return sum / maxf(count, 1)


func _sky_checks() -> void:
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "void",
			"light": {"ambient": 0.15, "screen_glow": 0.5},
			"sky": {"color": "#03060f", "stars": {"density": 0.7}, "clouds": {"cover": 0.45, "color": "#4a5368"}},
			"atmosphere": {"fog": {"density": 0.6, "height": 0.6}}, "parts": []}})
	_check("a sky with stars and clouds, fog (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var sky := main.env.get_node_or_null("AssistantLayer/Sky") as MeshInstance3D
	var code: String = (sky.material_override as ShaderMaterial).shader.code if sky != null else ""
	_check("the sky draws stars and clouds", code.contains("#define STARS") and code.contains("#define CLOUDS"))
	var fog: Node = main.env.get_node_or_null("AssistantLayer/Fog")
	_check("the fog is %d soft layers, low to its height" % RoomSchema.FOG_LAYERS, fog != null
			and fog.get_child_count() == RoomSchema.FOG_LAYERS
			and is_equal_approx((fog.get_child(RoomSchema.FOG_LAYERS - 1) as Node3D).position.y, 0.6))
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	var want := RoomSchema.COSTS["sky_stars"] + RoomSchema.COSTS["sky_clouds"] \
			+ RoomSchema.COSTS["fog_layer"] * RoomSchema.FOG_LAYERS
	_check("sky and fog cost (%s of %s)" % [st["used"]["cost"], want], float(st["used"]["cost"]) >= want - 0.05)
	if DisplayServer.get_name() != "headless":
		await _seconds(0.5)
		_save_shot(await _look(Vector2i(1280, 720), 60.0), "sky-stars-clouds-fog.png")
	r = await commands.run("room_apply", {"room": {"schema": 1, "sky": {"stars": {"twinkle": 0.8},
			"clouds": {"rain": 1}}, "atmosphere": {"smoke": {}}}})
	var text := str(r.get("errors", []))
	_check("the sky's bounds are enforced (%s)" % text, r.get("errors", []).size() == 3
			and text.contains("no larger brightness swings") and text.contains("$.atmosphere.smoke"))
	# Fog in a room with walls, at the seat.
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"light": {"ambient": 0.3, "screen_glow": 0.8}, "atmosphere": {"fog": {"density": 0.8, "height": 0.5}},
			"parts": []}})
	_check("fog in a room (%s)" % r.get("error", ""), r.get("ok") == true)
	if DisplayServer.get_name() != "headless":
		await _seconds(0.5)
		_save_shot(await _look(Vector2i(1280, 720), 60.0), "fog-dim-room.png")


func _react_checks() -> void:
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"light": {"ambient": 0.25, "screen_glow": 0.8}, "parts": [
				{"name": "Shimmer", "type": "box", "size": [1.0, 0.7, 0.02], "position": [-0.6, 1.4, -2.2],
					"material": {"color": "#6fb0ff"}, "widget": "screen_glow",
					"widget_options": {"react": "brightness", "style": "shimmer", "amount": 0.4, "strength": 0.6}},
				{"name": "Ripple", "type": "box", "size": [1.0, 0.7, 0.02], "position": [0.6, 1.4, -2.2],
					"material": {"color": "#ffb070"}, "widget": "screen_glow",
					"widget_options": {"react": "loudness", "style": "ripple", "amount": 0.4, "strength": 0.6}}]}})
	_check("screen-reactive glows (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var react: Node = main.env.get_node_or_null("React")
	_check("the room reacts through one node", react != null and react.count() == 2)
	var shimmer := _material_of("Shimmer")
	var ripple := _material_of("Ripple")
	_check("each glow its own variant", shimmer != null and shimmer.shader.code.contains("#define REACT_BRIGHTNESS")
			and shimmer.shader.code.contains("#define STYLE_SHIMMER") and ripple != null
			and ripple.shader.code.contains("#define REACT_LOUDNESS")
			and ripple.shader.code.contains("#define STYLE_RIPPLE"))
	_check("brightness keeps the picture's copy fresh, even with the bias light off",
			main.features.bias._requested())
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("reacting costs (%s)" % st["used"]["cost"],
			float(st["used"]["cost"]) >= 2 * (RoomSchema.COSTS["part"] + RoomSchema.COSTS["glow_react"]))
	# The loudness, through the smoothing: a 10 Hz beat is all but gone, a steady loud scene comes through, and no
	# frame moves the level further than a sine over the whole range at 3 Hz would.
	var rr: Node = (load("res://scripts/assistant/room_react.gd") as GDScript).new()
	var dt := 1.0 / 72.0
	var steepest := 0.0
	var prev := 0.0
	var lo := 1.0
	var hi := 0.0
	for i in 72 * 3:
		var lv: float = rr.step(1.0 if (i / 4) % 2 == 0 else 0.01, dt)
		steepest = maxf(steepest, absf(lv - prev))
		prev = lv
		if i >= 72 * 2:
			lo = minf(lo, lv)
			hi = maxf(hi, lv)
	_check("a 10 Hz beat barely moves the glow (%.3f)" % (hi - lo), hi - lo < 0.1)
	for i in 72 * 2:
		prev = rr.step(0.001, dt)
	for i in 72:
		var lv: float = rr.step(0.5, dt)
		steepest = maxf(steepest, absf(lv - prev))
		prev = lv
	_check("a loud scene after a quiet one comes through (%.2f)" % prev, prev > 0.5)
	_check("never steeper than the ceiling (%.3f a frame)" % steepest, steepest <= PI * RoomSchema.MAX_HZ * dt + 1e-6)
	rr.free()
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [
			{"name": "a", "type": "box", "size": [1, 1, 1], "widget": "screen_glow",
				"widget_options": {"react": "loudness", "amount": 0.7}},
			{"name": "b", "type": "box", "size": [1, 1, 1], "widget": "screen_glow",
				"widget_options": {"react": "music"}}]}})
	_check("react's bounds are enforced (%s)" % str(r.get("errors", "")),r.get("errors", []).size() == 2
			and str(r.get("errors")).contains("no larger brightness swings"))
	if DisplayServer.get_name() != "headless" and react != null:
		# No film plays here: hold both at full level to see the patterns.
		react.set_process(false)
		ripple.set_shader_parameter("react_level", 1.0)
		var flat := shimmer.duplicate() as ShaderMaterial
		flat.shader = Shader.new()
		flat.shader.code = shimmer.shader.code.replace("#define REACT_BRIGHTNESS", "#define REACT_LOUDNESS")
		flat.set_shader_parameter("react_level", 1.0)
		(main.env.get_node("%s/Shimmer/Mesh" % AssistantRoom.LAYER) as MeshInstance3D).material_override = flat
		await _seconds(0.5)
		_save_shot(await _look(Vector2i(1280, 720), 36.0), "screen-glow-react.png")


func _effect_checks() -> void:
	var fx := [["rim_glow", "sphere", {}], ["hologram", "box", {}], ["glass", "sphere", {}], ["metal", "sphere", {}],
			["toon_outline", "box", {}], ["dissolve", "sphere", {"amount": 0.45}], ["pulse", "sphere", {}],
			["flicker", "sphere", {}]]
	var parts: Array = []
	for i in fx.size():
		var e: Dictionary = {"name": fx[i][0]}
		e.merge(fx[i][2])
		var size: Array = [0.36] if fx[i][1] == "sphere" else [0.32, 0.32, 0.32]
		parts.append({"name": "FX_" + str(fx[i][0]), "type": fx[i][1], "size": size,
				"position": [(i % 4) * 0.55 - 0.82, 1.55 - (i / 4) * 0.55, -2.2],
				"rotation": [20, 30, 0] if fx[i][1] == "box" else [0, 0, 0],
				"material": {"color": {"glass": "#a8d8ff", "metal": "#d4a84b", "toon_outline": "#4a90d9"}.get(fx[i][0],
						"#8a6e4b"), "effect": e}})
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"light": {"ambient": 0.25, "screen_glow": 0.8}, "parts": parts}})
	_check("eight effects (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var all_ok := true
	for f: Array in fx:
		var m := _material_of("FX_" + str(f[0]))
		var define := "#define FX_%s" % ("TOON" if f[0] == "toon_outline" else str(f[0]).to_upper())
		if m == null or not m.shader.code.contains(define):
			all_ok = false
	_check("each part has its effect's shader", all_ok)
	var toon := _material_of("FX_toon_outline")
	_check("toon_outline draws an outline pass", toon != null and toon.next_pass is ShaderMaterial)
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("effects cost (%s)" % st["used"]["cost"], float(st["used"]["cost"]) >= 8 * RoomSchema.COSTS["part"] + 8 + 2 + 1)
	_check("room_state lists the effects and the ceiling", st.get("effects", []).size()
			== RoomSchema.EffectLibrary.schema_effects(false).size()
			and st.get("photosensitivity", {}).get("max_hz") == RoomSchema.MAX_HZ)
	# screen_glow follows the film through the bias light, low-passed: its cut-off (1 / 2 pi tau) is under 3 Hz.
	var tau: float = (load("res://scripts/env/bias_light.gd") as GDScript).get_script_constant_map()["BLEND_SECONDS"]
	_check("screen_glow changes slower than the ceiling (%.2f Hz)" % (1.0 / (TAU * tau)),
			1.0 / (TAU * tau) <= RoomSchema.MAX_HZ)
	if DisplayServer.get_name() != "headless":
		await _seconds(1.0)
		_save_shot(await _look(), "effects.png")
		_save_shot(await _look(Vector2i(1280, 720), 36.0), "effects-headset-scale.png")
		# The photosensitivity ceiling, seen: the candle's brightness over 2 s at 12 frames a second wanders, never
		# jumps (its default: 1.5 Hz, swing 0.25).
		var snap: RoomSnapshot = RoomSnapshot.new()
		root.add_child(snap)
		var c: Dictionary = await snap.capture_clip("viewer", Vector2i(320, 180), 60.0, 2.0, 12, "sheet")
		# The flicker sphere (bottom row, last): its centre in each frame, through the clip's own camera.
		var at := Vector2i(snap._camera.unproject_position(Vector3(3 * 0.55 - 0.82, 1.0, -2.2)))
		snap.queue_free()
		var sheet := Image.new()
		if c.has("png") and sheet.load_png_from_buffer(c["png"]) == OK:
			_save_shot(sheet, "effects-clip-sheet.png")
			var cols := int(c["columns"])
			var lum: Array = []
			for i in int(c["frames"]):
				var p := sheet.get_pixelv(at + Vector2i((i % cols) * 322, (i / cols) * (180 + 2)))
				lum.append(p.get_luminance())
			var mean: float = lum.reduce(func(s: float, x: float) -> float: return s + x, 0.0) / lum.size()
			var biggest := 0.0
			for i in range(1, lum.size()):
				biggest = maxf(biggest, absf(lum[i] - lum[i - 1]))
			_check("the candle wanders (%.3f..%.3f) but never jumps (largest step %.3f of %.3f)" % [lum.min(),
					lum.max(), biggest, mean], lum.max() - lum.min() > 0.005 and biggest < 0.25 * mean)
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [
			{"name": "a", "type": "box", "size": [1, 1, 1], "material": {"effect": {"name": "pulse", "rate": 5}}},
			{"name": "b", "type": "box", "size": [1, 1, 1], "material": {"effect": {"name": "flicker", "swing": 0.9}}},
			{"name": "c", "type": "box", "size": [1, 1, 1], "material": {"effect": {"name": "strobe"}}}]}})
	var errs: Array = r.get("errors", [])
	var text := str(errs)
	_check("the photosensitivity ceiling is enforced (%s)" % text, errs.size() == 3 and text.contains("3 times a second")
			and text.contains("no larger brightness swings") and text.contains("$.parts[2].material.effect.name"))


func _emitter(name: String, preset: String, x: float, extra := {}) -> Dictionary:
	var d := {"preset": preset}
	d.merge(extra)
	return {"name": name, "type": "particles", "size": [1.2, 2.0, 1.0], "position": [x, 1.2, -2.6], "particles": d}


func _particle_checks() -> void:
	var r: Dictionary = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room",
			"parts": [_emitter("Snow", "snow", -1.4), _emitter("Rain", "rain", 0.0),
			_emitter("Leaves", "leaves", 1.4, {"rate": 12})]}})
	_check("snow, rain, leaves (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var snow := main.env.get_node_or_null("AssistantLayer/Snow/Particles") as GPUParticles3D
	_check("GPU particles, as many as rate x life (%s)" % (snow.amount if snow else -1), snow != null
			and snow.amount == ceili(40.0 * 2.0 / 0.3) and snow.preprocess > 0.0)
	var pm := snow.process_material as ParticleProcessMaterial if snow else null
	var quad := snow.draw_pass_1 as QuadMesh if snow else null
	var sm := quad.material as StandardMaterial3D if quad else null
	_check("soft, varied, drifting: a mipmapped round sprite, size and alpha over life, turbulence", pm != null
			and pm.turbulence_enabled and pm.scale_min < pm.scale_max and pm.color_ramp != null
			and pm.scale_curve != null and sm != null and sm.albedo_texture != null
			and sm.albedo_texture.get_image().has_mipmaps())
	var st: Dictionary = (await commands.run("room_state", {}))["result"]
	_check("room_state counts emitters and particles (%s)" % st["used"], int(st["used"]["emitters"]) == 3
			and int(st["used"]["particles"]) > 300 and float(st["used"]["cost"]) > 3.0)
	await _seconds(6.0)
	_save_shot(await _look(), "particles-snow-rain-leaves.png")
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "void",
			"parts": [_emitter("Embers", "embers", -1.4), _emitter("Fireflies", "fireflies", 0.0, {"rate": 12}),
			_emitter("Dust", "dust", 1.4)]}})
	_check("embers, fireflies, dust (%s %s)" % [r.get("error", ""), r.get("errors", "")], r.get("ok") == true)
	var embers := main.env.get_node_or_null("AssistantLayer/Embers/Particles") as GPUParticles3D
	_check("embers glow additively", embers != null and ((embers.draw_pass_1 as QuadMesh).material as
			StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD)
	await _seconds(6.0)
	_save_shot(await _look(), "particles-embers-fireflies-dust.png")
	# At about the headset's pixel density (20 pixels a degree): how a firefly 2.6 m away really looks.
	_save_shot(await _look(Vector2i(1280, 720), 36.0), "particles-glow-headset-scale.png")
	var many: Array = []
	for i in 7:
		many.append(_emitter("E%d" % i, "dust", i * 0.5 - 1.5))
	r = await commands.run("new_room", {"room": {"schema": 1, "name": BOUNDS_NAME, "base": "dim_room", "parts": many}})
	_check("at most 6 emitters (%s)" % r.get("error", ""), r.get("ok") == false and r.get("limit") == "emitters")
	r = await commands.run("room_apply", {"room": {"schema": 1, "parts": [
			_emitter("a", "snow", 0, {"rate": 1000}), _emitter("b", "volcano", 0),
			{"name": "c", "type": "particles", "size": [40, 1, 1], "particles": {"preset": "dust"}},
			_emitter("d", "dust", 0, {"size": 2})]}})
	var paths: Array = r.get("errors", []).map(func(e: Dictionary) -> String: return e["path"])
	_check("particle bounds are enforced (%s)" % [paths], paths.has("$.parts[0].particles.rate")
			and paths.has("$.parts[1].particles.preset") and paths.has("$.parts[2].size")
			and paths.has("$.parts[3].particles.size"))


func _vec3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A small picture of one colour, as base64 PNG.
func _png_b64(c: Color) -> String:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	img.fill(c)
	return Marshalls.raw_to_base64(img.save_png_to_buffer())


func _material_of(part: String) -> ShaderMaterial:
	var mi := _mesh_of(part)
	if mi == null:
		return null
	return (mi.material_override if mi.material_override != null else mi.get_active_material(0)) as ShaderMaterial


## A part's mesh: a shape's Mesh, or the first mesh of a placed object's model (a picture object: room_keep.gd).
func _mesh_of(part: String) -> MeshInstance3D:
	var node: Node = main.env.get_node_or_null("%s/%s" % [AssistantRoom.LAYER, part])
	if node == null:
		return null
	if node.has_node("Mesh"):
		return node.get_node("Mesh") as MeshInstance3D
	var found := node.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null


func _sphere(radial: int, rings: int) -> Node3D:
	var root_node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var s := SphereMesh.new()
	s.radial_segments = radial
	s.rings = rings
	mi.mesh = s
	root_node.add_child(mi)
	return root_node


func _glb_of(node: Node3D) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(node, state)
	node.free()
	return doc.generate_buffer(state)


## The .glb with its JSON chunk changed by f(json).
func _with_json(glb: PackedByteArray, f: Callable) -> PackedByteArray:
	var json_len := glb.decode_u32(12)
	var j := JSON.new()
	j.parse(glb.slice(20, 20 + json_len).get_string_from_utf8())
	var g: Dictionary = j.data
	f.call(g)
	var text := JSON.stringify(g).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(32)
	var rest := glb.slice(20 + json_len)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + text.size() + rest.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	out.append_array(rest)
	return out


func _cleanup() -> void:
	for name in [ROOM_NAME, "Assistant room", BOUNDS_NAME]:
		var dir := AssistantRoom.files_dir(name)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
			DirAccess.remove_absolute(dir)
		DirAccess.remove_absolute(AssistantRoom.json_path(name))
	# The models and pictures these rooms kept in the object library (room_keep.gd), once the rooms are gone.
	for m: Dictionary in ObjectLibrary.list("", "user"):
		if not (m["id"] in _objects_before):
			ObjectLibrary.delete(m["id"])
			ObjectLibrary.purge(m["id"])


## Real time passing (with a renderer, so particles and motion settle before a picture); headless: no wait.
func _seconds(s: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
