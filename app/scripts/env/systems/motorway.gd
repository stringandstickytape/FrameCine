extends "res://scripts/env/systems/env_system.gd"

## Streaming real-world British motorway corridor (docs/environments/motorway.md): built offline from open geographic
## data (OpenStreetMap, GEDTM30 bare-earth elevation, ESA WorldCover land cover) and baked UK TSRGD road signs.
## The viewer never moves; the curved 6-lane motorway, real-DEM rolling terrain, alpha-cutout British trees & hedgerows,
## retroreflective UK signs, SOX/SON streetlamps, real OSM overbridges, iconic landmarks and motorway traffic stream
## smoothly past the windscreen and side windows at authentic British motorway cruising speed (~70 mph, scaled by
## comfort.motion, paused when the film pauses).

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvSignals := preload("res://scripts/env/env_signals.gd")
const ROAD_SHADER := preload("res://shaders/env_motorway_road.gdshader")
const TERRAIN_SHADER := preload("res://shaders/env_motorway_terrain.gdshader")
const TREES_SHADER := preload("res://shaders/env_motorway_trees.gdshader")
const SIGNS_SHADER := preload("res://shaders/env_motorway_signs.gdshader")
const PROPS_SHADER := preload("res://shaders/env_motorway_props.gdshader")
const HALO_SHADER := preload("res://shaders/env_motorway_halo.gdshader")

const CRUISE_MPS := 31.2928 # 70.0 mph authentic UK motorway speed
const CURVE_SLOTS := 32
const Z_BACK := 32.0
const Z_FRONT := -182.0
const Z_SPAN := Z_BACK - Z_FRONT # 214.0 m
const LATERAL_WORLD := [-168.0, -118.0, -72.0, -38.0, -16.0, 0.0, 29.0, 52.0, 86.0, 128.0, 174.0]
const STRIP_RECORD_BYTES := 76

const START_PRESETS := {
	"london_j1": 800.0,
	"chilterns_j10": 37400.0,
	"watford_gap_j16": 99200.0,
	"leicester_j21": 143100.0,
	"ratcliffe_j24": 175900.0,
	"sheffield_j33": 244200.0,
	"leeds_j47": 305200.0,
}

const TIME_MODES: Array[String] = ["morning", "afternoon", "golden", "dusk", "night", "progress"]
const WEATHER_MODES: Array[String] = ["mixed", "clear", "overcast", "fog", "rain", "storm"]

static var _route_cache := {}
static var _tex_cache := {}


static func spec() -> Dictionary:
	return {
		"kind": "journey",
		"moves_viewer": false,
		"description": "Real-world streaming British motorway corridor (M1 London J1 to Leeds J48) driven by pre-baked "
				+ "OSM alignment, GEDTM30 elevation, ESA WorldCover land cover and pixel-exact UK TSRGD road signs. "
				+ "Cruises at authentic 70 mph (scaled by Motion, held on pause) with per-stretch SOX/SON lighting, "
				+ "central barrier variety, traffic, landmarks, day/night progression, weather and live overbridge "
				+ "audio occlusion.",
		"params": {
			"route_bin": {"type": "string", "default": "res://environments/routes/m1_route.bin",
					"description": "binary corridor strip (elevation, curvature, WorldCover RGB, flags)"},
			"route_meta": {"type": "string", "default": "res://environments/routes/m1_route_meta.json",
					"description": "JSON metadata (junctions, services, overbridges, skyline, landmarks)"},
			"sign_atlas": {"type": "string", "default": "res://environments/routes/m1_signs_atlas.png",
					"description": "baked UK TSRGD motorway sign texture atlas"},
			"sign_meta": {"type": "string", "default": "res://environments/routes/m1_signs_atlas.json",
					"description": "UV and millimetre sizing metadata for the UK sign atlas"},
			"tree_atlas": {"type": "string", "default": "res://environments/routes/uk_trees_impostors.png",
					"description": "4x4 alpha-cutout British trees and hedgerows impostor atlas"},
			"start_at": {"type": "enum", "values": START_PRESETS.keys(), "default": "chilterns_j10", "live": true,
					"description": "starting junction along the M1 corridor"},
			"direction": {"type": "enum", "values": ["northbound", "southbound"], "default": "northbound", "live": true,
					"description": "direction of travel along the motorway"},
			"time_mode": {"type": "enum", "values": TIME_MODES, "default": "golden", "live": true,
					"description": "fixed time of day or smooth progression across the drive"},
			"weather_mode": {"type": "enum", "values": WEATHER_MODES, "default": "mixed", "live": true,
					"description": "British motorway weather preset or organic mixed drive"},
			"traffic": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.72, "live": true,
					"description": "motorway traffic density (Lane 1 slower vehicles + oncoming carriageway)"},
			"speed_scale": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
					"description": "speed multiplier (bound to comfort.motion)"},
			"flicker_allowed": {"type": "bool", "default": true, "live": true,
					"description": "whether distant soft cloud-sheet lightning glows during thunderstorms"},
			"headlights": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true,
					"description": "headlight beam intensity when dusk, night, fog or rain calls for them"},
		},
		"actions": {
			"jump_km": "jump to a chainage in kilometres (args: km)",
		},
		"cost": {"draws": 7, "triangles": 16000, "lights": 0, "particles": 0, "texture_mb": 14},
	}


static func comfort_for(_p: Dictionary) -> Array:
	return []


# --- Route & Atlas data -----------------------------------------------------------------------------------------------

var _n_samples := 0
var _step_m := 100.0
var _total_len_m := 310000.0
var _heading := PackedFloat32Array()
var _curv := PackedFloat32Array()
var _elev := PackedFloat32Array()
var _grade := PackedFloat32Array()
var _dh := PackedFloat32Array()       # n_samples * 11 (metres)
var _rgb := PackedByteArray()         # n_samples * 33
var _flags := PackedInt32Array()      # n_samples
var _urban := PackedByteArray()       # n_samples
var _vmist := PackedByteArray()       # n_samples

var _overbridges: Array = []          # [{s, width, skew, kind, name}]
var _skyline: Array = []              # [{s, lat, kind, h}]
var _landmarks: Array = []            # [{id, name, s, lat, kind}]
var _signs_nb: Array = []             # [{s, x, y, w, h, key, is_gantry, matrix}]
var _signs_sb: Array = []             # [{s, x, y, w, h, key, is_gantry, matrix}]
var _atlas_uv := {}                   # key -> {uv: Vector4, w_m: float, h_m: float, kind: String}

# --- Scene nodes & materials ------------------------------------------------------------------------------------------

var _root: Node3D
var _road_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _trees_mat: ShaderMaterial
var _signs_mat: ShaderMaterial
var _props_mat: ShaderMaterial
var _halo_mat: ShaderMaterial

var _h_img: Image
var _h_tex: ImageTexture
var _c_img: Image
var _c_tex: ImageTexture

var _trees_mm: MultiMesh
var _signs_mm: MultiMesh
var _boxes_mm: MultiMesh
var _cyls_mm: MultiMesh
var _halos_mm: MultiMesh

var _curve_prof: Array[Vector4] = []
var _curve_x := PackedFloat32Array()
var _curve_y := PackedFloat32Array()

# --- Live driving & weather state -------------------------------------------------------------------------------------

var _s_now := 37400.0
var _odom := 0.0
var _dir := 1.0
var _speed_mps := 0.0
var _drive_time := 0.0
var _terrain_baked_s := -1e9
var _placed := false

var _day_level := 0.65
var _wet_level := 0.0
var _rain_level := 0.0
var _fog_density := 0.06
var _headlight_now := 0.0
var _wiper_phase := 0.0
var _under_bridge := false
var _bridge_shelter := 1.0
var _last_bridge_idx := -1
var _matrix_active := false
var _lightning := 0.0
var _lightning_timer := 0.0
var _next_lightning := 9.0
var _thunder_delay := -1.0
var _last_start_key := ""
var _last_dir_key := ""
var _nearest_sign := ""
var _rng := RandomNumberGenerator.new()
var _box_i := 0
var _cyl_i := 0
var _sign_i := 0
var _tree_i := 0
var _halo_i := 0
var _lamp_on_now := 0.0


func setup() -> void:
	_rng.seed = 20040101
	_load_route_data()
	_load_sign_atlas_meta()
	_build_sign_schedules()

	_root = Node3D.new()
	_root.name = "MotorwayCorridor"
	own(_root)

	_curve_prof.resize(CURVE_SLOTS)
	_curve_x.resize(CURVE_SLOTS)
	_curve_y.resize(CURVE_SLOTS)

	_build_road_mesh()
	_build_terrain_mesh()
	_build_trees_multimesh()
	_build_signs_multimesh()
	_build_props_multimeshes()

	_apply_start_preset(true)
	_update_environment(0.0)
	_rebuild_curve_profile()
	_update_terrain_textures(true)
	_populate_instances(0.0)


func _apply_start_preset(force := false) -> void:
	var sk := str(params.get("start_at", "chilterns_j10"))
	var dk := str(params.get("direction", "northbound"))
	if not force and sk == _last_start_key and dk == _last_dir_key:
		return
	_last_start_key = sk
	_last_dir_key = dk
	_dir = -1.0 if dk == "southbound" else 1.0
	_s_now = clampf(float(START_PRESETS.get(sk, 37400.0)), 400.0, _total_len_m - 400.0)
	_terrain_baked_s = -1e9
	_last_bridge_idx = -1


func _param_changed(param: String, _value: Variant) -> void:
	if param == "start_at" or param == "direction":
		_apply_start_preset(false)
		_rebuild_curve_profile()
		_update_terrain_textures(true)
		_populate_instances(0.0)
	elif param == "time_mode" or param == "weather_mode":
		_update_environment(0.0)
		_populate_instances(0.0)


func act(action: String, args: Dictionary) -> void:
	if action == "jump_km":
		_s_now = clampf(float(args.get("km", 37.4)) * 1000.0, 400.0, _total_len_m - 400.0)
		_terrain_baked_s = -1e9
		_last_bridge_idx = -1
		_rebuild_curve_profile()
		_update_terrain_textures(true)
		_populate_instances(0.0)


func tick(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.2)
	_drive_time += dt

	# Determine target cruising speed: authentic 70 mph while playing/starting/credits, scaled by Motion; pauses cleanly!
	var motion_scale := float(params.get("speed_scale", 1.0))
	if host != null and host.signals != null:
		motion_scale *= float(host.signals.values.get("comfort.motion", 1.0))
	var state := "preshow"
	if host != null and host.get("timeline") != null:
		state = str(host.timeline.state)
	# Cruise naturally in preshow too (gentle 52 mph arrival/approach, full 70 mph during film; pauses cleanly when paused!)
	var want_mps := 0.0
	if state == "paused":
		want_mps = 0.0
	elif state in ["starting", "playing", "credits"]:
		want_mps = CRUISE_MPS * clampf(motion_scale, 0.0, 1.0)
	else:
		want_mps = CRUISE_MPS * 0.78 * clampf(motion_scale, 0.0, 1.0)
	if not _placed:
		_speed_mps = want_mps
		_placed = true
	else:
		_speed_mps = move_toward(_speed_mps, want_mps, 7.5 * dt)

	_s_now += _dir * _speed_mps * dt
	_odom += _speed_mps * dt
	# Gentle loop wrap only after full 310 km run
	if _s_now > _total_len_m - 400.0:
		_s_now = 600.0
		_terrain_baked_s = -1e9
		_last_bridge_idx = -1
	elif _s_now < 400.0:
		_s_now = _total_len_m - 600.0
		_terrain_baked_s = -1e9
		_last_bridge_idx = -1

	_update_environment(dt)
	_update_overbridge_audio(dt)
	_rebuild_curve_profile()
	if absf(_s_now - _terrain_baked_s) >= 4.0:
		_update_terrain_textures(false)
	_populate_instances(dt)

	# Publish standard journey & weather channels to bindings (dash speedo, GT W12 audio, rain beds, wiper shader)
	if host != null and host.signals != null:
		var vals: Dictionary = host.signals.values
		vals["journey.speed"] = clampf(_speed_mps / CRUISE_MPS, 0.0, 1.0)
		vals["journey.progress"] = clampf(_s_now / maxf(_total_len_m, 1.0), 0.0, 1.0)
		vals["weather.rain"] = _rain_level
		vals["weather.wet"] = _wet_level


# --- Public telemetry for GT cabin (speedo needle, wipers, wet windscreen) & tests ------------------------------------

func current_km() -> float:
	return _s_now * 0.001


func speed_mph() -> float:
	return _speed_mps * 2.236936


func rain_level() -> float:
	return _rain_level


func wet_level() -> float:
	return _wet_level


func wiper_phase() -> float:
	return _wiper_phase


func under_bridge() -> bool:
	return _under_bridge


func bridge_shelter() -> float:
	return _bridge_shelter


func matrix_active() -> bool:
	return _matrix_active


func lightning_glow() -> float:
	return _lightning


func nearest_sign_key() -> String:
	return _nearest_sign


func overbridge_count() -> int:
	return _overbridges.size()


func flow_volumes() -> Array:
	# High-angular-velocity lateral side-verge corridors alongside the cabin (z = -12..+14 m) where peripheral vection
	# is strongest; verifies the front seats and A-pillars shield the primary screen while keeping the forward focus of
	# expansion through the panoramic windscreen unobstructed.
	return [
		AABB(Vector3(-52.0, -0.5, -12.0), Vector3(42.0, 14.0, 26.0)),
		AABB(Vector3(11.0, -0.5, -12.0), Vector3(44.0, 14.0, 26.0)),
	]


# --- Route binary + JSON loading --------------------------------------------------------------------------------------

func _load_route_data() -> void:
	var bin_path := str(params.get("route_bin", "res://environments/routes/m1_route.bin"))
	var meta_path := str(params.get("route_meta", "res://environments/routes/m1_route_meta.json"))
	var cache_key := bin_path + "|" + meta_path
	if _route_cache.has(cache_key):
		var c: Dictionary = _route_cache[cache_key]
		_n_samples = c["n"]
		_step_m = c["step"]
		_total_len_m = c["len"]
		_heading = c["heading"]
		_curv = c["curv"]
		_elev = c["elev"]
		_grade = c["grade"]
		_dh = c["dh"]
		_rgb = c["rgb"]
		_flags = c["flags"]
		_urban = c["urban"]
		_vmist = c["vmist"]
		_overbridges = c["overbridges"]
		_skyline = c["skyline"]
		_landmarks = c["landmarks"]
		return

	var bytes := FileAccess.get_file_as_bytes(bin_path)
	if bytes.size() < 16:
		push_warning("motorway.gd: missing or empty route binary " + bin_path)
		_init_fallback_route()
		return
	var spb := StreamPeerBuffer.new()
	spb.data_array = bytes
	spb.big_endian = false
	var _magic := spb.get_utf8_string(4)
	var _ver := spb.get_u16()
	_n_samples = spb.get_u16()
	_step_m = spb.get_float()
	_total_len_m = spb.get_float()

	_heading.resize(_n_samples)
	_curv.resize(_n_samples)
	_elev.resize(_n_samples)
	_grade.resize(_n_samples)
	_dh.resize(_n_samples * 11)
	_rgb.resize(_n_samples * 33)
	_flags.resize(_n_samples)
	_urban.resize(_n_samples)
	_vmist.resize(_n_samples)

	for i in _n_samples:
		_heading[i] = spb.get_float()
		_curv[i] = spb.get_float()
		_elev[i] = spb.get_float()
		_grade[i] = spb.get_float()
		for k in 11:
			_dh[i * 11 + k] = float(spb.get_16()) * 0.1
		var base_c := i * 33
		for k in 33:
			_rgb[base_c + k] = spb.get_u8()
		_flags[i] = spb.get_u16()
		var _lanes := spb.get_u8()
		_urban[i] = spb.get_u8()
		_vmist[i] = spb.get_u8()

	_overbridges = []
	_skyline = []
	_landmarks = []
	var txt := FileAccess.get_file_as_string(meta_path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		for ob: Dictionary in parsed.get("overbridges", []):
			_overbridges.append({
				"s": float(ob.get("SMetres", 0.0)),
				"width": float(ob.get("WidthM", 12.0)),
				"skew": float(ob.get("SkewDeg", 0.0)),
				"kind": str(ob.get("Kind", "road")),
				"name": str(ob.get("Name", "")),
			})
		for sk: Dictionary in parsed.get("skyline", []):
			_skyline.append({
				"s": float(sk.get("SMetres", 0.0)),
				"lat": float(sk.get("LateralM", 120.0)),
				"kind": str(sk.get("Kind", "pylon")),
				"h": float(sk.get("HeightM", 46.0)),
			})
		for lm: Dictionary in parsed.get("landmarks", []):
			_landmarks.append({
				"id": str(lm.get("Id", "")),
				"name": str(lm.get("Name", "")),
				"s": float(lm.get("SMetres", 0.0)),
				"lat": float(lm.get("LateralM", 200.0)),
				"kind": str(lm.get("Kind", "")),
			})

	_route_cache[cache_key] = {
		"n": _n_samples, "step": _step_m, "len": _total_len_m,
		"heading": _heading, "curv": _curv, "elev": _elev, "grade": _grade,
		"dh": _dh, "rgb": _rgb, "flags": _flags, "urban": _urban, "vmist": _vmist,
		"overbridges": _overbridges, "skyline": _skyline, "landmarks": _landmarks,
	}


func _init_fallback_route() -> void:
	_n_samples = 64
	_step_m = 100.0
	_total_len_m = 6300.0
	_heading.resize(_n_samples)
	_curv.resize(_n_samples)
	_elev.resize(_n_samples)
	_grade.resize(_n_samples)
	_dh.resize(_n_samples * 11)
	_rgb.resize(_n_samples * 33)
	_flags.resize(_n_samples)
	_urban.resize(_n_samples)
	_vmist.resize(_n_samples)
	for i in _n_samples:
		_flags[i] = 3
		for k in 11:
			_rgb[i * 33 + k * 3 + 0] = 56
			_rgb[i * 33 + k * 3 + 1] = 84
			_rgb[i * 33 + k * 3 + 2] = 44


func _load_sign_atlas_meta() -> void:
	var meta_path := str(params.get("sign_meta", "res://environments/routes/m1_signs_atlas.json"))
	var txt := FileAccess.get_file_as_string(meta_path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return
	var signs: Dictionary = parsed.get("signs", {})
	for key: String in signs:
		var e: Dictionary = signs[key]
		var u0 := float(e.get("U0", 0.0))
		var v0 := float(e.get("V0", 0.0))
		var u1 := float(e.get("U1", 1.0))
		var v1 := float(e.get("V1", 1.0))
		var w_mm := float(e.get("WidthMm", 3000.0))
		var h_mm := float(e.get("HeightMm", 2000.0))
		var kind := str(e.get("Kind", "ads"))
		# Real-world motorway sign physical scale (metres), preserving exact TSRGD aspect ratio from FableRoadSignLibrary!
		var w_m := 4.4
		match kind:
			"countdown": w_m = 0.72
			"ads": w_m = 4.6
			"exit": w_m = 3.8
			"services": w_m = 3.8
			"gantry": w_m = 13.8
			"confirmatory": w_m = 3.2
			"matrix": w_m = 1.65
		var h_m := w_m * (h_mm / maxf(w_mm, 1.0))
		_atlas_uv[key] = {
			"uv": Vector4(u0, v0, u1 - u0, v1 - v0),
			"w": w_m, "h": h_m, "kind": kind,
		}


func _build_sign_schedules() -> void:
	_signs_nb = []
	_signs_sb = []
	# Authentic UK M1 Junction signage schedule (Northbound & Southbound) anchored to real extracted M1 chainages!
	# Every major junction gets: 1-mile ADS, 1/2-mile ADS or 3-lane overhead gantry, 300/200/100 yd countdown markers,
	# final -45 deg exit sign, and post-junction route confirmatory sign!
	var nb_jcts := [
		[17500.0,  "ads_nb_j5",  "exit_m25",         "gantry_nb_south",    "conf_nb_south"],
		[23200.0,  "ads_nb_j6a", "exit_m25",         "",                   ""],
		[38900.0,  "ads_nb_j10", "exit_luton",       "gantry_nb_south",    "conf_nb_south"],
		[69100.0,  "ads_nb_j14", "exit_northampton", "",                   ""],
		[89800.0,  "ads_nb_j15", "exit_northampton", "",                   "conf_nb_south"],
		[100200.0, "ads_nb_j15", "exit_northampton", "",                   ""],
		[121300.0, "ads_nb_j19", "exit_leicester",   "gantry_nb_midlands", "conf_nb_midlands"],
		[144300.0, "ads_nb_j21", "exit_leicester",   "gantry_nb_midlands", "conf_nb_midlands"],
		[176800.0, "ads_nb_j24", "exit_nottingham",  "",                   "conf_nb_midlands"],
		[192400.0, "ads_nb_j26", "exit_nottingham",  "",                   ""],
		[245600.0, "ads_nb_j33", "exit_sheffield",   "gantry_nb_yorks",    "conf_nb_north"],
		[280700.0, "ads_nb_j39", "exit_sheffield",   "",                   ""],
		[292200.0, "ads_nb_j42", "exit_m62",         "gantry_nb_yorks",    "conf_nb_north"],
	]
	for j: Array in nb_jcts:
		var sj := float(j[0])
		_add_junction_signs(_signs_nb, sj, 1.0, str(j[1]), str(j[2]), str(j[3]), str(j[4]))
	# Also put an immediate welcoming J1/M1 confirmatory + J10/J21/J24/J33 showcase sign near each starting preset!
	_add_verge_sign(_signs_nb, 910.0, "conf_nb_south")
	_add_verge_sign(_signs_nb, 1080.0, "ads_nb_j5")
	_add_gantry_sign(_signs_nb, 1260.0, "gantry_nb_south")
	_add_verge_sign(_signs_nb, 37485.0, "ads_nb_j10")
	_add_verge_sign(_signs_nb, 37610.0, "cd_3")
	_add_gantry_sign(_signs_nb, 37740.0, "gantry_nb_south")
	_add_verge_sign(_signs_nb, 143210.0, "ads_nb_j21")
	_add_gantry_sign(_signs_nb, 143380.0, "gantry_nb_midlands")
	_add_verge_sign(_signs_nb, 176040.0, "ads_nb_j24")
	_add_verge_sign(_signs_nb, 244320.0, "ads_nb_j33")

	# Real M1 Service Areas (Northbound)
	var svcs := [
		[49800.0, "svc_toddington"],
		[111200.0, "svc_watford_gap"],
		[99340.0, "svc_watford_gap"],
		[146200.0, "svc_lfe"],
		[190600.0, "svc_trowell"],
		[234200.0, "svc_woodall"],
		[276800.0, "svc_woolley"],
	]
	for sv: Array in svcs:
		_add_verge_sign(_signs_nb, float(sv[0]), str(sv[1]))
		_add_verge_sign(_signs_sb, float(sv[0]) + 1600.0, str(sv[1]))

	# Southbound junction signage schedule
	var sb_jcts := [
		[292200.0, "ads_sb_j42", "exit_m62",         "gantry_sb_midlands", "conf_sb_north"],
		[245600.0, "ads_sb_j33", "exit_sheffield",   "",                   "conf_sb_north"],
		[182800.0, "ads_sb_j25", "exit_nottingham",  "",                   "conf_sb_north"],
		[144300.0, "ads_sb_j21", "exit_leicester",   "gantry_sb_midlands", "conf_sb_south"],
		[121300.0, "ads_sb_j19", "exit_leicester",   "gantry_sb_midlands", "conf_sb_south"],
		[89800.0,  "ads_sb_j15", "exit_northampton", "",                   "conf_sb_south"],
		[38900.0,  "ads_sb_j10", "exit_luton",       "gantry_sb_london",   "conf_sb_south"],
		[23200.0,  "ads_sb_j6a", "exit_m25",         "gantry_sb_london",   "conf_sb_south"],
	]
	for j: Array in sb_jcts:
		_add_junction_signs(_signs_sb, float(j[0]), -1.0, str(j[1]), str(j[2]), str(j[3]), str(j[4]))
	_add_verge_sign(_signs_sb, 305080.0, "ads_sb_j42")
	_add_gantry_sign(_signs_sb, 304920.0, "gantry_sb_midlands")

	_signs_nb.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
	_signs_sb.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))


func _add_junction_signs(list: Array, s_jct: float, dir_s: float, ads_k: String, exit_k: String,
		gantry_k: String, conf_k: String) -> void:
	# 1 mile (1609 m) & 1/2 mile (805 m) before junction, 300/200/100 yd countdown markers, final exit, & confirmatory after
	_add_verge_sign(list, s_jct - dir_s * 1609.0, ads_k)
	if gantry_k != "":
		_add_gantry_sign(list, s_jct - dir_s * 805.0, gantry_k)
	else:
		_add_verge_sign(list, s_jct - dir_s * 805.0, ads_k)
	_add_verge_sign(list, s_jct - dir_s * 274.0, "cd_3")
	_add_verge_sign(list, s_jct - dir_s * 183.0, "cd_2")
	_add_verge_sign(list, s_jct - dir_s * 91.0, "cd_1")
	if exit_k != "":
		_add_verge_sign(list, s_jct - dir_s * 18.0, exit_k)
	if conf_k != "":
		_add_verge_sign(list, s_jct + dir_s * 360.0, conf_k)


func _add_verge_sign(list: Array, s_m: float, key: String) -> void:
	if not _atlas_uv.has(key):
		return
	var info: Dictionary = _atlas_uv[key]
	var w := float(info["w"])
	var h := float(info["h"])
	var is_cd := str(info["kind"]) == "countdown"
	var x := -9.6 if is_cd else -(9.4 + w * 0.5)
	var y := 1.45 if is_cd else (1.95 + h * 0.5)
	list.append({"s": s_m, "x": x, "y": y, "w": w, "h": h, "key": key, "gantry": false})


func _add_gantry_sign(list: Array, s_m: float, key: String) -> void:
	if not _atlas_uv.has(key):
		return
	var info: Dictionary = _atlas_uv[key]
	list.append({
		"s": s_m, "x": 0.0, "y": 6.65,
		"w": float(info["w"]), "h": float(info["h"]),
		"key": key, "gantry": true,
	})


# --- Texture loader helper (works identically in desktop, headless & packed .pck!) ------------------------------------

static func _load_png_tex(res_path: String) -> ImageTexture:
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]
	var bytes := FileAccess.get_file_as_bytes(res_path)
	var img := Image.new()
	if not bytes.is_empty():
		img.load_png_from_buffer(bytes)
		img.generate_mipmaps()
	else:
		img = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.4, 0.2, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[res_path] = tex
	return tex


# --- Mesh & MultiMesh construction (7 total draws!) -------------------------------------------------------------------

func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	var x0 := -10.2
	var x1 := 24.0
	for i in segs:
		var z0 := lerpf(Z_BACK, Z_FRONT, float(i) / segs)
		var z1 := lerpf(Z_BACK, Z_FRONT, float(i + 1) / segs)
		var a := Vector3(x0, -0.32, z0)
		var b := Vector3(x1, -0.32, z0)
		var c := Vector3(x1, -0.32, z1)
		var d := Vector3(x0, -0.32, z1)
		st.set_normal(Vector3.UP)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(d)
		st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.name = "MotorwayRoad"
	mi.mesh = st.commit()
	mi.custom_aabb = AABB(Vector3(-190.0, -40.0, -195.0), Vector3(380.0, 90.0, 240.0))
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = ROAD_SHADER
	mi.material_override = _road_mat
	_root.add_child(mi)


func _build_terrain_mesh() -> void:
	_h_img = Image.create_empty(11, 64, false, Image.FORMAT_RGBA8)
	_c_img = Image.create_empty(11, 64, false, Image.FORMAT_RGB8)
	_h_tex = ImageTexture.create_from_image(_h_img)
	_c_tex = ImageTexture.create_from_image(_c_img)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs_z := 63
	# Two continuous ribbons: LEFT side (lateral indices 0..4 -> x = -168..-16, plus shoulder tuck at -9.8)
	# and RIGHT side (shoulder tuck at +23.6, lateral indices 6..10 -> x = +29..+174).
	var left_x := [-168.0, -118.0, -72.0, -38.0, -16.0, -9.8]
	var left_u := [0.0, 0.1, 0.2, 0.3, 0.4, 0.45]
	var right_x := [23.6, 29.0, 52.0, 86.0, 128.0, 174.0]
	var right_u := [0.55, 0.6, 0.7, 0.8, 0.9, 1.0]

	for side_pair: Array in [[left_x, left_u], [right_x, right_u]]:
		var xs: Array = side_pair[0]
		var us: Array = side_pair[1]
		for iz in segs_z:
			var v0 := float(iz) / float(segs_z)
			var v1 := float(iz + 1) / float(segs_z)
			var z0 := lerpf(Z_BACK, Z_FRONT, v0)
			var z1 := lerpf(Z_BACK, Z_FRONT, v1)
			for ix in xs.size() - 1:
				var xa := float(xs[ix])
				var xb := float(xs[ix + 1])
				var ua := float(us[ix])
				var ub := float(us[ix + 1])
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(ua, v0))
				st.add_vertex(Vector3(xa, -0.34, z0))
				st.set_uv(Vector2(ub, v1))
				st.add_vertex(Vector3(xb, -0.34, z1))
				st.set_uv(Vector2(ub, v0))
				st.add_vertex(Vector3(xb, -0.34, z0))

				st.set_uv(Vector2(ua, v0))
				st.add_vertex(Vector3(xa, -0.34, z0))
				st.set_uv(Vector2(ua, v1))
				st.add_vertex(Vector3(xa, -0.34, z1))
				st.set_uv(Vector2(ub, v1))
				st.add_vertex(Vector3(xb, -0.34, z1))

	var mi := MeshInstance3D.new()
	mi.name = "MotorwayTerrain"
	mi.mesh = st.commit()
	mi.custom_aabb = AABB(Vector3(-220.0, -90.0, -210.0), Vector3(440.0, 220.0, 260.0))
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = TERRAIN_SHADER
	_terrain_mat.set_shader_parameter("height_tex", _h_tex)
	_terrain_mat.set_shader_parameter("colour_tex", _c_tex)
	mi.material_override = _terrain_mat
	_root.add_child(mi)


func _build_trees_multimesh() -> void:
	# Crossed dual-quad impostor card (2 quads = 4 tris per tree, bottom-anchored at y=0, height=1, width=1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang: float in [0.0, PI * 0.5]:
		var ca := cos(ang) * 0.5
		var sa := sin(ang) * 0.5
		var p0 := Vector3(-ca, 0.0, -sa)
		var p1 := Vector3(ca, 0.0, sa)
		var p2 := Vector3(ca, 1.0, sa)
		var p3 := Vector3(-ca, 1.0, -sa)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p2)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p3)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p2)

	_trees_mm = MultiMesh.new()
	_trees_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trees_mm.use_custom_data = true
	_trees_mm.mesh = st.commit()
	_trees_mm.instance_count = 520
	_trees_mm.visible_instance_count = 0

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MotorwayTrees"
	mmi.multimesh = _trees_mm
	mmi.set_meta("env_placed", [])
	mmi.custom_aabb = AABB(Vector3(-190.0, -40.0, -195.0), Vector3(380.0, 90.0, 240.0))
	_trees_mat = ShaderMaterial.new()
	_trees_mat.shader = TREES_SHADER
	_trees_mat.set_shader_parameter("tree_atlas", _load_png_tex(str(params.get("tree_atlas"))))
	mmi.material_override = _trees_mat
	_root.add_child(mmi)


func _build_signs_multimesh() -> void:
	# Unit quad facing +Z (towards oncoming viewer driving along -Z!)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_signs_mm = MultiMesh.new()
	_signs_mm.transform_format = MultiMesh.TRANSFORM_3D
	_signs_mm.use_colors = true
	_signs_mm.use_custom_data = true
	_signs_mm.mesh = q
	_signs_mm.instance_count = 40
	_signs_mm.visible_instance_count = 0

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MotorwaySigns"
	mmi.multimesh = _signs_mm
	mmi.set_meta("env_placed", [])
	mmi.custom_aabb = AABB(Vector3(-190.0, -30.0, -195.0), Vector3(380.0, 60.0, 240.0))
	_signs_mat = ShaderMaterial.new()
	_signs_mat.shader = SIGNS_SHADER
	_signs_mat.set_shader_parameter("sign_atlas", _load_png_tex(str(params.get("sign_atlas"))))
	mmi.material_override = _signs_mat
	_root.add_child(mmi)


func _build_props_multimeshes() -> void:
	_props_mat = ShaderMaterial.new()
	_props_mat.shader = PROPS_SHADER

	var box_m := BoxMesh.new()
	box_m.size = Vector3.ONE
	_boxes_mm = MultiMesh.new()
	_boxes_mm.transform_format = MultiMesh.TRANSFORM_3D
	_boxes_mm.use_colors = true
	_boxes_mm.use_custom_data = true
	_boxes_mm.mesh = box_m
	_boxes_mm.instance_count = 640
	_boxes_mm.visible_instance_count = 0
	var bmmi := MultiMeshInstance3D.new()
	bmmi.name = "MotorwayHardware"
	bmmi.multimesh = _boxes_mm
	bmmi.set_meta("env_placed", [])
	bmmi.custom_aabb = AABB(Vector3(-220.0, -60.0, -210.0), Vector3(440.0, 160.0, 260.0))
	bmmi.material_override = _props_mat
	_root.add_child(bmmi)

	var cyl_m := CylinderMesh.new()
	cyl_m.top_radius = 0.48
	cyl_m.bottom_radius = 0.50
	cyl_m.height = 1.0
	cyl_m.radial_segments = 16
	cyl_m.rings = 1
	_cyls_mm = MultiMesh.new()
	_cyls_mm.transform_format = MultiMesh.TRANSFORM_3D
	_cyls_mm.use_colors = true
	_cyls_mm.use_custom_data = true
	_cyls_mm.mesh = cyl_m
	_cyls_mm.instance_count = 96
	_cyls_mm.visible_instance_count = 0
	var cmmi := MultiMeshInstance3D.new()
	cmmi.name = "MotorwayTowers"
	cmmi.multimesh = _cyls_mm
	cmmi.set_meta("env_placed", [])
	cmmi.custom_aabb = AABB(Vector3(-260.0, -60.0, -220.0), Vector3(520.0, 220.0, 260.0))
	cmmi.material_override = _props_mat
	_root.add_child(cmmi)

	var hq := QuadMesh.new()
	hq.size = Vector2(1.0, 1.0)
	_halos_mm = MultiMesh.new()
	_halos_mm.transform_format = MultiMesh.TRANSFORM_3D
	_halos_mm.use_colors = true
	_halos_mm.mesh = hq
	_halos_mm.instance_count = 112
	_halos_mm.visible_instance_count = 0
	var hmmi := MultiMeshInstance3D.new()
	hmmi.name = "MotorwayHalos"
	hmmi.multimesh = _halos_mm
	hmmi.set_meta("env_placed", [])
	hmmi.custom_aabb = AABB(Vector3(-190.0, -30.0, -195.0), Vector3(380.0, 60.0, 240.0))
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = HALO_SHADER
	hmmi.material_override = _halo_mat
	_root.add_child(hmmi)


# --- Route sampling & real curvature / elevation integration ----------------------------------------------------------

func _sample_idx(s_m: float) -> int:
	return clampi(int(round(s_m / _step_m)), 0, _n_samples - 1)


func _sample_grade(s_m: float) -> float:
	var f := clampf(s_m / _step_m, 0.0, float(_n_samples - 2))
	var i0 := int(floor(f))
	return lerpf(_grade[i0], _grade[i0 + 1], f - i0) * _dir


func _sample_curv(s_m: float) -> float:
	var f := clampf(s_m / _step_m, 0.0, float(_n_samples - 2))
	var i0 := int(floor(f))
	return lerpf(_curv[i0], _curv[i0 + 1], f - i0) * _dir


func _sample_flags(s_m: float) -> int:
	return _flags[_sample_idx(s_m)]


func _rebuild_curve_profile() -> void:
	# Integrate real M1 curvature & grade forward from z=0 -> -182 and backward z=0 -> +32 so every world object bends seamlessly!
	var step_z := Z_SPAN / float(CURVE_SLOTS - 1) # ~6.9 m
	var zero_slot := int(round(Z_BACK / step_z))
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(CURVE_SLOTS)
	ys.resize(CURVE_SLOTS)
	xs[zero_slot] = 0.0
	ys[zero_slot] = 0.0
	var g0 := _sample_grade(_s_now)

	# Forward integration (z <= 0)
	var ang := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in range(zero_slot + 1, CURVE_SLOTS):
		var dz_m := (i - zero_slot) * step_z
		var s_here := _s_now + _dir * dz_m
		var k := clampf(_sample_curv(s_here) * 1.35, -0.0028, 0.0028)
		ang += k * step_z
		cx += sin(ang) * step_z
		var rel_g := clampf(_sample_grade(s_here) - g0, -0.035, 0.035)
		cy += rel_g * step_z
		xs[i] = cx
		ys[i] = cy

	# Backward integration (z > 0)
	ang = 0.0
	cx = 0.0
	cy = 0.0
	for i in range(zero_slot - 1, -1, -1):
		var dz_m := (zero_slot - i) * step_z
		var s_here := _s_now - _dir * dz_m
		var k := clampf(_sample_curv(s_here) * 1.35, -0.0028, 0.0028)
		ang -= k * step_z
		cx -= sin(ang) * step_z
		var rel_g := clampf(_sample_grade(s_here) - g0, -0.035, 0.035)
		cy -= rel_g * step_z
		xs[i] = cx
		ys[i] = cy

	for i in CURVE_SLOTS:
		var z_loc := lerpf(Z_BACK, Z_FRONT, float(i) / float(CURVE_SLOTS - 1))
		var s_here := _s_now + _dir * (-z_loc)
		var fl := _sample_flags(s_here)
		var lit_v := 1.0 if (fl & 1) != 0 else 0.0
		var lamp_st := float((fl >> 1) & 3)
		_curve_x[i] = xs[i]
		_curve_y[i] = ys[i]
		_curve_prof[i] = Vector4(xs[i], ys[i], lit_v, lamp_st)

	_road_mat.set_shader_parameter("curve_prof", _curve_prof)
	_terrain_mat.set_shader_parameter("curve_prof", _curve_prof)


func _curve_at_z(z_local: float) -> Vector2:
	var t := clampf((Z_BACK - z_local) / Z_SPAN, 0.0, 1.0) * float(CURVE_SLOTS - 1)
	var i0 := int(floor(t))
	var i1 := mini(i0 + 1, CURVE_SLOTS - 1)
	var f := t - i0
	return Vector2(lerpf(_curve_x[i0], _curve_x[i1], f), lerpf(_curve_y[i0], _curve_y[i1], f))


func _curve_tangent_yaw(z_local: float) -> float:
	var c0 := _curve_at_z(z_local + 3.0)
	var c1 := _curve_at_z(z_local - 3.0)
	return atan2(c0.x - c1.x, 6.0)


func _dem_dh_at(s_m: float, lat_x: float) -> float:
	var idx := _sample_idx(s_m)
	# Mirror lateral DEM lookup when heading southbound!
	var query_x := lat_x * _dir
	# Map world lateral x [-168..+174] onto 11 DEM bins
	var slot := 5
	if query_x < 0.0:
		slot = clampi(5 - int(round(clampf(absf(query_x) / 34.0, 0.0, 5.0))), 0, 5)
	else:
		slot = clampi(5 + int(round(clampf(query_x / 34.0, 0.0, 5.0))), 5, 10)
	return _dh[idx * 11 + slot]


func _update_terrain_textures(force: bool) -> void:
	if not force and absf(_s_now - _terrain_baked_s) < 3.5:
		return
	_terrain_baked_s = _s_now
	for iz in 64:
		var z_loc := lerpf(Z_BACK, Z_FRONT, float(iz) / 63.0)
		var s_here := _s_now + _dir * (-z_loc)
		var f := clampf(s_here / _step_m, 0.0, float(_n_samples - 2))
		var i0 := int(floor(f))
		var i1 := i0 + 1
		var frac := f - i0
		var fl := _flags[i0]
		var chalk := 1.0 if ((fl >> 6) & 1) != 0 else 0.0
		var vmist := float(_vmist[i0]) / 255.0
		var urban := float(_urban[i0]) / 255.0

		for k in 11:
			# When driving southbound (_dir < 0), left & right sides of the M1 swap!
			var dk := k if _dir > 0.0 else (10 - k)
			var dh := lerpf(_dh[i0 * 11 + dk], _dh[i1 * 11 + dk], frac)
			var h_enc := clampf(dh / 180.0 + 0.5, 0.0, 1.0)
			_h_img.set_pixel(k, iz, Color(h_enc, chalk, vmist, urban))

			var b0 := i0 * 33 + dk * 3
			var b1 := i1 * 33 + dk * 3
			var r := lerpf(float(_rgb[b0]), float(_rgb[b1]), frac) / 255.0
			var g := lerpf(float(_rgb[b0 + 1]), float(_rgb[b1 + 1]), frac) / 255.0
			var b := lerpf(float(_rgb[b0 + 2]), float(_rgb[b1 + 2]), frac) / 255.0
			# Keep authentic British countryside palette crisp & natural
			_c_img.set_pixel(k, iz, Color(clampf(r * 1.15, 0.04, 0.85), clampf(g * 1.18, 0.06, 0.88), clampf(b * 1.08, 0.04, 0.78)))
	_h_tex.update(_h_img)
	_c_tex.update(_c_img)


# --- Day / Night, British Weather, Soft Cloud-Sheet Lightning & Sky Sync ----------------------------------------------

func _update_environment(dt: float) -> void:
	# 1. Time of day -> hour, dusk, day_level, sun_dir, sun_col, sky_top, sky_low
	var tm := str(params.get("time_mode", "golden"))
	var film_prog := 0.0
	if host != null and host.signals != null:
		film_prog = float(host.signals.values.get("film.progress", 0.0))
	var hour := 18.6
	var dusk := 0.42
	match tm:
		"morning":
			hour = 8.4; dusk = 0.04
		"afternoon":
			hour = 14.2; dusk = 0.0
		"golden":
			hour = 18.7; dusk = 0.36
		"dusk":
			hour = 20.6; dusk = 0.84
		"night":
			hour = 22.8; dusk = 1.0
		"progress":
			# Smooth golden-hour -> twilight -> deep British night across the film (or drive time!)
			var p := clampf(film_prog if film_prog > 0.005 else fposmod(_drive_time / 1200.0, 1.0), 0.0, 1.0)
			hour = lerpf(17.8, 22.8, p)
			dusk = smoothstep(0.08, 0.78, p)

	# 2. Weather preset / organic Mixed British Drive
	var wm := str(params.get("weather_mode", "mixed"))
	var target_rain := 0.0
	var target_wet := 0.0
	var target_fog := 0.04
	var clouds := 0.48
	var is_storm := false
	match wm:
		"clear":
			target_rain = 0.0; target_wet = 0.0; target_fog = 0.025; clouds = 0.24
		"overcast":
			target_rain = 0.0; target_wet = 0.18; target_fog = 0.085; clouds = 0.78
		"fog":
			target_rain = 0.05; target_wet = 0.35; target_fog = 0.48; clouds = 0.86
		"rain":
			target_rain = 0.72; target_wet = 0.92; target_fog = 0.19; clouds = 0.88
		"storm":
			target_rain = 1.0; target_wet = 1.0; target_fog = 0.28; clouds = 0.96; is_storm = true
		"mixed":
			# Authentic British motorway weather evolving naturally along the miles (starts bright & dry at J10!)
			var w_phase := sin(_s_now * 0.00018 + 3.4) * 0.5 + 0.5
			var v_mist_here := float(_vmist[_sample_idx(_s_now)]) / 255.0
			target_rain = smoothstep(0.58, 0.92, w_phase) * 0.78
			target_wet = smoothstep(0.45, 0.82, w_phase) * 0.88
			target_fog = 0.04 + v_mist_here * 0.14 + target_rain * 0.12
			clouds = 0.36 + w_phase * 0.52

	if dt > 0.0:
		_rain_level = move_toward(_rain_level, target_rain, dt * 0.35)
		_wet_level = move_toward(_wet_level, target_wet, dt * 0.25)
		_fog_density = move_toward(_fog_density, target_fog, dt * 0.25)
	else:
		_rain_level = target_rain
		_wet_level = target_wet
		_fog_density = target_fog

	# Amber '50' matrix signals illuminate automatically in Fog or Thunderstorm!
	_matrix_active = (wm == "fog" or wm == "storm" or _fog_density > 0.34 or _rain_level > 0.88)

	# Animated front wiper cycle (smoothly runs whenever raining!)
	if _rain_level > 0.08 and dt > 0.0:
		var wipe_hz := lerpf(0.55, 0.95, _rain_level)
		_wiper_phase = fposmod(_wiper_phase + dt * wipe_hz, 1.0)
	elif _rain_level <= 0.08:
		_wiper_phase = move_toward(_wiper_phase, 0.0, dt * 0.8)

	# Comfort-safe soft ~1.1 s cloud-sheet lightning during Thunderstorm (strictly respects Flickering lights!)
	var flick_ok := bool(params.get("flicker_allowed", true))
	if is_storm and flick_ok and dt > 0.0:
		_lightning_timer += dt
		if _lightning_timer >= _next_lightning:
			_lightning_timer = 0.0
			_next_lightning = _rng.randf_range(11.0, 18.0)
			_thunder_delay = _rng.randf_range(2.2, 3.8)
		# Soft 1.15 s cloud-sheet swell (0.25 s gentle rise, 0.90 s smooth decay — zero strobe!)
		if _lightning_timer < 1.15:
			_lightning = smoothstep(0.0, 0.25, _lightning_timer) * (1.0 - smoothstep(0.28, 1.15, _lightning_timer))
		else:
			_lightning = 0.0
		if _thunder_delay > 0.0:
			_thunder_delay -= dt
			if _thunder_delay <= 0.0:
				_trigger_sound("thunder_roll")
	else:
		_lightning = move_toward(_lightning, 0.0, dt * 2.5) if dt > 0.0 else 0.0

	# Palette & lighting synthesis across all times of day & British skies
	var storm_dim := 1.0 - (0.42 if is_storm else _rain_level * 0.26)
	_day_level = clampf((1.0 - dusk * 0.92) * storm_dim, 0.06, 1.0)
	_headlight_now = float(params.get("headlights", 1.0)) * clampf(
			smoothstep(0.55, 0.14, _day_level) + _fog_density * 1.4 + _rain_level * 0.65, 0.0, 1.0)

	var sky_top := Color(0.14, 0.34, 0.64).lerp(Color(0.05, 0.07, 0.13), dusk)
	var sky_low := Color(0.56, 0.68, 0.80).lerp(Color(0.12, 0.13, 0.17), dusk)
	var sun_col := Color(1.0, 0.95, 0.86)
	var sun_dir := Vector3(0.32, 0.68, -0.66).normalized()
	if tm == "golden" or (tm == "progress" and dusk > 0.15 and dusk < 0.72):
		sky_top = Color(0.14, 0.24, 0.48).lerp(Color(0.07, 0.09, 0.18), dusk)
		sky_low = Color(0.92, 0.56, 0.30).lerp(Color(0.22, 0.16, 0.18), dusk)
		sun_col = Color(1.0, 0.68, 0.36)
		sun_dir = Vector3(-0.52, 0.24, -0.82).normalized()
	elif tm == "dusk":
		sky_top = Color(0.06, 0.09, 0.20)
		sky_low = Color(0.32, 0.22, 0.24)
		sun_col = Color(0.86, 0.44, 0.24)
		sun_dir = Vector3(-0.60, 0.12, -0.78).normalized()
	elif tm == "night":
		sky_top = Color(0.03, 0.04, 0.09)
		sky_low = Color(0.09, 0.095, 0.13)
		sun_col = Color(0.24, 0.28, 0.42)
		sun_dir = Vector3(0.25, 0.45, -0.85).normalized()

	# Desaturate & cool skies in overcast / fog / rain / storm
	var grey_sky := Color(0.46, 0.50, 0.54).lerp(Color(0.10, 0.11, 0.14), dusk) * storm_dim
	var overcast_mix := clampf(clouds * 0.55 + _fog_density * 0.85 + _rain_level * 0.35, 0.0, 0.85)
	sky_top = sky_top.lerp(grey_sky * 0.72, overcast_mix)
	sky_low = sky_low.lerp(grey_sky * 1.05, overcast_mix)
	if _lightning > 0.01:
		sky_top = sky_top.lerp(Color(0.55, 0.64, 0.84), _lightning * 0.65)
		sky_low = sky_low.lerp(Color(0.62, 0.68, 0.80), _lightning * 0.55)
	var fog_col := sky_low.lerp(Color(0.56, 0.59, 0.62) * (0.20 + 0.80 * _day_level), _fog_density * 0.65)

	# Sync sibling `sky` system seamlessly via set_param() so its shader updates immediately!
	var sky_sys: Node = host.system("sky") if host != null else null
	if sky_sys != null:
		sky_sys.call("set_param", "hour", hour)
		sky_sys.call("set_param", "dusk", dusk)
		sky_sys.call("set_param", "clouds", clouds)
		sky_sys.call("set_param", "afterglow", 0.0 if tm == "night" else (0.30 if tm in ["golden", "dusk"] else 0.08))
		sky_sys.call("set_param", "glow", [fog_col.r, fog_col.g, fog_col.b] if tm == "night" else [0.92, 0.54, 0.28])
		sky_sys.call("set_param", "twilight_zenith", [sky_top.r, sky_top.g, sky_top.b])
		sky_sys.call("set_param", "twilight_horizon", [sky_low.r, sky_low.g, sky_low.b])
		sky_sys.call("set_param", "night_zenith", [sky_top.r * 0.72, sky_top.g * 0.72, sky_top.b * 0.72])
		sky_sys.call("set_param", "night_horizon", [sky_low.r * 0.82, sky_low.g * 0.82, sky_low.b * 0.82])
		sky_sys.call("set_param", "cloud_colour", [grey_sky.r * 0.88, grey_sky.g * 0.88, grey_sky.b * 0.88])
		sky_sys.call("set_param", "cloud_glow_level", (0.04 if tm == "night" else lerpf(0.12, 0.55, dusk)) + _lightning * 0.85)
		sky_sys.call("set_param", "ground", [fog_col.r * 0.78, fog_col.g * 0.78, fog_col.b * 0.78])

	# Sync sibling `weather` system (falling rain streaks outside side windows & dry panes in clear skies!)
	var w_sys: Node = host.system("weather") if host != null else null
	if w_sys != null:
		var w_str := "clear"
		if _rain_level > 0.55:
			w_str = "heavy"
		elif _rain_level > 0.12:
			w_str = "light"
		w_sys.call("set_param", "mode", w_str)
		w_sys.set("_amount", _rain_level)
		w_sys.set("_wet", _wet_level)
		w_sys.call("_apply")

	# Push uniforms to all 6 motorway shaders
	for mat: ShaderMaterial in [_road_mat, _terrain_mat, _trees_mat, _signs_mat, _props_mat]:
		mat.set_shader_parameter("day_level", _day_level)
		mat.set_shader_parameter("fog_density", _fog_density)
		mat.set_shader_parameter("lightning", _lightning)
		mat.set_shader_parameter("sky_top", Vector3(sky_top.r, sky_top.g, sky_top.b))
		mat.set_shader_parameter("sky_low", Vector3(sky_low.r, sky_low.g, sky_low.b))
		mat.set_shader_parameter("sun_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
		mat.set_shader_parameter("fog_col", Vector3(fog_col.r, fog_col.g, fog_col.b))
	for mat: ShaderMaterial in [_road_mat, _terrain_mat, _props_mat]:
		mat.set_shader_parameter("sun_dir", sun_dir)
	_road_mat.set_shader_parameter("s_travel", _s_now)
	_road_mat.set_shader_parameter("dir_sign", _dir)
	_road_mat.set_shader_parameter("wet", _wet_level)
	_road_mat.set_shader_parameter("headlight_level", _headlight_now)
	_road_mat.set_shader_parameter("time_sec", _drive_time)
	_terrain_mat.set_shader_parameter("s_travel", _s_now)
	_terrain_mat.set_shader_parameter("dir_sign", _dir)
	_terrain_mat.set_shader_parameter("wet", _wet_level)
	_signs_mat.set_shader_parameter("headlight_level", _headlight_now)
	_halo_mat.set_shader_parameter("halo_strength",
			clampf((1.0 - _day_level) * 0.92 + _fog_density * 0.95, 0.0, 1.25))
	_halo_mat.set_shader_parameter("fog_density", _fog_density)


func _update_overbridge_audio(dt: float) -> void:
	# Check if our GT is currently passing underneath any of the 279 real OSM overbridges (or bridge cafés)!
	var hit_idx := -1
	var lo := 0
	var hi := _overbridges.size() - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var ob: Dictionary = _overbridges[mid]
		var ds := float(ob["s"]) - _s_now
		var half_w := maxf(float(ob["width"]) * 0.65, 8.5)
		if absf(ds) <= half_w:
			hit_idx = mid
			break
		if float(ob["s"]) < _s_now:
			lo = mid + 1
		else:
			hi = mid - 1

	_under_bridge = hit_idx >= 0
	if _under_bridge and hit_idx != _last_bridge_idx and _speed_mps > 8.0:
		_last_bridge_idx = hit_idx
		_trigger_sound("bridge_whoosh")
	elif not _under_bridge:
		_last_bridge_idx = -1

	# Smoothly dip rain on steel roof & windscreen by ~82% under concrete bridge decks!
	var want_shelter := 0.18 if _under_bridge else 1.0
	_bridge_shelter = move_toward(_bridge_shelter, want_shelter, dt * 6.5) if dt > 0.0 else want_shelter
	if host != null:
		for bed_id: String in ["rain_roof", "rain_windscreen"]:
			var sb: Node = host.system(bed_id)
			if sb != null:
				sb.set("external_gain", _bridge_shelter)


func _trigger_sound(bed_id: String) -> void:
	if host != null:
		var sb: Node = host.system(bed_id)
		if sb != null:
			sb.call("act", "play", {})


# --- Dynamic streaming population of all 5 MultiMeshes every tick (< 0.4 ms!) -----------------------------------------

func _add_box(x_l: float, y_l: float, z_l: float, sx: float, sy: float, sz: float,
		col: Color, yaw_extra := 0.0, emissive := 0.0) -> void:
	if _box_i >= _boxes_mm.instance_count:
		return
	var cv := _curve_at_z(z_l)
	var yaw := _curve_tangent_yaw(z_l) + yaw_extra
	var b := Basis(Vector3.UP, yaw).scaled_local(Vector3(sx, sy, sz))
	_boxes_mm.set_instance_transform(_box_i, Transform3D(b, Vector3(x_l + cv.x, y_l + cv.y, z_l)))
	_boxes_mm.set_instance_color(_box_i, col if emissive > 0.05 else col.srgb_to_linear())
	_boxes_mm.set_instance_custom_data(_box_i, Color(emissive, 0.0, 0.0, 0.0))
	_box_i += 1


func _add_cyl(x_l: float, y_l: float, z_l: float, rx: float, h: float, rz: float,
		col: Color, emissive := 0.0) -> void:
	if _cyl_i >= _cyls_mm.instance_count:
		return
	var cv := _curve_at_z(z_l)
	var b := Basis().scaled_local(Vector3(rx, h, rz))
	_cyls_mm.set_instance_transform(_cyl_i, Transform3D(b, Vector3(x_l + cv.x, y_l + cv.y, z_l)))
	_cyls_mm.set_instance_color(_cyl_i, col if emissive > 0.05 else col.srgb_to_linear())
	_cyls_mm.set_instance_custom_data(_cyl_i, Color(emissive, 0.0, 0.0, 0.0))
	_cyl_i += 1


func _add_halo(x_l: float, y_l: float, z_l: float, radius: float, col: Color) -> void:
	if _halo_i >= _halos_mm.instance_count or _lamp_on_now < 0.08:
		return
	var cv := _curve_at_z(z_l)
	var b := Basis().scaled_local(Vector3(radius, radius, 1.0))
	_halos_mm.set_instance_transform(_halo_i, Transform3D(b, Vector3(x_l + cv.x, y_l + cv.y, z_l)))
	_halos_mm.set_instance_color(_halo_i, col)
	_halo_i += 1


func _add_sign(x_l: float, y_l: float, z_l: float, w: float, h: float, key: String, self_lit := false) -> void:
	if _sign_i >= _signs_mm.instance_count or not _atlas_uv.has(key):
		return
	var cv := _curve_at_z(z_l)
	var yaw := _curve_tangent_yaw(z_l)
	var b := Basis(Vector3.UP, yaw).scaled_local(Vector3(w, h, 1.0))
	var uv: Vector4 = _atlas_uv[key]["uv"]
	_signs_mm.set_instance_transform(_sign_i, Transform3D(b, Vector3(x_l + cv.x, y_l + cv.y, z_l)))
	_signs_mm.set_instance_color(_sign_i, Color(1.0 if self_lit else 0.0, 0.0, 0.0, 1.0))
	_signs_mm.set_instance_custom_data(_sign_i, Color(uv.x, uv.y, uv.z, uv.w))
	_sign_i += 1


func _add_tree(x_l: float, y_l: float, z_l: float, w: float, h: float, slot: int, yaw: float, tint: float) -> void:
	if _tree_i >= _trees_mm.instance_count:
		return
	var cv := _curve_at_z(z_l)
	var b := Basis(Vector3.UP, yaw).scaled_local(Vector3(w, h, w))
	_trees_mm.set_instance_transform(_tree_i, Transform3D(b, Vector3(x_l + cv.x, y_l + cv.y, z_l)))
	_trees_mm.set_instance_custom_data(_tree_i, Color(float(slot % 4), float(slot / 4), tint, 0.0))
	_tree_i += 1


func _populate_instances(_dt: float) -> void:
	_box_i = 0
	_cyl_i = 0
	_sign_i = 0
	_tree_i = 0
	_halo_i = 0
	var night_fac := clampf(1.0 - smoothstep(0.16, 0.66, _day_level), 0.0, 1.0)
	var lamp_on := clampf(night_fac + _fog_density * 0.85, 0.0, 1.0)
	_lamp_on_now = lamp_on

	# --- 1. Central Reservation Barriers (Armco / Concrete Step / Shrubbed Median) & Verges every 14 m ----------------
	var s_base_14 := floorf(_s_now / 14.0) * 14.0
	for k in range(-2, 14):
		var s_b := s_base_14 + _dir * float(k) * 14.0
		var z_l := -(s_b - _s_now) * _dir
		if z_l > 24.0 or z_l < -176.0:
			continue
		var fl := _sample_flags(s_b)
		var bstyle := (fl >> 3) & 3
		if bstyle == 1:
			# Concrete step central barrier (urban/busy M1 stretches)
			_add_box(7.3, 0.22, z_l, 0.75, 1.08, 14.2, Color(0.56, 0.56, 0.54))
		else:
			# Classic twin steel Armco crash barrier
			_add_box(6.55, 0.28, z_l, 0.14, 0.36, 14.2, Color(0.58, 0.61, 0.64))
			_add_box(8.05, 0.28, z_l, 0.14, 0.36, 14.2, Color(0.58, 0.61, 0.64))
			_add_box(7.3, -0.05, z_l, 0.12, 0.58, 0.12, Color(0.42, 0.44, 0.46))
			if bstyle == 2 and (k & 1) == 0:
				# Green shrubbed central reservation (hawthorn/blackthorn shrubs!)
				_add_tree(7.3, -0.32, z_l, 2.3, 1.55, 8 + (absi(int(s_b / 14.0)) % 4), float(k) * 1.1, 0.88)
		# Left verge Armco guardrail on viaducts or embankments
		if ((fl >> 5) & 1) != 0:
			_add_box(-9.0, 0.38, z_l, 0.25, 1.35, 14.2, Color(0.52, 0.55, 0.58))
			_add_box(22.4, 0.38, z_l, 0.25, 1.35, 14.2, Color(0.52, 0.55, 0.58))

	# --- 2. Per-stretch SOX / SON Motorway Streetlamps (every 42 m on real OSM lit stretches!) ------------------------
	var s_base_42 := floorf(_s_now / 42.0) * 42.0
	for k in range(-1, 6):
		var s_l := s_base_42 + _dir * float(k) * 42.0
		var z_l := -(s_l - _s_now) * _dir
		if z_l > 24.0 or z_l < -176.0:
			continue
		var fl := _sample_flags(s_l)
		if (fl & 1) == 0:
			continue # Genuine unlit dark British countryside stretch!
		var lamp_style := (fl >> 1) & 3
		var is_son := lamp_style == 2
		var lamp_col := Color(1.0, 0.76, 0.34) if is_son else Color(1.0, 0.48, 0.08) # Golden SON vs deep orange SOX!
		var pole_col := Color(0.46, 0.49, 0.52)
		# Central dual-arm column rising from central reservation
		_add_box(7.3, 5.4, z_l, 0.22, 11.4, 0.22, pole_col)
		_add_box(7.3, 10.95, z_l, 5.2, 0.16, 0.18, pole_col)
		# Twin glowing lantern housings (left toward our carriageway, right toward oncoming!)
		var em := 3.6 if lamp_on > 0.15 else 0.0
		var l_c := lamp_col if lamp_on > 0.15 else Color(0.75, 0.76, 0.78)
		_add_box(4.8, 10.82, z_l, 1.25, 0.28, 0.44, l_c, 0.0, em)
		_add_box(9.8, 10.82, z_l, 1.25, 0.28, 0.44, l_c, 0.0, em)
		if lamp_on > 0.15:
			_add_halo(4.8, 10.72, z_l, 6.2, lamp_col * 1.15)
			_add_halo(9.8, 10.72, z_l, 6.2, lamp_col * 1.15)

	# --- 3. UK TSRGD Motorway Signs & Overhead Gantries (pixel-exact from FableRoadSignLibrary!) ----------------------
	var schedule := _signs_nb if _dir > 0.0 else _signs_sb
	_nearest_sign = ""
	var best_sign_d := 1e9
	for sg: Dictionary in schedule:
		var z_l := -(float(sg["s"]) - _s_now) * _dir
		if z_l > 20.0 or z_l < -176.0:
			continue
		var key := str(sg["key"])
		var sx := float(sg["x"])
		var sy := float(sg["y"])
		var sw := float(sg["w"])
		var sh := float(sg["h"])
		if z_l < 0.0 and -z_l < best_sign_d:
			best_sign_d = -z_l
			_nearest_sign = key
		_add_sign(sx, sy, z_l, sw, sh, key, false)
		if bool(sg["gantry"]):
			# Full steel motorway portal gantry sitting cleanly BEHIND the blue TSRGD sign (`z_l - 0.55`)!
			var steel := Color(0.40, 0.43, 0.46)
			_add_box(-9.5, 4.7, z_l - 0.55, 0.65, 10.0, 0.65, steel)
			_add_box(6.9, 4.7, z_l - 0.55, 0.65, 10.0, 0.65, steel)
			_add_box(-1.3, 9.25, z_l - 0.55, 17.2, 0.72, 0.65, steel)
			_add_box(-1.3, 4.45, z_l - 0.55, 17.2, 0.36, 0.42, steel)
			# Three UK Motorway amber dot-matrix signals mounted cleanly BELOW the white downward lane arrows!
			var m_key := "matrix_50" if _matrix_active else "matrix_blank"
			for lx: float in [-3.6, 0.0, 3.6]:
				_add_sign(lx, 4.02, z_l + 0.06, 1.18, 1.18, m_key, _matrix_active)
				if _matrix_active:
					_add_halo(lx, 4.02, z_l + 0.18, 3.4, Color(1.0, 0.68, 0.12))
		else:
			# Twin galvanized tubular grey steel sign posts + grey backing plate
			var post_c := Color(0.45, 0.47, 0.49)
			_add_box(sx, sy, z_l - 0.07, sw + 0.06, sh + 0.06, 0.08, Color(0.32, 0.34, 0.36))
			var post_h := sy + sh * 0.35
			if sw > 1.8:
				_add_box(sx - sw * 0.32, post_h * 0.5 - 0.32, z_l - 0.14, 0.14, post_h, 0.14, post_c)
				_add_box(sx + sw * 0.32, post_h * 0.5 - 0.32, z_l - 0.14, 0.14, post_h, 0.14, post_c)
			else:
				_add_box(sx, post_h * 0.5 - 0.32, z_l - 0.14, 0.11, post_h, 0.11, post_c)

	# --- 4. Real OSM Overbridges (all 279 road/rail/foot bridges!) ----------------------------------------------------
	for ob: Dictionary in _overbridges:
		var z_l := -(float(ob["s"]) - _s_now) * _dir
		if z_l > 26.0 or z_l < -176.0:
			continue
		var bw := clampf(float(ob["width"]), 5.5, 24.0)
		var skew := deg_to_rad(float(ob["skew"])) * _dir
		var kind := str(ob["kind"])
		var deck_col := Color(0.34, 0.37, 0.41) if kind == "rail" else Color(0.54, 0.53, 0.50)
		var pier_col := Color(0.48, 0.47, 0.45)
		# Main concrete/steel bridge deck spanning all 6 lanes (x = -12..+26, clear headroom 5.5 m!)
		_add_box(6.8, 6.15, z_l, 42.0, 1.35, bw, deck_col, skew)
		# Bridge parapets (top safety rail)
		_add_box(6.8, 7.25, z_l + bw * 0.48, 42.0, 0.95, 0.38, deck_col * 0.85, skew)
		_add_box(6.8, 7.25, z_l - bw * 0.48, 42.0, 0.95, 0.38, deck_col * 0.85, skew)
		# Central reservation pier & side abutments
		_add_box(7.3, 2.7, z_l, 1.1, 6.2, minf(bw * 0.72, 9.0), pier_col, skew)
		_add_box(-11.2, 2.7, z_l, 2.6, 6.2, bw * 0.95, pier_col, skew)
		_add_box(24.8, 2.7, z_l, 2.6, 6.2, bw * 0.95, pier_col, skew)

	# --- 5. Iconic Real M1 Landmarks! ---------------------------------------------------------------------------------
	for lm: Dictionary in _landmarks:
		var z_l := -(float(lm["s"]) - _s_now) * _dir
		if z_l > 45.0 or z_l < -180.0:
			continue
		var kind := str(lm["kind"])
		var lat := float(lm["lat"]) * _dir
		if kind == "bridge_cafe":
			# Leicester Forest East iconic elevated glass-walled motorway bridge cafe!
			_add_box(6.8, 7.4, z_l, 44.0, 4.2, 16.5, Color(0.52, 0.50, 0.47))
			# Warm glowing panoramic cafe windows looking down on the M1!
			var win_em := 1.85 if lamp_on > 0.1 else 0.55
			_add_box(6.8, 7.5, z_l + 8.32, 36.0, 2.1, 0.18, Color(1.0, 0.84, 0.56), 0.0, win_em)
			_add_box(6.8, 7.5, z_l - 8.32, 36.0, 2.1, 0.18, Color(1.0, 0.84, 0.56), 0.0, win_em)
			_add_box(-13.5, 3.0, z_l, 4.8, 6.8, 16.0, Color(0.46, 0.44, 0.42))
			_add_box(27.0, 3.0, z_l, 4.8, 6.8, 16.0, Color(0.46, 0.44, 0.42))
		elif kind == "cooling_towers_8":
			# Ratcliffe-on-Soar Power Station: ALL 8 iconic 114 m concrete cooling towers in 2 rows of 4 + main chimney!
			var base_x := clampf(lat * 0.42, 72.0, 138.0) if _dir > 0.0 else clampf(lat * 0.42, -138.0, -72.0)
			var tower_col := Color(0.58, 0.57, 0.55)
			for row in 2:
				for col_i in 4:
					var tx := base_x + float(row) * 26.0 * signf(base_x)
					var tz := z_l + (float(col_i) - 1.5) * 28.0
					if tz < -180.0 or tz > 35.0:
						continue
					# Smooth 5-tier hyperbolic concrete cooling tower profile (flared base -> pinched waist -> flared upper rim!)
					_add_cyl(tx, 7.5, tz, 17.6, 16.0, 17.6, tower_col * 0.92)
					_add_cyl(tx, 21.5, tz, 15.2, 16.0, 15.2, tower_col * 0.96)
					_add_cyl(tx, 35.5, tz, 13.4, 15.0, 13.4, tower_col)
					_add_cyl(tx, 48.0, tz, 12.7, 14.0, 12.7, tower_col * 1.02)
					_add_cyl(tx, 59.0, tz, 13.3, 11.0, 13.3, tower_col * 1.05)
			# Tall 199 m central flue chimney + glowing red aviation warning beacon!
			_add_cyl(base_x + 12.0 * signf(base_x), 46.0, z_l, 4.2, 94.0, 4.2, Color(0.50, 0.48, 0.46))
			_add_box(base_x + 12.0 * signf(base_x), 94.0, z_l, 1.4, 1.4, 1.4, Color(1.0, 0.14, 0.10), 0.0, 2.8)
		elif kind == "emley_mast":
			# Iconic 330 m Yorkshire concrete Emley Moor TV mast + red aircraft warning lights!
			var mx := clampf(lat * 0.30, -145.0, -75.0) if _dir > 0.0 else clampf(lat * 0.30, 75.0, 145.0)
			_add_cyl(mx, 44.0, z_l, 5.2, 88.0, 5.2, Color(0.62, 0.62, 0.60))
			_add_cyl(mx, 98.0, z_l, 2.2, 26.0, 2.2, Color(0.68, 0.68, 0.68))
			_add_box(mx, 86.0, z_l, 6.2, 4.2, 6.2, Color(0.44, 0.46, 0.49)) # Turret room
			_add_box(mx, 112.0, z_l, 1.6, 1.6, 1.6, Color(1.0, 0.12, 0.08), 0.0, 3.0)
		elif kind == "viaduct":
			# Tinsley Viaduct towering steel twin-deck valley piers & red-oxide truss girders!
			for pi in range(-3, 4):
				var pz := z_l + float(pi) * 28.0
				if pz < -176.0 or pz > 28.0:
					continue
				_add_box(-9.6, -12.0, pz, 1.8, 24.0, 1.8, Color(0.36, 0.38, 0.40))
				_add_box(23.0, -12.0, pz, 1.8, 24.0, 1.8, Color(0.36, 0.38, 0.40))

	# --- 6. Real OSM Skyline Mix (National Grid pylons, brick chimneys, occasional turbines!) -------------------------
	for sk: Dictionary in _skyline:
		var z_l := -(float(sk["s"]) - _s_now) * _dir
		if z_l > 22.0 or z_l < -174.0:
			continue
		var lx := clampf(float(sk["lat"]) * _dir * 0.38, -142.0, 148.0)
		if lx > -24.0 and lx < 38.0:
			lx = -30.0 if lx < 7.0 else 44.0
		var gy := -0.34 + _dem_dh_at(float(sk["s"]), lx) * 0.72
		var sk_kind := str(sk["kind"])
		if sk_kind == "pylon":
			# Iconic UK National Grid steel lattice transmission pylon with 3 crossarms!
			var pcol := Color(0.46, 0.49, 0.51)
			_add_box(lx, gy + 15.0, z_l, 2.2, 30.0, 2.2, pcol)
			_add_box(lx, gy + 18.5, z_l, 11.5, 0.65, 0.65, pcol)
			_add_box(lx, gy + 23.0, z_l, 13.0, 0.65, 0.65, pcol)
			_add_box(lx, gy + 27.5, z_l, 9.0, 0.60, 0.60, pcol)
		elif sk_kind == "chimney":
			_add_cyl(lx, gy + 18.0, z_l, 2.6, 36.0, 2.6, Color(0.46, 0.28, 0.22))
		elif sk_kind == "turbine":
			_add_cyl(lx, gy + 22.0, z_l, 1.4, 44.0, 1.4, Color(0.82, 0.84, 0.86))
			_add_box(lx, gy + 44.0, z_l, 18.0, 0.65, 0.45, Color(0.85, 0.87, 0.89), _drive_time * 0.9)

	# --- 7. Lush British Motorway Embankment Woodland & Continuous Hedgerows (520 impostors, 1 draw!) ----------------
	var s_base_7 := floorf(_s_now / 7.5) * 7.5
	for k in range(-2, 24):
		var s_t := s_base_7 + _dir * float(k) * 7.5
		var z_l := -(s_t - _s_now) * _dir
		if z_l > 20.0 or z_l < -174.0:
			continue
		var fl := _sample_flags(s_t)
		var wl := (fl >> 8) & 15
		var wr := (fl >> 12) & 15
		if _dir < 0.0:
			var tmp := wl; wl = wr; wr = tmp
		var cell_id := int(round(s_t / 7.5))
		# Keep open panoramic sight-line window toward Ratcliffe cooling towers valley (s = 177.2..178.4 km)
		var near_ratcliffe := absf(s_t - 177800.0) < 620.0
		# Organic UK motorway embankment tree-belt modulation alternating dense woodland tunnels with rolling pastoral gaps
		var belt_l := clampf(0.62 + 0.34 * sin(s_t * 0.0085 + 0.4) + float(wl) * 0.045, 0.28, 1.0)
		var belt_r := clampf(0.62 + 0.34 * cos(s_t * 0.0078 - 0.6) + float(wr) * 0.045, 0.28, 1.0)
		if near_ratcliffe:
			if _dir > 0.0:
				belt_r = 0.22
			else:
				belt_l = 0.22

		for side_i in 2:
			var belt := belt_l if side_i == 0 else belt_r
			var dens := wl if side_i == 0 else wr
			var h1 := _hash_u(cell_id * 17 + side_i * 31)
			var h2 := _hash_u(cell_id * 53 + side_i * 97)
			var h3 := _hash_u(cell_id * 89 + side_i * 41)

			# Layer A: Continuous dense British motorway verge hedgerow (hawthorn, blackthorn, buddleia, hazel, bramble)
			# Tucked cleanly behind left verge sign posts (x <= -14.8 left, x >= +25.4 right)!
			if h1 < clampf(0.76 + belt * 0.22, 0.0, 0.98):
				var vx := (-14.8 - h2 * 3.8) if side_i == 0 else (25.4 + h2 * 4.2)
				var gy := -0.34 + _dem_dh_at(s_t, vx) * 0.28
				var sh_slot := 8 + (absi(cell_id * 7 + side_i * 3) % 8)
				_add_tree(vx, gy, z_l + (h1 - 0.5) * 5.5, 5.8 + h2 * 3.0, 3.6 + h3 * 2.2, sh_slot, h1 * TAU, 0.78 + h2 * 0.26)

			# Layer B: Dense frontline embankment canopy belt (mature Oak, Ash, Beech, Birch, Sycamore, Hawthorn, Scots Pine)
			var n_front := 2 if belt > 0.68 else 1
			for fi in n_front:
				var hf := _hash_u(cell_id * 131 + side_i * 71 + fi * 23)
				var hf2 := _hash_u(cell_id * 197 + side_i * 59 + fi * 37)
				if hf > (0.35 + belt * 0.63):
					continue
				var lat_f := 17.2 + hf * 8.5 + float(fi) * 4.5
				var tx := -lat_f if side_i == 0 else (14.0 + lat_f)
				var gy := -0.34 + _dem_dh_at(s_t, tx) * 0.55
				var t_slot := absi(cell_id * 11 + fi * 5 + side_i * 3) % 8
				var th := 8.8 + hf2 * 7.8
				var tw := th * (0.58 if t_slot == 7 else 0.88)
				_add_tree(tx, gy, z_l + (hf - 0.5) * 6.8, tw, th, t_slot, hf2 * TAU, 0.76 + hf * 0.28)

			# Layer C: Deep layered backdrop woodland & hillside copses (gives genuine English motorway woodland depth!)
			var n_back := (2 if (belt > 0.58 or dens >= 4) else 1) + (1 if dens >= 8 else 0)
			for bi in n_back:
				var hb := _hash_u(cell_id * 223 + side_i * 83 + bi * 29)
				var hb2 := _hash_u(cell_id * 269 + side_i * 47 + bi * 13)
				if hb > (0.28 + belt * 0.64 + float(dens) * 0.03):
					continue
				var lat_b := 27.5 + hb * 36.0 + float(bi) * 14.0
				var bx := -lat_b if side_i == 0 else (14.0 + lat_b)
				var gy := -0.34 + _dem_dh_at(s_t, bx) * 0.70
				var b_slot := absi(cell_id * 13 + bi * 7 + side_i * 5) % 8
				var bh := 10.5 + hb2 * 9.0
				var bw := bh * (0.58 if b_slot == 7 else 0.90)
				_add_tree(bx, gy, z_l + (hb - 0.5) * 7.5, bw, bh, b_slot, hb2 * TAU, 0.72 + hb * 0.28)

	# --- 8. Simple Instanced UK Motorway Traffic (Lane 1 slower vehicles + Oncoming opposite carriageway!) ------------
	var traf := clampf(float(params.get("traffic", 0.72)), 0.0, 1.0)
	if traf > 0.05:
		# A. Slower Lane 1 vehicles (x = -3.6, cruising at 56 mph -> relative closing speed ~6.2 m/s in either direction!)
		var rel_s1 := _odom * 0.22 + 38.0
		var spacing1 := lerpf(125.0, 58.0, traf)
		var base1 := floorf(rel_s1 / spacing1) * spacing1
		for k in range(-1, 5):
			var v_id := int(round((base1 + float(k) * spacing1) / spacing1))
			var z_l := -(base1 + float(k) * spacing1 - rel_s1)
			if z_l > 22.0 or z_l < -165.0:
				continue
			var hv := _hash_u(v_id * 43 + 7)
			var is_hgv := hv < 0.38
			var is_van := hv >= 0.38 and hv < 0.62
			if is_hgv:
				# Articulated British curtain-sider HGV (cab + long trailer + rear red lamps & amber outline markers!)
				var tcol: Color = [Color(0.76, 0.78, 0.80), Color(0.16, 0.28, 0.48), Color(0.56, 0.16, 0.16)][absi(v_id) % 3]
				_add_box(-3.6, 1.85, z_l, 2.48, 3.25, 11.8, tcol)
				_add_box(-3.6, 1.55, z_l - 7.1, 2.42, 2.75, 2.4, Color(0.84, 0.85, 0.86))
				# Rear twin red tail-lights + upper red/amber marker lamps
				var tail_em := 2.4 if lamp_on > 0.1 else 1.2
				_add_box(-4.58, 0.65, z_l + 5.95, 0.38, 0.18, 0.12, Color(1.0, 0.10, 0.06), 0.0, tail_em)
				_add_box(-2.62, 0.65, z_l + 5.95, 0.38, 0.18, 0.12, Color(1.0, 0.10, 0.06), 0.0, tail_em)
				_add_box(-4.74, 3.35, z_l + 5.92, 0.16, 0.16, 0.12, Color(1.0, 0.16, 0.08), 0.0, tail_em)
				_add_box(-2.46, 3.35, z_l + 5.92, 0.16, 0.16, 0.12, Color(1.0, 0.16, 0.08), 0.0, tail_em)
				if lamp_on > 0.15:
					_add_halo(-4.58, 0.65, z_l + 6.0, 2.1, Color(1.0, 0.12, 0.06))
					_add_halo(-2.62, 0.65, z_l + 6.0, 2.1, Color(1.0, 0.12, 0.06))
			elif is_van:
				# White panel van
				_add_box(-3.6, 0.88, z_l, 2.02, 1.98, 5.2, Color(0.84, 0.85, 0.86))
				var tail_em := 2.2 if lamp_on > 0.1 else 1.1
				_add_box(-4.35, 0.72, z_l + 2.64, 0.24, 0.38, 0.10, Color(1.0, 0.10, 0.06), 0.0, tail_em)
				_add_box(-2.85, 0.72, z_l + 2.64, 0.24, 0.38, 0.10, Color(1.0, 0.10, 0.06), 0.0, tail_em)
			else:
				# British motorway saloon / hatchback
				var ccol: Color = [Color(0.16, 0.18, 0.22), Color(0.56, 0.58, 0.62), Color(0.14, 0.22, 0.36), Color(0.44, 0.14, 0.15)][absi(v_id) % 4]
				_add_box(-3.6, 0.42, z_l, 1.82, 0.78, 4.4, ccol)
				_add_box(-3.6, 0.96, z_l + 0.15, 1.48, 0.52, 2.2, ccol * 0.78)
				var tail_em := 2.2 if lamp_on > 0.1 else 1.0
				_add_box(-4.26, 0.54, z_l + 2.24, 0.34, 0.16, 0.10, Color(1.0, 0.10, 0.06), 0.0, tail_em)
				_add_box(-2.94, 0.54, z_l + 2.24, 0.34, 0.16, 0.10, Color(1.0, 0.10, 0.06), 0.0, tail_em)
				if lamp_on > 0.15:
					_add_halo(-4.26, 0.54, z_l + 2.3, 1.8, Color(1.0, 0.12, 0.06))
					_add_halo(-2.94, 0.54, z_l + 2.3, 1.8, Color(1.0, 0.12, 0.06))

		# B. Oncoming opposite-carriageway traffic (x = +11.0 / +14.6 / +18.2, streaming toward +Z in either direction!)
		var rel_on := _odom * 1.92 + _drive_time * 8.0 + 42.0
		var spacing_on := lerpf(92.0, 38.0, traf)
		var base_on := floorf(rel_on / spacing_on) * spacing_on
		for k in range(-1, 7):
			var v_id := int(round((base_on + float(k) * spacing_on) / spacing_on))
			var z_l := -(base_on + float(k) * spacing_on - rel_on)
			if z_l > 22.0 or z_l < -172.0:
				continue
			var lane_x: float = [11.0, 14.6, 18.2][absi(v_id * 5 + 3) % 3]
			var is_hgv := _hash_u(v_id * 67 + 11) < 0.30
			if is_hgv:
				_add_box(lane_x, 1.75, z_l, 2.46, 3.15, 11.4, Color(0.68, 0.70, 0.74))
			else:
				var ccol: Color = [Color(0.20, 0.22, 0.25), Color(0.62, 0.64, 0.66), Color(0.18, 0.24, 0.34)][absi(v_id) % 3]
				_add_box(lane_x, 0.44, z_l, 1.82, 0.80, 4.4, ccol)
				_add_box(lane_x, 0.96, z_l - 0.15, 1.48, 0.52, 2.2, ccol * 0.78)
			# Twin warm-white oncoming headlights (bright at dusk/night/fog!)
			var hl_z := z_l + (5.75 if is_hgv else 2.24)
			var hl_y := 0.85 if is_hgv else 0.52
			var hl_em := 2.8 if lamp_on > 0.1 else 0.95
			_add_box(lane_x - 0.68, hl_y, hl_z, 0.30, 0.18, 0.12, Color(1.0, 0.96, 0.86), 0.0, hl_em)
			_add_box(lane_x + 0.68, hl_y, hl_z, 0.30, 0.18, 0.12, Color(1.0, 0.96, 0.86), 0.0, hl_em)
			if lamp_on > 0.12:
				_add_halo(lane_x - 0.68, hl_y, hl_z + 0.1, 2.8, Color(1.0, 0.95, 0.82))
				_add_halo(lane_x + 0.68, hl_y, hl_z + 0.1, 2.8, Color(1.0, 0.95, 0.82))

	_boxes_mm.visible_instance_count = _box_i
	_cyls_mm.visible_instance_count = _cyl_i
	_signs_mm.visible_instance_count = _sign_i
	_trees_mm.visible_instance_count = _tree_i
	_halos_mm.visible_instance_count = _halo_i


static func _hash_u(n: int) -> float:
	var x := sin(float(n) * 12.9898 + 78.233) * 43758.5453
	return x - floorf(x)
