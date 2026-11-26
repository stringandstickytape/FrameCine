extends RefCounted

## M1 Grand Tour — 2004 British Grand Tourer interior (app/environments/m1_grand_tour.env.json;
## docs/environments/rooms/m1_grand_tour.md). Built by Gemini 4 Neon Extra High.
## Sculpted in Blender (res://environments/m1_grand_tour/gt_2004_interior.glb, CC0 1.0) into 8 VR-optimised
## material groups with metre-scale automotive UVs and baked 24-ray BVH crevice/contact ambient occlusion
## in vertex colours (COLOR_0), wired onto FrameCine's house, clearcoat/chrome reflection, and lamp shaders:
##   - Sleek curved GT saloon greenhouse: slim raked A/B/C pillars, seamless trapezoidal side windows with
##     chrome daylight-opening brightwork & rubber seals, sculpted power-domed GT bonnet & wing mirrors
##   - Iconic twin-wing stitched-hide & book-matched burr-walnut dashboard flowing into sweeping walnut door cards
##   - Four gleaming knurled-chrome bullseye vents + turned-chrome organ-stop pull plungers
##   - Central chrome-bezel analogue clock (`PieceClock`, live system time, zero watch branding)
##   - Hooded RHD 4-gauge chrome-ringed instrument binnacle with live animated speedo/tacho needles & 4-spoke
##     Beluga leather steering wheel (unbranded hub!), alloy shift paddles & drilled sport pedals
##   - Sloping burr-walnut centre waterfall with 4+4 chrome-rimmed soft keys framing a LIVE SYNCED auxiliary
##     `DashScreen` (mirrors `Flat.material_override` directly — 1 quad, 2 tris, 1 draw, zero extra SubViewports!)
##   - Natural automotive-position reclined cobra front bucket seats (strictly empty!) + plush 3-across rear bench
##     (dead-centre seat at (0, 0, 0)) + cantilevered walnut-and-alloy rear cinema screen stanchion
##   - Animated twin front wipers + wet laminated windscreen with live swept clear-arc mask
##   - Three instant live-switchable Crewe trims: Saddle & Burr Walnut, Beluga & Dark Walnut, Oxblood & Dark Walnut
##   - Zero trademarks/logos, zero people, static tinted mirrors only, zero live lights.

const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const Reflect := preload("res://scripts/env/systems/kit/reflect.gd")
const WINDSCREEN_SHADER := preload("res://shaders/env_gt_windscreen.gdshader")

const GLB_PATH := "res://environments/m1_grand_tour/gt_2004_interior.glb"
const PIECES: Array[String] = ["gt_2004_cabin", "gt_2004_dash"]

const DOME_WARM := Color(1.0, 0.88, 0.68)
const COVE_COOL := Color(0.86, 0.92, 1.0)
const PAINT_TEMPEST := Color(0.11, 0.145, 0.185)

## Three Crewe coachbuilt trims (live-applied to GT_mat_hide and GT_mat_walnut without rebuilding!).
const TRIMS := {
	"saddle":  {"hide": Color(0.77, 0.67, 0.53), "walnut": Color(0.28, 0.125, 0.055)},
	"beluga":  {"hide": Color(0.14, 0.16, 0.21), "walnut": Color(0.18, 0.092, 0.055)},
	"oxblood": {"hide": Color(0.46, 0.10, 0.12), "walnut": Color(0.20, 0.095, 0.058)},
}

## Static immutable geometry & anchor cache parsed once from the CC0 .glb so room rebuilds take < 2 ms!
static var _glb_cache: Dictionary = {}


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	match piece:
		"gt_2004_cabin":
			_build_cabin(c)
		"gt_2004_dash":
			_build_dash_and_live(c)


static func _load_glb() -> Dictionary:
	if not _glb_cache.is_empty():
		return _glb_cache
	var bytes := FileAccess.get_file_as_bytes(GLB_PATH)
	if bytes.is_empty():
		push_error("m1_grand_tour: missing GLB asset at %s" % GLB_PATH)
		return {}
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		push_error("m1_grand_tour: failed to parse %s (err=%d)" % [GLB_PATH, err])
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		push_error("m1_grand_tour: generate_scene returned null for %s" % GLB_PATH)
		return {}
	var meshes := {}
	var anchors := {}
	_collect_nodes(scene, Transform3D.IDENTITY, meshes, anchors)
	scene.free()
	_glb_cache = {"meshes": meshes, "anchors": anchors}
	return _glb_cache


static func _collect_nodes(node: Node, parent_xf: Transform3D, meshes: Dictionary, anchors: Dictionary) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var slot := _canonical_slot(node.name)
		meshes[slot] = {"mesh": (node as MeshInstance3D).mesh, "xf": xf}
	elif node is Node3D and not node.name.begins_with("GT_") and node.get_child_count() == 0:
		anchors[str(node.name)] = xf
	for child in node.get_children():
		_collect_nodes(child, xf, meshes, anchors)


static func _canonical_slot(raw: String) -> String:
	for k: String in ["GT_mat_hide", "GT_mat_walnut", "GT_mat_soft_trim", "GT_mat_hard_trim",
			"GT_mat_metal", "GT_mat_paint", "GT_mat_dome", "GT_mat_cove"]:
		if raw.begins_with(k):
			return k
	return raw


static func _house_uv_ao(c: Object, lib_id: String, col: Color, uv_repeat: Vector2,
		rough_scale := 0.9, norm_str := 0.6, ao_str := 0.45,
		reflect_metal := -1.0, reflect_amount := 0.0, reflect_rough := 0.14, reflect_flat := true) -> ShaderMaterial:
	var light: Node = c.kit._light
	var d := {"library": lib_id, "color": [col.r, col.g, col.b]}
	var m: ShaderMaterial = light.from_param(d, reflect_metal >= 0.0)
	m.set_shader_parameter("use_mesh_uv", true)
	m.set_shader_parameter("uv_repeat", uv_repeat)
	m.set_shader_parameter("instance_tint", true)
	m.set_shader_parameter("roughness_scale", rough_scale)
	m.set_shader_parameter("normal_strength", norm_str)
	m.set_shader_parameter("ao_strength", ao_str)
	if reflect_metal >= 0.0:
		Reflect.make(m, reflect_metal, reflect_amount, reflect_rough, reflect_flat)
		c.kit._reflect.append(m)
	return m


static func _mats(c: Object) -> Dictionary:
	var room: Node = c.room
	if room.has_meta("gt_mats"):
		return room.get_meta("gt_mats")
	var light: Node = c.kit._light
	var m := {
		"GT_mat_hide": _house_uv_ao(c, "brown_leather", TRIMS["saddle"]["hide"], Vector2(4.4, 4.4), 0.84, 0.34, 0.40),
		"GT_mat_walnut": _house_uv_ao(c, "walnut_veneer", TRIMS["saddle"]["walnut"], Vector2(2.4, 2.4), 0.36, 0.65, 0.85, 0.0, 0.38, 0.14, false),
		"GT_mat_soft_trim": _house_uv_ao(c, "black_leather", Color.WHITE, Vector2(3.6, 3.6), 0.92, 0.32, 0.35),
		"GT_mat_hard_trim": _house_uv_ao(c, "dark_metal", Color.WHITE, Vector2(2.0, 2.0), 0.85, 0.25, 0.35),
		"GT_mat_metal": _house_uv_ao(c, "brushed_steel", Color.WHITE, Vector2(2.2, 2.2), 0.25, 0.20, 0.15, 0.96, 0.88, 0.10, true),
		"GT_mat_paint": _house_uv_ao(c, "dark_metal", PAINT_TEMPEST, Vector2(1.5, 1.5), 0.32, 0.12, 0.20, 0.18, 0.78, 0.12, true),
		"GT_mat_dome": light.lamp_material(DOME_WARM, 1.45, 0.85, "house"),
		"GT_mat_cove": light.lamp_material(COVE_COOL, 1.15, 0.30, "accent"),
	}
	# Aliases for trim live-switching in GtLiveRig
	m["hide"] = m["GT_mat_hide"]
	m["walnut"] = m["GT_mat_walnut"]
	room.set_meta("gt_mats", m)
	return m


static func _build_cabin(c: Object) -> void:
	var data := _load_glb()
	if data.is_empty():
		return
	var mats := _mats(c)
	var holder := GtInteriorHolder.new()
	holder.setup(data["meshes"], mats)
	c.halls.append(holder)

	# Warm subtle top-down cabin stand-in lamps (0 live lights — shader stand-ins + hidden bake lights!)
	c.lamps.append([Vector3(0.0, 1.40, -1.28), DOME_WARM, 0.55])
	c.lamps.append([Vector3(0.0, 1.44, -0.18), DOME_WARM, 0.50])


static func _build_dash_and_live(c: Object) -> void:
	var data := _load_glb()
	if data.is_empty():
		return
	var anchors: Dictionary = data["anchors"]
	var mats := _mats(c)

	# 1. Live System-Time Central Chrome Analogue Clock (`PieceClock` mounted directly on ClockAnchor!)
	var clk_xf: Transform3D = anchors.get("ClockAnchor", Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(0.0, 0.942, -1.708)))
	var clk_n: Vector3 = clk_xf.basis.z.normalized()
	var clk_u: Vector3 = clk_xf.basis.x.normalized() * 0.0255
	var clk_v: Vector3 = clk_xf.basis.y.normalized() * 0.0255
	c.clocks.append([clk_xf.origin + clk_n * 0.002, clk_u, clk_v, clk_n])

	# 2. Live Interactive GT Cockpit Rig (`DashScreen`, live speedo/tacho needles, wet windscreen & front wipers!)
	var rig := GtLiveRig.new()
	rig.name = "GtLiveRig"
	rig.setup_rig(c.room, mats, anchors)
	c.halls.append(rig)


# --- Static Holder for the 8-draw Blender GLB Interior --------------------------------------------------------------

class GtInteriorHolder extends RefCounted:
	var _meshes: Dictionary
	var _mats: Dictionary

	func setup(meshes: Dictionary, mats: Dictionary) -> void:
		_meshes = meshes
		_mats = mats

	func finish(kit: Node) -> void:
		var root := Node3D.new()
		root.name = "GtInterior"
		kit.own(root)
		for slot: String in _meshes:
			var entry: Dictionary = _meshes[slot]
			var mi := MeshInstance3D.new()
			mi.name = slot
			mi.mesh = entry["mesh"] as Mesh
			mi.transform = entry["xf"] as Transform3D
			mi.material_override = _mats.get(slot, _mats["GT_mat_hard_trim"])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)

	func tick(_delta: float) -> void:
		pass


# --- Live GT Cockpit Rig (DashScreen mirror, animated front wipers, live gauges & instant trim tinting!) ------------

class GtLiveRig extends Node3D:
	var _room: Node
	var _mats: Dictionary
	var _dash_screen: MeshInstance3D
	var _dash_standby_mat: StandardMaterial3D
	var _windscreen_mat: ShaderMaterial
	var _wiper_l: Node3D
	var _wiper_r: Node3D
	var _needle_speedo: Node3D
	var _needle_tacho: Node3D
	var _last_trim := ""
	var _time := 0.0
	var _base_hide_tint := Color.WHITE
	var _base_walnut_tint := Color.WHITE
	var demo_film_mat: Material = null

	func finish(kit: Node) -> void:
		kit.own(self)
		var hm := _mats["hide"] as ShaderMaterial
		var wm := _mats["walnut"] as ShaderMaterial
		if hm != null and hm.get_shader_parameter("tint") is Color:
			_base_hide_tint = hm.get_shader_parameter("tint")
		if wm != null and wm.get_shader_parameter("tint") is Color:
			_base_walnut_tint = wm.get_shader_parameter("tint")
		tick(0.0)

	func setup_rig(room: Node, mats: Dictionary, anchors: Dictionary) -> void:
		_room = room
		_mats = mats

		# 1. Twin Synced Auxiliary DashScreen (1 quad, 2 tris, 1 draw — mirrors `Flat.material_override`!)
		_dash_standby_mat = StandardMaterial3D.new()
		_dash_standby_mat.albedo_color = Color(0.025, 0.032, 0.044)
		_dash_standby_mat.roughness = 0.12
		_dash_standby_mat.emission_enabled = true
		_dash_standby_mat.emission = Color(0.04, 0.07, 0.12)
		_dash_standby_mat.emission_energy_multiplier = 0.55

		var ds_xf: Transform3D = anchors.get("DashScreenAnchor",
				Transform3D(Basis(Vector3.RIGHT, -0.50), Vector3(0.0, 0.770, -1.619)))
		var dsq := QuadMesh.new()
		dsq.size = Vector2(0.156, 0.088)
		_dash_screen = MeshInstance3D.new()
		_dash_screen.name = "DashScreen"
		_dash_screen.mesh = dsq
		_dash_screen.material_override = _dash_standby_mat
		_dash_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dash_screen.transform = Transform3D(ds_xf.basis, ds_xf.origin + ds_xf.basis.z * 0.002)
		add_child(_dash_screen)

		# 2. Live Glowing Amber-Red Speedometer & Tachometer Needles mounted on exact Binnacle Pivots!
		var needle_mat := StandardMaterial3D.new()
		needle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		needle_mat.albedo_color = Color(1.0, 0.28, 0.10)
		var nm := BoxMesh.new()
		nm.size = Vector3(0.0042, 0.043, 0.0028)

		var tacho_xf: Transform3D = anchors.get("TachoPivot",
				Transform3D(Basis(Vector3.RIGHT, -0.175), Vector3(0.326, 0.944, -1.819)))
		var tacho_mount := Node3D.new()
		tacho_mount.transform = Transform3D(tacho_xf.basis, tacho_xf.origin + tacho_xf.basis.z * 0.002)
		add_child(tacho_mount)
		_needle_tacho = Node3D.new()
		_needle_tacho.name = "TachoNeedle"
		var nt_m := MeshInstance3D.new()
		nt_m.mesh = nm
		nt_m.material_override = needle_mat
		nt_m.position = Vector3(0.0, 0.017, 0.0)
		nt_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_needle_tacho.add_child(nt_m)
		tacho_mount.add_child(_needle_tacho)

		var speedo_xf: Transform3D = anchors.get("SpeedoPivot",
				Transform3D(Basis(Vector3.RIGHT, -0.175), Vector3(0.554, 0.944, -1.819)))
		var speedo_mount := Node3D.new()
		speedo_mount.transform = Transform3D(speedo_xf.basis, speedo_xf.origin + speedo_xf.basis.z * 0.002)
		add_child(speedo_mount)
		_needle_speedo = Node3D.new()
		_needle_speedo.name = "SpeedoNeedle"
		var ns_m := MeshInstance3D.new()
		ns_m.mesh = nm
		ns_m.material_override = needle_mat
		ns_m.position = Vector3(0.0, 0.017, 0.0)
		ns_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_needle_speedo.add_child(ns_m)
		speedo_mount.add_child(_needle_speedo)

		# 3. Raked Laminated Windscreen Pane (`env_gt_windscreen.gdshader` — wet rain + live wiped dry-arc mask!)
		var ws_xf: Transform3D = anchors.get("WindscreenAnchor",
				Transform3D(Basis(Vector3.RIGHT, 0.772), Vector3(0.0, 1.202, -1.780)))
		var wsq := QuadMesh.new()
		wsq.size = Vector2(1.52, 0.82)
		_windscreen_mat = ShaderMaterial.new()
		_windscreen_mat.shader = WINDSCREEN_SHADER
		var ws_mi := MeshInstance3D.new()
		ws_mi.name = "WindscreenGlass"
		ws_mi.mesh = wsq
		ws_mi.material_override = _windscreen_mat
		ws_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ws_mi.transform = ws_xf
		ws_mi.add_to_group("env_see_through")
		add_child(ws_mi)

		# 4. Twin Physical Animated Front Wiper Arms mounted cleanly outside bottom windscreen cowl!
		var w_mat := StandardMaterial3D.new()
		w_mat.albedo_color = Color(0.045, 0.048, 0.055)
		w_mat.roughness = 0.45
		var arm_m := BoxMesh.new()
		arm_m.size = Vector3(0.56, 0.015, 0.013)
		for idx in 2:
			var aname := "WiperLeftPivot" if idx == 0 else "WiperRightPivot"
			var fallback := Transform3D(ws_xf.basis, Vector3(-0.38 if idx == 0 else 0.24, 0.925, -2.085))
			var axf: Transform3D = anchors.get(aname, fallback)
			var mount := Node3D.new()
			mount.transform = axf
			add_child(mount)
			var piv := Node3D.new()
			piv.name = "WiperLeft" if idx == 0 else "WiperRight"
			var blade := MeshInstance3D.new()
			blade.mesh = arm_m
			blade.material_override = w_mat
			blade.position = Vector3(0.28, 0.0, 0.0)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			piv.add_child(blade)
			mount.add_child(piv)
			if idx == 0:
				_wiper_l = piv
			else:
				_wiper_r = piv

	func tick(delta: float) -> void:
		_time += delta
		var host: Node = _room.get("host") if is_instance_valid(_room) else null

		# A. Instant Crewe Trim tinting (saddle / beluga / oxblood)
		var trim := "saddle"
		if host != null and host.get("settings") is Dictionary:
			trim = str((host.settings as Dictionary).get("trim", "saddle"))
		if trim != _last_trim and TRIMS.has(trim):
			_last_trim = trim
			var td: Dictionary = TRIMS[trim]
			var s0: Dictionary = TRIMS["saddle"]
			var h_c: Color = td["hide"]
			var w_c: Color = td["walnut"]
			var h0: Color = s0["hide"]
			var w0: Color = s0["walnut"]
			var ht := Color(_base_hide_tint.r * (h_c.r / maxf(h0.r, 0.01)),
					_base_hide_tint.g * (h_c.g / maxf(h0.g, 0.01)),
					_base_hide_tint.b * (h_c.b / maxf(h0.b, 0.01)))
			var wt := Color(_base_walnut_tint.r * (w_c.r / maxf(w0.r, 0.01)),
					_base_walnut_tint.g * (w_c.g / maxf(w0.g, 0.01)),
					_base_walnut_tint.b * (w_c.b / maxf(w0.b, 0.01)))
			(_mats["hide"] as ShaderMaterial).set_shader_parameter("tint", ht)
			(_mats["walnut"] as ShaderMaterial).set_shader_parameter("tint", wt)

		# B. Twin Live Video Screen Mirror (`DashScreen` mirrors `Flat.material_override` directly!)
		var synced := false
		if demo_film_mat != null:
			if _dash_screen.material_override != demo_film_mat:
				_dash_screen.material_override = demo_film_mat
			synced = true
		elif host != null and host.has_method("main_node"):
			var m_node: Node = host.call("main_node")
			if m_node != null and m_node.get("screen") != null:
				var flat := (m_node.screen as Node).get_node_or_null("Flat") as MeshInstance3D
				if flat != null and flat.material_override != null and flat.is_visible_in_tree():
					if _dash_screen.material_override != flat.material_override:
						_dash_screen.material_override = flat.material_override
					synced = true
		if not synced and _dash_screen.material_override != _dash_standby_mat:
			_dash_screen.material_override = _dash_standby_mat

		# C. Live Motorway Telemetry -> Speedo Needle, Tacho Needle, Animated Front Wipers & Wet Windscreen Clear-Arc!
		var mph := 0.0
		var rain := 0.0
		var wet := 0.0
		var wphase := 0.0
		var day_l := 0.55
		var mw: Node = host.system("motorway") if host != null and host.has_method("system") else null
		if mw != null:
			mph = float(mw.call("speed_mph"))
			rain = float(mw.call("rain_level"))
			wet = float(mw.call("wet_level"))
			wphase = float(mw.call("wiper_phase"))
			day_l = float(mw.get("_day_level"))

		# 200 mph speedometer arc (-130 deg at 0 mph -> +130 deg at 200 mph; 70 mph = -39 deg!)
		var speedo_deg := lerpf(-130.0, 130.0, clampf(mph / 200.0, 0.0, 1.0))
		# 7000 rpm tachometer arc (700 rpm idle = -104 deg -> 1780 rpm cruise @ 70 mph = -64 deg!)
		var rpm := lerpf(700.0, 1780.0, clampf(mph / 70.0, 0.0, 1.0))
		var tacho_deg := lerpf(-130.0, 130.0, clampf(rpm / 7000.0, 0.0, 1.0))
		_needle_speedo.rotation.z = -deg_to_rad(speedo_deg)
		_needle_tacho.rotation.z = -deg_to_rad(tacho_deg)

		# Physical front wiper arm sweep synced 1:1 with `env_gt_windscreen.gdshader`!
		var cyc := fposmod(wphase, 1.0)
		var s_pos := smoothstep(0.04, 0.46, cyc) if cyc < 0.5 else (1.0 - smoothstep(0.54, 0.96, cyc))
		var w_ang := lerpf(0.14, 2.24, s_pos) if rain > 0.06 else 0.10
		_wiper_l.rotation.z = w_ang
		_wiper_r.rotation.z = w_ang

		_windscreen_mat.set_shader_parameter("rain", rain)
		_windscreen_mat.set_shader_parameter("wet", wet)
		_windscreen_mat.set_shader_parameter("wiper_phase", wphase)
		_windscreen_mat.set_shader_parameter("day_level", day_l)
		_windscreen_mat.set_shader_parameter("time_sec", _time)
