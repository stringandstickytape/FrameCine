extends RefCounted

## Where each channel of a film's audio comes from (spatial audio, ideas #21 / #47, docs/features.md #21), as pure
## functions: tests/test_spatial_audio.gd checks them for every layout.
##
## Channel names are FFmpeg's (MediaSource.get_audio_channels()). Directions follow ITU-R BS.775 and BS.2051:
##   FC 0, FL / FR -30 / 30, FLC / FRC -15 / 15, WL / WR -60 / 60
##   the one surround pair of a 5.x layout (SL / SR or BL / BR) -110 / 110; with both pairs (7.x) the sides at
##   -90 / 90 and the backs at -135 / 135; BC 180; SDL / SDR -90 / 90
##   heights at 40 degrees up: TFL / TFR -45 / 45, TFC 0, TSL / TSR -90 / 90, TBL / TBR -135 / 135, TBC 180, TC
##   straight up; bottoms 30 down: BFL / BFR -45 / 45, BFC 0
##   LFE, LFE2: no direction (both ears)
##   anything else (an unnamed CHn): spread round the listener in order
## Angles: azimuth in degrees from the front, positive to the right; elevation positive up.
##
##   direction(name, present) -> {azimuth, elevation} or {} for LFE
##   vector(azimuth, elevation) -> Vector3     (Godot axes: -Z front, +X right, +Y up)
##   is_lfe(name), is_screen(name), is_height(name)
##   place(names, room, seat, screen) -> [{name, index, kind, position, gain}]   positions in the room's frame (see
##       VREnvironment.get_sound_room()), for a flat screen; ring(names, front) for 180 / 360 (directions only)

const SCREEN := ["FL", "FR", "FC", "FLC", "FRC"]
const LFE := ["LFE", "LFE2", "LFE3"]
const HEIGHT_ELEVATION := 40.0
const BOTTOM_ELEVATION := -30.0
## The front pair is at least this far off centre (degrees), however small or far the screen.
const MIN_FRONT_ANGLE := 22.0
const MAX_FRONT_ANGLE := 35.0
## Screen speakers stand this far behind the picture.
const BEHIND_SCREEN := 0.3
## Wall speakers stand this far in from the room's box.
const INSET := 0.4
## Without walls the speakers stand this far from the seat.
const RING := 2.5

const FIXED := {
	"FC": [0.0, 0.0], "FL": [-30.0, 0.0], "FR": [30.0, 0.0], "FLC": [-15.0, 0.0], "FRC": [15.0, 0.0],
	"WL": [-60.0, 0.0], "WR": [60.0, 0.0], "BC": [180.0, 0.0], "SDL": [-90.0, 0.0], "SDR": [90.0, 0.0],
	"TFL": [-45.0, HEIGHT_ELEVATION], "TFR": [45.0, HEIGHT_ELEVATION], "TFC": [0.0, HEIGHT_ELEVATION],
	"TSL": [-90.0, HEIGHT_ELEVATION], "TSR": [90.0, HEIGHT_ELEVATION], "TBL": [-135.0, HEIGHT_ELEVATION],
	"TBR": [135.0, HEIGHT_ELEVATION], "TBC": [180.0, HEIGHT_ELEVATION], "TC": [0.0, 90.0],
	"BFL": [-45.0, BOTTOM_ELEVATION], "BFR": [45.0, BOTTOM_ELEVATION], "BFC": [0.0, BOTTOM_ELEVATION],
}


static func is_lfe(name: String) -> bool:
	return name in LFE


static func is_screen(name: String) -> bool:
	return name in SCREEN


static func is_height(name: String) -> bool:
	return name.begins_with("T") and FIXED.has(name)


## {azimuth, elevation} of a channel, given every channel present; {} for the LFE.
static func direction(name: String, present: Array) -> Dictionary:
	if is_lfe(name):
		return {}
	if FIXED.has(name):
		return {"azimuth": FIXED[name][0], "elevation": FIXED[name][1]}
	var both := ("SL" in present or "SR" in present) and ("BL" in present or "BR" in present)
	var side := -1.0 if name.ends_with("L") else 1.0
	match name:
		"SL", "SR":
			return {"azimuth": side * (90.0 if both else 110.0), "elevation": 0.0}
		"BL", "BR":
			return {"azimuth": side * (135.0 if both else 110.0), "elevation": 0.0}
	# Unknown: spread round in order, from the front left.
	var unknown: Array = []
	for n: String in present:
		if not is_lfe(n) and not FIXED.has(n) and not n in ["SL", "SR", "BL", "BR"]:
			unknown.append(n)
	var i := unknown.find(name)
	var count := maxi(unknown.size(), 1)
	if count == 1:
		return {"azimuth": 0.0, "elevation": 0.0}
	if count == 2:
		return {"azimuth": -30.0 if i == 0 else 30.0, "elevation": 0.0}
	return {"azimuth": wrapf(-30.0 + 360.0 * i / count, -180.0, 180.0), "elevation": 0.0}


static func vector(azimuth: float, elevation: float) -> Vector3:
	var a := deg_to_rad(azimuth)
	var e := deg_to_rad(elevation)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))


## 180 / 360 (and any time without a room): each channel a direction round the listener, the front turned to `front`
## (a horizontal direction). [{name, index, kind, position (a direction), gain, at_infinity}].
static func ring(names: Array, front: Vector3, lfe := false) -> Array:
	var out: Array = []
	var yaw := atan2(front.x, -front.z)
	for i in names.size():
		var n: String = names[i]
		if is_lfe(n):
			if lfe:
				out.append({"name": n, "index": i, "kind": "lfe", "position": Vector3.ZERO, "gain": 1.0})
			continue
		var d := direction(n, names)
		var v := vector(d.azimuth, d.elevation).rotated(Vector3.UP, -yaw)
		out.append({"name": n, "index": i, "kind": "point", "position": v, "gain": 1.0, "at_infinity": true})
	return out


## A flat screen in a room. room: VREnvironment.get_sound_room() (its frame: the seat at the origin, facing -Z, the
## floor at y 0). seat: the seated eye point in that frame. screen: {center, right (unit), width} in that frame.
## Screen channels go behind the picture (the front pair kept between MIN_FRONT_ANGLE and MAX_FRONT_ANGLE off centre);
## a room's own "speakers" (name -> position) win; the rest where their direction from the seat meets the room's box
## (wall speakers at "surround_height"), or RING metres away without a box. A room's "array" (n > 1) spreads each
## side and back surround over n speakers along its wall, each at 1 / sqrt(n).
static func place(names: Array, room: Dictionary, seat: Vector3, screen: Dictionary, lfe := false) -> Array:
	var out: Array = []
	var fixed: Dictionary = room.get("speakers", {})
	var box: Variant = room.get("box")
	var array_n := int(room.get("array", 1))
	var distance := float(room.get("distance", RING))
	var center: Vector3 = screen.get("center", seat + Vector3(0, 0, -3))
	var right: Vector3 = screen.get("right", Vector3.RIGHT)
	var width := float(screen.get("width", 2.0))
	var toward: Vector3 = right.cross(Vector3.UP).normalized() # From the screen towards the viewer.
	var to_screen := (center - seat)
	to_screen.y = 0.0
	var screen_distance := maxf(to_screen.length(), 0.5)
	for i in names.size():
		var n: String = names[i]
		if is_lfe(n):
			if lfe:
				out.append({"name": n, "index": i, "kind": "lfe", "position": Vector3.ZERO, "gain": 1.0})
			continue
		if fixed.has(n):
			out.append({"name": n, "index": i, "kind": "point", "position": fixed[n], "gain": 1.0})
			continue
		var d := direction(n, names)
		if is_screen(n):
			var x := 0.0
			match n:
				"FL", "FR":
					var half := clampf(width * 0.5, screen_distance * tan(deg_to_rad(MIN_FRONT_ANGLE)),
							screen_distance * tan(deg_to_rad(MAX_FRONT_ANGLE)))
					x = -half if n == "FL" else half
				"FLC", "FRC":
					x = (-0.25 if n == "FLC" else 0.25) * width
			out.append({"name": n, "index": i, "kind": "point", "position": center + right * x - toward * BEHIND_SCREEN,
					"gain": 1.0})
			continue
		var dir := vector(d.azimuth, d.elevation)
		var pos: Vector3
		if box is AABB and not bool(room.get("ring", false)):
			pos = _hit(seat, dir, (box as AABB).grow(-INSET))
			if float(d.elevation) == 0.0 and room.has("surround_height"):
				pos.y = float(room["surround_height"])
		else:
			pos = seat + dir * distance
		var spread := array_n > 1 and box is AABB and not bool(room.get("ring", false)) and n in ["SL", "SR", "BL", "BR"]
		if not spread:
			out.append({"name": n, "index": i, "kind": "point", "position": pos, "gain": 1.0})
			continue
		# An array along the wall it is on: side walls run front to back, the back wall left to right.
		var along := Vector3.BACK if absf(pos.x - seat.x) > absf(pos.z - seat.z) else Vector3.RIGHT
		var spacing := float(room.get("array_spacing", 2.5))
		for k in array_n:
			var offset := (k - (array_n - 1) * 0.5) * spacing
			var p := pos + along * offset
			if box is AABB:
				var inner := (box as AABB).grow(-INSET)
				p = p.clamp(inner.position, inner.end)
			out.append({"name": n, "index": i, "kind": "point", "position": p, "gain": 1.0 / sqrt(array_n)})
	return out


## Where a ray from `from` (inside `box`) along `dir` leaves the box.
static func _hit(from: Vector3, dir: Vector3, box: AABB) -> Vector3:
	var t := INF
	for axis in 3:
		var d := dir[axis]
		if absf(d) < 1e-6:
			continue
		var wall: float = box.end[axis] if d > 0.0 else box.position[axis]
		var k := (wall - from[axis]) / d
		if k > 0.0:
			t = minf(t, k)
	if t == INF:
		t = RING
	return from + dir * t
