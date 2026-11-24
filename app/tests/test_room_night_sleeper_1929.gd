extends "res://tests/env_builder_harness.gd"

## Night sleeper, 1929 (app/environments/night_sleeper_1929.env.json; docs/environments/rooms/night_sleeper_1929.md):
## an intimate 1929 Art Deco marquetry sleeping compartment crossing a snowy alpine winter night into rosy dawn.
## Built by Gemini 4 Neon Extra High. Features inlaid walnut & brass corridor panelling, recessed sliding frosted-glass
## corridor door, stowed upper sleeping berth & claret velvet lower berth, brass luggage rack & working railway clock,
## glowing sapphire-blue ceiling night lamp (PieceCove, cove_floor 0.65), tabletop 1929 16 mm projector with dusty warm
## beam onto a portable roller linen screen, falling snow outside the panoramic left window, and midnight-to-alpine-dawn
## arrival with the credits.
## godot --headless --xr-mode off --path app --script res://tests/test_room_night_sleeper_1929.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const NightSleeper := preload("res://scripts/env/systems/kit/night_sleeper_1929.gd")
const DOC := "res://environments/night_sleeper_1929.env.json"


func run_tests() -> void:
	test_name = "test_room_night_sleeper_1929"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "night_sleeper_1929", doc, "compartment", "alps", {
			"min_speed": 3.4, "max_speed": 4.2, "start_landmark": "station", "end_landmark": "station"})
	RoomJourney.check_fittings(self, room, "compartment", "fittings",
			"the sleeper compartment berths, front console and projector table", 4)
	check("the corridor bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the sapphire night lamp cove is built (PieceCove)", room.find_child("PieceCove", true, false) != null)
	check("the frosted corridor door panes are built (PieceWindows)",
			room.find_child("PieceWindows", true, false) != null)
	check("the projector lens glow is built (PiecePort)", room.find_child("PiecePort", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("one private compartment seat at the origin (%d)" % seats.size(),
			seats.size() == 1 and seats[0].origin.length() < 0.001)
	await _dawn_and_atmosphere(room)
	_settings(room)
	# Sound: rhythmic rail joints following journey.speed, soft 16 mm tabletop projector hum, winter mountain wind
	# outside the left window, and departure/arrival train whistle; intimate small-room acoustics.
	RoomSound.check_beds(self, "night_sleeper_1929", room, {"rails": "rail_joints", "projector": "projector",
			"wind": "wind", "whistle": "train_whistle"}, "small_room")
	RoomJourney.check_speed_bed(self, room, "rails", "the sleeper rail joints", 0.0)
	RoomJourney.check_figures(self, "night_sleeper_1929", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "night_sleeper_1929", doc)
	await _render(doc)


## Midnight winter stars transition to rosy alpine dawn over the final third of the film; the 16 mm tabletop projector
## beam blooms during playback and stays well within the headset blend-layer budget.
func _dawn_and_atmosphere(room: Node3D) -> void:
	var host: Node = room.host
	var sky: Node = host.system("sky")
	var atm: Node = host.system("atmosphere")
	var weather: Node = host.system("weather")
	var sc_sz: Array = (room.doc["screen"] as Dictionary)["size"]
	host.on_screen_changed(room.get_screen_anchor(), Vector2(float(sc_sz[0]), float(sc_sz[1])))
	check("snowfall particles built outside the left window",
			weather != null and not (weather.areas() as Array).is_empty() and str(weather.params["falls"]) == "snow")
	check("projector beam haze built at the 16 mm tabletop lens (%s)" % atm.lens(),
			atm != null and atm.beam() != null and atm.lens().distance_to(NightSleeper.PROJECTOR_LENS) < 0.01)

	# Pre-show / midnight start: deep night dusk = 1.0, projector beam off.
	host.timeline.state = ""
	host.snapshot_override = {"open": false}
	host.signals.fake("film.progress", 0.0)
	host.signals.fake("playback.playing", 0.0)
	for i in 48:
		host.step(0.25)
	var dusk_night := float(sky.params["dusk"])
	var hor_night: Color = (sky.sky_light() as Dictionary)["horizon"]
	var haze_off := float(atm.params["beam_haze"])
	check("midnight departure: deep winter night (dusk %.2f, horizon %s) and beam off (%.2f)" % [
			dusk_night, hor_night, haze_off], dusk_night > 0.95 and hor_night.b > hor_night.r and haze_off < 0.02)

	# Mid-film playing: still midnight under the Moon, tabletop projector beam & dust active, blend layers low.
	host.snapshot_override = {"open": true, "playing": true, "position": RoomJourney.FILM * 0.48,
			"duration": RoomJourney.FILM}
	host.signals.fake("film.progress", 0.48)
	host.signals.fake("playback.playing", 1.0)
	for i in 48:
		host.step(0.25)
	var haze_on := float(atm.params["beam_haze"])
	var dust_on := float(atm.params["beam_dust"])
	check("during film: projector beam haze (%.2f) and dust (%.2f) bloom smoothly" % [haze_on, dust_on],
			haze_on > 0.30 and dust_on > 0.48 and atm.beam().visible)
	var layers_play: Dictionary = await EnvChecks.blend_layers(self, room)
	check("blend layers during film with projector beam stay under budget (%s)" % [layers_play],
			float(layers_play["mean"]) <= EnvChecks.BLEND_BUDGET * 0.6)

	# Final third -> rosy alpine dawn arrival (film.progress 0.66 -> 1.0).
	host.signals.fake("film.progress", 1.0)
	for i in 48:
		host.step(0.25)
	var dusk_dawn := float(sky.params["dusk"])
	var hor_dawn: Color = (sky.sky_light() as Dictionary)["horizon"]
	check("rosy alpine dawn arrival: sky.dusk falls to %.2f and horizon turns warm rose (%s)" % [
			dusk_dawn, hor_dawn], dusk_dawn < 0.16 and hor_dawn.r > hor_dawn.b * 1.4 and hor_dawn.r > 0.6)
	host.signals.clear_fakes()


## Live settings: Night lamp (Sapphire blue / Warm amber / Off + stays lit via cove_floor), Snowfall, and Film print.
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var kit: Node = host.system("fittings")
	var weather: Node = host.system("weather")
	var pres: Node = host.system("presentation")

	# Night lamp defaults to glowing sapphire blue and keeps glowing via cove_floor even with house lamps dimmed.
	host.snapshot_override = {"open": true, "playing": true, "position": 300.0, "duration": RoomJourney.FILM}
	for i in 32:
		host.step(0.25)
	var st_sap: Dictionary = kit.cove_state()
	var c_sap: Color = st_sap.get("colour", Color.BLACK)
	var g_sap := float(st_sap.get("glow", 0.0))
	check("Night lamp=sapphire glows sapphire blue even dimmed (%s, glow %.2f)" % [c_sap, g_sap],
			c_sap.b > c_sap.r * 2.5 and g_sap > 0.9)

	host.set_setting("night_lamp", "amber")
	for i in 8:
		host.step(0.25)
	var c_amb: Color = (kit.cove_state() as Dictionary).get("colour", Color.BLACK)
	check("Night lamp=amber shifts ceiling globe & halo to warm amber (%s)" % c_amb, c_amb.r > c_amb.b * 2.0)

	host.set_setting("night_lamp", "off")
	for i in 8:
		host.step(0.25)
	var g_off := float((kit.cove_state() as Dictionary).get("glow", 1.0))
	check("Night lamp=off turns night lamp completely off (glow %.2f)" % g_off, g_off < 0.01)
	host.set_setting("night_lamp", "sapphire")
	host.step(0.25)

	# Snowfall live setting: light -> heavy -> clear -> light.
	host.set_setting("snowfall", "heavy")
	for i in 80:
		host.step(0.25)
	check("Snowfall=heavy brings snow to full (%.2f)" % weather.snow_amount(), weather.snow_amount() > 0.9)
	host.set_setting("snowfall", "clear")
	for i in 120:
		host.step(0.25)
	check("Snowfall=clear stops the snow (%.2f)" % weather.snow_amount(), weather.snow_amount() < 0.03)
	host.set_setting("snowfall", "light")
	for i in 80:
		host.step(0.25)
	check("Snowfall=light holds gentle flurries (%.2f)" % weather.snow_amount(),
			weather.snow_amount() > 0.2 and weather.snow_amount() < 0.45)

	# Film print live setting: 1929 home print -> Clean picture -> 1929 home print.
	check("Film print defaults to 1929 16 mm film print (source=%s, weave=%.2f)" % [
			pres.value("source"), float(pres.value("weave"))],
			pres != null and str(pres.value("source")) == "film" and float(pres.value("weave")) > 0.25)
	host.set_setting("film_print", "clean")
	host.step(0.25)
	check("Film print=clean switches off film stage cleanly",
			str(pres.value("source")) == "none" and not pres.picture_on())
	host.set_setting("film_print", "print")
	host.step(0.25)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.05)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	var eye := Vector3(0.0, 1.2, 0.0)

	# Pre-show: warm Art Deco reading sconces + sapphire night lamp, berthed at snowy midnight departure station.
	host.snapshot_override = {"open": false}
	host.signals.fake("film.progress", 0.0)
	host.signals.fake("playback.playing", 0.0)
	host.set_setting("snowfall", "heavy")
	host.set_setting("night_lamp", "sapphire")
	for i in 80:
		host.step(0.25)
	RoomRender.set_light(screen, 0.05)
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(0.86, 1.54, 1.05), Vector3(-0.22, 1.24, -2.1), "sleeper_preshow_overview")
	await RoomRender.shot(self, vc, Vector3(-0.88, 1.48, 0.45), Vector3(1.30, 1.45, -0.72), "sleeper_preshow_corridor")
	await RoomRender.shot(self, vc, Vector3(-0.42, 1.48, -1.48), Vector3(0.10, 1.20, 1.78), "sleeper_preshow_berths")
	await RoomRender.shot(self, vc, Vector3(0.18, 1.26, -0.25), Vector3(-1.00, 0.90, -0.96), "sleeper_preshow_projector")

	# Film playing: dimmed sconces, glowing sapphire ceiling night lamp, warm 16 mm projector beam & dust motes!
	host.signals.fake("film.brightness", 0.65)
	host.signals.fake("playback.playing", 1.0)
	RoomRender.set_light(screen, 0.018)
	# Stage 1: snowy midnight departure station.
	RoomJourney.step_stage(host, 0.0004)
	await RoomRender.shot(self, vc, eye, Vector3(-0.34, 1.32, -2.34), "sleeper_departure_seat")
	await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.26, -0.42), "sleeper_departure_window")

	# Stage 2a: deep winter midnight crossing — snow-capped pines, silver birches, alpine peaks & gibbous Moon.
	RoomJourney.step_stage(host, 0.38)
	await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.34, -0.40), "sleeper_midnight_forest")
	await RoomRender.shot(self, vc, Vector3(-1.6, 2.5, 0.0), Vector3(-80.0, 4.5, -16.0), "sleeper_midnight_outside")

	# Stage 2b: sleeping snowbound wayside station at mid-night (landmark at 0.48, stepping ~67 m across 20 s).
	RoomJourney.step_stage(host, 0.4767)
	await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.26, -0.42), "sleeper_midnight_station")

	# Stage 3: alpine forest under rising rosy dawn (film.progress 0.88).
	host.set_setting("snowfall", "light")
	RoomJourney.step_stage(host, 0.88)
	await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.34, -0.40), "sleeper_dawn_window")

	# Stage 4: rosy golden-rose alpine dawn arrival at the destination station (credits at 0.9995, dimmed interior).
	RoomJourney.step_stage(host, 0.9995)
	await RoomRender.shot(self, vc, eye, Vector3(-2.0, 1.32, -0.40), "sleeper_arrival_window")
	await RoomRender.shot(self, vc, Vector3(0.75, 1.46, 0.98), Vector3(-1.25, 1.40, -0.95), "sleeper_arrival_cabin")
	await RoomRender.shot(self, vc, Vector3(-1.6, 2.5, 0.0), Vector3(-80.0, 4.8, -16.0), "sleeper_arrival_outside")
	await RoomRender.close(self, vc)
