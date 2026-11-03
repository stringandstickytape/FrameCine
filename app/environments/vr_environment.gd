extends Node3D

## Common interface of the environments (scenes in this folder). An environment is cheap unlit geometry around the
## viewer, who sits at the origin facing -Z with the floor at y = 0. It tells the app:
##   - where the screen goes by default: the ScreenAnchor marker (centre of the screen, facing +Z) and
##     default_screen_width. Marker heights assume a seated eye height of NOMINAL_EYE_HEIGHT; the app keeps the
##     screen's offset from the viewer's real eye height.
##   - its light: ambient_level (brightness of its surfaces with a dark screen) and screen_glow (how much the screen
##     lights them), applied through the global shader parameters env_light / screen_glow that env_unlit.gdshader
##     and grid.gdshader read. No lights, shadows, GI or post-processing anywhere.
## on_screen_changed() lets an environment fit itself to the screen (the cinema moves its masking border).

const NOMINAL_EYE_HEIGHT := 1.2

@export var display_name := "Void"
@export_range(0.0, 1.0) var ambient_level := 0.0
@export_range(0.0, 2.0) var screen_glow := 0.0
@export var default_screen_width := 3.0
@export var screen_anchor: Marker3D
## The room's light flashes with loud moments in the film (scripts/env/film_react.gd, ideas #81), when that is on.
@export var reacts_to_film := false


func get_screen_anchor() -> Transform3D:
	if screen_anchor != null:
		return screen_anchor.transform
	return Transform3D(Basis(), Vector3(0, NOMINAL_EYE_HEIGHT, -3))


## {width, distance, height_offset}: the default screen relative to the viewer.
func get_default_screen() -> Dictionary:
	var anchor := get_screen_anchor()
	return {
		"width": default_screen_width,
		"distance": Vector2(anchor.origin.x, anchor.origin.z).length(),
		"height_offset": anchor.origin.y - NOMINAL_EYE_HEIGHT,
	}


## Light level: ambient_level scaled by the user's room light setting (0..2, 1 = as designed).
func apply_light(user_scale: float) -> void:
	RenderingServer.global_shader_parameter_set("env_light", ambient_level * user_scale)
	RenderingServer.global_shader_parameter_set("screen_glow", screen_glow * user_scale)


## The screen moved or resized (flat mode). screen_transform: centre, facing +Z; size in metres.
func on_screen_changed(_screen_transform: Transform3D, _size: Vector2) -> void:
	pass
