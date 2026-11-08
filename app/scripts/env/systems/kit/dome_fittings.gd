extends RefCounted

## A dome hall's fittings (dome_hall.gd: portholes, rivets, gauges, console, hatch; docs/environments.md "dome_hall"),
## a diving bell's inside made from code: no file, no lettering, no maker's shape.
##   Portholes  round ports in the drum, a brass rim with eight bolts, the water's glass in each (the water's shader,
##              so a port shows the water as the dome does); none in front, where the screen is
##   Rivets     a rivet's round head every half metre along each rib and round the drum's ledge (unbaked: too small
##              and too many to be lightmap charts)
##   Gauges     pressure gauges on the drum: a brass bezel, a backlit face (ticks round three quarters, a red arc at the
##              end), a needle that rests at its own reading and swings with `gauge` (bind it to film.bass)
##   Console    an instrument desk against the drum behind the seats: a sloped panel with a round sonar scope in the
##              middle (env_sonar.gdshader: a slow sweep and its echoes), two gauges either side, rows of toggles,
##              small steady indicator lamps
##   Hatch      a round hatch in the floor behind the last row: a brass ring, a steel lid, a wheel with four spokes
## Angles: theta 0 points from the hall's centre towards the screen (-Z), 90 degrees to the viewer's right (+X).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")

## Ports and gauges keep out of this sector in front (degrees either side of the screen's direction).
const FRONT_CLEAR := 50.0
## The console's place: straight behind the seats.
const CONSOLE_THETA := 180.0
const CONSOLE_WIDTH := 2.6


static func centre(p: Dictionary) -> Vector3:
	return Vector3(0.0, float(p["floor_y"]), float(p["centre_z"]))


## A point on the drum's inner face at theta (degrees), y over the floor, `inset` metres in from it.
static func on_drum(p: Dictionary, theta: float, y: float, inset := 0.0) -> Vector3:
	var a := deg_to_rad(theta)
	var r := float(p["radius"]) - inset
	return centre(p) + Vector3(sin(a) * r, y, -cos(a) * r)


## Facing into the hall at theta: the basis whose +Z points in (towards the centre) and +Y up.
static func facing_in(theta: float) -> Basis:
	var a := deg_to_rad(theta)
	var into := -Vector3(sin(a), 0.0, -cos(a))
	return Basis(Vector3.UP.cross(into).normalized(), Vector3.UP, into)


## The angles (degrees) for n things round the drum, spread evenly between the lamps, clear of the front.
static func round_drum(n: int, offset := 0.5) -> Array[float]:
	var out: Array[float] = []
	if n <= 0:
		return out
	var span := 360.0 - FRONT_CLEAR * 2.0
	for i in n:
		out.append(FRONT_CLEAR + span * (float(i) + offset) / float(n))
	return out


# --- Portholes -------------------------------------------------------------------------------------------------------

## Port centres: [position on the drum's face, theta]. Not where the console stands.
static func portholes(p: Dictionary) -> Array:
	var out: Array = []
	var y := float(p["drum_height"]) * 0.6
	for t: float in round_drum(int(p["portholes"])):
		if bool(p["console"]) and absf(t - CONSOLE_THETA) < 14.0:
			continue
		out.append([on_drum(p, t, y), t])
	return out


const PORT_R := 0.24


## The ports' rims and bolts (brass) into b.
static func porthole_rims(b: RoomMesh, p: Dictionary) -> void:
	for port: Array in portholes(p):
		var at: Vector3 = port[0]
		var basis := facing_in(float(port[1]))
		var ring := basis * Basis(Vector3.RIGHT, PI * 0.5)
		# A flat ring proud of the drum, its inner lip turning into the port.
		Shapes.lathe(b, [Vector2(PORT_R, -0.06), Vector2(PORT_R, 0.04), Vector2(PORT_R + 0.08, 0.05),
				Vector2(PORT_R + 0.1, 0.0)], at, 16, ring)
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			var bolt := at + basis * Vector3(cos(a) * (PORT_R + 0.055), sin(a) * (PORT_R + 0.055), 0.055)
			b.box(bolt, Vector3(0.025, 0.025, 0.02), basis)


## The ports' glass: one disc each, a little back from the rim (the water's shader draws it).
static func porthole_glass(p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for port: Array in portholes(p):
		var at: Vector3 = port[0]
		var basis := facing_in(float(port[1]))
		var c := at - basis.z * 0.03
		for k in 16:
			var a0 := TAU * k / 16.0
			var a1 := TAU * (k + 1) / 16.0
			for q: Vector3 in [c, c + basis * Vector3(cos(a1), sin(a1), 0.0) * PORT_R,
					c + basis * Vector3(cos(a0), sin(a0), 0.0) * PORT_R]:
				st.set_normal(basis.z)
				st.add_vertex(q)
	return st.commit()


# --- Rivets ----------------------------------------------------------------------------------------------------------

## A rivet's low round head (six sides) at `at`, facing `n`.
static func rivet(b: RoomMesh, at: Vector3, n: Vector3, r := 0.022) -> void:
	var side := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(n).normalized()
	var top := at + n * r * 0.6
	var ring: Array[Vector3] = []
	for k in 6:
		var a := TAU * k / 6.0
		ring.append(at + (side * cos(a) + up * sin(a)) * r)
	for k in 6:
		var a := ring[k]
		var c := ring[(k + 1) % 6]
		var fn := (c - a).cross(top - a).normalized()
		if fn.dot(n) < 0.0:
			fn = -fn
		b.face([a, c, top], fn)


## Rivets along a glass dome's ribs (every `pitch` metres, on the face towards the hall) and round the drum's ledge.
static func rivets(b: RoomMesh, p: Dictionary, pitch := 0.5) -> void:
	var c := centre(p)
	var r := float(p["radius"])
	var drum_h := float(p["drum_height"])
	var dome_h := float(p["dome_height"])
	var base := c + Vector3(0, drum_h, 0)
	var n := int(p["ribs"])
	for k in n:
		var a := TAU * (k + float(p["rib_phase"])) / n
		var left := 0.0
		var prev := Vector3.INF
		for i in 97:
			var lat := PI * 0.5 * i / 96.0
			var q := base + Vector3(sin(a) * cos(lat) * (r - 0.05), sin(lat) * dome_h, cos(a) * cos(lat) * (r - 0.05))
			if prev != Vector3.INF:
				left += q.distance_to(prev)
			prev = q
			if left >= pitch and i < 92:
				left = 0.0
				var nn := (base - q).normalized()
				# Two heads side by side across the rib's inner face.
				var across := Vector3(cos(a), 0.0, -sin(a))
				var face_p := q + nn * 0.055
				rivet(b, face_p + across * 0.025, nn, 0.014)
				rivet(b, face_p - across * 0.025, nn, 0.014)
	var ledge_y := drum_h + 0.06
	var count := int(TAU * r / 0.4)
	for i in count:
		var a := TAU * i / count
		var dir := Vector3(sin(a), 0, cos(a))
		rivet(b, c + dir * (r - 0.255) + Vector3(0, ledge_y, 0), -dir, 0.018)


# --- Gauges ----------------------------------------------------------------------------------------------------------

## Gauge places: [centre on the drum's face, theta, the needle's rest (0..1 of its sweep), how far it swings with
## `gauge` (0..1)]. The first two on the console; the rest round the drum.
static func gauges(p: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20
	if bool(p["console"]):
		var panel := console_panel(p)
		for sx: float in [-0.85, 0.85]:
			var q: Vector3 = (panel["origin"] as Vector3) + (panel["basis"] as Basis) * Vector3(sx, 0.0, 0.01)
			out.append([q, panel["basis"], 0.25 + 0.1 * sx, 0.55, 0.13])
	var y := float(p["drum_height"]) * 0.72
	for t: float in round_drum(int(p["gauges"]), 0.0):
		if bool(p["console"]) and absf(t - CONSOLE_THETA) < 14.0:
			continue
		var q := on_drum(p, t, y, 0.04)
		out.append([q, facing_in(t), rng.randf_range(0.15, 0.5), rng.randf_range(0.15, 0.45), 0.11])
	return out


## The gauges' bezels (brass) into b.
static func gauge_bezels(b: RoomMesh, p: Dictionary) -> void:
	for g: Array in gauges(p):
		var basis: Basis = g[1]
		var rr: float = g[4]
		Shapes.lathe(b, [Vector2(rr * 1.12, -0.03), Vector2(rr * 1.18, 0.0), Vector2(rr * 1.12, 0.025),
				Vector2(rr * 1.0, 0.025)], g[0], 16, basis * Basis(Vector3.RIGHT, PI * 0.5))


## The faces as quads for builder._add_picture: [centre, half across, half up, facing].
static func gauge_faces(p: Dictionary) -> Array:
	var out: Array = []
	for g: Array in gauges(p):
		var basis: Basis = g[1]
		var rr: float = g[4]
		out.append([(g[0] as Vector3) + basis.z * 0.012, basis.x * rr, basis.y * rr, basis.z])
	return out


## A gauge's face: cream, ticks round three quarters (from lower left round the top to lower right), the last eighth
## red, the bezel's dark edge outside the circle. 64 x 64, made once.
static var _face: Texture2D


static func gauge_face() -> Texture2D:
	if _face != null:
		return _face
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := 1.0 - (y + 0.5) / n * 2.0
			var r := sqrt(u * u + v * v)
			var col := Color(0.08, 0.06, 0.04)
			if r < 0.95:
				col = Color(0.86, 0.8, 0.66)
				var ang := atan2(u, v)
				var sweep := (ang + PI * 0.75) / (PI * 1.5)
				if sweep >= 0.0 and sweep <= 1.0 and r > 0.62 and r < 0.86:
					var tick := absf(fmod(sweep * 20.0 + 0.5, 1.0) - 0.5)
					var major := absf(fmod(sweep * 4.0 + 0.5, 1.0) - 0.5)
					if tick < 0.09 or (major < 0.03 and r > 0.56):
						col = Color(0.1, 0.08, 0.06)
					elif sweep > 0.85 and r > 0.78:
						col = Color(0.72, 0.12, 0.08)
				if r < 0.07:
					col = Color(0.2, 0.15, 0.08)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_face = ImageTexture.create_from_image(img)
	return _face


## A needle: a thin tapering blade from its hub up its local +Y, a little proud of the face (local +Z).
static func needle_mesh(rr: float, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := rr * 0.06
	var tail := -rr * 0.18
	var tip := rr * 0.82
	for q: Vector3 in [Vector3(-w, 0, 0.02), Vector3(0, tip, 0.02), Vector3(w, 0, 0.02),
			Vector3(-w, 0, 0.02), Vector3(w, 0, 0.02), Vector3(0, tail, 0.02)]:
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(q.x, q.y))
		st.add_vertex(q)
	st.set_material(material)
	return st.commit()


## A needle's transform: at the gauge's centre, turned to its reading (0..1 over three quarters of a turn).
static func needle_xform(g: Array, reading: float) -> Transform3D:
	var basis: Basis = g[1]
	var a := PI * 0.75 - clampf(reading, 0.0, 1.0) * PI * 1.5
	return Transform3D(basis * Basis(Vector3.BACK, a), g[0])


# --- The console -----------------------------------------------------------------------------------------------------

## The console's sloped panel: its middle (origin), basis (x along the desk, y up the slope, z out of the panel).
static func console_panel(p: Dictionary) -> Dictionary:
	var foot := on_drum(p, CONSOLE_THETA, 0.0, 0.05)
	var into := facing_in(CONSOLE_THETA)
	var depth := 0.75
	var front := foot + into.z * depth
	var slope := Basis(into.x, deg_to_rad(-35.0))
	var basis := slope * into
	var mid := front.lerp(foot, 0.45) + Vector3(0, 1.0, 0)
	return {"origin": mid, "basis": basis, "front": front, "foot": foot, "into": into, "depth": depth}


## The desk's body (dark metal) into body, its trim and the hatch-like scope's ring (brass) into brass, its toggles
## into knobs (unbaked). Returns the indicator lamps' places [[centre, half across, half up, facing], colour index].
static func console(body: RoomMesh, brass: RoomMesh, knobs: RoomMesh, p: Dictionary) -> Array:
	var c := console_panel(p)
	var into: Basis = c["into"]
	var foot: Vector3 = c["foot"]
	var depth: float = c["depth"]
	var w := CONSOLE_WIDTH
	# The base: a box from the drum to the front, 0.85 m high, and the sloped panel's box over it.
	body.box(foot + into.z * depth * 0.5 + Vector3(0, 0.42, 0), Vector3(w, 0.84, depth), into)
	var panel: Basis = c["basis"]
	var origin: Vector3 = c["origin"]
	body.box(origin - panel.z * 0.06, Vector3(w, 0.62, 0.12), panel)
	# A back board up the drum, to the ledge.
	body.box(foot + into.z * 0.06 + Vector3(0, 1.08, 0), Vector3(w, 0.44, 0.08), into)
	# Brass trim along the panel's edges and the desk's front.
	for sy: float in [-0.31, 0.31]:
		brass.box(origin + panel * Vector3(0, sy, -0.0), Vector3(w + 0.04, 0.03, 0.14), panel)
	brass.box((c["front"] as Vector3) + Vector3(0, 0.84, 0), Vector3(w + 0.04, 0.04, 0.04), into)
	# The scope's ring in the middle.
	Shapes.lathe(brass, [Vector2(0.27, -0.01), Vector2(0.27, 0.03), Vector2(0.23, 0.035)], origin, 20,
			panel * Basis(Vector3.RIGHT, PI * 0.5))
	# Toggles in two rows either side of the gauges.
	for sx: float in [-1.15, -1.0, -0.6, -0.45, 0.45, 0.6, 1.0, 1.15]:
		for sy: float in [-0.18, 0.16]:
			var at := origin + panel * Vector3(sx, sy, 0.0)
			knobs.box(at + panel.z * 0.012, Vector3(0.05, 0.035, 0.025), panel)
			Shapes.cylinder(knobs, at + panel.z * 0.02, 0.008, 0.05, 6,
					panel * Basis(Vector3.RIGHT, PI * 0.5 - 0.35))
	var lamps: Array = []
	var k := 0
	for sx: float in [-1.15, -1.0, -0.6, -0.45, 0.45, 0.6, 1.0, 1.15]:
		var at := origin + panel * Vector3(sx, -0.02, 0.012)
		lamps.append([[at, panel.x * 0.018, panel.y * 0.018, panel.z], k % 3])
		k += 1
	return lamps


## The scope's quad for builder._add_picture-like drawing: [centre, half across, half up, facing].
static func scope_quad(p: Dictionary) -> Array:
	var c := console_panel(p)
	var panel: Basis = c["basis"]
	return [(c["origin"] as Vector3) + panel.z * 0.02, panel.x * 0.24, panel.y * 0.24, panel.z]


## A box round the console for object physics.
static func console_box(p: Dictionary) -> Array:
	var c := console_panel(p)
	var into: Basis = c["into"]
	return [(c["foot"] as Vector3) + into.z * 0.4 + Vector3(0, 0.55, 0), Vector3(CONSOLE_WIDTH, 1.1, 0.8), into]


# --- The hatch -------------------------------------------------------------------------------------------------------

## The hatch's middle on the floor: behind the last row, before the console.
static func hatch_at(p: Dictionary) -> Vector3:
	var c := centre(p)
	var back := c.z + float(p["radius"]) - (1.75 if bool(p["console"]) else 1.2)
	return Vector3(c.x, c.y + 0.0, back)


## The hatch: a brass ring (brass), a steel lid and its wheel (lid).
static func hatch(brass: RoomMesh, lid: RoomMesh, p: Dictionary) -> void:
	var at := hatch_at(p)
	Shapes.lathe(brass, [Vector2(0.62, 0.0), Vector2(0.62, 0.035), Vector2(0.52, 0.04), Vector2(0.52, 0.0)], at, 24)
	Shapes.cylinder(lid, at, 0.52, 0.05, 24)
	# The wheel: a rim on four spokes, on a hub.
	var hub := at + Vector3(0, 0.12, 0)
	Shapes.cylinder(lid, at + Vector3(0, 0.05, 0), 0.06, 0.07, 8)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		Shapes.beam(lid, hub, hub + Vector3(cos(a), 0, sin(a)) * 0.3, Vector2(0.03, 0.025))
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		Shapes.beam(lid, hub + Vector3(cos(a0), 0, sin(a0)) * 0.3, hub + Vector3(cos(a1), 0, sin(a1)) * 0.3,
				Vector2(0.035, 0.03))
