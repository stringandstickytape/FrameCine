## Preload this script to use it (no class_name: the project must run without the editor's class cache).
extends RefCounted

const VideoMode := preload("res://scripts/video_mode.gd")

## How a video file is laid out and projected: projection (flat / 180 / 360 / fisheye / dual fisheye 360), stereo layout
## (mono / side by side / top-bottom), half (anamorphic: each eye squeezed to half width or height), swapped eyes,
## fisheye field of view. Also the guess from a file name and size.
##
## FISHEYE is one image circle per eye, both looking ahead (VR180 cameras). DUAL_FISHEYE is a 360 camera's raw frame:
## two circles side by side, the left one looking ahead and the right one looking back, one picture for both eyes
## (always mono). Its lens values (field of view, circle, alignment) are a lens profile, not part of the mode
## (scripts/play/dual_fisheye.gd).

enum Proj { FLAT, EQUIRECT_180, EQUIRECT_360, FISHEYE, DUAL_FISHEYE }
enum Layout { MONO, SBS, TB }

const PROJECTION_IDS: Array[String] = ["flat", "180", "360", "fisheye", "dualfisheye"]
const LAYOUT_IDS: Array[String] = ["mono", "sbs", "tb"]
const PROJECTION_NAMES: Array[String] = ["Flat", "180°", "360°", "Fisheye", "Dual fisheye 360°"]
const LAYOUT_NAMES: Array[String] = ["Mono", "Side by side", "Top / bottom"]

var projection: Proj = Proj.FLAT
var layout: Layout = Layout.MONO
## Half-width SBS / half-height TB: each eye is stored squeezed and is shown at the full frame's aspect.
var half := false
## Right eye first.
var swap := false
## Fisheye field of view, degrees (equidistant lens model).
var fisheye_fov := 180.0


static func make(p_projection: Proj, p_layout: Layout, p_half := false, p_swap := false,
		p_fov := 180.0) -> VideoMode:
	var m := VideoMode.new()
	m.projection = p_projection
	m.layout = p_layout
	m.half = p_half
	m.swap = p_swap
	m.fisheye_fov = p_fov
	m.normalise()
	return m


## A dual fisheye frame is one picture for both eyes: no stereo layout, half or swap.
func normalise() -> void:
	if projection == Proj.DUAL_FISHEYE:
		layout = Layout.MONO
		half = false
		swap = false


func copy() -> VideoMode:
	return VideoMode.make(projection, layout, half, swap, fisheye_fov)


func equals(other: VideoMode) -> bool:
	return other != null and to_id() == other.to_id()


func is_spherical() -> bool:
	return projection != Proj.FLAT


func is_stereo() -> bool:
	return layout != Layout.MONO


## Compact id, e.g. "flat_sbs_half", "360_tb", "fisheye_sbs_swap_fov200", "dualfisheye_mono". Stored in settings and
## accepted by --mode=.
func to_id() -> String:
	var parts: Array[String] = [PROJECTION_IDS[projection], LAYOUT_IDS[layout]]
	if half and layout != Layout.MONO:
		parts.append("half")
	if swap and layout != Layout.MONO:
		parts.append("swap")
	if projection == Proj.FISHEYE and not is_equal_approx(fisheye_fov, 180.0):
		parts.append("fov%d" % roundi(fisheye_fov))
	return "_".join(parts)


static func from_id(id: String) -> VideoMode:
	var m := VideoMode.new()
	for part in id.to_lower().split("_", false):
		if part in PROJECTION_IDS:
			m.projection = PROJECTION_IDS.find(part) as Proj
		elif part == "dfe":
			m.projection = Proj.DUAL_FISHEYE
		elif part in LAYOUT_IDS:
			m.layout = LAYOUT_IDS.find(part) as Layout
		elif part == "half":
			m.half = true
		elif part == "swap":
			m.swap = true
		elif part.begins_with("fov") and part.trim_prefix("fov").is_valid_float():
			m.fisheye_fov = part.trim_prefix("fov").to_float()
	m.normalise()
	return m


func describe() -> String:
	if projection == Proj.DUAL_FISHEYE:
		return PROJECTION_NAMES[projection]
	var text := PROJECTION_NAMES[projection]
	if projection == Proj.FISHEYE:
		text += " %d°" % roundi(fisheye_fov)
	text += ", " + LAYOUT_NAMES[layout].to_lower()
	if half and layout != Layout.MONO:
		text += " (half)"
	if swap and layout != Layout.MONO:
		text += ", eyes swapped"
	return text


## Size in pixels of one eye's picture as stored in a frame of the given size.
func eye_pixels(frame_size: Vector2) -> Vector2:
	match layout:
		Layout.SBS:
			return Vector2(frame_size.x * 0.5, frame_size.y)
		Layout.TB:
			return Vector2(frame_size.x, frame_size.y * 0.5)
	return frame_size


## Width / height of one eye's picture as it should be shown (flat projection).
func display_aspect(frame_size: Vector2) -> float:
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return 16.0 / 9.0
	var eye := frame_size if half else eye_pixels(frame_size)
	return eye.x / eye.y


## Guesses the mode from a file name (tags such as _SBS, _TB, _3D, HSBS, _180, _360, fisheye, fisheye200, _LR,
## _RL, dualfisheye, dual_fisheye, dfe) and, where the name is ambiguous, from the frame size (0 = unknown).
## Camera names: a 360 camera's own file (360_0042.MP4, 360_0010.JPG) is its raw dual fisheye frame; the
## phone app's stitched copy (SAM_100_0001.mp4) is an ordinary 360. Both only with a 2:1 frame (or an unknown size).
static func guess(file_name: String, width := 0, height := 0) -> VideoMode:
	var m := VideoMode.new()
	var name := file_name.get_file().get_basename().to_lower()
	var tokens := _tokens(name)
	var aspect := float(width) / float(height) if width > 0 and height > 0 else 0.0
	var two_to_one := aspect == 0.0 or absf(aspect - 2.0) < 0.05
	if is_dual_fisheye_name(name) or (two_to_one and is_camera360_raw_name(name)):
		m.projection = Proj.DUAL_FISHEYE
		return m
	if two_to_one and _matches(name, "^sam_100_[0-9]{4}$"):
		m.projection = Proj.EQUIRECT_360
		return m

	# Proj.
	var fisheye := _has_any(tokens, ["fisheye", "fish"]) or name.contains("fisheye")
	if fisheye:
		m.projection = Proj.FISHEYE
		for fov in [190, 200, 210, 220, 230]:
			if name.contains(str(fov)):
				m.fisheye_fov = fov
				break
	elif _matches(name, "(^|[^0-9])360([^0-9]|$)"):
		m.projection = Proj.EQUIRECT_360
	elif _matches(name, "(^|[^0-9])180([^0-9]|$)"):
		m.projection = Proj.EQUIRECT_180
	elif "vr" in tokens and is_equal_approx(snappedf(aspect, 0.05), 2.0):
		m.projection = Proj.EQUIRECT_180

	# Layout, from tags. "h-sbs" / "half sbs" style tags are two tokens; "hsbs" / "3dh" one.
	var explicit_half := false
	var explicit_full := false
	for i in tokens.size():
		var t: String = tokens[i]
		var prev: String = tokens[i - 1] if i > 0 else ""
		var sbs_tag := t in ["sbs", "lr", "rl", "sidebyside", "3dlr"]
		var tb_tag := t in ["tb", "bt", "ou", "overunder", "topbottom", "3dtb"]
		if sbs_tag or tb_tag:
			m.layout = Layout.SBS if sbs_tag else Layout.TB
			if t in ["rl", "bt"]:
				m.swap = true
			if prev in ["h", "half"]:
				explicit_half = true
			elif prev in ["f", "full"]:
				explicit_full = true
		elif t in ["hsbs", "halfsbs", "3dh", "sbshalf"]:
			m.layout = Layout.SBS
			explicit_half = true
		elif t in ["fsbs", "fullsbs", "sbsfull"]:
			m.layout = Layout.SBS
			explicit_full = true
		elif t in ["htb", "hou", "halfou", "halftb", "3dv", "tbhalf", "ouhalf"]:
			m.layout = Layout.TB
			explicit_half = true
		elif t in ["ftb", "fou", "fullou", "fulltb"]:
			m.layout = Layout.TB
			explicit_full = true
		elif t in ["half"] and m.layout != Layout.MONO:
			explicit_half = true
		elif t == "swap":
			m.swap = true
	# An explicit MONO / 2D tag (with no layout tag) stops the 3D and frame-shape guesses below.
	var stereo_hint := m.layout != Layout.MONO or _has_any(tokens, ["mono", "2d"])
	if not stereo_hint and _has_any(tokens, ["3d", "stereo"]):
		# 3D without a layout tag: by shape (full SBS is very wide, full TB tall), else the common half SBS.
		m.layout = Layout.TB if aspect > 0.0 and aspect < 1.2 else Layout.SBS
		stereo_hint = true
	if not stereo_hint and aspect > 0.0 and m.is_spherical():
		# Standard spherical frames: 180 mono is 1:1 and 180 SBS 2:1; 360 mono is 2:1 and 360 TB 1:1.
		if m.projection in [Proj.EQUIRECT_180, Proj.FISHEYE] and aspect > 1.6:
			m.layout = Layout.SBS
		elif m.projection == Proj.EQUIRECT_360 and aspect < 1.4:
			m.layout = Layout.TB

	# Half or full: only matters for flat (the screen's aspect); spherical maps by angle. Flat: by tag, else by shape
	# (full SBS is wider than 2.5:1, full TB not much wider than 1.2:1), else half, the common release format.
	if m.layout != Layout.MONO:
		if m.is_spherical() or explicit_full:
			m.half = false
		elif explicit_half:
			m.half = true
		elif aspect > 0.0:
			m.half = aspect < 2.5 if m.layout == Layout.SBS else aspect > 1.2
		else:
			m.half = true
	return m


## The --mode= argument: a full id (flat_sbs_half, 360_tb, fisheye_sbs_fov200, ...) or a short form such as flat,
## sbs, hsbs, fsbs, tb, ou, hou, 3d, 180, 180sbs, 360, 360tb, fisheye, mono. Short forms are read like a file-name
## tag, so half/full and the fisheye layout come from the frame size when it is known (0 = unknown).
static func from_arg(text: String, width := 0, height := 0) -> VideoMode:
	var t := text.strip_edges().to_lower().replace("-", "_")
	if t == "":
		return VideoMode.new()
	if from_id(t).to_id() == t:
		return from_id(t)
	# "180sbs" -> "180 sbs", "360tb" -> "360 tb", then read it like a file-name tag.
	var spaced := RegEx.create_from_string("(180|360)([a-z])").sub(t, "$1 $2", true)
	var m := guess(spaced, width, height)
	if m.projection == Proj.FISHEYE and m.layout == Layout.MONO and not "mono" in _tokens(spaced) \
			and (width == 0 or float(width) / maxf(height, 1) > 1.6):
		# Fisheye video is almost always a dual-lens side-by-side recording.
		m.layout = Layout.SBS
	return m


## A dual fisheye 360 tag in a (lower-case) name: "dualfisheye", "dual_fisheye", "dual-fisheye", "dual fisheye" or
## "dfe" as a word of its own. The plain fisheye tags stay the stereo (VR180-style) fisheye.
static func is_dual_fisheye_name(name: String) -> bool:
	name = name.to_lower()
	return _matches(name, "dual[ ._-]?fisheye") or "dfe" in _tokens(name)


## A 360 camera's own file name (360_NNNN), which holds its raw dual fisheye frame.
static func is_camera360_raw_name(name: String) -> bool:
	return _matches(name.get_file().get_basename().to_lower(), "^360_[0-9]{4}$")


static func _tokens(name: String) -> PackedStringArray:
	var re := RegEx.create_from_string("[a-z0-9]+")
	var out := PackedStringArray()
	for found in re.search_all(name):
		out.append(found.get_string())
	return out


static func _has_any(tokens: PackedStringArray, words: Array) -> bool:
	for w: String in words:
		if w in tokens:
			return true
	return false


static func _matches(text: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
