extends "res://tests/env_builder_harness.gd"

## Sky lift (app/environments/sky_lift.env.json; docs/environments/rooms/sky_lift.md): a near-future equatorial orbital
## elevator climber car ascending from an equatorial ocean tether platform through the cloud deck into black star-filled
## orbit, with Earth's glowing curved limb opening out beneath you. Built by Gemini 4 Neon Extra High.
## godot --headless --xr-mode off --path app --script res://tests/test_room_sky_lift.gd

const Passing := preload("res://scripts/env/systems/passing.gd")
const PassingShapes := preload("res://scripts/env/systems/passing/shapes.gd")
const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/sky_lift.env.json"


func run_tests() -> void:
	test_name = "test_room_sky_lift"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "sky_lift", doc, "climber", "ascent", {
			"min_speed": 2.4, "max_speed": 3.4, "start_landmark": "ocean_platform",
			"end_landmark": "orbital_station"})
	RoomJourney.check_fittings(self, room, "climber", "fittings",
			"the climber avionics console, sill bolsters, docking hatch, telemetry desks and aft guard-rails", 8)
	check("the mission chronometer is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the canopy coves and floor pathway strips are built (PieceCove)",
			room.find_child("PieceCove", true, false) != null)
	check("the under-sill cabin sconces and hatch status ring are built (PieceLamps)",
			room.find_child("PieceLamps", true, false) != null)
	check("the telemetry edge bars and aft climb-profile displays are built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the aft docking viewport and balustrade glass are built (PieceGlass)",
			room.find_child("PieceGlass", true, false) != null)
	check("the curved glazed roof canopy and panoramic windows are built (Glass)",
			room.find_child("Glass", true, false) != null)
	check("the live detailed Earth sphere is built (SkyEarth)", room.find_child("SkyEarth", true, false) != null)
	var room_meta: Dictionary = doc.get("room", {})
	check("the room is credited to Gemini 4 Neon Extra High",
			str(room_meta.get("author", "")) == "Gemini 4 Neon Extra High")
	var desc := str(room_meta.get("description", ""))
	check("room.description is within 200 chars (%d)" % desc.length(), desc.length() > 0 and desc.length() <= 200)
	check("zero trademarks in document (%s)" % [EnvChecks.names(doc)], EnvChecks.names(doc).is_empty())
	check("zero people words in document (%s)" % [EnvChecks.no_people(doc)], EnvChecks.no_people(doc).is_empty())
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("two rows of four aerospace recliners (%d), one at the origin" % seats.size(), seats.size() == 8 and own)
	_vertical_comfort(room)
	_ascent_arc_and_settings(room)
	# Sound: electromagnetic tether linear-motor hum following journey.speed, equatorial wind fading to silence in
	# vacuum, orbital launch/docking cabin chime; small_room acoustics.
	RoomSound.check_beds(self, "sky_lift", room, {"drive": "climber_hum", "wind": "wind", "chime": "cabin_chime"},
			"small_room")
	RoomJourney.check_speed_bed(self, room, "drive", "the electromagnetic climber hum", 0.0)
	RoomJourney.check_figures(self, "sky_lift", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "sky_lift", doc)
	await _render(doc)


## Vertical climb uses facing == "up" and holds every passing band and landmark <= 10 deg/s at catch-up speed.
func _vertical_comfort(room: Node3D) -> void:
	var ascent: Node = room.host.system("ascent")
	check("passing system climbs vertically (facing == up)", str(ascent.params["facing"]) == "up")
	var top := float(ascent.params["speed"]) * (1.0 + Passing.CATCH_UP)
	var peak := 0.0
	for raw: Variant in ascent.params["bands"]:
		var b := Passing.band_with_defaults(raw)
		var shape := str(b["shape"])
		var largest := float(b["size"]) * (1.0 if PassingShapes.SEGMENT.has(shape) else PassingShapes.VARY.y)
		var near := PassingShapes.nearest(shape, largest, float(b["near"]), float(b["height"]), EnvChecks.EYE_HEIGHT)
		peak = maxf(peak, rad_to_deg(top / float(b["seems"]) / maxf(near, 0.001)))
	for raw: Variant in ascent.params["landmarks"]:
		var lm := Passing.landmark_with_defaults(raw)
		var near := PassingShapes.nearest(str(lm["shape"]), float(lm["size"]), float(lm["distance"]),
				float(lm["height"]), EnvChecks.EYE_HEIGHT)
		peak = maxf(peak, rad_to_deg(top / maxf(near, 0.001)))
	check("serene orbital ascent angular rate <= 10.0 deg/s (peak %.1f deg/s)" % peak, peak <= 10.0)


## Full atmospheric-to-orbital climb timeline plus live Cabin light and Starlight settings.
func _ascent_arc_and_settings(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var ascent: Node = host.system("ascent")
	var wind: Node = host.system("wind")
	var kit: Node = host.system("fittings")

	# Launch state (progress = 0.0): bright equatorial daylight, sea visible, Earth hidden, trade wind audible.
	RoomJourney.step_stage(host, 0.0)
	check("launch sky is sunlit equatorial blue with 4000 faint stars & all_sky (dusk %.2f, space_mix %.2f, earth_alpha %.2f)"
			% [float(sky.params["dusk"]), float(sky.params["space_mix"]), float(sky.params["earth_alpha"])],
			float(sky.params["dusk"]) < 0.05 and float(sky.params["space_mix"]) < 0.05
			and float(sky.params["earth_alpha"]) < 0.05 and bool(sky.params["all_sky"])
			and int(sky.params["faint_stars"]) == 4000 and float(sky.params["milky_detail"]) >= 0.99)
	check("ocean ground visible (%.2f) and lower-atmosphere wind audible (%.2f) at launch" % [
			float(ascent.params["ground_vis"]), float(wind.params["level"])],
			float(ascent.params["ground_vis"]) > 0.95 and float(wind.params["level"]) > 0.55)

	# Stratosphere transition (progress = 0.40): sea faded out, sky darkening toward orbit, Earth emerging.
	RoomJourney.step_stage(host, 0.40)
	check("above cloud deck (0.40): ocean hidden (%.2f), stratosphere dusk (%.2f), space_mix mid (%.2f)" % [
			float(ascent.params["ground_vis"]), float(sky.params["dusk"]), float(sky.params["space_mix"])],
			float(ascent.params["ground_vis"]) < 0.02 and float(sky.params["dusk"]) > 0.8
			and float(sky.params["space_mix"]) > 0.3 and float(sky.params["space_mix"]) < 0.65)

	# Full orbit (progress = 0.60): 360-degree space, Earth fully revealed, atmospheric wind silenced in vacuum!
	RoomJourney.step_stage(host, 0.60)
	check("in orbit (0.60): pure black space (%.2f), Earth full alpha (%.2f), vacuum wind silent (%.2f)" % [
			float(sky.params["space_mix"]), float(sky.params["earth_alpha"]), float(wind.params["level"])],
			float(sky.params["space_mix"]) > 0.98 and float(sky.params["earth_alpha"]) > 0.98
			and float(wind.params["level"]) < 0.02)

	# High orbital terminus (progress = 1.0): Earth curved limb opens out from 78 deg to 62 deg, rising to -22 deg.
	RoomJourney.step_stage(host, 1.0)
	check("at orbital docking (1.0): Earth shrinks to 62 deg (%.1f) and rises to -22 deg (%.1f)" % [
			float(sky.params["earth_size"]), float(sky.params["earth_altitude"])],
			absf(float(sky.params["earth_size"]) - 62.0) < 1.0
			and absf(float(sky.params["earth_altitude"]) - (-22.0)) < 1.0)

	# Cabin light setting: Orbital cyan / Warm ivory / Amber night / Off.
	host.set_setting("cove", "amber")
	for i in 12:
		host.step(0.25)
	var st_a: Dictionary = kit.cove_state()
	var col_a: Color = st_a.get("colour", Color.BLACK)
	check("Cabin light=amber shifts coves & pathway strips warm amber (%s)" % col_a,
			not st_a.is_empty() and col_a.r > col_a.b * 3.0)
	host.set_setting("cove", "ivory")
	for i in 12:
		host.step(0.25)
	var col_i: Color = kit.cove_state().get("colour", Color.BLACK)
	check("Cabin light=ivory shifts coves warm ivory (%s)" % col_i, col_i.r > 0.85 and col_i.g > 0.85 and col_i.b > 0.7)
	host.set_setting("cove", "off")
	for i in 12:
		host.step(0.25)
	check("Cabin light=off dims cove strips to zero (%.2f)" % float(kit.cove_state().get("glow", 1.0)),
			float(kit.cove_state().get("glow", 1.0)) < 0.01)
	host.set_setting("cove", "cyan")
	for i in 12:
		host.step(0.25)
	var col_c: Color = kit.cove_state().get("colour", Color.BLACK)
	check("Cabin light=cyan restores orbital cyan glow (%s)" % col_c,
			col_c.b > col_c.r * 3.0 and col_c.g > col_c.r * 2.5)

	# Starlight setting: Milky Way / Quiet stars / Constellations.
	host.set_setting("starlight", "quiet")
	for i in 24:
		host.step(0.25)
	check("Starlight=quiet lowers Milky Way (%.2f)" % float(sky.params["milky_way"]),
			float(sky.params["milky_way"]) < 0.4)
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	check("Starlight=constellations raises constellation lines (%.2f) and builds SkyLines" % float(sky.params["lines"]),
			float(sky.params["lines"]) > 0.45 and room.find_child("SkyLines", true, false) != null)
	host.set_setting("starlight", "milky")
	for i in 24:
		host.step(0.25)
	check("Starlight=milky restores full Milky Way (%.2f)" % float(sky.params["milky_way"]),
			float(sky.params["milky_way"]) > 0.9)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.02)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.signals.fake("film.brightness", 0.6)
	host.signals.fake("playback.playing", 1.0)
	var eye := Vector3(0.0, 1.2, 0.0)

	# 1. Pre-show at equatorial launch platform (bright sunlit blue sky, cabin lights up, screen_glow = 0).
	host.snapshot_override = {"open": false}
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, 0.055)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.72, 2.50), screen, "skylift_01_preshow_front")
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.56, -2.45), Vector3(-0.85, 1.38, 3.40), "skylift_02_preshow_aft")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.92, 0.02, -0.34), "skylift_03_launch_platform")

	# 2. Ascending through sunlit cloud deck (film.progress = 0.22).
	RoomRender.set_light(screen, 0.022)
	RoomJourney.step_stage(host, 0.22)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.92, 0.08, -0.34), "skylift_04_cloud_deck")

	# 3. High-altitude indigo stratosphere above the cloud deck (film.progress = 0.40).
	RoomJourney.step_stage(host, 0.40)
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.90, 0.06, -0.44), "skylift_05_stratosphere")

	# 4. High orbit: velvet-black 360-degree space, 4000 stars, full Milky Way, glowing curved Earth limb & tether rings!
	RoomRender.set_light(screen, 0.016)
	RoomJourney.step_stage(host, 0.78)
	await RoomRender.shot(self, vc, eye, screen, "skylift_06_orbit_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.90, -0.02, -0.44), "skylift_07_orbit_earth")
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.15, 0.35), Vector3(-0.85, 3.05, -0.85), "skylift_08_orbit_sky_up")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.06, -0.10), "skylift_09_orbit_tether_left")

	# 5. Live Amber night + Constellations verification in orbit.
	host.set_setting("cove", "amber")
	host.set_setting("starlight", "constellations")
	for i in 24:
		host.step(0.25)
	await RoomRender.shot(self, vc, Vector3(-0.85, 1.32, 1.75), Vector3(-0.85, 2.30, -3.2),
			"skylift_10_amber_constellations")
	host.set_setting("cove", "cyan")
	host.set_setting("starlight", "milky")
	for i in 24:
		host.step(0.25)

	# 6. Arrival & docking at the gleaming white-and-gold orbital station with full Earth curve across the bay!
	RoomJourney.step_stage(host, 1.0)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.06, -0.12), "skylift_11_docking_station")
	await RoomRender.shot(self, vc, eye, eye + Vector3(0.90, 0.02, -0.44), "skylift_12_docking_earth")
	await RoomRender.close(self, vc)
