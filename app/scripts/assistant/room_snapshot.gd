extends Node

## GET /snapshot.png (docs/assistant.md): lets the assistant look at the room it changed. A small offscreen
## SubViewport shares the main World3D (the room, the screen with the film's frame, the panel) and renders only on
## demand, one frame; the pixels come back with RenderingDevice.texture_get_data_async (no GPU stall: the copy is
## read a frame or two later) and the PNG is encoded on a worker thread. So a picture costs one extra small render and
## never holds the frame. One picture at a time; callers queue.
##
##   capture(from, size, fov) -> {png: PackedByteArray, width, height} or {error}      (await it)
##   from "viewer": the head's pose now (in the headset, the left eye's view without the lens distortion)
##        "seat": the seated eyes (the measured eye height over the seat), looking at the screen's centre

const WorkerTask := preload("res://scripts/dev/worker_task.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const DEFAULT_SIZE := Vector2i(640, 360)
const MAX_SIDE := 1280
## Vertical field of view, degrees (16:9: about 90 degrees across).
const DEFAULT_FOV := 60.0
## Frames to wait for the render and for the copy before giving up (a renderer that never draws: headless).
const WAIT_FRAMES := 30
## Clips: at most this long, this many frames a second, this wide.
const CLIP_SECONDS_MAX := 4.0
const CLIP_FPS_MAX := 12
const CLIP_FRAMES_MAX := 48
const CLIP_DEFAULT_SIZE := Vector2i(320, 180)
const CLIP_MAX_SIDE := 640

var _viewport: SubViewport
var _camera: Camera3D
var _busy := false
## Snapshots taken.
var taken := 0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SnapshotViewport"
	_viewport.size = DEFAULT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 500.0
	_camera.current = true
	# Not the agents' terminal, on the pane or the big screen: its contents never leave the headset.
	_camera.set_cull_mask_value(VideoScreen.PRIVATE_LAYER, false)
	_viewport.add_child(_camera)


func _main() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


## The camera's pose for `from`, in world space: "viewer" (the head), "seat" (the seat in use, level, towards the
## screen) or "seat:<name>" (that seat of the room, at the viewer's eye height, towards the screen).
static func pose(main: Node, from: String) -> Transform3D:
	var head: Node3D = main.camera
	if from == "viewer" and head != null and head.is_inside_tree():
		return head.global_transform
	var eye := Vector3(0, float(main.eye_height), 0)
	if from.begins_with("seat:") and main.get("features") != null and main.features.seat != null:
		var seat: Node = main.features.seat
		var i: int = seat.names().find(from.trim_prefix("seat:"))
		if i >= 0:
			var env: Node3D = main.env
			eye = env.global_transform * (seat.seat_transform(i) * Vector3(0, float(main.eye_height), 0))
	var target: Vector3 = (main.screen as Node3D).global_position
	if main.mode.is_spherical() or Vector2(target.x - eye.x, target.z - eye.z).length() < 0.05:
		var yaw: float = main.screen_yaw
		target = eye + Vector3(sin(yaw), 0, -cos(yaw))
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func capture(from: String, size: Vector2i, fov := DEFAULT_FOV) -> Dictionary:
	var main := _main()
	if main == null or not ("screen" in main):
		return {"error": "the player is not ready"}
	if DisplayServer.get_name() == "headless":
		return {"error": "no picture: the app runs without a renderer here (headless)"}
	while _busy:
		await get_tree().process_frame
	_busy = true
	var r := await _capture(main, from, size, fov)
	_busy = false
	return r


## A short clip: `seconds` at `fps`, each frame rendered and read back like a snapshot (one small render per frame,
## nothing held). format "sheet": one PNG with the frames in rows, left to right then down (an AI can read the motion
## from it); "apng": an animated PNG. {png, frames, width, height, columns} or {error}.
func capture_clip(from: String, size: Vector2i, fov: float, seconds: float, fps: int, format: String) -> Dictionary:
	var main := _main()
	if main == null or not ("screen" in main):
		return {"error": "the player is not ready"}
	if DisplayServer.get_name() == "headless":
		return {"error": "no picture: the app runs without a renderer here (headless)"}
	while _busy:
		await get_tree().process_frame
	_busy = true
	var n := clampi(roundi(seconds * fps), 2, CLIP_FRAMES_MAX)
	var frames: Array = []
	var next := Time.get_ticks_msec()
	var err := ""
	for i in n:
		while Time.get_ticks_msec() < next:
			await get_tree().process_frame
		next += roundi(1000.0 / fps)
		var r := await _render(main, from, size, fov)
		if r.has("error"):
			err = r["error"]
			break
		frames.append(r["image"])
	_busy = false
	if err != "":
		return {"error": err}
	var columns := clampi(ceili(sqrt(float(n) * size.y / size.x)), 1, n) if format == "sheet" else 0
	var encode := func() -> Variant:
		for img: Image in frames:
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
		return sheet(frames, columns) if format == "sheet" else apng(frames, fps)
	var t: Dictionary = await WorkerTask.run(get_tree(), encode, 30.0)
	if not t["done"] or not (t["result"] is PackedByteArray):
		return {"error": "no clip: encoding took too long"}
	taken += 1
	return {"png": t["result"], "frames": n, "width": size.x, "height": size.y, "columns": columns}


func _capture(main: Node, from: String, size: Vector2i, fov: float) -> Dictionary:
	var r := await _render(main, from, size, fov)
	if r.has("error"):
		return r
	var img: Image = r["image"]
	var encode := func() -> Variant:
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		return img.save_png_to_buffer()
	var t: Dictionary = await WorkerTask.run(get_tree(), encode, 10.0)
	if not t["done"] or not (t["result"] is PackedByteArray):
		return {"error": "no picture: encoding the PNG took too long"}
	taken += 1
	return {"png": t["result"], "width": size.x, "height": size.y}


## One frame: rendered once, read back without a stall. {image} or {error}.
func _render(main: Node, from: String, size: Vector2i, fov: float) -> Dictionary:
	_viewport.size = size
	_camera.global_transform = pose(main, from)
	_camera.fov = fov
	var drawn := [false]
	var on_draw := func() -> void: drawn[0] = true
	# The viewport renders in the next draw; wait for that draw to finish.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(on_draw, CONNECT_ONE_SHOT)
	for i in WAIT_FRAMES:
		if drawn[0]:
			break
		await get_tree().process_frame
	if not drawn[0]:
		if RenderingServer.frame_post_draw.is_connected(on_draw):
			RenderingServer.frame_post_draw.disconnect(on_draw)
		return {"error": "no picture: the renderer did not draw"}
	var img: Image = await _read_back(size)
	if img == null or img.is_empty() or img.get_size() != size:
		return {"error": "no picture: the render could not be read back"}
	return {"image": img}


## The frames in a grid, `columns` wide, 2 px of grey between them. Worker-safe.
static func sheet(frames: Array, columns: int) -> PackedByteArray:
	var w: int = (frames[0] as Image).get_width()
	var h: int = (frames[0] as Image).get_height()
	var rows := ceili(float(frames.size()) / columns)
	var out := Image.create_empty(columns * w + (columns - 1) * 2, rows * h + (rows - 1) * 2, false, Image.FORMAT_RGB8)
	out.fill(Color(0.5, 0.5, 0.5))
	for i in frames.size():
		out.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i((i % columns) * (w + 2), (i / columns) * (h + 2)))
	return out.save_png_to_buffer()


## An animated PNG (APNG): each frame encoded by the engine, its image data moved into fdAT chunks. Worker-safe.
static func apng(frames: Array, fps: int) -> PackedByteArray:
	var out := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	var seq := 0
	for i in frames.size():
		var chunks := _chunks((frames[i] as Image).save_png_to_buffer())
		if i == 0:
			out.append_array(_chunk("IHDR", chunks["IHDR"][0]))
			out.append_array(_chunk("acTL", _be([frames.size(), 0])))
		var img: Image = frames[i]
		var fctl := _be([seq, img.get_width(), img.get_height(), 0, 0])
		fctl.append_array(PackedByteArray([0, 1, 0, fps, 0, 0]))  # delay 1/fps s, dispose none, blend source
		out.append_array(_chunk("fcTL", fctl))
		seq += 1
		for data: PackedByteArray in chunks["IDAT"]:
			if i == 0:
				out.append_array(_chunk("IDAT", data))
			else:
				var fd := _be([seq])
				fd.append_array(data)
				out.append_array(_chunk("fdAT", fd))
				seq += 1
	out.append_array(_chunk("IEND", PackedByteArray()))
	return out


## A PNG's chunks by type: {type: [data, ...]}.
static func _chunks(png: PackedByteArray) -> Dictionary:
	var out := {}
	var pos := 8
	while pos + 8 <= png.size():
		var n := (png[pos] << 24) | (png[pos + 1] << 16) | (png[pos + 2] << 8) | png[pos + 3]
		var type := png.slice(pos + 4, pos + 8).get_string_from_ascii()
		if not out.has(type):
			out[type] = []
		out[type].append(png.slice(pos + 8, pos + 8 + n))
		pos += 12 + n
	return out


static func _be(values: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for v: int in values:
		out.append_array(PackedByteArray([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]))
	return out


static var _crc_table := PackedInt64Array()


static func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var body := type.to_ascii_buffer()
	body.append_array(data)
	var out := _be([data.size()])
	out.append_array(body)
	out.append_array(_be([_crc32(body)]))
	return out


static func _crc32(b: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for n in 256:
			var c := n
			for k in 8:
				c = (0xEDB88320 ^ (c >> 1)) if c & 1 else (c >> 1)
			_crc_table[n] = c
	var crc := 0xFFFFFFFF
	for x in b:
		crc = _crc_table[(crc ^ x) & 255] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


## The viewport's pixels: copied asynchronously when the texture is plain 8-bit RGBA, else read directly (small, so
## the stall is short).
func _read_back(size: Vector2i) -> Image:
	var rd := RenderingServer.get_rendering_device()
	var tex := _viewport.get_texture()
	if rd != null:
		var rid := RenderingServer.texture_get_rd_texture(tex.get_rid())
		if rid.is_valid():
			var fmt := rd.texture_get_format(rid)
			if fmt.format in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB] \
					and fmt.width == size.x and fmt.height == size.y:
				var box := {}
				var err := rd.texture_get_data_async(rid, 0, func(data: PackedByteArray) -> void: box["data"] = data)
				if err == OK:
					for i in WAIT_FRAMES:
						if box.has("data"):
							break
						await get_tree().process_frame
					var data: PackedByteArray = box.get("data", PackedByteArray())
					if data.size() == size.x * size.y * 4:
						return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
	return tex.get_image()
