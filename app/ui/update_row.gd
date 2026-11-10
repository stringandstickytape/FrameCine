extends VBoxContainer

## The System tab's "Updates" section (scripts/update/updater.gd, docs/framedrop.md): the check on or off
## ([update] check), Check now (the answer is a notice), the installed version and what the updater is doing
## (looking, downloading, ready), and Restart now when a new version is ready. Why a timed check failed is one line in
## the log.
## Languages (docs/i18n.md): the fixed words translate themselves; the status line is built again in refresh().

const W := preload("res://ui/pane_widgets.gd")

var app: Node
var _toggle: Button
var _status: Label
var _restart: Button
var _check: Button
var _feature: Node


func _init() -> void:
	name = "UpdateRow"
	add_theme_constant_override("separation", 4)


func bind(p_app: Node) -> void:
	app = p_app
	_feature = app.features.get("update") if app.get("features") != null else null
	_toggle = W.toggle("Check for updates", func(on: bool) -> void:
		if _feature != null:
			_feature.set_enabled(on))
	_check = W.button("Check now", func() -> void:
		if _feature != null:
			_feature.check_by_hand()
			refresh())
	_restart = W.button("Restart now", func() -> void:
		if _feature != null:
			_feature.restart_now())
	add_child(W.flow([_toggle, _check, _restart]))
	_status = W.label("", &"MutedLabel")
	W.content(_status)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	add_child(W.help("At each start, and once a day while it runs, the player asks GitHub for a new version and "
			+ "downloads it in the background. It installs only when you say yes. Only your IP address goes to GitHub."))
	if _feature != null:
		_feature.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _feature == null:
		visible = false
		return
	W.set_on(_toggle, bool(_feature.enabled))
	_restart.visible = str(_feature.state) == "ready"
	# Not while a check or a download is going, nor outside an install; with a version ready, Restart now is the step.
	_check.visible = str(_feature.install_dir) != "" and str(_feature.state) == "idle"
	var line: String = _feature.status_text()
	var notes: String = _feature.notes()
	_status.text = line + ("\n" + notes if notes != "" else "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _status != null:
		refresh()
