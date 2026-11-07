extends SceneTree

## The sky system (scripts/env/systems/sky.gd; docs/environments.md, "The sky"): the bright-star catalogue reads and
## every constellation line names a star in it; the stars stand where they really are for a latitude, a day and a time
## (Polaris at the latitude's height in the north, Betelgeuse high in the south on a January midnight, Vega near the
## zenith on a July night); the facing turns the compass, not the sky's height; the gradient and the stars follow a
## dusk track by film.minutes; the aurora swells with film.quiet and fades slowly; the clouds take the film's colour;
## the Milky Way rises as playback starts; a change of hour turns the stars no faster than the comfort limit, slower
## with the Motion setting down; Earth turns at its speed times the Motion setting; a shooting star crosses and goes;
## mode black draws nothing; a test room (a hall open to the sky) passes the checks. Under a renderer (lavapipe) the
## dome, the stars, the twilight's glow and Earth are drawn. No main scene.
## godot --headless --xr-mode off --path app --script res://tests/test_env_sky.gd

const EnvChecks := preload("res://scripts/env/env_checks.gd")
const EnvDoc := preload("res://scripts/env/env_doc.gd")
const EnvRoom := preload("res://scripts/env/env_room.gd")
const Registry := preload("res://scripts/env/systems/registry.gd")
const SkySystem := preload("res://scripts/env/systems/sky.gd")

const VIEW := Vector2i(320, 320)

var _failures := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


static func test_doc() -> Dictionary:
	return {"schema": 4, "name": "Sky test", "room": {"ambient": 0.05, "screen_glow": 1.0},
		"screen": {"center": [0.0, 1.6, -13.8], "size": [12.0, 5.0]},
		"systems": [{"system": "light"},
			{"system": "auditorium", "id": "hall", "params": {"ceiling_cover": 0.0}},
			{"system": "screen_frame"},
			{"system": "sky", "params": {
				"latitude": 40.0, "day_of_year": 200.0, "hour": 22.0, "lines": 0.5, "clouds": 0.4,
				"cloud_colour": {"bind": "film.colour", "strength": 0.5, "base": "#3a3e48", "smooth": 1.0},
				"aurora": {"bind": "film.quiet", "range": [0.0, 1.0], "smooth": 2.0},
				"milky_way": {"bind": "playback.playing", "range": [0.2, 0.9], "smooth": 3.0}}}],
		"timeline": {"tracks": [{"target": "sky.dusk", "by": "film.minutes", "keys": [[0, 0.0], [10, 1.0]],
			"smooth": 0.5}]}}


func _build(doc: Dictionary, parent: Node = null) -> Node3D:
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	(parent if parent != null else root).add_child(room)
	room.host.auto = false
	room.host.on_screen_changed(room.get_screen_anchor(), Vector2(12.0, 5.0))
	return room


func _steps(host: Node, seconds: float, delta := 0.25) -> void:
	for i in int(round(seconds / delta)):
		host.step(delta)


## A room direction's altitude (degrees over the horizon) and compass bearing, the room's front facing `facing`.
static func _alt_bearing(d: Vector3, facing: float) -> Vector2:
	var alt := rad_to_deg(asin(clampf(d.normalized().y, -1.0, 1.0)))
	var bearing := fposmod(facing + rad_to_deg(atan2(d.x, -d.z)), 360.0)
	return Vector2(alt, bearing)


static func _star(sid: String, latitude: float, day: float, hour: float, facing := 180.0) -> Vector2:
	var s: Array = SkySystem.catalogue()["stars"][sid]
	var b := SkySystem.star_basis_for(latitude, SkySystem.sidereal_hours(day, hour), facing)
	return _alt_bearing(b * SkySystem.equatorial(s[0], s[1]), facing)


func _run() -> void:
	var s := Registry.spec("sky")
	_check("registered, kind sky", Registry.has("sky") and s["kind"] == "sky")
	# The catalogue.
	var cat := SkySystem.catalogue()
	var stars: Dictionary = cat["stars"]
	_check("the bright stars read (%d)" % stars.size(), stars.size() >= 250)
	var sane := true
	for sid: String in stars:
		var st: Array = stars[sid]
		if float(st[0]) < 0.0 or float(st[0]) >= 24.0 or absf(float(st[1])) > 90.0 or float(st[2]) > 6.5:
			sane = false
			print("  odd star %s %s" % [sid, st])
	_check("right ascensions 0..24 h, declinations within 90, magnitudes to 6.5", sane)
	var missing: Array = []
	var pairs := 0
	for cname: String in cat["lines"]:
		for pair: Array in cat["lines"][cname]:
			pairs += 1
			for x: Variant in pair:
				if not stars.has(str(x)):
					missing.append("%s: %s" % [cname, x])
	_check("%d constellations, %d lines" % [(cat["lines"] as Dictionary).size(), pairs],
			(cat["lines"] as Dictionary).size() >= 40 and pairs >= 150)
	_check("every line's stars are in the catalogue %s" % [missing.slice(0, 6)], missing.is_empty())
	_check("Sirius the brightest", float(stars["Sirius"][2]) < -1.0)
	# Where the stars stand.
	var p := _star("Polaris", 40.0, 200.0, 22.0)
	_check("Polaris at the latitude's height, 40 N (%.2f)" % p.x, absf(p.x - 40.0) < 1.0)
	_check("and due north (bearing %.1f)" % p.y, minf(p.y, 360.0 - p.y) < 1.5)
	var p2 := _star("Polaris", 40.0, 30.0, 3.0)
	_check("Polaris stays put through the night and the year (%.2f)" % p2.x, absf(p2.x - p.x) < 1.0)
	var ps := _star("Polaris", -34.0, 200.0, 22.0)
	_check("from 34 S Polaris is under the horizon (%.1f)" % ps.x, ps.x < -32.0 and ps.x > -36.0)
	var bet := _star("Betelgeuse", 40.0, 15.0, 0.0)
	_check("Betelgeuse high in the south, 40 N, 15 January, midnight (alt %.1f, bearing %.1f)" % [bet.x, bet.y],
			bet.x > 45.0 and bet.y > 150.0 and bet.y < 260.0)
	var bet7 := _star("Betelgeuse", 40.0, 196.0, 0.0)
	_check("and under the horizon in July (%.1f)" % bet7.x, bet7.x < 0.0)
	var vega := _star("Vega", 40.0, 200.0, 22.0)
	_check("Vega near the zenith, 40 N, mid July, 22 h (alt %.1f)" % vega.x, vega.x > 75.0)
	var vega2 := _star("Vega", 40.0, 200.0, 4.0)
	_check("Vega lower in the north-west before dawn (alt %.1f, bearing %.1f)" % [vega2.x, vega2.y],
			vega2.x < 45.0 and vega2.y > 270.0 and vega2.y < 340.0)
	var north_ahead := SkySystem.star_basis_for(40.0, 12.0, 0.0) * SkySystem.equatorial(0.0, 90.0)
	_check("facing north: the pole ahead of the room (%s)" % north_ahead, north_ahead.z < -0.7)
	var north_behind := SkySystem.star_basis_for(40.0, 12.0, 180.0) * SkySystem.equatorial(0.0, 90.0)
	_check("facing south: the pole behind (%s)" % north_behind, north_behind.z > 0.7
			and is_equal_approx(north_ahead.y, north_behind.y))
	_check("the sidereal clock gains about 4 minutes a day", absf(fposmod(SkySystem.sidereal_hours(2.0, 0.0)
			- SkySystem.sidereal_hours(1.0, 0.0), 24.0) - 0.0657) < 0.001)
	var faint := SkySystem.faint_field(1600)
	var low := 0
	for f: Array in faint:
		if absf(SkySystem.galactic_latitude(f[0])) < 20.0:
			low += 1
	_check("the faint field, thicker along the Milky Way (%d of %d within 20 degrees)" % [low, faint.size()],
			faint.size() == 1600 and low > faint.size() * 0.45)
	_check("the same faint field each time", SkySystem.faint_field(1600) == faint)
	# The test room.
	var doc := test_doc()
	var v := EnvDoc.validate(doc)
	_check("the test room validates: bindings and a dusk track (%s)" % [v["errors"]], v["ok"])
	var st := EnvChecks.static_checks(doc)
	for k: String in st:
		_check("static check %s %s" % [k, st[k]], (st[k] as Array).is_empty())
	var bad := test_doc()
	bad["systems"][3]["params"]["earth_turn"] = 90.0
	_check("an Earth spinning past its limit is refused", not EnvDoc.validate(bad)["ok"]
			or not EnvChecks.comfort(bad).is_empty())
	var bad2 := test_doc()
	bad2["systems"][3]["params"]["aurora"]["smooth"] = 0.0
	_check("an aurora flashing with the sound is refused (comfort)", not EnvChecks.comfort(bad2).is_empty())
	var room := _build(doc)
	await process_frame
	var host: Node = room.host
	var sky: Node = host.system("sky")
	_check("built", sky != null and sky.get_script() == SkySystem)
	var layers: Dictionary = sky.layers()
	_check("a dome, stars and the lines; no Earth", layers["dome"] != null and layers["stars"] != null
			and layers["lines"] != null and layers["earth"] == null)
	var star_mesh: ArrayMesh = (layers["stars"] as MeshInstance3D).mesh
	_check("one quad a star (%d)" % star_mesh.surface_get_array_len(0),
			star_mesh.surface_get_array_len(0) == (stars.size() + 1600) * 4)
	var far := true
	for n: String in layers:
		var mi := layers[n] as MeshInstance3D
		if mi == null:
			continue
		var bb := mi.get_aabb()
		if mi.mesh.get_faces().size() > 0:
			var near := INF
			for f: Vector3 in mi.mesh.get_faces():
				near = minf(near, (mi.transform * f).length())
			if near < 150.0:
				far = false
				print("  %s comes within %.1f m" % [n, near])
		if mi.gi_mode != GeometryInstance3D.GI_MODE_DISABLED or bb.size == Vector3.ZERO:
			far = false
	_check("every layer's mesh is far out (the checks never see it near) and out of the bake", far)
	# The dusk track by film.minutes.
	var signals: RefCounted = host.signals
	signals.fake("film.minutes", 0.0)
	_steps(host, 3.0)
	var dome: ShaderMaterial = sky.material("dome")
	_check("film minute 0: the last light (dusk %.2f)" % float(dome.get_shader_parameter("dusk")),
			float(dome.get_shader_parameter("dusk")) < 0.02)
	var twilight: Dictionary = sky.sky_light()
	signals.fake("film.minutes", 5.0)
	_steps(host, 4.0)
	_check("minute 5: half way (%.2f)" % float(dome.get_shader_parameter("dusk")),
			absf(float(dome.get_shader_parameter("dusk")) - 0.5) < 0.03)
	_check("the stars' layer has it too", is_equal_approx(float(sky.material("stars").get_shader_parameter("dusk")),
			float(dome.get_shader_parameter("dusk"))))
	signals.fake("film.minutes", 30.0)
	_steps(host, 4.0)
	var night: Dictionary = sky.sky_light()
	_check("minute 30: night (%.2f)" % float(dome.get_shader_parameter("dusk")),
			float(dome.get_shader_parameter("dusk")) > 0.98)
	_check("the light for the vista darkens with it (%s to %s)" % [twilight["zenith"], night["zenith"]],
			(night["zenith"] as Color).get_luminance() < (twilight["zenith"] as Color).get_luminance()
			and (night["horizon"] as Color).get_luminance() < (twilight["horizon"] as Color).get_luminance())
	# The aurora swells in a quiet scene.
	_check("no aurora in a loud scene", float(dome.get_shader_parameter("aurora")) < 0.01)
	signals.fake("film.quiet", 1.0)
	host.step(0.25)
	_check("it swells, not at once (%.2f)" % float(dome.get_shader_parameter("aurora")),
			float(dome.get_shader_parameter("aurora")) < 0.2)
	_steps(host, 10.0)
	_check("a quiet scene: the aurora (%.2f)" % float(dome.get_shader_parameter("aurora")),
			float(dome.get_shader_parameter("aurora")) > 0.95)
	var t0 := float(dome.get_shader_parameter("aurora_time"))
	_steps(host, 2.0)
	_check("its curtains wave slowly (%.3f)" % (float(dome.get_shader_parameter("aurora_time")) - t0),
			absf(float(dome.get_shader_parameter("aurora_time")) - t0 - 0.8) < 0.01)
	signals.fake("film.quiet", 0.0)
	_steps(host, 1.0)
	_check("it fades when the quiet ends, slowly (%.2f)" % float(dome.get_shader_parameter("aurora")),
			float(dome.get_shader_parameter("aurora")) > 0.5)
	# The clouds take the film's colour.
	signals.fake("film.colour", Color(1.0, 0.0, 0.0))
	_steps(host, 8.0)
	var cc: Color = dome.get_shader_parameter("cloud_colour")
	_check("the clouds go half way to the film's colour (%s)" % cc, cc.r > 0.6 and cc.g < 0.2)
	_check("the clouds drift", sky.cloud_offset() != Vector2.ZERO)
	# The Milky Way as the film plays.
	var mw0 := float(dome.get_shader_parameter("milky_way"))
	signals.fake("playback.playing", 1.0)
	_steps(host, 15.0)
	var mw1 := float(dome.get_shader_parameter("milky_way"))
	_check("the Milky Way comes out as the film plays (%.2f to %.2f)" % [mw0, mw1], mw0 < 0.25 and mw1 > 0.85)
	# The stars turn no faster than the limit.
	var vega_dir: Vector3 = sky.star_direction("Vega")
	sky.set_param("hour", 4.0)
	host.step(1.0)
	var turned := rad_to_deg(vega_dir.angle_to(sky.star_direction("Vega")))
	_check("a change of six hours: the stars turn slowly (%.3f degrees in a second)" % turned,
			turned > 0.05 and turned <= 0.26)
	_steps(host, 59.0)
	_check("an hour of sky a minute (%.2f h)" % sky.hour_shown(), absf(sky.hour_shown() - 23.0) < 0.02)
	host.set_setting("motion", 0.5)
	_steps(host, 60.0)
	_check("half as fast with Motion at half (%.2f h)" % sky.hour_shown(), absf(sky.hour_shown() - 23.5) < 0.02)
	host.set_setting("motion", 1.0)
	_steps(host, 60.0 * 4.6)
	_check("there in the end, the short way round (%.2f h)" % sky.hour_shown(), is_equal_approx(sky.hour_shown(), 4.0))
	# A shooting star.
	sky.act("shooting_star", {})
	host.step(0.3)
	var m: Vector4 = dome.get_shader_parameter("meteor_from")
	_check("a shooting star crosses (%s)" % m, sky.meteors_sent == 1 and m.w > 0.0 and m.w < 1.0 and m.y > 0.4)
	_steps(host, 1.0)
	_check("and is gone", float((dome.get_shader_parameter("meteor_from") as Vector4).w) < 0.0)
	# Lines off, then on.
	sky.set_param("lines", 0.0)
	_check("lines off: hidden", not (layers["lines"] as MeshInstance3D).visible)
	sky.set_param("lines", 0.4)
	_check("on again", (layers["lines"] as MeshInstance3D).visible)
	# The checks.
	var stats := EnvChecks.measure(room)
	print("  sky test room: %s" % [stats])
	if DisplayServer.get_name() == "headless":
		_check("within the headset's budget %s" % [EnvChecks.budget(stats)], EnvChecks.budget(stats).is_empty())
	else:
		# Under a renderer the hall's library textures measure larger; the budget is the headless measure
		# (test_environments.gd). The sky's own share is checked below either way.
		print("  (the budget is checked headless)")
	var own := _own_cost(sky)
	print("  sky's own: %s (spec: %s)" % [own, s["cost"]])
	_check("its own: a dome, stars and lines, 3 draws (%s)" % [own], own["draws"] == 3 and own["particles"] == 0
			and own["lights"] == 0)
	_check("the spec's cost is honest (%s vs %s)" % [own, s["cost"]], int(s["cost"]["draws"]) >= own["draws"]
			and int(s["cost"]["triangles"]) >= own["triangles"] and float(s["cost"]["texture_mb"]) + 0.01 >= own["texture_mb"])
	var blocked: Array = await EnvChecks.sight_line(self, room)
	_check("a clear sight line from every seat %s" % [blocked.slice(0, 2)], blocked.is_empty())
	_check("no sound of its own", host.sounds.is_empty())
	room.queue_free()
	await process_frame
	# Space and Earth.
	var moon := {"schema": 4, "name": "Moon test", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": [{"system": "sky", "params": {"mode": "space", "earth": true, "earth_turn": 60.0,
			"earth_bearing": 180.0, "earth_altitude": 30.0, "milky_way": 0.8}}]}
	_check("a Moon sky validates (%s)" % [EnvDoc.validate(moon)["errors"]], EnvDoc.validate(moon)["ok"])
	_check("and is comfortable %s" % [EnvChecks.comfort(moon)], EnvChecks.comfort(moon).is_empty())
	room = _build(moon)
	await process_frame
	sky = room.host.system("sky")
	_check("Earth built", sky.layers()["earth"] != null)
	var earth := sky.layers()["earth"] as MeshInstance3D
	var ab := _alt_bearing(earth.position, 180.0)
	_check("Earth where it was put: 30 degrees up, ahead (alt %.1f, bearing %.1f)" % [ab.x, ab.y],
			absf(ab.x - 30.0) < 0.5 and absf(ab.y - 180.0) < 0.5)
	_steps(room.host, 60.0)
	_check("Earth turns at sixty times its speed: 15 degrees a minute (%.2f)" % sky.earth_spin_deg(),
			absf(sky.earth_spin_deg() - 15.0) < 0.05)
	room.host.set_setting("motion", 0.5)
	_check("the Motion setting halves it", is_equal_approx(float(sky.params["earth_turn"]), 30.0))
	var e0: float = sky.earth_spin_deg()
	_steps(room.host, 60.0)
	_check("half as fast (%.2f)" % (sky.earth_spin_deg() - e0), absf(sky.earth_spin_deg() - e0 - 7.5) < 0.05)
	var moon_own := _own_cost(sky)
	print("  space sky with Earth, its own: %s" % [moon_own])
	_check("with Earth: 3 draws (no lines)", moon_own["draws"] == 3)
	_check("the spec's cost covers Earth and the lines (%s)" % [s["cost"]], int(s["cost"]["triangles"])
			>= moon_own["triangles"] + _lines_triangles())
	room.queue_free()
	await process_frame
	# Mode black: nothing.
	var black := {"schema": 4, "name": "Black test", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
		"systems": [{"system": "sky", "params": {"mode": "black", "lines": 1.0, "earth": true}}]}
	room = _build(black)
	await process_frame
	sky = room.host.system("sky")
	_check("mode black draws nothing", sky.owned().is_empty() and EnvChecks.measure(room)["draws"] == 0)
	_steps(room.host, 1.0)
	sky.act("shooting_star", {})
	_check("and does nothing", sky.meteors_sent == 0)
	room.queue_free()
	await process_frame
	await _render()
	print("test_env_sky: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _own_cost(sys: Node) -> Dictionary:
	var holder := Node3D.new()
	for n: Node in sys.owned():
		holder.add_child(n.duplicate())
	var m := EnvChecks.measure(holder)
	holder.free()
	return m


## The constellation lines' triangles at the catalogue's size (built in a room of their own).
func _lines_triangles() -> int:
	var room := Node3D.new()
	root.add_child(room)
	var sky: Node = SkySystem.new()
	sky.room = room
	sky.id = "sky"
	sky.params = EnvDoc.with_defaults(SkySystem.spec()["params"], {"lines": 1.0})
	room.add_child(sky)
	sky.setup()
	var n := EnvChecks._triangles((sky.layers()["lines"] as MeshInstance3D).mesh)
	room.free()
	return n


# --- Render (lavapipe) --------------------------------------------------------------------------------------------------

func _viewport(room: Node3D, fov := 60.0) -> Array:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	if room != null:
		vp.add_child(room)
		room.host.auto = false
		room.host.on_screen_changed(room.get_screen_anchor(), Vector2(6.0, 3.0))
	return [vp, cam]


func _shot(vc: Array, at: Vector3, look: Vector3, up := Vector3.UP) -> Image:
	(vc[1] as Camera3D).look_at_from_position(at, look, up)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := (vc[0] as SubViewport).get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	# ENV_SHOTS=<dir>: keep the pictures to look at.
	var out := OS.get_environment("ENV_SHOTS")
	if out != "":
		_shots += 1
		img.save_png("%s/sky_%02d.png" % [out, _shots])
	return img


var _shots := 0


## {mean, bright: pixels over 0.25, max, r, g, b (means)}
static func _stats(img: Image) -> Dictionary:
	var sum := 0.0
	var bright := 0
	var top := 0.0
	var rgb := Vector3.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.get_luminance()
			sum += l
			top = maxf(top, l)
			rgb += Vector3(c.r, c.g, c.b)
			if l > 0.25:
				bright += 1
	var n := float(img.get_width() * img.get_height())
	return {"mean": sum / n, "bright": bright, "max": top, "r": rgb.x / n, "g": rgb.y / n, "b": rgb.z / n}


func _render() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP render checks (headless)")
		return
	var sky_only := func(p: Dictionary) -> Node3D:
		var r: Node3D = EnvRoom.new()
		r.doc = {"schema": 4, "name": "Sky render", "screen": {"center": [0.0, 1.6, -8.0], "size": [6.0, 3.0]},
			"systems": [{"system": "sky", "params": p}]}
		return r
	# Night, looking up: a dark sky with stars in it.
	var night: Node3D = sky_only.call({"dusk": 1.0, "hour": 22.0, "day_of_year": 200.0, "milky_way": 0.0})
	var a := _viewport(night)
	var up_img: Image = await _shot(a, Vector3(0, 1.2, 0), Vector3(0.01, 50.0, -1.0), Vector3(0, 0, -1))
	var up := _stats(up_img)
	print("  night, overhead: %s" % [up])
	_check("the night sky is drawn dark (%.3f)" % up["mean"], up["mean"] > 0.002 and up["mean"] < 0.08)
	_check("stars show in it (%d bright pixels, brightest %.2f)" % [up["bright"], up["max"]], up["bright"] >= 6
			and up["max"] > 0.5)
	# Turn the stars off: none.
	night.host.system("sky").set_param("stars", 0.0)
	var none := _stats(await _shot(a, Vector3(0, 1.2, 0), Vector3(0.01, 50.0, -1.0), Vector3(0, 0, -1)))
	_check("stars off: none (%d)" % none["bright"], none["bright"] == 0)
	# The Milky Way where Cygnus is, overhead in July.
	night.host.system("sky").set_param("milky_way", 1.0)
	var mw := _stats(await _shot(a, Vector3(0, 1.2, 0), Vector3(0.01, 50.0, -1.0), Vector3(0, 0, -1)))
	print("  the Milky Way overhead: %s" % [mw])
	_check("the Milky Way brightens the sky overhead (%.4f to %.4f)" % [none["mean"], mw["mean"]],
			mw["mean"] > none["mean"] * 1.15)
	(a[0] as Node).queue_free()
	await process_frame
	# Clouds towards the screen catch its light; an aurora over the north.
	RenderingServer.global_shader_parameter_set("screen_center", Vector3(0.0, 1.6, -8.0))
	RenderingServer.global_shader_parameter_set("screen_glow", 1.0)
	RenderingServer.global_shader_parameter_set("screen_tint", 0.0)
	var cloudy: Node3D = sky_only.call({"clouds": 0.7, "wind": 0.0, "cloud_screen": 2.0, "milky_way": 0.0})
	var cl := _viewport(cloudy, 90.0)
	var ahead := Vector3(0.0, 1.2 + 10.0 * tan(deg_to_rad(25.0)), -10.0)
	var lit := _stats(await _shot(cl, Vector3(0, 1.2, 0), ahead))
	cloudy.host.system("sky").set_param("cloud_screen", 0.0)
	var unlit := _stats(await _shot(cl, Vector3(0, 1.2, 0), ahead))
	print("  clouds towards the screen, lit: %s, unlit: %s" % [lit, unlit])
	_check("the clouds towards the screen catch its light (%.4f to %.4f)" % [unlit["mean"], lit["mean"]],
			lit["mean"] > unlit["mean"] * 1.5)
	cloudy.host.system("sky").set_param("clouds", 0.0)
	cloudy.host.system("sky").set_param("aurora", 1.0)
	var north := Vector3(0.0, 1.2 + 10.0 * tan(deg_to_rad(20.0)), 10.0)
	var aur := _stats(await _shot(cl, Vector3(0, 1.2, 0), north))
	var south := _stats(await _shot(cl, Vector3(0, 1.2, 0), ahead))
	print("  aurora north: %s, south: %s" % [aur, south])
	_check("an aurora over the north, green (%.4f, g %.3f)" % [aur["mean"], aur["g"]], aur["g"] > aur["r"]
			and aur["mean"] > south["mean"] * 1.6)
	(cl[0] as Node).queue_free()
	await process_frame
	# Dusk: the glow where the sun went down is warm and bright, the opposite side darker.
	var dusk: Node3D = sky_only.call({"dusk": 0.0, "glow_bearing": 270.0, "facing": 180.0})
	var b := _viewport(dusk)
	# Facing 180: the west (270) is to the room's right (+x).
	var west := _stats(await _shot(b, Vector3(0, 1.2, 0), Vector3(10.0, 4.0, 0.0)))
	var east := _stats(await _shot(b, Vector3(0, 1.2, 0), Vector3(-10.0, 4.0, 0.0)))
	print("  dusk west: %s, east: %s" % [west, east])
	_check("dusk: the west glows warm (r %.3f, b %.3f)" % [west["r"], west["b"]], west["r"] > west["b"]
			and west["mean"] > 0.15)
	_check("brighter than the east (%.3f, %.3f)" % [west["mean"], east["mean"]], west["mean"] > east["mean"] * 1.3)
	dusk.host.system("sky").set_param("dusk", 1.0)
	var later := _stats(await _shot(b, Vector3(0, 1.2, 0), Vector3(10.0, 4.0, 0.0)))
	_check("night falls (%.3f to %.3f)" % [west["mean"], later["mean"]], later["mean"] < west["mean"] * 0.3)
	(b[0] as Node).queue_free()
	await process_frame
	# The Moon: Earth in a black sky, lit on one side.
	var moon: Node3D = sky_only.call({"mode": "space", "earth": true, "earth_bearing": 180.0, "earth_altitude": 30.0,
			"earth_size": 6.0, "earth_phase": 1.0, "milky_way": 0.0, "faint_stars": 0})
	var c := _viewport(moon, 20.0)
	var e_dir: Vector3 = moon.host.system("sky").layers()["earth"].position
	var earth := _stats(await _shot(c, Vector3(0, 1.2, 0), Vector3(0, 1.2, 0) + e_dir))
	var away := _stats(await _shot(c, Vector3(0, 1.2, 0), Vector3(0, 1.2, 0) + Vector3(e_dir.x, e_dir.y,
			e_dir.z).rotated(Vector3.UP, 1.4)))
	print("  Earth: %s, away from it: %s" % [earth, away])
	_check("Earth drawn (%.3f, blue %.3f)" % [earth["mean"], earth["b"]], earth["mean"] > 0.03
			and earth["b"] > earth["r"])
	_check("space is black round it (%.4f)" % away["mean"], away["mean"] < 0.01)
	(c[0] as Node).queue_free()
	await process_frame
	# Mode black: nothing drawn.
	var blk: Node3D = sky_only.call({"mode": "black"})
	var d := _viewport(blk)
	var bs := _stats(await _shot(d, Vector3(0, 1.2, 0), Vector3(0.01, 50.0, -1.0), Vector3(0, 0, -1)))
	_check("mode black: black (%.4f)" % bs["mean"], bs["mean"] == 0.0)
	(d[0] as Node).queue_free()
	await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: ", what)
