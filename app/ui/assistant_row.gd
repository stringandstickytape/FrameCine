extends VBoxContainer

## The System tab's "Assistant" section (docs/assistant.md): on / off; "Let an assistant find me" (60 minutes in which
## an assistant on this network can read the guide and ask to pair; the address and the time left, with Stop); the
## pairing prompt (the code in large digits, who asks, Cancel); the paired assistants with Forget; what the assistant
## may do; and, for developers with the dev link connected too, where the voice goes. Nothing is typed here.
## Languages (docs/i18n.md): the fixed words translate themselves; the built lines are made again when the language
## changes. The service's own status line (assistant_service.gd status_text()) comes translated.

const W := preload("res://ui/pane_widgets.gd")
const Assistant := preload("res://scripts/assistant/assistant.gd")
const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const AssistantSwitches := preload("res://scripts/assistant/assistant_switches.gd")
## The line under each switch.
# i18n: begin
const SWITCH_HELP := {
	"control": "Off: it can see what plays and answer on the card, nothing else.",
	"room": "Each change shows at once and is kept as a room in the Room tab. Ask the assistant to change it back, "
			+ "or Reset room for the stock room.",
	"settings": "Picture, sound, subtitles and system preferences, kept as if you set them.",
	"files": "Copies and downloads into the Library, places and saved hosts. It never sees a share's login.",
	"apps": "Starts, stops, shows and hides Android apps and the agents on this headset.",
}
# i18n: end


var app: Node
var _toggle: Button
var _status: Label
var _body: VBoxContainer
var _find_button: Button
var _window_box: HBoxContainer
var _address: Label
var _left: Label
var _pair_box: VBoxContainer
var _pair_who: Label
var _code: Label
var _paired_box: VBoxContainer
var _paired_ids: Array = []
## level -> its switch's toggle ("Let the assistant control playback", ...).
var _switches := {}
var _service: Node
## "Voice goes to": shown when there is more than one place for it (the dev link, the assistant link, the agents
## running on this headset); see ui_layer.voice_target().
var _voice_box: HBoxContainer
var _voice_choice: HFlowContainer
var _voice_targets: Array[String] = []


func _init() -> void:
	name = "AssistantRow"
	add_theme_constant_override("separation", 4)


func bind(p_app: Node) -> void:
	app = p_app
	_toggle = W.toggle("Assistant", func(on: bool) -> void:
		if on:
			Assistant.start(app, true)
		else:
			Assistant.stop(app, true)
		refresh.call_deferred())
	add_child(W.hbox([_toggle]))
	add_child(W.help("An AI assistant on a computer on this network sees what plays, answers you on a card, and "
			+ "hears you while you hold the bumper. No program to install."))
	_body = W.vbox()
	add_child(_body)
	_status = W.label("")
	W.content(_status)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)

	_pair_box = W.vbox()
	_pair_who = W.label("")
	W.content(_pair_who)
	_pair_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pair_box.add_child(_pair_who)
	_code = W.label("", &"TitleLabel")  # the largest text style
	W.content(_code)
	_pair_box.add_child(W.hbox([_code, W.button("Cancel", func() -> void:
		if _service != null:
			_service.cancel_pairing())]))
	_pair_box.add_child(W.help("Read this code out to the assistant. Cancel if you did not ask for it."))
	_pair_box.visible = false
	_body.add_child(_pair_box)

	_find_button = W.button("Let an assistant find me", func() -> void:
		var s := Assistant.start(app, true)
		if s != null:
			_open_window.call_deferred(s)
		refresh.call_deferred())
	_body.add_child(W.hbox([_find_button]))
	_address = W.label("", &"TimeLabel")
	W.content(_address)
	_left = W.label("", &"MutedLabel")
	W.content(_left)
	_window_box = W.hbox([_address, _left, W.button("Stop", func() -> void:
		if _service != null:
			_service.close_window())])
	_window_box.visible = false
	_body.add_child(_window_box)
	_body.add_child(W.help("Give the assistant this address. For an hour it can ask to pair; then it shows a code "
			+ "here for you to read out."))

	_paired_box = W.vbox()
	_body.add_child(_paired_box)

	# One row per switch (AssistantSwitches.SWITCHES), each off until the viewer turns it on.
	for level: String in AssistantSwitches.SWITCHES:
		var t := W.toggle(AssistantSwitches.SWITCHES[level]["label"], func(on: bool) -> void:
			if _service != null:
				_service.set_allowed(level, on)
			else:
				app.settings.set_value("assistant", AssistantSwitches.SWITCHES[level]["key"], on))
		_switches[level] = t
		_body.add_child(W.hbox([t]))
		_body.add_child(W.help(SWITCH_HELP[level]))
	_voice_box = W.hbox([W.label("Voice goes to")])
	_voice_box.visible = false
	_body.add_child(_voice_box)
	refresh()


## The service is added to the tree deferred: open the window once it is there.
func _open_window(s: Node) -> void:
	if not is_instance_valid(s):
		return
	if not s.is_inside_tree():
		await s.ready
	s.open_window()
	refresh()


## The pairing prompt, for the System tab to scroll to.
func pairing_prompt() -> Control:
	return _pair_box


## Called by the System tab a few times a second while it shows.
func tick() -> void:
	if Assistant.instance() != _service:
		refresh()
	elif _service != null and is_instance_valid(_service) and _service.is_inside_tree():
		_refresh_window()
	_refresh_voice()


## The places the voice can go now: id -> what the choice says.
func voice_targets() -> Dictionary:
	var out := {}
	var dev := get_tree().root.get_node_or_null("DevHost") if is_inside_tree() else null
	if dev != null and dev.get_node_or_null("PushToTalk") != null:
		out["dev"] = tr("Dev link")
	if Assistant.push_to_talk() != null:
		out["assistant"] = tr("Assistant")
	var agents: Node = app.get("local_agents")
	if agents != null:
		for id: String in agents.running():
			out[id] = tr("%s on this headset") % AgentTerminal.AGENTS[id]["name"]
	return out


func _refresh_voice() -> void:
	var targets := voice_targets()
	_voice_box.visible = targets.size() > 1
	if targets.size() < 2:
		return
	var ids: Array[String] = []
	ids.assign(targets.keys())
	if ids != _voice_targets:
		_voice_targets = ids
		if _voice_choice != null:
			_voice_box.remove_child(_voice_choice)
			_voice_choice.queue_free()
		var labels: Array[String] = []
		labels.assign(targets.values())
		_voice_choice = W.choices(labels, _on_voice_choice)
		_voice_box.add_child(_voice_choice)
	W.set_choice(_voice_choice, ids.find(str(app.settings.get_value("assistant", "voice_to", ids[0]))))


func _on_voice_choice(i: int) -> void:
	var to := _voice_targets[i]
	app.settings.set_value("assistant", "voice_to", to)
	var agents: Node = app.get("local_agents")
	if agents != null and AgentTerminal.AGENTS.has(to):
		agents.set_active(to)
	var ui_layer: Node = app.get("ui")
	if ui_layer != null and ui_layer.has_method("check_push_to_talk"):
		ui_layer.check_push_to_talk()


func refresh() -> void:
	var service := Assistant.instance()
	if service != _service:
		_service = service
		if service != null:
			# Methods, not lambdas: the service outlives the pane across `reload app`.
			service.status_changed.connect(refresh)
			service.pairing_changed.connect(refresh)
	var on := service != null
	W.set_on(_toggle, on)
	_body.visible = on
	for level: String in _switches:
		W.set_on(_switches[level], bool(app.settings.get_value("assistant", AssistantSwitches.SWITCHES[level]["key"],
				false)))
	if not on or not service.is_inside_tree():
		return
	_refresh_window()
	var ids: Array = service.paired().map(func(c: Dictionary) -> String: return c["id"])
	if ids != _paired_ids:
		_paired_ids = ids
		for child in _paired_box.get_children():
			child.queue_free()
		for c: Dictionary in service.paired():
			var id: String = c["id"]
			var label := W.ellipsis(W.label(tr("%s, paired %s") % [c["name"], str(c["paired_at"]).get_slice(" ", 0)],
					&"MutedLabel"))
			W.content(label)
			_paired_box.add_child(W.hbox([label, W.button("Forget", func() -> void:
				if _service != null:
					_service.forget(id))]))


func _refresh_window() -> void:
	var s := _service
	_status.text = s.status_text()
	var p: Dictionary = s.pairing()
	_pair_box.visible = not p.is_empty()
	if not p.is_empty():
		_pair_who.text = tr("%s asks to pair with this headset.") % p["client"]
		_code.text = "%s %s" % [str(p["code"]).left(3), str(p["code"]).right(3)]
	var open: bool = s.window_open()
	_window_box.visible = open
	_find_button.visible = not open
	if open:
		_address.text = s.guide_address()
		var pin: String = s.pin_short()
		var minutes := ceili(float(s.window_left()) / 60.0)
		_left.text = tr("%d min left  ·  pin %s") % [minutes, pin] if pin != "" else tr("%d min left") % minutes


## The language changed: the paired list and the voice choice are made again in it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and app != null and _paired_box != null:
		_paired_ids = []
		_voice_targets = []
		refresh()
