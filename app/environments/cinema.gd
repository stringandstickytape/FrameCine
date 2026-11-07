extends "res://scripts/env/env_room.gd"

## The cinema: a stadium-seated auditorium, the flagship room. A version 4 room document
## (environments/cinema.env.json, docs/environments.md "The converted cinema") built by the environments engine's
## systems: the light system (house materials, lamps, the bake's lights), the auditorium builder (its defaults are this
## room), the screen's frame (masking, the projector's beam) and the showing (the curtains in the ritual). Until
## 2026-11-07 it was 1000 lines of code; that version is kept as tests/fixtures/cinema_v3.gd, which the render
## comparison (tests/test_env_cinema_render.gd) draws against this one.
##
## The names below are the hall's layout as the document makes it, for the tests and the tools that read the cinema's
## rows without building it (tests/test_cinema.gd, test_physics.gd).

const Auditorium := preload("res://scripts/env/systems/auditorium.gd")
const DOC := "res://environments/cinema.env.json"
const SEAT_BOX_CENTRE := Auditorium.SEAT_BOX_CENTRE
const SEAT_BOX_SIZE := Auditorium.SEAT_BOX_SIZE
const SEAT_BACK_PIVOT := Auditorium.SEAT_BACK_PIVOT
const SEAT_BACK_TILT_DEG := Auditorium.SEAT_BACK_TILT_DEG
const SEAT_BACK_CENTRE := Auditorium.SEAT_BACK_CENTRE
const SEAT_BACK_SIZE := Auditorium.SEAT_BACK_SIZE

## The auditorium's parameters, the document's over the builder's defaults.
static var HALL := _hall()
static var ROWS_FRONT: int = int(HALL["rows_front"])
static var ROWS_BACK: int = int(HALL["rows_back"])
static var SEATS_PER_ROW: int = int(HALL["seats_per_row"])
static var ROW_DEPTH: float = float(HALL["row_depth"])
static var ROW_RISE: float = float(HALL["row_rise"])


static func _hall() -> Dictionary:
	var d := load_doc(DOC)
	for entry: Dictionary in d.get("systems", []):
		if entry["system"] == "auditorium":
			return EnvDoc.with_defaults(Auditorium.PARAMS, entry.get("params", {}))
	return EnvDoc.with_defaults(Auditorium.PARAMS, {})


func _init() -> void:
	if document == "":
		document = DOC


## Every seat: the floor point under the seated eyes and its facing, by row from the back, left to right.
static func seat_transforms() -> Array[Transform3D]:
	return Auditorium.layout(HALL).seat_transforms()
