extends SceneTree

## Tests for the test lab's sharpness cards (lab://zoneplate, lab://zoneplate_360, lab://starfield_360;
## scripts/video/lab_card.gd, shaders/lab_pattern.gdshader; docs/test-lab.md) in the real main scene: listed, their
## frame size and mode, drawn once (a still: no redraws while it plays), and, with a renderer, the pattern itself
## pixel for pixel (the zone plate white at the centre and alternating at the frame's finest at the corner; stars a
## few in a thousand pixels, single pixels on black). Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_lab_patterns.gd (the pixel checks need a
## renderer: under xvfb-run with lavapipe, VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json)

const Lab := preload("res://scripts/video/lab_video_source.gd")
const LabCard := preload("res://scripts/video/lab_card.gd")

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	for want: Array in [["lab://zoneplate", Vector2i(3840, 2160), "flat_mono"],
			["lab://zoneplate_360", Vector2i(7680, 3840), "360_mono"],
			["lab://starfield_360", Vector2i(7680, 3840), "360_mono"]]:
		var path: String = want[0]
		_check("%s is listed" % path, Lab.list_cards().any(func(c: Dictionary) -> bool: return c["path"] == path))
		main.open_path(path)
		await _frames(4)
		var src: Object = main.player.source
		var info: Dictionary = src.get_video_info() if src != null else {}
		_check("%s: %s, %s (%s)" % [path, want[1], want[2], info], src != null and src.get_kind() == "lab"
				and int(info.get("width", 0)) == want[1].x and int(info.get("height", 0)) == want[1].y
				and main.mode.to_id() == want[2])
		var drawn: int = src.get("_redraws")
		main.player.play()
		await _frames(40)
		_check("%s: a still, drawn once (%d, then %d)" % [path, drawn, int(src.get("_redraws"))],
				src.has_frame() and int(src.get("_redraws")) == 1)

	if DisplayServer.get_name() == "headless":
		print("SKIP pixel checks (headless)")
	else:
		var zp := await _render("zoneplate", Vector2i(512, 256))
		var mid := zp.get_pixel(256, 128).v
		var lo := 1.0
		var hi := 0.0
		for y in 4:
			for x in 4:
				lo = minf(lo, zp.get_pixel(x, y).v)
				hi = maxf(hi, zp.get_pixel(x, y).v)
		_check("zone plate: white at the centre (%.2f)" % mid, mid > 0.95)
		_check("zone plate: at the corner, nearly a cycle every two pixels, still full contrast (%.2f to %.2f)"
				% [lo, hi], hi - lo > 0.8)
		var sf := await _render("starfield", Vector2i(512, 512))
		var stars := 0
		for y in sf.get_height():
			for x in sf.get_width():
				if sf.get_pixel(x, y).v > 0.1:
					stars += 1
		var share := float(stars) / float(sf.get_width() * sf.get_height())
		_check("starfield: a few stars in a thousand pixels (%.4f)" % share, share > 0.001 and share < 0.006)
		_check("starfield: on black", sf.get_pixel(3, 3).v < 0.1 or sf.get_pixel(4, 3).v < 0.1)
		_check("starfield: the same stars every time", (await _render("starfield", Vector2i(512, 512))).get_data()
				== sf.get_data())

	print("Lab patterns test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## A card drawn alone into a viewport of `px` pixels and read back.
func _render(card_id: String, px: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = px
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := LabCard.new()
	card.card_id = card_id
	card.size = Vector2(px)
	vp.add_child(card)
	root.add_child(vp)
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS " if ok else "FAIL ") + what)
