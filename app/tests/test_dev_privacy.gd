extends SceneTree

## The dev link never reads or writes secrets: BuiltinCommands.is_private() for settings ("section/key") and property
## paths, as get, set, get_prop, set_prop and call use it.
## godot --headless --xr-mode off --path app --script res://tests/test_dev_privacy.gd

const BuiltinCommands := preload("res://scripts/dev/builtin_commands.gd")

var _fails := 0


func _init() -> void:
	for p in ["remote/key", "x/pin", "network/hosts", "network/anything", "_key", "_server:_key", "share/password",
			"x/api_token", "a/b_secret", "dev/smb_credentials", "mesh:_private", "Remote/_key"]:
		_check(BuiltinCommands.is_private(p), "private: " + p)
	for p in ["audio/volume", "subtitles/size", "pane/scale", "position", "mesh:size", "keyboard_visible", "mapping",
			"spinner", "remote/port", "remote/enabled", "monkey", "material_override:albedo_color"]:
		_check(not BuiltinCommands.is_private(p), "not private: " + p)
	print("test_dev_privacy: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)
