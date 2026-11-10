## Chooses where a keyboard stroke goes: the menu field, a focused window, then the big screen. A stroke keeps its
## target through release, even if the viewer looks away. Captures and keys stay here, never in dev command results.
extends RefCounted

var app: Node
## Later floating terminals can register a provider returning {name, object, send, repeat, identity} or {}.
var providers: Array[Callable] = []
var _down := {}


func capture() -> Dictionary:
	if app == null:
		return {}
	var ui: Node = app.get("ui")
	if ui != null and ui.panel != null and ui.panel.visible:
		var field: Control = ui.panel.focus_owner()
		if (field is LineEdit or field is TextEdit) and field.is_visible_in_tree():
			return {"name": tr("the text field"), "object": field, "identity": field,
					"send": func(e: InputEventKey) -> void:
						if is_instance_valid(field) and field.is_inside_tree():
							if e.pressed and field.get_viewport().gui_get_focus_owner() != field:
								return
							field.get_viewport().push_input(e, true), "repeat": true}
	for provider in providers:
		var t: Dictionary = provider.call()
		if not t.is_empty():
			return t
	return {}


func target_name() -> String:
	var t := capture()
	return tr("Nothing to type into") if t.is_empty() else tr("Typing into: %s") % str(t.name)


## The targets' own paired-keyboard handlers are the only way into windows. Each provider captures its window,
## not just the current focus, so releasing a key cannot leave it held in a previous window.
func setup(p_app: Node) -> void:
	app = p_app
	# Capture the app parameter, not this RefCounted router: its own provider list must not keep it alive after a
	# UI reload. Static translation calls below likewise avoid capturing the router as a lambda's owner.
	providers.append(func() -> Dictionary:
		var pc: Node = p_app.features.pc_windows
		var pane: Node = pc.focused
		if pane == null:
			return {}
		return {"name": TranslationServer.translate("the PC window"), "object": pane, "identity": pane,
				"send": func(e: InputEventKey) -> void: pc.keyboard_key(e, pane), "repeat": false})
	providers.append(func() -> Dictionary:
		var agents: Node = p_app.local_agents
		var t: Object = agents.keyboard_target()
		if t == null:
			return {}
		return {"name": TranslationServer.translate("the terminal"), "object": t, "identity": t,
				"send": func(e: InputEventKey) -> void: agents.keyboard_key(e, t, true), "repeat": false, "locations": false})
	providers.append(func() -> Dictionary:
		var wp: Node = p_app.window_pointer
		var src: Object = wp.get_source()
		if src == null or not src.has_frame() or src.is_ended():
			return {}
		return {"name": TranslationServer.translate("the browser"), "object": src, "identity": src,
				"send": func(e: InputEventKey) -> void: wp.keyboard_key(e, src, true), "repeat": false, "locations": false})


## Counts overlapping hands' use of the same key. Only the last release reaches the window; repeats are only
## synthesised for fields. A missing target consumes the stroke, so it never turns into a player shortcut.
func key(event: InputEventKey, target: Dictionary) -> void:
	if target.is_empty():
		return
	if not target.has("token"):
		if not is_instance_valid(target.get("identity")):
			return
		target.token = target.identity.get_instance_id()
	var location := event.location if bool(target.get("locations", true)) else KEY_LOCATION_UNSPECIFIED
	var id := "%s:%s:%s" % [target.token, event.physical_keycode, location]
	if not is_instance_valid(target.get("object")):
		_down.erase(id)
		return
	if event.echo:
		if bool(target.get("repeat", false)):
			(target.send as Callable).call(event)
		return
	var count := int(_down.get(id, 0))
	if event.pressed:
		_down[id] = count + 1
		if count == 0:
			(target.send as Callable).call(event)
	elif count > 0:
		if count == 1:
			_down.erase(id)
			(target.send as Callable).call(event)
		else:
			_down[id] = count - 1
