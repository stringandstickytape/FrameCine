extends Node3D

## A/B control for spike 02: a red unshaded quad 2 m in front of a flat camera, a 2D label, nothing else.
## Uses no fork-only classes, so the same project runs on the patched build and on stock 4.7.2 (the .BASELINE binary).
## User arguments (after `--`): --quit-after=N, --screenshot=PATH, --screenshot-frame=N (default 30).

var quit_after := -1
var screenshot_path := ""
var screenshot_frame := 30
var frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quit-after="):
			quit_after = arg.trim_prefix("--quit-after=").to_int()
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = arg.trim_prefix("--screenshot-frame=").to_int()
	print("Renderer: %s / %s, adapter: %s %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name()])


func _process(_delta: float) -> void:
	frames += 1
	if frames == screenshot_frame and screenshot_path != "":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var centre := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		print("Screenshot %s (%dx%d), centre pixel %s (red = 3D drew): %s" % [screenshot_path, img.get_width(), img.get_height(), centre.to_html(false), error_string(img.save_png(screenshot_path))])
	if quit_after > 0 and frames >= quit_after:
		print("Quitting after %d frames" % frames)
		get_tree().quit()
