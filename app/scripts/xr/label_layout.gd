extends Resource

## Our controller label layout (xr/controller_labels_layout.tres), authored offline with tools/label_layout.tscn on the
## runtime's controller model (--dump-render-models). Each entry is one printed legend: where it sits in the runtime
## model's own space (metres), so the same data serves the runtime model on the device and our own model registered
## to it. Keyed by input (the physical spot: "a", "thumbstick", "trigger", ...), not by action: which action an input
## carries depends on the profile the runtime binds; the text comes from the bindings (main.gd CONTROL_LABELS).
##
## The transform places the print (scripts/xr/label_surface.gd): Y points out of the surface, the text runs along +X and
## its lines go down along +Z, centred on the origin. The size follows from the legend and line_height per line. Depth
## is how far the print looks for the surface along Y.

const LabelFont := preload("res://scripts/xr/label_font.gd")
## Metres per text line of print with no entry of its own: a capital is about 2.7 mm tall.
const DEFAULT_LINE := 0.0045

## [{"side": "left"|"right", "input": String, "node": model node it sits by (reference only), "transform":
## Transform3D, "line_height": metres per text line, "depth": how far to look for the surface, "width": the room along
## the text; a longer legend is printed smaller, in that state only}]
@export var entries: Array[Dictionary] = []


func find(side: String, input: String) -> Dictionary:
	for e in entries:
		if e.get("side") == side and e.get("input") == input:
			return e
	return {}


func has_side(side: String) -> bool:
	for e in entries:
		if e.get("side") == side:
			return true
	return false


func set_entry(side: String, input: String, node: String, xform: Transform3D, line_height: float, depth: float,
		width: float) -> void:
	var e := {"side": side, "input": input, "node": node, "transform": xform.orthonormalized(),
			"line_height": line_height, "depth": depth, "width": width}
	for i in entries.size():
		if entries[i].get("side") == side and entries[i].get("input") == input:
			entries[i] = e
			return
	entries.append(e)


func remove_entry(side: String, input: String) -> void:
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].get("side") == side and entries[i].get("input") == input:
			entries.remove_at(i)


## The printed size of a legend: (text width, depth, text height), tight on its capitals, at fitted_line() metres per
## text line, and the entry's depth.
static func print_size(entry: Dictionary, text: String) -> Vector3:
	var size: Vector2 = LabelFont.shape(text)["size"] * metres_per_em(fitted_line(entry, text))
	return Vector3(size.x, float(entry.get("depth", 0.012)), size.y)


## The entry's line height, smaller for a legend wider than the entry's room.
static func fitted_line(entry: Dictionary, text: String) -> float:
	var line := float(entry.get("line_height", DEFAULT_LINE))
	var width: float = LabelFont.shape(text)["size"].x * metres_per_em(line)
	var room := float(entry.get("width", 0.0))
	return line * room / width if room > 0.0 and width > room else line


## The font size for a line height.
static func metres_per_em(line_height: float) -> float:
	return line_height / LabelFont.LINE_STEP
