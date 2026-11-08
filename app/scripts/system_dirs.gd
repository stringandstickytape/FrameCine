extends RefCounted

## The system's folders (OS.get_system_dir()), each asked once and kept: on Linux every OS.get_system_dir() call runs
## xdg-user-dir, about 45 to 75 ms on the headset's main thread. The picture keeper asked for Downloads every 2 s while
## the browser was on the big screen, and the headset stuttered every 2 s (the user, 2026-11-08).
##
##   const SystemDirs := preload("res://scripts/system_dirs.gd")
##   SystemDirs.get_dir(OS.SYSTEM_DIR_DOWNLOADS)

static var _known := {}


## The folder, or "" when the system has none.
static func get_dir(which: OS.SystemDir) -> String:
	if not _known.has(which):
		_known[which] = OS.get_system_dir(which)
	return _known[which]
