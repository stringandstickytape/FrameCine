extends RefCounted

## Shopfront 1906's picture house (shopfront.gd with style "edwardian"; docs/environments.md, "Room: Shopfront 1906"),
## made for the deep pass of 2026-11-08 ("continue working on the environments one-by-one like you did with the
## bathysphere, really improving their quality, imagination, delight, detail, lighting and so on", the user). A draper's
## shop of about 1906 turned into a dream for a penny: the builder lays out the hall, its chairs and the sheet as they
## were (the seats and the screen as tuned on the headset); this draws it into the builder's meshes:
##   - the shell: a bare plank floor worn pale down the aisles and by the door, darker by the walls; a dado of dark
##     varnished matchboard with a skirting and a moulded rail; cream pressed tin above it on the walls, a cornice of
##     tin (a bead and reel band, a cove), a ceiling of 2 ft plates in relief round two roses, a border round them; gas
##     soot on the tin above every lamp and over the ceiling's roses
##   - the screen end: the sheet stretched in a gilt frame on a deep red end wall, a little stage with a velvet skirt and
##     a gilt fringe, crimson drapes looped back either side under a pelmet board with the house's name in gilt
##   - the player piano by the stage's left (walnut, a 65-note player of the time: its roll turns behind glass doors and
##     its keys go down as it plays), two candles in brass sconces; the lecturer's lectern on the stage's right with
##     its reading lamp and a pointer
##   - the shop's front behind: the plate glass window with the house's gilt letters (their backs, mirrored), coloured
##     transom lights, curtains looped back; the half-glazed door with its bell on a spring and a portière
##   - the booth: a fireproof box of riveted sheet iron on a timber platform over the door, its lens port and peepholes
##     glowing, a ladder up to it, a fire bucket on its post
##   - gas: three brass brackets a wall with opal globes, two pendants from the ceiling's roses; they waver slowly
##   - bills on the walls (our own: invented pictures, period type), the price board, the hats notice, a drop-dial
##     clock, coat hooks with a bowler and an umbrella
##   - the street through the glass: a gas lamp outside, the wet setts, a confectioner's lit window across the road
## Everything here is ours; the type is the app's own face. No figures: the hats and the coat hang empty.

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const Pictures := preload("res://scripts/env/systems/kit/shopfront_pictures.gd")
const U := preload("res://scripts/env/systems/kit/build_util.gd")
const Builder := preload("res://scripts/env/systems/kit/builder.gd")

## Metres a lightmap texel covers: the big plain surfaces, the joinery and the small parts.
const SHELL_TEXEL := 0.1
const JOINERY_TEXEL := 0.25
## The ceiling's plates (2 ft), the walls' pattern (half a plate), the cornice's band.
const PLATE := 0.61
const WALL_TILE := 0.305
const BEAD_TILE := 0.1
## The plates' field: 7 across (one centred on the hall's axis), 20 along; the roses over plates' middles.
const FIELD_ACROSS := 7
const FIELD_FROM_Z := -6.405
const FIELD_PLATES := 20
const ROSES_Z: Array[float] = [-3.05, 2.44]
## The cornice: its profile out from the wall and up (metres), its foot over the floor.
const CORNICE_FOOT := 3.62
const CORNICE: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.03), Vector2(0.045, 0.04),
		Vector2(0.045, 0.14), Vector2(0.06, 0.15), Vector2(0.1, 0.2), Vector2(0.17, 0.28), Vector2(0.23, 0.36),
		Vector2(0.24, 0.42), Vector2(0.3, 0.46), Vector2(0.3, 0.58)]
## The cornice's bead band: the profile's segment that carries it (index of its lower point).
const CORNICE_BAND := 3
## The sheet: its linen margin round the picture, the gilt frame's width and how far it stands out from the wall.
const MARGIN := 0.08
const FRAME_W := 0.11
const FRAME_OUT := 0.1
## The pelmet board over the sheet: its foot, and how far it stands out.
const PELMET_FOOT := 3.83
const PELMET_OUT := 0.16
## The lamps: their places along each wall (z), the globes' height; the pendants hang this far.
const LAMPS_Z: Array[float] = [-5.75, -1.9, 2.1]
const LAMP_Y := 2.32
const LAMP_OUT := 0.3
const PENDANT_DROP := 0.42
const GAS := Color(1.0, 0.76, 0.48)
## Dark iron as a vertex colour on the dull material (linear: about 0.12 as seen).
const IRON := Color(0.014, 0.014, 0.014)
## Each wall lamp's light for the bake (reach, energy), a pendant's, and their stand-ins' energy before a bake.
const LAMP_REACH := 4.5
const LAMP_LIGHT := 0.4
const PENDANT_LIGHT := 0.3
const STANDIN := 0.55
## The piano: against the left wall in front of the stage, its keyboard to the room (z range, depth, height).
const PIANO_Z := Vector2(-6.08, -4.88)
const PIANO_DEPTH := 0.58
const PIANO_H := 1.32
const KEYS := 65
const KEYBED_Y := 0.7
const KEY_OUT := 0.17
## The first key's MIDI note (a 65-note player: A1 up to C#7).
const LOW_NOTE := 33
## The booth over the door: its platform (x range, depth from the front wall, height), the box (inset), the lens.
const PLATFORM_X := Vector2(-2.8, -0.42)
const PLATFORM_DEPTH := 1.75
const PLATFORM_Y := 2.2
const BOOTH_X := Vector2(-2.75, -1.0)
const BOOTH_H := 1.8
const LENS := Vector3(-1.95, 3.27, 0.0)
## The shop front: the door and the window (x ranges), the stall riser's top, the window's head, the transom's head.
const DOOR_X := Vector2(-2.6, -1.7)
const DOOR_H := 2.02
const WINDOW_X := Vector2(-1.45, 2.6)
const SILL := 0.5
const WINDOW_TOP := 2.5
const TRANSOM_TOP := 3.12
## The street outside: how far the shops opposite stand, our lamp's place (x, metres out), the street's level.
const STREET_DEEP := 11.0
const STREET_Y := -0.12
const STREET_WIDE := 16.0
const LAMP_OUT_H := 3.25
## The window's middle (the street's pictures are centred on it).
static var WINDOW_MID := 0.575


## What the hall is drawn into and what moves in it.
class Hall:
	var n: Node
	var p: Dictionary
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	var hw := 2.8
	var rng := RandomNumberGenerator.new()
	## Baked: the shell's big surfaces (fine texels) and the joinery (coarse); the bills (atlas UVs).
	var shell := RoomMesh.new()
	var joinery := RoomMesh.new()
	var bills := RoomMesh.new()
	## Unbaked: small turned and curved parts (brass, gilt, iron, glass globes' galleries).
	var fittings := RoomMesh.new()
	var mats := {}
	## The bills' faces in the order drawn: [cell name, corners (bl, br, tr, tl)].
	var bill_faces: Array = []
	## Lamps: wall globes by side, the pendants' globes, the booth's ports, the flames' quads by group.
	var globes_l := RoomMesh.new()
	var globes_r := RoomMesh.new()
	var ports := RoomMesh.new()
	var candle_flames: Array = []
	var lamp_flames: Array = []
	## The places of the lamps (for the soot and the bake).
	var lamp_points: Array[Vector3] = []
	var pendant_points: Array[Vector3] = []
	## The piano's keys: [MultiMesh, rest transforms, down now], its roll's material and the scroll.
	var keys_mm: MultiMesh
	var key_rest: Array[Transform3D] = []
	var key_down: Array[bool] = []
	var roll_mat: ShaderMaterial
	var roll_scroll := 0.0
	var street_mat: StandardMaterial3D
	var street_lamps: ShaderMaterial
	## The cart in the street: its node, how far through its pass (seconds of seconds), its legs and wheels.
	var cart: Node3D
	var cart_t := 0.0
	var cart_seconds := 16.0
	## The cart's silhouette (one mesh made again each frame it passes: the body's triangles, the legs about their
	## hips, the wheels about their hubs), its dark material, the first leg's swing now, its lamps' glow.
	var cart_shape: ArrayMesh
	var cart_dark: Material
	var cart_body := PackedVector3Array()
	var cart_wheels: Array = []
	var cart_leg_angle := 0.0
	var cart_glows: Array = []
	## The clock's hands (one mesh, made again as they move) and their angles now (hour, minute; about the wall's
	## normal, 0 at twelve).
	var clock_mesh: ArrayMesh
	var clock_angles := Vector2.ZERO


# --- Building ---------------------------------------------------------------------------------------------------------

static func build(n: Node) -> Hall:
	var h := Hall.new()
	h.n = n
	h.p = n.params
	h.rng.seed = 1906
	var w := float(h.p["width"])
	h.hw = w * 0.5
	h.lo = Vector3(-h.hw, 0.0, float(h.p["screen_wall_z"]))
	h.hi = Vector3(h.hw, float(h.p["height"]), float(h.p["front_z"]))
	WINDOW_MID = (WINDOW_X.x + WINDOW_X.y) * 0.5
	_materials(h)
	h.shell.texel = SHELL_TEXEL
	h.joinery.texel = JOINERY_TEXEL
	h.bills.texel = JOINERY_TEXEL
	for z: float in LAMPS_Z:
		for s: float in [-1.0, 1.0]:
			h.lamp_points.append(Vector3(s * (h.hw - LAMP_OUT), LAMP_Y, z))
	for z: float in ROSES_Z:
		h.pendant_points.append(Vector3(0.0, h.hi.y - PENDANT_DROP, z))
	_floor(h)
	_walls(h)
	_cornice(h)
	_ceiling(h)
	_screen_end(h)
	_front(h)
	_booth(h)
	_lamps(h)
	_piano(h)
	_lectern(h)
	_wall_things(h)
	_street(h)
	_cart(h)
	n._add_static("Shell", h.shell)
	n._add_static("Joinery", h.joinery)
	_commit_bills(h)
	n._add_unbaked("Fittings", h.fittings)
	return h


## The room's materials, from the builder's parameters where it has them (the floor, the dado, the trim, the brass, the
## tin), the rest the hall's own.
static func _materials(h: Hall) -> void:
	var n := h.n
	var L: Node = n._light
	var floor_m: ShaderMaterial = n._mat("floor")
	floor_m.set_shader_parameter("instance_tint", true)
	floor_m.set_shader_parameter("spill", 0.22)
	h.mats["planks"] = floor_m
	var tin_colour := RoomSchemaRef.to_color(h.p["tin"].get("color", "#b0a890"))
	# The screen's light on the room (the film's colour on the tin): enough to read near the sheet, little by the
	# viewer; the ceiling less (it faces away). The user found rooms "overlit"; the film is the star.
	for kind: String in ["ceiling", "wall", "beads"]:
		var m: ShaderMaterial = L.library("smooth_plaster", tin_colour, {"spill": 0.12 if kind == "ceiling" else 0.16})
		Pictures.apply(m, kind, tin_colour, {"ceiling": PLATE, "wall": WALL_TILE, "beads": BEAD_TILE}[kind])
		m.set_shader_parameter("instance_tint", true)
		m.set_shader_parameter("specular", 0.35)
		h.mats["tin_" + kind] = m
	# The ceiling's plates line up with the roses: a plate's middle over the hall's axis and over each rose.
	(h.mats["tin_ceiling"] as ShaderMaterial).set_shader_parameter("uv_offset", Vector2(0.5, 0.5))
	var dado: ShaderMaterial = n._mat("dado")
	Pictures.apply(dado, "matchboard", RoomSchemaRef.to_color(h.p["dado"].get("color", "#47291a")), 0.38)
	dado.set_shader_parameter("specular", 0.7)
	dado.set_shader_parameter("spill", 0.22)
	h.mats["matchboard"] = dado
	var trim: ShaderMaterial = n._mat("trim")
	trim.set_shader_parameter("instance_tint", true)
	trim.set_shader_parameter("spill", 0.25)
	h.mats["wood"] = trim
	var paint: ShaderMaterial = L.library("smooth_plaster", Color(0.36, 0.1, 0.08), {"spill": 0.5})
	paint.set_shader_parameter("instance_tint", true)
	h.mats["paint"] = paint
	# Velvet in its pieces' own colours (the vertex colours: the drapes' crimson, the portiere's green).
	var velvet: ShaderMaterial = L.library("velvet", Color(0.85, 0.85, 0.85), {"spill": 0.45, "tiling": 0.3})
	velvet.set_shader_parameter("instance_tint", true)
	h.mats["velvet"] = velvet
	h.mats["linen"] = L.library("linen", Color(0.86, 0.85, 0.8), {"spill": 1.0, "tiling": 0.4})
	var iron: ShaderMaterial = L.library("smooth_plaster", Color(0.42, 0.44, 0.38), {"spill": 0.3})
	Pictures.apply(iron, "riveted", Color(0.42, 0.44, 0.38), 1.2)
	# The ports' dark reveals and the door in the booth's own iron, darker by vertex colour (a draw fewer).
	iron.set_shader_parameter("instance_tint", true)
	h.mats["booth"] = iron
	# Unbaked parts keep the fill and the stand-in lamps after a bake (the instanced form of a material).
	h.mats["brass"] = L.from_param(h.p["brass"], true)
	h.mats["gilt"] = L.library("brass", Color(0.8, 0.6, 0.28), {"spill": 0.6}, true)
	# The small painted and dyed things (the iron, the fire bucket, the lamp's shade, the bowler, the coat, the pointer,
	# the clock's hands): one material, each its own colour by vertex. One draw for them all (the headset's budget).
	var dull: ShaderMaterial = L.library("smooth_plaster", Color(1, 1, 1), {"spill": 0.5}, true)
	dull.set_shader_parameter("instance_tint", true)
	dull.set_shader_parameter("normal_strength", 0.0)
	h.mats["dull"] = dull
	h.mats["ivory"] = L.library("smooth_plaster", Color(0.9, 0.87, 0.78), {"spill": 0.8}, true)
	(h.mats["ivory"] as ShaderMaterial).set_shader_parameter("instance_tint", true)
	h.mats["wax"] = n._lamp(Color(0.95, 0.86, 0.66), 0.18, 1.0, "house")
	# The bills: the atlas on the mesh's own UVs, matte paper.
	var paper: ShaderMaterial = L.library("smooth_plaster", Color(1, 1, 1), {"spill": 0.2})
	paper.set_shader_parameter("albedo_map", Pictures.bills())
	paper.set_shader_parameter("normal_strength", 0.0)
	paper.set_shader_parameter("orm_map", _orm(0.85))
	paper.set_shader_parameter("tint", Color(1, 1, 1))
	paper.set_shader_parameter("use_mesh_uv", true)
	paper.set_shader_parameter("uv_repeat", Vector2.ONE)
	paper.set_shader_parameter("uv_offset", Vector2.ZERO)
	h.mats["paper"] = paper
	h.shell.surface(floor_m)
	h.joinery.surface(trim)
	h.bills.surface(paper)
	h.fittings.surface(h.mats["brass"])


static var _orms := {}


## A flat packed map: no occlusion, this roughness, no metal.
static func _orm(rough: float) -> Texture2D:
	if _orms.has(rough):
		return _orms[rough]
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, rough, 0.0))
	_orms[rough] = ImageTexture.create_from_image(img)
	return _orms[rough]


static func _lin(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


# --- The shell ----------------------------------------------------------------------------------------------------------

## The floor's wear: pale and greyed down the aisles, before the stage and by the door, dark by the walls and in the
## corners (multiplies the planks' colour).
static func _wear(h: Hall, x: float, z: float) -> Color:
	var aisle := 0.0
	for s: float in [-1.0, 1.0]:
		aisle = maxf(aisle, smoothstep(0.55, 0.15, absf(x - s * 2.33)))
	var front := smoothstep(0.7, 0.1, absf(z - (h.lo.z + float(h.p["stage_depth"]) + 0.45)))
	var door := smoothstep(1.6, 0.3, Vector2(x - (DOOR_X.x + DOOR_X.y) * 0.5, z - h.hi.z + 0.6).length())
	var back := smoothstep(0.9, 0.2, absf(z - (h.hi.z - 1.9))) * smoothstep(-2.6, -0.6, x) * smoothstep(2.6, 1.0, x)
	var worn := clampf(maxf(maxf(aisle * 0.85, front * 0.6), maxf(door, back * 0.7)), 0.0, 1.0)
	var wall := smoothstep(0.35, 0.0, h.hw - absf(x)) + smoothstep(0.3, 0.0, h.hi.z - z) * 0.5
	var blot := Pictures._noise((x + 3.0) / 6.0, (z + 8.0) / 16.0, 6, 16, 33)
	var c := Color(0.78, 0.74, 0.72).lerp(Color(1.0, 0.97, 0.9), worn)
	c = c.darkened(0.35 * clampf(wall, 0.0, 1.0) + 0.12 * blot)
	return _lin(c)


static func _floor(h: Hall) -> void:
	var stage_d := float(h.p["stage_depth"])
	var stage_h := float(h.p["stage_height"])
	var z0 := h.lo.z + stage_d
	var step := 0.25
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	var nz := int(ceil((h.hi.z - z0) / step))
	var nx := int(ceil(h.hw * 2.0 / step))
	for i in nz + 1:
		var z := minf(z0 + i * step, h.hi.z)
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in nx + 1:
			var x := minf(-h.hw + j * step, h.hw)
			row.append(Vector3(x, 0.0, z))
			nr.append(Vector3.UP)
			cr.append(_wear(h, x, z))
		rows.append(row)
		normals.append(nr)
		colours.append(cr)
	h.shell.surface(h.mats["planks"])
	h.shell.sheet(rows, normals, colours, Vector3.RIGHT, Vector3.BACK)
	# The stage: boards on top (a little worn at its lip), its front and its side under a velvet skirt.
	h.shell.colour = _lin(Color(0.86, 0.82, 0.78))
	h.shell.face([Vector3(-h.hw, stage_h, h.lo.z), Vector3(h.hw, stage_h, h.lo.z), Vector3(h.hw, stage_h, z0),
			Vector3(-h.hw, stage_h, z0)], Vector3.UP)
	h.shell.colour = Color.WHITE
	# A nosing along the stage's lip (the joinery's wood).
	h.joinery.surface(h.mats["wood"])
	h.joinery.colour = _lin(Color(0.55, 0.42, 0.32))
	h.joinery.box(Vector3(0.0, stage_h - 0.02, z0 + 0.02), Vector3(h.hw * 2.0, 0.04, 0.05), Basis(), [RoomMesh.DOWN])
	h.joinery.colour = Color.WHITE
	# The skirt: velvet in deep folds from the lip to the floor, a gilt fringe along its top.
	_drape(h, Vector3(-h.hw + 0.04, stage_h - 0.04, z0 + 0.05), Vector3(h.hw - 0.04, stage_h - 0.04, z0 + 0.05),
			stage_h - 0.04, 0.035, 0.09, Color(0.55, 0.1, 0.09))
	var fringe := h.fittings
	fringe.surface(h.mats["gilt"])
	fringe.box(Vector3(0.0, stage_h - 0.06, z0 + 0.1), Vector3(h.hw * 2.0 - 0.08, 0.05, 0.012), Basis(),
			[RoomMesh.BACK, RoomMesh.UP])
	fringe.surface(h.mats["brass"])


## A curtain of velvet hanging from a straight rail (from a to b at its top) down `drop` metres, in folds `depth` deep
## every `pitch` metres, facing `out` (the side it is seen from), in this colour; gather: the folds deepen down it.
static func _drape(h: Hall, a: Vector3, b: Vector3, drop: float, depth: float, pitch: float, colour: Color,
		gather := 0.0, out := Vector3.BACK) -> void:
	var length := a.distance_to(b)
	var along := (b - a).normalized()
	var nx := maxi(int(length / pitch * 4.0), 4)
	var ny := 4
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	for i in ny + 1:
		var y := -drop * float(i) / ny
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in nx + 1:
			var t := float(j) / nx
			var phase := t * length / pitch * TAU
			var d := depth * sin(phase) * (1.0 + gather * float(i) / ny)
			row.append(a + along * t * length + out * d + Vector3(0, y, 0))
			var nn := (out - along * depth * cos(phase) * TAU / pitch).normalized()
			nr.append(nn)
			var shade := 0.82 + 0.18 * (0.5 + 0.5 * sin(phase))
			cr.append(_lin(colour * shade))
		rows.append(row)
		normals.append(nr)
		colours.append(cr)
	h.joinery.surface(h.mats["velvet"])
	h.joinery.sheet(rows, normals, colours, along, Vector3.DOWN)
	h.joinery.surface(h.mats["wood"])


## The soot on the tin: dark over each lamp, rising and spreading, and a haze over the whole ceiling near its roses.
static func _soot(h: Hall, q: Vector3) -> Color:
	var k := 0.0
	var on_ceiling := q.y > h.hi.y - 0.05
	for l: Vector3 in h.lamp_points:
		if signf(q.x) != signf(l.x):
			continue
		if on_ceiling:
			# Over the lamp the soot runs on from the wall's top a little way across the ceiling.
			var d := Vector2(h.hw - absf(q.x), q.z - l.z)
			k += 0.45 * exp(-d.x * d.x / 0.3 - d.y * d.y / 0.35)
			continue
		var up := q.y - l.y - 0.1
		if up > -0.2 and absf(q.x) > h.hw - 0.4:
			var spread := 0.16 + up * 0.22
			var dz := q.z - l.z
			k += 0.9 * exp(-dz * dz / (spread * spread)) * smoothstep(-0.2, 0.15, up) * exp(-maxf(up, 0.0) / 2.2)
	for pp: Vector3 in h.pendant_points:
		var d := Vector2(q.x - pp.x, q.z - pp.z).length()
		if q.y > h.hi.y - 0.05:
			k += 0.6 * exp(-d * d / 0.5)
	var age := Pictures._noise((q.x + q.z * 0.3 + 10.0) / 7.0, (q.y + q.z * 0.7 + 10.0) / 7.0, 7, 7, 51)
	var c := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.55, 0.45), clampf(k, 0.0, 1.0) * 0.8)
	c = c * (0.9 + 0.1 * age)
	# Higher up the tin has yellowed more (the gas, the years).
	c = c.lerp(c * Color(0.92, 0.86, 0.74), smoothstep(1.4, h.hi.y, q.y) * 0.7)
	return _lin(c)


## A flat sheet of the tin from corner o along u and v (lengths lu, lv), facing `nrm`, a vertex every `step` metres,
## each vertex's colour its soot.
static func _tin_sheet(h: Hall, m: Material, o: Vector3, u: Vector3, v: Vector3, lu: float, lv: float, nrm: Vector3,
		step := 0.25) -> void:
	var nu := maxi(int(ceil(lu / step)), 1)
	var nv := maxi(int(ceil(lv / step)), 1)
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	for i in nv + 1:
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in nu + 1:
			var q := o + u * minf(j * step, lu) + v * minf(i * step, lv)
			row.append(q)
			nr.append(nrm)
			cr.append(_soot(h, q))
		rows.append(row)
		normals.append(nr)
		colours.append(cr)
	h.shell.surface(m)
	h.shell.sheet(rows, normals, colours, u, v)


static func _walls(h: Hall) -> void:
	var dado_h := float(h.p["dado_height"])
	var stage_d := float(h.p["stage_depth"])
	var stage_h := float(h.p["stage_height"])
	var top := CORNICE_FOOT
	var z_from := h.lo.z + stage_d
	# Tin above the dado on both side walls (the screen end's stretch above the stage too, behind the drapes).
	for s: float in [-1.0, 1.0]:
		var x := s * h.hw
		var nrm := Vector3(-s, 0, 0)
		_tin_sheet(h, h.mats["tin_wall"], Vector3(x, dado_h, h.lo.z), Vector3(0, 0, 1), Vector3.UP,
				h.hi.z - h.lo.z, top - dado_h, nrm)
		# Behind the stage the tin comes down to the stage's boards.
		_tin_sheet(h, h.mats["tin_wall"], Vector3(x, stage_h, h.lo.z), Vector3(0, 0, 1), Vector3.UP, stage_d,
				dado_h - stage_h, nrm)
	# The dado: matchboard from the floor to the rail on each side wall (from the stage's front to the shop front)
	# and on the front wall under the window's sill and either side of the door.
	h.shell.surface(h.mats["matchboard"])
	for s: float in [-1.0, 1.0]:
		var x := s * (h.hw - 0.012)
		h.shell.face([Vector3(x, 0.0, z_from), Vector3(x, 0.0, h.hi.z), Vector3(x, dado_h, h.hi.z),
				Vector3(x, dado_h, z_from)], Vector3(-s, 0, 0))
		# The stage's side against the wall: the dado's end, cut square.
	# The rail and the skirting (the joinery's wood): a moulded rail on top, a skirting with a rounded top.
	for s: float in [-1.0, 1.0]:
		var x := s * h.hw
		_moulding(h.joinery, h.mats["wood"], [Vector2(0.0, -0.05), Vector2(0.02, -0.05), Vector2(0.03, -0.035),
				Vector2(0.03, 0.0), Vector2(0.045, 0.012), Vector2(0.045, 0.03), Vector2(0.02, 0.045),
				Vector2(0.0, 0.045)], Vector3(x, dado_h, z_from), Vector3(x, dado_h, h.hi.z), Vector3(-s, 0, 0),
				_lin(Color(0.6, 0.45, 0.35)))
		_moulding(h.joinery, h.mats["wood"], [Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.15),
				Vector2(0.018, 0.17), Vector2(0.0, 0.18)], Vector3(x, 0.0, z_from), Vector3(x, 0.0, h.hi.z),
				Vector3(-s, 0, 0), _lin(Color(0.45, 0.33, 0.26)))
	# The end wall: deep red paint, from the stage to the ceiling (the frame, the drapes and the pelmet cover most).
	h.shell.surface(h.mats["paint"])
	h.shell.face([Vector3(-h.hw, stage_h, h.lo.z), Vector3(h.hw, stage_h, h.lo.z), Vector3(h.hw, h.hi.y, h.lo.z),
			Vector3(-h.hw, h.hi.y, h.lo.z)], Vector3.BACK)
	# The front wall above the window and the door, to the cornice; the wall either side of the openings in tin; the
	# dado under the sill and beside the door.
	var fz := h.hi.z
	var nrm_f := Vector3.FORWARD
	_tin_sheet(h, h.mats["tin_wall"], Vector3(h.hw, TRANSOM_TOP, fz), Vector3(-1, 0, 0), Vector3.UP, h.hw * 2.0,
			top - TRANSOM_TOP, nrm_f)
	# Above the door, under the platform (the platform's slab covers the rest).
	_tin_sheet(h, h.mats["tin_wall"], Vector3(WINDOW_X.x, DOOR_H + 0.08, fz), Vector3(-1, 0, 0), Vector3.UP,
			WINDOW_X.x + h.hw, PLATFORM_Y - DOOR_H - 0.08, nrm_f)
	h.shell.surface(h.mats["matchboard"])
	for seg: Vector2 in [Vector2(-h.hw, DOOR_X.x), Vector2(DOOR_X.y, WINDOW_X.x), Vector2(WINDOW_X.y, h.hw)]:
		h.shell.face([Vector3(seg.x, 0.0, fz - 0.012), Vector3(seg.y, 0.0, fz - 0.012), Vector3(seg.y, dado_h,
				fz - 0.012), Vector3(seg.x, dado_h, fz - 0.012)], nrm_f)
	for seg: Vector2 in [Vector2(-h.hw, DOOR_X.x), Vector2(DOOR_X.y, WINDOW_X.x), Vector2(WINDOW_X.y, h.hw)]:
		_tin_sheet(h, h.mats["tin_wall"], Vector3(seg.y, dado_h, fz), Vector3(-1, 0, 0), Vector3.UP, seg.y - seg.x,
				(DOOR_H + 0.08 if seg.x < WINDOW_X.x else TRANSOM_TOP) - dado_h, nrm_f)
	for seg: Vector2 in [Vector2(-h.hw, DOOR_X.x), Vector2(DOOR_X.y, WINDOW_X.x), Vector2(WINDOW_X.y, h.hw)]:
		_moulding(h.joinery, h.mats["wood"], [Vector2(0.0, -0.05), Vector2(0.02, -0.05), Vector2(0.03, -0.035),
				Vector2(0.03, 0.0), Vector2(0.045, 0.012), Vector2(0.045, 0.03), Vector2(0.02, 0.045),
				Vector2(0.0, 0.045)], Vector3(seg.x, dado_h, fz), Vector3(seg.y, dado_h, fz), nrm_f,
				_lin(Color(0.6, 0.45, 0.35)))


## A moulding along a straight run: its profile (out from the wall, up) swept from a to b; each step a face.
static func _moulding(b: RoomMesh, m: Material, profile: Array, a: Vector3, c: Vector3, out: Vector3,
		colour := Color.WHITE) -> void:
	b.surface(m)
	var keep := b.colour
	b.colour = colour
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		if p0.distance_to(p1) < 0.0005:
			continue
		# The profile runs from the wall at its foot, out and up, back to the wall: its outside is to the right.
		var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
		var nrm := (out * n2.x + Vector3.UP * n2.y).normalized()
		b.face([a + out * p0.x + Vector3.UP * p0.y, c + out * p0.x + Vector3.UP * p0.y,
				c + out * p1.x + Vector3.UP * p1.y, a + out * p1.x + Vector3.UP * p1.y], nrm)
	b.colour = keep


## The cornice round the side walls and the front: the profile in tin, its band of bead and reel, mitred at the corners.
static func _cornice(h: Hall) -> void:
	var y := CORNICE_FOOT
	var runs := [
		[Vector3(-h.hw, y, h.lo.z), Vector3(-h.hw, y, h.hi.z), Vector3(1, 0, 0), 0.0, -1.0],
		[Vector3(h.hw, y, h.lo.z), Vector3(h.hw, y, h.hi.z), Vector3(-1, 0, 0), 0.0, -1.0],
		[Vector3(-h.hw, y, h.hi.z), Vector3(h.hw, y, h.hi.z), Vector3(0, 0, -1), -1.0, -1.0],
	]
	for r: Array in runs:
		var a: Vector3 = r[0]
		var c: Vector3 = r[1]
		var out: Vector3 = r[2]
		var along := (c - a).normalized()
		for i in CORNICE.size() - 1:
			var p0: Vector2 = CORNICE[i]
			var p1: Vector2 = CORNICE[i + 1]
			if p0.distance_to(p1) < 0.0005:
				continue
			# Mitres: at the front corners each run ends where the other's profile is (x and z both inset).
			var a0 := a
			var c0 := c
			var a1 := a
			var c1 := c
			if absf(out.x) > 0.5:
				c0 -= along * p0.x
				c1 -= along * p1.x
			else:
				a0 += along * p0.x
				a1 += along * p1.x
				c0 -= along * p0.x
				c1 -= along * p1.x
			var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			var nrm := (out * n2.x + Vector3.UP * n2.y).normalized()
			var m: Material = h.mats["tin_beads"] if i == CORNICE_BAND else h.mats["tin_wall"]
			h.shell.surface(m)
			var q0 := a0 + out * p0.x + Vector3.UP * p0.y
			var q1 := c0 + out * p0.x + Vector3.UP * p0.y
			var q2 := c1 + out * p1.x + Vector3.UP * p1.y
			var q3 := a1 + out * p1.x + Vector3.UP * p1.y
			h.shell.colour = _soot(h, (q0 + q2) * 0.5)
			h.shell.face([q0, q1, q2, q3], nrm)
	h.shell.colour = Color.WHITE


static func _ceiling(h: Hall) -> void:
	var top := h.hi.y
	var inset := CORNICE[-1].x
	var half := FIELD_ACROSS * PLATE * 0.5
	var z0 := FIELD_FROM_Z
	var z1 := FIELD_FROM_Z + FIELD_PLATES * PLATE
	# The field of plates.
	_tin_sheet(h, h.mats["tin_ceiling"], Vector3(-half, top, z0), Vector3(1, 0, 0), Vector3(0, 0, 1), half * 2.0,
			z1 - z0, Vector3.DOWN, PLATE * 0.5)
	# The border round it: the walls' small pattern, from the field to the cornice (to the end wall at the screen).
	var bx := h.hw - inset
	var bz0 := h.lo.z
	var bz1 := h.hi.z - inset
	for s: float in [-1.0, 1.0]:
		var xa := minf(s * half, s * bx)
		var xb := maxf(s * half, s * bx)
		_tin_sheet(h, h.mats["tin_wall"], Vector3(xa, top, bz0), Vector3(1, 0, 0), Vector3(0, 0, 1), xb - xa,
				bz1 - bz0, Vector3.DOWN, 0.3)
	for zz: Vector2 in [Vector2(bz0, z0), Vector2(z1, bz1)]:
		_tin_sheet(h, h.mats["tin_wall"], Vector3(-half, top, zz.x), Vector3(1, 0, 0), Vector3(0, 0, 1), half * 2.0,
				zz.y - zz.x, Vector3.DOWN, 0.3)
	# A moulded rib round the field (a half round of tin).
	var rib := [Vector2(0.0, 0.0), Vector2(0.012, -0.015), Vector2(0.03, -0.022), Vector2(0.048, -0.015),
			Vector2(0.06, 0.0)]
	var corners := [Vector3(-half, top, z0), Vector3(half, top, z0), Vector3(half, top, z1), Vector3(-half, top, z1)]
	for k in 4:
		var a: Vector3 = corners[k]
		var c: Vector3 = corners[(k + 1) % 4]
		var along := (c - a).normalized()
		var across := Vector3.UP.cross(along).normalized()
		for i in rib.size() - 1:
			var p0: Vector2 = rib[i]
			var p1: Vector2 = rib[i + 1]
			var off0 := across * (p0.x - 0.03)
			var off1 := across * (p1.x - 0.03)
			var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			var nrm := (across * n2.x + Vector3.UP * n2.y).normalized()
			if nrm.y > 0.0:
				nrm = -nrm
			h.shell.surface(h.mats["tin_beads"])
			h.shell.colour = _soot(h, a)
			h.shell.face([a + off0 + Vector3.UP * p0.y - along * 0.03, c + off0 + Vector3.UP * p0.y + along * 0.03,
					c + off1 + Vector3.UP * p1.y + along * 0.03, a + off1 + Vector3.UP * p1.y - along * 0.03], nrm)
	h.shell.colour = Color.WHITE
	# The roses: tin turned in rings round each pendant's pipe.
	for pz: float in ROSES_Z:
		var prof := [Vector2(0.0, 0.0), Vector2(0.06, -0.075), Vector2(0.12, -0.055), Vector2(0.16, -0.065),
				Vector2(0.2, -0.04), Vector2(0.26, -0.045), Vector2(0.3, -0.015), Vector2(0.34, 0.0)]
		prof.reverse()
		h.shell.surface(h.mats["tin_beads"])
		h.shell.colour = _soot(h, Vector3(0.0, top, pz))
		Shapes.lathe(h.shell, prof, Vector3(0.0, top, pz), 20)
	h.shell.colour = Color.WHITE


# --- The screen end ----------------------------------------------------------------------------------------------------

static func _screen_end(h: Hall) -> void:
	var sc: Dictionary = h.n.screen()
	var c := U.v3(sc["center"])
	var size := U.v2(sc["size"])
	var wall_z := h.lo.z
	var half := size * 0.5 + Vector2(MARGIN, MARGIN)
	# The sheet's linen margin, just behind the picture, and the sheet's back edge (laced to the frame).
	h.joinery.surface(h.mats["linen"])
	h.joinery.face([Vector3(c.x - half.x, c.y - half.y, c.z - 0.006), Vector3(c.x + half.x, c.y - half.y,
			c.z - 0.006), Vector3(c.x + half.x, c.y + half.y, c.z - 0.006), Vector3(c.x - half.x, c.y + half.y,
			c.z - 0.006)], Vector3.BACK)
	# The gilt frame: an ogee moulding round the sheet, mitred, standing FRAME_OUT from the wall.
	var fz := wall_z + FRAME_OUT
	var prof := [Vector2(0.0, -FRAME_OUT + 0.01), Vector2(0.0, 0.0), Vector2(0.015, 0.006), Vector2(0.035, 0.0),
			Vector2(0.06, -0.012), Vector2(0.085, -0.008), Vector2(FRAME_W - 0.008, -0.03), Vector2(FRAME_W, -0.05),
			Vector2(FRAME_W, -FRAME_OUT + 0.01)]
	var rect := Rect2(Vector2(c.x - half.x, c.y - half.y), half * 2.0)
	var pts := [Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 4]
		var along := (b - a).normalized()
		var outward := Vector2(along.y, -along.x)
		for i in prof.size() - 1:
			var p0: Vector2 = prof[i]
			var p1: Vector2 = prof[i + 1]
			var a0 := a + outward * p0.x - along * p0.x
			var b0 := b + outward * p0.x + along * p0.x
			var a1 := a + outward * p1.x - along * p1.x
			var b1 := b + outward * p1.x + along * p1.x
			var d := Vector2(p1.x - p0.x, p1.y - p0.y)
			# The profile runs up the inner side, across the face, down the outer side: its outside to the left.
			var nrm := (Vector3(outward.x, outward.y, 0.0) * -d.y + Vector3(0, 0, 1) * d.x).normalized()
			h.fittings.surface(h.mats["gilt"])
			h.fittings.face([Vector3(a0.x, a0.y, fz + p0.y), Vector3(b0.x, b0.y, fz + p0.y),
					Vector3(b1.x, b1.y, fz + p1.y), Vector3(a1.x, a1.y, fz + p1.y)], nrm)
	# Corner ornaments: a small boss at each corner of the frame.
	for q: Vector2 in pts:
		var o := q + (q - Vector2(c.x, c.y)).normalized() * 0.055
		Shapes.lathe(h.fittings, [Vector2(0.04, 0.0), Vector2(0.035, 0.015), Vector2(0.018, 0.025), Vector2(0.0, 0.028)],
				Vector3(o.x, o.y, fz + 0.002), 10, Basis(Vector3.RIGHT, PI * 0.5))
	h.fittings.surface(h.mats["brass"])
	# The pelmet board across the top: its painted face is a bill (the name), its edges and soffit wood, gilt beads.
	var top := h.hi.y
	var pz := wall_z + PELMET_OUT
	h.bill_faces.append(["pelmet", [Vector3(-h.hw, PELMET_FOOT, pz), Vector3(h.hw, PELMET_FOOT, pz),
			Vector3(h.hw, top, pz), Vector3(-h.hw, top, pz)]])
	h.joinery.surface(h.mats["wood"])
	h.joinery.colour = _lin(Color(0.4, 0.28, 0.2))
	h.joinery.face([Vector3(-h.hw, PELMET_FOOT, wall_z), Vector3(h.hw, PELMET_FOOT, wall_z), Vector3(h.hw, PELMET_FOOT,
			pz), Vector3(-h.hw, PELMET_FOOT, pz)], Vector3.DOWN)
	h.joinery.box(Vector3(0.0, PELMET_FOOT + 0.012, pz + 0.012), Vector3(h.hw * 2.0, 0.024, 0.024))
	h.joinery.colour = Color.WHITE
	# The drapes: either side of the frame, from under the pelmet to the stage, looped back to the walls.
	var stage_h := float(h.p["stage_height"])
	for s: float in [-1.0, 1.0]:
		_side_drape(h, s, wall_z + 0.06, rect, stage_h)


## A side drape: crimson velvet hanging behind the pelmet from the frame's edge to the wall, caught by a gilt cord at
## the height of a seated head, flaring below it.
static func _side_drape(h: Hall, s: float, z: float, frame: Rect2, floor_y: float) -> void:
	var inner_top := s * (frame.end.x + FRAME_W + 0.02) if s > 0.0 else frame.position.x - FRAME_W - 0.02
	var wall := s * (h.hw - 0.03)
	var tie := 1.55
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	var ny := 12
	var nx := 14
	for i in ny + 1:
		var y := lerpf(PELMET_FOOT + 0.02, floor_y + 0.01, float(i) / ny)
		# How far the inner edge is drawn in to the wall: none at the top, most at the tie, a little flare below.
		var pull := 0.0
		if y > tie:
			pull = (PELMET_FOOT - y) / (PELMET_FOOT - tie)
			pull = pull * pull
		else:
			pull = 1.0 - 0.45 * clampf((tie - y) / (tie - floor_y), 0.0, 1.0)
		var inner := lerpf(inner_top, wall - s * 0.12, pull * 0.85)
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in nx + 1:
			var t := float(j) / nx
			var x := lerpf(wall, inner, t)
			var folds := 2.5 + 2.0 * pull
			var phase := t * folds * TAU
			var depth := 0.03 + 0.05 * pull
			row.append(Vector3(x, y, z + depth * (0.5 + 0.5 * sin(phase))))
			nr.append(Vector3(-sin(phase) * 0.6 * s, 0.0, 1.0).normalized())
			cr.append(_lin(Color(0.5, 0.08, 0.08) * (0.75 + 0.25 * (0.5 + 0.5 * cos(phase)))))
		rows.append(row)
		normals.append(nr)
		colours.append(cr)
	h.joinery.surface(h.mats["velvet"])
	h.joinery.sheet(rows, normals, colours, Vector3(-s, 0, 0), Vector3.DOWN)
	h.joinery.surface(h.mats["wood"])
	# The tie-back: a gilt cord round the gathered drape, a tassel below it, a hook in the wall.
	var at := Vector3(wall - s * 0.1, tie, z + 0.09)
	h.fittings.surface(h.mats["gilt"])
	Shapes.lathe(h.fittings, [Vector2(0.0, -0.17), Vector2(0.03, -0.15), Vector2(0.035, -0.08), Vector2(0.015, -0.05),
			Vector2(0.012, 0.0)], at + Vector3(0, -0.02, 0), 8)
	Shapes.beam(h.fittings, at + Vector3(-s * 0.09, 0.0, -0.02), at + Vector3(s * 0.09, 0.0, -0.06),
			Vector2(0.018, 0.018))
	h.fittings.surface(h.mats["brass"])


# --- The shop's front -------------------------------------------------------------------------------------------------

static func _front(h: Hall) -> void:
	var fz := h.hi.z
	var wood: Material = h.mats["wood"]
	h.joinery.surface(wood)
	var frame_c := _lin(Color(0.5, 0.36, 0.26))
	h.joinery.colour = frame_c
	# The window: its frame (jambs, a head, the transom's bar), two mullions, the stall riser's panels, a deep sill.
	var depth := 0.12
	var zf := fz - depth * 0.5
	for x: float in [WINDOW_X.x, WINDOW_X.y]:
		h.joinery.box(Vector3(x, (SILL + TRANSOM_TOP) * 0.5, zf), Vector3(0.1, TRANSOM_TOP - SILL, depth))
	h.joinery.box(Vector3(WINDOW_MID, WINDOW_TOP + 0.05, zf), Vector3(WINDOW_X.y - WINDOW_X.x, 0.1, depth))
	h.joinery.box(Vector3(WINDOW_MID, TRANSOM_TOP + 0.04, zf), Vector3(WINDOW_X.y - WINDOW_X.x + 0.1, 0.08, depth))
	for k in 2:
		var x := lerpf(WINDOW_X.x, WINDOW_X.y, (k + 1) / 3.0)
		h.joinery.box(Vector3(x, (SILL + WINDOW_TOP) * 0.5, fz - 0.03), Vector3(0.045, WINDOW_TOP - SILL, 0.05))
	for k in 4:
		var x := lerpf(WINDOW_X.x, WINDOW_X.y, (k + 1) / 5.0)
		h.joinery.box(Vector3(x, (WINDOW_TOP + TRANSOM_TOP) * 0.5, fz - 0.03), Vector3(0.035,
				TRANSOM_TOP - WINDOW_TOP, 0.04))
	h.joinery.box(Vector3(WINDOW_MID, SILL - 0.02, fz - 0.16), Vector3(WINDOW_X.y - WINDOW_X.x + 0.16, 0.04, 0.34))
	# The stall riser: boarded, two fielded panels.
	h.joinery.colour = _lin(Color(0.42, 0.3, 0.22))
	h.joinery.face([Vector3(WINDOW_X.x, 0.0, fz - 0.33), Vector3(WINDOW_X.y, 0.0, fz - 0.33), Vector3(WINDOW_X.y,
			SILL - 0.04, fz - 0.33), Vector3(WINDOW_X.x, SILL - 0.04, fz - 0.33)], Vector3.FORWARD)
	for k in 3:
		var x0 := lerpf(WINDOW_X.x, WINDOW_X.y, k / 3.0) + 0.1
		var x1 := lerpf(WINDOW_X.x, WINDOW_X.y, (k + 1) / 3.0) - 0.1
		h.joinery.box(Vector3((x0 + x1) * 0.5, 0.26, fz - 0.345), Vector3(x1 - x0, 0.26, 0.03), Basis(),
				[RoomMesh.BACK])
	h.joinery.colour = Color.WHITE
	# The glass: the plate, the door's light, the transom's lights (a coloured tulip in each, faintly).
	var glass := RoomMesh.new()
	glass.surface(Builder.GLASS)
	Shapes.quad(glass, Vector3(WINDOW_MID, (SILL + WINDOW_TOP) * 0.5, fz - 0.02), Vector3((WINDOW_X.y - WINDOW_X.x)
			* 0.5, 0, 0), Vector3(0, (WINDOW_TOP - SILL) * 0.5, 0), Vector3.FORWARD)
	Shapes.quad(glass, Vector3(WINDOW_MID, (WINDOW_TOP + TRANSOM_TOP) * 0.5 + 0.03, fz - 0.02),
			Vector3((WINDOW_X.y - WINDOW_X.x) * 0.5, 0, 0), Vector3(0, (TRANSOM_TOP - WINDOW_TOP) * 0.5 - 0.05, 0),
			Vector3.FORWARD)
	var door_mid := (DOOR_X.x + DOOR_X.y) * 0.5
	Shapes.quad(glass, Vector3(door_mid, 1.47, fz - 0.03), Vector3((DOOR_X.y - DOOR_X.x) * 0.5 - 0.1, 0, 0),
			Vector3(0, 0.45, 0), Vector3.FORWARD)
	h.n._add_glass("Window", glass, Color(0.55, 0.62, 0.6), 0.07)
	# The door: its frame, the leaf (panels under, a light over), the knob, the bell on its spring.
	h.joinery.surface(wood)
	h.joinery.colour = frame_c
	for x: float in [DOOR_X.x, DOOR_X.y]:
		h.joinery.box(Vector3(x, DOOR_H * 0.5, zf), Vector3(0.08, DOOR_H, depth))
	h.joinery.box(Vector3(door_mid, DOOR_H + 0.04, zf), Vector3(DOOR_X.y - DOOR_X.x + 0.08, 0.08, depth))
	h.joinery.colour = _lin(Color(0.45, 0.32, 0.24))
	var leaf_z := fz - 0.05
	var dw := DOOR_X.y - DOOR_X.x - 0.08
	h.joinery.box(Vector3(door_mid, 0.5, leaf_z), Vector3(dw, 1.0, 0.045))
	for side_x: float in [-1.0, 1.0]:
		h.joinery.box(Vector3(door_mid + side_x * (dw * 0.5 - 0.05), 1.47, leaf_z), Vector3(0.1, 0.94, 0.045))
	h.joinery.box(Vector3(door_mid, 1.96, leaf_z), Vector3(dw, 0.1, 0.045))
	h.joinery.box(Vector3(door_mid, 1.47, leaf_z), Vector3(dw, 0.04, 0.035))
	for k in 2:
		h.joinery.box(Vector3(door_mid + (k - 0.5) * dw * 0.48, 0.5, leaf_z - 0.025), Vector3(dw * 0.36, 0.7,
				0.012), Basis(), [RoomMesh.BACK])
	h.joinery.colour = Color.WHITE
	h.fittings.surface(h.mats["brass"])
	Shapes.lathe(h.fittings, [Vector2(0.0, 0.0), Vector2(0.012, 0.0), Vector2(0.01, 0.04), Vector2(0.028, 0.06),
			Vector2(0.028, 0.08), Vector2(0.0, 0.09)], Vector3(DOOR_X.y - 0.12, 1.0, leaf_z - 0.022), 10,
			Basis(Vector3.RIGHT, -PI * 0.5))
	# The bell: a spring of brass strip curling from the frame's head, the bell hanging from it.
	var bell := Vector3(DOOR_X.y - 0.2, DOOR_H - 0.05, fz - 0.25)
	Shapes.beam(h.fittings, Vector3(bell.x, DOOR_H + 0.06, fz - 0.07), Vector3(bell.x, DOOR_H + 0.03, bell.z + 0.05),
			Vector2(0.012, 0.004))
	for k in 6:
		var a0 := k * PI / 3.0
		var a1 := (k + 1) * PI / 3.0
		var r := 0.035 - k * 0.003
		Shapes.beam(h.fittings, bell + Vector3(0, 0.06 + r * sin(a0), r * cos(a0)), bell + Vector3(0, 0.06 + r * sin(a1),
				r * cos(a1)), Vector2(0.01, 0.004))
	Shapes.lathe(h.fittings, [Vector2(0.0, -0.05), Vector2(0.045, -0.05), Vector2(0.04, -0.035), Vector2(0.028, 0.0),
			Vector2(0.018, 0.02), Vector2(0.0, 0.03)], bell, 12)
	# The portière: green velvet on a brass rod across the door, drawn back to the wall's side.
	var rod_y := DOOR_H + 0.14
	Shapes.cylinder(h.fittings, Vector3(-h.hw + 0.02, rod_y, fz - 0.2), 0.012, DOOR_X.y + 0.12 + h.hw - 0.02, 8,
			Basis(Vector3.BACK, -PI * 0.5), false)
	for x: float in [-h.hw + 0.06, DOOR_X.y + 0.12]:
		h.fittings.box(Vector3(x, rod_y, fz - 0.11), Vector3(0.02, 0.02, 0.18))
		Shapes.lathe(h.fittings, [Vector2(0.0, -0.025), Vector2(0.024, -0.01), Vector2(0.024, 0.01), Vector2(0.0, 0.025)],
				Vector3(x + (0.03 if x > 0.0 or x > -2.0 else -0.03), rod_y, fz - 0.2), 8, Basis(Vector3.BACK, PI * 0.5))
	_drape(h, Vector3(-h.hw + 0.04, rod_y - 0.02, fz - 0.2), Vector3(DOOR_X.x + 0.18, rod_y - 0.02, fz - 0.2),
			rod_y - 0.03, 0.06, 0.12, Color(0.14, 0.27, 0.18), 0.4, Vector3.FORWARD)
	# The window's curtains, looped back either side under a pelmet rail.
	var crod := TRANSOM_TOP + 0.16
	Shapes.cylinder(h.fittings, Vector3(WINDOW_X.x - 0.1, crod, fz - 0.24), 0.012, WINDOW_X.y - WINDOW_X.x + 0.2, 8,
			Basis(Vector3.BACK, -PI * 0.5), false)
	for s: float in [-1.0, 1.0]:
		var edge := WINDOW_X.x if s < 0.0 else WINDOW_X.y
		var inner := edge - s * 0.42
		var outer := edge + s * 0.06
		_window_curtain(h, outer, inner, crod - 0.02, fz - 0.24, s)
	# The lettering on the glass: the backs of the gilt letters, from inside.
	_lettering(h, fz - 0.026)


## A window curtain from the rod to the sill, caught back to its side at the sill's height and a little over.
static func _window_curtain(h: Hall, outer: float, inner: float, top: float, z: float, s: float) -> void:
	var tie := 1.25
	var rows: Array = []
	var normals: Array = []
	var colours: Array = []
	var ny := 10
	var nx := 10
	for i in ny + 1:
		var y := lerpf(top, SILL + 0.02, float(i) / ny)
		var pull := 0.0
		if y > tie:
			pull = pow((top - y) / (top - tie), 2.0)
		else:
			pull = 1.0 - 0.5 * (tie - y) / (tie - SILL)
		var inner_x := lerpf(inner, outer - s * -0.18, pull * 0.8)
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in nx + 1:
			var t := float(j) / nx
			var x := lerpf(outer, inner_x, t)
			var phase := t * (2.0 + 1.5 * pull) * TAU
			row.append(Vector3(x, y, z - (0.03 + 0.04 * pull) * (0.5 + 0.5 * sin(phase))))
			nr.append(Vector3(sin(phase) * 0.5 * s, 0.0, -1.0).normalized())
			cr.append(_lin(Color(0.14, 0.27, 0.18) * (0.75 + 0.25 * (0.5 + 0.5 * cos(phase)))))
		rows.append(row)
		normals.append(nr)
		colours.append(cr)
	h.joinery.surface(h.mats["velvet"])
	h.joinery.sheet(rows, normals, colours, Vector3(-s, 0, 0), Vector3.DOWN)
	h.joinery.surface(h.mats["wood"])


static func _lettering(h: Hall, z: float) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_texture = Pictures.lettering()
	m.albedo_color = Color(0.85, 0.8, 0.75)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var w := WINDOW_X.y - WINDOW_X.x - 0.3
	var hh := w * float(Pictures.LETTERING_SIZE.y) / Pictures.LETTERING_SIZE.x
	var c := Vector3(WINDOW_MID, WINDOW_TOP - 0.08 - hh * 0.5, z)
	var mi := _quads_mesh(h, "Lettering", [[c, Vector3(w * 0.5, 0, 0), Vector3(0, hh * 0.5, 0), Rect2(1, 0, -1, 1)]],
			Vector3.FORWARD, m)
	mi.add_to_group(Builder.SEE_THROUGH)


## Quads with their own UVs in one mesh: [centre, half across, half up, uv rect] each, facing `normal`.
static func _quads_mesh(h: Hall, node_name: String, quads: Array, normal: Vector3, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in quads:
		var c: Vector3 = q[0]
		var u: Vector3 = q[1]
		var v: Vector3 = q[2]
		var r: Rect2 = q[3]
		var nrm: Vector3 = q[4] if q.size() > 4 else normal
		var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
		var uvs := [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y),
				r.position]
		var order := [0, 1, 2, 0, 2, 3]
		if (corners[2] - corners[0]).cross(corners[1] - corners[0]).dot(nrm) < 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			st.set_normal(nrm)
			st.set_uv(uvs[k])
			st.add_vertex(corners[k])
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var mi: MeshInstance3D = h.n._add_mesh(node_name, mesh)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


# --- The booth --------------------------------------------------------------------------------------------------------

static func _booth(h: Hall) -> void:
	var fz := h.hi.z
	var pz := fz - PLATFORM_DEPTH
	var wood: Material = h.mats["wood"]
	h.joinery.surface(wood)
	var timber := _lin(Color(0.5, 0.38, 0.28))
	h.joinery.colour = timber
	# The platform: a boarded slab on joists, a post and its braces at the open corner, a handrail beside the door.
	h.joinery.box(Vector3((PLATFORM_X.x + PLATFORM_X.y) * 0.5, PLATFORM_Y + 0.06, (pz + fz) * 0.5),
			Vector3(PLATFORM_X.y - PLATFORM_X.x, 0.12, PLATFORM_DEPTH))
	for k in 4:
		var z := lerpf(pz + 0.06, fz - 0.1, k / 3.0)
		h.joinery.box(Vector3((PLATFORM_X.x + PLATFORM_X.y) * 0.5, PLATFORM_Y - 0.07, z), Vector3(PLATFORM_X.y
				- PLATFORM_X.x, 0.14, 0.07), Basis(), [RoomMesh.UP])
	var post := Vector3(PLATFORM_X.y - 0.05, 0.0, pz + 0.05)
	h.joinery.box(post + Vector3(0, PLATFORM_Y * 0.5, 0), Vector3(0.1, PLATFORM_Y, 0.1))
	h.joinery.box(post + Vector3(0, 0.03, 0), Vector3(0.14, 0.06, 0.14))
	Shapes.beam(h.joinery, post + Vector3(-0.04, PLATFORM_Y - 0.55, 0.0), post + Vector3(-0.5, PLATFORM_Y - 0.14, 0.0),
			Vector2(0.06, 0.06), Vector3.BACK)
	Shapes.beam(h.joinery, post + Vector3(0.0, PLATFORM_Y - 0.55, 0.04), post + Vector3(0.0, PLATFORM_Y - 0.14, 0.5),
			Vector2(0.06, 0.06), Vector3.RIGHT)
	# The landing's rail: the post carried up, a rail along the open side.
	h.joinery.box(post + Vector3(0, PLATFORM_Y + 0.12 + 0.45, 0), Vector3(0.07, 0.9, 0.07))
	h.joinery.box(Vector3(post.x, PLATFORM_Y + 1.02, (pz + fz) * 0.5), Vector3(0.06, 0.06, PLATFORM_DEPTH))
	h.joinery.box(Vector3(post.x, PLATFORM_Y + 0.6, (pz + fz) * 0.5), Vector3(0.04, 0.04, PLATFORM_DEPTH))
	# The box: riveted sheet iron, a flat roof, its door on the landing's side.
	var y0 := PLATFORM_Y + 0.12
	var y1 := y0 + BOOTH_H
	var bz0 := pz + 0.1
	var bz1 := fz - 0.04
	h.joinery.surface(h.mats["booth"])
	h.joinery.colour = Color.WHITE
	var front := [Rect2(LENS.x - BOOTH_X.x - 0.1, LENS.y - y0 - 0.08, 0.2, 0.16)]
	for px: float in [-0.38, 0.38]:
		front.append(Rect2(LENS.x + px - BOOTH_X.x - 0.06, LENS.y - y0 + 0.02, 0.12, 0.08))
	Shapes.wall(h.joinery, Vector3(BOOTH_X.x, y0, bz0), Vector3.RIGHT, Vector3.FORWARD, BOOTH_X.y - BOOTH_X.x, BOOTH_H,
			front)
	Shapes.wall(h.joinery, Vector3(BOOTH_X.y, y0, bz0), Vector3.BACK, Vector3.RIGHT, bz1 - bz0, BOOTH_H, [])
	h.joinery.face([Vector3(BOOTH_X.x, y1, bz0), Vector3(BOOTH_X.y, y1, bz0), Vector3(BOOTH_X.y, y1, bz1),
			Vector3(BOOTH_X.x, y1, bz1)], Vector3.UP)
	# The ports' reveals (dark inside), their shutters raised over them in their guides.
	h.joinery.colour = _lin(Color(0.1, 0.1, 0.1))
	for r: Rect2 in front:
		var c := Vector3(BOOTH_X.x + r.get_center().x, y0 + r.get_center().y, bz0)
		h.joinery.box(c + Vector3(0, 0, 0.04), Vector3(r.size.x, r.size.y, 0.08), Basis(), [RoomMesh.FRONT,
				RoomMesh.BACK], true)
		h.joinery.box(c + Vector3(0, r.size.y + 0.03, -0.012), Vector3(r.size.x + 0.04, r.size.y + 0.02, 0.008))
		for s: float in [-1.0, 1.0]:
			h.joinery.box(c + Vector3(s * (r.size.x * 0.5 + 0.03), r.size.y * 0.6, -0.015), Vector3(0.012,
					r.size.y * 2.6, 0.014))
	# The door on its side, a vent's louvres high on it.
	h.joinery.colour = _lin(Color(0.62, 0.62, 0.6))
	h.joinery.box(Vector3(BOOTH_X.y + 0.012, y0 + 0.85, (bz0 + bz1) * 0.5 - 0.15), Vector3(0.02, 1.62, 0.6), Basis(),
			[RoomMesh.LEFT])
	for k in 5:
		h.joinery.box(Vector3(BOOTH_X.y + 0.02, y1 - 0.12 - k * 0.04, (bz0 + bz1) * 0.5 + 0.45), Vector3(0.03, 0.012,
				0.4), Basis(Vector3.BACK, 0.4))
	# The lens's tube in its port, the ports' glow (the lamp house beyond: brighter at the lens).
	h.fittings.surface(h.mats["brass"])
	Shapes.cylinder(h.fittings, Vector3(LENS.x, LENS.y, bz0 + 0.02), 0.045, 0.08, 12, Basis(Vector3.RIGHT, -PI * 0.5))
	var port_glow: ShaderMaterial = h.n._lamp(Color(1.0, 0.86, 0.62), 0.9, 0.0, "booth")
	port_glow.set_shader_parameter("use_vertex_colour", true)
	h.ports.surface(port_glow)
	Shapes.quad(h.ports, Vector3(LENS.x, LENS.y, bz0 + 0.07), Vector3(0.1, 0, 0), Vector3(0, 0.08, 0), Vector3.FORWARD)
	# The peepholes dimmer (the lamp house is by the lens): the same draw, darker by vertex colour.
	h.ports.colour = Color(0.28, 0.24, 0.19)
	for px: float in [-0.38, 0.38]:
		Shapes.quad(h.ports, Vector3(LENS.x + px, LENS.y + 0.06, bz0 + 0.07), Vector3(0.06, 0, 0), Vector3(0, 0.04, 0),
				Vector3.FORWARD)
	h.ports.colour = Color.WHITE
	h.n._add_lamps("BoothPorts", h.ports)
	_spot(h, "BoothPort", Vector3(LENS.x, LENS.y, bz0 - 0.03), Vector3(0.0, 1.0, bz0 - 4.0), 40.0, 4.0, 0.12,
			Color(1.0, 0.86, 0.62))
	# The ladder up to the landing, leaning on the platform's edge.
	h.joinery.surface(wood)
	h.joinery.colour = timber
	var foot_z := pz - 0.62
	var lx := PLATFORM_X.y - 0.3
	for s: float in [-1.0, 1.0]:
		Shapes.beam(h.joinery, Vector3(lx + s * 0.2, 0.0, foot_z), Vector3(lx + s * 0.2, PLATFORM_Y + 0.85, pz + 0.12),
				Vector2(0.05, 0.07), Vector3.BACK)
	for k in 8:
		var t := (k + 1) / 9.0 * PLATFORM_Y / (PLATFORM_Y + 0.85)
		var a := Vector3(lx - 0.2, t * (PLATFORM_Y + 0.85), lerpf(foot_z, pz + 0.12, t))
		Shapes.beam(h.joinery, a, a + Vector3(0.4, 0, 0), Vector2(0.035, 0.035))
	h.joinery.colour = Color.WHITE
	# The fire bucket on its hook on the post: red, sand in it.
	var bucket := post + Vector3(0.0, 1.35, -0.12)
	h.fittings.surface(h.mats["dull"])
	h.fittings.colour = IRON
	h.fittings.box(post + Vector3(0, 1.62, -0.06), Vector3(0.015, 0.015, 0.08))
	h.fittings.colour = _lin(Color(0.62, 0.08, 0.05))
	Shapes.lathe(h.fittings, [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.13, 0.24), Vector2(0.12, 0.24),
			Vector2(0.09, 0.02)], bucket, 14)
	h.fittings.colour = IRON
	Shapes.arch(h.fittings, bucket + Vector3(0, 0.24, 0), 0.12, 0.13, 0.008, 8)
	h.fittings.colour = Color.WHITE
	h.fittings.surface(h.mats["brass"])


# --- Gas -----------------------------------------------------------------------------------------------------------------

static func _lamps(h: Hall) -> void:
	var light: Node = h.n._light
	var cone := cos(deg_to_rad(float(light.params["lamp_cone_deg"])))
	# The globes glow at the house lamps' level alone (follows_house 0): turned low in the film they still show a
	# little warm light, as gas does, rather than going grey with the room's light.
	var globe_l: ShaderMaterial = h.n._lamp(GAS, 1.5, 0.0, "house", true)
	var globe_r: ShaderMaterial = h.n._lamp(GAS, 1.5, 0.0, "house", true)
	for m: ShaderMaterial in [globe_l, globe_r]:
		m.set_shader_parameter("rim", 0.8)
	# The pendants' globes in the left wall's draw (flickering with it), a little dimmer by vertex colour.
	globe_l.set_shader_parameter("use_vertex_colour", true)
	h.globes_l.surface(globe_l)
	h.globes_r.surface(globe_r)
	var i := 0
	for at: Vector3 in h.lamp_points:
		var s := signf(at.x)
		var wall := Vector3(s * h.hw, at.y, at.z)
		# The bracket: a back plate, an arm out and up in a swan neck, the gas cock, a gallery holding the globe.
		h.fittings.surface(h.mats["brass"])
		Shapes.lathe(h.fittings, [Vector2(0.06, 0.0), Vector2(0.055, 0.012), Vector2(0.03, 0.02), Vector2(0.015, 0.03)],
				wall + Vector3(0, -0.2, 0), 12, Basis(Vector3.BACK, s * PI * 0.5))
		var arm := [wall + Vector3(-s * 0.02, -0.2, 0), wall + Vector3(-s * 0.12, -0.22, 0),
				wall + Vector3(-s * 0.22, -0.2, 0), wall + Vector3(-s * 0.28, -0.14, 0), at + Vector3(0, -0.11, 0)]
		for k in arm.size() - 1:
			Shapes.beam(h.fittings, arm[k], arm[k + 1], Vector2(0.018, 0.018))
		h.fittings.box(wall + Vector3(-s * 0.15, -0.19, 0), Vector3(0.02, 0.05, 0.02))
		Shapes.beam(h.fittings, wall + Vector3(-s * 0.15, -0.17, 0), wall + Vector3(-s * 0.15, -0.14, 0.05),
				Vector2(0.008, 0.008))
		Shapes.lathe(h.fittings, [Vector2(0.015, -0.12), Vector2(0.045, -0.1), Vector2(0.055, -0.075),
				Vector2(0.04, -0.07)], at, 12)
		# The globe: opal glass, a tulip open at the top.
		var g: RoomMesh = h.globes_l if s < 0.0 else h.globes_r
		Shapes.lathe(g, [Vector2(0.03, -0.075), Vector2(0.07, -0.04), Vector2(0.085, 0.02), Vector2(0.075, 0.08),
				Vector2(0.06, 0.11), Vector2(0.065, 0.13)], at, 14)
		light.add_lamp(at, GAS * STANDIN * float(light.params["lamp_energy"]) / 2.6, cone)
		h.n._bake_omni("Gas%d" % i, at + Vector3(0, 0.02, 0), LAMP_REACH, LAMP_LIGHT, GAS)
		i += 1
	# The pendants from the roses: a pipe, a crossbar, two inverted mantles in globes.
	for k in h.pendant_points.size():
		var pp: Vector3 = h.pendant_points[k]
		var top := h.hi.y
		h.fittings.surface(h.mats["brass"])
		Shapes.cylinder(h.fittings, Vector3(0.0, pp.y + 0.12, pp.z), 0.012, top - pp.y - 0.12, 8, Basis(), false)
		Shapes.lathe(h.fittings, [Vector2(0.0, -0.02), Vector2(0.03, -0.01), Vector2(0.035, 0.02), Vector2(0.0, 0.04)],
				Vector3(0.0, pp.y + 0.12, pp.z), 10)
		Shapes.beam(h.fittings, Vector3(-0.24, pp.y + 0.12, pp.z), Vector3(0.24, pp.y + 0.12, pp.z),
				Vector2(0.018, 0.018))
		for s: float in [-1.0, 1.0]:
			var g := Vector3(s * 0.24, pp.y, pp.z)
			Shapes.lathe(h.fittings, [Vector2(0.012, 0.12), Vector2(0.04, 0.1), Vector2(0.05, 0.08), Vector2(0.0, 0.075)],
					g, 10)
			h.globes_l.colour = Color(0.87, 0.87, 0.87)
			Shapes.lathe(h.globes_l, [Vector2(0.0, -0.06), Vector2(0.04, -0.055), Vector2(0.065, -0.02),
					Vector2(0.07, 0.03), Vector2(0.05, 0.075)], g, 14)
			h.globes_l.colour = Color.WHITE
		light.add_lamp(pp, GAS * STANDIN * 1.2 * float(light.params["lamp_energy"]) / 2.6, cone)
		h.n._bake_omni("Pendant%d" % k, pp, LAMP_REACH + 0.5, PENDANT_LIGHT, GAS)
	h.n._add_lamps("GasLamps", h.globes_l)
	h.n._add_lamps("GasLampsRight", h.globes_r)


# --- The piano --------------------------------------------------------------------------------------------------------

## The piano's frame: x from the left wall into the room (its front at depth), y up, z along it.
static func _piano_at(h: Hall, x: float, y: float, z: float) -> Vector3:
	return Vector3(-h.hw + 0.035 + x, y, z)


static func _piano(h: Hall) -> void:
	var walnut := _lin(Color(0.5, 0.32, 0.22))
	var dark := _lin(Color(0.3, 0.19, 0.13))
	var d := PIANO_DEPTH
	var z0 := PIANO_Z.x
	var z1 := PIANO_Z.y
	var zm := (z0 + z1) * 0.5
	var lz := z1 - z0
	var b := h.joinery
	b.surface(h.mats["wood"])
	b.colour = walnut
	# The case: plinth, the lower front, the keybed with its cheeks, the upper front round the spool box, the top.
	b.box(_piano_at(h, d * 0.5, 0.05, zm), Vector3(d + 0.02, 0.1, lz + 0.02))
	b.box(_piano_at(h, (d - 0.22) * 0.5, 0.4, zm), Vector3(d - 0.22, 0.6, lz))
	b.box(_piano_at(h, d - 0.21, 0.4, zm), Vector3(0.02, 0.6, lz - 0.08), Basis(), [RoomMesh.LEFT])
	b.colour = dark
	for k in 2:
		var pz := lerpf(z0 + 0.12, z1 - 0.12, (k + 0.5) / 2.0)
		b.box(_piano_at(h, d - 0.195, 0.4, pz), Vector3(0.012, 0.42, lz * 0.5 - 0.2), Basis(), [RoomMesh.LEFT])
	b.colour = walnut
	b.box(_piano_at(h, (d + KEY_OUT) * 0.5, KEYBED_Y - 0.03, zm), Vector3(d + KEY_OUT, 0.06, lz))
	b.box(_piano_at(h, d + KEY_OUT - 0.012, KEYBED_Y + 0.0, zm), Vector3(0.024, 0.05, lz - 0.12), Basis(),
			[RoomMesh.LEFT])
	for s: float in [-1.0, 1.0]:
		var cz := zm + s * (lz * 0.5 - 0.04)
		b.box(_piano_at(h, (d + KEY_OUT) * 0.5, KEYBED_Y + 0.04, cz), Vector3(d + KEY_OUT, 0.1, 0.08))
		# The consoles under the cheeks: scrolled brackets down to the plinth.
		b.box(_piano_at(h, d + 0.02, 0.38, cz), Vector3(0.12, 0.56, 0.06))
		Shapes.lathe(b, [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.05, 0.03), Vector2(0.035, 0.06),
				Vector2(0.0, 0.065)], _piano_at(h, d + 0.07, 0.62, cz), 8, Basis(Vector3.BACK, -PI * 0.5))
	# The fallboard (open, folded back) and the name board behind the keys.
	b.box(_piano_at(h, d - 0.2, KEYBED_Y + 0.1, zm), Vector3(0.04, 0.12, lz - 0.16))
	b.box(_piano_at(h, (d - 0.2) * 0.5, 0.98, zm), Vector3(d - 0.2, 0.5, lz))
	b.box(_piano_at(h, (d - 0.17) * 0.5, PIANO_H - 0.02, zm), Vector3(d - 0.17, 0.04, lz + 0.04))
	for s: float in [-1.0, 1.0]:
		b.box(_piano_at(h, (d - 0.2) * 0.5 + 0.01, (PIANO_H - 0.04 + KEYBED_Y) * 0.5, zm + s * (lz * 0.5 - 0.015)),
				Vector3(d - 0.18, PIANO_H - 0.04 - KEYBED_Y, 0.03))
	# The upper front: panels either side of the spool box's glass doors, a moulding over them.
	var spool := Rect2(zm - 0.2, 0.84, 0.4, 0.3)
	b.colour = walnut
	for s: float in [-1.0, 1.0]:
		var w := (lz - spool.size.x) * 0.5 - 0.02
		var pz := zm + s * (spool.size.x * 0.5 + w * 0.5 + 0.01)
		b.box(_piano_at(h, d - 0.21, 0.98, pz), Vector3(0.02, 0.44, w))
		b.colour = dark
		b.box(_piano_at(h, d - 0.198, 0.98, pz), Vector3(0.008, 0.3, w - 0.1), Basis(), [RoomMesh.LEFT])
		b.colour = walnut
	b.box(_piano_at(h, d - 0.205, 1.215, zm), Vector3(0.035, 0.03, lz))
	b.box(_piano_at(h, d - 0.205, 0.76, zm), Vector3(0.035, 0.03, lz))
	# The spool box: its back (dark), the doors' frames; the roll's paper between the spools (its own mesh, scrolling).
	b.colour = dark
	b.box(_piano_at(h, d - 0.29, spool.get_center().y, zm), Vector3(0.02, spool.size.y, spool.size.x))
	b.colour = walnut
	for s: float in [-1.0, 1.0]:
		b.box(_piano_at(h, d - 0.205, spool.get_center().y, zm + s * (spool.size.x * 0.5 + 0.015)), Vector3(0.03,
				spool.size.y + 0.04, 0.03))
	b.box(_piano_at(h, d - 0.205, spool.get_center().y, zm), Vector3(0.025, spool.size.y, 0.02))
	b.colour = Color.WHITE
	# The spools and the tracker bar (brass), the roll's paper.
	h.fittings.surface(h.mats["brass"])
	for sy: float in [spool.position.y + 0.04, spool.end.y - 0.045]:
		Shapes.cylinder(h.fittings, _piano_at(h, d - 0.25, sy, spool.position.x - 0.01), 0.022, spool.size.x + 0.02, 10,
				Basis(Vector3.RIGHT, PI * 0.5), true)
	h.fittings.box(_piano_at(h, d - 0.245, spool.get_center().y - 0.02, zm), Vector3(0.02, 0.025, spool.size.x - 0.04))
	var roll := RoomMesh.new()
	var rm: ShaderMaterial = h.n._light.library("smooth_plaster", Color(1, 1, 1), {"spill": 0.8}, true)
	rm.set_shader_parameter("albedo_map", Pictures.roll())
	rm.set_shader_parameter("normal_strength", 0.0)
	rm.set_shader_parameter("orm_map", _orm(0.9))
	rm.set_shader_parameter("tint", Color(1, 1, 1))
	rm.set_shader_parameter("use_mesh_uv", true)
	rm.set_shader_parameter("uv_repeat", Vector2(1.0 / 0.29, 1.0 / 1.16))
	h.roll_mat = rm
	roll.surface(rm)
	var rx := d - 0.255
	roll.face([_piano_at(h, rx, spool.end.y - 0.02, spool.position.x + 0.05), _piano_at(h, rx, spool.end.y - 0.02,
			spool.end.x - 0.05), _piano_at(h, rx, spool.position.y + 0.02, spool.end.x - 0.05), _piano_at(h, rx,
			spool.position.y + 0.02, spool.position.x + 0.05)], Vector3.RIGHT)
	h.n._add_unbaked("PianoRoll", roll)
	# The pedals: two brass pedals under the keybed.
	h.fittings.surface(h.mats["brass"])
	for s: float in [-1.0, 1.0]:
		h.fittings.box(_piano_at(h, d + 0.02, 0.07, zm + s * 0.08), Vector3(0.13, 0.015, 0.035))
	# The candle sconces: a brass arm swung out from each side of the upper front, a drip pan, a candle, its flame.
	var wax := RoomMesh.new()
	wax.surface(h.mats["wax"])
	for s: float in [-1.0, 1.0]:
		var base := _piano_at(h, d - 0.2, 1.08, zm + s * (lz * 0.5 - 0.1))
		var cup := base + Vector3(0.16, 0.02, s * 0.05)
		h.fittings.surface(h.mats["brass"])
		Shapes.lathe(h.fittings, [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.02, 0.01), Vector2(0.0, 0.015)],
				base, 8, Basis(Vector3.BACK, -PI * 0.5))
		Shapes.beam(h.fittings, base + Vector3(0.01, 0, 0), cup + Vector3(0, -0.02, 0), Vector2(0.012, 0.012))
		Shapes.lathe(h.fittings, [Vector2(0.0, -0.025), Vector2(0.045, -0.02), Vector2(0.05, -0.012), Vector2(0.02, -0.01),
				Vector2(0.015, 0.0)], cup, 12)
		Shapes.cylinder(wax, cup, 0.011, 0.13, 8, Basis(), true)
		var flame := cup + Vector3(0, 0.155, 0)
		h.candle_flames.append([flame + Vector3(0, 0, 0), Vector3(0.0, 0.0, 0.018), Vector3(0, 0.03, 0),
				Vector3.RIGHT])
		h.candle_flames.append([flame, Vector3(0.018, 0.0, 0.0), Vector3(0, 0.03, 0), Vector3.BACK])
		h.n._bake_omni("Candle%d" % int(s + 1.0), flame, 2.5, 0.12, Color(1.0, 0.7, 0.4))
	h.n._add_lamps("CandleWax", wax)
	h.n._add_glow("CandleFlames", h.candle_flames, Procedural.flame(), Color(1.0, 0.75, 0.42), 1.6, "house", true)
	# The keys: one MultiMesh, white and black by the instance's colour; each goes down as its note sounds.
	_keys(h, zm)
	# Roll boxes on the top: three lying, one standing.
	var top := PIANO_H
	b.surface(h.mats["wood"])
	b.colour = _lin(Color(0.62, 0.5, 0.36))
	for k in 3:
		var bz := z0 + 0.25 + k * 0.075
		b.box(_piano_at(h, (d - 0.2) * 0.5, top + 0.035, bz), Vector3(0.32, 0.07, 0.07))
	b.colour = Color.WHITE


static func _keys(h: Hall, zm: float) -> void:
	var span := 0.88
	var whites := 0
	for k in KEYS:
		if not _is_black(LOW_NOTE + k):
			whites += 1
	var ww := span / whites
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = h.mats["ivory"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = KEYS
	var wi := 0
	for k in KEYS:
		var black := _is_black(LOW_NOTE + k)
		var z: float
		var xf: Transform3D
		if black:
			z = zm + span * 0.5 - wi * ww
			xf = Transform3D(Basis().scaled(Vector3(0.09, 0.022, ww * 0.55)), _piano_at(h, PIANO_DEPTH + KEY_OUT - 0.105,
					KEYBED_Y + 0.047, z))
			mm.set_instance_color(k, Color(0.06, 0.05, 0.05))
		else:
			z = zm + span * 0.5 - (wi + 0.5) * ww
			xf = Transform3D(Basis().scaled(Vector3(0.15, 0.02, ww - 0.0015)), _piano_at(h,
					PIANO_DEPTH + KEY_OUT - 0.075, KEYBED_Y + 0.03, z))
			mm.set_instance_color(k, Color(1, 1, 1))
			wi += 1
		mm.set_instance_transform(k, xf)
		h.key_rest.append(xf)
		h.key_down.append(false)
	var mi := MultiMeshInstance3D.new()
	mi.name = "PianoKeys"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_meta("env_placed", h.key_rest.duplicate())
	h.n.own(mi)
	h.keys_mm = mm


static func _is_black(midi: int) -> bool:
	return (midi % 12) in [1, 3, 6, 8, 10]


## The keys as the piano plays: down while their notes sound (a key tips 3 degrees round its back), the roll scrolling
## at the tempo's pace while it plays.
static func animate(h: Hall, delta: float, notes: Array, playing: bool) -> void:
	if h.keys_mm != null:
		var want: Array[bool] = []
		want.resize(KEYS)
		want.fill(false)
		for m: int in notes:
			var k := m - LOW_NOTE
			while k < 0:
				k += 12
			while k >= KEYS:
				k -= 12
			want[k] = true
		for k in KEYS:
			if want[k] != h.key_down[k]:
				h.key_down[k] = want[k]
				var xf := h.key_rest[k]
				if want[k]:
					var pivot := xf.origin + Vector3(-xf.basis.x.length() * 0.5, 0, 0)
					var turn := Transform3D(Basis(Vector3.BACK, -deg_to_rad(3.0)), Vector3.ZERO)
					xf = Transform3D(Basis(), pivot) * turn * Transform3D(Basis(), -pivot) * xf
				h.keys_mm.set_instance_transform(k, xf)
	if h.roll_mat != null and playing:
		h.roll_scroll = fposmod(h.roll_scroll + delta * 0.035 / 1.16, 1.0)
		h.roll_mat.set_shader_parameter("uv_offset", Vector2(0.0, -h.roll_scroll))


# --- The lectern ------------------------------------------------------------------------------------------------------

static func _lectern(h: Hall) -> void:
	var stage_h := float(h.p["stage_height"])
	var at := Vector3(h.hw - 0.32, stage_h, h.lo.z + 0.9)
	var b := h.joinery
	b.surface(h.mats["wood"])
	b.colour = _lin(Color(0.5, 0.32, 0.22))
	# A foot, a turned column, the sloping desk with a ledge, a shelf under it.
	b.box(at + Vector3(0, 0.03, 0), Vector3(0.4, 0.06, 0.36))
	Shapes.lathe(b, [Vector2(0.05, 0.06), Vector2(0.04, 0.12), Vector2(0.03, 0.15), Vector2(0.03, 0.85),
			Vector2(0.045, 0.9), Vector2(0.03, 0.95)], at, 10)
	var desk := Basis(Vector3.BACK, deg_to_rad(28.0))
	b.box(at + Vector3(-0.02, 1.05, 0), Vector3(0.36, 0.03, 0.48), desk)
	b.box(at + Vector3(-0.17, 0.97, 0), Vector3(0.025, 0.05, 0.48), desk)
	b.box(at + Vector3(0.03, 0.97, 0), Vector3(0.24, 0.12, 0.42))
	b.colour = Color.WHITE
	# Papers on the desk (the lecturer's notes: blank), the pointer leaning on it.
	b.surface(h.mats["linen"])
	b.box(at + Vector3(-0.025, 1.071, 0.02), Vector3(0.26, 0.004, 0.2), desk)
	b.box(at + Vector3(-0.02, 1.075, -0.03), Vector3(0.25, 0.004, 0.19), desk * Basis(Vector3.UP, 0.08))
	h.fittings.surface(h.mats["dull"])
	h.fittings.colour = _lin(Color(0.36, 0.24, 0.15))
	Shapes.beam(h.fittings, at + Vector3(-0.15, 0.0, -0.3), at + Vector3(-0.2, 1.3, -0.14), Vector2(0.014, 0.014))
	h.fittings.colour = Color.WHITE
	# The reading lamp: a brass stem, a green shade, its glow under it (the house's group: it goes down with the gas).
	h.fittings.surface(h.mats["brass"])
	var lamp := at + Vector3(0.08, 1.04, -0.18)
	Shapes.lathe(h.fittings, [Vector2(0.05, 0.0), Vector2(0.045, 0.015), Vector2(0.008, 0.02), Vector2(0.008, 0.26),
			Vector2(0.0, 0.27)], lamp, 10)
	h.fittings.surface(h.mats["dull"])
	h.fittings.colour = _lin(Color(0.12, 0.3, 0.14))
	Shapes.lathe(h.fittings, [Vector2(0.11, 0.18), Vector2(0.1, 0.2), Vector2(0.06, 0.26), Vector2(0.025, 0.28)],
			lamp, 14)
	h.fittings.colour = Color.WHITE
	h.fittings.surface(h.mats["brass"])
	var glow := RoomMesh.new()
	glow.surface(h.n._lamp(Color(1.0, 0.85, 0.6), 1.0, 1.0, "house"))
	glow.face([lamp + Vector3(-0.09, 0.181, -0.09), lamp + Vector3(0.09, 0.181, -0.09), lamp + Vector3(0.09, 0.181, 0.09),
			lamp + Vector3(-0.09, 0.181, 0.09)], Vector3.DOWN)
	h.n._add_lamps("LecternLamp", glow)
	h.n._bake_spot("LecternLight", lamp + Vector3(0, 0.17, 0), true, 50.0, 1.6, 0.6, Color(1.0, 0.85, 0.6))


# --- On the walls ---------------------------------------------------------------------------------------------------

## A bill on a wall: its face for the atlas, a thin dark frame (framed) or four brass tacks (pasted).
static func _bill(h: Hall, cell: String, s: float, z: float, y: float, size: Vector2, framed: bool) -> void:
	var x := s * (h.hw - (0.03 if framed else 0.006))
	var a := Vector3(x, y - size.y * 0.5, z - s * size.x * 0.5)
	var b := Vector3(x, y - size.y * 0.5, z + s * size.x * 0.5)
	h.bill_faces.append([cell, [a, b, b + Vector3(0, size.y, 0), a + Vector3(0, size.y, 0)]])
	if framed:
		h.joinery.surface(h.mats["wood"])
		h.joinery.colour = _lin(Color(0.18, 0.12, 0.09))
		var fw := 0.035
		var cx := s * (h.hw - 0.02)
		for k: float in [-1.0, 1.0]:
			h.joinery.box(Vector3(cx, y + k * (size.y + fw) * 0.5, z), Vector3(0.04, fw, size.x + fw * 2.0))
			h.joinery.box(Vector3(cx, y, z + k * (size.x + fw) * 0.5), Vector3(0.04, size.y, fw))
		h.joinery.colour = Color.WHITE
	else:
		h.fittings.surface(h.mats["brass"])
		for cu: float in [-1.0, 1.0]:
			for cv: float in [-1.0, 1.0]:
				Shapes.lathe(h.fittings, [Vector2(0.0, 0.0), Vector2(0.009, 0.0), Vector2(0.007, 0.004),
						Vector2(0.0, 0.006)], Vector3(x - s * 0.002, y + cv * (size.y * 0.5 - 0.02), z + cu
						* (size.x * 0.5 - 0.02)), 6, Basis(Vector3.BACK, s * PI * 0.5))


static func _wall_things(h: Hall) -> void:
	var bill := Vector2(0.5, 0.75)
	_bill(h, "kettle", -1.0, -3.9, 1.7, bill, false)
	_bill(h, "express", -1.0, 0.1, 1.72, bill, true)
	_bill(h, "programme", -1.0, 4.1, 1.7, bill * 0.9, false)
	_bill(h, "arctic", 1.0, -3.9, 1.66, bill, true)
	_bill(h, "perambulator", 1.0, 0.1, 1.72, bill, false)
	_bill(h, "inn", 1.0, 4.1, 1.7, bill * 0.9, false)
	_bill(h, "hats", 1.0, -3.9, 2.5, Vector2(0.84, 0.28), true)
	_bill(h, "prices", 1.0, 5.6, 1.85, Vector2(0.9, 0.6), true)
	# The drop-dial clock over the first bill on the left: a round case, its face (a bill's cell), the drop below,
	# its hands.
	var cz := -3.9
	var cy := 2.68
	var cx := -h.hw + 0.06
	h.joinery.surface(h.mats["wood"])
	h.joinery.colour = _lin(Color(0.4, 0.25, 0.15))
	Shapes.cylinder(h.joinery, Vector3(-h.hw, cy, cz), 0.2, 0.08, 18, Basis(Vector3.BACK, -PI * 0.5), true)
	h.joinery.box(Vector3(-h.hw + 0.035, cy - 0.28, cz), Vector3(0.07, 0.3, 0.26))
	h.joinery.colour = Color.WHITE
	h.bill_faces.append(["clock", [Vector3(cx + 0.026, cy - 0.17, cz + 0.17), Vector3(cx + 0.026, cy - 0.17, cz - 0.17),
			Vector3(cx + 0.026, cy + 0.17, cz - 0.17), Vector3(cx + 0.026, cy + 0.17, cz + 0.17)]])
	h.fittings.surface(h.mats["brass"])
	Shapes.lathe(h.fittings, [Vector2(0.19, 0.0), Vector2(0.2, 0.01), Vector2(0.175, 0.025), Vector2(0.165, 0.012)],
			Vector3(cx + 0.02, cy, cz), 24, Basis(Vector3.BACK, -PI * 0.5))
	_clock_hands(h, Vector3(cx + 0.034, cy, cz))
	# Coat hooks under the booth's platform: a board of brass hooks, a bowler on one, a coat and an umbrella.
	var hz0 := h.hi.z - PLATFORM_DEPTH + 0.35
	var hz1 := h.hi.z - 0.2
	h.joinery.surface(h.mats["wood"])
	h.joinery.colour = _lin(Color(0.45, 0.3, 0.2))
	h.joinery.box(Vector3(-h.hw + 0.015, 1.72, (hz0 + hz1) * 0.5), Vector3(0.03, 0.1, hz1 - hz0))
	h.joinery.colour = Color.WHITE
	h.fittings.surface(h.mats["brass"])
	var hooks: Array[Vector3] = []
	for k in 4:
		var z := lerpf(hz0 + 0.12, hz1 - 0.12, k / 3.0)
		var at := Vector3(-h.hw + 0.03, 1.72, z)
		Shapes.beam(h.fittings, at, at + Vector3(0.09, 0.05, 0), Vector2(0.012, 0.012))
		Shapes.beam(h.fittings, at + Vector3(0.0, -0.01, 0), at + Vector3(0.07, -0.05, 0), Vector2(0.01, 0.01))
		hooks.append(at + Vector3(0.09, 0.05, 0))
	# A hat shelf over the hooks on brackets, a bowler on it.
	h.joinery.surface(h.mats["wood"])
	h.joinery.colour = _lin(Color(0.45, 0.3, 0.2))
	h.joinery.box(Vector3(-h.hw + 0.13, 1.98, (hz0 + hz1) * 0.5), Vector3(0.26, 0.025, hz1 - hz0))
	for z: float in [hz0 + 0.05, hz1 - 0.05]:
		Shapes.beam(h.joinery, Vector3(-h.hw + 0.01, 1.8, z), Vector3(-h.hw + 0.22, 1.965, z), Vector2(0.025, 0.03))
	h.joinery.colour = Color.WHITE
	h.fittings.surface(h.mats["dull"])
	h.fittings.colour = _lin(Color(0.12, 0.11, 0.1))
	var hat := Vector3(-h.hw + 0.17, 1.993, hooks[1].z + 0.05)
	Shapes.lathe(h.fittings, [Vector2(0.0, 0.0), Vector2(0.15, 0.0), Vector2(0.155, 0.01), Vector2(0.15, 0.018),
			Vector2(0.1, 0.022), Vector2(0.098, 0.07), Vector2(0.085, 0.115), Vector2(0.05, 0.135), Vector2(0.0, 0.14)],
			hat, 16)
	# The coat: a heavy overcoat hanging from the third hook, its shoulders and its fall.
	var coat_top := hooks[2] + Vector3(0.05, -0.04, 0)
	var coat_rows: Array = []
	var coat_n: Array = []
	var coat_c: Array = []
	for i in 7:
		var t := float(i) / 6.0
		var y := coat_top.y - t * 1.05
		var half := lerpf(0.06, 0.24, minf(t * 3.0, 1.0)) + 0.03 * t
		var row := PackedVector3Array()
		var nr := PackedVector3Array()
		var cr := PackedColorArray()
		for j in 9:
			var a := lerpf(-PI * 0.9, PI * 0.9, j / 8.0)
			row.append(Vector3(-h.hw + 0.05 + (0.06 + 0.1 * minf(t * 3.0, 1.0)) * (1.0 + cos(a)) * 0.5 + 0.02 * sin(j
					* 1.7 + i), y, coat_top.z + half * sin(a)))
			nr.append(Vector3(cos(a), 0.0, sin(a)).normalized())
			cr.append(_lin(Color(0.19, 0.17, 0.145) * (0.8 + 0.2 * cos(a * 3.0))))
		coat_rows.append(row)
		coat_n.append(nr)
		coat_c.append(cr)
	h.fittings.grid(coat_rows, coat_n, coat_c)
	# The umbrella: furled, its handle on the last hook.
	h.fittings.colour = IRON
	var um := hooks[3] + Vector3(0.0, 0.02, 0)
	Shapes.arch(h.fittings, um + Vector3(0.0, -0.03, 0), 0.025, 0.035, 0.012, 6, Basis(Vector3.UP, PI * 0.5), 0.0, PI)
	Shapes.lathe(h.fittings, [Vector2(0.0, -0.95), Vector2(0.008, -0.9), Vector2(0.035, -0.55), Vector2(0.03, -0.2),
			Vector2(0.008, -0.08), Vector2(0.008, -0.03)], um + Vector3(0.035, 0.0, 0), 8)
	h.fittings.colour = Color.WHITE
	h.fittings.surface(h.mats["brass"])


static func _clock_hands(h: Hall, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "ClockHands"
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	h.clock_mesh = ArrayMesh.new()
	mi.mesh = h.clock_mesh
	h.n.own(mi)
	set_clock(h, 10.0, 10.0)


## The clock's hands at the time of day (the room's clock keeps the viewer's own time): two flat hands in the wall's
## plane (facing +x), the minute's a hair in front, one mesh made again (a few vertices, once a second).
static func set_clock(h: Hall, hours: float, minutes: float) -> void:
	if h.clock_mesh == null:
		return
	h.clock_angles = Vector2(-fposmod(hours + minutes / 60.0, 12.0) / 12.0 * TAU, -fposmod(minutes, 60.0) / 60.0 * TAU)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in 2:
		var length := 0.11 if k == 0 else 0.15
		var width := 0.012 if k == 0 else 0.007
		var turn := Basis(Vector3.RIGHT, h.clock_angles[k])
		var x := 0.002 * k
		var base := verts.size()
		for c: Vector3 in [Vector3(x, -0.02, -width), Vector3(x, length, -width * 0.4), Vector3(x, length, width * 0.4),
				Vector3(x, -0.02, width)]:
			verts.append(turn * c)
		for i: int in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
			idx.append(base + i)
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for v in verts.size():
		normals.append(Vector3.RIGHT)
		colours.append(IRON)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = idx
	h.clock_mesh.clear_surfaces()
	h.clock_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	h.clock_mesh.surface_set_material(0, h.mats["dull"])


## The bills' mesh: each face's UVs set to its cell of the atlas (RoomMesh gives a face its own metres; the atlas
## needs 0..1 within the cell). Baked like the walls they hang on.
static func _commit_bills(h: Hall) -> void:
	var paper: Material = h.mats["paper"]
	h.bills.surface(paper)
	for f: Array in h.bill_faces:
		var c: Array = f[1]
		var nrm := ((c[1] as Vector3) - (c[0] as Vector3)).cross((c[3] as Vector3) - (c[0] as Vector3)).normalized()
		h.bills.face(c, nrm)
	var mi: MeshInstance3D = h.n._add_static("Bills", h.bills)
	if mi == null:
		return
	var mesh := mi.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var corner_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in h.bill_faces.size():
		var r := Pictures.uv_rect(Pictures.BILL_RECTS[h.bill_faces[k][0]], Pictures.BILLS_SIZE)
		for v in 4:
			uvs[k * 4 + v] = r.position + corner_uv[v] * r.size
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var hint := mesh.lightmap_size_hint
	var fresh := ArrayMesh.new()
	fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	fresh.surface_set_material(0, paper)
	fresh.lightmap_size_hint = hint
	mi.mesh = fresh


# --- The street ------------------------------------------------------------------------------------------------------

static func _street(h: Hall) -> void:
	var fz := h.hi.z
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = Pictures.street()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	h.street_mat = m
	set_street(h, float(h.p["street_glow"]))
	var atlas := Pictures.STREET_SIZE
	var mid := WINDOW_MID
	var fw := Pictures.FACADE_M
	var gm := Pictures.GROUND_M
	var quads := [
		[Vector3(mid, STREET_Y + fw.y * 0.5, fz + STREET_DEEP), Vector3(-fw.x * 0.5, 0, 0), Vector3(0, fw.y * 0.5, 0),
				Pictures.uv_rect(Pictures.STREET_RECTS["facade"], atlas), Vector3.FORWARD],
		[Vector3(mid, STREET_Y, fz + gm.y * 0.5), Vector3(-gm.x * 0.5, 0, 0), Vector3(0, 0, gm.y * 0.5),
				Pictures.uv_rect(Pictures.STREET_RECTS["ground"], atlas), Vector3.UP],
		[Vector3(mid, STREET_Y + fw.y + 4.0, fz + STREET_DEEP + 0.5), Vector3(-fw.x, 0, 0), Vector3(0, 4.0, 0),
				Pictures.uv_rect(Pictures.STREET_RECTS["sky"], atlas), Vector3.FORWARD],
	]
	_quads_mesh(h, "Street", quads, Vector3.FORWARD, m)
	# Our lamp outside the window: its post and lantern (dark iron) and the lantern's glowing panes.
	# (The pictures are drawn as seen from the street's side: their x runs the other way to the room's.)
	var lamp := Vector3(mid - Pictures.LAMP_OURS.x, STREET_Y, fz + Pictures.LAMP_OURS.y)
	var post := RoomMesh.new()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.02, 0.02, 0.02)
	iron.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.surface(iron)
	Shapes.lathe(post, [Vector2(0.11, 0.0), Vector2(0.1, 0.4), Vector2(0.06, 0.5), Vector2(0.05, LAMP_OUT_H - 0.3),
			Vector2(0.07, LAMP_OUT_H - 0.25), Vector2(0.0, LAMP_OUT_H - 0.24)], lamp, 10)
	Shapes.beam(post, lamp + Vector3(-0.3, LAMP_OUT_H - 0.45, 0), lamp + Vector3(0.3, LAMP_OUT_H - 0.45, 0),
			Vector2(0.03, 0.03))
	Shapes.lathe(post, [Vector2(0.0, 0.25), Vector2(0.2, 0.2), Vector2(0.03, 0.34), Vector2(0.0, 0.38)],
			lamp + Vector3(0, LAMP_OUT_H - 0.05, 0), 4)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		Shapes.beam(post, lamp + Vector3(cos(a) * 0.1, LAMP_OUT_H - 0.24, sin(a) * 0.1), lamp + Vector3(cos(a) * 0.17,
				LAMP_OUT_H + 0.15, sin(a) * 0.17), Vector2(0.015, 0.015))
	var pmi: MeshInstance3D = h.n._add_unbaked("StreetLamp", post)
	pmi.add_to_group(Builder.SEE_THROUGH)
	var panes := RoomMesh.new()
	var lm: ShaderMaterial = h.n._light.lamp_material(Color(1.0, 0.86, 0.6), 2.4, 0.0, "accent")
	h.street_lamps = lm
	panes.surface(lm)
	Shapes.lathe(panes, [Vector2(0.09, -0.22), Vector2(0.16, 0.14), Vector2(0.0, 0.16)], lamp + Vector3(0, LAMP_OUT_H,
			0), 4, Basis(Vector3.UP, PI * 0.25))
	# Their lamp across the road: the lantern's glow on its post (the post is in the picture).
	var theirs := Vector3(mid - Pictures.LAMP_THEIRS.x, STREET_Y + Pictures.LAMP_THEIRS.y, fz + STREET_DEEP - 0.05)
	Shapes.quad(panes, theirs, Vector3(0.18, 0, 0), Vector3(0, 0.25, 0), Vector3.FORWARD)
	var gmi: MeshInstance3D = h.n._add_lamps("StreetLamps", panes)
	gmi.add_to_group(Builder.SEE_THROUGH)
	# The street's light into the hall for the bake: the lamp outside through the glass, cool from the night.
	_spot(h, "StreetLight", lamp + Vector3(0.0, LAMP_OUT_H - 0.1, -0.25), Vector3(WINDOW_MID, 0.0, fz - 3.5), 38.0,
			14.0, 2.2, Color(0.72, 0.82, 1.0))


## A hidden spot for the bake from `at` towards `to`.
static func _spot(h: Hall, node_name: String, at: Vector3, to: Vector3, angle: float, reach: float, energy: float,
		colour: Color) -> void:
	var l := SpotLight3D.new()
	l.name = node_name
	l.position = at
	l.basis = Basis.looking_at(to - at, Vector3.UP if absf((to - at).normalized().y) < 0.99 else Vector3.BACK)
	l.spot_angle = angle
	l.spot_range = reach
	l.light_energy = energy
	l.light_color = colour
	h.n._light.add_bake_light(l)


## The street's brightness as seen (the builder's street_glow: 0.35 as designed).
static func set_street(h: Hall, glow: float) -> void:
	var k := glow / 0.35
	if h.street_mat != null:
		h.street_mat.albedo_color = Color(k, k, k)
	if h.street_lamps != null:
		h.street_lamps.set_shader_parameter("energy", 2.4 * k)


# --- The cart ----------------------------------------------------------------------------------------------------------

## A horse and a covered cart passing in the street, now and then before the film (the room's `cart` cue with the
## hooves' sound): seen through the window as a dark shape against the lit shop opposite, its two lamps gliding by and
## their streaks on the wet setts. The horse walks (its legs swing, slowly), the wheels turn. Never in the room, never
## in the sight line (behind the seats, outside the glass).
const CART_Z := 5.6
const CART_SPEED := 1.7
const CART_REACH := 13.6
## A horse's walk: about a stride (1.8 m) a second at its pace, the legs swinging 0.22 rad (slow: under 1.5 rad/s).
const CART_STRIDE := 1.8
const CART_LEG_SWING := 0.22


static func _cart(h: Hall) -> void:
	var cart := Node3D.new()
	cart.name = "Cart"
	cart.visible = false
	h.n.own(cart)
	cart.add_to_group(Builder.SEE_THROUGH)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.012, 0.01, 0.009)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	h.cart_dark = dark
	# The van and the horse as flat shapes facing the window (local x along the street, y up).
	var body := [
		# The van's box with its curved roof, its shafts, the horse's body, neck and head, its tail.
		PackedVector2Array([Vector2(-1.5, 0.75), Vector2(0.35, 0.75), Vector2(0.35, 2.05), Vector2(0.15, 2.2),
				Vector2(-0.6, 2.28), Vector2(-1.3, 2.2), Vector2(-1.5, 2.05)]),
		PackedVector2Array([Vector2(0.3, 1.0), Vector2(1.35, 1.25), Vector2(1.35, 1.29), Vector2(0.3, 1.06)]),
		PackedVector2Array([Vector2(1.0, 1.05), Vector2(1.15, 0.98), Vector2(2.25, 0.98), Vector2(2.45, 1.08),
				Vector2(2.5, 1.35), Vector2(2.42, 1.55), Vector2(2.2, 1.62), Vector2(1.3, 1.62), Vector2(1.05, 1.52),
				Vector2(0.98, 1.3)]),
		PackedVector2Array([Vector2(2.2, 1.45), Vector2(2.45, 1.5), Vector2(2.78, 1.96), Vector2(2.98, 1.86),
				Vector2(3.1, 1.88), Vector2(3.08, 1.98), Vector2(2.95, 2.16), Vector2(2.86, 2.28), Vector2(2.8, 2.2),
				Vector2(2.7, 2.18), Vector2(2.42, 1.8)]),
		PackedVector2Array([Vector2(1.02, 1.5), Vector2(0.9, 1.3), Vector2(0.92, 0.95), Vector2(0.98, 0.95),
				Vector2(1.0, 1.3)]),
	]
	h.cart_body = PackedVector3Array()
	for poly: PackedVector2Array in body:
		for k in Geometry2D.triangulate_polygon(poly):
			h.cart_body.append(Vector3(poly[k].x, poly[k].y, 0.0))
	# The wheels: a rim, a hub and spokes (triangles about the hub, turned as it rolls).
	h.cart_wheels.clear()
	for w: Vector2 in [Vector2(-1.1, 0.6), Vector2(0.05, 0.45)]:
		var tris := PackedVector2Array()
		for k in 24:
			var a := k * TAU / 24.0
			for q: Vector2 in _ring_quad(a, a + TAU / 24.0, w.y - 0.06, w.y):
				tris.append(q)
		for k in 6:
			var a := k * TAU / 6.0
			var dir := Vector2(cos(a), sin(a))
			var side := Vector2(-dir.y, dir.x) * 0.02
			for q: Vector2 in [side, dir * w.y - side, dir * w.y + side, side, dir * w.y + side, -side]:
				tris.append(q)
		h.cart_wheels.append([w, tris])
	h.cart_shape = ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.name = "Shape"
	mi.mesh = h.cart_shape
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	cart.add_child(mi)
	# The lamps on the van's front corners and their streak on the wet setts towards the window (from under the lamp,
	# a hair over the road): one draw, the streak dimmer by vertex colour.
	var glow := ShaderMaterial.new()
	glow.shader = Builder.GLOW_SHADER
	glow.set_shader_parameter("colour", Color(1.0, 0.78, 0.45))
	glow.set_shader_parameter("picture", Procedural.flame())
	glow.set_shader_parameter("energy", 2.0)
	glow.set_shader_parameter("use_vertex_colour", true)
	var gs := SurfaceTool.new()
	gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	gs.set_color(Color.WHITE)
	for q: Array in [[Vector3(0.38, 1.55, -0.05), Vector2(0.07, 0.1)], [Vector3(0.38, 1.55, 0.7), Vector2(0.06, 0.09)]]:
		_glow_quad(gs, q[0], Vector3(q[1].x, 0, 0), Vector3(0, q[1].y, 0))
	gs.set_color(Color(0.18, 0.16, 0.14))
	_glow_quad(gs, Vector3(0.38, 0.01, 1.3), Vector3(0.12, 0, 0), Vector3(0, 0, 1.3))
	var gmesh := gs.commit()
	gmesh.surface_set_material(0, glow)
	var gmi := MeshInstance3D.new()
	gmi.name = "Lamps"
	gmi.mesh = gmesh
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cart.add_child(gmi)
	h.cart = cart
	h.cart_glows = [glow]
	_place_cart(h)


static func _ring_quad(a0: float, a1: float, r0: float, r1: float) -> Array:
	var p := [Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))]
	return [p[0] * r0, p[1] * r0, p[1] * r1, p[0] * r0, p[1] * r1, p[0] * r1]


static func _glow_quad(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3) -> void:
	var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.FORWARD)
		st.set_uv(uvs[k])
		st.add_vertex(corners[k])


## The projector's lens: the front of its tube in the booth's port (the room's beam starts here).
static func lens(h: Hall) -> Vector3:
	return Vector3(LENS.x, LENS.y, h.hi.z - PLATFORM_DEPTH + 0.1 - 0.06)


## How many of the piano's keys are down now; how far its roll has turned (0..1, one picture of the roll).
static func keys_down(h: Hall) -> int:
	return h.key_down.count(true)


static func roll_turned(h: Hall) -> float:
	return h.roll_scroll


## The cart starts across the street (left to right as the room sees it through the window), `seconds` to pass.
static func start_cart(h: Hall, seconds: float) -> void:
	if h.cart == null or cart_passing(h):
		return
	h.cart_t = 0.0
	h.cart_seconds = maxf(seconds, 1.0)
	h.cart.visible = true
	_place_cart(h)


static func cart_passing(h: Hall) -> bool:
	return h.cart != null and h.cart.visible


## Where the cart is now (the room's frame).
static func cart_position(h: Hall) -> Vector3:
	return h.cart.position if h.cart != null else Vector3.ZERO


static func _place_cart(h: Hall) -> void:
	var f := clampf(h.cart_t / h.cart_seconds, 0.0, 1.0)
	# It drives on the far side of the road's middle, its front to +x; seen from the window its near side faces us.
	h.cart.position = Vector3(WINDOW_MID + lerpf(CART_REACH, -CART_REACH, f), STREET_Y, h.hi.z + CART_Z)
	h.cart.rotation = Vector3(0.0, PI, 0.0)
	# A walk: a stride of CART_STRIDE at its pace, each leg a quarter out of step with the next.
	var stride := h.cart_t * CART_SPEED / CART_STRIDE * TAU
	var phases := [0.0, 0.5, 0.26, 0.76]
	var hips := [1.18, 1.3, 2.18, 2.3]
	var verts := h.cart_body.duplicate()
	for k in 4:
		var swing := CART_LEG_SWING * sin(stride + phases[k] * TAU)
		if k == 0:
			h.cart_leg_angle = swing
		var hip := Vector2(hips[k], 1.05)
		var c := [Vector2(-0.0375, 0.0), Vector2(0.0375, 0.0), Vector2(0.0375, -0.98), Vector2(-0.0375, -0.98)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var q: Vector2 = hip + (c[i] as Vector2).rotated(swing)
			verts.append(Vector3(q.x, q.y, 0.002))
	for w: Array in h.cart_wheels:
		var hub: Vector2 = w[0]
		var turn := -h.cart_t * CART_SPEED / hub.y
		for q: Vector2 in (w[1] as PackedVector2Array):
			var r := hub + q.rotated(turn)
			verts.append(Vector3(r.x, r.y, -0.003))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.FORWARD)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	h.cart_shape.clear_surfaces()
	h.cart_shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	h.cart_shape.surface_set_material(0, h.cart_dark)


static func animate_cart(h: Hall, delta: float) -> void:
	if not cart_passing(h):
		return
	h.cart_t += delta
	if h.cart_t >= h.cart_seconds:
		h.cart.visible = false
		return
	_place_cart(h)


const RoomSchemaRef := preload("res://scripts/assistant/room_schema.gd")
