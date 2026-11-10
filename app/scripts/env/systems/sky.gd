extends "res://scripts/env/systems/env_system.gd"

## The sky (docs/environments.md, "The sky"): a dome round the viewer with a twilight to night gradient, the real stars
## (environments/sky/bright_stars.json, the bright stars of the public-domain catalogue, and a generated field of faint
## ones) where they stand for a latitude, a day and a time, the constellations' lines if asked for, the Milky Way where
## the galaxy really lies, clouds lit by the screen, an aurora, shooting stars, and Earth as seen from the Moon,
## turning slowly. Mode black draws nothing (the Void's black, as before).
##
## Every layer is drawn round the camera at 175 to 190 m (the camera's far plane is 200), so walls, the screen and
## the vista always stand in front of it, and it never moves with the room's seat. Nothing here moves the viewer or the
## horizon: the stars turn with the time of day (a track or a cue moves `hour`), clouds drift, the aurora waves and
## Earth spins on its axis, each slowly and each a `motion` parameter (the room's Motion setting scales it).
## Shaders: shaders/env_sky.gdshader (the dome: gradient, Milky Way, clouds, aurora, shooting stars), env_sky_stars,
## env_sky_lines, env_sky_earth, sharing env_sky_common.gdshaderinc. vista.gd reads sky_light() to light its scenery.

const DOME_SHADER := preload("res://shaders/env_sky.gdshader")
const STAR_SHADER := preload("res://shaders/env_sky_stars.gdshader")
const LINE_SHADER := preload("res://shaders/env_sky_lines.gdshader")
const EARTH_SHADER := preload("res://shaders/env_sky_earth.gdshader")
const EARTH_DETAIL_SHADER := preload("res://shaders/env_sky_earth_detail.gdshader")
const EarthMap := preload("res://scripts/env/systems/kit/earth_map.gd")
const MOON_SHADER := preload("res://shaders/env_sky_moon.gdshader")
const ProcCache := preload("res://scripts/env/proc_cache.gd")
## The Moon's layer: nearer than the stars (it hides them), beyond Earth's. Its quad reaches HALO times its radius,
## for the halo round it.
const MOON_RADIUS := 178.0
const MOON_HALO := 3.0
## How much of its road on water the Moon keeps under a sky still light (`dusk` 0), against a night's (moon_shine()).
const MOON_ROAD_IN_TWILIGHT := 0.3
const CATALOGUE := "res://environments/sky/bright_stars.json"
const DOME_RADIUS := 190.0
const STAR_RADIUS := 185.0
const LINE_RADIUS := 184.0
const EARTH_RADIUS := 175.0
## Equatorial (J2000) to galactic coordinates (the IAU's rotation): x to the galaxy's centre, z to its north pole.
const GALACTIC := Basis(Vector3(-0.0548755604, 0.4941094279, -0.8676661490),
		Vector3(-0.8734370902, -0.4448296300, -0.1980763734), Vector3(-0.4838350155, 0.7469822445, 0.4559837762))
## The local sidereal time at 0 h local mean time on 1 January (hours), and its gain a day.
const LST_JAN1 := 6.664
const LST_PER_DAY := 0.0657098
const SIDEREAL_RATE := 1.0027379
## A star's quad: its half size in degrees at magnitude 6, and how much it grows a magnitude brighter (to 4 or so).
const STAR_SIZE := 0.075
const STAR_GROW := 0.04
## The faint field is generated from this seed: the same sky every time.
const FIELD_SEED := 1928
const SHOOTING_SECONDS := 0.9
## Earth's axial tilt (degrees), so it looks like itself.
const EARTH_TILT := 23.4
## The fastest the stars may turn when `hour` changes (a track, a cue, a setting): an hour of sky a minute, 0.25 degrees
## a second (sixty times the real speed), scaled by the room's Motion setting. A larger change is eased to, never
## jumped or spun.
const MAX_HOURS_PER_SECOND := 1.0 / 60.0
const MODES: Array[String] = ["sky", "space", "black"]


static func spec() -> Dictionary:
	var compass := func(d: float, what: String) -> Dictionary:
		return {"type": "float", "min": 0.0, "max": 360.0, "default": d, "description": what}
	return {
		"kind": "sky",
		"description": "A sky dome round the viewer: twilight to night, the real stars for a latitude, day and time "
				+ "(constellation lines if asked), the Milky Way where it really lies, clouds lit by the screen, an "
				+ "aurora, shooting stars, and Earth turning as seen from the Moon. Mode black draws nothing.",
		"params": {
			"mode": {"type": "enum", "values": MODES, "default": "sky",
					"description": "sky: air, a gradient from twilight to night; space: black, the stars at full (the "
					+ "Moon); black: nothing drawn (the Void)"},
			"latitude": {"type": "float", "min": -90.0, "max": 90.0, "default": 40.0,
					"description": "degrees north (negative: south): where the stars stand"},
			"day_of_year": {"type": "float", "min": 1.0, "max": 366.0, "default": 200.0,
					"description": "the day of the year (1 is 1 January; 200 is mid July)"},
			"hour": {"type": "float", "min": 0.0, "max": 24.0, "default": 22.0, "live": true,
					"description": "local time in hours (mean solar time, no summer time): the stars turn with it; "
					+ "a film-time track can turn them over the film. They turn at most an hour of sky a minute"},
			"facing": compass.call(180.0, "the compass bearing the room's front (the screen) faces: 0 north, 90 "
					+ "east, 180 south"),
			"dusk": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "how far dusk has fallen: 0 the last light of the evening, 1 full night (a "
					+ "film-time track takes it from dusk to stars)"},
			"night_zenith": {"type": "color", "default": "#070a16", "description": "the night sky overhead"},
			"night_horizon": {"type": "color", "default": "#151b2e", "description": "the night sky at the horizon"},
			"twilight_zenith": {"type": "color", "default": "#2b4079", "description": "the twilight sky overhead"},
			"twilight_horizon": {"type": "color", "default": "#d48a5c",
					"description": "the twilight sky at the horizon"},
			"glow": {"type": "color", "default": "#ff8a3c",
					"description": "the sunset's glow low over the horizon (it fades as dusk falls)"},
			"glow_bearing": compass.call(300.0, "where the sun went down (compass bearing)"),
			"ground": {"type": "color", "default": "#0a0a0c", "description": "below the horizon"},
			"stars": {"type": "float", "min": 0.0, "max": 1.0, "default": 1.0, "live": true, "brightness": true,
					"description": "how bright the stars are (they also hide in the twilight and behind clouds)"},
			"faint_stars": {"type": "int", "min": 0, "max": 4000, "default": 1600,
					"description": "how many faint stars (generated, thicker along the Milky Way) besides the "
					+ "catalogue's bright ones"},
			"twinkle": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "a slow, small twinkle (under 1 Hz); off by default for comfort"},
			"lines": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "the constellations' lines, faint, as a planetarium shows them; 0: none"},
			"line_colour": {"type": "color", "default": "#6f8fd0", "description": "the lines' colour"},
			"milky_way": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6, "live": true, "brightness": true,
					"description": "the Milky Way's brightness (bind it to playback.playing to show it as the "
					+ "lights dim)"},
			"milky_colour": {"type": "color", "default": "#e6dccb", "description": "the Milky Way's colour"},
			# Since 2026-11-08 (the drive-in: "the sky's change from sunset glow to a deep starfield with the Milky Way
			# rising is the star of the show", the brief). Each 0 by default: the sky as before.
			"milky_detail": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
					"description": "the Milky Way's finer structure: dust lanes, star clouds, a warmer bulge (0: the "
					+ "soft band)"},
			"afterglow": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
					"description": "the twilight's structure: the warm light in a thin band at the horizon, and "
					+ "opposite the sunset the Earth's shadow under the pink belt of Venus (0: the plain gradient)"},
			"belt_colour": {"type": "color", "default": "#9e5c6b", "description": "the belt of Venus's pink"},
			"evening_star": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
					"description": "a bright planet low over the sunset's glow at the start (it sets with the sky as "
					+ "the hours turn); 0: none"},
			"clouds": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "how much of the sky the clouds cover; 0: a clear sky"},
			"cloud_colour": {"type": "color", "default": "#3a3e48", "live": true,
					"description": "the clouds' own colour in the night (bind it to film.colour with a strength)"},
			"cloud_screen": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0, "live": true,
					"brightness": true, "description": "how much the clouds towards the screen catch its light, in "
					+ "the picture's colour"},
			"wind": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true, "motion": {"max": 1.0},
					"description": "how fast the clouds drift (1 is a breezy night)"},
			"wind_from": compass.call(270.0, "where the wind comes from (compass bearing)"),
			"aurora": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "an aurora's brightness (bind it to film.quiet, smoothed, to swell in quiet "
					+ "scenes)"},
			"aurora_low": {"type": "color", "default": "#5cff9e", "description": "the aurora's colour low down"},
			"aurora_high": {"type": "color", "default": "#b46ee0", "description": "its colour high up"},
			"aurora_bearing": compass.call(0.0, "where the aurora hangs (compass bearing; 0, the north)"),
			"aurora_speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "live": true,
					"motion": {"max": 1.0}, "description": "how fast its curtains wave and drift"},
			"meteors": {"type": "float", "min": 0.0, "max": 30.0, "default": 0.0, "live": true,
					"description": "shooting stars an hour, at random (the action shooting_star sends one)"},
			"earth": {"type": "bool", "default": false, "description": "Earth in the sky, as seen from the Moon"},
			"earth_bearing": compass.call(180.0, "where Earth hangs (compass bearing)"),
			"earth_altitude": {"type": "float", "min": 0.0, "max": 90.0, "default": 35.0,
					"description": "Earth's height over the horizon in degrees"},
			"earth_size": {"type": "float", "min": 0.5, "max": 12.0, "default": 2.0,
					"description": "Earth's size across in degrees (from the Moon it is about 1.9)"},
			"earth_phase": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.65,
					"description": "how much of Earth's face is lit: 0 new, 1 full"},
			"earth_angle": {"type": "float", "min": -3600.0, "max": 3600.0, "default": 0.0, "live": true,
					"description": "how far Earth has turned on its axis, in degrees (a film-time track can turn it "
					+ "over the film)"},
			"earth_turn": {"type": "float", "min": 0.0, "max": 60.0, "default": 1.0, "live": true,
					"motion": {"max": 60.0}, "description": "Earth's own turning, in times its real speed (1: once a "
					+ "day; 60: once in 24 minutes)"},
			# Since 2026-11-08, for the Crater ("Earth is the jewel", the brief). Off: Earth as before.
			"earth_detail": {"type": "bool", "default": false,
					"description": "Earth as itself: its continents, deserts and ice from a small map, cloud bands, "
					+ "the sun's glint on the oceans, a thin blue atmosphere round the limb, the cities' lights on "
					+ "the night side (off: the plain Earth-like world)"},
			"earth_light_angle": {"type": "float", "min": -180.0, "max": 180.0, "default": 0.0,
					"description": "where the sunlight comes from round Earth's face, in degrees from its right "
					+ "(90: from above; -90: from below, the sun under the horizon behind the viewer)"},
			"earth_lights": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "live": true,
					"brightness": true, "description": "earth_detail: the cities' lights on the night side"},
			# Since 2026-11-08, for the Atmospheric 1928 ("perhaps a crescent moon over the wall"; clouds "lit warm
			# from below by the house"). Every other room keeps its sky: the moon is off and the glow at 0 by default.
			"moon": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"description": "the Moon's brightness (its crescent, the faint earthshine on the rest, a soft halo, "
					+ "the clouds near it silvered); 0: no Moon"},
			"moon_bearing": compass.call(220.0, "where the Moon stands (compass bearing)"),
			"moon_altitude": {"type": "float", "min": 0.0, "max": 90.0, "default": 45.0,
					"description": "the Moon's height over the horizon in degrees"},
			"moon_size": {"type": "float", "min": 0.3, "max": 8.0, "default": 1.6,
					"description": "the Moon's size across in degrees (the real one is half a degree; a little larger "
					+ "reads in a headset)"},
			"moon_phase": {"type": "float", "min": 0.02, "max": 1.0, "default": 0.22,
					"description": "how much of the Moon's face is lit: a young crescent 0.1 to 0.3, full 1; the lit "
					+ "side faces where the sun went down (glow_bearing)"},
			"cloud_glow": {"type": "color", "default": "#ff9a52",
					"description": "the town's light on the clouds' undersides, strongest low over the walls"},
			"cloud_glow_level": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"brightness": true, "description": "how much of the town's light the clouds catch (a cue takes "
					+ "it down with the house lights); 0: none"},
		},
		"actions": {"shooting_star": "a shooting star crosses the sky (args: none)"},
		"cost": {"draws": 4, "triangles": 9000, "lights": 0, "particles": 0, "texture_mb": 0.3},
		"provides": ["sky_light"],
	}


static var _catalogue := {}
static var _noise: ImageTexture
static var _field := {}

var _dome: MeshInstance3D
var _stars: MeshInstance3D
var _lines: MeshInstance3D
var _earth: MeshInstance3D
var _moon: MeshInstance3D
var _materials: Array[ShaderMaterial] = []
var _cloud_offset := Vector2.ZERO
var _aurora_time := 0.0
var _earth_spin := 0.0
## The hour the stars show now: it follows `hour` no faster than MAX_HOURS_PER_SECOND.
var _hour_shown := 0.0
## A shooting star in flight: [from, to, age] or [].
var _meteor: Array = []
var _rng := RandomNumberGenerator.new()
## Shooting stars sent (tests).
var meteors_sent := 0


# --- The catalogue and the noise --------------------------------------------------------------------------------------

## The bright stars and lines (environments/sky/bright_stars.json), read once: {stars: {id: [ra_h, dec_deg, mag, bv]},
## order: [ids], lines: {constellation: [[id, id], ...]}}.
static func catalogue() -> Dictionary:
	if _catalogue.is_empty():
		var j := JSON.new()
		var stars := {}
		var order: Array[String] = []
		var lines := {}
		if j.parse(FileAccess.get_file_as_string(CATALOGUE)) == OK and j.data is Dictionary:
			for row: Array in j.data.get("stars", []):
				stars[str(row[0])] = [float(row[1]), float(row[2]), float(row[3]), float(row[4])]
				order.append(str(row[0]))
			lines = j.data.get("lines", {})
		else:
			push_warning("sky: the star catalogue %s could not be read" % CATALOGUE)
		_catalogue = {"stars": stars, "order": order, "lines": lines}
	return _catalogue


## A direction on the celestial sphere (equatorial frame: x to the vernal equinox, z to the north celestial pole).
static func equatorial(ra_hours: float, dec_deg: float) -> Vector3:
	var a := deg_to_rad(ra_hours * 15.0)
	var d := deg_to_rad(dec_deg)
	return Vector3(cos(d) * cos(a), cos(d) * sin(a), sin(d))


## The galactic latitude of an equatorial direction, in degrees.
static func galactic_latitude(eq: Vector3) -> float:
	return rad_to_deg(asin(clampf((GALACTIC * eq).z, -1.0, 1.0)))


## The faint field: count stars of magnitude 4 to 6.2, generated (not a catalogue), thicker towards the galaxy's
## plane, as the real faint stars are. [[direction (equatorial), magnitude, bv], ...]. Cached by count.
static func faint_field(count: int) -> Array:
	if _field.has(count):
		return _field[count]
	var rng := RandomNumberGenerator.new()
	rng.seed = FIELD_SEED
	var out: Array = []
	var lo := pow(10.0, 0.45 * 4.0)
	var hi := pow(10.0, 0.45 * 6.2)
	while out.size() < count:
		var z := rng.randf_range(-1.0, 1.0)
		var phi := rng.randf() * TAU
		var r := sqrt(1.0 - z * z)
		var e := Vector3(r * cos(phi), r * sin(phi), z)
		var b := deg_to_rad(galactic_latitude(e))
		if rng.randf() > 0.3 + 0.7 * exp(-b * b / 0.09):
			continue
		var mag := log(lo + rng.randf() * (hi - lo)) / log(10.0) / 0.45
		out.append([e, mag, clampf(rng.randfn(0.55, 0.42), -0.3, 1.8)])
	_field[count] = out
	return out


## The noise every sky layer draws from (and the vista's): 256 x 256, tiling, four kinds in r, g, b, a (big cloud,
## small cloud, the galaxy's mottling, fine streaks). Made once.
static func noise_texture() -> ImageTexture:
	if _noise != null:
		return _noise
	_noise = ImageTexture.create_from_image(ProcCache.image("sky.gd:noise_texture", _draw_noise_texture))
	return _noise


static func _draw_noise_texture() -> Image:
	var size := 256
	var chans: Array[PackedByteArray] = []
	var freqs := [0.012, 0.03, 0.022, 0.06]
	for i in 4:
		var n := FastNoiseLite.new()
		n.seed = 71 + i * 13
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = freqs[i]
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4 if i < 3 else 3
		var img := n.get_seamless_image(size, size, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var r := chans[0]
	var g := chans[1]
	var b := chans[2]
	var a := chans[3]
	for i in size * size:
		data[i * 4] = r[i]
		data[i * 4 + 1] = g[i]
		data[i * 4 + 2] = b[i]
		data[i * 4 + 3] = a[i]
	var out := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return out


## A star's colour from its B-V colour index (a blue-white to orange ramp, softened as the eye sees it).
static func star_colour(bv: float) -> Color:
	var keys := [[-0.3, Color(0.62, 0.72, 1.0)], [0.0, Color(0.8, 0.86, 1.0)], [0.4, Color(1.0, 0.97, 0.92)],
			[0.8, Color(1.0, 0.88, 0.72)], [1.2, Color(1.0, 0.8, 0.58)], [1.7, Color(1.0, 0.68, 0.44)]]
	var c: Color = keys[-1][1]
	if bv <= float(keys[0][0]):
		c = keys[0][1]
	else:
		for i in range(1, keys.size()):
			if bv <= float(keys[i][0]):
				var f := (bv - float(keys[i - 1][0])) / (float(keys[i][0]) - float(keys[i - 1][0]))
				c = (keys[i - 1][1] as Color).lerp(keys[i][1], f)
				break
	return c.lerp(Color.WHITE, 0.3)


## A star's opacity at the core by magnitude (Sirius 1, the faintest a few per cent).
static func star_intensity(mag: float) -> float:
	return clampf(pow(10.0, -0.24 * (mag - 1.5)), 0.07, 1.0)


# --- Where things are -------------------------------------------------------------------------------------------------

## The local sidereal time (hours) for a day of the year and local mean time (good to a few minutes in any year).
static func sidereal_hours(day_of_year: float, hour: float) -> float:
	return fposmod(LST_JAN1 + LST_PER_DAY * (day_of_year - 1.0) + SIDEREAL_RATE * hour, 24.0)


## A compass bearing (degrees, clockwise from north seen from above) as a direction in the room, the room's front
## facing `facing`.
static func bearing_dir(bearing: float, facing: float) -> Vector3:
	var a := deg_to_rad(bearing - facing)
	return Vector3(sin(a), 0.0, -cos(a))


## Equatorial -> the room's frame, for a latitude, a sidereal time and the room's facing.
static func star_basis_for(latitude: float, lst_hours: float, facing: float) -> Basis:
	var phi := deg_to_rad(latitude)
	var north := bearing_dir(0.0, facing)
	var up := Vector3.UP
	var east := north.cross(up)
	var meridian := -sin(phi) * north + cos(phi) * up
	var pole := cos(phi) * north + sin(phi) * up
	var m := Basis(meridian, east, pole)
	return m * Basis(Vector3(0, 0, 1), -deg_to_rad(lst_hours * 15.0))


func star_basis() -> Basis:
	return star_basis_for(float(params["latitude"]), sidereal_hours(float(params["day_of_year"]), _hour_shown),
			float(params["facing"]))


## The hour the stars stand at now (it eases towards `hour`).
func hour_shown() -> float:
	return _hour_shown


## A catalogue star's direction in the room now (Vector3.ZERO when it isn't in the catalogue).
func star_direction(star_id: String) -> Vector3:
	var s: Variant = catalogue()["stars"].get(star_id)
	if s == null:
		return Vector3.ZERO
	return star_basis() * equatorial(float(s[0]), float(s[1]))


func _bearing(param: String) -> Vector3:
	return bearing_dir(float(params[param]), float(params["facing"]))


## Where the sun went down, as a direction in the room's frame (a reflection's glow, kit/reflect.gd).
func glow_direction() -> Vector3:
	return _bearing("glow_bearing")


## The sky's light now, for scenery under it (vista.gd): {zenith, horizon} (sRGB colours), and dusk.
func sky_light() -> Dictionary:
	if str(params["mode"]) != "sky":
		return {"zenith": Color(0.0, 0.0, 0.0), "horizon": color_param("ground"), "dusk": 1.0}
	var k := smoothstep(0.0, 1.0, float(params["dusk"]))
	return {"zenith": color_param("twilight_zenith").lerp(color_param("night_zenith"), k),
			"horizon": color_param("twilight_horizon").lerp(color_param("night_horizon"), k),
			"dusk": float(params["dusk"])}


## The Moon as a light on what lies under the sky (the passing system's water, passing.gd): {direction: towards it,
## in the room's frame; level: how bright its road on water is}. The level is `moon`, less for the air low down as
## the Moon's own shader dims it, less by how much of its face is dark (`moon_phase`), and less while the sky is
## still light: a road under a Moon in a bright evening sky is barely there, and comes as the dusk deepens.
## Level 0 without a Moon.
func moon_shine() -> Dictionary:
	if _moon == null or str(params["mode"]) != "sky":
		return {"direction": Vector3.UP, "level": 0.0}
	var dir := _moon_dir()
	var dark := smoothstep(0.0, 1.0, float(params["dusk"]))
	return {"direction": dir, "level": float(params["moon"]) * lerpf(0.6, 1.0, smoothstep(0.05, 0.3, dir.y))
			* float(params["moon_phase"]) * lerpf(MOON_ROAD_IN_TWILIGHT, 1.0, dark)}


# --- Building ------------------------------------------------------------------------------------------------------------

func setup() -> void:
	_rng.seed = hash(id + "sky")
	_materials.clear()
	_hour_shown = float(params["hour"])
	if str(params["mode"]) == "black":
		return
	var noise := noise_texture()
	var dome := SphereMesh.new()
	dome.radius = DOME_RADIUS
	dome.height = DOME_RADIUS * 2.0
	dome.radial_segments = 48
	dome.rings = 24
	_dome = _instance("SkyDome", dome, _material(DOME_SHADER, noise))
	_stars = _instance("SkyStars", _star_mesh(), _material(STAR_SHADER, noise))
	_stars.material_override.set_shader_parameter("model_radius", STAR_RADIUS)
	_stars.material_override.render_priority = 1
	if float(params["lines"]) > 0.0:
		_build_lines()
	if bool(params["earth"]):
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		var detail := bool(params["earth_detail"])
		_earth = _instance("SkyEarth", sphere, _material(EARTH_DETAIL_SHADER if detail else EARTH_SHADER, noise))
		if detail:
			_earth.material_override.set_shader_parameter("earth_map", EarthMap.texture())
		# Its mesh where it shows (the checks see it there), its size as drawn.
		var dir := _earth_dir()
		var half := tan(deg_to_rad(float(params["earth_size"])) * 0.5) * EARTH_RADIUS
		_earth.transform = Transform3D(Basis().scaled(Vector3.ONE * half), dir * EARTH_RADIUS)
	if float(params["moon"]) > 0.0 and str(params["mode"]) == "sky":
		_moon = _instance("SkyMoon", _moon_mesh(), _material(MOON_SHADER, noise))
		_moon.material_override.render_priority = 2
	_apply_all()


func _instance(node_name: String, mesh: Mesh, m: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Drawn round the camera, wherever the room's origin is: never culled.
	mi.extra_cull_margin = 16384.0
	own(mi)
	return mi


func _material(shader: Shader, noise: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("sky_noise", noise)
	_materials.append(m)
	return m


func _star_list() -> Array:
	var out: Array = []
	var cat := catalogue()
	for sid: String in cat["order"]:
		var s: Array = cat["stars"][sid]
		out.append([equatorial(s[0], s[1]), float(s[2]), float(s[3])])
	out.append_array(faint_field(int(params["faint_stars"])))
	var es := float(params.get("evening_star", 0.0))
	if es > 0.0:
		# Low over the glow at the starting hour (11 degrees up, a little left of where the sun went down), fixed on
		# the celestial sphere from there, so it sets as the hours turn. Brighter than any star (magnitude -3.5 at 1),
		# its size held to a star's largest.
		var flat := bearing_dir(float(params["glow_bearing"]) - 6.0, float(params["facing"]))
		var alt := deg_to_rad(11.0)
		var here := (flat * cos(alt) + Vector3.UP * sin(alt)).normalized()
		out.append([star_basis().inverse() * here, lerpf(0.5, -1.2, es), 0.75])
	return out


func _star_mesh() -> ArrayMesh:
	var list := _star_list()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = FIELD_SEED + 1
	for s: Array in list:
		var e: Vector3 = s[0]
		var mag: float = s[1]
		var half := tan(deg_to_rad(STAR_SIZE + STAR_GROW * maxf(0.0, 6.0 - mag)))
		var u := e.cross(Vector3(0, 0, 1))
		if u.length() < 0.01:
			u = e.cross(Vector3(1, 0, 0))
		u = u.normalized() * half
		var v := e.cross(u.normalized()) * half
		var c := star_colour(s[2])
		c.a = star_intensity(mag)
		var phase := rng.randf()
		var base := verts.size()
		for k in 4:
			var sx := -1.0 if k == 0 or k == 3 else 1.0
			var sy := -1.0 if k < 2 else 1.0
			verts.append((e + u * sx + v * sy) * STAR_RADIUS)
			uvs.append(Vector2(sx * 0.5 + 0.5, sy * 0.5 + 0.5))
			uv2s.append(Vector2(phase, mag))
			cols.append(c)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return _array_mesh(verts, uvs, uv2s, cols, idx)


static func _array_mesh(verts: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not uv2s.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if not verts.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The constellations' lines: each pair as a thin band along the great circle, kept a little short of its stars.
func _build_lines() -> void:
	var cat := catalogue()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var half := tan(deg_to_rad(0.05))
	var gap := deg_to_rad(0.7)
	for cname: String in cat["lines"]:
		for pair: Array in cat["lines"][cname]:
			var a: Variant = cat["stars"].get(str(pair[0]))
			var b: Variant = cat["stars"].get(str(pair[1]))
			if a == null or b == null:
				continue
			var p := equatorial(a[0], a[1])
			var q := equatorial(b[0], b[1])
			var ang := p.angle_to(q)
			if ang <= gap * 2.0:
				continue
			var axis := p.cross(q).normalized()
			var steps := maxi(1, ceili(rad_to_deg(ang) / 4.0))
			var base := verts.size()
			for i in steps + 1:
				var t := gap + (ang - gap * 2.0) * float(i) / steps
				var d := p.rotated(axis, t)
				var w := axis * half
				verts.append((d - w) * LINE_RADIUS)
				verts.append((d + w) * LINE_RADIUS)
				uvs.append(Vector2(float(i) / steps, 0.0))
				uvs.append(Vector2(float(i) / steps, 1.0))
			for i in steps:
				var k := base + i * 2
				idx.append_array([k, k + 1, k + 3, k, k + 3, k + 2])
	var m := ShaderMaterial.new()
	m.shader = LINE_SHADER
	m.set_shader_parameter("sky_noise", noise_texture())
	m.set_shader_parameter("model_radius", LINE_RADIUS)
	_materials.append(m)
	_lines = _instance("SkyLines", _array_mesh(verts, uvs, PackedVector2Array(), PackedColorArray(), idx), m)
	_apply_all()


## The Moon's quad where it hangs (the shader draws it round the camera; the vertices are here so the checks see it
## far off): MOON_HALO times its radius each way, for the halo.
func _moon_mesh() -> ArrayMesh:
	var dir := _moon_dir()
	var f := _moon_frame()
	var half := tan(deg_to_rad(float(params["moon_size"])) * 0.5) * MOON_HALO
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		verts.append((dir + (f[0] * k.x + f[1] * k.y) * half) * MOON_RADIUS)
		uvs.append(k * 0.5 + Vector2(0.5, 0.5))
	return _array_mesh(verts, uvs, PackedVector2Array(), PackedColorArray(), PackedInt32Array([0, 1, 2, 0, 2, 3]))


func _moon_dir() -> Vector3:
	var flat := _bearing("moon_bearing")
	var alt := deg_to_rad(float(params["moon_altitude"]))
	return (flat * cos(alt) + Vector3.UP * sin(alt)).normalized()


## The Moon's quad's right and up (its up as near the sky's up as it can be).
func _moon_frame() -> Array:
	var dir := _moon_dir()
	var right := Vector3.UP.cross(-dir)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := (-dir).cross(right).normalized()
	return [right, up]


## Where the sunlight comes from on the Moon's face, in its quad's frame (x right, y up, z towards the viewer): the sun
## is down behind the horizon at glow_bearing; its angle from the Moon sets how much of it is lit (moon_phase).
func _moon_light() -> Vector3:
	var f := _moon_frame()
	var sun := (_bearing("glow_bearing") * cos(deg_to_rad(-12.0)) + Vector3.UP * sin(deg_to_rad(-12.0))).normalized()
	var side := Vector2(sun.dot(f[0]), sun.dot(f[1]))
	side = side.normalized() if side.length() > 0.001 else Vector2(1, 0)
	var theta := acos(clampf(1.0 - 2.0 * float(params["moon_phase"]), -1.0, 1.0))
	return Vector3(side.x * sin(theta), side.y * sin(theta), -cos(theta))


func _earth_dir() -> Vector3:
	var flat := _bearing("earth_bearing")
	var alt := deg_to_rad(float(params["earth_altitude"]))
	return (flat * cos(alt) + Vector3.UP * sin(alt)).normalized()


## Earth's frame: z towards the viewer, y its axis (the room's up, tilted), x the rest.
func _earth_basis() -> Basis:
	var z := -_earth_dir()
	var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
	if y.length() < 0.5:
		y = Vector3(0, 0, -1)
	var x := y.cross(z).normalized()
	var b := Basis(x, y, z)
	return Basis(z, deg_to_rad(EARTH_TILT)) * b


# --- Uniforms --------------------------------------------------------------------------------------------------------------

func _set_all(uniform: String, value: Variant) -> void:
	for m in _materials:
		m.set_shader_parameter(uniform, value)


## Every uniform from the parameters (after building, or a change).
func _apply_all() -> void:
	if _materials.is_empty():
		return
	for k: String in ["night_zenith", "night_horizon", "twilight_zenith", "twilight_horizon"]:
		_set_all(k, color_param(k))
	_set_all("ground_colour", color_param("ground"))
	_set_all("glow_colour", color_param("glow"))
	_set_all("glow_dir", _bearing("glow_bearing"))
	_set_all("space", 1.0 if str(params["mode"]) == "space" else 0.0)
	_set_all("afterglow", float(params["afterglow"]))
	_set_all("belt_colour", color_param("belt_colour"))
	_set_all("radius", DOME_RADIUS)
	for k: String in ["dusk", "clouds"]:
		_set_all(k, float(params[k]))
	_set_all("cloud_offset", _cloud_offset)
	_set_basis()
	var dm := _dome.material_override as ShaderMaterial
	dm.set_shader_parameter("milky_way", float(params["milky_way"]))
	dm.set_shader_parameter("milky_colour", color_param("milky_colour"))
	dm.set_shader_parameter("milky_detail", float(params["milky_detail"]))
	dm.set_shader_parameter("cloud_colour", color_param("cloud_colour"))
	dm.set_shader_parameter("cloud_screen", float(params["cloud_screen"]))
	dm.set_shader_parameter("aurora", float(params["aurora"]))
	dm.set_shader_parameter("aurora_low", color_param("aurora_low"))
	dm.set_shader_parameter("aurora_high", color_param("aurora_high"))
	dm.set_shader_parameter("aurora_dir", _bearing("aurora_bearing"))
	dm.set_shader_parameter("aurora_time", _aurora_time)
	dm.set_shader_parameter("cloud_glow", color_param("cloud_glow"))
	dm.set_shader_parameter("cloud_glow_level", float(params["cloud_glow_level"]))
	dm.set_shader_parameter("moon_dir", _moon_dir())
	dm.set_shader_parameter("moon_light", float(params["moon"]) if _moon != null else 0.0)
	if _moon != null:
		var mm := _moon.material_override as ShaderMaterial
		var f := _moon_frame()
		mm.set_shader_parameter("moon", float(params["moon"]))
		mm.set_shader_parameter("moon_dir", _moon_dir())
		mm.set_shader_parameter("moon_right", f[0])
		mm.set_shader_parameter("moon_up", f[1])
		mm.set_shader_parameter("moon_half", tan(deg_to_rad(float(params["moon_size"])) * 0.5))
		mm.set_shader_parameter("halo", MOON_HALO)
		mm.set_shader_parameter("sun", _moon_light())
		mm.set_shader_parameter("model_radius", MOON_RADIUS)
	var sm := _stars.material_override as ShaderMaterial
	sm.set_shader_parameter("stars", float(params["stars"]))
	sm.set_shader_parameter("twinkle", float(params["twinkle"]))
	sm.set_shader_parameter("bright_in_twilight", 1.0 if float(params["evening_star"]) > 0.0 else 0.0)
	if _lines != null:
		var lm := _lines.material_override as ShaderMaterial
		lm.set_shader_parameter("lines", float(params["lines"]))
		lm.set_shader_parameter("line_colour", color_param("line_colour"))
		_lines.visible = float(params["lines"]) > 0.0
	if _earth != null:
		var em := _earth.material_override as ShaderMaterial
		var dir := _earth_dir()
		var eb := _earth_basis()
		var theta := (1.0 - float(params["earth_phase"])) * PI
		em.set_shader_parameter("earth_dir", dir)
		em.set_shader_parameter("earth_half", tan(deg_to_rad(float(params["earth_size"])) * 0.5))
		em.set_shader_parameter("earth_basis", eb)
		em.set_shader_parameter("earth_radius", EARTH_RADIUS)
		var la := deg_to_rad(float(params["earth_light_angle"]))
		var side := eb.x * cos(la) + eb.y * sin(la)
		em.set_shader_parameter("sun_dir", (-dir * cos(theta) + side * sin(theta)).normalized())
		em.set_shader_parameter("city_level", float(params["earth_lights"]))
		_set_spin()


func _set_basis() -> void:
	var b := star_basis()
	_set_all("star_basis", b)
	if _dome != null:
		(_dome.material_override as ShaderMaterial).set_shader_parameter("galactic", GALACTIC * b.transposed())


func _set_spin() -> void:
	if _earth != null:
		(_earth.material_override as ShaderMaterial).set_shader_parameter("earth_spin",
				deg_to_rad(float(params["earth_angle"])) + _earth_spin)


func _param_changed(param: String, _value: Variant) -> void:
	if _materials.is_empty():
		return
	match param:
		"hour":
			pass
		"earth_angle":
			_set_spin()
		"lines":
			if _lines == null and float(params["lines"]) > 0.0:
				_build_lines()
			else:
				_apply_all()
		"wind", "aurora_speed", "earth_turn", "meteors":
			pass
		_:
			_apply_all()


# --- Each frame -------------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if _materials.is_empty():
		return
	_turn_stars(delta)
	var wind := float(params["wind"])
	if wind > 0.0 and float(params["clouds"]) > 0.0:
		var to := -_bearing("wind_from")
		_cloud_offset -= Vector2(to.x, to.z) * wind * 0.004 * delta
		_cloud_offset = Vector2(fposmod(_cloud_offset.x, 64.0), fposmod(_cloud_offset.y, 64.0))
		_set_all("cloud_offset", _cloud_offset)
	if float(params["aurora"]) > 0.0:
		_aurora_time += float(params["aurora_speed"]) * delta
		(_dome.material_override as ShaderMaterial).set_shader_parameter("aurora_time", _aurora_time)
	if _earth != null and float(params["earth_turn"]) > 0.0:
		_earth_spin = fposmod(_earth_spin + float(params["earth_turn"]) * TAU / 86400.0 * delta, TAU)
		_set_spin()
	var rate := float(params["meteors"])
	if rate > 0.0 and _meteor.is_empty() and _rng.randf() < rate / 3600.0 * delta:
		act("shooting_star", {})
	if not _meteor.is_empty():
		_meteor[2] = float(_meteor[2]) + delta / SHOOTING_SECONDS
		var dm := _dome.material_override as ShaderMaterial
		if float(_meteor[2]) >= 1.0:
			_meteor = []
			dm.set_shader_parameter("meteor_from", Vector4(0, 1, 0, -1))
		else:
			var f: Vector3 = _meteor[0]
			dm.set_shader_parameter("meteor_from", Vector4(f.x, f.y, f.z, float(_meteor[2])))
			dm.set_shader_parameter("meteor_to", _meteor[1])


## The stars towards `hour`, the short way round, no faster than the comfort limit.
func _turn_stars(delta: float) -> void:
	var want := float(params["hour"])
	var diff := fposmod(want - _hour_shown + 12.0, 24.0) - 12.0
	if absf(diff) < 1e-6:
		return
	var motion := 1.0
	if host != null and host.setting("motion") != null:
		motion = clampf(float(host.setting("motion")), 0.0, 1.0)
	var most := MAX_HOURS_PER_SECOND * motion * delta
	if absf(diff) <= most:
		_hour_shown = want
	else:
		_hour_shown = fposmod(_hour_shown + signf(diff) * most, 24.0)
	_set_basis()


func act(action: String, _args: Dictionary) -> void:
	if action != "shooting_star" or _dome == null:
		return
	var az := _rng.randf() * TAU
	var alt := deg_to_rad(_rng.randf_range(35.0, 70.0))
	var from := Vector3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt))
	var side := from.cross(Vector3.UP).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
	var down := (Vector3.DOWN - from * from.dot(Vector3.DOWN)).normalized()
	var to := (from + (down * 0.8 + side * 0.6).normalized() * deg_to_rad(_rng.randf_range(10.0, 22.0))).normalized()
	_meteor = [from, to, 0.0]
	meteors_sent += 1


## Tests: the nodes drawn.
func layers() -> Dictionary:
	return {"dome": _dome, "stars": _stars, "lines": _lines, "earth": _earth, "moon": _moon}


## The Moon's direction in the room (tests; Vector3.ZERO without a Moon).
func moon_direction() -> Vector3:
	return _moon_dir() if _moon != null else Vector3.ZERO


func material(layer: String) -> ShaderMaterial:
	var n: MeshInstance3D = layers().get(layer)
	return n.material_override as ShaderMaterial if n != null else null


func earth_spin_deg() -> float:
	return rad_to_deg(_earth_spin)


func cloud_offset() -> Vector2:
	return _cloud_offset
