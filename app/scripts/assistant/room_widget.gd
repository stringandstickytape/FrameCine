extends Node3D

## A widget on a part of an assistant's room (room_schema.gd, WIDGETS): the assistant only names it and its options;
## the drawing is this app code. A face (a quad on the part's front, top or cap) shows a small offscreen canvas that
## is drawn again only when what it shows changes, at most once a second (film_progress: ten times a second), so a
## room of widgets costs next to nothing per frame. screen_glow has no face: it is a material (assistant_room.gd).

const InfoOverlay := preload("res://scripts/info_overlay.gd")
const EndTime := preload("res://scripts/play/end_time.gd")
const RoomSchema := preload("res://scripts/assistant/room_schema.gd")

var kind := ""
var options := {}
## The face's size in metres, and whether it is round (a cylinder's cap).
var face := Vector2(0.4, 0.4)
var round_face := false
var _vp: SubViewport
var _canvas: Face
var _left := 0.0
var _last := ""


class Face extends Control:
	var widget: Node

	func _draw() -> void:
		widget.draw_face(self)


func _ready() -> void:
	var style := str(options.get("style", ""))
	var square: bool = round_face or (kind == "clock" and style == "analog") or (kind == "film_progress"
			and style == "ring")
	var h := 256
	var w := h if square else clampi(int(h * face.x / maxf(face.y, 0.01)), 64, 1024)
	_vp = SubViewport.new()
	_vp.size = Vector2i(w, h)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_canvas = Face.new()
	_canvas.widget = self
	_canvas.size = Vector2(w, h)
	_vp.add_child(_canvas)
	var quad := QuadMesh.new()
	quad.size = face
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _vp.get_texture()
	var mi := MeshInstance3D.new()
	mi.name = "Face"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = 0.1 if kind == "film_progress" else 1.0
	var key := _key()
	if key != _last:
		_last = key
		_canvas.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _main() -> Node:
	var tree := get_tree()
	return tree.current_scene if tree != null else null


## What the face shows now, as text: drawn again only when it changes.
func _key() -> String:
	var m := _main()
	var has_player: bool = m != null and "player" in m
	match kind:
		"clock":
			var t := Time.get_time_dict_from_system()
			return "%02d:%02d" % [t["hour"], t["minute"]] + (":%02d" % t["second"] if options.get("style") == "analog"
					else "")
		"film_progress":
			if not has_player or m.player.get_duration() <= 0.0:
				return "0"
			return str(roundi(m.player.get_position() / m.player.get_duration() * 400.0))
		"now_playing":
			return m.display_title() if has_player and str(m.current_path) != "" else "Nothing playing"
		"end_time":
			var f: Node = m.get("features") if m != null else null
			var text: String = f.end_text() if f != null and float(f.remaining()) > 0.0 else ""
			return text if text != "" else "-"
		"battery":
			return battery_text()
	return kind


func battery_text() -> String:
	var parts: Array[String] = []
	var pct := InfoOverlay.read_battery()
	parts.append("Headset %d %%" % pct if pct >= 0 else "Headset -")
	var m := _main()
	var ui: Node = m.get("ui") if m != null else null
	var cb: Node = ui.get("controller_battery") if ui != null else null
	if bool(options.get("controllers", true)) and cb != null:
		var levels: Dictionary = cb.get("levels")
		for side: String in levels:
			parts.append("%s %d %%" % [side.left(1).to_upper(), int(levels[side])])
	return "  ".join(parts)


func draw_face(c: Control) -> void:
	var size := c.size
	var fg := RoomSchema.to_color(options.get("color", "#f2f2f2"))
	var bg := RoomSchema.to_color(options.get("background", "#1c1c1c"))
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if round_face:
		c.draw_circle(centre, radius, bg)
	else:
		c.draw_rect(Rect2(Vector2.ZERO, size), bg)
	var font := ThemeDB.fallback_font
	var m := _main()
	match kind:
		"clock":
			var t := Time.get_time_dict_from_system()
			if options.get("style") == "analog":
				var r := radius * 0.9
				for i in 12:
					var a := TAU * i / 12.0
					var d := Vector2(sin(a), -cos(a))
					c.draw_line(centre + d * r * 0.85, centre + d * r, fg, 4.0 if i % 3 == 0 else 2.0, true)
				var hours := (int(t["hour"]) % 12 + int(t["minute"]) / 60.0) / 12.0 * TAU
				var mins := (int(t["minute"]) + int(t["second"]) / 60.0) / 60.0 * TAU
				c.draw_line(centre, centre + Vector2(sin(hours), -cos(hours)) * r * 0.5, fg, 7.0, true)
				c.draw_line(centre, centre + Vector2(sin(mins), -cos(mins)) * r * 0.78, fg, 4.0, true)
				c.draw_circle(centre, 6.0, fg)
			else:
				var h24 := bool(options.get("hours_24", EndTime.use_24h))
				var h := int(t["hour"])
				var text := "%02d:%02d" % [h, t["minute"]] if h24 else "%d:%02d" % [12 if h % 12 == 0 else h % 12,
						t["minute"]]
				_text(c, font, text, fg)
		"film_progress":
			var f := 0.0
			if m != null and "player" in m and m.player.get_duration() > 0.0:
				f = clampf(m.player.get_position() / m.player.get_duration(), 0.0, 1.0)
			if options.get("style") == "ring":
				c.draw_arc(centre, radius * 0.8, 0.0, TAU, 64, fg.darkened(0.7), radius * 0.15, true)
				if f > 0.0:
					c.draw_arc(centre, radius * 0.8, -PI / 2.0, -PI / 2.0 + TAU * f, 64, fg, radius * 0.15, true)
			else:
				var pad := size.y * 0.3
				var bar := Rect2(Vector2(pad, pad), Vector2(size.x - 2.0 * pad, size.y - 2.0 * pad))
				c.draw_rect(bar, fg.darkened(0.7))
				c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), fg)
		_:
			_text(c, font, _key(), fg)


## One line of text, as large as fits.
func _text(c: Control, font: Font, text: String, colour: Color) -> void:
	var size := c.size
	var fs := int(size.y * 0.5)
	while fs > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x * 0.9:
		fs -= 2
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
