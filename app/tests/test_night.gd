extends SceneTree

## Tests for scripts/play/night_mode.gd (ideas #26) in the real main scene: settings, and the values reaching the
## engine's MediaSource when a file opens and on a change. Needs an engine with MediaSource.night_mode and the 5.1 file
## app-features/vp9_51side.mkv (docs/features.md, #21, says how it was made); without them only the settings checks
## run. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_night.gd

const NightMode := preload("res://scripts/play/night_mode.gd")
var FILE := OS.get_environment("HOME").path_join("media-tests/app-features/vp9_51side.mkv")

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
	var n: Node = main.features.night
	_check("off by default, strength 1, no boost", not n.night and is_equal_approx(n.strength, 1.0)
			and is_zero_approx(n.boost_db))
	main.open_path("stub://flat_mono")
	await _frames(3)
	n.set_night(true)
	_check("a test pattern: no error, nothing to apply", n.stats().is_empty())
	_check("remembered", main.settings.get_value("sound", "night_mode", false) == true)
	n.set_dialogue_boost(20.0)
	_check("boost clamped to 12 dB", is_equal_approx(n.boost_db, 12.0))
	n.set_dialogue_boost(6.2)
	_check("boost in half-dB steps", is_equal_approx(n.boost_db, 6.0))
	n.set_strength(0.5)
	if not NightMode.available() or not FileAccess.file_exists(FILE):
		print("SKIP engine checks (no night mode in this engine, or no %s)" % FILE)
	else:
		main.open_path(FILE)
		await _until(func() -> bool: return main.current_path == FILE and main.player.source.has_method("get_media_stats"),
				10.0)
		await _frames(5)
		var media: Object = main.player.source._media
		_check("applied when the file opens", media.night_mode and is_equal_approx(media.night_mode_strength, 0.5)
				and is_equal_approx(media.dialogue_boost, 6.0))
		n.set_night(false)
		n.set_dialogue_boost(0.0)
		_check("a change reaches it at once", not media.night_mode and is_zero_approx(media.dialogue_boost))
		await _frames(30)
		print("  stats: %s" % n.stats())
		_check("5.1: the boost applies (centre channel)", n.boost_applies())
	n.set_night(false)
	n.set_strength(1.0)
	n.set_dialogue_boost(0.0)
	_check("defaults erase the settings", not main.settings.has_value("sound", "night_mode")
			and not main.settings.has_value("sound", "night_strength")
			and not main.settings.has_value("sound", "dialogue_boost_db"))
	main.open_path("stub://flat_mono")
	await _frames(3)
	print("test_night: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
