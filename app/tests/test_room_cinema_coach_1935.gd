extends "res://tests/env_builder_harness.gd"

## Cinema coach 1935 (app/environments/cinema_coach_1935.env.json; docs/environments/rooms/cinema_coach_1935.md): a
## 1935 express newsreel railway cinema carriage in the Journeys arc. Built by Gemini 4 Neon Extra High. Narrow
## mahogany carriage with arched elliptical roof, twenty plush velvet tip-up seats across a central Art Deco carpet
## aisle, curved brass-hooded rear-projection cove surround, continuous brass-and-netting luggage racks, partly drawn
## window blinds, coat hooks, emergency communication cord, aft vestibule door with frosted brass grille and working
## bulkhead clock, swaying hanging brass-and-opal-glass carriage lamps, vintage 1935 newsreel print presentation,
## departure and arrival railway stations, telegraph poles, semaphore signals, and a dark mid-reel railway tunnel.
## godot --headless --xr-mode off --path app --script res://tests/test_room_cinema_coach_1935.gd

const RoomJourney := preload("res://tests/room_journey.gd")
const RoomRender := preload("res://tests/room_render.gd")
const RoomSound := preload("res://tests/room_sound.gd")
const DOC := "res://environments/cinema_coach_1935.env.json"


func run_tests() -> void:
	test_name = "test_room_cinema_coach_1935"
	var doc := RoomJourney.load_doc(self, DOC)
	if doc.is_empty():
		return
	var room := await RoomJourney.check_journey(self, "cinema_coach_1935", doc, "carriage", "track", {
			"min_speed": 4.4, "max_speed": 5.5, "start_landmark": "station", "end_landmark": "station"})
	RoomJourney.check_fittings(self, room, "carriage", "fittings",
			"the 1935 cinema coach proscenium, racks and aft vestibule", 4)
	check("the aft railway bulkhead clock is built (PieceClock)", room.find_child("PieceClock", true, false) != null)
	check("the brass-hooded screen cove is built (PieceCove)", room.find_child("PieceCove", true, false) != null)
	check("the room is credited to Gemini 4 Neon Extra High",
			str((doc.get("room", {}) as Dictionary).get("author", "")) == "Gemini 4 Neon Extra High")
	var seats: Array[Transform3D] = room.room_seat_transforms()
	var own := seats.any(func(t: Transform3D) -> bool: return t.origin.length() < 0.001)
	check("five rows of four plush cinema seats (%d), one at the origin" % seats.size(), seats.size() == 20 and own)
	_swaying_lamps(room)
	_tunnel_arc(room)
	_settings(room)
	# Sound: rail joints following journey.speed (silent in station, rhythmic under way), steam train whistle one-shot,
	# rear-projection booth hum behind front bulkhead, faint night wind; small_room carriage acoustics.
	RoomSound.check_beds(self, "cinema_coach_1935", room, {"bogies": "rail_joints", "whistle": "train_whistle",
			"projector": "projector", "wind": "wind"}, "small_room")
	RoomJourney.check_speed_bed(self, room, "bogies", "the rail joints", 0.0)
	RoomJourney.check_figures(self, "cinema_coach_1935", room, 38, 120000)
	await done(room)
	await RoomSound.check_level(self, self, "cinema_coach_1935", doc)
	await _render(doc)


## Hanging brass-and-opal-glass carriage lamps sway gently in unison with journey.speed while the carriage stays level.
func _swaying_lamps(room: Node3D) -> void:
	var host: Node = room.host
	var left: Node = host.system("sway_left")
	var right: Node = host.system("sway_right")
	var kl: Node = host.system("lamps_left")
	var kr: Node = host.system("lamps_right")
	check("both lamp kits built with no problems", kl != null and kr != null and kl.problems().is_empty()
			and kr.problems().is_empty())
	check("both lamp movers target their rack_lamps groups", left != null and right != null
			and left.target() != null and right.target() != null)
	if left == null or right == null:
		return
	host.timeline.state = ""
	var pos := 1000.0
	var peak_run := 0.0
	for i in 120:
		pos += 0.25
		host.snapshot_override = {"open": true, "playing": true, "position": pos, "duration": RoomJourney.FILM}
		host.step(0.25)
		peak_run = maxf(peak_run, absf(float(left.call("_angle_now"))))
	var ang_l := float(left.call("_angle_now"))
	var ang_r := float(right.call("_angle_now"))
	check("under way: carriage lamps sway together (peak %.2f deg, L %.2f R %.2f)" % [peak_run, ang_l, ang_r],
			peak_run > 1.2 and peak_run <= 2.1 and absf(ang_l - ang_r) < 0.05)
	host.snapshot_override = {"open": true, "playing": false, "position": pos, "duration": RoomJourney.FILM}
	for i in 120:
		host.step(0.25)
	var peak_stop := 0.0
	for i in 40:
		host.step(0.25)
		peak_stop = maxf(peak_stop, absf(float(left.call("_angle_now"))))
	check("in station: carriage lamps settle gently (peak %.2f deg)" % peak_stop, peak_stop <= 0.25)


## Mid-journey railway tunnel: track.tunnel and sky.blackout darken outside scenery & stars smoothly, then emerge,
## while the interior cove keeps glowing softly via cove_floor.
func _tunnel_arc(room: Node3D) -> void:
	var host: Node = room.host
	var track: Node = host.system("track")
	var sky: Node = host.system("sky")
	var kit: Node = host.system("fittings")
	RoomJourney.step_stage(host, 0.25)
	var before_t := float(track.params["tunnel"])
	var before_b := float(sky.params["blackout"])
	RoomJourney.step_stage(host, 0.49)
	var inside_t := float(track.params["tunnel"])
	var inside_b := float(sky.params["blackout"])
	var pmat: ShaderMaterial = track.material_of("Passing")
	var shown_in := float(pmat.get_shader_parameter("shown")) if pmat != null else 1.0
	var cove_in := float(kit.cove_state().get("glow", 0.0))
	RoomJourney.step_stage(host, 0.72)
	var after_t := float(track.params["tunnel"])
	var after_b := float(sky.params["blackout"])
	check("open countryside before tunnel (tunnel %.2f, blackout %.2f)" % [before_t, before_b],
			before_t < 0.05 and before_b < 0.05)
	check("mid-reel railway tunnel blacks out scenery and sky (tunnel %.2f, blackout %.2f, shown %.2f)" % [
			inside_t, inside_b, shown_in], inside_t > 0.95 and inside_b > 0.95 and shown_in < 0.05)
	check("warm brass-hooded cove keeps glowing inside dark tunnel (glow %.2f)" % cove_in, cove_in > 0.35)
	check("emerge back into starlit countryside after tunnel (tunnel %.2f, blackout %.2f)" % [after_t, after_b],
			after_t < 0.05 and after_b < 0.05)


## Live settings: Lighting (Warm amber / Ruby cove / Off) and Picture (Newsreel print / Clean picture).
func _settings(room: Node3D) -> void:
	var host: Node = room.host
	var pres: Node = host.system("presentation")
	var kit: Node = host.system("fittings")
	check("presentation defaults to 1935 newsreel film print (worn_print, film)", pres != null
			and str(pres.value("preset")) == "worn_print" and str(pres.value("source")) == "film")
	host.set_setting("picture", "clean")
	host.step(0.25)
	check("picture=clean disables film print stages", str(pres.value("source")) == "none"
			and not bool(pres.picture_on()))
	host.set_setting("picture", "newsreel")
	host.step(0.25)
	host.set_setting("lighting", "ruby")
	for i in 12:
		host.step(0.25)
	var ruby_st: Dictionary = kit.cove_state()
	var ruby_col: Color = ruby_st.get("colour", Color.BLACK)
	check("Lighting=ruby turns screen cove and cornice ruby (%s)" % ruby_col,
			not ruby_st.is_empty() and ruby_col.r > ruby_col.g * 2.5)
	host.set_setting("lighting", "off")
	for i in 12:
		host.step(0.25)
	check("Lighting=off switches off coves (%.2f)" % float(kit.cove_state().get("glow", 1.0)),
			float(kit.cove_state().get("glow", 1.0)) < 0.05)
	host.set_setting("lighting", "amber")
	for i in 12:
		host.step(0.25)


func _render(doc: Dictionary) -> void:
	if not RoomRender.has_renderer():
		print("SKIP render (headless)")
		return
	var sc: Array = doc["screen"]["center"]
	var screen := Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
	RoomRender.set_light(screen, 0.018)
	var vc := await RoomRender.open(self, doc)
	var host: Node = (vc[2] as Node).host
	host.signals.fake("film.brightness", 0.6)
	host.signals.fake("playback.playing", 1.0)
	var eye := Vector3(0.0, 1.2, 0.0)
	# Pre-show: parked at the warm-lit 1935 railway station platform; house lamps bright, zero false film spill.
	host.snapshot_override = {"open": false}
	for i in 48:
		host.step(0.25)
	RoomRender.set_light(screen, float(doc["room"]["ambient"]))
	RenderingServer.global_shader_parameter_set("screen_glow", 0.0)
	await RoomRender.shot(self, vc, Vector3(-0.57, 1.56, 3.6), screen, "coach_preshow_front")
	await RoomRender.shot(self, vc, Vector3(-0.57, 1.52, -3.4), Vector3(-0.57, 1.54, 4.6), "coach_preshow_aft")
	await RoomRender.shot(self, vc, eye, screen, "coach_preshow_seat")
	await RoomRender.shot(self, vc, Vector3(-0.42, 1.58, 0.72), Vector3(-2.15, 1.82, -1.25), "coach_preshow_racks")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.04, -0.25), "coach_preshow_right")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.04, -0.25), "coach_preshow_left")
	# Restore film spill & dim lighting for station departure (gliding past the warm departure platform as lamps dim).
	RoomRender.set_light(screen, 0.018)
	host.snapshot_override = {"open": true, "playing": true, "position": 1.5, "duration": RoomJourney.FILM}
	host.signals.fake("film.progress", 0.0002)
	host.signals.fake("film.minutes", 0.025)
	for i in 20:
		host.step(0.25)
	await RoomRender.shot(self, vc, eye, screen, "coach_station_seat")
	await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.04, -0.25), "coach_station_left")
	await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.04, -0.25), "coach_station_right")
	await RoomRender.shot(self, vc, Vector3(-0.57, 3.2, 0.0), Vector3(-60.0, 1.6, -16.0), "coach_station_ext_left")
	await RoomRender.shot(self, vc, Vector3(-0.57, 3.2, 0.0), Vector3(60.0, 1.6, -16.0), "coach_station_ext_right")
	# Four later journey stages: starlit countryside with telegraph poles & left signal, pitch-dark railway tunnel
	# (plus ruby cove look), tunnel-exit emerald semaphore signal framed in the right window, and terminus arrival.
	for stage: Array in [["countryside", 0.2167], ["tunnel", 0.49], ["signal", 0.5702], ["arrival", 1.0]]:
		RoomJourney.step_stage(host, float(stage[1]))
		var n := str(stage[0])
		await RoomRender.shot(self, vc, eye, screen, "coach_%s_seat" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(-1.0, 0.04, -0.25), "coach_%s_left" % n)
		await RoomRender.shot(self, vc, eye, eye + Vector3(1.0, 0.04, -0.25), "coach_%s_right" % n)
		if n == "tunnel":
			await RoomRender.shot(self, vc, Vector3(-0.57, 1.56, 3.6), screen, "coach_tunnel_cabin")
			host.set_setting("lighting", "ruby")
			for j in 12:
				host.step(0.25)
			await RoomRender.shot(self, vc, Vector3(-0.57, 1.56, 3.6), screen, "coach_tunnel_ruby")
			host.set_setting("lighting", "amber")
			for j in 12:
				host.step(0.25)
		elif n in ["countryside", "signal", "arrival"]:
			await RoomRender.shot(self, vc, Vector3(-0.57, 3.2, 0.0), Vector3(-60.0, 1.6, -16.0),
					"coach_%s_ext_left" % n)
			await RoomRender.shot(self, vc, Vector3(-0.57, 3.2, 0.0), Vector3(60.0, 1.6, -16.0),
					"coach_%s_ext_right" % n)
	await RoomRender.close(self, vc)
