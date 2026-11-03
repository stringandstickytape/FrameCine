extends RefCounted

## Screenshots over the dev link (idea #16): the `screenshot` command. Each eye as the user sees it, and a
## third-person free camera, at reduced size, so the PC (or an AI session) can see what it changed. Rendering is the
## snapshot facility's (scripts/dev/snapshots.gd, render_view()): its own offscreen SubViewport, which renders only
## while a picture is taken. The PNGs are saved on the headset under user://dev_shots/, sent inline in the reply
## (the listener writes them to its shots/ folder) and announced with a `screenshot` event.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const Snapshots := preload("res://scripts/dev/snapshots.gd")

const VIEWS: Array[String] = ["left", "right", "third"]
const OUT_DIR := "user://dev_shots"
## Half the distance between the eyes, for the desktop (flat camera) stand-in of the eye poses.
const HALF_IPD := 0.032
## Third-person camera default: this far behind and above the head, looking at the screen.
const THIRD_BACK := 2.5
const THIRD_UP := 1.0
const MAX_SIZE := 2048

## scripts/dev/dev_host.gd
var host: Node
var _snapshots: Snapshots
var _count := 0


func register_all() -> void:
	DevCommands.register("screenshot", _cmd_screenshot, {
		"description": "Renders each eye's view and a third-person free camera at reduced size, saves the PNGs on the "
				+ "headset and sends them inline (the listener saves them to its shots/ folder).",
		"params": [
			{"name": "views", "type": "array", "default": VIEWS,
					"description": "any of left, right, third"},
			{"name": "size", "type": "int", "default": 512,
					"description": "eye pictures size x size; third is size wide, 16:9"},
			{"name": "position", "type": "any", "default": null,
					"description": "third camera position [x, y, z] (default behind and above the head)"},
			{"name": "target", "type": "any", "default": null,
					"description": "third camera looks at [x, y, z] (default the screen)"},
			{"name": "fov", "type": "float", "default": 70.0, "description": "third camera vertical field of view"},
			{"name": "inline", "type": "bool", "default": true, "description": "send the PNG data in the reply"}],
		"returns": "{images: [{view, path, width, height, png_b64}]}"})


func _ensure_snapshots() -> Snapshots:
	if _snapshots == null or not is_instance_valid(_snapshots) or _snapshots.main != host.main:
		if _snapshots != null and is_instance_valid(_snapshots):
			_snapshots.queue_free()
		_snapshots = Snapshots.new()
		_snapshots.name = "DevShots"
		_snapshots.main = host.main
		_snapshots.out_dir = ProjectSettings.globalize_path(OUT_DIR)
		_snapshots.announce = false
		host.add_child(_snapshots)
	return _snapshots


func _cmd_screenshot(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var main: Node = host.main
	if main == null:
		return ctx.fail("no main scene")
	if DisplayServer.get_name() == "headless":
		return ctx.fail("nothing renders in --headless")
	var views: Array = args["views"]
	for v: Variant in views:
		if not (str(v) in VIEWS):
			return ctx.fail("views: %s is not one of %s" % [v, VIEWS])
	var size := clampi(args["size"], 64, MAX_SIZE)
	var snaps := _ensure_snapshots()
	_count += 1
	var images: Array = []
	for v: Variant in views:
		var view := str(v)
		var pic_size := Vector2i(size, size)
		var xform: Transform3D
		var fov: float
		var eye := -1
		if view == "third":
			pic_size = Vector2i(size, maxi(roundi(size * 9.0 / 16.0), 16))
			var pos: Variant = DevCommands.coerce(args["position"], "vector3")[0] if args["position"] != null else null
			var target: Variant = DevCommands.coerce(args["target"], "vector3")[0] if args["target"] != null else null
			if args["position"] != null and pos == null:
				return ctx.fail("position: expected [x, y, z]")
			if args["target"] != null and target == null:
				return ctx.fail("target: expected [x, y, z]")
			xform = _third_pose(main, pos, target)
			fov = clampf(args["fov"], 10.0, 150.0)
		else:
			eye = 0 if view == "left" else 1
			var pose := _eye_pose(main, eye)
			xform = pose[0]
			fov = pose[1]
		var file_name := "shot_%d_%s" % [_count, view]
		var path: String = await snaps.render_view(file_name, pic_size, xform, fov, eye)
		if not FileAccess.file_exists(path):
			return ctx.fail("could not render or save %s" % path)
		var entry := {"view": view, "path": path, "width": pic_size.x, "height": pic_size.y,
				"camera": DevCommands.to_json(xform.origin), "fov": snappedf(fov, 0.1)}
		if args["inline"]:
			entry["png_b64"] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(path))
		images.append(entry)
	if host.link != null:
		var announced: Array = []
		for e: Dictionary in images:
			var a := e.duplicate()
			a.erase("png_b64")
			announced.append(a)
		host.link.send_event("screenshot", {"images": announced})
	return {"images": images}


## [world transform, vertical fov] of one eye: the runtime's eye pose in XR; the flat camera moved by half the eye
## distance on a desktop.
static func _eye_pose(main: Node, eye: int) -> Array:
	var cam: Camera3D = main.camera
	var xr := XRServer.primary_interface
	if main.use_xr and xr != null and xr.is_initialized():
		var origin: Transform3D = main.xr_origin.global_transform
		var t := xr.get_transform_for_view(eye, origin)
		var proj := xr.get_projection_for_view(eye, 1.0, 0.05, 100.0)
		# A square picture: the projection's horizontal field of view stands for both.
		return [t, proj.get_fov()]
	var side := -1.0 if eye == 0 else 1.0
	var t2 := cam.global_transform
	t2.origin += t2.basis.x * HALF_IPD * side
	return [t2, cam.fov]


## The third-person camera: at `pos` (default behind and above the head, along the head's yaw) looking at `target`
## (default the screen's centre, or 3 m ahead of the head for 180 / 360).
static func _third_pose(main: Node, pos: Variant, target: Variant) -> Transform3D:
	var head: Transform3D = (main.camera as Camera3D).global_transform
	var fwd := -head.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
	var p: Vector3 = pos if pos != null else head.origin - fwd * THIRD_BACK + Vector3.UP * THIRD_UP
	var t: Vector3
	if target != null:
		t = target
	elif main.mode.is_spherical():
		t = head.origin + fwd * 3.0
	else:
		t = (main.screen as Node3D).global_position
	if p.is_equal_approx(t):
		t = p + Vector3.FORWARD
	var up := Vector3.UP if absf((t - p).normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
	return Transform3D(Basis.looking_at(t - p, up), p)
