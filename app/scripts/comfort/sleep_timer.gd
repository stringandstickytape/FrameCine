extends Node

## Sleep timer (ideas #17): after the chosen time, dim the room and the picture and fade the sound out over
## FADE_SECONDS, then pause and save the position (resume, #7). The room and picture stay dim until playback starts
## again; the sound level is back for then.
##
##   start(minutes)       arm the timer (replaces a running one); minutes <= 0 cancels
##   start_end_of_file()  sleep when the file ends instead of going on to the next (fades over the last minute)
##   cancel()             disarm, and undo a fade in progress
##   cycle()              off -> 15 -> 30 -> 60 -> 90 -> off (one button)
##   active, remaining() (seconds until the pause; at the end of the file for end-of-file), fading
##   status_text(localised := false)   "sleep in 23 min", "sleep at end of file", "" when off
##   signals changed(active, remaining), fade_started, slept
## Anything the user does during the fade (play/pause, a seek, opening a file) cancels it and puts everything back.
## End of file: while armed, a --dir playlist doesn't go on to the next file (main.auto_advance is held off).
## The timer counts wall-clock time, also while paused; during a pause it doesn't fade or pause (nothing to do).
## Then (the user, 2026-11-08: say what it does, give a choice): "pause" (the film pauses, the room stays dim),
## "close" (the app closes after the pause) or "off" (the headset turns itself off: the app closes and asks the system
## to power off; only in the headset). Each keeps the film's place first. set_then(what).
## Settings: [sleep] fade_seconds (default 60), [sleep] last_minutes (the last choice, for the pane's default),
## [sleep] then.
## Desktop key (menu hidden): Z cycles.

signal changed(active: bool, remaining: float)
signal fade_started
signal slept

const CHOICES: Array[int] = [15, 30, 60, 90]
## What happens once the film has paused.
const THENS: Array[String] = ["pause", "close", "off"]
const FADE_SECONDS := 60.0
## The room and the picture dim to these at the end of the fade.
const ROOM_DIM := 0.15
const PICTURE_DIM := 0.25

var main: Node3D
var active := false
var end_of_file := false
var fading := false
var fade_seconds := FADE_SECONDS
var then := "pause"
## Seconds of wall-clock time until the pause (timer mode).
var _left := 0.0
var _fade_t := 0.0
var _own := false
## The room and picture stay dim after the sleep until playback starts again.
var _dimmed := false
var _prev_left := 0.0
## main.auto_advance while an end-of-file sleep holds it off, or null.
var _held_advance: Variant = null


func _ready() -> void:
	fade_seconds = maxf(float(main.settings.get_value("sleep", "fade_seconds", FADE_SECONDS)), 1.0)
	then = str(main.settings.get_value("sleep", "then", "pause"))
	if not then in THENS:
		then = "pause"
	main.player.playing_changed.connect(_on_playing_changed)
	main.player.seeked.connect(func(_t: float) -> void:
		if fading and not _own:
			_undo_fade())
	main.file_opened.connect(func(_p: String) -> void:
		if fading and not _own:
			_undo_fade())


## What happens once the film has paused: "pause", "close" or "off" (THENS); remembered.
func set_then(what: String) -> void:
	if not what in THENS or what == then:
		return
	then = what
	main.settings.set_value("sleep", "then", what)
	changed.emit(active, remaining())


func start(minutes: float) -> void:
	if minutes <= 0.0:
		cancel()
		return
	_undo_fade()
	_release_advance()
	active = true
	end_of_file = false
	_left = minutes * 60.0
	main.settings.set_value("sleep", "last_minutes", int(minutes))
	changed.emit(true, remaining())


func start_end_of_file() -> void:
	_undo_fade()
	active = true
	end_of_file = true
	if _held_advance == null:
		_held_advance = main.auto_advance
		main.auto_advance = false
	_prev_left = remaining()
	changed.emit(true, remaining())


func cancel() -> void:
	var was := active
	active = false
	end_of_file = false
	_undo_fade()
	_release_advance()
	if was:
		changed.emit(false, 0.0)


func cycle() -> void:
	if not active:
		start(CHOICES[0])
		return
	var cur := int(round(_left / 60.0))
	for c in CHOICES:
		if c > cur + 1:
			start(c)
			return
	cancel()


func remaining() -> float:
	if not active:
		return 0.0
	if end_of_file:
		return main.features.remaining()
	return maxf(_left, 0.0)


## localised: in the menus' language (the Room tab, docs/i18n.md); else English, as an assistant reads it.
func status_text(localised := false) -> String:
	if not active:
		return ""
	if end_of_file:
		return tr("sleep at end of file") if localised else "sleep at end of file"
	return (tr("sleep in %d min") if localised else "sleep in %d min") % ceili(_left / 60.0)


## One line for what the timer does with the choice made (the Room tab, under the choices).
func then_text() -> String:
	match then:
		"close":
			return tr("The sound and the room fade out over a minute, the film pauses with its place kept, then the "
					+ "app closes.")
		"off":
			return tr("The sound and the room fade out over a minute, the film pauses with its place kept, then the "
					+ "headset turns itself off.")
	return tr("The sound and the room fade out over a minute, then the film pauses with its place kept; the room "
			+ "stays dim until you play again.")


func _process(delta: float) -> void:
	if not active:
		return
	if not end_of_file:
		_left -= delta
	var playing: bool = main.player.is_playing() and main.player.has_source()
	var left := remaining()
	if not fading and playing and left <= fade_seconds and (left > 0.0 or not end_of_file):
		fading = true
		_fade_t = clampf(fade_seconds - left, 0.0, fade_seconds) if end_of_file else 0.0
		fade_started.emit()
	if fading:
		_fade_t += delta
		_set_level(1.0 - clampf(_fade_t / fade_seconds, 0.0, 1.0))
		# End of file: the end reached, or the position wrapped (a looping source).
		if _fade_t >= fade_seconds or (end_of_file and (left <= 0.05 or left > _prev_left + 1.0)):
			_sleep()
	elif not end_of_file and _left <= 0.0:
		# Ran out while paused or with nothing open: nothing to fade.
		active = false
		changed.emit(false, 0.0)
	_prev_left = left


## 1 = normal, 0 = fully faded: sound silent, room and picture at their dim levels.
func _set_level(k: float) -> void:
	main.player.audio.volume_db = linear_to_db(maxf(k, 0.0001))
	main.features.room_light.set_factor("sleep", lerpf(ROOM_DIM, 1.0, k))
	main.screen.material.set_shader_parameter("brightness", lerpf(PICTURE_DIM, 1.0, k))


func _sleep() -> void:
	_own = true
	if main.player.is_playing():
		main.player.pause()
	_own = false
	main.player.audio.volume_db = 0.0
	fading = false
	active = false
	end_of_file = false
	_release_advance()
	_dimmed = true
	main.features.resume.save_now()
	print("Sleep timer: paused and saved")
	slept.emit()
	changed.emit(false, 0.0)
	if then != "pause" and main.settings.has_method("save_if_dirty"):
		main.settings.save_if_dirty()
	match then:
		"close":
			print("Sleep timer: closing the app")
			main.get_tree().quit.call_deferred()
		"off":
			# Only the headset turns off; a desktop run (tests, development) closes the app at most.
			if bool(main.get("use_xr")) and OS.get_name() == "Linux":
				print("Sleep timer: turning the headset off")
				OS.create_process("systemctl", ["poweroff"])
			else:
				print("Sleep timer: would turn the headset off (not in the headset)")
			main.get_tree().quit.call_deferred()


func _undo_fade() -> void:
	if fading or _dimmed:
		fading = false
		_dimmed = false
		main.player.audio.volume_db = 0.0
		main.features.room_light.set_factor("sleep", 1.0, 1.0)
		main.screen.material.set_shader_parameter("brightness", 1.0)


func _release_advance() -> void:
	if _held_advance != null:
		main.auto_advance = bool(_held_advance)
		_held_advance = null


func _on_playing_changed(playing: bool) -> void:
	if _own:
		return
	if fading and end_of_file and not playing and main.player.has_source() and main.player.source.is_ended():
		# The file ended during the end-of-file fade: that is the sleep.
		_sleep()
		return
	if fading or (playing and _dimmed):
		_undo_fade()


## True while the file's end should not go on to the next file (end-of-file sleep).
func holds_auto_advance() -> bool:
	return active and end_of_file


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or main.menu_shown or main.window_pointer.is_active():
		return
	if key.keycode == KEY_Z:
		cycle()
		print("Sleep timer: %s" % (status_text() if active else "off"))
