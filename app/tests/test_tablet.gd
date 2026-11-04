extends SceneTree

## Tests for the tablet prototype (ui/tablet.gd) in the real main scene: where it goes for a head pose (ahead and
## below, tilted up towards the eyes, by the head's heading only), the setting, and the menu button showing it with
## the front panel where the head is, keeping it there while the head moves, and hiding it with the panel; the two
## panes; the style document (its defaults valid, partial changes from outside, bad values refused with their paths,
## only the changes kept, reset); the now playing pane (title, played / total, the bar and its hit area, a long
## title cut); the laser's ray, a touch and skipping; the fades.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_tablet.gd

const Tablet := preload("res://ui/tablet.gd")
const W := preload("res://ui/pane_widgets.gd")

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
	# The pose, for a head at 1.6 m looking down -Z.
	var head := Transform3D(Basis(), Vector3(0, 1.6, 0))
	var p := Tablet.pose(head)
	var to_eye := (head.origin - p.origin).normalized()
	_check("ahead and below the eyes (%s)" % p.origin, p.origin.z < -0.3 and p.origin.y < 1.35 and absf(p.origin.x) < 0.001)
	_check("its face points back towards the eyes (%.1f° off)" % rad_to_deg(p.basis.z.angle_to(to_eye)),
			p.basis.z.angle_to(to_eye) < deg_to_rad(15.0))
	_check("tilted TILT° from vertical", absf(rad_to_deg(p.basis.z.angle_to(Vector3.BACK)) - Tablet.TILT) < 0.1)
	_check("level side to side", absf(p.basis.x.y) < 0.001)
	_check("its top edge leans away", p.basis.y.z < 0.0 and p.basis.y.y > 0.0)
	var down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-50)), head.origin)
	_check("looking down doesn't move it", Tablet.pose(down).is_equal_approx(p))
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(90)), head.origin)
	var q := Tablet.pose(turned)
	_check("turned 90° left: it goes round with the heading (%s)" % q.origin, q.origin.x < -0.3 and absf(q.origin.z) < 0.001)

	# The setting and the menu button.
	var layer: Node = main.ui
	var tablet: Tablet = layer.tablet
	_check("off by default", not tablet.enabled and not tablet.is_shown())
	tablet.set_enabled(true)
	_check("on: saved", main.settings.get_value("pane", "tablet", false) == true)
	main.camera.global_transform = head
	layer.hide_panel() # Open at launch.
	await _frames(1)
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	await _frames(1)
	_check("menu: shown in front of the head", tablet.is_shown() and tablet.global_transform.is_equal_approx(p))
	_check("menu: the front panel opens too", layer.is_open())
	main.camera.global_transform = turned
	await _frames(2)
	_check("the head turns: it stays where it was", tablet.global_transform.is_equal_approx(p))
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	_check("menu again: hidden with the panel", not tablet.is_shown() and not layer.is_open())
	tablet.set_enabled(false)
	_check("off: the key goes", not main.settings.has_value("pane", "tablet"))
	layer.on_menu(null, true)
	layer.on_menu(null, false)
	_check("off: the menu opens only the front panel", layer.is_open() and not tablet.is_shown())

	# Two panes: a short now playing one on top, the main one below, a gap between, filling the tablet.
	var r: Dictionary = Tablet.pane_rects()
	var np: Rect2 = r["now_playing"]
	var mp: Rect2 = r["main"]
	_check("now playing on top, short", np.position.y > mp.end.y and np.size.y < mp.size.y * 0.5)
	_check("a gap of %.0f mm between them" % ((np.position.y - mp.end.y) * 1000.0),
			is_equal_approx(np.position.y - mp.end.y, Tablet.GAP))
	_check("together they fill the tablet", is_equal_approx(np.end.y - mp.position.y, Tablet.SIZE.y)
			and is_equal_approx(np.size.x, Tablet.SIZE.x) and is_equal_approx(mp.size.x, Tablet.SIZE.x))
	_check("the pane nodes sit there", tablet.now_playing.position.is_equal_approx(Vector3(0, np.get_center().y, 0))
			and tablet.main_pane.position.is_equal_approx(Vector3(0, mp.get_center().y, 0)))
	var top_mat: ShaderMaterial = tablet.now_playing.material_override
	_check("each pane's backdrop is its own size", (top_mat.get_shader_parameter("size") as Vector2).is_equal_approx(np.size))

	# The style: one JSON document, the defaults from ui/themes/tablet.json, changed from outside in part.
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(Tablet.STYLE_PATH))
	_check("the default document is valid", defaults is Dictionary and Tablet.validate(defaults).is_empty())
	var st := tablet.style()
	_check("in use: the defaults", st == defaults)
	var fill := Color.html(st["pane"]["fill"])
	var powder := Color.html("#b0e0e6")
	_check("pane fill: powder blue at 10 %%: %s" % fill, fill.is_equal_approx(Color(powder, fill.a))
			and absf(fill.a - 0.1) < 0.01)
	_check("pane border: 3 mm at 75 %", is_equal_approx(float(st["pane"]["border_width"]), 0.003)
			and absf(Color.html(st["pane"]["border"]).a - 0.75) < 0.01)
	var mat: ShaderMaterial = tablet.main_pane.material_override
	_check("both panes' shaders have it", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(fill)
			and (top_mat.get_shader_parameter("fill_color") as Color).is_equal_approx(fill)
			and is_equal_approx(float(mat.get_shader_parameter("corner_radius")), 0.024))
	var errors: Array = tablet.set_style({"pane": {"fill": "#ff000080"}, "now_playing": {"title": {"size": 0.02}}})
	_check("a partial change: no errors, the rest stays (%s)" % [errors], errors.is_empty()
			and tablet.style()["pane"]["fill"] == "#ff000080" and tablet.style()["pane"]["border"] == st["pane"]["border"]
			and is_equal_approx(float(tablet.style()["now_playing"]["title"]["size"]), 0.02))
	_check("it takes effect", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(Color.html("#ff000080"))
			and is_equal_approx(tablet.title_label.pixel_size, 0.02 / Tablet.FONT_PX))
	_check("only the changes are kept", main.settings.get_value("pane", "tablet_style", {}) == {
			"pane": {"fill": "#ff000080"}, "now_playing": {"title": {"size": 0.02}}})
	errors = tablet.set_style({"pane": {"border": "not a colour", "border_width": 0.5}, "shadow": 1,
			"now_playing": {"time": {"font": "comic"}}})
	_check("bad values: four errors with their paths, nothing changed (%s)" % [errors], errors.size() == 4
			and errors.any(func(e: Dictionary) -> bool: return e["path"] == "pane/border_width")
			and errors.any(func(e: Dictionary) -> bool: return e["path"] == "now_playing/time/font")
			and tablet.style()["pane"]["fill"] == "#ff000080")
	tablet.set_style({"pane": {"fill": null}})
	_check("null: back to the default for that value", tablet.style()["pane"]["fill"] == st["pane"]["fill"]
			and is_equal_approx(float(tablet.style()["now_playing"]["title"]["size"]), 0.02))
	tablet.reset_style()
	_check("reset: the defaults again, nothing kept", tablet.style() == st
			and not main.settings.has_value("pane", "tablet_style"))

	# Now playing: the title, played / total, and the bar.
	tablet.set_enabled(true, false)
	main.open_path("stub://flat_mono")
	await _frames(3)
	tablet.show_at(head)
	await _frames(2)
	var dur: float = main.player.get_duration()
	_check("the title is the display title (%s)" % tablet.title_label.text, tablet.title_label.text != ""
			and main.display_title().begins_with(tablet.title_label.text.trim_suffix("…")))
	_check("the time reads played / total (%s)" % tablet.time_label.text, dur <= 0.0
			or tablet.time_label.text.ends_with(" / " + W.clock(dur)))
	var bar: Rect2 = tablet.bar_rect()
	var np_rect: Rect2 = Tablet.pane_rects()["now_playing"]
	_check("the bar runs along the bottom inside the padding", bar.position.y < 0.0 and bar.size.x > np_rect.size.x * 0.8)
	_check("the title above the bar, on the left; the time on the right", tablet.title_label.position.y > bar.end.y
			and tablet.title_label.position.x < 0.0 and tablet.time_label.position.x > 0.0)
	var on_bar := tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * 0.25, bar.get_center().y, 0))
	_check("a point a quarter along the bar: 0.25", is_equal_approx(tablet.bar_fraction(on_bar), 0.25))
	var near := tablet.now_playing.to_global(Vector3(bar.end.x - 0.001, bar.get_center().y + Tablet.BAR_HIT.y * 0.9, 0))
	_check("just above it still counts", tablet.bar_fraction(near) > 0.99)
	var off := tablet.now_playing.to_global(Vector3(0, np_rect.size.y * 0.4, 0))
	_check("the title row is not the bar", tablet.bar_fraction(off) < 0.0)
	tablet.title_label.text = ""
	tablet.set("_title_full", "A very long title " .repeat(8))
	tablet.set("_title_fit", -1.0)
	tablet.call("_fit_title")
	_check("a long title is cut with an ellipsis to fit beside the time", tablet.title_label.text.ends_with("…")
			and tablet.call("_text_width", tablet.title_label, tablet.title_label.text) < np_rect.size.x * 0.8)

	# Input: the laser's ray, a touch, and skipping.
	var eye := head.origin
	var bar_mid := tablet.now_playing.to_global(Vector3(bar.position.x + bar.size.x * 0.75, bar.get_center().y, 0))
	var hit: Dictionary = tablet.ray_hit(eye, (bar_mid - eye).normalized())
	_check("a ray at the bar: the now playing pane, 0.75 along (%s)" % hit.get("fraction"), hit.get("pane") == "now_playing"
			and absf(float(hit["fraction"]) - 0.75) < 0.01 and absf(float(hit["distance"]) - eye.distance_to(bar_mid)) < 0.001)
	var main_mid := tablet.main_pane.global_position
	hit = tablet.ray_hit(eye, (main_mid - eye).normalized())
	_check("a ray at the main pane: that pane, off the bar", hit.get("pane") == "main" and float(hit["fraction"]) < 0.0)
	_check("a ray past the tablet: nothing", tablet.ray_hit(eye, Vector3.FORWARD).is_empty())
	var face: Vector3 = tablet.global_transform.basis.z
	var probe: Dictionary = tablet.poke_probe(bar_mid + face * 0.003)
	_check("a tip 3 mm over the bar: its depth and place", absf(float(probe["depth"]) - 0.003) < 0.0005
			and absf(float(probe["fraction"]) - 0.75) < 0.01)
	if main.player.can_seek() and dur > 0.0:
		_check("skipping to 0.5", tablet.seek_to(0.5))
		await _frames(3)
		_check("the film is half way (%.1f of %.1f)" % [main.player.get_position(), dur],
				absf(main.player.get_position() - dur * 0.5) < maxf(2.0, dur * 0.02))

	# Fades.
	_check("showing fades in", tablet.visible)
	await create_timer(float(st["fade"]["in"]) + 0.15).timeout
	_check("faded in", is_equal_approx(float(top_mat.get_shader_parameter("opacity")), 1.0)
			and absf(tablet.title_label.modulate.a - Color.html(st["now_playing"]["title"]["color"]).a) < 0.01)
	tablet.hide_tablet()
	_check("hiding: not shown at once, still visible while it fades", not tablet.is_shown() and tablet.visible)
	await create_timer(float(st["fade"]["out"]) + 0.15).timeout
	_check("faded out: hidden", not tablet.visible and float(top_mat.get_shader_parameter("opacity")) < 0.01)
	print("test_tablet: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
