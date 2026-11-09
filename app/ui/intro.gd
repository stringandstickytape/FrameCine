extends VBoxContainer

## The introduction at the app's first start (the user, 2026-11-09): it fills the menu on the tablet's main pane
## (ui/pane_ui.gd show_intro()) in place of the tabs, until it is gone through to its last step. Closing the menu leaves
## it there for the next time the menu opens. Until it is done the agents' terminals take no controller keys
## (scripts/agents/local_agents.gd).
##
## Steps (STEPS), in big type, a few plain sentences each:
##   gaze   only when the headset has eye gaze (EyeGaze.supported()): why to calibrate (the look gives the keys to a
##          window or the agent's terminal), Calibrate (scripts/xr/eye_gaze.gd calibrate(); the menu steps aside while
##          the dots show, and comes back after) or Skip. Skipped, cancelled or not possible: the next step says the
##          gaze still works, less exactly.
##   keys   the controls of the whole app: talk on the pointer hand's bumper (where it types), the menu, trigger,
##          stick, A and B
##   agent  the agent's terminal's own keys: X Enter while it shows, Y, and the keys while it has the input
##   start  Start: done ([intro] done = true), the tabs come back
## The speech model (about 264 MB, scripts/voice/whisper_backend.gd) downloads from the moment the introduction opens,
## not at the first use of voice (the user, 2026-11-09: waiting for it then is a horrible experience). Every step says
## how far it is; Start waits for it. A failed download: Retry, or Start without voice (voice then fetches it when used).
## A step goes forward with its main button (the laser and the trigger, or the trigger on the focused button) or with
## A; B goes back a step. For GUARD seconds after a step shows, its buttons are off and A does nothing, so a press
## already on its way (the one that opened the menu, a double press) can't tap through it.
##
## When: wanted() at start (main.gd): not done yet, and not a run with read-only settings (tests, screenshots), a
## headless one, or one started for a file, a folder, a tour or a test. System, Test and setup, "Show the introduction
## again" shows it at any time (ui_layer.gd show_intro()).
##
##   begin(steps), next(), back(), active, step(), steps, primary(), steps_for(has_gaze)
##   signals: finished, calibrate_requested, calibration_ended

signal finished
## The Calibrate button: the layer hides the menu and starts the calibration (ui_layer.gd).
signal calibrate_requested
## The calibration ended (done, cancelled or not possible): the layer shows the menu again.
signal calibration_ended

const W := preload("res://ui/pane_widgets.gd")
const WhisperBackend := preload("res://scripts/voice/whisper_backend.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const SECTION := "intro"
## Seconds a step takes no input after it shows.
const GUARD := 0.6
## A calibration that hasn't started this long after Calibrate never will (no gaze tracked now).
const CAL_START_WAIT := 0.3
## The type: the body text and the title, times the theme's own body size.
const TEXT_SCALE := 1.45
const TITLE_SCALE := 2.0
## Arguments that start the app for something else: no introduction that run (main.gd's user arguments).
const SKIP_ARGS: Array[String] = ["file", "dir", "tour", "kiosk", "shots", "ui-test", "window-test", "no-ui",
		"screenshot", "quit-after", "benchmark"]

# i18n: begin
## Each step: its title, its lines (lines_left: the same with the left hand pointing), its buttons.
const STEPS := {
	"gaze": {
		"title": "Calibrate your eyes",
		"lines": [
			"The headset sees where you look. Look at a window or at the agent's terminal, and the controller's keys go to it.",
			"A short calibration makes this exact. Look at each dot and pull the trigger. It takes about a minute.",
		],
		"primary": "Calibrate", "secondary": "Skip",
	},
	"keys": {
		"title": "The controls",
		"lines": [
			"Hold the right bumper and speak instead of typing. It types into a text field in the browser, a PC window or the agent's terminal, or talks to a connected assistant. Its label says TALK when it can.",
			"Menu button: this menu. Hold it to bring the menu in front of you.",
			"Trigger: play and pause. On the menu it clicks.",
			"Stick: seek and screen distance. On the menu it scrolls.",
			"A and B: the next and the previous video.",
		],
		"lines_left": [
			"Hold the left bumper and speak instead of typing. It types into a text field in the browser, a PC window or the agent's terminal, or talks to a connected assistant. Its label says TALK when it can.",
		],
		"primary": "Next", "secondary": "Back",
	},
	"agent": {
		"title": "In the agent's terminal",
		"lines": [
			"Only for Claude Code and Codex on the headset, on the pane at your controller.",
			"X is Enter while the terminal shows.",
			"Y shows and hides it. A quick tap of the bumper hides it too.",
			"When it asks you something (an amber edge), when you look at it (a blue edge) or while you hold the squeeze: the trigger is Enter, the stick is the arrow keys, A is Space and B is Escape.",
			"Squeeze held: the stick scrolls back.",
			"A keyboard paired to the headset types into it.",
		],
		"primary": "Next", "secondary": "Back",
	},
	"start": {
		"title": "Ready",
		"lines": [
			"The print on the controllers always shows what each button does now.",
			"To see this again: System, Test and setup, Show the introduction again.",
		],
		"primary": "Start", "secondary": "Back",
	},
}
const GAZE_DONE := "Eye calibration done."
const GAZE_SKIPPED := "No calibration: the gaze still works, but less exactly."
## Calibrate pressed, but the headset gave no eye gaze then (scripts/xr/eye_gaze.gd available() false).
const GAZE_UNAVAILABLE := "The calibration could not start: the headset gave no eye gaze. Try again later from System, Show the introduction again."
const MODEL_RUNNING := "Downloading the speech model for voice (about 264 MB): %d %%"
const MODEL_WAIT := "Start comes on when the speech model is here: %d %%"
const MODEL_READY := "The speech model for voice is here."
const MODEL_FAILED := "The speech model for voice did not download."
const MODEL_OFFLINE := "The speech model for voice did not download: no network. Connect to Wi-Fi and press Retry."
const MODEL_RETRY := "Retry"
const MODEL_WITHOUT := "Start without voice"
# i18n: end

## scripts/main.gd
var app: Node
## The steps of this showing, in order (steps_for()).
var steps: Array[String] = []
## Between begin() and the last step's Start.
var active := false
var _index := 0
var _guard := 0.0
## The calibration started from the gaze step runs; how it ended ("done", "skipped", "unavailable" or "").
var _calibrating := false
var _cal_seen := false
var _cal_wait := 0.0
var _cal_before := ""
var _gaze_result := ""
var _title: Label
var _note: Label
var _lines: VBoxContainer
var _scroll: ScrollContainer
var _progress: Label
var _primary: Button
var _secondary: Button
## The speech model's line, its Start without voice button, and the backend (null: none here, as in tests).
var _model: Label
var _without: Button
var _voice: Node = null
## The model was fetched at this showing; its state at the last look ("" none to fetch).
var _model_asked := false
var _model_state := ""


## Show it at this start: not done yet, and the app not started for something else (or headless).
static func wanted(settings: Object, args: Dictionary, headless := DisplayServer.get_name() == "headless") -> bool:
	if settings.read_only or headless:
		return false
	if bool(settings.get_value(SECTION, "done", false)):
		return false
	for a in SKIP_ARGS:
		if args.has(a):
			return false
	return true


## The steps for a headset with eye gaze or without.
static func steps_for(has_gaze: bool) -> Array[String]:
	var out: Array[String] = ["keys", "agent", "start"]
	if has_gaze:
		out.push_front("gaze")
	return out


func _init() -> void:
	name = "Intro"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_title = W.label("", &"TitleLabel")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_note = W.label("", &"AccentLabel")
	W.content(_note)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	add_child(_note)
	var s := W.scrolled()
	_scroll = s[0]
	_lines = s[1]
	_lines.add_theme_constant_override("separation", 10)
	add_child(_scroll)
	_model = W.label("", &"MutedLabel")
	W.content(_model)
	_model.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_model.visible = false
	add_child(_model)
	_progress = W.label("", &"MutedLabel")
	W.content(_progress)
	_secondary = W.button("", func() -> void: _on_secondary())
	_primary = W.button("", func() -> void: _on_primary())
	_without = W.button(MODEL_WITHOUT, func() -> void: _finish())
	_without.visible = false
	_primary.name = "IntroPrimary"
	_secondary.name = "IntroSecondary"
	_without.name = "IntroWithoutVoice"
	add_child(W.hbox([_progress, W.spacer(), _without, _secondary, _primary]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_sizes()


## Starts at the first of `p_steps`.
func begin(p_steps: Array[String]) -> void:
	steps = p_steps.duplicate()
	active = true
	_index = 0
	_gaze_result = ""
	_calibrating = false
	_model_asked = false
	_model_state = ""
	if _voice == null and app != null and is_inside_tree() and not _headless():
		_voice = WhisperBackend.ensure(get_tree())
	_show_step()


func step() -> String:
	return steps[_index] if active and _index < steps.size() else ""


## The step's main button (the stick focus starts there).
func primary() -> Button:
	return _primary


## Forward, as the main button: on the gaze step that is Calibrate. False while the guard holds (or a calibration runs).
func next() -> bool:
	if not active or _guard > 0.0 or _calibrating:
		return false
	_on_primary()
	return true


## Back a step; on the first, nothing.
func back() -> bool:
	if not active or _guard > 0.0 or _calibrating or _index == 0:
		return false
	_index -= 1
	_show_step()
	return true


func _on_primary() -> void:
	if _guard > 0.0 or _calibrating:
		return
	match step():
		"gaze":
			_calibrating = true
			_cal_seen = false
			_cal_wait = 0.0
			_cal_before = str(app.settings.get_value("gaze", "calibrated_at", "")) if app != null else ""
			_set_buttons(false)
			calibrate_requested.emit()
		"start":
			if _model_state == "failed":
				_voice.call("fetch_model")
				_update_model()
			elif not _model_busy():
				_finish()
		_:
			_go(_index + 1)


func _finish() -> void:
	active = false
	if is_instance_valid(_voice):
		_voice.set("quiet", false)
	if app != null:
		app.settings.set_value(SECTION, "done", true)
	finished.emit()


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## The download runs (or is about to): Start waits.
func _model_busy() -> bool:
	return _model_state in ["needed", "running"]


## Fetches the model the first time it's seen missing, then keeps the line, Start and Retry up to date.
func _update_model() -> void:
	var st := ""
	var pct := 0
	var offline := false
	if is_instance_valid(_voice) and _voice.has_method("model_status"):
		var m: Dictionary = _voice.call("model_status")
		st = str(m["state"])
		pct = int(m["percent"])
		offline = bool(m["offline"])
		if st == "needed" and not _model_asked:
			_model_asked = true
			_voice.set("quiet", true)
			_voice.call("fetch_model")
			st = str(_voice.call("model_status")["state"])
	var changed := st != _model_state
	_model_state = st
	_model.visible = _model_asked and st != ""
	match st:
		"needed", "running":
			_model.text = tr(MODEL_WAIT if step() == "start" else MODEL_RUNNING) % pct
		"failed":
			_model.text = tr(MODEL_OFFLINE if offline else MODEL_FAILED)
		_:
			_model.text = tr(MODEL_READY)
	var on_start := step() == "start"
	_without.visible = on_start and st == "failed"
	if on_start:
		_primary.text = tr(MODEL_RETRY) if st == "failed" else tr(STEPS["start"]["primary"])
		if _guard <= 0.0 and not _calibrating:
			_primary.disabled = _model_busy()
	if changed:
		_apply_sizes()


func _on_secondary() -> void:
	if _guard > 0.0 or _calibrating:
		return
	if step() == "gaze":
		_gaze_result = "skipped"
		_go(_index + 1)
	else:
		back()


func _go(index: int) -> void:
	_index = clampi(index, 0, steps.size() - 1)
	_show_step()


func _show_step() -> void:
	var id := step()
	if id == "":
		return
	var s: Dictionary = STEPS[id]
	_title.text = s["title"]
	var lines: Array = s["lines"].duplicate()
	if s.has("lines_left") and _left_pointing():
		var left: Array = s["lines_left"]
		for i in left.size():
			lines[i] = left[i]
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for line: String in lines:
		var l := W.label(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lines.add_child(l)
	# The gaze step's outcome, on the step after it.
	_note.visible = _gaze_result != "" and _index > 0 and steps[_index - 1] == "gaze"
	_note.text = tr(GAZE_DONE if _gaze_result == "done" else (GAZE_UNAVAILABLE if _gaze_result == "unavailable"
			else GAZE_SKIPPED))
	_primary.text = s["primary"]
	_secondary.text = s["secondary"]
	_secondary.visible = not (s["secondary"] == "Back" and _index == 0)
	_progress.text = tr("Step %d of %d") % [_index + 1, steps.size()]
	_scroll.scroll_vertical = 0
	_guard = GUARD
	_set_buttons(false)
	_update_model()
	_apply_sizes()


func _left_pointing() -> bool:
	var layer: Variant = app.get("ui") if app != null else null
	return layer != null and layer.get("pointer_hand") != null and layer.pointer_hand == app.get("left_hand")


func _set_buttons(on: bool) -> void:
	_primary.disabled = not on or (step() == "start" and _model_busy())
	_secondary.disabled = not on
	_without.disabled = not on
	if on and is_visible_in_tree():
		_primary.grab_focus()


func _process(delta: float) -> void:
	if not active:
		return
	_update_model()
	if _guard > 0.0:
		_guard -= delta
		if _guard <= 0.0 and not _calibrating:
			_set_buttons(true)
	if _calibrating:
		var gaze: Object = app.features.get("gaze") if app != null and app.get("features") != null else null
		var running: bool = gaze != null and bool(gaze.get("calibrating"))
		_cal_seen = _cal_seen or running
		_cal_wait += delta
		# calibrate() starts at once or not at all (no gaze tracked now): until it ends, or a moment for nothing.
		if not running and (_cal_seen or _cal_wait >= CAL_START_WAIT):
			_calibrating = false
			var now := str(app.settings.get_value("gaze", "calibrated_at", ""))
			if not _cal_seen:
				_gaze_result = "unavailable"
			else:
				_gaze_result = "done" if now != "" and now != _cal_before else "skipped"
			_go(_index + 1)
			calibration_ended.emit()


## The big type: the theme's body size (the tablet's scale in it) times TEXT_SCALE, the title TITLE_SCALE.
func _apply_sizes() -> void:
	var body := get_theme_default_font_size()
	if body <= 0:
		body = PaneStyle.font_size(&"body")
	var text_px := roundi(body * TEXT_SCALE)
	_title.add_theme_font_size_override("font_size", roundi(body * TITLE_SCALE))
	_note.add_theme_font_size_override("font_size", text_px)
	_model.add_theme_font_size_override("font_size", text_px)
	for l in _lines.get_children():
		(l as Control).add_theme_font_size_override("font_size", text_px)
	for b: Button in [_primary, _secondary, _without]:
		b.add_theme_font_size_override("font_size", text_px)
		b.custom_minimum_size = Vector2(maxf(160.0, text_px * 6.0), PaneStyle.constant(&"button_height") * 1.4)
