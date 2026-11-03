extends SceneTree

## The player's audio_external hook (PC audio pulls the sound with MediaSource.read_audio_frames()): no
## AudioStreamPlayer stream while it is on, also across a new file and an audio track change; the stream back when it
## is off. PC audio asked to pull from a source without read_audio_frames() falls back to capture and leaves the hook
## off. Settings are read-only.
## godot --xr-mode off --path app --script res://tests/test_audio_external.gd (the clock check needs a renderer)

const PCAudio := preload("res://scripts/dev/pc_audio.gd")

var main: Node3D
var _fails := 0


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(5)
	var p: Node = main.player
	main.open_path("lab://av_sync")
	await _frames(5)
	_check(p.audio.stream != null, "the lab card brings its audio")

	p.audio_external = true
	_check(p.audio.stream == null and not p.audio.playing, "external: no stream, nothing playing")
	if DisplayServer.get_name() != "headless":
		var t0: float = p.get_position()
		await create_timer(1.0).timeout
		_check(p.get_position() - t0 > 0.5, "external: the video runs on frame time (%.2f s)" % (p.get_position() - t0))
	main.open_path("lab://av_sync")
	await _frames(5)
	_check(p.audio.stream == null, "external: a new file brings no stream")
	p.select_audio_track(0)
	_check(p.audio.stream == null, "external: an audio track change brings no stream")

	p.audio_external = false
	_check(p.audio.stream != null and p.audio.stream == p.source.get_audio_stream(), "off: the stream is back")
	if DisplayServer.get_name() != "headless":
		await _frames(3)
		_check(p.audio.playing, "off: the stream plays again")

	var n: Node = PCAudio.start(main, "127.0.0.1:1", false, "pull")
	await _frames(3)
	var st: Dictionary = n.status()
	_check(st["mode"] == "capture" and not p.audio_external, "pull without read_audio_frames: capture (%s)" % st["mode"])
	PCAudio.stop()
	await _frames(2)
	_check(not p.audio_external and p.audio.stream != null, "PC audio off: the player has its stream")

	print("test_audio_external: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
