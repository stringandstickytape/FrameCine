extends "res://scripts/env/systems/env_system.gd"

## The seats system (docs/environments.md, "The seats system"): seat models outside the builders, and the seats a
## room draws with them. Three ways in:
##   - the builders' seat slots: a builder with seat_slots() (shopfront, nave, terrace, domestic, vehicle, dome_hall)
##     draws no seats of its own when the room has a seats system; this system draws one in every slot, the model
##     chosen by the slot's style or by `model`. The builder lists those seats (its seats()); this system does not.
##   - its own seats: rows (`per_row`, `rows_front`, `rows_back`) round `origin`, and single `places`. These are its
##     seats() (seat choice, seat picking, the sight-line check).
##   - broken seats over a builder that draws its own (the auditorium): `broken` names room seats by their index in
##     the room's seat list; the builder's seat there is folded away and a broken one drawn in its place.
## A builder can also draw a model itself: model_mesh() (auditorium.gd seat_mesh() does, for every model but the
## stadium seat, which stays its own).
##
## Every model is low-poly (RoomMesh boxes and rounded boxes, 100 to 700 triangles), in its own frame: the floor point
## under the seated eyes at the origin, facing -Z. One MultiMesh per model and form ("Seats", "SeatsUp",
## "SeatsBroken"), a slight tint per seat on the upholstery (instance colour: faded and replaced seat by seat), the
## viewer's own seat folded away (single seats only; a pew, a bench, a cushion, a hide or a bean bag stays), and
## boxes for object physics (collision_shapes()). Pews' and benches' seats are segments a slot wide: their ends go into
## one static mesh, "SeatEnds", at each run's two ends. Library materials only (all CC0).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const AUDITORIUM := "res://scripts/env/systems/auditorium.gd"

## The models: their default materials, whether the viewer's own seat folds away, whether a seat is a segment of a
## longer piece (its ends drawn apart), its width when the slot gives none, the other forms it has (up: the tip-up
## seat tipped up; broken), and its collision boxes [centre, size, tilt about x in degrees] in its own frame.
const MODELS := {
	"stadium": {"upholstery": {"library": "velvet", "color": [0.376, 0.092, 0.11], "tiling": 0.22},
		"frame": {"library": "black_leather", "color": [0.08, 0.075, 0.078]}, "fold": true, "segment": false,
		"width": 0.58, "forms": ["up", "broken"],
		"boxes": [[Vector3(0.0, 0.24, -0.05), Vector3(0.55, 0.48, 0.52), 0.0],
				[Vector3(0.0, 0.76, 0.27), Vector3(0.52, 0.72, 0.14), 13.0]]},
	"folding_chair": {"upholstery": {"library": "oak_veneer", "color": [0.42, 0.28, 0.16]},
		"frame": {"library": "red_hardwood", "color": [0.3, 0.19, 0.12]}, "fold": true, "segment": false,
		"width": 0.5, "forms": [],
		"boxes": [[Vector3(0.0, 0.23, -0.1), Vector3(0.44, 0.46, 0.42), 0.0],
				[Vector3(0.0, 0.68, 0.14), Vector3(0.44, 0.45, 0.05), 8.0]]},
	"plush": {"upholstery": {"library": "velvet", "color": [0.45, 0.07, 0.12], "tiling": 0.22},
		"frame": {"library": "walnut_veneer", "color": [0.22, 0.13, 0.08]}, "fold": true, "segment": false,
		"width": 0.6, "forms": ["up", "broken"],
		"boxes": [[Vector3(0.0, 0.25, -0.05), Vector3(0.56, 0.5, 0.54), 0.0],
				[Vector3(0.0, 0.8, 0.27), Vector3(0.54, 0.8, 0.14), 11.0]]},
	"multiplex": {"upholstery": {"library": "woven_upholstery", "color": [0.38, 0.17, 0.09]},
		"frame": {"library": "pale_laminate", "color": [0.12, 0.12, 0.14]}, "fold": true, "segment": false,
		"width": 0.56, "forms": ["up", "broken"],
		"boxes": [[Vector3(0.0, 0.24, -0.05), Vector3(0.54, 0.48, 0.52), 0.0],
				[Vector3(0.0, 0.8, 0.27), Vector3(0.52, 0.8, 0.12), 12.0]]},
	"pew": {"upholstery": {"library": "oak_veneer", "color": [0.36, 0.23, 0.13]},
		"frame": {"library": "walnut_veneer", "color": [0.24, 0.15, 0.09]}, "fold": false, "segment": true,
		"width": 0.55, "forms": [],
		"boxes": [[Vector3(0.0, 0.235, -0.08), Vector3(1.0, 0.47, 0.42), 0.0],
				[Vector3(0.0, 0.72, 0.17), Vector3(1.0, 0.55, 0.06), 10.0]]},
	"club_chair": {"upholstery": {"library": "brown_leather", "color": [0.33, 0.18, 0.1]},
		"frame": {"library": "walnut_veneer", "color": [0.2, 0.12, 0.07]}, "fold": true, "segment": false,
		"width": 0.96, "forms": [],
		"boxes": [[Vector3(0.0, 0.3, 0.0), Vector3(0.86, 0.6, 0.86), 0.0],
				[Vector3(0.0, 0.75, 0.35), Vector3(0.86, 0.5, 0.2), 10.0]]},
	"director": {"upholstery": {"library": "linen", "color": [0.62, 0.55, 0.42]},
		"frame": {"library": "oak_veneer", "color": [0.45, 0.31, 0.18]}, "fold": true, "segment": false,
		"width": 0.66, "forms": [],
		"boxes": [[Vector3(0.0, 0.23, -0.1), Vector3(0.56, 0.46, 0.46), 0.0],
				[Vector3(0.0, 0.68, 0.13), Vector3(0.56, 0.45, 0.05), 0.0]]},
	"bench_seat": {"upholstery": {"library": "brown_leather", "color": [0.78, 0.72, 0.62]},
		"frame": {"library": "dark_metal", "color": [0.5, 0.08, 0.08]}, "fold": false, "segment": true,
		"width": 0.6, "forms": [],
		"boxes": [[Vector3(0.0, 0.23, -0.1), Vector3(1.0, 0.46, 0.52), 0.0],
				[Vector3(0.0, 0.75, 0.22), Vector3(1.0, 0.7, 0.18), 14.0]]},
	"cushion": {"upholstery": {"library": "corduroy", "color": [0.5, 0.32, 0.2]},
		"frame": {"library": "corduroy", "color": [0.3, 0.2, 0.14]}, "fold": false, "segment": false,
		"width": 0.62, "forms": [],
		"boxes": [[Vector3(0.0, 0.075, -0.05), Vector3(0.56, 0.15, 0.56), 0.0]]},
	"hide": {"upholstery": {"library": "cream_carpet", "color": [0.86, 0.8, 0.72]},
		"frame": {"library": "white_marble", "color": [0.72, 0.8, 0.86]}, "fold": false, "segment": false,
		"width": 0.7, "forms": [],
		"boxes": [[Vector3(0.0, 0.22, -0.05), Vector3(0.6, 0.44, 0.6), 0.0]]},
	"bean_bag": {"upholstery": {"library": "corduroy", "color": [0.2, 0.3, 0.45]},
		"frame": {"library": "corduroy", "color": [0.2, 0.3, 0.45]}, "fold": false, "segment": false,
		"width": 0.95, "forms": [],
		"boxes": [[Vector3(0.0, 0.25, -0.05), Vector3(0.9, 0.5, 0.9), 0.0]]},
	"settee": {"upholstery": {"library": "melange_fabric", "color": [0.45, 0.38, 0.3]},
		"frame": {"library": "oak_veneer", "color": [0.28, 0.18, 0.1]}, "fold": false, "segment": true,
		"width": 0.62, "forms": [],
		"boxes": [[Vector3(0.0, 0.24, -0.03), Vector3(1.0, 0.48, 0.84), 0.0],
				[Vector3(0.0, 0.68, 0.32), Vector3(1.0, 0.5, 0.2), 12.0]]},
}
const MODEL_NAMES: Array[String] = ["stadium", "folding_chair", "plush", "multiplex", "pew", "club_chair",
		"director", "bench_seat", "cushion", "hide", "bean_bag", "settee"]
## The models a hall of rows takes (auditorium.gd seat_model): single seats, not segments.
const SINGLE_MODELS: Array[String] = ["stadium", "folding_chair", "plush", "multiplex", "club_chair", "director",
		"cushion", "bean_bag"]
## A builder's slot style -> the model drawn there when `model` is auto.
const STYLE_MODELS := {"chair": "folding_chair", "pew": "pew", "bench": "bench_seat", "cushion": "cushion",
		"club": "club_chair", "ring": "plush", "tier": "cushion", "hide": "hide", "director": "director",
		"settee": "settee"}
## The tip-up seat tipped up (degrees) and the broken seat's back, slumped (degrees from upright).
## A settee's arm, its width.
const SETTEE_ARM := 0.17
const TIP_UP_DEG := 78.0
const BROKEN_BACK_DEG := 36.0


static func spec() -> Dictionary:
	return {
		"kind": "seats",
		"description": "Seat models and the seats a room draws with them: in the builders' seat slots (by the slot's "
				+ "style or one model), in rows or single places of its own, and broken seats over a builder's own. "
				+ "Models: stadium, folding_chair (1906), plush (tip-up, palaces), multiplex (1980s, a broken one), "
				+ "pew, club_chair, director, bench_seat, cushion, hide, bean_bag, settee (two or three places in a "
				+ "row, its arms at the ends). Instanced, tinted seat by seat, "
				+ "the viewer's own chair folded away, boxes for object physics.",
		"params": PARAMS,
		"actions": {},
		"provides": ["seats", "collision"],
		"requires": [],
		"cost": {"draws": 6, "triangles": 60000, "lights": 0, "particles": 0, "texture_mb": 16},
	}


const PARAMS := {
	"model": {"type": "enum", "values": ["auto", "stadium", "folding_chair", "plush", "multiplex", "pew",
			"club_chair", "director", "bench_seat", "cushion", "hide", "bean_bag", "settee"], "default": "auto",
			"description": "the seat; auto: by each slot's style (its own rows: folding chairs)"},
	"from_builders": {"type": "bool", "default": true,
			"description": "a seat in every seat slot of the room's builders"},
	"per_row": {"type": "int", "min": 0, "max": 40, "default": 0,
			"description": "its own rows: seats in each; 0: no rows of its own"},
	"rows_front": {"type": "int", "min": 0, "max": 30, "default": 0,
			"description": "its own rows in front of the row at origin"},
	"rows_back": {"type": "int", "min": 0, "max": 30, "default": 0,
			"description": "its own rows behind the row at origin"},
	"pitch": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.0,
			"description": "seat centres along a row, metres; 0: the model's own width"},
	"row_depth": {"type": "float", "min": 0.5, "max": 4.0, "default": 1.1, "description": "metres a row"},
	"row_rise": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
			"description": "each row this much higher than the one in front"},
	"aisle": {"type": "float", "min": 0.0, "max": 6.0, "default": 0.0,
			"description": "a gap this wide down the middle of the rows; 0: none"},
	"origin": {"type": "vec3", "min": -200.0, "max": 200.0, "default": [0.0, 0.0, 0.0],
			"description": "the middle of the row at origin (the viewer's own seat with an odd per_row)"},
	"facing": {"type": "float", "min": -180.0, "max": 180.0, "default": 0.0,
			"description": "the rows turn by this, degrees (0: towards -z)"},
	"places": {"type": "list", "max": 32, "default": [],
			"of": {"type": "object", "fields": {
				"at": {"type": "vec3", "min": -200.0, "max": 200.0, "description": "the floor point"},
				"turn": {"type": "float", "min": -180.0, "max": 180.0, "description": "degrees (0: towards -z)"},
				"model": {"type": "enum", "values": ["auto", "stadium", "folding_chair", "plush", "multiplex", "pew",
						"club_chair", "director", "bench_seat", "cushion", "hide", "bean_bag", "settee"],
						"description": "this one's model; auto: the system's"}}},
			"description": "single seats of its own: {at, turn, model}"},
	"upholstery": {"type": "material", "default": null, "nullable": true,
			"description": "the cushions and backs; null: the model's own"},
	"frame": {"type": "material", "default": null, "nullable": true,
			"description": "the frames, legs and shells; null: the model's own"},
	"variation": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
			"description": "how much one seat's colour differs from the next"},
	"seed": {"type": "int", "min": 0, "max": 1000000, "default": 1906, "description": "the tints' and tips' seed"},
	"tipped": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
			"description": "the share of tip-up seats (stadium, plush, multiplex) left tipped up"},
	"broken": {"type": "list", "of": {"type": "int", "min": 0, "max": 9999}, "max": 8, "default": [],
			"description": "room seats drawn broken (their index in the room's seat list): chairs only"},
	"fold_own": {"type": "bool", "default": true, "description": "the viewer's own chair folded away"},
	# Since 2026-11-08, for Reclaimed (a ruin's stalls: some seats tipped up, as broken does for a builder's own).
	"up": {"type": "list", "of": {"type": "int", "min": 0, "max": 9999}, "max": 24, "default": [],
			"description": "room seats drawn tipped up (their index in the room's seat list), a builder's own too: "
			+ "tip-up seats only"},
}


# --- Models -------------------------------------------------------------------------------------------------------------

## The model's own default material ("upholstery" or "frame").
static func default_material(model: String, part: String) -> Dictionary:
	return MODELS.get(model, MODELS["folding_chair"])[part]


static func model_width(model: String) -> float:
	return float(MODELS.get(model, MODELS["folding_chair"])["width"])


## One seat of a model, its floor point under the seated eyes at the origin, facing -Z, `width` metres along its row
## (0: the model's own). form: "" (as it stands), "up" (a tip-up seat tipped up), "broken" (the back slumped, the
## cushion hanging).
static func model_mesh(model: String, upholstery: Material, frame: Material, width := 0.0, form := "") -> ArrayMesh:
	var w := width if width > 0.0 else model_width(model)
	var b := RoomMesh.new()
	match model:
		"stadium":
			if form == "":
				return (load(AUDITORIUM) as GDScript).call("seat_mesh", upholstery, frame, w)
			_theatre(b, upholstery, frame, w, form, "stadium")
		"plush", "multiplex":
			_theatre(b, upholstery, frame, w, form, model)
		"pew":
			_pew(b, upholstery, frame, w)
		"club_chair":
			_club(b, upholstery, frame)
		"director":
			_director(b, upholstery, frame)
		"bench_seat":
			_bench(b, upholstery, frame, w)
		"cushion":
			_cushion(b, upholstery, frame)
		"hide":
			_hide(b, upholstery, frame)
		"bean_bag":
			_bean_bag(b, upholstery)
		"settee":
			_settee(b, upholstery, w)
		_:
			_folding_chair(b, upholstery, frame, w)
	return b.commit(false)


## The ends of a run of segments (a pew's carved ends, a bench's side trim), at the run's left (side -1) or right
## (side 1) end, into b in the frame `xf` (a segment's own frame).
static func end_piece(b: RoomMesh, model: String, xf: Transform3D, w: float, side: float, frame: Material,
		upholstery: Material) -> void:
	var x := side * (w * 0.5 + 0.025)
	match model:
		"pew":
			b.surface(frame)
			b.box(xf * Vector3(x, 0.5, -0.03), Vector3(0.05, 1.0, 0.62), xf.basis, [RoomMesh.DOWN])
			b.box(xf * Vector3(x, 1.03, -0.03), Vector3(0.07, 0.06, 0.66), xf.basis, [RoomMesh.DOWN])
			b.box(xf * Vector3(x, 0.03, -0.03), Vector3(0.08, 0.06, 0.68), xf.basis, [RoomMesh.DOWN])
		"bench_seat":
			b.surface(upholstery)
			b.box(xf * Vector3(x, 0.45, -0.06), Vector3(0.05, 0.22, 0.52), xf.basis, [RoomMesh.DOWN])
		"settee":
			# A padded arm, and the settee's two feet at that end.
			var ax := side * (w * 0.5 + SETTEE_ARM * 0.5)
			b.surface(upholstery)
			b.rounded_box(Vector3.ZERO, Vector3(SETTEE_ARM, 0.6, 0.86), 0.06, xf * Transform3D(Basis(),
					Vector3(ax, 0.38, 0.0)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
			b.surface(frame)
			for z: float in [-0.36, 0.36]:
				b.box(xf * Vector3(ax, 0.04, z), Vector3(0.05, 0.08, 0.05), xf.basis, [RoomMesh.DOWN, RoomMesh.UP])


## The theatre seats: a cushion and a back between half arm rests and half standards (a joined row, as the stadium
## seat): stadium (velvet on black), plush (a deeper cushion, a taller back with a wooden shell, cast standards) and
## multiplex (a moulded shell round a fabric insert, broad arms with a cup holder).
static func _theatre(b: RoomMesh, u: Material, f: Material, w: float, form: String, style: String) -> void:
	var half := w * 0.5
	var plush := style == "plush"
	var multi := style == "multiplex"
	var seat_y := 0.44 if plush else (0.43 if multi else 0.41)
	var thick := 0.16 if plush else (0.12 if multi else 0.13)
	var back_h := 0.78 if plush else (0.74 if multi else 0.66)
	var tilt_deg := 11.0 if plush else (12.0 if multi else 13.0)
	if form == "broken":
		tilt_deg = BROKEN_BACK_DEG
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(tilt_deg)), Vector3(0.0, seat_y + 0.01, 0.2))
	# The cushion: down, tipped up about its back edge, or hanging (broken: dropped at the front and to one side).
	var hinge := Vector3(0.0, seat_y, 0.17)
	var cushion_xf := Transform3D()
	if form == "up":
		cushion_xf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(TIP_UP_DEG)), hinge) * Transform3D(Basis(), -hinge)
	elif form == "broken":
		var basis := Basis(Vector3.RIGHT, deg_to_rad(-14.0)) * Basis(Vector3.BACK, deg_to_rad(5.0))
		cushion_xf = Transform3D(basis, hinge) * Transform3D(Basis(), -hinge)
	b.surface(u)
	b.rounded_box(Vector3(0.0, seat_y, -0.07), Vector3(half * 2.0 - 0.08, thick, 0.5), 0.045, cushion_xf, 1,
			Vector3i(1, 0, 0), 0.0, [RoomMesh.DOWN])
	b.rounded_box(Vector3(0.0, back_h * 0.5, 0.0), Vector3(half * 2.0 - 0.08, back_h, 0.09), 0.04, tilt, 1,
			Vector3i(3, 1, 0), -0.5, [RoomMesh.DOWN])
	# The back's outer cover (what the row behind sees): velvet on the stadium, the shell on the others.
	if plush or multi:
		b.surface(f)
	var shell_w := half * 2.0 - (0.03 if multi else 0.06)
	b.rounded_box(Vector3(0.0, back_h * 0.5 + 0.02, 0.068), Vector3(shell_w, back_h + 0.06, 0.05 if multi else 0.045),
			0.02, tilt, 1, Vector3i(3, 1, 0), -0.5, [RoomMesh.DOWN])
	b.surface(f)
	var arm_w := 0.05 if multi else 0.031
	var arm_y := seat_y + (0.24 if plush else 0.245)
	for s: float in [-1.0, 1.0]:
		var x := s * (half - arm_w * 0.5)
		b.rounded_box(Vector3(x, arm_y, -0.03), Vector3(arm_w, 0.05, 0.46 if multi else 0.44), 0.012, Transform3D(), 1,
				Vector3i.ZERO, 0.0, [Vector3(s, 0, 0), RoomMesh.DOWN])
		if plush:
			# A cast standard: a broad foot and a waisted upright.
			b.box(Vector3(x, 0.04, -0.02), Vector3(arm_w, 0.08, 0.5), Basis(), [Vector3(s, 0, 0), RoomMesh.DOWN])
			b.box(Vector3(x, arm_y * 0.5, 0.02), Vector3(arm_w, arm_y, 0.16), Basis(), [Vector3(s, 0, 0), RoomMesh.DOWN])
		else:
			b.box(Vector3(x, arm_y * 0.48, 0.09 if not multi else -0.02), Vector3(arm_w, arm_y * 0.96,
					0.3 if not multi else 0.5), Basis(), [Vector3(s, 0, 0), RoomMesh.DOWN])
	if multi:
		# The cup holder at the right arm's front.
		b.box(Vector3(half - 0.03, arm_y + 0.03, -0.24), Vector3(0.07, 0.015, 0.07), Basis(), [RoomMesh.DOWN])
	if not plush:
		b.box(Vector3(0.0, 0.175, -0.02), Vector3(0.1, 0.31, 0.1), Basis(), [RoomMesh.DOWN, RoomMesh.UP])
		b.box(Vector3(0.0, 0.01, -0.02), Vector3(0.32, 0.02, 0.26), Basis(), [RoomMesh.DOWN])


## A folding wooden chair of the shopfront years: a slatted seat, two back slats, the back legs running up into the
## uprights, a stretcher in front.
static func _folding_chair(b: RoomMesh, u: Material, f: Material, w: float) -> void:
	var sw := minf(w - 0.08, 0.44)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(8.0))
	b.surface(u)
	for z: float in [-0.25, -0.11, 0.03]:
		b.box(Vector3(0.0, 0.45, z), Vector3(sw, 0.022, 0.115))
	for y: float in [0.68, 0.82]:
		b.box(Vector3(0.0, y, 0.11 + (y - 0.45) * tan(deg_to_rad(8.0))), Vector3(sw, 0.075, 0.018), lean)
	b.surface(f)
	for s: float in [-1.0, 1.0]:
		var x := s * (sw * 0.5 - 0.015)
		b.box(Vector3(x, 0.22, -0.27), Vector3(0.03, 0.44, 0.03), Basis(), [RoomMesh.DOWN])
		b.box(Vector3(x, 0.45, 0.11), Vector3(0.03, 0.9, 0.03), lean, [RoomMesh.DOWN])
		b.box(Vector3(x, 0.425, -0.08), Vector3(0.022, 0.03, 0.4))
	b.box(Vector3(0.0, 0.18, -0.27), Vector3(sw - 0.03, 0.025, 0.02))
	b.box(Vector3(0.0, 0.18, 0.08), Vector3(sw - 0.03, 0.025, 0.02))


## A pew's segment, one sitting place wide: the plank, the panelled back leaning back, its top rail, the book ledge
## on its back for the row behind, the apron under the front. The ends are end_piece().
static func _pew(b: RoomMesh, u: Material, f: Material, w: float) -> void:
	var lean := Basis(Vector3.RIGHT, deg_to_rad(10.0))
	b.surface(u)
	b.box(Vector3(0.0, 0.445, -0.08), Vector3(w, 0.045, 0.4), Basis(), [Vector3.LEFT, Vector3.RIGHT])
	b.box(Vector3(0.0, 0.72, 0.15), Vector3(w, 0.5, 0.025), lean, [Vector3.LEFT, Vector3.RIGHT])
	b.surface(f)
	b.box(Vector3(0.0, 0.985, 0.2), Vector3(w, 0.05, 0.07), Basis(), [Vector3.LEFT, Vector3.RIGHT])
	b.box(Vector3(0.0, 0.78, 0.24), Vector3(w, 0.02, 0.12), Basis(), [Vector3.LEFT, Vector3.RIGHT])
	b.box(Vector3(0.0, 0.8, 0.295), Vector3(w, 0.05, 0.015), Basis(), [Vector3.LEFT, Vector3.RIGHT])
	b.box(Vector3(0.0, 0.38, -0.265), Vector3(w, 0.08, 0.025), Basis(), [Vector3.LEFT, Vector3.RIGHT])


## A deep club chair: a leather body on four short feet, a cushion, rolled arms, a low curved back.
static func _club(b: RoomMesh, u: Material, f: Material) -> void:
	b.surface(u)
	b.rounded_box(Vector3(0.0, 0.25, 0.0), Vector3(0.86, 0.3, 0.86), 0.04, Transform3D(), 1, Vector3i.ZERO, 0.0,
			[RoomMesh.DOWN])
	b.rounded_box(Vector3(0.0, 0.46, -0.08), Vector3(0.56, 0.13, 0.64), 0.05, Transform3D(), 1, Vector3i(1, 0, 1), 0.0,
			[RoomMesh.DOWN])
	for s: float in [-1.0, 1.0]:
		b.rounded_box(Vector3(s * 0.355, 0.56, 0.0), Vector3(0.15, 0.34, 0.84), 0.06, Transform3D(), 1, Vector3i.ZERO,
				0.0, [RoomMesh.DOWN])
	b.rounded_box(Vector3.ZERO, Vector3(0.86, 0.5, 0.2), 0.07,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(10.0)), Vector3(0.0, 0.66, 0.33)), 1, Vector3i(2, 0, 0), -0.25,
			[RoomMesh.DOWN])
	b.surface(f)
	for x: float in [-0.36, 0.36]:
		for z: float in [-0.36, 0.36]:
			b.box(Vector3(x, 0.05, z), Vector3(0.05, 0.1, 0.05), Basis(), [RoomMesh.DOWN, RoomMesh.UP])


## A director's chair: crossed legs either side, seat rails, arms on short posts, a canvas seat and back band.
static func _director(b: RoomMesh, u: Material, f: Material) -> void:
	b.surface(u)
	b.box(Vector3(0.0, 0.43, -0.1), Vector3(0.47, 0.012, 0.42))
	b.box(Vector3(0.0, 0.82, 0.135), Vector3(0.5, 0.18, 0.012))
	b.surface(f)
	for s: float in [-1.0, 1.0]:
		var x := s * 0.25
		for a: float in [45.0, -45.0]:
			b.box(Vector3(x, 0.232, -0.1), Vector3(0.03, 0.62, 0.035), Basis(Vector3.RIGHT, deg_to_rad(a)))
		b.box(Vector3(x, 0.44, -0.1), Vector3(0.035, 0.035, 0.46))
		b.box(Vector3(x, 0.015, -0.1), Vector3(0.035, 0.03, 0.46), Basis(), [RoomMesh.DOWN])
		b.box(Vector3(x, 0.7, 0.13), Vector3(0.03, 0.52, 0.03))
		b.box(Vector3(x, 0.66, -0.1), Vector3(0.05, 0.025, 0.46))
		b.box(Vector3(x, 0.55, -0.3), Vector3(0.03, 0.2, 0.03))


## A convertible's bench seat, one place wide: a sprung cushion, a tuck-and-roll back of three rolls under a top
## roll, the painted plinth under it. The side trim is end_piece().
static func _bench(b: RoomMesh, u: Material, f: Material, w: float) -> void:
	var lean := Basis(Vector3.RIGHT, deg_to_rad(14.0))
	b.surface(u)
	b.rounded_box(Vector3.ZERO, Vector3(w, 0.16, 0.52), 0.05,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-4.0)), Vector3(0.0, 0.38, -0.1)), 1, Vector3i.ZERO, 0.0,
			[RoomMesh.DOWN, Vector3.LEFT, Vector3.RIGHT])
	for k in 3:
		var x := (k - 1) * w / 3.0
		b.rounded_box(Vector3.ZERO, Vector3(w / 3.0 - 0.006, 0.54, 0.13), 0.055,
				Transform3D(lean, Vector3(x, 0.72, 0.21)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
	b.rounded_box(Vector3.ZERO, Vector3(w, 0.1, 0.18), 0.045, Transform3D(lean, Vector3(0.0, 1.0, 0.29)), 1,
			Vector3i.ZERO, 0.0, [RoomMesh.DOWN, Vector3.LEFT, Vector3.RIGHT])
	b.surface(f)
	b.box(Vector3(0.0, 0.15, -0.06), Vector3(w, 0.3, 0.46), Basis(), [RoomMesh.DOWN, Vector3.LEFT, Vector3.RIGHT])


## A settee's segment, one place wide: the upholstered base (open at the sides: it runs on into the next place), the
## place's own seat cushion and back cushion, the back behind them. The arms and feet are end_piece().
static func _settee(b: RoomMesh, u: Material, w: float) -> void:
	var sides := [Vector3.LEFT, Vector3.RIGHT]
	b.surface(u)
	b.box(Vector3(0.0, 0.22, -0.02), Vector3(w, 0.28, 0.82), Basis(), sides + [RoomMesh.DOWN])
	b.box(Vector3(0.0, 0.58, 0.36), Vector3(w, 0.44, 0.1), Basis(), sides + [RoomMesh.DOWN])
	b.rounded_box(Vector3(0.0, 0.42, -0.08), Vector3(w - 0.012, 0.13, 0.62), 0.05, Transform3D(), 1, Vector3i(1, 0, 1),
			0.0, [RoomMesh.DOWN])
	b.rounded_box(Vector3.ZERO, Vector3(w - 0.012, 0.44, 0.16), 0.06,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12.0)), Vector3(0.0, 0.68, 0.24)), 1, Vector3i(1, 1, 0), 0.0,
			[RoomMesh.DOWN])


## A floor cushion, buttoned in the middle.
static func _cushion(b: RoomMesh, u: Material, f: Material) -> void:
	b.surface(u)
	b.rounded_box(Vector3(0.0, 0.075, -0.05), Vector3(0.56, 0.15, 0.56), 0.06, Transform3D(), 2, Vector3i(1, 0, 1), 0.0,
			[RoomMesh.DOWN])
	b.surface(f)
	b.box(Vector3(0.0, 0.152, -0.05), Vector3(0.045, 0.012, 0.045), Basis(), [RoomMesh.DOWN])


## A hide over a low block (of ice, in the ice cinema): the pelt on top, its front hanging down, its forelegs at the
## sides.
static func _hide(b: RoomMesh, u: Material, f: Material) -> void:
	b.surface(f)
	b.box(Vector3(0.0, 0.2, -0.05), Vector3(0.6, 0.4, 0.55), Basis(), [RoomMesh.DOWN])
	b.surface(u)
	_pelt(b)


## A reindeer's pelt over the block (since 2026-11-08, for the Ice cinema: "reindeer hides and furs on the benches
## with real thickness and fur edges", the brief): its outline uneven and narrower at the neck, which hangs down the
## block's front, thick as a pelt is and rounded over at its edges, darker brown-grey along the spine and pale towards
## the belly's edges. Colours per vertex (the instance tint multiplies them). Since the second pass (2026-11-08, the
## coordinator: "make them reindeer pelts: lighter cream-grey-brown with a darker spine, a soft fur edge ... a
## natural ragged outline"): the reindeer's colours, a ragged edge, and a fringe of tufts all round it.
static func _pelt(b: RoomMesh) -> void:
	const ACROSS := 9
	const TOP := 0.4
	const THICK := 0.02
	# The path down the pelt, back to front: on the top, over the front edge and down the block's face.
	var path: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for k in 11:
		var z := lerpf(0.27, -0.31, float(k) / 10.0)
		path.append(Vector3(0.0, TOP, z))
		normals.append(Vector3.UP)
	for k in 3:
		var t := (k + 1) / 3.0 * PI * 0.5
		path.append(Vector3(0.0, TOP - 0.035 * (1.0 - cos(t)), -0.31 - 0.035 * sin(t)))
		normals.append(Vector3(0.0, cos(t), -sin(t)))
	for k in 4:
		path.append(Vector3(0.0, TOP - 0.06 - 0.05 * (k + 1), -0.345 - 0.004 * k))
		normals.append(Vector3(0.0, 0.05, -1.0).normalized())
	var rows: Array = []
	var ns: Array = []
	var cols: Array = []
	var spine := Color(0.52, 0.46, 0.4)
	var flank := Color(0.8, 0.76, 0.7)
	var belly := Color(0.96, 0.94, 0.9)
	for i in path.size():
		var s := float(i) / (path.size() - 1)
		# The half width along the pelt: the neck narrower at the front, uneven all along, each side its own way.
		var wave := 0.026 * sin(s * 9.0 + 1.0) + 0.012 * sin(s * 23.0 + 0.5) + 0.008 * sin(s * 47.0 + 2.0)
		var half := 0.3 + wave - 0.06 * smoothstep(0.75, 1.0, s)
		var skew := 0.012 * sin(s * 17.0 + 2.0)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var crow := PackedColorArray()
		for j in ACROSS:
			var u := lerpf(-1.0, 1.0, float(j) / (ACROSS - 1))
			# The pelt rounds down at its sides, its thickness showing.
			var drop := (THICK - 0.004) * smoothstep(0.82, 1.0, absf(u))
			var p := path[i] + Vector3(u * half + skew * absf(u), 0, 0) + normals[i] * (THICK - drop)
			row.append(p)
			nrow.append((normals[i] + Vector3(u * 0.2 * smoothstep(0.75, 1.0, absf(u)), 0, 0)).normalized())
			# The dark back down the spine, the grey-brown flanks, the cream belly at the edges.
			var c := flank.lerp(spine, 1.0 - smoothstep(0.0, 0.22, absf(u)))
			c = c.lerp(belly, smoothstep(0.6, 1.0, absf(u)) * 0.9 + 0.1 * s)
			# The hair lying in patches, a little lighter or darker.
			c *= 0.9 + 0.2 * fposmod(sin(float(i * 31 + j * 7) * 12.9898) * 43758.5453, 1.0)
			crow.append(c.srgb_to_linear())
		rows.append(row)
		ns.append(nrow)
		cols.append(crow)
	b.grid(rows, ns, cols)
	# The fringe: tufts of the belly's long hair round the edge, out from the sides and the back, down from the front.
	var edge_colour := belly.srgb_to_linear() * 0.95
	var last := path.size() - 1
	for side: int in [0, ACROSS - 1]:
		var line: Array[Vector3] = []
		var outs: Array[Vector3] = []
		var up: Array[Vector3] = []
		for i in path.size():
			line.append((rows[i] as PackedVector3Array)[side])
			outs.append(Vector3(-1.0 if side == 0 else 1.0, 0, 0))
			up.append(normals[i])
		_fringe(b, line, outs, up, edge_colour)
	for end: int in [0, last]:
		var line: Array[Vector3] = []
		var outs: Array[Vector3] = []
		var up: Array[Vector3] = []
		for j in ACROSS:
			line.append((rows[end] as PackedVector3Array)[j])
			outs.append(Vector3(0, 0, 1) if end == 0 else Vector3(0, -1, -0.15).normalized())
			up.append(normals[end])
		_fringe(b, line, outs, up, edge_colour)


## Tufts along an edge (points in order), each pointing `outs` from it: every centimetre and a half one, its length and lean
## random and longer in clumps, its tip darker (a soft, ragged edge, not a saw's); facing `up` (the side they are seen
## from).
static func _fringe(b: RoomMesh, line: Array[Vector3], outs: Array[Vector3], up: Array[Vector3],
		colour: Color) -> void:
	var a := PackedVector3Array()
	var c := PackedVector3Array()
	var ns := PackedVector3Array()
	var k := 0
	for i in line.size() - 1:
		var along := (line[i + 1] - line[i]).normalized()
		var steps := maxi(1, ceili(line[i].distance_to(line[i + 1]) / 0.014))
		for j in steps:
			var t := float(j) / steps
			var p := line[i].lerp(line[i + 1], t)
			var out := outs[i].lerp(outs[i + 1], t).normalized()
			# By a hash of the place, so every hide is ragged the same way (the mesh is shared).
			var r1 := fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0)
			var r2 := fposmod(sin(float(k) * 78.233 + 1.7) * 43758.5453, 1.0)
			var clump := 0.55 + 0.45 * sin(float(k) * 0.37 + r2 * 0.8)
			var tuft := 0.002 if k % 2 == 0 else (0.006 + 0.03 * r1 * r1) * clump
			a.append(p)
			c.append(p + out * tuft + along * (r2 - 0.5) * tuft * 0.6)
			ns.append(up[i].lerp(up[i + 1], t).normalized())
			k += 1
	if a.size() < 2:
		return
	var base := PackedColorArray()
	var tips := PackedColorArray()
	for i in a.size():
		base.append(colour)
		tips.append(colour * 0.7)
	b.grid([a, c], [ns, ns], [base, tips])


## A bean bag: a squat round sack, taller at the back, with the dent where one sits.
static func _bean_bag(b: RoomMesh, u: Material) -> void:
	b.surface(u)
	const SEGS := 14
	const RINGS := 7
	var rings: Array[PackedVector3Array] = []
	for k in RINGS + 1:
		var phi := lerpf(-PI * 0.5, PI * 0.5, float(k) / RINGS)
		var ring := PackedVector3Array()
		for i in SEGS + 1:
			ring.append(_bag_point(phi, TAU * float(i) / SEGS))
		rings.append(ring)
	for k in RINGS:
		var normals := PackedVector3Array()
		var phi := lerpf(-PI * 0.5, PI * 0.5, (k + 0.5) / RINGS)
		for i in SEGS + 1:
			var th := TAU * float(i) / SEGS
			var e := 0.02
			var du := _bag_point(phi, th + e) - _bag_point(phi, th - e)
			var dv := _bag_point(phi + e, th) - _bag_point(phi - e, th)
			var n := dv.cross(du).normalized()
			var mid := _bag_point(phi, th) - Vector3(0.0, 0.25, -0.05)
			normals.append(n if n.dot(mid) >= 0.0 else -n)
		b.strip(rings[k], rings[k + 1], normals)


static func _bag_point(phi: float, th: float) -> Vector3:
	var x := 0.46 * cos(phi) * cos(th)
	var z := 0.46 * cos(phi) * sin(th)
	var back := 1.0 + 0.6 * maxf(0.0, sin(th))
	var y := 0.21 * (1.0 + sin(phi)) * back
	if phi > 0.0:
		y -= 0.12 * sin(phi) * exp(-(x * x + (z + 0.1) * (z + 0.1)) / 0.05)
	return Vector3(x, maxf(y, 0.0), z - 0.05)


## A model's collision boxes, [[Shape3D, Transform3D]] in the frame xf; a segment's boxes `width` wide.
static func model_boxes(model: String, xf: Transform3D, width := 0.0) -> Array:
	var info: Dictionary = MODELS.get(model, MODELS["folding_chair"])
	var w := width if width > 0.0 else model_width(model)
	var out: Array = []
	for bx: Array in info["boxes"]:
		var size: Vector3 = bx[1]
		if bool(info["segment"]):
			size.x = w
		var shape := BoxShape3D.new()
		shape.size = size
		out.append([shape, xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(bx[2]))), bx[0])])
	return out


# --- The system ---------------------------------------------------------------------------------------------------------

## The seats it draws: {xf (room frame), model, width, form, own (one of its seats()), run (pews: the run's key),
## overlay (a builder's seat it covers: [builder, index])}
var _entries: Array = []
## "<model>|<form>|<width cm>" -> {node: MultiMeshInstance3D, entries: [entry index]}
var _groups := {}
var _built := false
var _folded := -1
## [[MultiMeshInstance3D of a builder, instance]] folded away under a broken seat of ours.
var _covered: Array = []
## Times a covered seat was folded away again (tests).
var hides := 0


func setup() -> void:
	_built = false


## Its own seats (rows and places): floor points under the seated eyes, facing -Z, in the room's frame.
func seats() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for e: Dictionary in own_entries(params):
		out.append(e["xf"])
	return out


## The model a slot style or a place takes.
func _model_for(given: String, style := "") -> String:
	var m := given if given != "" and given != "auto" else str(params.get("model", "auto"))
	if m != "auto":
		return m
	return str(STYLE_MODELS.get(style, "folding_chair"))


## Its own rows and places from parameters: [{xf, model, width, run}].
static func own_entries(p: Dictionary) -> Array:
	var out: Array = []
	var sys_model := str(p.get("model", "auto"))
	var row_model := sys_model if sys_model != "auto" else "folding_chair"
	var origin := Vector3(float(p["origin"][0]), float(p["origin"][1]), float(p["origin"][2]))
	var turn := Basis(Vector3.UP, deg_to_rad(float(p["facing"])))
	var per_row := int(p["per_row"])
	var width := model_width(row_model)
	var pitch := float(p["pitch"]) if float(p["pitch"]) > 0.0 else width
	var aisle := float(p["aisle"])
	if per_row > 0:
		for row in range(-int(p["rows_back"]), int(p["rows_front"]) + 1):
			var z := -row * float(p["row_depth"])
			var y := -row * float(p["row_rise"])
			for k in per_row:
				var x := (k - (per_row - 1) * 0.5) * pitch
				if aisle > 0.0:
					x += (1.0 if float(k) >= (per_row - 1) * 0.5 else -1.0) * aisle * 0.5
				var side := 0 if x < 0.0 else 1
				out.append({"xf": Transform3D(turn, origin + turn * Vector3(x, y, z)), "model": row_model,
						"width": pitch if bool(MODELS[row_model]["segment"]) else width,
						"run": "own:%d:%d" % [row, side], "own": true})
	for pl: Variant in p.get("places", []):
		if not (pl is Dictionary):
			continue
		var m := str((pl as Dictionary).get("model", "auto"))
		if m == "auto":
			m = row_model
		var at: Array = pl.get("at", [0.0, 0.0, 0.0])
		out.append({"xf": Transform3D(Basis(Vector3.UP, deg_to_rad(float(pl.get("turn", 0.0)))),
				Vector3(float(at[0]), float(at[1]), float(at[2]))), "model": m, "width": model_width(m),
				"run": "", "own": true})
	return out


func _ensure() -> void:
	if not _built:
		_build()


## Everything is built once the room's other systems are (their seats() and slots are ready then): at the first
## room move or frame.
func _build() -> void:
	_built = true
	_entries.clear()
	_covered.clear()
	_folded = -1
	for e: Dictionary in own_entries(params):
		e["form"] = ""
		_entries.append(e)
	if bool(params["from_builders"]):
		for bsys: Node in host.systems_of_kind("builder"):
			if not bsys.has_method("seat_slots"):
				continue
			for slot: Dictionary in bsys.call("seat_slots"):
				var m := _model_for("", str(slot.get("style", "chair")))
				_entries.append({"xf": slot["transform"], "model": m,
						"width": float(slot.get("width", model_width(m))), "form": "", "own": false,
						"run": "%s:%s" % [str(bsys.get("id")), str(slot.get("row", 0))], "slot": [bsys, 0]})
	_tips()
	_broken()
	_draw()


## Tip-up seats left tipped up: `tipped` of them, by the seed.
func _tips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params["seed"]) + 7
	var share := float(params["tipped"])
	for e: Dictionary in _entries:
		var roll := rng.randf()
		if "up" in MODELS[e["model"]]["forms"] and roll < share:
			e["form"] = "up"


## Broken seats: the room's seat list, system by system; ours take the broken form, a builder's own is covered.
func _broken() -> void:
	_mark(params["broken"], "broken")
	_mark(params["up"], "up")


## Room seats (by index in the room's seat list) drawn in this form: ours take it, a builder's own is covered.
func _mark(wanted: Array, form: String) -> void:
	if wanted.is_empty():
		return
	var count := 0
	for s: Node in host.order:
		if not s.has_method("seats"):
			continue
		var list: Array = s.call("seats")
		for idx: Variant in wanted:
			var i := int(idx) - count
			if i < 0 or i >= list.size():
				continue
			if s == self:
				_own_broken(i, form)
			elif s.has_method("seat_slots"):
				_slot_broken(s, i, form)
			else:
				_cover(s, i, list[i], form)
		count += list.size()


func _can_break(model: String, form := "broken") -> bool:
	return form in MODELS.get(model, {}).get("forms", [])


func _own_broken(i: int, form := "broken") -> void:
	var k := 0
	for e: Dictionary in _entries:
		if bool(e["own"]):
			if k == i and _can_break(e["model"], form):
				e["form"] = form
			k += 1


func _slot_broken(builder: Node, i: int, form := "broken") -> void:
	var k := 0
	for e: Dictionary in _entries:
		if e.has("slot") and e["slot"][0] == builder:
			if k == i and _can_break(e["model"], form):
				e["form"] = form
			k += 1


## A builder's own seat i (its MultiMesh "Seats") folded away, and a broken (or tipped up) seat of the builder's
## model (or ours, or the multiplex's) drawn in its place.
func _cover(builder: Node, i: int, xf: Transform3D, form := "broken") -> void:
	var m := str(params["model"])
	if m == "auto":
		m = str(builder.params.get("seat_model", "multiplex")) if builder.get("params") is Dictionary else "multiplex"
	if not _can_break(m, form):
		m = "multiplex"
	var width := float(builder.params.get("seat_pitch", model_width(m))) if builder.get("params") is Dictionary \
			else model_width(m)
	var under: MultiMeshInstance3D = null
	for n: Node in builder.call("owned"):
		if n is MultiMeshInstance3D and n.name == &"Seats":
			_covered.append([n, i])
			under = n
	var e := {"xf": xf, "model": m, "width": width, "form": form, "own": false, "run": "",
			"overlay": [builder, i]}
	if under != null:
		e["under"] = under
	_entries.append(e)
	_hide_covered()


## The builder's seats under our broken ones folded away (again: the builder gives its seat back when the viewer
## leaves it). Their transforms from the builder's seats(): a MultiMesh keeps no instances without a renderer.
func _hide_covered() -> void:
	for c: Array in _covered:
		var mmi: MultiMeshInstance3D = c[0]
		if is_instance_valid(mmi) and int(c[1]) < int(mmi.get_meta("instances", mmi.multimesh.instance_count)):
			mmi.multimesh.set_instance_transform(int(c[1]), Transform3D(Basis().scaled(Vector3.ZERO),
					_covered_xf(c)))
			hides += 1


func _covered_xf(c: Array) -> Vector3:
	for e: Dictionary in _entries:
		if e.has("overlay") and int(e["overlay"][1]) == int(c[1]):
			return (e["xf"] as Transform3D).origin
	return Vector3.ZERO


func _material(part: String, model: String) -> ShaderMaterial:
	var given: Variant = params.get(part)
	var m: Dictionary = given if given is Dictionary else default_material(model, part)
	var light: Node = host.system_of_kind("light") if host != null else null
	var out: ShaderMaterial
	if light != null:
		out = light.call("from_param", m, true)
	else:
		var o := {"colour": RoomSchemaRef.to_color(m.get("color", "#808080"))}
		for k: String in ["tiling", "pleats", "pleat_depth", "spill"]:
			if m.has(k):
				o[k] = float(m[k])
		var shared := MaterialLibrary.get_material(str(m.get("library", "felt")), o)
		out = shared.duplicate() as ShaderMaterial if shared != null else ShaderMaterial.new()
	if part == "upholstery":
		out.set_shader_parameter("instance_tint", true)
		if model == "hide":
			# Fur's soft sheen at a glancing look (since 2026-11-08: "a little sheen", the coordinator).
			out.set_shader_parameter("sheen", 0.2)
	return out


## A broken seat over a builder's own: the builder's seat materials (its upholstery: the one tinted per seat), so it
## matches its neighbours and brings no textures of its own. A material given in params wins; `fallback` when the
## builder's seat has no such surface.
func _under_materials(under: MultiMeshInstance3D, fallback: Array) -> Array:
	var out := fallback.duplicate()
	var mesh: Mesh = under.multimesh.mesh if is_instance_valid(under) and under.multimesh != null else null
	if mesh == null:
		return out
	var tinted: Material = null
	var other: Material = null
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("instance_tint") == true:
			tinted = m if tinted == null else tinted
		elif m != null and other == null:
			other = m
	if not (params.get("upholstery") is Dictionary) and tinted != null:
		out[0] = tinted
	if not (params.get("frame") is Dictionary) and other != null:
		out[1] = other
	return out


func _draw() -> void:
	_groups.clear()
	_names_used.clear()
	var mats := {}
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var key := "%s|%s|%d" % [e["model"], e["form"], roundi(float(e["width"]) * 100.0)]
		if e.has("under"):
			key += "|%d" % (e["under"] as Object).get_instance_id()
		if not _groups.has(key):
			_groups[key] = {"entries": [], "model": e["model"], "form": e["form"], "width": float(e["width"]),
					"under": e.get("under")}
		_groups[key]["entries"].append(i)
		e["group"] = key
		e["instance"] = (_groups[key]["entries"] as Array).size() - 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(params["seed"])
	var k := float(params["variation"])
	var tints: Array[Color] = []
	for i in _entries.size():
		var v := lerpf(0.98, rng.randf_range(0.86, 1.1), k)
		var warm := rng.randf_range(-0.04, 0.04) * k
		tints.append(Color(v * (1.0 + warm), v, v * (1.0 - warm)))
	# A settee is one piece of furniture: its places take no tint of their own, so they match each other and its arms.
	for i in _entries.size():
		if _entries[i]["model"] == "settee":
			tints[i] = Color(1, 1, 1)
	for key: String in _groups:
		var g: Dictionary = _groups[key]
		var model := str(g["model"])
		if not mats.has(model):
			mats[model] = [_material("upholstery", model), _material("frame", model)]
		var pair: Array = mats[model]
		if g["under"] != null:
			pair = _under_materials(g["under"], pair)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = model_mesh(model, pair[0], pair[1], float(g["width"]), str(g["form"]))
		var list: Array = g["entries"]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, _entries[list[j]]["xf"])
			mm.set_instance_color(j, tints[list[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Seats" + ("" if g["form"] == "" else str(g["form"]).capitalize()) + _suffix(key)
		mmi.multimesh = mm
		# Read by the checks (a MultiMesh keeps no instances without a renderer).
		mmi.set_meta("instances", list.size())
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		own(mmi)
		g["node"] = mmi
	_draw_ends(mats)


## Each group's node gets its own name: the first "Seats", then "Seats2", ...
var _names_used := {}


func _suffix(key: String) -> String:
	var base := key.split("|")[1]
	var n := int(_names_used.get(base, 0)) + 1
	_names_used[base] = n
	return "" if n == 1 else str(n)


## The ends of every run of segments (a pew, a bench): one static mesh.
func _draw_ends(mats: Dictionary) -> void:
	var runs := {}
	var order: Array = []
	for e: Dictionary in _entries:
		if not bool(MODELS[e["model"]]["segment"]):
			continue
		var key := str(e["run"])
		if not runs.has(key):
			runs[key] = []
			order.append(key)
		runs[key].append(e)
	if runs.is_empty():
		return
	var b := RoomMesh.new()
	for key: String in order:
		var list: Array = runs[key]
		# A run breaks where neighbours stand more than 1.5 widths apart (an aisle).
		var start := 0
		for i in range(1, list.size() + 1):
			var cut := i == list.size()
			if not cut:
				var w := float(list[i]["width"])
				cut = (list[i]["xf"] as Transform3D).origin.distance_to((list[i - 1]["xf"] as Transform3D).origin) > 1.5 * w
			if cut:
				var first: Dictionary = list[start]
				var last: Dictionary = list[i - 1]
				var m: Array = mats[first["model"]]
				end_piece(b, first["model"], first["xf"], float(first["width"]), -1.0, m[1], m[0])
				end_piece(b, last["model"], last["xf"], float(last["width"]), 1.0, m[1], m[0])
				start = i
	var mesh := b.commit(false)
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "SeatEnds"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	own(mi)


# --- Hooks ---------------------------------------------------------------------------------------------------------------

## Object physics: every seat it draws as its model's boxes (a covered builder's seat keeps the builder's).
func collision_shapes() -> Array:
	_ensure()
	var out: Array = []
	for e: Dictionary in _entries:
		if e.has("overlay"):
			continue
		out.append_array(model_boxes(e["model"], e["xf"], float(e["width"])))
	return out


func on_room_moved() -> void:
	_ensure()
	_fold_own()
	# After every system has had the move (a builder before or after this one gives its seat back first).
	_hide_covered.call_deferred()


func tick(_delta: float) -> void:
	_ensure()


## The chair the viewer sits in (the room moved so it is at the origin) is folded away; pews, benches, cushions,
## hides and bean bags stay.
func _fold_own() -> void:
	if not room.is_inside_tree():
		return
	var here := room.global_transform.affine_inverse() * Vector3.ZERO
	var found := -1
	if bool(params["fold_own"]):
		for i in _entries.size():
			var o := (_entries[i]["xf"] as Transform3D).origin
			if Vector2(o.x - here.x, o.z - here.z).length() < 0.2 and absf(o.y - here.y) < 0.2 \
					and bool(MODELS[_entries[i]["model"]]["fold"]):
				found = i
				break
	if found == _folded:
		return
	if _folded >= 0:
		_set_instance(_folded, _entries[_folded]["xf"])
	if found >= 0:
		_set_instance(found, (_entries[found]["xf"] as Transform3D).scaled_local(Vector3.ZERO))
	_folded = found


func _set_instance(i: int, xf: Transform3D) -> void:
	var e: Dictionary = _entries[i]
	e["shown"] = xf
	var g: Dictionary = _groups[e["group"]]
	(g["node"] as MultiMeshInstance3D).multimesh.set_instance_transform(int(e["instance"]), xf)


# --- Tests -------------------------------------------------------------------------------------------------------------

## What it draws: [{model, form, xf, own}] (tests).
func drawn() -> Array:
	_ensure()
	return _entries.map(func(e: Dictionary) -> Dictionary: return {"model": e["model"], "form": e["form"],
			"xf": e["xf"], "own": e["own"], "group": e.get("group", "")})


## The seat folded away (an index into drawn()), -1 none.
func folded() -> int:
	return _folded


## The MultiMeshInstance3D a drawn seat is in.
func node_of(i: int) -> MultiMeshInstance3D:
	_ensure()
	return _groups[_entries[i]["group"]]["node"]


func instance_of(i: int) -> int:
	return int(_entries[i]["instance"])


## The transform a drawn seat's instance was last given (a MultiMesh keeps none without a renderer).
func shown(i: int) -> Transform3D:
	return _entries[i].get("shown", _entries[i]["xf"])


## The builder's seats folded away under broken ones: [[MultiMeshInstance3D, instance]].
func covered() -> Array:
	return _covered
