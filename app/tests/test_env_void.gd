extends SceneTree

## The Void as a version 4 document (environments/void.env.json; docs/environments.md, "The Void") in the real main
## scene: built by the mirror floor, black (nothing above the floor), the floor at y 0 under the reflection, which is
## on by default; a ripple where the head moves faster than a walk's start, none when it stays still, its strength the
## room's Ripple setting (0: none); and, as the base of an assistant's room, no second floor.
## godot --headless --xr-mode off --path app --script res://tests/test_env_void.gd

const EnvRoom := preload("res://scripts/env/env_room.gd")
const MirrorFloor := preload("res://scripts/env/systems/mirror_floor.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(5)
	main.set_environment("void")
	main.open_path("stub://flat_mono")
	await _frames(5)
	var env: Node3D = main.env
	_check("the Void is a document's room", env.get_script() == EnvRoom and str(env.document).ends_with("void.env.json"))
	var floor_sys: Node = env.host.system("mirror_floor")
	_check("built by the mirror floor", floor_sys != null and floor_sys.get_script() == MirrorFloor)
	var floor := env.get_node_or_null("MirrorFloor") as MeshInstance3D
	_check("a black floor at y 0, wide", floor != null and floor.visible and is_equal_approx(floor.position.y, 0.0)
			and (floor.mesh as PlaneMesh).size.x >= 40.0)
	var albedo: Color = floor.material_override.get_shader_parameter("albedo")
	_check("mirror-black (%s)" % albedo, albedo.get_luminance() < 0.02)
	var others := env.find_children("*", "GeometryInstance3D", true, false).filter(func(g: Node) -> bool:
			return g != floor)
	_check("nothing else drawn: a black sky", others.is_empty())
	_check("the film's reflection on by default", main.features.reflection.available()
			and main.features.reflection.enabled and main.features.reflection.is_showing())
	_check("the Ripple setting in This room (%s)" % [main.features.room_settings.declarations().map(
			func(d: Dictionary) -> String: return d["name"])], main.features.room_settings.declarations().any(
			func(d: Dictionary) -> bool: return d["name"] == "ripple"))
	# The ripple: the head held still, then moved.
	floor_sys.head_override = Vector3(0, 1.2, 0)
	await _frames(10)
	_check("a still head: no ripple", floor_sys.rings().is_empty())
	var started: int = floor_sys.started
	for i in 10:
		floor_sys.head_override = Vector3(0.02 * (i + 1), 1.2, 0.0)
		await process_frame
	_check("the head moves: a ring starts under it (%s)" % [floor_sys.rings()], floor_sys.started > started
			and not floor_sys.rings().is_empty())
	var ring: Array = floor_sys.rings()[0]
	_check("at the default strength, half (%.2f)" % ring[2], is_equal_approx(float(ring[2]), 0.5))
	var ages: PackedFloat32Array = floor_sys.material().get_shader_parameter("ripple_age")
	_check("the shader has it", ages.size() == MirrorFloor.RIPPLES)
	main.features.room_settings.set_value("ripple", 1.0)
	await _frames(2)
	_check("the room's setting: full strength (%.2f)" % float(floor_sys.rings()[0][2]),
			is_equal_approx(float(floor_sys.rings()[0][2]), 1.0) if not floor_sys.rings().is_empty() else false)
	await create_timer(3.0).timeout
	_check("it fades out within its life", floor_sys.rings().is_empty())
	main.features.room_settings.set_value("ripple", 0.0)
	var before: int = floor_sys.started
	for i in 10:
		floor_sys.head_override = Vector3(0.5 - 0.03 * i, 1.2, 0.0)
		await process_frame
	_check("ripple 0: none", floor_sys.started == before)
	main.features.room_settings.reset()
	# Under an assistant's room: the room's own floor, no second one.
	var holder := Node3D.new()
	holder.set("name", "Holder")
	holder.set_script(load("res://tests/fixtures/assistant_like.gd"))
	var base: Node3D = (load("res://environments/void.tscn") as PackedScene).instantiate()
	holder.add_child(base)
	root.add_child(holder)
	await _frames(2)
	_check("the Void as a base: no floor of its own", not (base.get_node("MirrorFloor") as MeshInstance3D).visible)
	holder.queue_free()
	main.queue_free()
	await _frames(2)
	print("test_env_void: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
