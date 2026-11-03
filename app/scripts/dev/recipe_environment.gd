extends "res://environments/vr_environment.gd"

## The root script of a scene recipe (recipes.gd; docs/recipes.md): an environment made of a base environment
## (the child "Base", an instance of void, dim room or cinema) and what was built over the dev link (the child
## "Built"). The screen anchor and the light come from the moment it was saved. The base still follows the screen
## (the cinema's masking border).


func on_screen_changed(screen_transform: Transform3D, size: Vector2) -> void:
	var base := get_node_or_null("Base")
	if base != null and base.has_method("on_screen_changed"):
		base.on_screen_changed(screen_transform, size)
