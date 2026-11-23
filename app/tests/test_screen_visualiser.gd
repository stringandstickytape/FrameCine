extends SceneTree

## Tests for a visualiser on the screen in place of what plays (scripts/play/screen_visualiser.gd) and the buttons
## beside the screen (ui/screen_buttons.gd), in the real main scene with a stub film: on and off, the screen's own
## material in between, stepping through the visualisers, the film layer stepping aside, a new file starting with its
## picture, 360 not usable, and the buttons' places and presses. How it looks needs a renderer and the headset.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_screen_visualiser.gd

const MusicSource := preload("res://scripts/play/music_source.gd")
const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")

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
	var vis: Node = main.features.screen_vis
	var flat: MeshInstance3D = main.screen.get_node("Flat")
	var film: Node = main.features.film_layer
	var buttons: Node3D = main.ui.screen_buttons
	main.set_environment("void")
	main.ui.hide_panel()
	await _frames(2)
	_check("nothing playing: not usable, not on, no buttons", not vis.usable() and not vis.is_on()
			and not buttons.wanted())
	vis.set_on(true)
	_check("and on does nothing then", not vis.is_on())

	main.features.set_visualiser("bars")
	main.open_path("stub://flat_mono")
	await _frames(4)
	_check("a film: usable, off, the screen's own material", vis.usable() and not vis.is_on()
			and flat.material_override == main.screen.material and vis.host == null)
	_check("the buttons show only with the menu", not buttons.wanted())
	main.ui.show_panel()
	await _frames(20)
	_check("the menu open: the buttons beside the screen", buttons.wanted() and buttons.shown())
	var corner: Vector3 = main.screen.top_right_corner() - main.screen.global_basis.y * float(main.screen.get_flat_size().y)
	var head: Vector3 = main.camera.global_position
	var to_corner := (corner - head).normalized()
	var to_panel: Vector3 = (buttons.global_position - head).normalized()
	_check("to the right of the picture's bottom-right corner, no lower than it", to_panel.cross(to_corner).y > 0.0
			and buttons.global_position.y - buttons.size_m.y * 0.5 >= (head + to_corner * head.distance_to(
			buttons.global_position)).y - 0.02)

	# On: the visualiser's viewport on the screen's mesh, the film layer asked aside, the film still playing.
	var pos: float = main.player.get_position()
	_check("the Visualiser button", buttons.click(buttons.button_point("toggle")) == "toggle")
	await _frames(4)
	_check("on: another material on the screen's mesh, the host running bars", vis.is_on()
			and flat.material_override != main.screen.material and vis.host != null and vis.host.id == "bars"
			and vis.host.is_processing())
	_check("the film layer steps aside", film.scene_requests.has("visualiser") and film.wanted_kind() == "")
	var px: Vector2i = (vis.host.get_parent() as SubViewport).size
	var flat_size: Vector2 = main.screen.get_flat_size()
	_check("its viewport has the picture's shape (%s)" % px, px.y == 720
			and absf(float(px.x) / px.y - flat_size.x / flat_size.y) < 0.01)
	await _frames(10)
	_check("the film plays on behind it (%.2f s)" % main.player.get_position(), main.player.is_playing()
			and main.player.get_position() >= pos)
	_check("the button reads on, with the visualiser's name", buttons._toggle.button_pressed
			and buttons._name.text == str(Registry.entry("bars")["name"]))

	# Stepping: the menu's order, round the ends, never off.
	var ids := Registry.ids()
	var at := ids.find("bars")
	_check("next", buttons.click(buttons.button_point("next")) == "next" and MusicSource.style == ids[(at + 1) % ids.size()])
	await _frames(3)
	_check("the host follows", vis.host.id == MusicSource.style)
	buttons.click(buttons.button_point("previous"))
	buttons.click(buttons.button_point("previous"))
	_check("previous, twice", MusicSource.style == ids[posmod(at - 1, ids.size())])
	main.features.set_visualiser("bars")
	await _frames(2)

	# Off chosen in the Picture tab: the picture again; on brings the last one back.
	main.features.set_visualiser(MusicSource.OFF)
	await _frames(3)
	_check("Off in the menu: the picture again", not vis.is_on() and flat.material_override == main.screen.material
			and not film.scene_requests.has("visualiser"))
	vis.set_on(true)
	await _frames(3)
	_check("on again: the one before (%s)" % MusicSource.style, vis.is_on() and MusicSource.style == "bars")
	vis.toggle()
	await _frames(3)
	_check("toggle: off, the visualiser chosen kept", not vis.is_on() and MusicSource.style == "bars"
			and flat.material_override == main.screen.material and not vis.host.is_processing())
	_check("a step turns it on", (func() -> bool:
		vis.step(1)
		return vis.is_on()).call())
	await _frames(3)

	# A new file starts with its own picture.
	main.open_path("stub://flat_sbs")
	await _frames(4)
	_check("a new file: its picture, not the visualiser", not vis.is_on()
			and flat.material_override == main.screen.material)
	vis.set_on(true)
	await _frames(3)
	_check("3D film: the visualiser takes the whole screen with its own material", vis.is_on()
			and flat.material_override != main.screen.material)
	vis.set_on(false)

	# 360: nothing flat to draw on.
	main.open_path("stub://360_mono")
	await _frames(4)
	_check("360: not usable, no buttons", not vis.usable() and not buttons.wanted())
	vis.set_on(true)
	await _frames(2)
	_check("and on does nothing there", not vis.is_on())

	# The laser's hit goes to the buttons through the menu's pointer.
	main.open_path("stub://flat_mono")
	await _frames(20)
	var p: Vector3 = buttons.button_point("toggle")
	var hit: Dictionary = buttons.ray_hit(head, (p - head).normalized())
	_check("a ray at a button hits the panel there", not hit.is_empty() and (hit["point"] as Vector3).distance_to(p) < 0.01)
	_check("a ray past it misses", buttons.ray_hit(head, Vector3.UP).is_empty())
	main.ui.hide_panel()
	await _frames(30)
	_check("the menu closed: the buttons go", not buttons.shown() and buttons.ray_hit(head, (p - head).normalized()).is_empty())

	# A captured window's sound (scripts/play/window_audio.gd): which of the sound server's streams is recorded.
	var WindowAudio := load("res://scripts/play/window_audio.gd") as GDScript
	var node := func(serial: int, klass: String, app: Variant, binary: Variant, name := "x") -> Dictionary:
		# As JSON gives it: a float.
		var props := {"media.class": klass, "object.serial": float(serial), "node.name": name}
		if app != null:
			props["application.name"] = app
		if binary != null:
			props["application.process.binary"] = binary
		return {"id": serial, "type": "PipeWire:Interface:Node", "info": {"props": props}}
	var dump := [node.call(1, "Audio/Sink", null, null), node.call(2, "Stream/Output/Audio", null, null, "filter-chain"),
			node.call(3, "Stream/Output/Audio", "FrameCine", "framecine-engine"),
			node.call(4, "Stream/Output/Audio", "A player", "player"),
			node.call(5, "Stream/Output/Audio", "Chromium", "chrome"),
			node.call(6, "Stream/Input/Audio", "Chromium", "chrome"), {"type": "PipeWire:Interface:Link"}]
	_check("the browser's stream is the one recorded", WindowAudio.find_stream(dump) == {"serial": "5", "name": "Chromium"})
	_check("no browser: another program's", WindowAudio.find_stream(dump.slice(0, 4)) == {"serial": "4", "name": "A player"})
	_check("never the app's own, a system stream or the recorder's", WindowAudio.find_stream(dump.slice(0, 3)).is_empty()
			and WindowAudio.find_stream([node.call(7, "Stream/Output/Audio", "pw-record", "pw-record",
			WindowAudio.NODE_NAME)]).is_empty() and WindowAudio.find_stream(null).is_empty())
	var wa: Node = main.features.window_audio
	_check("a film is not a window: nothing is recorded for it", not wa._want and not wa.live)
	var analysis: Node = main.features.audio_analysis
	analysis.set_bus("no such bus")
	_check("the analysis keeps to a bus that exists", analysis.bus_name() != "no such bus")
	analysis.set_bus("")

	main.features.set_visualiser(MusicSource.DEFAULT_STYLE)
	print("test_screen_visualiser: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL %s" % what)
