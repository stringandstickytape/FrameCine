extends "res://scripts/env/primitive_room.gd"

## A drive-in at night (ideas #52): you sit in a car (dashboard, bonnet, windscreen pillars) in the middle row of a lot,
## the big screen on its frame across the lot, other cars around, speaker posts, a projection booth behind, a dark sky
## with a dusk band low down and stars. Unlit; the screen's spill lights the cars nearest to it.
## set_time_of_day(sun elevation) changes the sky, the horizon band, the stars and the lot's light (ideas #84,
## scripts/env/time_of_day.gd); -90, the default, is the night as designed.

const SKY_RADIUS := 150.0
## Colours as shown on screen (sRGB) for night, dusk and day.
const SKY_NIGHT := Color(0.01, 0.012, 0.024)
const SKY_DUSK := Color(0.1, 0.12, 0.26)
const SKY_DAY := Color(0.42, 0.6, 0.9)
const BAND_NIGHT := Color(0.036, 0.022, 0.018)
const BAND_DUSK := Color(0.85, 0.42, 0.22)
const BAND_DAY := Color(0.7, 0.78, 0.9)
const AMBIENT_NIGHT := 0.04
const AMBIENT_DUSK := 0.12
const AMBIENT_DAY := 0.9
const STARS := Color(0.85, 0.85, 0.95)

var sun_elevation := -90.0
var _sky_mat: ShaderMaterial
var _band_mat: ShaderMaterial
var _star_mat: StandardMaterial3D
var _stars: Node3D


func _build() -> void:
	# Under an open sky: thunder in the film flashes the lot (scripts/env/film_react.gd, ideas #81).
	reacts_to_film = true
	var asphalt := material(Color(0.1, 0.1, 0.11), 0.6, 0.0)
	var ground := PlaneMesh.new()
	ground.size = Vector2(300, 300)
	add_mesh("Ground", ground, Transform3D(), asphalt)

	# Sky: a dark dome, a lighter band at the horizon, stars.
	var sky := SphereMesh.new()
	sky.radius = SKY_RADIUS
	sky.height = SKY_RADIUS * 2.0
	sky.flip_faces = true
	_sky_mat = material(Color(0.25, 0.3, 0.6), 0.0, 0.0)
	add_mesh("Sky", sky, Transform3D(), _sky_mat)
	var band := CylinderMesh.new()
	band.top_radius = SKY_RADIUS - 2.0
	band.bottom_radius = SKY_RADIUS - 2.0
	band.height = 14.0
	band.flip_faces = true
	band.cap_top = false
	band.cap_bottom = false
	_band_mat = material(Color(0.9, 0.55, 0.45), 0.0, 0.0)
	add_mesh("DuskBand", band, Transform3D(Basis(), Vector3(0, 7, 0)), _band_mat)
	var star := SphereMesh.new()
	star.radius = 0.35
	star.height = 0.7
	star.radial_segments = 4
	star.rings = 2
	var stars: Array[Transform3D] = []
	for p in sky_points(500, 0.12):
		stars.append(Transform3D(Basis(), p * (SKY_RADIUS - 4.0)))
	_star_mat = glow(STARS)
	_stars = add_multimesh("Stars", star, stars, _star_mat)

	# The screen's frame and legs (the picture itself is the app's screen at the anchor).
	var a := get_screen_anchor().origin
	var frame := material(Color(0.32, 0.32, 0.34), 1.0, 0.0)
	add_box("ScreenBack", Vector3(24, 13, 0.4), Vector3(a.x, a.y, a.z - 0.4), frame)
	for x in [-10.0, -4.0, 4.0, 10.0]:
		add_box("Leg", Vector3(0.5, a.y, 0.5), Vector3(x, a.y * 0.5, a.z - 0.8), frame)

	# Our car: dashboard, bonnet, pillars, the roof's front edge.
	var car := material(Color(0.25, 0.05, 0.05), 0.8, 0.0)
	var dash := material(Color(0.06, 0.06, 0.07), 0.5, 0.0)
	add_box("Dashboard", Vector3(1.6, 0.25, 0.45), Vector3(0, 0.78, -0.75), dash)
	add_box("Bonnet", Vector3(1.75, 0.3, 1.8), Vector3(0, 0.68, -1.9), car)
	for side in [-1.0, 1.0]:
		add_box("Pillar", Vector3(0.08, 0.75, 0.08), Vector3(0.78 * side, 1.25, -0.62), car,
				Basis(Vector3.RIGHT, deg_to_rad(-30.0)))
	add_box("RoofEdge", Vector3(1.65, 0.08, 0.3), Vector3(0, 1.6, -0.35), car)

	# Other cars: rows facing the screen, a gap where ours is.
	var body := BoxMesh.new()
	body.size = Vector3(1.8, 0.75, 4.3)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.6, 0.55, 2.2)
	var bodies: Array[Transform3D] = []
	var cabins: Array[Transform3D] = []
	var posts: Array[Transform3D] = []
	for row in range(-2, 4):
		var z := 0.4 - row * 7.0
		for col in range(-4, 5):
			var x := col * 3.2
			if row == 0 and col == 0:
				continue
			bodies.append(Transform3D(Basis(), Vector3(x, 0.55, z)))
			cabins.append(Transform3D(Basis(), Vector3(x, 1.2, z + 0.4)))
		for col in range(-4, 5):
			posts.append(Transform3D(Basis(), Vector3(col * 3.2 + 1.6, 0.6, z - 0.6)))
	add_multimesh("CarBodies", body, bodies, material(Color(0.2, 0.22, 0.28), 1.0, 0.0))
	add_multimesh("CarCabins", cabin, cabins, material(Color(0.08, 0.09, 0.11), 1.0, 0.0))
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.2, 0.12)
	add_multimesh("SpeakerPosts", post, posts, material(Color(0.3, 0.3, 0.3), 0.6, 0.0))

	# The projection booth behind, its window lit; a few lamps along the lot's edge.
	add_box("Booth", Vector3(8, 4, 5), Vector3(0, 2, 28), material(Color(0.22, 0.2, 0.18), 0.3, 0.0))
	add_box("BoothWindow", Vector3(1.2, 0.6, 0.05), Vector3(0, 2.6, 25.45), glow(Color(1.0, 0.9, 0.7)))
	var lamp := SphereMesh.new()
	lamp.radius = 0.3
	lamp.height = 0.6
	var lamps: Array[Transform3D] = []
	var lamp_posts: Array[Transform3D] = []
	for x in [-18.0, 18.0]:
		for z in [-25.0, -10.0, 5.0, 20.0]:
			lamps.append(Transform3D(Basis(), Vector3(x, 6.0, z)))
			lamp_posts.append(Transform3D(Basis.from_scale(Vector3(1, 5, 1)), Vector3(x, 3.0, z)))
	add_multimesh("Lamps", lamp, lamps, glow(Color(1.0, 0.8, 0.5)))
	add_multimesh("LampPosts", post, lamp_posts, material(Color(0.2, 0.2, 0.2), 0.0, 0.0))


## The albedo (sRGB, as the material takes it) that shows `colour` (sRGB) at this room's ambient level.
func shown_albedo(colour: Color) -> Color:
	var lin := colour.srgb_to_linear()
	return Color(lin.r / ambient_level, lin.g / ambient_level, lin.b / ambient_level).linear_to_srgb()


## The sky for the sun at `elevation` degrees (ideas #84): night below -12, twilight and dusk around the horizon (the
## band glows warm between about -6 and +4), day above about 10. -90 restores the night as designed.
func set_time_of_day(elevation: float) -> void:
	sun_elevation = elevation
	if elevation <= -89.0:
		ambient_level = AMBIENT_NIGHT
		_sky_mat.set_shader_parameter("albedo", Color(0.25, 0.3, 0.6))
		_band_mat.set_shader_parameter("albedo", Color(0.9, 0.55, 0.45))
		_star_mat.albedo_color = STARS
		_stars.visible = true
		return
	var dusk := smoothstep(-12.0, -2.0, elevation)
	var day := smoothstep(-2.0, 10.0, elevation)
	var glow_k := clampf(1.0 - absf(elevation + 1.0) / 6.0, 0.0, 1.0)
	ambient_level = lerpf(lerpf(AMBIENT_NIGHT, AMBIENT_DUSK, dusk), AMBIENT_DAY, day)
	var sky := SKY_NIGHT.lerp(SKY_DUSK, dusk).lerp(SKY_DAY, day)
	var band := BAND_NIGHT.lerp(BAND_DAY, day).lerp(BAND_DUSK, glow_k)
	# The materials multiply by the room's light (ambient), in linear light, and their albedo is an sRGB colour:
	# divide the ambient out in linear light so the sky shows the colour above.
	_sky_mat.set_shader_parameter("albedo", shown_albedo(sky))
	_band_mat.set_shader_parameter("albedo", shown_albedo(band))
	_star_mat.albedo_color = STARS * (1.0 - dusk)
	_stars.visible = dusk < 0.98
