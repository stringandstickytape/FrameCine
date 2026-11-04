extends Node3D

## One list on the tablet (ui/tablet.gd): rows of text, one under another, in a rectangle of its pane; scrolled by
## dragging when they don't all fit (the user, 2026-11-04: push through it, drag, pull back out).
##
## A grab (the trigger held on the list, or a controller's tip pushed through it) moves the rows with the point, and
## they carry on a little after it lets go (FRICTION). A grab let go within TAP metres of where it began is a tap on
## the row it began on: picked(index). A list that fits can't scroll, so it picks at once, on the press. The tablet
## decides what a pick does (select() marks a row).
##
## The rows are a pool, as many as the rectangle shows, filled from the items as it scrolls. A row part way out at
## the top or bottom is cut there (its fill by the shader's clip, its text faded by how much of it is inside). A thin
## thumb at the right shows where a list that scrolls is.
##
##   rect (the pane's space, metres), items (texts), selected (-1 none), hover
##   layout(rect, style), set_items(texts, keep_scroll := false), select(i), set_hover(local) (null: none)
##   scroll (metres the rows have moved up), max_scroll(), can_scroll(), set_scroll(v), row_at(local) -> int (-1)
##   grab(local) -> bool, drag(local), release() -> bool (true when it picked), grabbing

signal picked(index: int)

## Metres a grab may move and still be a tap.
const TAP := 0.006
## How fast a flick slows (per second), and the speed it stops at (metres per second).
const FRICTION := 5.0
const STOP := 0.01

var tablet: Node3D
## The visual middle of capitals over the baseline, a share of the font's size (the tablet's CAP_MIDDLE).
var cap_middle := 0.36
var rect := Rect2()
var items: Array[String] = []
var selected := -1
var hover := -1
var scroll := 0.0
var grabbing := false
var _style := {}
var _velocity := 0.0
var _grab_y := 0.0
var _grab_scroll := 0.0
var _grab_row := -1
var _moved := 0.0
var _picked_on_press := false
var _last_y := 0.0
var _last_t := 0.0
var _fills: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _marker: MeshInstance3D
var _thumb: MeshInstance3D
## Item index -> its text cut to the row (ellipsis), until the items or the layout change.
var _fitted := {}


func _ready() -> void:
	_marker = tablet.make_quad("Marker", "list_marker", self, 2)
	_thumb = tablet.make_quad("Thumb", "list_thumb", self, 2)


func _process(delta: float) -> void:
	if grabbing or _velocity == 0.0:
		return
	var before := scroll
	set_scroll(scroll + _velocity * delta)
	_velocity *= exp(-FRICTION * delta)
	if absf(_velocity) < STOP or scroll == before:
		_velocity = 0.0


## Places the list in its pane and styles it (the tablet's "list" style); makes as many rows as it shows.
func layout(r: Rect2, list_style: Dictionary) -> void:
	rect = r
	_style = list_style
	_fitted.clear()
	var want := int(ceil(rect.size.y / _row_height())) + 1
	while _fills.size() < want:
		var k := _fills.size()
		_fills.append(tablet.make_quad("Row%d" % k, "list_row", self, 1))
		_labels.append(tablet.make_label("RowText%d" % k, HORIZONTAL_ALIGNMENT_LEFT, self))
	set_scroll(scroll, true)


func set_items(texts: Array[String], keep_scroll := false) -> void:
	items = texts.duplicate()
	_fitted.clear()
	if selected >= items.size():
		selected = -1
	if hover >= items.size():
		hover = -1
	if not keep_scroll:
		_velocity = 0.0
	set_scroll(scroll if keep_scroll else 0.0, true)


func select(i: int) -> void:
	selected = i if i >= 0 and i < items.size() else -1
	_refresh()


## The row under a point in the pane's space lights up (null: none).
func set_hover(local: Variant) -> void:
	var i := row_at(local) if local is Vector2 else -1
	if i != hover:
		hover = i
		_refresh()


func max_scroll() -> float:
	return maxf(items.size() * _row_height() - rect.size.y, 0.0)


func can_scroll() -> bool:
	return max_scroll() > 0.0


func set_scroll(v: float, force := false) -> void:
	v = clampf(v, 0.0, max_scroll())
	if v == scroll and not force:
		return
	scroll = v
	_refresh()


## The item at a point in the pane's space, or -1.
func row_at(local: Vector2) -> int:
	if not rect.has_point(local):
		return -1
	var i := int(floor((rect.end.y - local.y + scroll) / _row_height()))
	return i if i >= 0 and i < items.size() else -1


# --- Grabbing -----------------------------------------------------------------------------------------------------

## A grab at a point in the pane's space; false when it isn't on the list.
func grab(local: Vector2) -> bool:
	if not rect.has_point(local):
		return false
	grabbing = true
	_velocity = 0.0
	_grab_y = local.y
	_grab_scroll = scroll
	_grab_row = row_at(local)
	_moved = 0.0
	_last_y = local.y
	_last_t = _now()
	_picked_on_press = false
	if not can_scroll() and _grab_row >= 0:
		_picked_on_press = true
		picked.emit(_grab_row)
	return true


## The grab moves (the point need not stay on the list): the rows move with it.
func drag(local: Vector2) -> void:
	if not grabbing:
		return
	_moved = maxf(_moved, absf(local.y - _grab_y))
	if can_scroll():
		set_scroll(_grab_scroll + local.y - _grab_y)
	var now := _now()
	var dt := now - _last_t
	if dt > 0.0:
		_velocity = lerpf(_velocity, (local.y - _last_y) / dt, 0.5)
		_last_y = local.y
		_last_t = now


## Lets go: a tap picks the row it began on, a drag carries on a little. True when it picked (now or on the press).
func release() -> bool:
	if not grabbing:
		return false
	grabbing = false
	if _moved < TAP:
		_velocity = 0.0
		if not _picked_on_press and _grab_row >= 0:
			picked.emit(_grab_row)
			return true
		return _picked_on_press
	if not can_scroll():
		_velocity = 0.0
	return false


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


# --- Drawing ------------------------------------------------------------------------------------------------------

func _row_height() -> float:
	return float(_style.get("row_height", 0.02))


func _refresh() -> void:
	if _style.is_empty() or tablet == null:
		return
	var h := _row_height()
	var scrolls := can_scroll()
	var thumb_w := float(_style["thumb_width"])
	var w := rect.size.x - (thumb_w * 2.0 if scrolls else 0.0)
	var first := int(floor(scroll / h))
	var inset := float(_style["text_inset"])
	var text_size := float(_style["text"]["size"])
	_marker.visible = false
	for k in _fills.size():
		var i := first + k
		var fill := _fills[k]
		var l := _labels[k]
		var on := i >= 0 and i < items.size()
		fill.visible = on
		l.visible = on
		if not on:
			continue
		var centre := Vector2(rect.position.x + w * 0.5, rect.end.y - h * (i + 0.5) + scroll)
		_place(fill, centre, Vector2(w, h))
		var key := "selected_fill" if i == selected else ("hover_fill" if i == hover else "fill")
		_mat(fill).set_shader_parameter("fill_color", Color.html(_style[key]))
		if not _fitted.has(i):
			_fitted[i] = tablet.fit_text(l, items[i], w - inset * 2.0, _style["text"])
		l.text = _fitted[i]
		tablet.place_text(l, _style["text"], Vector2(rect.position.x + inset, centre.y))
		var c := Color.html(_style["selected_color"] if i == selected else _style["text"]["color"])
		# The text's share inside the list, top to bottom: a row half out fades to nothing at the edge.
		var half := text_size * cap_middle
		var inside := (minf(centre.y + half, rect.end.y) - maxf(centre.y - half, rect.position.y)) / (half * 2.0)
		l.set_meta("clip", clampf(inside, 0.0, 1.0))
		l.visible = inside > 0.01
		tablet.tint(l, c)
		if i == selected:
			var mw := float(_style["marker_width"])
			_marker.visible = mw > 0.0
			_place(_marker, Vector2(rect.position.x + mw * 0.5, centre.y), Vector2(maxf(mw, 0.0001), h * 0.6))
	_thumb.visible = scrolls
	if scrolls:
		var content := items.size() * h
		var th := maxf(rect.size.y * rect.size.y / content, 0.01)
		var top := rect.end.y - (scroll / max_scroll()) * (rect.size.y - th)
		_place(_thumb, Vector2(rect.end.x - thumb_w * 0.5, top - th * 0.5), Vector2(thumb_w, th))


## A quad at a centre in the pane's space, cut to the list's rectangle.
func _place(mi: MeshInstance3D, centre: Vector2, size: Vector2) -> void:
	(mi.mesh as QuadMesh).size = size
	var m := _mat(mi)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("clip", Vector4(rect.position.x - centre.x, rect.position.y - centre.y,
			rect.end.x - centre.x, rect.end.y - centre.y))
	mi.position = Vector3(centre.x, centre.y, mi.position.z)


func _mat(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial
