extends Node

## In-headset snapshots (--snapshot-dir=PATH): renders what the user sees and close-ups of both controllers to PNG, so
## the label layout can be checked off the headset. Taken on left bumper held + A, on F12 (desktop), and every
## --snapshot-every=S seconds. One offscreen SubViewport shares the world; it renders only while a snapshot is taken.
## Files, n counting up from the highest already in the folder:
##   head_<n>.png         1920x1080 from the XR camera's (flat camera's) current pose
##   left_<n>.png, right_<n>.png              1024x1024, 25 cm above the face centre looking down at the face, the
##                                            aim direction up in the image
##   left_side_<n>.png, right_side_<n>.png    1024x1024, 25 cm out from the outer side, the face up in the image

const HEAD_SIZE := Vector2i(1920, 1080)
const CLOSE_SIZE := Vector2i(1024, 1024)
## Vertical field of view of the head picture (about the headset's, 16:9).
const HEAD_FOV := 80.0
const CLOSE_DISTANCE := 0.25
## About 18 cm across at 25 cm: the whole controller.
const CLOSE_FOV := 40.0

## scripts/main.gd
var main: Node3D
var out_dir := ""
## Seconds between automatic snapshots; 0 = off.
var every := 0.0
## Print the "Snapshots to ..." line at start (the dev link's own instance, scripts/dev/dev_shots.gd, does not).
var announce := true
var _viewport: SubViewport
var _camera: Camera3D
var _count := 0
var _busy := false
var _timer := 0.0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SnapshotViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.near = 0.01
	_camera.current = true
	_viewport.add_child(_camera)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in DirAccess.get_files_at(out_dir):
		if f.begins_with("head_") and f.ends_with(".png"):
			_count = maxi(_count, f.trim_prefix("head_").trim_suffix(".png").to_int())
	if announce:
		print("Snapshots to %s%s (left bumper + A, F12)" % [out_dir, ", every %.0f s" % every if every > 0.0 else ""])


func _process(delta: float) -> void:
	if every <= 0.0:
		return
	_timer += delta
	if _timer >= every:
		_timer = 0.0
		take()


func is_busy() -> bool:
	return _busy


## Renders and saves the five pictures; prints their paths.
func take() -> void:
	if _busy:
		return
	_busy = true
	_count += 1
	var n := _count
	var paths: Array[String] = []
	var head: Camera3D = main.camera
	paths.append(await _shot("head_%d" % n, HEAD_SIZE, head.global_transform, HEAD_FOV))
	for hand: Node3D in main.hands:
		var side := "left" if hand == main.left_hand else "right"
		var face: Dictionary = hand.visual.get_face_frame()
		var normal: Vector3 = face["normal"]
		var aim := -hand.global_basis.z
		var up := aim - normal * aim.dot(normal)
		if up.length() < 1e-3:
			up = hand.global_basis.y - normal * hand.global_basis.y.dot(normal)
		up = up.normalized()
		var centre: Vector3 = face["centre"]
		paths.append(await _shot("%s_%d" % [side, n], CLOSE_SIZE,
				Transform3D(Basis.looking_at(-normal, up), centre + normal * CLOSE_DISTANCE), CLOSE_FOV))
		# The outer side: +X of the aim pose for the right hand, -X for the left, across the face.
		var outer := hand.global_basis.x * (1.0 if side == "right" else -1.0)
		outer = (outer - normal * outer.dot(normal)).normalized()
		var body: Vector3 = face["body_centre"]
		paths.append(await _shot("%s_side_%d" % [side, n], CLOSE_SIZE,
				Transform3D(Basis.looking_at(-outer, normal), body + outer * CLOSE_DISTANCE), CLOSE_FOV))
	print("Snapshot %d: %s" % [n, ", ".join(paths)])
	_busy = false


## One picture from any pose, saved as out_dir/<file_name>.png; returns the path (the dev link's screenshot command,
## scripts/dev/dev_shots.gd). eye 0 / 1: the video screen and the overlay show that eye's picture meanwhile (they pick
## it by VIEW_INDEX, always 0 in this mono viewport; in the headset both eyes see it for those frames); -1: as they are.
func render_view(file_name: String, size: Vector2i, xform: Transform3D, fov: float, eye := -1) -> String:
	while _busy:
		await get_tree().process_frame
	_busy = true
	if eye >= 0:
		main.screen.set_force_eye(eye)
		main.overlay.set_force_eye(eye)
	var path := await _shot(file_name, size, xform, fov)
	if eye >= 0:
		main.screen.set_force_eye(-1)
		main.overlay.set_force_eye(-1)
	_busy = false
	return path


func _shot(file_name: String, size: Vector2i, xform: Transform3D, fov: float) -> String:
	_viewport.size = size
	_camera.global_transform = xform
	_camera.fov = fov
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var img := _viewport.get_texture().get_image()
	var path := out_dir.path_join(file_name + ".png")
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	if err != OK:
		print("Snapshot: can't save %s: %s" % [path, error_string(err)])
	return path
