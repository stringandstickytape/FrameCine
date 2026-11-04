extends SceneTree

## Tests for the tablet prototype (ui/tablet.gd) in the real main scene: where it goes for a head pose (ahead and
## below, tilted up towards the eyes, by the head's heading only), the setting, and the menu button showing it with
## the front panel where the head is, keeping it there while the head moves, and hiding it with the panel; its style
## (the theme's defaults, partial changes from outside, bad values refused, kept, reset).
## Run: godot --headless --xr-mode off --path app --script res://tests/test_tablet.gd

const Tablet := preload("res://ui/tablet.gd")

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

	# The style: the theme's defaults, changed from outside in part, checked, kept, and back to the theme's.
	var st := tablet.style()
	var powder := Color(0.69, 0.878, 0.902)
	var fill: Color = st["fill"]
	_check("default fill: powder blue at 50 %%: %s" % fill, absf(fill.r - powder.r) < 0.01 and absf(fill.g - powder.g) < 0.01
			and absf(fill.b - powder.b) < 0.01 and absf(fill.a - 0.5) < 0.01)
	_check("default border: 75 %% opaque", absf((st["border"] as Color).a - 0.75) < 0.01)
	_check("default corner and border in metres", is_equal_approx(float(st["corner_radius"]), 0.024)
			and is_equal_approx(float(st["border_width"]), 0.006))
	var mat: ShaderMaterial = (tablet.get_node("Quad") as MeshInstance3D).material_override
	_check("the shader has them", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(st["fill"])
			and is_equal_approx(float(mat.get_shader_parameter("corner_radius")), 0.024))
	var errors: Array = tablet.set_style({"fill": "#ff000080", "corner_radius": 0.05})
	_check("a partial change: no errors, the rest stays", errors.is_empty()
			and (tablet.style()["fill"] as Color).is_equal_approx(Color("#ff000080"))
			and is_equal_approx(float(tablet.style()["border_width"]), 0.006))
	_check("the shader follows", (mat.get_shader_parameter("fill_color") as Color).is_equal_approx(Color("#ff000080"))
			and is_equal_approx(float(mat.get_shader_parameter("corner_radius")), 0.05))
	_check("kept in the settings as text", str((main.settings.get_value("pane", "tablet_style", {}) as Dictionary)
			.get("fill", "")) == "#ff000080")
	errors = tablet.set_style({"border": "not a colour", "border_width": 0.5, "shadow": 1})
	_check("bad values: three errors, nothing changed (%s)" % [errors], errors.size() == 3
			and (tablet.style()["fill"] as Color).is_equal_approx(Color("#ff000080")))
	tablet.set_style({"fill": null})
	_check("null: back to the theme's for that key", (tablet.style()["fill"] as Color).is_equal_approx(st["fill"])
			and is_equal_approx(float(tablet.style()["corner_radius"]), 0.05))
	tablet.reset_style()
	_check("reset: the theme's again, nothing kept", tablet.style() == st
			and not main.settings.has_value("pane", "tablet_style"))
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
