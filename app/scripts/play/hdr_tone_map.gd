extends Node

## Colour description and HDR tone mapping (ideas #85). On each file it reads the source's video info and sets
## video.gdshader's colour uniforms: the Y'CbCr matrix (BT.709, BT.601, BT.2020), the range, the transfer (SDR, PQ,
## HLG) and BT.2020 primaries (converted to BT.709). HDR pictures are tone mapped to the display, so the content's
## peak lands on display white and greys keep their level. Two curves:
##   - the BT.2390 EETF with the engine's parameters (MediaSource.get_tone_mapping(info, target nits), engine fork
##     015fc1857b) when the engine has it: display white is the target brightness in nits (default 203, reference
##     white), lowered by the exposure (+1 stop: half the nits, everything brighter);
##   - else the app's own curve: linear light with reference white at 1.0, times the exposure (and 203 / target), with
##     everything above the knee compressed. The knee applies to this curve only (uses_engine_curve() is false).
## Exposure, knee and target brightness are remembered per environment (a dark cinema wants less).
##
## Content peak, best first: the file's MaxCLL (`max_cll`), its mastering display's peak (`mastering_display_luminance`
## .y, or `mastering_max_luminance`), else DEFAULT_PEAK_NITS. MaxCLL is capped by the mastering peak. With the engine
## curve the engine chooses the peak the same way and current["peak_nits"] is its value.
##
##   describe(video_info) -> {matrix, transfer, primaries_bt2020, full_range, peak_nits, peak_from}   (static)
##   current                 describe() of the open file
##   is_hdr() -> bool, text() -> "HDR10 (PQ), peak 1000 nits (mastering display)" or ""
##   enabled                 [hdr] tone_map: false clips the highlights instead (for comparison)
##   set_enabled(on), set_value("exposure" | "knee" | "target_nits", v), reset() (this environment), values
##   uses_engine_curve() -> bool     the BT.2390 curve from the engine is in use for HDR files
##   RANGES                  name -> [min, max, default, step]; exposure in stops
##   signal changed(values)
## Settings: [hdr] tone_map; [tonemap_<environment id>] exposure, knee, target_nits (only values that differ from the
## default).

signal changed(values: Dictionary)

const REF_WHITE_NITS := 203.0
const DEFAULT_PEAK_NITS := 1000.0
const RANGES := {
	"exposure": [-2.0, 2.0, 0.0, 0.1],
	"knee": [0.5, 0.95, 0.75, 0.01],
	"target_nits": [100.0, 400.0, 203.0, 1.0],
}
const TRANSFER_SDR := 0
const TRANSFER_PQ := 1
const TRANSFER_HLG := 2
const MATRIX_709 := 0
const MATRIX_601 := 1
const MATRIX_2020 := 2

var main: Node3D
var enabled := true
var values := {}
var current := describe({})
## The engine's tone mapping parameters for the open HDR file ({} without the engine curve).
var engine_params := {}
var _env := ""
var _info := {}


func _ready() -> void:
	enabled = bool(main.settings.get_value("hdr", "tone_map", true))
	main.environment_changed.connect(func(id: String, _l: float) -> void: load_for(id))
	main.file_opened.connect(_on_file_opened)
	load_for(main.env_id)


static func describe(info: Dictionary) -> Dictionary:
	var trc := str(info.get("color_transfer", "")).to_lower()
	var transfer := TRANSFER_SDR
	if trc == "smpte2084":
		transfer = TRANSFER_PQ
	elif trc == "arib-std-b67":
		transfer = TRANSFER_HLG
	elif str(info.get("hdr_transfer", "")).to_lower() == "hlg":
		transfer = TRANSFER_HLG
	elif str(info.get("hdr_transfer", "")).to_lower() == "pq" or bool(info.get("hdr", false)):
		transfer = TRANSFER_PQ
	# Dolby Vision profile 5 has no HDR10 base: the planes are Dolby's IPT-PQ-c2 signal (PQ, BT.2020), whatever the file
	# declares (usually nothing, so it showed as BT.709 SDR with a purple and green cast). The shader converts them
	# (uniform dovi); its range step stands in for the RPU's reshaping, so the range is limited.
	var dovi := 1 if int(info.get("dolby_vision_profile", -1)) == 5 else 0
	if dovi == 1:
		transfer = TRANSFER_PQ
	var prim := str(info.get("color_primaries", "")).to_lower()
	var known_prim := prim != "" and prim != "unknown" and prim != "unspecified"
	var bt2020 := prim == "bt2020" or (not known_prim and transfer != TRANSFER_SDR)
	var mtx := str(info.get("color_matrix", "")).to_lower()
	var matrix := MATRIX_709
	if mtx.begins_with("bt2020") or bool(info.get("matrix_bt2020", false)):
		matrix = MATRIX_2020
	elif mtx in ["bt470bg", "smpte170m", "bt601"]:
		matrix = MATRIX_601
	elif mtx == "" or mtx == "unknown" or mtx == "unspecified":
		var h := int(info.get("height", 0))
		if bt2020:
			matrix = MATRIX_2020
		elif h > 0 and h <= 576:
			matrix = MATRIX_601
	if dovi == 1:
		bt2020 = true
		matrix = MATRIX_2020
	var cll := float(info.get("max_cll", 0.0))
	var mastering := float(info.get("mastering_max_luminance", 0.0))
	var mdl: Variant = info.get("mastering_display_luminance")
	if mdl is Vector2 and (mdl as Vector2).y > 0.0:
		mastering = (mdl as Vector2).y
	var peak := DEFAULT_PEAK_NITS
	var from := "default"
	if cll > 0.0:
		peak = minf(cll, mastering) if mastering > 0.0 else cll
		from = "content light level"
	elif mastering > 0.0:
		peak = mastering
		from = "mastering display"
	return {"matrix": matrix, "transfer": transfer, "primaries_bt2020": bt2020,
			"full_range": dovi == 0 and (bool(info.get("full_range", false)) or str(info.get("color_range", "")) == "pc"),
			"dovi": dovi,
			"peak_nits": clampf(peak, REF_WHITE_NITS, 10000.0), "peak_from": from}


## The engine's BT.2390 tone mapping helper is there.
static func engine_curve_available() -> bool:
	return ClassDB.class_exists("MediaSource") and ClassDB.class_has_method("MediaSource", "get_tone_mapping")


func uses_engine_curve() -> bool:
	return not engine_params.is_empty()


func is_hdr() -> bool:
	return int(current["transfer"]) != TRANSFER_SDR


func text() -> String:
	if not is_hdr():
		return ""
	var kind := "HDR10 (PQ)" if int(current["transfer"]) == TRANSFER_PQ else "HLG"
	if int(current.get("dovi", 0)) == 1:
		kind = "DV profile 5 (IPT, as PQ)"
	return "%s, peak %d nits (%s)%s%s" % [kind,
			roundi(float(current["peak_nits"])), current["peak_from"], ", BT.2390" if uses_engine_curve() else "",
			"" if enabled else ", tone mapping off"]


func set_enabled(on: bool) -> void:
	enabled = on
	main.settings.set_value("hdr", "tone_map", null if on else false)
	_apply()


func load_for(env_id: String) -> void:
	_env = env_id
	values = {}
	for k: String in RANGES:
		values[k] = clampf(float(main.settings.get_value(_section(), k, RANGES[k][2])), RANGES[k][0], RANGES[k][1])
	_apply()


func set_value(key: String, v: float) -> void:
	if not RANGES.has(key):
		push_warning("Tone map: no '%s'" % key)
		return
	var r: Array = RANGES[key]
	v = clampf(snappedf(v, 0.001), r[0], r[1])
	values[key] = v
	main.settings.set_value(_section(), key, null if is_equal_approx(v, r[2]) else v)
	_apply()


func reset() -> void:
	for k: String in RANGES:
		main.settings.set_value(_section(), k, null)
	load_for(_env)


func _section() -> String:
	return "tonemap_" + _env


func _on_file_opened(_path: String) -> void:
	var src: Object = main.player.source
	_info = src.get_video_info() if src != null else {}
	current = describe(_info)
	_engine_params()
	if is_hdr():
		print("HDR: %s" % text())
	_apply()


## Display white in nits: the target brightness, lowered by the exposure.
func display_white_nits() -> float:
	return float(values.get("target_nits", REF_WHITE_NITS)) / pow(2.0, float(values.get("exposure", 0.0)))


func _engine_params() -> void:
	engine_params = {}
	if not is_hdr() or not engine_curve_available():
		return
	var ms: Object = ClassDB.instantiate("MediaSource")
	var tm: Variant = ms.call("get_tone_mapping", _info, display_white_nits())
	if tm is Dictionary and bool((tm as Dictionary).get("tone_mapping", false)):
		engine_params = tm
		current["peak_nits"] = float(engine_params.get("source_peak_nits", current["peak_nits"]))


func _apply() -> void:
	var m: ShaderMaterial = main.screen.material
	if m == null:
		return
	_engine_params()
	m.set_shader_parameter("yuv_matrix", int(current["matrix"]))
	m.set_shader_parameter("full_range", bool(current["full_range"]))
	m.set_shader_parameter("transfer", int(current["transfer"]))
	m.set_shader_parameter("primaries_bt2020", bool(current["primaries_bt2020"]))
	m.set_shader_parameter("dovi", int(current.get("dovi", 0)))
	m.set_shader_parameter("tm_enabled", enabled)
	m.set_shader_parameter("tm_peak", float(current["peak_nits"]) / REF_WHITE_NITS)
	m.set_shader_parameter("tm_exposure", REF_WHITE_NITS / display_white_nits())
	m.set_shader_parameter("tm_curve", 1 if uses_engine_curve() else 0)
	if uses_engine_curve():
		m.set_shader_parameter("tm_src_min_pq", float(engine_params["source_min_pq"]))
		m.set_shader_parameter("tm_src_max_pq", float(engine_params["source_max_pq"]))
		m.set_shader_parameter("tm_max_lum", float(engine_params["max_luminance"]))
		m.set_shader_parameter("tm_knee_start", float(engine_params["knee_start"]))
		m.set_shader_parameter("tm_target_nits", float(engine_params["target_peak_nits"]))
	m.set_shader_parameter("tm_knee", float(values.get("knee", RANGES["knee"][2])))
	changed.emit(values)
