extends "res://environments/vr_environment.gd"

## The dim room (dim_room.tscn): a plain box around you with a grid floor. Its walls and ceiling get the smooth plaster
## of the material library (docs/materials.md) in the scene's own colour and light; the grid floor stays. Without the
## library, and in an assistant's lit room (which relights plain materials only), the scene's plain material shows.

const MaterialLibrary := preload("res://scripts/env/material_library.gd")

const WALLS := Color(0.42, 0.4, 0.38)


func _ready() -> void:
	var room := get_node_or_null("Room") as MeshInstance3D
	if room != null and not MaterialLibrary.in_lit_room(self):
		MaterialLibrary.apply(room, "smooth_plaster", {"colour": WALLS, "spill": 1.0, "floor_darkening": 0.35})
