extends RefCounted

## Giant's study (app/environments/giants_study.env.json; docs/environments/rooms/giants_study.md):
## an Other Worlds room built by Gemini 4 Neon Extra High. A cozy rainy late-night Victorian study at 10:1 miniature
## scale where you sit ten centimetres tall on stitched felt cushions resting on a giant woven cork-and-felt coaster
## atop a gleaming mahogany desk. Everything is drawn from boxes, lathes, arches and strips; zero people, zero real
## marks, 100% procedural/CC0.
##
## Pieces (dispatched from kit/pieces.gd):
##   study_desk   the colossal mahogany desktop and chamfered apron, green gold-tooled leather desk blotter with
##                stitched leather corner guards, giant woven cork-and-felt coaster nook under the seats, brushed-brass
##                & walnut pocket display / miniature travel theatre propped on a giant folded leather notebook & brass
##                architect's ruler cradle, towering 5.8 m leaning stack of leather-bound hardcover books, colossal
##                glazed cream-and-cobalt ceramic teacup & saucer with dark steaming tea, 2.3 m gleaming brass pocket
##                watch with live working dial (`PieceClock`) & coiled brass chain, giant lacquered fountain pen with
##                gleaming gold nib, soaring 7.8 m articulated brass & green-glass banker's desk lamp (`PieceCove` +
##                `PieceLamps` + soft downward volumetric cone on `env_world_shaft.gdshader`), faceted glass & brass
##                inkwell (`PieceGlass`), tall glazed ceramic pot bristling with giant coloured cedar pencils, folded
##                brass wire-rimmed spectacles, brass-handled magnifying glass, and giant brass paperclip.
##   study_room   the cavernous shadowy timber-panelled Victorian study beyond the desk edge (x = +/-16 m,
##                z = -15.5..+14.5 m, floor y = -7.8 m, coffered timber ceiling y = +10.2 m): mahogany desk pedestals
##                with brass drawer pulls, empty buttoned mahogany desk chair back far aft, towering floor-to-ceiling
##                bookshelves packed with giant distant book blocks, carved chimneypiece & glowing cozy fireplace
##                hearth across the back-right study wall (`PieceWindows` + flickering hearth embers), and a colossal
##                mullioned leaded-glass study window on the left wall framed by heavy burgundy velvet curtains looking
##                out onto a misty moonlit rainy autumn night.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const SHAFT_SHADER := preload("res://shaders/env_world_shaft.gdshader")

const PIECES: Array[String] = ["study_desk", "study_room"]

## Key desk & blotter elevations (cushions sit on the coaster at y = 0.0).
const DESK_TOP := -0.025
const DESK_THICK := 1.10
const BLOTTER_TOP := -0.012
const COASTER_TOP := -0.001

## Desk footprint (metres, 10:1 scale: 2.4 m x 1.6 m desk -> 24 m x 16 m).
const DESK_X0 := -12.0
const DESK_X1 := 12.0
const DESK_Z0 := -8.5
const DESK_Z1 := 7.5

## Green leather desk blotter footprint.
const BLOT_X0 := -5.5
const BLOT_X1 := 5.5
const BLOT_Z0 := -6.2
const BLOT_Z1 := 3.5

## Cavernous Victorian study room extents.
const ROOM_X0 := -16.0
const ROOM_X1 := 16.0
const ROOM_Z0 := -15.5
const ROOM_Z1 := 14.5
const FLOOR_Y := -6.2
const CEIL_Y := 10.2

## Colossal leaded-glass window opening on the left wall (x = -16.0), split by a central pier into two bays matching
## weather.panes (each 5.75 m x 9.40 m, <= 10 m).
const WIN_Z0 := -8.70
const WIN_Z1 := 3.70
const WIN_PIER_Z := -2.50
const WIN_PIER_W := 0.55
const WIN_Y0 := -1.10
const WIN_Y1 := 8.30

## Banker's lamp shade centre & downward volumetric cone target.
const SHADE_AT := Vector3(4.65, 6.25, -2.15)
const CONE_FOOT := Vector3(3.45, 0.04, -1.65)

## Palette (sRGB; converted to linear on vertex colours).
const MAHOGANY := Color(0.30, 0.13, 0.075)
const MAHOGANY_DARK := Color(0.17, 0.075, 0.045)
const MAHOGANY_WARM := Color(0.40, 0.19, 0.105)
const WALNUT := Color(0.26, 0.15, 0.09)
const OAK_FLOOR := Color(0.16, 0.10, 0.065)
const PLASTER_STUDY := Color(0.11, 0.15, 0.125)
const CEIL_PLASTER := Color(0.16, 0.14, 0.12)
const LEATHER_DARK := Color(0.19, 0.095, 0.055)
const LEATHER_SADDLE := Color(0.36, 0.18, 0.09)
const CORK := Color(0.56, 0.40, 0.25)
const COASTER_FELT := Color(0.32, 0.11, 0.12)
const COASTER_STITCH := Color(0.84, 0.76, 0.62)
const CREAM_PAGE := Color(0.88, 0.82, 0.70)
const CREAM_PORCELAIN := Color(0.93, 0.90, 0.83)
const COBALT_GLAZE := Color(0.12, 0.26, 0.60)
const TEA_DARK := Color(0.12, 0.048, 0.018)
const BRASS := Color(0.86, 0.68, 0.34)
const BRASS_WARM := Color(0.92, 0.74, 0.38)
const BRASS_DARK := Color(0.54, 0.40, 0.18)
const IRON_DARK := Color(0.08, 0.08, 0.085)
const INK_INDIGO := Color(0.045, 0.065, 0.14)
const PEN_LACQUER := Color(0.14, 0.035, 0.045)
const CURTAIN_BURGUNDY := Color(0.28, 0.065, 0.08)
const BRICK_HEARTH := Color(0.30, 0.15, 0.11)
const STONE_MANTEL := Color(0.20, 0.19, 0.18)
const LAMP_WARM := Color(1.0, 0.84, 0.56)
const FIRE_EMBER := Color(1.0, 0.50, 0.16)
const FIRE_CORE := Color(1.0, 0.76, 0.32)
const POT_CREAM := Color(0.80, 0.74, 0.63)
const POT_SAGE := Color(0.26, 0.38, 0.32)
const CEDAR_RAW := Color(0.76, 0.58, 0.38)
const ERASER_PINK := Color(0.82, 0.48, 0.50)

## Rich Victorian leather book colours.
const BOOK_CRIMSON := Color(0.46, 0.095, 0.11)
const BOOK_GREEN := Color(0.11, 0.28, 0.17)
const BOOK_NAVY := Color(0.10, 0.17, 0.32)
const BOOK_TAN := Color(0.50, 0.31, 0.15)
const BOOK_PLUM := Color(0.30, 0.11, 0.22)
const BOOK_OCHRE := Color(0.58, 0.41, 0.16)
const RIBBON_GOLD := Color(0.80, 0.62, 0.24)
const RIBBON_CRIMSON := Color(0.58, 0.10, 0.12)


## Custom Hall for Giant's study: builds the exact 0..1 UV green gold-tooled leather desk blotter (baked static) and
## the soft downward volumetric banker's lamp cone (`env_world_shaft.gdshader`, in group `env_see_through`), updating
## the lamp cone colour and intensity live with `desk_lamp` and house dimming.
class Hall:
	var kit: Node
	var has_desk := false
	var shaft_m: ShaderMaterial
	var shaft_t := 0.0
	var blotter_node: MeshInstance3D
	var cone_node: MeshInstance3D

	func finish(k: Node) -> void:
		if not has_desk:
			return
		_build_blotter(k)
		_build_lamp_cone(k)
		# Tune PieceGlass to crisp crystal-clear inkwell & magnifying glass transparency.
		for n: Node in k.owned():
			if n is MeshInstance3D and str(n.name).begins_with("PieceGlass"):
				var gm := (n as MeshInstance3D).material_override as ShaderMaterial
				if gm != null:
					gm.set_shader_parameter("alpha", 0.13)
					gm.set_shader_parameter("rim", 0.44)
		tick(0.0)

	## Baked static mesh for the 11.0 x 9.7 m green gold-tooled leather desk blotter with exact 0..1 UVs & tangents so
	## Procedural.maps("leather_blotter") frames the entire blotter with its double gold-leaf rule and pebble grain.
	func _build_blotter(k: Node) -> void:
		var m: ShaderMaterial = k._light.from_param({"library": "brown_leather", "color": [1.0, 1.0, 1.0]}, false)
		var maps: Dictionary = Procedural.maps("leather_blotter")
		m.set_shader_parameter("albedo_map", maps["albedo"])
		m.set_shader_parameter("normal_map", maps["normal"])
		m.set_shader_parameter("orm_map", maps["orm"])
		m.set_shader_parameter("tint", Color(1.55, 1.62, 1.48))
		m.set_shader_parameter("use_mesh_uv", true)
		m.set_shader_parameter("uv_repeat", Vector2(1.0, 1.0))
		m.set_shader_parameter("normal_strength", 1.15)
		m.set_shader_parameter("specular", 0.58)

		var by := BLOTTER_TOP + 0.002
		var v := PackedVector3Array([
			Vector3(BLOT_X0, by, BLOT_Z0),
			Vector3(BLOT_X1, by, BLOT_Z0),
			Vector3(BLOT_X1, by, BLOT_Z1),
			Vector3(BLOT_X0, by, BLOT_Z1),
		])
		var n := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		var t := PackedFloat32Array([
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
			1.0, 0.0, 0.0, 1.0,
		])
		var uv := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
		var uv2 := PackedVector2Array([Vector2(0.04, 0.04), Vector2(0.96, 0.04), Vector2(0.96, 0.96), Vector2(0.04, 0.96)])
		var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TANGENT] = t
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, m)
		mesh.lightmap_size_hint = Vector2i(128, 128)
		blotter_node = k._add_mesh("LeatherBlotter", mesh)
		blotter_node.gi_mode = GeometryInstance3D.GI_MODE_STATIC

	## Soft warm volumetric downward cone descending from the soaring 7.8 m banker's lamp onto the right desk blotter
	## (`env_world_shaft.gdshader`, in group `env_see_through`, zero live lights, strictly clear of sight lines).
	func _build_lamp_cone(k: Node) -> void:
		var top := SHADE_AT + Vector3(-0.08, -0.35, 0.05)
		var bot := CONE_FOOT
		var axis := (bot - top).normalized()
		var side_x := axis.cross(Vector3.FORWARD).normalized()
		var side_z := side_x.cross(axis).normalized()
		var sides := 24
		var r_top := 0.88
		var r_bot := 2.75
		var v := PackedVector3Array()
		var n := PackedVector3Array()
		var col := PackedColorArray()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		var slope_len := top.distance_to(bot)
		var dr := r_bot - r_top
		for j in 2:
			var fy := float(j)
			var ctr := top.lerp(bot, fy)
			var rad := lerpf(r_top, r_bot, fy)
			var alpha := 0.92 if j == 0 else 0.34
			for i in sides + 1:
				var a := TAU * float(i) / float(sides)
				var radial := side_x * cos(a) + side_z * sin(a)
				var p := ctr + radial * rad
				var nrm := (radial * slope_len - axis * dr).normalized()
				v.append(p)
				n.append(nrm)
				col.append(Color(1.0, 0.97, 0.90, alpha))
				uv.append(Vector2(float(i) / float(sides), fy))
		var row := sides + 1
		for i in sides:
			var a := i
			var b := i + 1
			var cc := row + i + 1
			var d := row + i
			idx.append_array([a, cc, b, a, d, cc])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		shaft_m = ShaderMaterial.new()
		shaft_m.shader = SHAFT_SHADER
		shaft_m.set_shader_parameter("noise_map", SkySys.noise_texture())
		shaft_m.set_shader_parameter("shaft_colour", Color(1.0, 0.82, 0.48))
		shaft_m.set_shader_parameter("shaft_level", 0.16)
		shaft_m.set_shader_parameter("edge_softness", 2.45)
		shaft_m.set_shader_parameter("wisp_strength", 0.32)
		mesh.surface_set_material(0, shaft_m)
		cone_node = k._add_mesh("LampCone", mesh)
		cone_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		cone_node.add_to_group("env_see_through")

	func tick(delta: float) -> void:
		if shaft_m == null or kit == null:
			return
		var motion := float(kit.params.get("water_motion", 1.0))
		shaft_t += delta * motion
		shaft_m.set_shader_parameter("clock", shaft_t)
		var cove_col: Color = kit.cove_colour_now()
		# Blend a touch of warm bulb light into the downward air cone so Green banker's glow still feels cozy & luminous.
		var cone_col := cove_col.lerp(Color(1.0, 0.86, 0.56), 0.30)
		var cove_val := clampf(float(kit.params.get("cove", 1.0)), 0.0, 2.0)
		var house := float(kit._group_level("house"))
		var fl := clampf(float(kit.params.get("cove_floor", 0.45)), 0.0, 1.0)
		var level := 0.14 * clampf(cove_val / 1.20, 0.0, 1.25) * maxf(house, fl * 0.55)
		shaft_m.set_shader_parameter("shaft_colour", cone_col)
		shaft_m.set_shader_parameter("shaft_level", level)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	# Coarser lightmap texel keeps the colossal 32 m x 30 m x 18 m study's static atlas crisp and well under 2048 px.
	c.s.texel = maxf(float(c.s.texel), 0.26)
	var h := _hall(c)
	match piece:
		"study_desk":
			h.has_desk = true
			_study_desk(c)
		"study_room":
			_study_room(c)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove, c.glass]:
		b.colour = Color.WHITE


static func _hall(c: Object) -> Hall:
	for obj: Object in c.halls:
		if obj is Hall:
			return obj
	var h := Hall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


# --- Shared helpers ---------------------------------------------------------------------------------------------------

static func _lin(col: Color, alpha := 1.0) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _brass(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.72, 0.22)


static func _ceramic(c: Object) -> Material:
	return c.shiny("china", 0.0, 0.38, 0.14)


static func _lacquer(c: Object) -> Material:
	return c.shiny("iron", 0.0, 0.48, 0.10)


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


## Smooth swept elliptical tube along a 3D polyline (`pts`, >= 2 points) with radii `rx` (side) and `ry` (in-plane),
## zero gaps or miter kinks (teacup handle, coiled brass watch chain).
static func _tube(b: RoomMesh, pts: Array[Vector3], rx: float, ry: float, sides := 10, side_hint := Vector3.UP) -> void:
	if pts.size() < 2:
		return
	var rings: Array = []
	var nrings: Array = []
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var s1 := side_hint.cross(t)
		if s1.length() < 0.01:
			s1 = Vector3.RIGHT.cross(t)
		s1 = s1.normalized()
		var s2 := t.cross(s1).normalized()
		var ring := PackedVector3Array()
		var nring := PackedVector3Array()
		for k in sides + 1:
			var a := TAU * float(k % sides) / float(sides)
			var ca := cos(a)
			var sa := sin(a)
			ring.append(pts[i] + s1 * (ca * rx) + s2 * (sa * ry))
			nring.append((s1 * (ca / maxf(rx, 0.001)) + s2 * (sa / maxf(ry, 0.001))).normalized())
		rings.append(ring)
		nrings.append(nring)
	for i in pts.size() - 1:
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var n0: PackedVector3Array = nrings[i]
		var n1: PackedVector3Array = nrings[i + 1]
		var nmid := PackedVector3Array()
		for k in sides + 1:
			nmid.append((n0[k] + n1[k]).normalized())
		b.strip(r0, r1, nmid)


## Cubic Bezier point at parameter t in 0..1.
static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


# ======================================================================================================================
# Piece 1: study_desk — everything on the giant's mahogany desk at 10:1 miniature scale
# ======================================================================================================================

static func _study_desk(c: Object) -> void:
	_mahogany_desktop(c)
	_blotter_frame_and_corners(c)
	_coaster_nook(c)
	_pocket_display_and_cradle(c)
	_left_books_stack(c)
	_left_pocket_watch(c)
	_left_teacup_and_saucer(c)
	_left_fountain_pen(c)
	_right_bankers_lamp(c)
	_right_inkwell(c)
	_right_pencil_pot(c)
	_right_spectacles(c)
	_right_magnifying_glass(c)
	_right_paperclip(c)
	_desk_lamps(c)


## Vast gleaming polished mahogany desktop (x = -12..+12 m, z = -8.5..+7.5 m) with thick chamfered bullnose apron and
## classical stepped edge mouldings dropping cleanly down toward the cavernous study floor below.
static func _mahogany_desktop(c: Object) -> void:
	var s: RoomMesh = c.s
	var w := DESK_X1 - DESK_X0
	var d := DESK_Z1 - DESK_Z0
	var cx := (DESK_X0 + DESK_X1) * 0.5
	var cz := (DESK_Z0 + DESK_Z1) * 0.5

	s.surface(c.tinted("wood"))
	# Main polished mahogany desktop slab.
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(cx, DESK_TOP - 0.16, cz), Vector3(w, 0.32, d), Basis(), [RoomMesh.DOWN])
	# Stepped chamfered lip & deeper carved under-apron descending 1.10 m below the desktop surface.
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(cx, DESK_TOP - 0.09, cz), Vector3(w + 0.18, 0.14, d + 0.18), Basis(), [RoomMesh.UP, RoomMesh.DOWN])
	s.colour = _lin(MAHOGANY_DARK)
	s.box(Vector3(cx, DESK_TOP - 0.68, cz), Vector3(w - 0.50, DESK_THICK - 0.24, d - 0.50), Basis(), [RoomMesh.UP])

	# Subtle brass corner inlay strips along the desktop perimeter for extra 10:1 cabinetmaker craft.
	var u: RoomMesh = c.u
	u.surface(_brass(c))
	u.colour = _lin(BRASS_DARK)
	for sz: float in [DESK_Z0 + 0.42, DESK_Z1 - 0.42]:
		u.box(Vector3(cx, DESK_TOP + 0.002, sz), Vector3(w - 0.84, 0.008, 0.065), Basis(), [RoomMesh.DOWN])
	for sx: float in [DESK_X0 + 0.42, DESK_X1 - 0.42]:
		u.box(Vector3(sx, DESK_TOP + 0.002, cz), Vector3(0.065, 0.008, d - 0.84), Basis(), [RoomMesh.DOWN])


## Padded leather desk blotter rim and four giant stitched mahogany-leather triangular corner guards framing the custom
## `LeatherBlotter` surface (built in Hall with exact 0..1 UVs on `Procedural.maps("leather_blotter")`).
static func _blotter_frame_and_corners(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var bw := BLOT_X1 - BLOT_X0
	var bd := BLOT_Z1 - BLOT_Z0
	var bcx := (BLOT_X0 + BLOT_X1) * 0.5
	var bcz := (BLOT_Z0 + BLOT_Z1) * 0.5

	# Padded dark saddle-leather blotter edge rim underneath the green top (skip UP face so zero Z-fighting with LeatherBlotter!).
	s.surface(c.tinted("cloth"))
	s.colour = _lin(LEATHER_DARK)
	s.box(Vector3(bcx, (DESK_TOP + BLOTTER_TOP) * 0.5, bcz), Vector3(bw + 0.16, BLOTTER_TOP - DESK_TOP, bd + 0.16),
			Basis(), [RoomMesh.DOWN, RoomMesh.UP])
	# Narrow perimeter leather trim lip around the outside of the green blotter (strictly outside BLOT_X0..X1, Z0..Z1).
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(bcx, (DESK_TOP + BLOTTER_TOP) * 0.5, bcz + sd * (bd * 0.5 + 0.045)),
				Vector3(bw + 0.16, BLOTTER_TOP - DESK_TOP + 0.002, 0.09), Basis(), [RoomMesh.DOWN])
		s.box(Vector3(bcx + sd * (bw * 0.5 + 0.045), (DESK_TOP + BLOTTER_TOP) * 0.5, bcz),
				Vector3(0.09, BLOTTER_TOP - DESK_TOP + 0.002, bd), Basis(), [RoomMesh.DOWN])

	# Four giant stitched leather corner guards (each a bevelled right-triangle flap with stitched gold thread & studs).
	var leg := 1.18
	var ch := 0.036
	var y_top := BLOTTER_TOP + ch
	for corner: Array in [
			[BLOT_X0, BLOT_Z0, 1.0, 1.0],
			[BLOT_X1, BLOT_Z0, -1.0, 1.0],
			[BLOT_X0, BLOT_Z1, 1.0, -1.0],
			[BLOT_X1, BLOT_Z1, -1.0, -1.0]]:
		var x0: float = corner[0]
		var z0: float = corner[1]
		var sx: float = corner[2]
		var sz: float = corner[3]
		var p0 := Vector3(x0 - sx * 0.08, y_top, z0 - sz * 0.08)
		var p1 := Vector3(x0 + sx * leg, y_top, z0 - sz * 0.08)
		var p2 := Vector3(x0 - sx * 0.08, y_top, z0 + sz * leg)
		var b0 := Vector3(p0.x, DESK_TOP, p0.z)
		var b1 := Vector3(p1.x, DESK_TOP, p1.z)
		var b2 := Vector3(p2.x, DESK_TOP, p2.z)
		s.surface(c.tinted("cloth"))
		s.colour = _lin(LEATHER_SADDLE)
		s.face([p0, p1, p2], Vector3.UP)
		# Outer & diagonal bevel skirts.
		var diag_n := Vector3(sx, 0.25, sz).normalized()
		s.face([b1, b2, p2, p1], diag_n)
		s.face([b0, b1, p1, p0], Vector3(0.0, 0.0, -sz))
		s.face([b2, b0, p0, p2], Vector3(-sx, 0.0, 0.0))

		# Stitched gold-thread dash line along the diagonal leather flap + corner brass stud!
		u.surface(_brass(c))
		u.colour = _lin(BRASS)
		var diag_dir := (p2 - p1).normalized()
		var diag_len := p1.distance_to(p2)
		var inward := Vector3(-sx, 0.0, -sz).normalized()
		var stitch_basis := Basis(inward, Vector3.UP, diag_dir)
		for k in 9:
			var t := (float(k) + 0.5) / 9.0
			var sp := p1.lerp(p2, t) + inward * 0.095 + Vector3(0.0, 0.005, 0.0)
			u.box(sp, Vector3(0.018, 0.008, diag_len * 0.06), stitch_basis, [RoomMesh.DOWN])
		Shapes.cylinder(u, Vector3(x0 + sx * 0.14, y_top, z0 + sz * 0.14), 0.055, 0.024, 10)


## Giant circular woven cork & stitched burgundy felt coaster nook cradling all 6 miniature seat cushions (`r = 2.35 m`,
## centred at `(0.0, 0.0, 0.75)` so front row `z = 0.0` and back row `z = 1.5` rest cleanly inside its stitched ring).
static func _coaster_nook(c: Object) -> void:
	var u: RoomMesh = c.u
	var ctr := Vector3(0.0, BLOTTER_TOP, 0.75)
	var h := COASTER_TOP - BLOTTER_TOP

	# Outer natural cork beveled base disc.
	u.surface(c.soft("fabric", true))
	u.colour = _lin(CORK)
	Shapes.lathe(u, [
		Vector2(2.38, 0.0),
		Vector2(2.38, h * 0.65),
		Vector2(2.32, h),
		Vector2(2.22, h),
	], ctr, 32)
	# Recessed stitched burgundy wool/felt top pad.
	u.colour = _lin(COASTER_FELT)
	var pad_pts: Array = []
	for k in 32:
		var a := TAU * float(k) / 32.0
		pad_pts.append(ctr + Vector3(cos(a) * 2.23, h - 0.0005, sin(a) * 2.23))
	u.face(pad_pts, Vector3.UP)

	# Concentric cream blanket-stitch dashes around the coaster rim (instant 10:1 textile scale cue!).
	u.colour = _lin(COASTER_STITCH)
	for k in 36:
		var a := TAU * float(k) / 36.0
		var pos := ctr + Vector3(cos(a) * 2.11, h + 0.002, sin(a) * 2.11)
		u.box(pos, Vector3(0.032, 0.006, 0.14), Basis(Vector3.UP, -a), [RoomMesh.DOWN])

	# Fine inlaid brass trim wire ringing the cork bevel.
	u.surface(_brass(c))
	u.colour = _lin(BRASS_DARK)
	Shapes.lathe(u, [Vector2(2.26, h - 0.001), Vector2(2.23, h + 0.004), Vector2(2.20, h - 0.001)], ctr, 32)


## The cinema screen (`center: [0.0, 1.55, -5.2]`, `size: [3.80, 2.14]`) framed as a colossal brushed-brass & walnut
## pocket display / miniature travel theatre propped cleanly on a giant folded leather notebook & brass ruler cradle.
## Every solid face stays strictly at z <= -5.205 or outside the picture rectangle so every seat has a 100% clear sight
## line.
static func _pocket_display_and_cradle(c: Object) -> void:
	var scr: Dictionary = c.screen
	var sc_xf: Transform3D = scr.get("xf", Transform3D(Basis(), Vector3(0.0, 1.55, -5.2)))
	var sc_sz: Vector2 = scr.get("size", Vector2(3.80, 2.14))
	var cx := sc_xf.origin.x
	var cy := sc_xf.origin.y
	var sz := sc_xf.origin.z
	var w := sc_sz.x
	var h := sc_sz.y
	var hw := w * 0.5
	var hh := h * 0.5

	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)

	# --- 1. Giant Folded Saddle-Leather Notebook Cradle (`y = BLOTTER_TOP..0.28 m`, well below screen bottom 0.48 m) ---
	var nb_z := sz - 0.25
	var nb_top := 0.28
	s.surface(c.tinted("cloth"))
	s.colour = _lin(LEATHER_SADDLE)
	# Lower hardcover board + rounded spine at left.
	s.box(Vector3(cx, BLOTTER_TOP + 0.028, nb_z), Vector3(4.90, 0.056, 2.05), Basis(), [RoomMesh.DOWN])
	# Upper cover board resting atop the cream page block.
	s.box(Vector3(cx, nb_top - 0.025, nb_z), Vector3(4.86, 0.050, 2.00))
	# Thick stack of cream deckled notebook pages visible along front, right and left edges.
	s.surface(c.tinted("plaster"))
	s.colour = _lin(CREAM_PAGE)
	s.box(Vector3(cx + 0.04, (BLOTTER_TOP + 0.056 + nb_top - 0.050) * 0.5, nb_z + 0.02),
			Vector3(4.66, (nb_top - 0.050) - (BLOTTER_TOP + 0.056), 1.88))
	# Deep crimson satin ribbon bookmark emerging from the notebook front onto the green blotter!
	s.surface(c.tinted("cloth"))
	s.colour = _lin(RIBBON_CRIMSON)
	s.box(Vector3(cx - 1.25, 0.14, nb_z + 1.00), Vector3(0.24, 0.27, 0.03), Basis(Vector3.RIGHT, deg_to_rad(-18.0)))
	s.box(Vector3(cx - 1.28, BLOTTER_TOP + 0.008, nb_z + 1.38), Vector3(0.24, 0.016, 0.72),
			Basis(Vector3.UP, deg_to_rad(10.0)), [RoomMesh.DOWN])
	# Brass notebook clasp tabs along the left spine.
	u.surface(brass)
	u.colour = _lin(BRASS)
	for dz: float in [-0.55, 0.55]:
		u.box(Vector3(cx - 2.46, 0.14, nb_z + dz), Vector3(0.06, 0.29, 0.18))

	# --- 2. Giant Brass & Walnut Architect's Ruler Cradle Stop (`z = -4.62`, top y = 0.36 m, 12 cm clear of screen) ---
	var r_z := sz + 0.58
	var r_y := nb_top + 0.038
	s.surface(c.tinted("wood"))
	s.colour = _lin(WALNUT)
	s.box(Vector3(cx, r_y, r_z), Vector3(5.40, 0.076, 0.36))
	# Gleaming beveled brass straightedge facing the viewer.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	u.box(Vector3(cx, r_y - 0.012, r_z + 0.21), Vector3(5.40, 0.048, 0.11), Basis(Vector3.RIGHT, deg_to_rad(22.0)))
	# Crisp dark engraved ruler graduations along the front brass bevel (instant 10:1 precision scale cue!).
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	for k in 25:
		var rx := cx - 2.40 + float(k) * 0.20
		var major := (k % 5 == 0)
		var tick_len := 0.11 if major else 0.062
		s.box(Vector3(rx, r_y + 0.039, r_z + 0.175 - tick_len * 0.5), Vector3(0.016 if major else 0.010, 0.006, tick_len))

	# --- 3. Brushed-Brass & Walnut Pocket Display / Miniature Travel Theatre Housing ---
	var bezel_w := 0.11
	var wood_w := 0.22
	var outer_hw := hw + bezel_w + wood_w
	var outer_hh := hh + bezel_w + wood_w
	var body_d := 0.32
	var body_z := sz - 0.04 - body_d * 0.5

	# Matte-black rear backing plate strictly behind the picture plane (z = sz - 0.035).
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	s.box(Vector3(cx, cy, sz - 0.045), Vector3(w + 0.10, h + 0.10, 0.03))

	# Outer rich walnut cabinet rails surrounding the brass bezel (four sides, strictly outside screen opening).
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(cx + sd * (hw + bezel_w + wood_w * 0.5), cy, body_z),
				Vector3(wood_w, outer_hh * 2.0, body_d))
	s.box(Vector3(cx, cy + hh + bezel_w + wood_w * 0.5, body_z), Vector3((hw + bezel_w) * 2.0, wood_w, body_d))
	s.box(Vector3(cx, cy - hh - bezel_w - wood_w * 0.5, body_z), Vector3((hw + bezel_w) * 2.0, wood_w, body_d))
	# Solid walnut back panel closing the theatre cabinet cleanly behind the screen.
	s.box(Vector3(cx, cy, sz - 0.04 - body_d), Vector3(outer_hw * 2.0, outer_hh * 2.0, 0.06))
	# Walnut corner foot blocks seating the bottom cabinet rail cleanly onto the leather notebook top (y = 0.28).
	var bot_y := cy - outer_hh
	if bot_y > nb_top:
		for fx: float in [-1.65, 1.65]:
			s.box(Vector3(cx + fx, (nb_top + bot_y) * 0.5, body_z), Vector3(0.46, bot_y - nb_top + 0.02, 0.28))

	# Inner stepped gleaming brushed-brass bezel framing the picture cleanly at z = sz - 0.022 (never crossing z = sz!).
	u.surface(brass)
	u.colour = _lin(BRASS)
	var bz := sz - 0.028
	for sd: float in [-1.0, 1.0]:
		u.box(Vector3(cx + sd * (hw + bezel_w * 0.5), cy, bz), Vector3(bezel_w, (hh + bezel_w) * 2.0, 0.048))
	u.box(Vector3(cx, cy + hh + bezel_w * 0.5, bz), Vector3(w, bezel_w, 0.048))
	u.box(Vector3(cx, cy - hh - bezel_w * 0.5, bz), Vector3(w, bezel_w, 0.048))

	# Decorative gleaming brass corner brackets, rivets, side hinges & knurled right-hand brass tuning dials!
	u.colour = _lin(BRASS_WARM)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var bx := cx + sx * (outer_hw - 0.08)
			var by := cy + sy * (outer_hh - 0.08)
			u.box(Vector3(bx, by, sz - 0.025), Vector3(0.24, 0.24, 0.042))
			Shapes.cylinder(u, Vector3(bx - sx * 0.04, by - sy * 0.04, sz - 0.008), 0.026, 0.018, 8,
					Basis(Vector3.RIGHT, PI * 0.5))
	# Twin knurled brass control dials on the right flank of the walnut pocket display.
	for dy: float in [-0.35, 0.15]:
		Shapes.cylinder(u, Vector3(cx + outer_hw, cy + dy, body_z + 0.04), 0.11, 0.12, 14,
				Basis(Vector3.BACK, -PI * 0.5))
	# Classic curved brass carrying handle arch atop the pocket travel theatre (`y = cy + outer_hh .. +0.34 m`).
	var top_y := cy + outer_hh
	for sx: float in [-0.62, 0.62]:
		Shapes.cylinder(u, Vector3(cx + sx, top_y, body_z), 0.055, 0.20, 10)
		u.box(Vector3(cx + sx, top_y + 0.02, body_z), Vector3(0.18, 0.04, 0.16))
	Shapes.beam(u, Vector3(cx - 0.62, top_y + 0.20, body_z), Vector3(cx + 0.62, top_y + 0.20, body_z),
			Vector2(0.068, 0.068))
	# Folding brass A-frame easel prop legs & cross-brace extending cleanly behind the theatre onto the notebook!
	for sx: float in [-1.20, 1.20]:
		Shapes.beam(u, Vector3(cx + sx, cy + 0.65, sz - 0.36), Vector3(cx + sx * 1.08, nb_top + 0.01, sz - 1.18),
				Vector2(0.08, 0.08))
		Shapes.beam(u, Vector3(cx + sx, cy - 0.35, sz - 0.36), Vector3(cx + sx * 1.05, nb_top + 0.42, sz - 0.92),
				Vector2(0.05, 0.05))
	Shapes.beam(u, Vector3(cx - 1.28, nb_top + 0.22, sz - 1.06), Vector3(cx + 1.28, nb_top + 0.22, sz - 1.06),
			Vector2(0.06, 0.06))

	# Clean physics box enclosing the pocket display & notebook cradle (strictly at z <= -4.40, > 4.4 m from seats).
	_solid(c, Vector3(cx, (BLOTTER_TOP + top_y + 0.22) * 0.5, sz - 0.30),
			Vector3(outer_hw * 2.0 + 0.2, top_y + 0.25 - BLOTTER_TOP, 1.55))


## Left desk hero 1: Towering 5.8 m leaning stack of 5 giant Victorian leather-bound hardcover books with raised gilded
## spine bands, embossed spine cartouches, recessed cream deckled page blocks, and a draped gold ribbon bookmark.
static func _left_books_stack(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var base_x := -6.80
	var base_z := -5.20
	var y := BLOTTER_TOP

	# [width_x, height_y, depth_z, dx, dz, yaw_deg, spine_color]
	# Spine faces local +X (angled cleanly toward the viewer's seat!).
	var specs: Array = [
		[3.25, 1.26, 4.20,  0.00,  0.00,  22.0, BOOK_CRIMSON],
		[3.05, 1.12, 3.92,  0.16, -0.14,  11.0, BOOK_GREEN],
		[2.90, 1.24, 3.72, -0.10,  0.12,  32.0, BOOK_NAVY],
		[2.72, 1.08, 3.46,  0.12, -0.06,  17.0, BOOK_TAN],
		[2.52, 1.12, 3.22, -0.08,  0.10,  38.0, BOOK_PLUM],
	]

	for i in specs.size():
		var sp: Array = specs[i]
		var bw: float = sp[0]
		var bh: float = sp[1]
		var bd: float = sp[2]
		var bx := base_x + float(sp[3])
		var bz := base_z + float(sp[4])
		var basis := Basis(Vector3.UP, deg_to_rad(float(sp[5])))
		var col: Color = sp[6]
		var cover_t := 0.085
		var spine_t := 0.12
		var mid_y := y + bh * 0.5
		var ctr := Vector3(bx, mid_y, bz)

		# Hardcover leather boards (bottom, top) and rounded leather spine on +X face.
		s.surface(c.tinted("cloth"))
		s.colour = _lin(col)
		s.box(ctr + Vector3(0.0, -bh * 0.5 + cover_t * 0.5, 0.0), Vector3(bw, cover_t, bd), basis)
		s.box(ctr + Vector3(0.0, bh * 0.5 - cover_t * 0.5, 0.0), Vector3(bw, cover_t, bd), basis)
		s.box(ctr + basis * Vector3(bw * 0.5 - spine_t * 0.5, 0.0, 0.0), Vector3(spine_t, bh, bd), basis)

		# Recessed cream deckled page block (overhung by the leather boards by 12 cm for crisp hardcover shadow!).
		s.surface(c.tinted("plaster"))
		s.colour = _lin(CREAM_PAGE * (0.95 + 0.05 * float(i % 2)))
		var page_h := bh - cover_t * 2.0
		s.box(ctr + basis * Vector3(-0.07, 0.0, 0.0), Vector3(bw - spine_t - 0.14, page_h, bd - 0.24), basis)
		# Subtle dark page-signature banding along the visible fore-edge / foot edge.
		s.colour = _lin(CREAM_PAGE * 0.78)
		for l in 3:
			var ly := -page_h * 0.32 + float(l) * page_h * 0.32
			s.box(ctr + basis * Vector3(-0.07, ly, 0.0), Vector3(bw - spine_t - 0.13, 0.025, bd - 0.23), basis)

		# Raised horizontal gilded brass spine ribs (5 raised bands across the spine + gold-tooled title cartouche!).
		u.surface(brass)
		u.colour = _lin(BRASS)
		for band in 5:
			var bdz := lerpf(-bd * 0.40, bd * 0.40, float(band) / 4.0)
			u.box(ctr + basis * Vector3(bw * 0.5 + 0.025, 0.0, bdz), Vector3(0.055, bh * 0.94, 0.075), basis)
		# Gilded spine title frame plaque between bands 1 and 2.
		u.colour = _lin(BRASS_WARM)
		u.box(ctr + basis * Vector3(bw * 0.5 + 0.014, 0.0, bd * 0.18), Vector3(0.024, bh * 0.62, bd * 0.18), basis)

		# Draped gold cloth ribbon bookmark spilling over Volume 3's page edge!
		if i == 2:
			s.surface(c.tinted("cloth"))
			s.colour = _lin(RIBBON_GOLD)
			var rp := ctr + basis * Vector3(-0.35, -0.05, bd * 0.5 + 0.02)
			s.box(rp + Vector3(0.0, -0.75, 0.05), Vector3(0.20, 1.55, 0.024),
					basis * Basis(Vector3.RIGHT, deg_to_rad(6.0)))

		y += bh

	_solid(c, Vector3(base_x, (BLOTTER_TOP + y) * 0.5, base_z), Vector3(3.8, y - BLOTTER_TOP, 4.6))


## Left desk hero 2: 2.3 m diameter gleaming brass pocket watch propped cleanly against the lower crimson book corner,
## with a sculpted lathed brass case, ribbed winding crown, curved brass bow ring, coiled watch chain, and a working
## live dial keeping real wall time (`PieceClock`).
static func _left_pocket_watch(c: Object) -> void:
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var watch_r := 1.15 # exact 2.30 m diameter!
	# Propped cleanly against the front-right edge of the lower book stack, angled straight toward the viewer's seat!
	var pos := Vector3(-4.35, BLOTTER_TOP + watch_r * 0.985, -3.45)
	var to_eye := (Vector3(0.0, 1.25, 0.0) - pos)
	to_eye.y = 0.0
	var horiz_n := to_eye.normalized()
	# Slight 15° natural backward lean against the books so the face tilts gently up toward the viewer.
	var lean := deg_to_rad(15.0)
	var n := (horiz_n * cos(lean) + Vector3.UP * sin(lean)).normalized()
	# Right-handed face frame: right_u = viewer's right (3 o'clock), up_v = 12 o'clock, n = outward normal.
	var right_u := Vector3.UP.cross(n).normalized()
	var up_v := n.cross(right_u).normalized()
	var face_basis := Basis(right_u, up_v, n)
	# Lathe axis is local +Y, so rotate local +Y -> +n (local +Z -> -up_v).
	var lathe_basis := Basis(right_u, n, -up_v)

	# Turned sculpted gleaming brass pocket watch case (convex back, stepped rim, crisp front bezel lip).
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.00, -0.28),
		Vector2(0.72, -0.27),
		Vector2(1.04, -0.18),
		Vector2(1.15, -0.05),
		Vector2(1.15,  0.08),
		Vector2(1.09,  0.16),
		Vector2(0.98,  0.17),
		Vector2(0.97,  0.11),
	], pos, 32, lathe_basis)

	# Gleaming inner bezel fillet ring.
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, pos + n * 0.13, 0.97, 1.07, 0.06, 32, face_basis, 0.0, TAU, ["front", "inner", "outer"])

	# Working live watch dial (`PieceClock`, `env_clock.gdshader` keeping real wall time!).
	c.clocks.append([pos + n * 0.125, right_u * 0.985, up_v * 0.985, n])

	# Ribbed brass winding pendant neck & knurled crown at 12 o'clock (`+up_v`).
	var neck_base := pos + up_v * (watch_r - 0.02)
	var stem_basis := Basis(right_u, up_v, n)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.16, 0.00),
		Vector2(0.11, 0.12),
		Vector2(0.13, 0.22),
		Vector2(0.24, 0.25),
		Vector2(0.25, 0.36),
		Vector2(0.21, 0.42),
		Vector2(0.00, 0.43),
	], neck_base, 16, stem_basis)

	# Iconic curved brass bow ring arching cleanly over the knurled crown!
	var bow_ctr := neck_base + up_v * 0.36
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, bow_ctr, 0.29, 0.37, 0.085, 22, face_basis, -0.32, PI + 0.32)

	# Graceful coiled brass Albert watch chain sweeping cleanly off the LEFT side of the bow ring (never crossing in
	# front of the clock dial!) and resting in a smooth curve on the green leather blotter!
	var c_pts: Array[Vector3] = []
	var c0 := bow_ctr - right_u * 0.34
	var c1 := pos - right_u * 1.48 + up_v * 0.72 - n * 0.10
	var c2 := pos - right_u * 1.38 - up_v * 0.68 + n * 0.28
	var c3 := Vector3(pos.x - 0.18, BLOTTER_TOP + 0.042, pos.z + 1.35)
	for k in 13:
		c_pts.append(_bezier(c0, c1, c2, c3, float(k) / 12.0))
	var f1 := Vector3(pos.x + 0.42, BLOTTER_TOP + 0.040, pos.z + 1.72)
	var f2 := Vector3(pos.x + 1.05, BLOTTER_TOP + 0.040, pos.z + 1.42)
	var f3 := Vector3(pos.x + 1.35, BLOTTER_TOP + 0.040, pos.z + 0.92)
	for k in range(1, 10):
		c_pts.append(_bezier(c3, f1, f2, f3, float(k) / 9.0))
	u.colour = _lin(BRASS)
	_tube(u, c_pts, 0.036, 0.036, 8, Vector3.UP)
	# Turned brass T-bar fob resting cleanly on the green blotter at the end of the watch chain.
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, f3 + Vector3(-0.20, 0.015, 0.0), 0.044, 0.42, 10, Basis(Vector3.BACK, -PI * 0.5))

	_solid(c, pos, Vector3(2.3, 2.5, 1.2), face_basis)


## Left desk hero 3: Colossal glazed cream-and-cobalt ceramic teacup & saucer (`~2.95 m` tall) with cobalt painted rim
## bands, silky swept ceramic handle, and dark glossy tea surface inside (warm steam wafts above via `atmosphere` `fog`
## at `[-5.60, 2.80, 0.95]`, placed aft of the watch to open a wide dramatic view through the moonlit leaded window!).
static func _left_teacup_and_saucer(c: Object) -> void:
	var u: RoomMesh = c.u
	var ceramic := _ceramic(c)
	var ctr := Vector3(-5.60, BLOTTER_TOP, 0.95)

	# --- Broad Sculpted Cream Porcelain Saucer (r = 2.05 m; non-overlapping cobalt & gold rim segments!) ---
	u.surface(ceramic)
	u.colour = _lin(CREAM_PORCELAIN)
	Shapes.lathe(u, [
		Vector2(1.08, 0.00),
		Vector2(1.22, 0.07),
		Vector2(1.78, 0.22),
		Vector2(2.05, 0.42),
		Vector2(2.03, 0.45),
	], ctr, 32)
	# Inner saucer well (closing cleanly under the cup foot & stopping before the cobalt rim band — zero gaps or Z-fighting!).
	Shapes.lathe(u, [
		Vector2(1.83, 0.37),
		Vector2(1.56, 0.24),
		Vector2(1.02, 0.14),
		Vector2(0.84, 0.115),
		Vector2(0.00, 0.11),
	], ctr, 32)
	# Cobalt-blue glazed band cleanly joining the saucer lip (r = 1.98 -> 1.83, exact non-overlapping strip!).
	u.colour = _lin(COBALT_GLAZE)
	Shapes.lathe(u, [
		Vector2(1.98, 0.455),
		Vector2(1.83, 0.37),
	], ctr, 32)
	# Gleaming gilded rim lip capping the saucer edge (r = 2.03 -> 1.98).
	u.surface(_brass(c))
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [
		Vector2(2.03, 0.45),
		Vector2(2.01, 0.465),
		Vector2(1.98, 0.455),
	], ctr, 32)

	# --- Colossal Curved Victorian Teacup (`y = 0.12..2.94 m`, top radius 1.50 m; clean non-overlapping glaze bands!) ---
	u.surface(ceramic)
	u.colour = _lin(CREAM_PORCELAIN)
	Shapes.lathe(u, [
		Vector2(0.86, 0.12),
		Vector2(0.94, 0.24),
		Vector2(0.88, 0.38),
		Vector2(1.18, 0.78),
		Vector2(1.36, 1.38),
		Vector2(1.425, 2.08),
	], ctr, 32)
	# Thin lower cobalt glaze ring (`y = 2.08..2.22`).
	u.colour = _lin(COBALT_GLAZE)
	Shapes.lathe(u, [Vector2(1.425, 2.08), Vector2(1.440, 2.22)], ctr, 32)
	# Cream band between stripes (`y = 2.22..2.40`).
	u.colour = _lin(CREAM_PORCELAIN)
	Shapes.lathe(u, [Vector2(1.440, 2.22), Vector2(1.460, 2.40)], ctr, 32)
	# Broad upper cobalt glaze band (`y = 2.40..2.68`).
	u.colour = _lin(COBALT_GLAZE)
	Shapes.lathe(u, [Vector2(1.460, 2.40), Vector2(1.486, 2.68)], ctr, 32)
	# Cream upper collar (`y = 2.68..2.88`) & inner cup wall (`y = 2.91..1.85`).
	u.colour = _lin(CREAM_PORCELAIN)
	Shapes.lathe(u, [Vector2(1.486, 2.68), Vector2(1.500, 2.88)], ctr, 32)
	Shapes.lathe(u, [Vector2(1.41, 2.91), Vector2(1.32, 2.38), Vector2(1.22, 1.85)], ctr, 32)
	# Gleaming gilded cup rim lip (`y = 2.88..2.945..2.91`).
	u.surface(_brass(c))
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [
		Vector2(1.500, 2.88),
		Vector2(1.475, 2.945),
		Vector2(1.410, 2.91),
	], ctr, 32)

	# Silky swept ear-shaped porcelain teacup handle (smooth 16-segment cubic Bezier tube — zero kinks or gaps!).
	var h_ang := deg_to_rad(56.0)
	var h_dir := Vector3(cos(h_ang), 0.0, sin(h_ang))
	var h_side := Vector3(-sin(h_ang), 0.0, cos(h_ang))
	var h0 := ctr + h_dir * 1.43 + Vector3(0.0, 2.42, 0.0)
	var h1 := ctr + h_dir * 2.52 + Vector3(0.0, 2.74, 0.0)
	var h2 := ctr + h_dir * 2.38 + Vector3(0.0, 1.08, 0.0)
	var h3 := ctr + h_dir * 1.18 + Vector3(0.0, 0.84, 0.0)
	var handle_curve: Array[Vector3] = []
	for k in 17:
		handle_curve.append(_bezier(h0, h1, h2, h3, float(k) / 16.0))
	u.surface(ceramic)
	u.colour = _lin(CREAM_PORCELAIN)
	_tube(u, handle_curve, 0.145, 0.095, 10, h_side)

	# Rich glossy dark steaming tea surface inside the teacup (`y = 2.50 m`, CCW from +Y so normal faces upward!).
	u.surface(_lacquer(c))
	u.colour = _lin(TEA_DARK)
	var tea_pts: Array = []
	for k in 24:
		var a := -TAU * float(k) / 24.0
		tea_pts.append(ctr + Vector3(cos(a) * 1.34, 2.50, sin(a) * 1.34))
	u.face(tea_pts, Vector3.UP)

	_solid(c, ctr + Vector3(0.0, 1.48, 0.0), Vector3(3.6, 2.95, 3.6))


## Left desk hero 4: Giant lacquered burgundy-black fountain pen with gleaming gold nib resting horizontally across the
## front-left blotter corner, plus its uncapped brass-banded lid lying nearby.
static func _left_fountain_pen(c: Object) -> void:
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var pen_origin := Vector3(-3.35, BLOTTER_TOP + 0.145, -1.25)
	# Pen axis points toward (+X, -Z) along the blotter edge, strictly x <= -2.35 (clear of coaster & sight line).
	var yaw := deg_to_rad(-34.0)
	var pen_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5) # local +Y runs along the pen's length!

	# Deep burgundy-black glossy lacquered barrel & sculpted grip section (length ~ 2.45 m + 0.55 m gold nib!).
	u.surface(_lacquer(c))
	u.colour = _lin(PEN_LACQUER)
	Shapes.lathe(u, [
		Vector2(0.00, -1.45),
		Vector2(0.08, -1.42),
		Vector2(0.135, -1.15),
		Vector2(0.148, -0.30),
		Vector2(0.145,  0.55),
		Vector2(0.115,  0.70),
		Vector2(0.105,  0.98),
		Vector2(0.120,  1.06),
		Vector2(0.095,  1.10),
	], pen_origin, 16, pen_basis)

	# Gleaming brass decorative barrel bands & section trim collar.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.152, 0.48), Vector2(0.152, 0.57)], pen_origin, 16, pen_basis)
	Shapes.lathe(u, [Vector2(0.142, -1.08), Vector2(0.142, -1.03)], pen_origin, 16, pen_basis)

	# Gleaming sculpted gold fountain pen nib (diamond-tapered curved blade projecting forward to +1.64 m!).
	var axis_f := pen_basis * Vector3.UP
	var axis_r := pen_basis * Vector3.FORWARD
	var axis_u := Vector3.UP
	var nib_root := pen_origin + axis_f * 1.06
	var nib_mid := pen_origin + axis_f * 1.32
	var nib_tip := pen_origin + axis_f * 1.66
	var w0 := 0.082
	var w1 := 0.115
	u.face([
		nib_root - axis_r * w0 + axis_u * 0.035,
		nib_root + axis_r * w0 + axis_u * 0.035,
		nib_mid + axis_r * w1 + axis_u * 0.025,
		nib_tip,
		nib_mid - axis_r * w1 + axis_u * 0.025,
	], axis_u)
	u.face([
		nib_root - axis_r * w0 + axis_u * 0.012,
		nib_mid - axis_r * w1 + axis_u * 0.008,
		nib_tip - axis_u * 0.008,
		nib_mid + axis_r * w1 + axis_u * 0.008,
		nib_root + axis_r * w0 + axis_u * 0.012,
	], -axis_u)
	# Dark ebonite ink feed under the gold nib & central breather slit.
	u.surface(_lacquer(c))
	u.colour = _lin(IRON_DARK)
	Shapes.beam(u, nib_root + axis_u * 0.036, nib_tip - axis_f * 0.06 + axis_u * 0.012, Vector2(0.012, 0.012))
	Shapes.beam(u, nib_root - axis_u * 0.018, nib_mid + axis_f * 0.12 - axis_u * 0.022, Vector2(0.095, 0.045))

	# Uncapped lacquered pen cap with brass pocket clip resting diagonally nearby (`x = -3.75, z = -2.25`).
	var cap_pos := Vector3(-3.85, BLOTTER_TOP + 0.165, -2.18)
	var cap_basis := Basis(Vector3.UP, deg_to_rad(18.0)) * Basis(Vector3.BACK, -PI * 0.5)
	u.surface(_lacquer(c))
	u.colour = _lin(PEN_LACQUER)
	Shapes.lathe(u, [
		Vector2(0.00, -0.58),
		Vector2(0.11, -0.55),
		Vector2(0.165, -0.35),
		Vector2(0.168,  0.55),
		Vector2(0.145,  0.55),
	], cap_pos, 14, cap_basis)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.174, 0.36), Vector2(0.174, 0.52)], cap_pos, 14, cap_basis)
	var cf := cap_basis * Vector3.UP
	Shapes.beam(u, cap_pos - cf * 0.42 + Vector3(0.0, 0.18, 0.0), cap_pos + cf * 0.38 + Vector3(0.0, 0.20, 0.0),
			Vector2(0.045, 0.028))


## Right desk hero 1: Soaring 7.8 m tall iconic green-glass banker's / articulated brass desk lamp arching gracefully
## over the right side of the desk (strictly clear of sight lines!), with glowing translucent emerald/warm shade in
## `PieceCove` (live `desk_lamp` setting + `cove_floor: 0.45`), warm inner bulb & diffuser in `PieceLamps`, brass pull
## chain, and downward volumetric cone (`LampCone` in Hall).
static func _right_bankers_lamp(c: Object) -> void:
	var u: RoomMesh = c.u
	var cove: RoomMesh = c.cove
	var lit: RoomMesh = c.lit
	var brass := _brass(c)

	var base_at := Vector3(6.85, DESK_TOP, -2.80)
	var elbow_at := Vector3(6.95, 5.05, -2.82)
	var apex_at := Vector3(5.55, 7.80, -2.35) # True 7.8 m towering apex!
	var yoke_top := Vector3(4.85, 7.05, -2.18)

	# --- Heavy Stepped Classical Tiered Brass Pedestal Base (`r = 1.45 m`, height `0.85 m`) ---
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(1.48, 0.00),
		Vector2(1.48, 0.16),
		Vector2(1.36, 0.24),
		Vector2(1.24, 0.28),
		Vector2(1.16, 0.44),
		Vector2(0.86, 0.56),
		Vector2(0.68, 0.68),
		Vector2(0.46, 0.84),
		Vector2(0.32, 0.94),
	], base_at, 24)
	# Gleaming brass push-toggle switch on the front base plinth.
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, base_at + Vector3(-1.05, 0.22, 0.45), 0.11, 0.18, 10)

	# --- Articulated Twin-Column & Graceful Arched Brass Neck (reaching 7.80 m!) ---
	u.colour = _lin(BRASS)
	# Twin parallel vertical brass lower risers from pedestal to articulated knuckle joint.
	for dz: float in [-0.18, 0.18]:
		Shapes.beam(u, base_at + Vector3(0.0, 0.86, dz), elbow_at + Vector3(0.0, 0.0, dz), Vector2(0.14, 0.14))
	# Heavy machined brass elbow knuckle & tension wing-nut bolt.
	Shapes.cylinder(u, elbow_at + Vector3(0.0, 0.0, -0.34), 0.24, 0.68, 14, Basis(Vector3.RIGHT, PI * 0.5))
	u.colour = _lin(BRASS_WARM)
	Shapes.cylinder(u, elbow_at + Vector3(0.0, 0.0, 0.34), 0.16, 0.16, 12, Basis(Vector3.RIGHT, PI * 0.5))

	# Sweeping arched upper swan-neck arm rising from elbow (5.05 m) up over the 7.80 m apex to the shade yoke!
	var arc_pts: Array[Vector3] = [
		elbow_at,
		Vector3(6.85, 6.25, -2.74),
		Vector3(6.42, 7.25, -2.58),
		apex_at,
		Vector3(5.12, 7.56, -2.26),
		yoke_top,
	]
	u.colour = _lin(BRASS)
	for k in arc_pts.size() - 1:
		Shapes.beam(u, arc_pts[k], arc_pts[k + 1], Vector2(0.20, 0.20))
	# Turned decorative brass apex finial cap at y = 7.80 m.
	Shapes.lathe(u, [Vector2(0.14, 0.0), Vector2(0.19, 0.08), Vector2(0.10, 0.18), Vector2(0.0, 0.26)],
			apex_at + Vector3(0.0, 0.06, 0.0), 12)

	# Twin forked brass swivel yoke embracing the ends of the curved banker's glass cowl shade!
	var shade_len := 3.15
	var shade_r := 0.96
	var shade_tilt := Basis(Vector3.UP, deg_to_rad(14.0)) * Basis(Vector3.BACK, deg_to_rad(22.0))
	var sh_end_a := SHADE_AT + shade_tilt * Vector3(0.0, 0.0, -shade_len * 0.52)
	var sh_end_b := SHADE_AT + shade_tilt * Vector3(0.0, 0.0, shade_len * 0.52)
	u.colour = _lin(BRASS_WARM)
	Shapes.beam(u, yoke_top, sh_end_a, Vector2(0.11, 0.11))
	Shapes.beam(u, yoke_top, sh_end_b, Vector2(0.11, 0.11))
	# Turned brass shade-end pivot rosettes.
	for end_p: Vector3 in [sh_end_a, sh_end_b]:
		Shapes.cylinder(u, end_p - shade_tilt * Vector3(0.0, 0.0, 0.08), 0.22, 0.16, 12,
				shade_tilt * Basis(Vector3.RIGHT, PI * 0.5))

	# Hanging beaded brass pull-chain with turned acorn tassel beneath the shade!
	var chain_top := SHADE_AT + Vector3(0.55, -0.15, 0.25)
	for k in 11:
		var by := chain_top.y - float(k) * 0.145
		Shapes.cylinder(u, Vector3(chain_top.x, by, chain_top.z), 0.042, 0.075, 8)
	Shapes.lathe(u, [
		Vector2(0.00, 0.00),
		Vector2(0.095, 0.10),
		Vector2(0.115, 0.22),
		Vector2(0.065, 0.30),
		Vector2(0.00, 0.32),
	], Vector3(chain_top.x, chain_top.y - 1.92, chain_top.z), 12)

	# --- Iconic Curved Translucent Banker's Glass Cowl Shade (`PieceCove` -> live `desk_lamp` setting!) ---
	# Outer curved emerald/warm glass cowl with graded glow weight (deeper jewel saturation at edges, glowing gently
	# near the filament crown so Green banker's glow glows rich emerald green rather than blown-out mint!).
	cove.surface(c.kit.cove_material())
	var segs := 16
	var half_l := shade_len * 0.5
	var cowl_rows: Array = []
	var cowl_norms: Array = []
	var cowl_cols: Array = []
	for j in 2:
		var z_loc := -half_l if j == 0 else half_l
		var r_pts := PackedVector3Array()
		var r_nrms := PackedVector3Array()
		var r_cols := PackedColorArray()
		for k in segs + 1:
			var t := float(k) / float(segs)
			var ang := lerpf(-0.12, PI + 0.12, t)
			var local_p := Vector3(cos(ang) * shade_r, sin(ang) * shade_r * 0.88, z_loc)
			var local_n := Vector3(cos(ang), sin(ang) * 1.12, 0.0).normalized()
			r_pts.append(SHADE_AT + shade_tilt * local_p)
			r_nrms.append((shade_tilt * local_n).normalized())
			var crown := sin(clampf(t * PI, 0.0, PI))
			var w := lerpf(0.46, 0.72, crown)
			r_cols.append(Color(0.76, 0.80, 0.76, w))
		cowl_rows.append(r_pts)
		cowl_norms.append(r_nrms)
		cowl_cols.append(r_cols)
	cove.sheet(cowl_rows, cowl_norms, cowl_cols, Vector3.RIGHT, Vector3.FORWARD)
	# Curved solid end cheeks of the banker's shade in PieceCove so the glowing glass cowl reads solid from every angle!
	for sd: float in [-1.0, 1.0]:
		var pts: Array = []
		for k in segs + 1:
			var ang := lerpf(-0.12, PI + 0.12, float(k) / float(segs))
			pts.append(SHADE_AT + shade_tilt * Vector3(cos(ang) * shade_r, sin(ang) * shade_r * 0.88, sd * half_l))
		cove.colour = Color(0.70, 0.74, 0.70, 0.56)
		cove.face(pts, (shade_tilt * Vector3(0.0, 0.0, sd)).normalized())

	# Gleaming brass edge binding strips framing the lower lip of the glass cowl.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	for sd: float in [-1.0, 1.0]:
		var lip := SHADE_AT + shade_tilt * Vector3(sd * shade_r * 0.99, -0.09, 0.0)
		u.box(lip, Vector3(0.075, 0.09, shade_len + 0.06), shade_tilt)

	# --- Warm Opal-Cream Inner Liner & Glowing Incandescent Bulb inside the Banker's Shade (`PieceLamps`) ---
	lit.surface(c.shade(LAMP_WARM))
	var in_front := PackedVector3Array()
	var in_back := PackedVector3Array()
	var in_norms := PackedVector3Array()
	for k in segs + 1:
		var ang := lerpf(-0.08, PI + 0.08, float(k) / float(segs))
		var local_p := Vector3(cos(ang) * (shade_r - 0.06), sin(ang) * (shade_r * 0.88 - 0.06), 0.0)
		var local_n := -Vector3(cos(ang), sin(ang) * 1.12, 0.0).normalized()
		in_front.append(SHADE_AT + shade_tilt * (local_p + Vector3(0.0, 0.0, half_l - 0.05)))
		in_back.append(SHADE_AT + shade_tilt * (local_p + Vector3(0.0, 0.0, -half_l + 0.05)))
		in_norms.append((shade_tilt * local_n).normalized())
	lit.strip(in_front, in_back, in_norms)
	# Glowing elongated vintage glass filament bulb tucked inside the shade.
	Shapes.lathe(lit, [
		Vector2(0.00, -0.45),
		Vector2(0.24, -0.35),
		Vector2(0.28,  0.00),
		Vector2(0.24,  0.35),
		Vector2(0.00,  0.45),
	], SHADE_AT + shade_tilt * Vector3(0.0, 0.24, 0.0), 14, shade_tilt * Basis(Vector3.RIGHT, PI * 0.5))

	_solid(c, base_at + Vector3(0.0, 3.6, 0.0), Vector3(2.9, 7.2, 2.9))


## Right desk hero 2: Giant faceted crystal glass & brass inkwell (`x = +4.35, z = -3.55`, ~1.45 m tall) with dark
## midnight-indigo ink visible inside the glass prism (`PieceGlass`) and a flipped-open hinged brass cap!
static func _right_inkwell(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var g: RoomMesh = c.glass
	var brass := _brass(c)
	var ctr := Vector3(4.35, BLOTTER_TOP, -3.55)
	var rot := Basis(Vector3.UP, deg_to_rad(-18.0))

	# Dark midnight-indigo ink reservoir inside the crystal glass body.
	s.surface(c.tinted("iron"))
	s.colour = _lin(INK_INDIGO)
	Shapes.cylinder(s, ctr + Vector3(0.0, 0.14, 0.0), 0.48, 0.62, 12, rot)

	# Heavy faceted 8-sided beveled crystal inkwell prism (`PieceGlass`, see-through!).
	g.surface(c.kit.GLASS)
	Shapes.lathe(g, [
		Vector2(0.76, 0.00),
		Vector2(0.79, 0.08),
		Vector2(0.79, 0.88),
		Vector2(0.66, 1.05),
		Vector2(0.42, 1.10),
	], ctr, 8, rot)

	# Turned brass collar neck & flipped-open hinged domed brass lid!
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.lathe(u, [
		Vector2(0.46, 1.04),
		Vector2(0.48, 1.14),
		Vector2(0.40, 1.18),
		Vector2(0.42, 1.28),
		Vector2(0.32, 1.28),
	], ctr, 18, rot)
	# Open hinged brass lid flipped 82° back on its hinge knuckle — closed solid double-sided shell so both inner and
	# outer brass surfaces show cleanly from the viewer's seat!
	var hinge := ctr + rot * Vector3(0.0, 1.28, -0.40)
	u.colour = _lin(BRASS_WARM)
	u.box(hinge, Vector3(0.28, 0.11, 0.11), rot)
	var lid_basis := rot * Basis(Vector3.RIGHT, deg_to_rad(-82.0))
	Shapes.lathe(u, [
		Vector2(0.00, 0.02),
		Vector2(0.36, 0.02),
		Vector2(0.42, 0.00),
		Vector2(0.43, 0.08),
		Vector2(0.33, 0.20),
		Vector2(0.14, 0.26),
		Vector2(0.16, 0.34),
		Vector2(0.00, 0.38),
	], hinge + lid_basis * Vector3(0.0, 0.0, 0.42), 18, lid_basis)

	_solid(c, ctr + Vector3(0.0, 0.72, 0.0), Vector3(1.55, 1.45, 1.55), rot)


## Right desk hero 3: Tall glazed stoneware ceramic pot (`y = 0..2.35 m`) bristling with 7 giant hexagonal coloured
## cedar pencils (every pencil passes strictly inside the open rim — zero wall clipping!).
static func _right_pencil_pot(c: Object) -> void:
	var u: RoomMesh = c.u
	var ceramic := _ceramic(c)
	var ctr := Vector3(6.45, BLOTTER_TOP, -0.15)

	# Tall ribbed glazed two-tone stoneware ceramic pencil pot with generous open mouth (inner r = 0.84 m).
	u.surface(ceramic)
	u.colour = _lin(POT_SAGE)
	Shapes.lathe(u, [
		Vector2(0.86, 0.00),
		Vector2(0.94, 0.28),
		Vector2(0.98, 0.95),
		Vector2(0.96, 1.55),
	], ctr, 24)
	u.colour = _lin(POT_CREAM)
	Shapes.lathe(u, [
		Vector2(0.96, 1.55),
		Vector2(0.94, 2.15),
		Vector2(0.99, 2.30),
		Vector2(0.93, 2.36),
		Vector2(0.84, 2.32),
		Vector2(0.80, 1.55),
	], ctr, 24)

	# 7 giant hexagonal coloured cedar pencils fanning cleanly out of the pot mouth (every pencil anchored from its
	# rim-exit point `(rx, rz)` inside `r <= 0.60 m` down into the pot bottom — mathematically guaranteed ZERO clipping!).
	# [rim_x, rim_z, tilt_out_deg, length, lacquer_color, has_eraser_up]
	var pencils: Array = [
		[-0.44, -0.22, 13.0, 3.65, Color(0.76, 0.16, 0.14), false], # Crimson red
		[ 0.42, -0.26, 12.0, 3.82, Color(0.84, 0.62, 0.16), false], # Golden ochre
		[-0.22,  0.46, 13.0, 3.58, Color(0.14, 0.34, 0.68), false], # Deep cobalt
		[ 0.46,  0.22, 12.0, 3.74, Color(0.14, 0.54, 0.30), false], # Lush emerald
		[-0.48,  0.14, 11.0, 3.48, Color(0.68, 0.30, 0.14), false], # Burnt sienna
		[ 0.04, -0.02,  3.5, 3.94, Color(0.86, 0.66, 0.18), true],  # Classic drafting pencil (eraser up!)
		[ 0.06, -0.46, 12.0, 3.52, Color(0.22, 0.23, 0.26), false], # Slate charcoal
	]
	var wood_soft: Material = c.soft("wood", true)
	var brass := _brass(c)
	for pc: Array in pencils:
		var rx: float = pc[0]
		var rz: float = pc[1]
		var tilt := deg_to_rad(float(pc[2]))
		var plen: float = pc[3]
		var col: Color = pc[4]
		var eraser_up: bool = pc[5]
		var out_xz := Vector3(rx, 0.0, rz).normalized()
		var axis_up := (Vector3.UP * cos(tilt) + out_xz * sin(tilt)).normalized()
		var side_r := axis_up.cross(Vector3.FORWARD)
		if side_r.length() < 0.01:
			side_r = axis_up.cross(Vector3.RIGHT)
		side_r = side_r.normalized()
		var side_f := side_r.cross(axis_up).normalized()
		var p_basis := Basis(side_r, axis_up, side_f)
		# Place the pencil so it crosses y = 2.30 right at `(rx, 2.30, rz)` and rests 1.75 m inside the pot!
		var rim_p := ctr + Vector3(rx, 2.30, rz)
		var base := rim_p - axis_up * 1.72
		var r := 0.105
		if eraser_up:
			u.surface(wood_soft)
			u.colour = _lin(col)
			Shapes.cylinder(u, base, r, plen - 0.52, 6, p_basis, false)
			u.surface(brass)
			u.colour = _lin(BRASS_WARM)
			Shapes.cylinder(u, base + p_basis * Vector3(0.0, plen - 0.52, 0.0), r * 1.05, 0.28, 12, p_basis, false)
			u.surface(wood_soft)
			u.colour = _lin(ERASER_PINK)
			Shapes.lathe(u, [Vector2(r * 0.98, 0.0), Vector2(r * 0.96, 0.20), Vector2(0.0, 0.25)],
					base + p_basis * Vector3(0.0, plen - 0.24, 0.0), 12, p_basis)
		else:
			u.surface(wood_soft)
			u.colour = _lin(col)
			Shapes.cylinder(u, base, r, plen - 0.55, 6, p_basis, false)
			# Raw cedar sharpened wood cone.
			u.colour = _lin(CEDAR_RAW)
			Shapes.lathe(u, [Vector2(r, 0.0), Vector2(r * 0.34, 0.38)],
					base + p_basis * Vector3(0.0, plen - 0.55, 0.0), 6, p_basis)
			# Coloured / graphite pencil tip point!
			u.colour = _lin(col * 0.72)
			Shapes.lathe(u, [Vector2(r * 0.34, 0.0), Vector2(0.0, 0.18)],
					base + p_basis * Vector3(0.0, plen - 0.17, 0.0), 6, p_basis)

	_solid(c, ctr + Vector3(0.0, 1.85, 0.0), Vector3(2.2, 3.7, 2.2))


## Right desk hero 4: Giant brass wire-rimmed Victorian spectacles resting open & upright on the green leather blotter
## (`x = +3.95, z = -0.35`, curved brass temple arms sweeping cleanly back with zero lens intersection!).
static func _right_spectacles(c: Object) -> void:
	var u: RoomMesh = c.u
	var g: RoomMesh = c.glass
	var brass := _brass(c)
	var lens_r := 0.48
	var sep := 0.64
	var ctr := Vector3(3.95, BLOTTER_TOP + lens_r + 0.04, -0.35)
	var rot := Basis(Vector3.UP, deg_to_rad(-34.0)) * Basis(Vector3.RIGHT, deg_to_rad(10.0))

	# Twin standing circular brass wire rims facing slightly toward the viewer.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	for sd: float in [-1.0, 1.0]:
		var lc := ctr + rot * Vector3(sd * sep, 0.0, 0.0)
		Shapes.arch(u, lc, lens_r - 0.042, lens_r + 0.042, 0.068, 24, rot, 0.0, TAU)
		# Clear glass spectacles lens disc (`PieceGlass`).
		g.surface(c.kit.GLASS)
		var pts: Array = []
		for k in 16:
			var a := TAU * float(k) / 16.0
			pts.append(lc + rot * Vector3(cos(a) * (lens_r - 0.04), sin(a) * (lens_r - 0.04), 0.0))
		g.face(pts, (rot * Vector3.BACK).normalized())

	# Graceful arched brass saddle nose-bridge joining the two lens rims.
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.arch(u, ctr + rot * Vector3(0.0, 0.04, 0.0), sep - lens_r - 0.04, sep - lens_r + 0.04, 0.055, 14, rot,
			0.0, PI)

	# Open slender brass wire ear-temples extending cleanly back to rest on the green blotter with curved ear hooks!
	for sd: float in [-1.0, 1.0]:
		var hinge := ctr + rot * Vector3(sd * (sep + lens_r + 0.02), 0.06, -0.02)
		var mid_t := ctr + rot * Vector3(sd * (sep + lens_r + 0.04), -0.10, -1.25)
		var tip_t := ctr + rot * Vector3(sd * (sep + lens_r - 0.08), -0.44, -1.52)
		var arm_pts: Array[Vector3] = [hinge, hinge.lerp(mid_t, 0.5), mid_t,
				ctr + rot * Vector3(sd * (sep + lens_r + 0.01), -0.26, -1.46), tip_t]
		_tube(u, arm_pts, 0.026, 0.026, 8, rot * Vector3.RIGHT)


## Right desk hero 5: Giant brass-handled magnifying glass resting beside the spectacles (`x = +4.40, z = +1.65`).
static func _right_magnifying_glass(c: Object) -> void:
	var u: RoomMesh = c.u
	var g: RoomMesh = c.glass
	var brass := _brass(c)
	var lens_c := Vector3(4.25, BLOTTER_TOP + 0.095, 1.55)
	var rot := Basis(Vector3.UP, deg_to_rad(36.0))
	var lens_r := 0.78

	# Heavy beveled brass lens frame ring.
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.arch(u, lens_c, lens_r - 0.09, lens_r + 0.09, 0.16, 24, rot * Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU)

	# Clear glass magnifying lens (`PieceGlass`).
	g.surface(c.kit.GLASS)
	var pts: Array = []
	for k in 20:
		var a := TAU * float(k) / 20.0
		pts.append(lens_c + Vector3(cos(a) * (lens_r - 0.085), 0.015, sin(a) * (lens_r - 0.085)))
	g.face(pts, Vector3.UP)

	# Turned brass ferrule collar, dark sculpted mahogany handle & brass pommel cap extending along local +X.
	var h_basis := rot * Basis(Vector3.BACK, -PI * 0.5)
	var h_start := lens_c + rot * Vector3(lens_r + 0.06, 0.0, 0.0)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.11, 0.0), Vector2(0.145, 0.08), Vector2(0.135, 0.28)], h_start, 14, h_basis)
	u.surface(c.soft("wood", true))
	u.colour = _lin(MAHOGANY_DARK)
	Shapes.lathe(u, [
		Vector2(0.132, 0.28),
		Vector2(0.165, 0.65),
		Vector2(0.195, 1.25),
		Vector2(0.175, 1.68),
		Vector2(0.125, 1.78),
	], h_start, 14, h_basis)
	u.surface(brass)
	u.colour = _lin(BRASS_WARM)
	Shapes.lathe(u, [Vector2(0.125, 1.78), Vector2(0.11, 1.88), Vector2(0.0, 1.94)], h_start, 12, h_basis)


## Right desk hero 6: Iconic giant gleaming brass trombone paperclip (`1.18 m` long) resting flat on the foreground
## green blotter (`x = +3.10, z = -1.95`) — instant unmistakable 10:1 miniature scale anchor!
static func _right_paperclip(c: Object) -> void:
	var u: RoomMesh = c.u
	u.surface(_brass(c))
	u.colour = _lin(BRASS_WARM)
	var ctr := Vector3(3.10, BLOTTER_TOP + 0.034, -1.95)
	var rot := Basis(Vector3.UP, deg_to_rad(24.0))
	var flat := rot * Basis(Vector3.RIGHT, PI * 0.5)
	var wr := 0.032

	# Outer right-side & left-side straight bars + inner nested straight bar.
	Shapes.beam(u, ctr + rot * Vector3(-0.36, 0.0, -0.17), ctr + rot * Vector3(0.38, 0.0, -0.17), Vector2(wr * 2.0, wr * 2.0))
	Shapes.beam(u, ctr + rot * Vector3(-0.36, 0.0,  0.17), ctr + rot * Vector3(0.30, 0.0,  0.17), Vector2(wr * 2.0, wr * 2.0))
	Shapes.beam(u, ctr + rot * Vector3(-0.26, 0.0, -0.095), ctr + rot * Vector3(0.38, 0.0, -0.095), Vector2(wr * 2.0, wr * 2.0))
	Shapes.beam(u, ctr + rot * Vector3(-0.26, 0.0,  0.095), ctr + rot * Vector3(0.24, 0.0,  0.095), Vector2(wr * 2.0, wr * 2.0))

	# Three concentric curved wire U-bends completing the trombone loop!
	Shapes.arch(u, ctr + rot * Vector3(-0.36, 0.0, 0.0), 0.17 - wr, 0.17 + wr, wr * 1.9, 12, flat, PI * 0.5, PI * 1.5)
	Shapes.arch(u, ctr + rot * Vector3(0.38, 0.0, -0.1325), 0.0375 - wr * 0.55, 0.0375 + wr * 1.15, wr * 1.9, 10, flat,
			-PI * 0.5, PI * 0.5)
	Shapes.arch(u, ctr + rot * Vector3(-0.26, 0.0, 0.0), 0.095 - wr * 0.85, 0.095 + wr * 0.85, wr * 1.9, 10, flat,
			PI * 0.5, PI * 1.5)
	Shapes.arch(u, ctr + rot * Vector3(0.30, 0.0, 0.1325), 0.0375 - wr * 0.55, 0.0375 + wr * 1.15, wr * 1.9, 10, flat,
			-PI * 0.5, PI * 0.5)


## 8 stand-in shader + hidden bake lamps (`bake_lamps: 8`) plus a bake-only moonlight spotlight through the colossal
## left window: warm golden banker's lamp & fireplace glow balanced against cool silver moonlight on the left!
static func _desk_lamps(c: Object) -> void:
	# 1. Banker's lamp primary warm golden pool over right desk props.
	c.lamps.append([Vector3(4.55, 5.20, -2.05), Color(1.0, 0.80, 0.46), 1.65])
	# 2. Warm lower blotter & pocket display key bounce.
	c.lamps.append([Vector3(2.80, 2.35, -2.55), Color(1.0, 0.76, 0.44), 0.95])
	# 3. Cozy warm desk rim catching the brass pocket watch, books, fountain pen & teacup.
	c.lamps.append([Vector3(-3.10, 2.90, -2.35), Color(1.0, 0.74, 0.44), 0.92])
	# 4. Silvery cool moonlight grazing in from the colossal left leaded window.
	c.lamps.append([Vector3(-12.0, 4.60, -2.50), Color(0.54, 0.70, 0.96), 1.30])
	# 5. Warm glowing fireplace hearth across the back-right study wall.
	c.lamps.append([Vector3(12.2, 1.25, 5.60), Color(1.0, 0.52, 0.20), 1.70])
	# 6. Warm hearth upper mantel & aft library bookshelves wash.
	c.lamps.append([Vector3(9.80, 4.90, 5.80), Color(0.96, 0.56, 0.26), 0.95])
	# 7. Subtle warm library backdrop wash on the towering front bookshelves behind the screen.
	c.lamps.append([Vector3(0.0, 5.60, -11.0), Color(0.84, 0.62, 0.36), 0.78])
	# 8. Soft overhead cozy fill over the woven cork coaster cushions & aft mahogany desk edge.
	c.lamps.append([Vector3(0.20, 4.10, 1.35), Color(0.96, 0.74, 0.46), 0.72])

	# Hidden bake-only moonlight SpotLight3D slanting in through the colossal left leaded window.
	c.spots.append([Vector3(-17.0, 6.4, -3.0), Vector3(-3.5, 0.2, -1.5), Color(0.58, 0.74, 0.98), 2.4, 24.0, 42.0])


# ======================================================================================================================
# Piece 2: study_room — the colossal shadowy Victorian study beyond the desk edge
# ======================================================================================================================

static func _study_room(c: Object) -> void:
	_study_shell_and_ceiling(c)
	_desk_pedestals_and_chair(c)
	_colossal_window_and_curtains(c)
	_giant_bookshelves(c)
	_study_fireplace_hearth(c)


## Cavernous timber-panelled study walls (x = +/-16 m, z = -15.5..+14.5 m, floor y = -7.8 m, coffered ceiling
## y = +10.2 m) with an open 12.4 m x 9.4 m window aperture on the left wall for the rainy moonlit sky.
static func _study_shell_and_ceiling(c: Object) -> void:
	var s: RoomMesh = c.s
	var rw := ROOM_X1 - ROOM_X0
	var rd := ROOM_Z1 - ROOM_Z0
	var rh := CEIL_Y - FLOOR_Y
	var rcx := (ROOM_X0 + ROOM_X1) * 0.5
	var rcz := (ROOM_Z0 + ROOM_Z1) * 0.5

	# Dark oak study floor far below the desk edge + muted crimson hearth rug across the right floor.
	s.surface(c.tinted("wood"))
	s.colour = _lin(OAK_FLOOR)
	s.face([
		Vector3(ROOM_X0, FLOOR_Y, ROOM_Z0), Vector3(ROOM_X1, FLOOR_Y, ROOM_Z0),
		Vector3(ROOM_X1, FLOOR_Y, ROOM_Z1), Vector3(ROOM_X0, FLOOR_Y, ROOM_Z1),
	], Vector3.UP)
	s.surface(c.tinted("fabric"))
	s.colour = _lin(Color(0.28, 0.08, 0.09))
	s.face([
		Vector3(4.5, FLOOR_Y + 0.03, 0.5), Vector3(14.5, FLOOR_Y + 0.03, 0.5),
		Vector3(14.5, FLOOR_Y + 0.03, 11.2), Vector3(4.5, FLOOR_Y + 0.03, 11.2),
	], Vector3.UP)

	# Upper dark library green-slate plaster walls (`y = 0.6..10.2 m`) and dark mahogany wainscoting (`y = -7.8..+0.6 m`).
	var dado_y := 0.60
	# Front, right and back walls (solid).
	s.surface(c.tinted("plaster"))
	s.colour = _lin(PLASTER_STUDY)
	s.face([Vector3(ROOM_X0, dado_y, ROOM_Z0), Vector3(ROOM_X1, dado_y, ROOM_Z0),
			Vector3(ROOM_X1, CEIL_Y, ROOM_Z0), Vector3(ROOM_X0, CEIL_Y, ROOM_Z0)], Vector3.BACK)
	s.face([Vector3(ROOM_X1, dado_y, ROOM_Z0), Vector3(ROOM_X1, dado_y, ROOM_Z1),
			Vector3(ROOM_X1, CEIL_Y, ROOM_Z1), Vector3(ROOM_X1, CEIL_Y, ROOM_Z0)], Vector3.LEFT)
	s.face([Vector3(ROOM_X1, dado_y, ROOM_Z1), Vector3(ROOM_X0, dado_y, ROOM_Z1),
			Vector3(ROOM_X0, CEIL_Y, ROOM_Z1), Vector3(ROOM_X1, CEIL_Y, ROOM_Z1)], Vector3.FORWARD)

	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	s.face([Vector3(ROOM_X0, FLOOR_Y, ROOM_Z0), Vector3(ROOM_X1, FLOOR_Y, ROOM_Z0),
			Vector3(ROOM_X1, dado_y, ROOM_Z0), Vector3(ROOM_X0, dado_y, ROOM_Z0)], Vector3.BACK)
	s.face([Vector3(ROOM_X1, FLOOR_Y, ROOM_Z0), Vector3(ROOM_X1, FLOOR_Y, ROOM_Z1),
			Vector3(ROOM_X1, dado_y, ROOM_Z1), Vector3(ROOM_X1, dado_y, ROOM_Z0)], Vector3.LEFT)
	s.face([Vector3(ROOM_X1, FLOOR_Y, ROOM_Z1), Vector3(ROOM_X0, FLOOR_Y, ROOM_Z1),
			Vector3(ROOM_X0, dado_y, ROOM_Z1), Vector3(ROOM_X1, dado_y, ROOM_Z1)], Vector3.FORWARD)

	# Left study wall (`x = -16.0 m`) WITH colossal rectangular window opening cut cleanly via Shapes.wall!
	var hole := Rect2(WIN_Z0 - ROOM_Z0, WIN_Y0 - FLOOR_Y, WIN_Z1 - WIN_Z0, WIN_Y1 - WIN_Y0)
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	Shapes.wall(s, Vector3(ROOM_X0, FLOOR_Y, ROOM_Z0), Vector3.BACK, Vector3.RIGHT, rd, rh, [hole])
	# Raised mahogany wainscot panelling ribs on the solid parts of the left wall beside the window.
	for z_span: Vector2 in [Vector2(ROOM_Z0 + 0.5, WIN_Z0 - 0.6), Vector2(WIN_Z1 + 0.6, ROOM_Z1 - 0.5)]:
		var zl := z_span.y - z_span.x
		var zc := (z_span.x + z_span.y) * 0.5
		s.colour = _lin(MAHOGANY)
		s.box(Vector3(ROOM_X0 + 0.14, dado_y, zc), Vector3(0.28, 0.34, zl), Basis(), [RoomMesh.LEFT])
		s.box(Vector3(ROOM_X0 + 0.08, (FLOOR_Y + dado_y) * 0.5, zc), Vector3(0.16, dado_y - FLOOR_Y - 1.4, zl - 0.9),
				Basis(), [RoomMesh.LEFT])

	# Coffered dark timber ceiling (`y = +10.2 m`) with heavy oak cross-beams & crown cornice!
	s.surface(c.tinted("plaster"))
	s.colour = _lin(CEIL_PLASTER)
	s.face([
		Vector3(ROOM_X0, CEIL_Y, ROOM_Z0), Vector3(ROOM_X1, CEIL_Y, ROOM_Z0),
		Vector3(ROOM_X1, CEIL_Y, ROOM_Z1), Vector3(ROOM_X0, CEIL_Y, ROOM_Z1),
	], Vector3.DOWN)
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	for bz: float in [-11.5, -5.5, 0.5, 6.5, 12.0]:
		s.box(Vector3(rcx, CEIL_Y - 0.38, bz), Vector3(rw, 0.76, 0.65), Basis(), [RoomMesh.UP])
	for bx: float in [-10.0, 0.0, 10.0]:
		s.box(Vector3(bx, CEIL_Y - 0.32, rcz), Vector3(0.58, 0.64, rd), Basis(), [RoomMesh.UP])
	# Crown cornice rails along all four upper wall junctions.
	for sz: float in [ROOM_Z0 + 0.32, ROOM_Z1 - 0.32]:
		s.box(Vector3(rcx, CEIL_Y - 0.35, sz), Vector3(rw, 0.70, 0.64), Basis(), [RoomMesh.UP])
	for sx: float in [ROOM_X0 + 0.32, ROOM_X1 - 0.32]:
		s.box(Vector3(sx, CEIL_Y - 0.35, rcz), Vector3(0.64, 0.70, rd), Basis(), [RoomMesh.UP])


## Massive mahogany pedestal drawer cabinets descending from under the desktop to the study floor (`y = -7.8 m`), plus
## an empty carved mahogany & oxblood-leather Victorian desk chair back rising far behind the desk (`z = +10.4 m`).
static func _desk_pedestals_and_chair(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var ped_h := (DESK_TOP - DESK_THICK) - FLOOR_Y
	var ped_y := FLOOR_Y + ped_h * 0.5

	# Left & right giant desk pedestals descending to the study floor, leaving a central kneehole recess!
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	for side: float in [-1.0, 1.0]:
		var px := side * 8.4
		s.box(Vector3(px, ped_y, -0.5), Vector3(6.2, ped_h, 14.6), Basis(), [RoomMesh.UP, RoomMesh.DOWN])
		# 3 giant recessed drawer fronts facing aft (+Z) with gleaming brass drop-handles!
		s.colour = _lin(MAHOGANY)
		for row in 3:
			var dy := FLOOR_Y + 1.15 + float(row) * 1.95
			s.box(Vector3(px, dy, 6.86), Vector3(5.1, 1.55, 0.14), Basis(), [RoomMesh.FRONT])
			u.surface(brass)
			u.colour = _lin(BRASS)
			for hx: float in [-1.1, 1.1]:
				u.box(Vector3(px + hx, dy, 6.98), Vector3(0.75, 0.14, 0.14))
		s.colour = _lin(MAHOGANY_DARK)

	# Empty carved Victorian mahogany & oxblood-leather desk chair pushed back behind the viewer (`z = +10.4 m`).
	var ch_z := 10.6
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	# Chair seat base down at y = -3.4 m, sculpted curved side uprights rising to a carved crest rail at y = +4.8 m!
	s.box(Vector3(0.0, -3.4, ch_z - 1.1), Vector3(6.8, 0.65, 5.2))
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(sd * 3.1, 0.9, ch_z + 1.1), Vector3(0.58, 8.6, 0.58))
		s.box(Vector3(sd * 3.1, -1.4, ch_z - 1.2), Vector3(0.55, 0.42, 4.8))
	s.box(Vector3(0.0, 5.1, ch_z + 1.1), Vector3(6.8, 0.85, 0.64))
	# Deep oxblood-leather padded chair backrest panel.
	s.surface(c.tinted("cloth"))
	s.colour = _lin(Color(0.24, 0.065, 0.06))
	s.box(Vector3(0.0, 1.0, ch_z + 0.95), Vector3(5.6, 7.2, 0.42))
	# Gleaming brass upholstery tacks edging the chair back.
	u.surface(brass)
	u.colour = _lin(BRASS_DARK)
	for k in 7:
		var tx := lerpf(-2.45, 2.45, float(k) / 6.0)
		Shapes.cylinder(u, Vector3(tx, 4.45, ch_z + 0.72), 0.075, 0.04, 8, Basis(Vector3.RIGHT, PI * 0.5))


## Colossal mullioned leaded-glass study window on the left wall (`x = -16.0`, `z = -8.7..+3.7`, `y = -1.1..+8.3`) with
## central carved mahogany pier, dark leaded iron glazing bars, heavy stone sill, and gathered burgundy velvet curtains.
static func _colossal_window_and_curtains(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var brass := _brass(c)
	var win_w := WIN_Z1 - WIN_Z0
	var win_h := WIN_Y1 - WIN_Y0
	var win_zc := (WIN_Z0 + WIN_Z1) * 0.5
	var win_yc := (WIN_Y0 + WIN_Y1) * 0.5

	# Deep carved mahogany window casing, reveal jambs, lintel header, broad sill ledge & central pier (`z = -2.5`).
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY)
	s.box(Vector3(ROOM_X0 + 0.35, WIN_Y0 - 0.22, win_zc), Vector3(1.50, 0.44, win_w + 1.2))
	s.box(Vector3(ROOM_X0 + 0.25, WIN_Y1 + 0.28, win_zc), Vector3(1.25, 0.56, win_w + 1.2))
	for wz: float in [WIN_Z0 - 0.26, WIN_Z1 + 0.26]:
		s.box(Vector3(ROOM_X0 + 0.25, win_yc, wz), Vector3(1.25, win_h + 0.6, 0.52))
	# Central heavy vertical mullion pier separating the two tall rain-beaded window bays!
	s.box(Vector3(ROOM_X0 + 0.42, win_yc, WIN_PIER_Z), Vector3(0.95, win_h + 0.1, WIN_PIER_W))

	# Dark wrought-iron leaded glazing bars & transoms across both tall window bays (`x = -15.48 m`, just outside
	# weather.panes at x = -15.30 m so rain streaks shimmer across the glass inside the dark leaded grid!).
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	var bar_x := -15.46
	var bays: Array = [[WIN_Z0, WIN_PIER_Z - WIN_PIER_W * 0.5], [WIN_PIER_Z + WIN_PIER_W * 0.5, WIN_Z1]]
	for bay: Array in bays:
		var bz0: float = bay[0]
		var bz1: float = bay[1]
		var bw := bz1 - bz0
		var bzc := (bz0 + bz1) * 0.5
		# 2 vertical slender iron mullions per bay (3 tall leaded lancets per bay).
		for col in [1, 2]:
			var mz := bz0 + bw * float(col) / 3.0
			s.box(Vector3(bar_x, win_yc, mz), Vector3(0.09, win_h, 0.085))
		# 3 horizontal iron transoms per bay.
		for row in [1, 2, 3]:
			var my := WIN_Y0 + win_h * float(row) / 4.0
			s.box(Vector3(bar_x, my, bzc), Vector3(0.09, 0.085, bw))

	# Heavy gathered deep burgundy velvet study curtains drawn cleanly back on both sides of the colossal window!
	var pole_y := WIN_Y1 + 0.90
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.cylinder(u, Vector3(ROOM_X0 + 0.95, pole_y, WIN_Z0 - 2.3), 0.15, win_w + 4.6, 12,
			Basis(Vector3.RIGHT, PI * 0.5))
	for fz: float in [WIN_Z0 - 2.45, WIN_Z1 + 2.45]:
		Shapes.lathe(u, [Vector2(0.15, 0.0), Vector2(0.32, 0.18), Vector2(0.28, 0.36), Vector2(0.0, 0.52)],
				Vector3(ROOM_X0 + 0.95, pole_y, fz), 12, Basis(Vector3.RIGHT, PI * (0.5 if fz > 0.0 else -0.5)))

	# Sculpted deep pleated burgundy curtains flanking the window (`z = -10.5..-8.6` and `z = +3.6..+5.5`).
	s.surface(c.tinted("cloth"))
	for stack: Vector2 in [Vector2(WIN_Z0 - 1.9, WIN_Z0 + 0.05), Vector2(WIN_Z1 - 0.05, WIN_Z1 + 1.9)]:
		var folds := 5
		var n := folds * 4
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		var dz := stack.y - stack.x
		for j in 2:
			var y := FLOOR_Y + 0.1 if j == 0 else pole_y - 0.12
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for k in n + 1:
				var t := float(k) / float(n)
				var z := stack.x + dz * t
				var ph := t * float(folds) * TAU
				var amp := 0.34
				var xo := ROOM_X0 + 0.92 + amp * sin(ph)
				var slope := amp * cos(ph) * float(folds) * TAU / dz
				row.append(Vector3(xo, y, z))
				nrow.append(Vector3(1.0, 0.0, -slope).normalized())
				var lit_f := 0.52 + 0.48 * (0.5 + 0.5 * sin(ph))
				crow.append(_lin(CURTAIN_BURGUNDY * lit_f * (0.75 if j == 0 else 1.0)))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		s.sheet(rows, norms, cols, Vector3(0.0, 0.0, 1.0), Vector3.UP)


## Towering floor-to-ceiling giant mahogany bookshelves lining the front wall (`z = -15.5 m`), back wall (`z = +14.5 m`)
## and right wall flanking the fireplace, packed with rows of giant muted-leather distant book blocks!
static func _giant_bookshelves(c: Object) -> void:
	var s: RoomMesh = c.s
	var rng := RandomNumberGenerator.new()
	rng.seed = 1889
	# [origin, along_axis, into_room_normal, length, bays]
	var cases: Array = [
		[Vector3(-13.8, FLOOR_Y, ROOM_Z0 + 0.05), Vector3.RIGHT, Vector3.BACK, 27.6, 5],
		[Vector3(13.8, FLOOR_Y, ROOM_Z1 - 0.05), Vector3.LEFT, Vector3.FORWARD, 27.6, 5],
		[Vector3(ROOM_X1 - 0.05, FLOOR_Y, -13.6), Vector3.BACK, Vector3.LEFT, 14.4, 3],
		[Vector3(ROOM_X1 - 0.05, FLOOR_Y, 10.4), Vector3.BACK, Vector3.LEFT, 3.6, 1],
	]
	var palette: Array[Color] = [
		BOOK_CRIMSON * 0.72, BOOK_GREEN * 0.74, BOOK_NAVY * 0.74,
		BOOK_TAN * 0.72, BOOK_PLUM * 0.74, BOOK_OCHRE * 0.68,
		MAHOGANY_WARM * 0.78, Color(0.22, 0.24, 0.18),
	]
	var depth := 1.45
	var case_h := 15.2
	var shelves := 7
	var shelf_step := 1.98

	for cs: Array in cases:
		var orig: Vector3 = cs[0]
		var along: Vector3 = cs[1]
		var normal: Vector3 = cs[2]
		var length: float = cs[3]
		var bays: int = cs[4]
		var basis := Basis(along, Vector3.UP, normal)
		var bay_w := length / float(bays)

		s.surface(c.tinted("wood"))
		s.colour = _lin(MAHOGANY_DARK)
		# Top crown cornice & lower wainscot plinth cabinet (y = 0..1.7 m above floor).
		s.box(orig + along * (length * 0.5) + Vector3.UP * (case_h + 0.35) + normal * (depth * 0.58),
				Vector3(length + 0.4, 0.70, depth * 1.16), basis, [RoomMesh.FRONT])
		s.box(orig + along * (length * 0.5) + Vector3.UP * 0.85 + normal * (depth * 0.52),
				Vector3(length, 1.70, depth * 1.04), basis, [RoomMesh.FRONT, RoomMesh.DOWN])

		# Vertical mahogany pilaster uprights framing each bay.
		s.colour = _lin(MAHOGANY)
		for b in bays + 1:
			var bx := float(b) * bay_w
			s.box(orig + along * bx + Vector3.UP * (case_h * 0.5) + normal * (depth * 0.5),
					Vector3(0.34, case_h, depth), basis, [RoomMesh.FRONT])

		# Horizontal shelves & giant packed distant leather book blocks!
		for sh in shelves:
			var sy := 1.70 + float(sh) * shelf_step
			s.surface(c.tinted("wood"))
			s.colour = _lin(MAHOGANY * 0.90)
			s.box(orig + along * (length * 0.5) + Vector3.UP * sy + normal * (depth * 0.5),
					Vector3(length, 0.18, depth), basis, [RoomMesh.FRONT])
			if sh == shelves - 1:
				continue
			# Distant book blocks across each bay (chunky varied-height leather volumes keeping triangles lean!).
			s.surface(c.tinted("cloth"))
			for b in bays:
				var x0 := float(b) * bay_w + 0.24
				var x1 := float(b + 1) * bay_w - 0.24
				var x := x0
				while x < x1 - 0.38:
					var bw := minf(rng.randf_range(0.52, 1.08), x1 - x)
					var bh := rng.randf_range(1.18, 1.78)
					var bd := rng.randf_range(0.82, 1.12)
					var col: Color = palette[rng.randi() % palette.size()] * rng.randf_range(0.84, 1.12)
					s.colour = _lin(col)
					s.box(orig + along * (x + bw * 0.5) + Vector3.UP * (sy + 0.09 + bh * 0.5)
							+ normal * (0.18 + bd * 0.5), Vector3(bw - 0.04, bh, bd), basis,
							[RoomMesh.FRONT, RoomMesh.DOWN])
					x += bw


## Glowing cozy Victorian fireplace hearth across the back-right study wall (`x = +15.9 m, z = +1.4..+9.8 m`), with
## carved mahogany & dark stone chimneypiece, deep brick firebox, cast-iron grate, charred logs, warm glowing embers
## (`PieceWindows`), flickering fire tongues (`PieceLamps`, accent group), and giant brass mantel candlesticks!
static func _study_fireplace_hearth(c: Object) -> void:
	var s: RoomMesh = c.s
	var u: RoomMesh = c.u
	var lit: RoomMesh = c.lit
	var brass := _brass(c)

	var fz := 5.60
	var breast_w := 8.20
	var breast_d := 1.85
	var mantel_y := 3.55
	var open_w := 4.60
	# Raised stone hearth plinth (`hearth_top = -0.38 m`) puts the roaring embers, charred logs and flickering flames
	# (`y = -0.25..+2.35 m`) in glorious clear view right over the mahogany desktop edge from EVERY seat on the desk!
	var hearth_top := -0.38
	var fire_top := 2.85
	var face_x := ROOM_X1 - breast_d

	# Massive mahogany & dark stone chimney breast rising floor-to-ceiling.
	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_DARK)
	# Upper breast above the firebox opening (`y = fire_top..CEIL_Y`).
	s.box(Vector3(ROOM_X1 - breast_d * 0.5, (fire_top + CEIL_Y) * 0.5, fz),
			Vector3(breast_d, CEIL_Y - fire_top, breast_w), Basis(), [RoomMesh.RIGHT])
	# Left & right chimney piers flanking the firebox opening.
	var pier_w := (breast_w - open_w) * 0.5
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(ROOM_X1 - breast_d * 0.5, (FLOOR_Y + fire_top) * 0.5, fz + sd * (open_w * 0.5 + pier_w * 0.5)),
				Vector3(breast_d, fire_top - FLOOR_Y, pier_w), Basis(), [RoomMesh.RIGHT, RoomMesh.DOWN])

	# Raised carved dark stone hearth plinth (`FLOOR_Y..hearth_top`), fire surround & projecting mahogany mantel shelf!
	s.surface(c.tinted("stone"))
	s.colour = _lin(STONE_MANTEL)
	s.box(Vector3(ROOM_X1 - 2.20, (FLOOR_Y + hearth_top) * 0.5, fz),
			Vector3(4.40, hearth_top - FLOOR_Y, breast_w + 1.4), Basis(), [RoomMesh.RIGHT, RoomMesh.DOWN])
	for sd: float in [-1.0, 1.0]:
		s.box(Vector3(face_x - 0.14, (hearth_top + mantel_y) * 0.5, fz + sd * (open_w * 0.5 + 0.42)),
				Vector3(0.45, mantel_y - hearth_top, 0.85))
	s.box(Vector3(face_x - 0.14, (fire_top + mantel_y) * 0.5, fz), Vector3(0.45, mantel_y - fire_top, open_w + 1.7))

	s.surface(c.tinted("wood"))
	s.colour = _lin(MAHOGANY_WARM)
	s.box(Vector3(face_x - 0.42, mantel_y + 0.25, fz), Vector3(1.15, 0.50, breast_w + 0.9))

	# Recessed dark brick firebox back & cheeks.
	s.surface(c.tinted("stone"))
	s.colour = _lin(BRICK_HEARTH)
	s.face([
		Vector3(ROOM_X1 - 0.12, hearth_top, fz - open_w * 0.5),
		Vector3(ROOM_X1 - 0.12, hearth_top, fz + open_w * 0.5),
		Vector3(ROOM_X1 - 0.12, fire_top, fz + open_w * 0.5),
		Vector3(ROOM_X1 - 0.12, fire_top, fz - open_w * 0.5),
	], Vector3.LEFT)

	# Heavy black cast-iron fire basket grate, fender rail & stacked charred fireplace logs.
	s.surface(c.tinted("iron"))
	s.colour = _lin(IRON_DARK)
	var grate_x := ROOM_X1 - 1.15
	for k in 7:
		var gz := fz - 1.50 + float(k) * 0.50
		s.box(Vector3(grate_x - 0.25, hearth_top + 0.62, gz), Vector3(0.14, 1.18, 0.14))
	s.box(Vector3(grate_x - 0.25, hearth_top + 0.26, fz), Vector3(0.18, 0.18, 3.30))
	s.box(Vector3(grate_x - 0.25, hearth_top + 1.05, fz), Vector3(0.18, 0.18, 3.30))
	# Charred logs resting in the grate.
	for log_info: Array in [
			[Vector3(grate_x + 0.25, hearth_top + 0.68, fz - 0.35), 14.0],
			[Vector3(grate_x + 0.20, hearth_top + 0.88, fz + 0.45), -18.0],
			[Vector3(grate_x + 0.35, hearth_top + 1.18, fz + 0.05), 8.0]]:
		var lp: Vector3 = log_info[0]
		Shapes.cylinder(s, lp + Vector3(0.0, 0.0, -1.15), 0.28, 2.30, 8,
				Basis(Vector3.UP, deg_to_rad(float(log_info[1]))) * Basis(Vector3.RIGHT, PI * 0.5))

	# Warm glowing ember hearth bed (`PieceWindows`, accent group -> softens gently during the film!).
	var gw: Array = c.glows.get("window", [])
	gw.append([Vector3(ROOM_X1 - 0.32, hearth_top + 1.48, fz), Vector3(0.0, 0.0, 1.95), Vector3(0.0, 1.38, 0.0),
			Vector3.LEFT])
	gw.append([Vector3(grate_x + 0.22, hearth_top + 0.48, fz), Vector3(0.0, 0.0, 1.55), Vector3(0.55, 0.0, 0.0),
			Vector3.UP])
	c.glows["window"] = gw

	# Flickering warm hearth flame silhouettes (`PieceLamps`, accent group with slow sub-3 Hz flicker!).
	lit.surface(c.kit._lamp(FIRE_EMBER, 1.65, 0.25, "accent", true))
	for fl: Array in [[fz - 0.85, 1.85, 0.72], [fz + 0.05, 2.45, 0.88], [fz + 0.88, 1.72, 0.68]]:
		var fzc: float = fl[0]
		var fh: float = fl[1]
		var fw: float = fl[2]
		lit.face([
			Vector3(grate_x + 0.15, hearth_top + 0.55, fzc - fw),
			Vector3(grate_x + 0.15, hearth_top + 0.55, fzc + fw),
			Vector3(grate_x + 0.15, hearth_top + 0.55 + fh * 0.65, fzc + fw * 0.45),
			Vector3(grate_x + 0.15, hearth_top + 0.55 + fh, fzc),
			Vector3(grate_x + 0.15, hearth_top + 0.55 + fh * 0.65, fzc - fw * 0.45),
		], Vector3.LEFT)
	lit.surface(c.kit._lamp(FIRE_CORE, 2.05, 0.20, "accent", true))
	for fl2: Array in [[fz - 0.30, 1.55, 0.46], [fz + 0.40, 1.38, 0.42]]:
		var fzc2: float = fl2[0]
		var fh2: float = fl2[1]
		var fw2: float = fl2[2]
		lit.face([
			Vector3(grate_x + 0.02, hearth_top + 0.52, fzc2 - fw2),
			Vector3(grate_x + 0.02, hearth_top + 0.52, fzc2 + fw2),
			Vector3(grate_x + 0.02, hearth_top + 0.52 + fh2, fzc2),
		], Vector3.LEFT)

	# Giant gleaming brass candlesticks & overmantel oval brass mirror frame on the mantel (`y = 4.05 m`, zero people!).
	u.surface(brass)
	u.colour = _lin(BRASS)
	for cz: float in [fz - 3.1, fz + 3.1]:
		Shapes.lathe(u, [
			Vector2(0.48, 0.00), Vector2(0.42, 0.18), Vector2(0.16, 0.42),
			Vector2(0.22, 1.05), Vector2(0.14, 1.65), Vector2(0.32, 1.85), Vector2(0.24, 2.02),
		], Vector3(face_x - 0.35, mantel_y + 0.50, cz), 14)
	# Brass overmantel circular mirror frame with dark smoky antique mirror glass plate (pure classical frame, no people).
	Shapes.arch(u, Vector3(face_x - 0.06, mantel_y + 3.15, fz), 1.85, 2.15, 0.18, 24,
			Basis(Vector3.UP, -PI * 0.5), 0.0, TAU, ["front", "inner", "outer"])
	u.surface(_lacquer(c))
	u.colour = _lin(Color(0.08, 0.10, 0.13))
	var mirror_pts: Array = []
	for k in 24:
		var ma := TAU * float(k) / 24.0
		mirror_pts.append(Vector3(face_x - 0.09, mantel_y + 3.15 + sin(ma) * 1.88, fz + cos(ma) * 1.88))
	u.face(mirror_pts, Vector3.LEFT)
	# Gleaming brass hearth fender rail along the stone hearth edge.
	u.surface(brass)
	u.colour = _lin(BRASS)
	Shapes.beam(u, Vector3(face_x - 2.35, hearth_top + 0.42, fz - 3.5),
			Vector3(face_x - 2.35, hearth_top + 0.42, fz + 3.5), Vector2(0.14, 0.14))
	for pz: float in [fz - 3.5, fz, fz + 3.5]:
		Shapes.cylinder(u, Vector3(face_x - 2.35, hearth_top, pz), 0.12, 0.52, 10)
