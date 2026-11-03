extends "res://environments/vr_environment.gd"

## The dim room (dim_room.tscn): a plain box around you with a grid floor. Its walls and ceiling get the smooth plaster
## of the material library (docs/materials.md) in the scene's own colour and light; the grid floor stays. Without the
## library, the scene's plain material shows; in an assistant's lit room the plaster is lit there (its lit form).

const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const WALLS := Color(0.42, 0.4, 0.38)


## Spatial audio: the box of dim_room.tscn's Room (8 x 3 x 8 m), bare plaster: the liveliest of the rooms.
func get_sound_room() -> Dictionary:
	return {"box": AABB(Vector3(-4, 0, -4.6), Vector3(8, 3, 8)), "reflect": 0.6, "rt60": 0.55, "wet": 0.55,
			"surround_height": 1.6}


func _ready() -> void:
	var room := get_node_or_null("Room") as MeshInstance3D
	if room != null:
		MaterialLibrary.apply(room, "smooth_plaster", {"colour": WALLS, "spill": 1.0, "floor_darkening": 0.35})
