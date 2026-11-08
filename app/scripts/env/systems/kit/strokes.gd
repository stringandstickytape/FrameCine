extends RefCounted

## A stroke font of our own (since 2026-11-08, the drive-in): each glyph a few polylines in a box 4 wide and 6 high
## (y up from the baseline), the way a sign maker bends neon tube or a dial painter draws numerals. No borrowed face.
## Drawn as lines into a picture (a dial's numerals, a marquee's letters) or as tubes (neon, drive_in_lot.gd).
## Static; preload to use.
##
##   lines(text, height, spacing) -> Array[PackedVector2Array]   the text's strokes, metres, left at x 0
##   width(text, height, spacing) -> float
##   draw(img, text, at, height, colour, thickness, centred)    into an Image (pixels; y down), antialiased
##   line(img, a, b, colour, thickness)                          one antialiased line (pixels)

const GLYPHS := {
	"A": [[0, 0, 0, 4, 2, 6, 4, 4, 4, 0], [0, 2.7, 4, 2.7]],
	"B": [[0, 3, 3, 3, 4, 4, 4, 5, 3, 6, 0, 6, 0, 0, 3, 0, 4, 1, 4, 2, 3, 3]],
	"C": [[4, 5, 3, 6, 1, 6, 0, 5, 0, 1, 1, 0, 3, 0, 4, 1]],
	"D": [[0, 0, 0, 6, 2, 6, 4, 4.3, 4, 1.7, 2, 0, 0, 0]],
	"E": [[4, 6, 0, 6, 0, 0, 4, 0], [0, 3, 3, 3]],
	"F": [[4, 6, 0, 6, 0, 0], [0, 3, 3, 3]],
	"G": [[4, 5, 3, 6, 1, 6, 0, 5, 0, 1, 1, 0, 3, 0, 4, 1, 4, 2.7, 2.2, 2.7]],
	"H": [[0, 0, 0, 6], [4, 0, 4, 6], [0, 3, 4, 3]],
	"I": [[1, 6, 3, 6], [2, 6, 2, 0], [1, 0, 3, 0]],
	"J": [[1.5, 6, 4, 6], [3.2, 6, 3.2, 1, 2.2, 0, 1, 0, 0, 1]],
	"K": [[0, 0, 0, 6], [4, 6, 0, 2], [1.3, 3.3, 4, 0]],
	"L": [[0, 6, 0, 0, 4, 0]],
	"M": [[0, 0, 0, 6, 2, 3, 4, 6, 4, 0]],
	"N": [[0, 0, 0, 6, 4, 0, 4, 6]],
	"O": [[1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5, 4, 1, 3, 0, 1, 0]],
	"P": [[0, 0, 0, 6, 3, 6, 4, 5, 4, 4, 3, 3, 0, 3]],
	"Q": [[1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5, 4, 1, 3, 0, 1, 0], [2.4, 1.6, 4.2, -0.4]],
	"R": [[0, 0, 0, 6, 3, 6, 4, 5, 4, 4, 3, 3, 0, 3], [2, 3, 4, 0]],
	"S": [[4, 5, 3, 6, 1, 6, 0, 5, 0, 4, 1, 3, 3, 3, 4, 2, 4, 1, 3, 0, 1, 0, 0, 1]],
	"T": [[0, 6, 4, 6], [2, 6, 2, 0]],
	"U": [[0, 6, 0, 1, 1, 0, 3, 0, 4, 1, 4, 6]],
	"V": [[0, 6, 2, 0, 4, 6]],
	"W": [[0, 6, 1, 0, 2, 4, 3, 0, 4, 6]],
	"X": [[0, 0, 4, 6], [0, 6, 4, 0]],
	"Y": [[0, 6, 2, 3, 4, 6], [2, 3, 2, 0]],
	"Z": [[0, 6, 4, 6, 0, 0, 4, 0]],
	"0": [[1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5, 4, 1, 3, 0, 1, 0]],
	"1": [[1, 5, 2, 6, 2, 0], [1, 0, 3, 0]],
	"2": [[0, 5, 1, 6, 3, 6, 4, 5, 4, 4, 0, 0, 4, 0]],
	"3": [[0, 5, 1, 6, 3, 6, 4, 5, 4, 4, 3, 3, 4, 2, 4, 1, 3, 0, 1, 0, 0, 1], [1.5, 3, 3, 3]],
	"4": [[3, 0, 3, 6, 0, 2, 4, 2]],
	"5": [[4, 6, 0, 6, 0, 3.3, 3, 3.3, 4, 2.3, 4, 1, 3, 0, 0, 0]],
	"6": [[4, 5, 3, 6, 1, 6, 0, 5, 0, 1, 1, 0, 3, 0, 4, 1, 4, 2, 3, 3, 0, 3]],
	"7": [[0, 6, 4, 6, 1.2, 0]],
	"8": [[1, 3, 0, 4, 0, 5, 1, 6, 3, 6, 4, 5, 4, 4, 3, 3, 1, 3, 0, 2, 0, 1, 1, 0, 3, 0, 4, 1, 4, 2, 3, 3]],
	"9": [[4, 3, 1, 3, 0, 4, 0, 5, 1, 6, 3, 6, 4, 5, 4, 1, 3, 0, 1, 0]],
	"-": [[1, 3, 3, 3]],
	".": [[1.8, 0, 2.2, 0, 2.2, 0.4, 1.8, 0.4, 1.8, 0]],
	"'": [[2, 6, 2, 4.8]],
	"*": [[2, 1, 2, 5], [0.3, 2, 3.7, 4], [0.3, 4, 3.7, 2]],
	" ": [],
	# Greek capitals that have no Latin twin (since 2026-11-08: the Athens rooftop's painted signs); the others are
	# drawn as their Latin twins (ALIASES).
	"Γ": [[0, 0, 0, 6, 4, 6]],
	"Δ": [[0, 0, 2, 6, 4, 0, 0, 0]],
	"Θ": [[1, 0, 0, 1, 0, 5, 1, 6, 3, 6, 4, 5, 4, 1, 3, 0, 1, 0], [1.2, 3, 2.8, 3]],
	"Λ": [[0, 0, 2, 6, 4, 0]],
	"Ξ": [[0, 6, 4, 6], [0.8, 3, 3.2, 3], [0, 0, 4, 0]],
	"Π": [[0, 0, 0, 6, 4, 6, 4, 0]],
	"Σ": [[4, 6, 0, 6, 2, 3, 0, 0, 4, 0]],
	"Φ": [[2, 0, 2, 6], [1, 1.2, 0, 2, 0, 4, 1, 4.8, 3, 4.8, 4, 4, 4, 2, 3, 1.2, 1, 1.2]],
	"Ψ": [[2, 0, 2, 6], [0, 6, 0, 3.5, 1, 2.5, 3, 2.5, 4, 3.5, 4, 6]],
	"Ω": [[0, 0, 1.2, 0, 0.2, 1.6, 0, 3, 0.4, 4.6, 1.4, 5.7, 2.6, 5.7, 3.6, 4.6, 4, 3, 3.8, 1.6, 2.8, 0, 4, 0]],
}
## Greek capitals drawn as the Latin letter of the same shape.
const ALIASES := {"Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N",
		"Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X"}
## A glyph's advance, in the glyph box's units (4 wide).
const ADVANCE := 5.6


static func _advance(ch: String) -> float:
	ch = ALIASES.get(ch, ch)
	return 4.4 if ch == "I" or ch == "1" else (3.0 if ch == "." or ch == "'" else ADVANCE)


## The text's strokes in metres, its baseline at y 0, starting at x 0; height: the capitals' height. spacing: times
## the advance.
static func lines(text: String, height: float, spacing := 1.0) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var k := height / 6.0
	var x := 0.0
	for ch in text.to_upper():
		var g: Array = GLYPHS.get(ALIASES.get(ch, ch), [])
		var shift := (ADVANCE - _advance(ch)) * 0.5
		for poly: Array in g:
			var line := PackedVector2Array()
			for i in range(0, poly.size(), 2):
				line.append(Vector2((float(poly[i]) - shift) * k + x, float(poly[i + 1]) * k))
			out.append(line)
		x += _advance(ch) * k * spacing
	return out


static func width(text: String, height: float, spacing := 1.0) -> float:
	var k := height / 6.0
	var w := 0.0
	for ch in text.to_upper():
		w += _advance(ch) * k * spacing
	return maxf(w - (ADVANCE - 4.0) * k * spacing, 0.0)


## The text drawn into an image: at its baseline's left (or its middle with centred), height in pixels.
static func draw(img: Image, text: String, at: Vector2, height: float, colour: Color, thickness: float,
		centred := false, spacing := 1.0) -> void:
	var x0 := at.x - (width(text, height, spacing) * 0.5 if centred else 0.0)
	for poly: PackedVector2Array in lines(text, height, spacing):
		for i in poly.size() - 1:
			var a := Vector2(x0 + poly[i].x, at.y - poly[i].y)
			var b := Vector2(x0 + poly[i + 1].x, at.y - poly[i + 1].y)
			line(img, a, b, colour, thickness)


## One antialiased line of this thickness (pixels), blended over what is there by its coverage.
static func line(img: Image, a: Vector2, b: Vector2, colour: Color, thickness: float) -> void:
	var r := thickness * 0.5
	var x0 := maxi(int(floor(minf(a.x, b.x) - r - 1.0)), 0)
	var x1 := mini(int(ceil(maxf(a.x, b.x) + r + 1.0)), img.get_width() - 1)
	var y0 := maxi(int(floor(minf(a.y, b.y) - r - 1.0)), 0)
	var y1 := mini(int(ceil(maxf(a.y, b.y) + r + 1.0)), img.get_height() - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var cover := clampf(r + 0.5 - d, 0.0, 1.0)
			if cover > 0.0:
				var was := img.get_pixel(x, y)
				img.set_pixel(x, y, was.lerp(Color(colour.r, colour.g, colour.b, maxf(was.a, colour.a)),
						cover * colour.a))
