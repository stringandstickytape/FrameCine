extends RefCounted

## Container metadata first (ideas #25): the stereo and spherical metadata the demuxer exposes (Matroska StereoMode and
## Projection, MP4 st3d / sv3d, read by FFmpeg as stereo-3D and spherical side data) decides the mode before the guess
## from the file name. Static helpers; preload to use.
##
## Keys read from VideoSource.get_video_info() (MediaSource, engine fork, modules/hwvideo/media_source_extras.cpp; on
## an older engine they are absent and nothing changes). Both the engine's names and the longer ones first proposed
## are accepted:
##   stereo_mode       "", "2d", "sbs" / "side_by_side", "tb" / "top_bottom", "unspecified", or another FFmpeg layout
##                     ("frame_sequence", "checkerboard", "lines", "columns", "sbs_quincunx")
##   stereo_inverted   right eye first
##   projection        "", "equirectangular" (tiles included, with bounds), "half_equirectangular", "fisheye",
##                     "cubemap", "rectilinear", "parametric_immersive", "other"
##   projection_fov    Vector2(horizontal, vertical) degrees: an equirectangular picture 200° or less wide is a 180
##   projection_bounds Vector4(left, top, right, bottom) cropped fractions (also bound_left / bound_right)
##   stereo_fov        horizontal field of view in degrees (fisheye lenses; also stereo_hfov)
##
## from_info(info, file_name, width, height) -> {mode: VideoMode or null, reason: String, local: String}
##   mode null: the metadata says nothing usable (absent, "2d" alone, or a layout or projection the app can't show);
##   reason says why in that case too, for the footer ("Container says cubemap; not supported yet"). reason is
##   English (the dev link, the log); local is the same in the menus' language (docs/i18n.md), absent with no reason.
## What the metadata doesn't say is filled in from the file-name guess: a projection without a stereo layout keeps the
## guess's layout (and its frame-shape rule), a stereo layout without a projection is flat. Half or full for flat SBS
## / TB comes from the frame shape as in the guess.

const VideoMode := preload("res://scripts/video_mode.gd")


static func from_info(info: Dictionary, file_name: String, width := 0, height := 0) -> Dictionary:
	var stereo := str(info.get("stereo_mode", "")).to_lower()
	stereo = {"sbs": "side_by_side", "tb": "top_bottom", "unspecified": "unspec"}.get(stereo, stereo)
	var projection := str(info.get("projection", "")).to_lower()
	if stereo in ["", "2d", "mono", "unspec"] and projection in ["", "rectilinear"]:
		# Nothing, or only "2d": many muxers write StereoMode 0 by default, so that alone doesn't overrule the name.
		return {"mode": null, "reason": ""}
	var guess := VideoMode.guess(file_name, width, height)
	var m := guess.copy()
	var parts: Array[String] = []

	match projection:
		"equirectangular":
			var cropped := float(info.get("bound_left", 0.0)) + float(info.get("bound_right", 0.0))
			var bounds: Variant = info.get("projection_bounds")
			if bounds is Vector4:
				cropped = maxf(cropped, (bounds as Vector4).x + (bounds as Vector4).z)
			var fov: Variant = info.get("projection_fov")
			var half := cropped >= 0.4 or (fov is Vector2 and (fov as Vector2).x > 0.0 and (fov as Vector2).x <= 200.0)
			m.projection = VideoMode.Proj.EQUIRECT_180 if half else VideoMode.Proj.EQUIRECT_360
			parts.append("180°" if half else "360°")
		"half_equirectangular":
			m.projection = VideoMode.Proj.EQUIRECT_180
			parts.append("180°")
		"fisheye":
			m.projection = VideoMode.Proj.FISHEYE
			var lens := float(info.get("stereo_fov", info.get("stereo_hfov", 0.0)))
			var pf: Variant = info.get("projection_fov")
			if lens <= 0.0 and pf is Vector2:
				lens = (pf as Vector2).x
			if lens >= 120.0 and lens <= 240.0:
				m.fisheye_fov = lens
			parts.append("fisheye") # i18n
		"cubemap", "equirectangular_tile", "parametric_immersive", "other":
			var what := projection.replace("_", " ")
			return {"mode": null, "reason": "Container says %s; not supported yet" % what,
					"local": TranslationServer.translate("Container says %s; not supported yet") % what}
		_:
			if stereo != "" and guess.is_spherical():
				pass  # The name's projection stands; the metadata gives the layout.
			else:
				m.projection = VideoMode.Proj.FLAT

	var stereo_known := true
	match stereo:
		"side_by_side":
			m.layout = VideoMode.Layout.SBS
			parts.append("side by side") # i18n
		"top_bottom":
			m.layout = VideoMode.Layout.TB
			parts.append("top / bottom") # i18n
		"2d", "mono":
			m.layout = VideoMode.Layout.MONO
			parts.append("mono") # i18n
		"", "unspec":
			stereo_known = false
		_:
			if parts.is_empty():
				var what := stereo.replace("_", " ")
				return {"mode": null, "reason": "Container says %s 3D; not supported" % what,
						"local": TranslationServer.translate("Container says %s 3D; not supported") % what}
			stereo_known = false
	if stereo_known:
		m.swap = bool(info.get("stereo_inverted", false)) and m.layout != VideoMode.Layout.MONO
		if m.swap:
			parts.append("right eye first") # i18n
	elif m.is_spherical() and m.layout == VideoMode.Layout.MONO and width > 0 and height > 0:
		# The guess's frame-shape rule, for a projection that came from the metadata.
		var aspect := float(width) / float(height)
		if m.projection in [VideoMode.Proj.EQUIRECT_180, VideoMode.Proj.FISHEYE] and aspect > 1.6:
			m.layout = VideoMode.Layout.SBS
		elif m.projection == VideoMode.Proj.EQUIRECT_360 and aspect < 1.4:
			m.layout = VideoMode.Layout.TB

	if m.layout == VideoMode.Layout.MONO or m.is_spherical():
		m.half = false
	elif width > 0 and height > 0:
		var a := float(width) / float(height)
		m.half = a < 2.5 if m.layout == VideoMode.Layout.SBS else a > 1.2
	else:
		m.half = guess.half if guess.layout == m.layout else true
	var local: Array[String] = []
	for part in parts:
		local.append(TranslationServer.translate(part))
	return {"mode": m, "reason": "container: " + ", ".join(parts),
			"local": TranslationServer.translate("container: %s") % ", ".join(local)}
