extends SceneTree

## Integration test for the playback features hub (scripts/play/features.gd, docs/features.md): loads the real main
## scene with a test pattern and checks each feature end to end, without a headset. Settings are read-only.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_features.gd

var _failures := 0
var _checks := 0
var main: Node3D


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	var f: Node = main.features
	_check("hub exists", f != null)
	main.open_path("stub://flat_sbs")
	await _frames(10)
	main.player.seek(100.0)
	await _frames(5)

	# #36 end time
	_check("end text '%s'" % f.end_text(), f.end_text().begins_with("ends "))
	_check("overlay time line has the end time", "ends " in main._overlay_text())

	# #2 battery forecast (a desktop: maybe no battery; either way a forecast with the film end)
	var fc: Dictionary = f.battery.sample()
	_check("battery forecast has a film end (%s)" % fc.get("text", ""), str(fc.get("film_end_text", "")) != "")
	_check("overlay battery line '%s'" % f.battery_text(), f.battery_text() != "")

	# #4 3D depth: global, then this file's own value, then back to the global one; another file keeps the global.
	var mat: ShaderMaterial = main.screen.material
	f.depth.set_depth(0.01)
	_check("global depth reaches the shader", is_equal_approx(mat.get_shader_parameter("stereo_shift"), 0.01))
	f.depth.set_depth(-0.02, true)
	_check("file depth wins", f.depth.has_file_value() and is_equal_approx(mat.get_shader_parameter("stereo_shift"), -0.02))
	f.depth.nudge(0.002)
	_check("nudge moves the file's value", is_equal_approx(f.depth.value, -0.018))
	main.open_path("stub://360_tb")
	await _frames(5)
	_check("another file uses the global depth", not f.depth.has_file_value() and is_equal_approx(f.depth.value, 0.01))
	_check("360 wraps horizontally", mat.get_shader_parameter("wrap_x") == true)
	main.open_path("stub://flat_sbs")
	await _frames(5)
	_check("the file's depth comes back", is_equal_approx(f.depth.value, -0.018))
	f.depth.clear_file()
	_check("clear_file: back to global", is_equal_approx(f.depth.value, 0.01) and not f.depth.has_file_value())
	_check("flat does not wrap", mat.get_shader_parameter("wrap_x") == false)
	f.depth.set_depth(0.0)

	# #7 resume: play past the minimum, switch files, come back: resumed near the old place; continue watching lists it.
	var r: Node = f.resume
	r.mode = "auto"
	main.player.seek(200.0)
	await _frames(3)
	main.open_path("stub://360_mono")
	await _frames(3)
	var e: Dictionary = r.entry_for("stub://flat_sbs")
	_check("position saved on switching files (%s)" % e, absf(float(e.get("position", 0.0)) - 200.0) < 2.0)
	_check("continue watching lists it", r.continue_watching().any(func(x: Dictionary) -> bool:
			return x["path"] == "stub://flat_sbs"))
	var got := [-1.0]
	r.resumed.connect(func(p: float) -> void: got[0] = p, CONNECT_ONE_SHOT)
	main.open_path("stub://flat_sbs")
	await _frames(5)
	_check("resumed at the saved place (%.1f, playing at %.1f)" % [got[0], main.player.get_position()],
			absf(got[0] - 200.0) < 2.0 and absf(main.player.get_position() - 197.0) < 3.0)
	# A short visit to a saved file keeps its place.
	main.player.seek(5.0)
	await _frames(2)
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("a short visit keeps the place", absf(r.position_for("stub://flat_sbs") - 200.0) < 3.0)
	# Near the end: finished, position cleared, not in continue watching.
	main.open_path("stub://flat_sbs")
	await _frames(3)
	main.player.seek(main.player.get_duration() - 10.0)
	await _frames(2)
	main.player.pause()
	await _frames(1)
	e = r.entry_for("stub://flat_sbs")
	_check("finished near the end (%s)" % e, bool(e.get("finished", false)) and float(e.get("position", -1.0)) == 0.0)
	_check("finished files leave continue watching", not r.continue_watching().any(func(x: Dictionary) -> bool:
			return x["path"] == "stub://flat_sbs"))
	# "ask" mode: offered, not sought.
	main.player.play()
	main.player.seek(300.0)
	await _frames(2)
	main.open_path("stub://360_mono")
	await _frames(2)
	r.mode = "ask"
	main.open_path("stub://flat_sbs")
	await _frames(3)
	_check("ask mode offers without seeking (%.1f)" % r.pending_position, absf(r.pending_position - 300.0) < 2.0
			and main.player.get_position() < 10.0)
	r.resume()
	await _frames(2)
	_check("resume() seeks", main.player.get_position() > 290.0)
	r.start_over()
	await _frames(2)
	_check("start_over() goes to 0 and clears the place", main.player.get_position() < 1.0
			and r.position_for("stub://flat_sbs") == 0.0)
	r.mode = "auto"

	# Subtitles: the test pattern's tracks, on, lines at their times, kept after a jump back, off.
	var sub: Node = f.subtitles
	main.open_path("stub://flat_mono")
	await _frames(3)
	_check("pattern has two subtitle tracks", sub.tracks.size() == 2 and sub.track == -1)
	sub.select_track(0)
	main.player.seek(20.0)
	main.player.play()
	await _wait_until(func() -> bool: return sub.text != "", 3.0)
	_check("a line shows at 20 s: '%s'" % sub.text, sub.text == "Line 5 at 0:20")
	await _frames(2)
	var rd: Node3D = sub.display
	_check("the renderer shows it", rd.is_showing() and _labels(rd).size() == 1
			and _labels(rd)[0].get_parsed_text() == sub.text)
	await _subtitle_renderer_checks(main, sub, rd)
	_check("text_at between lines is empty", sub.text_at(23.5) == "")
	sub.add_event(30.0, -1.0, "open end")
	sub.add_event(31.0, 33.0, "overlap")
	_check("open-ended event lasts until the next one", sub.text_at(30.5) == "open end" and sub.text_at(31.5) == "overlap")
	main.player.seek(10.0)
	await _frames(2)
	_check("earlier lines kept after a jump back (%d events)" % sub.event_count(), sub.text_at(20.5) == "Line 5 at 0:20")
	sub.cycle_track()
	_check("cycle: second track", sub.track == 1 and sub.enabled)
	sub.cycle_track()
	_check("cycle: off", sub.track == -1 and not sub.enabled and sub.text == "")
	main.open_path("stub://360_mono")
	await _frames(3)
	_check("off stays off on the next file", sub.track == -1)
	f.languages.forget()  # the cycling above was a user's choice of French (language memory, #28)
	sub.set_enabled(true)
	_check("on picks the first text track", sub.track == 0)
	var t360: float = main.player.get_position()
	sub.add_event(t360 - 0.5, t360 + 30.0, "sphere line")
	await _frames(3)
	var q360: Node3D = sub.display.get_node("Quad")
	_check("spherical: a quad low in front (%s)" % q360.global_position, sub.display.is_showing()
			and q360.global_position.z < -1.0 and q360.global_position.y < main.eye_height - 0.2)
	sub.set_enabled(false)

	# #11 catch-up replay: back 10 s, subtitles on, restored (off) once past the start point.
	var cu: Node = f.catch_up
	f.languages.forget()
	main.open_path("stub://flat_mono")
	await _frames(3)
	main.player.seek(60.0)
	main.player.pause()
	await _frames(2)
	cu.replay()
	await _frames(2)
	_check("replay: back 10 s, playing, subtitles on (%.1f)" % main.player.get_position(),
			cu.active and absf(main.player.get_position() - 50.0) < 0.5 and main.player.is_playing() and sub.enabled
			and sub.track == 0)
	await _wait_until(func() -> bool: return sub.text != "", 2.0)
	_check("a line from the replayed part shows: '%s'" % sub.text, sub.text == "Line 11 at 0:50")
	main.player.seek(59.9)
	_check("a seek by someone else ends the replay", not cu.active and not sub.enabled)
	cu.replay()
	await _frames(1)
	# Shorten the wait: the replay ends 0.3 s of playback from here.
	cu.end_position = main.player.get_position() + 0.3
	await _frames(3)
	_check("still replaying before the end point", cu.active and sub.enabled)
	await _wait_until(func() -> bool: return not cu.active, 3.0)
	_check("replay ends at its start point and restores subtitles off", not cu.active and not sub.enabled)
	# Subtitles on with track 1 before: kept as they were.
	sub.select_track(1)
	cu.replay()
	_check("already on: track kept during replay", sub.track == 1)
	cu.cancel()
	_check("cancel restores track 1", sub.track == 1 and sub.enabled)
	# The user turns subtitles off during the replay: their choice stays.
	sub.set_enabled(false)
	cu.replay()
	sub.select_track(1)
	cu.cancel()
	_check("user's change during the replay is kept", sub.enabled and sub.track == 1)
	sub.set_enabled(false)

	# #15 chapters: the pattern's five, skip forward and back, restart within a chapter, ticks, overlay, normalise.
	var ch: Node = f.chapters
	main.open_path("stub://flat_mono")
	await _frames(3)
	main.player.seek(10.0)
	await _frames(3)
	_check("five chapters, in the first (%s)" % ch.title_text(), ch.chapters.size() == 5 and ch.current == 0
			and ch.title_text() == "1/5 Opening")
	ch.next_chapter()
	await _frames(2)
	_check("next: chapter 2 at 120 s", ch.current == 1 and is_equal_approx(main.player.get_position(), 120.0))
	main.player.seek(130.0)
	ch.previous_chapter()
	_check("previous 10 s in: start of this chapter", is_equal_approx(main.player.get_position(), 120.0))
	ch.previous_chapter()
	_check("previous at the start: the chapter before", is_equal_approx(main.player.get_position(), 0.0))
	main.player.seek(590.0)
	ch.next_chapter()
	_check("next in the last chapter does nothing", is_equal_approx(main.player.get_position(), 590.0))
	_check("ticks at 0.2 .. 0.8", ch.tick_positions().size() == 4 and is_equal_approx(ch.tick_positions()[0], 0.2))
	await _frames(3)
	_check("overlay shows the chapter", "chapter 5/5 Closing" in main._overlay_text())
	main.left_hand.button_pressed.emit("chapter_prev")
	_check("d-pad action chapter_prev works", is_equal_approx(main.player.get_position(), 480.0))
	var n: Array[Dictionary] = ch.normalise([{"start": 50.0, "title": ""}, {"start": 0.0, "end": 9999.0, "title": " Intro "}], 100.0)
	_check("normalise: sorted, ends, titles", n[0]["title"] == "Intro" and is_equal_approx(n[0]["end"], 50.0)
			and n[1]["title"] == "Chapter 2" and is_equal_approx(n[1]["end"], 100.0) and n[1]["index"] == 1)

	# #17 sleep timer (short times): fade, pause, saved, room and picture dim until play, sound back; undo on input.
	var sl: Node = f.sleep
	var rl: Node = f.room_light
	main.open_path("stub://flat_mono")
	await _frames(3)
	main.player.seek(100.0)
	main.player.play()
	sl.fade_seconds = 0.6
	sl.start(1.0 / 60.0)
	_check("armed: '%s'" % sl.status_text(), sl.active and sl.status_text() == "sleep in 1 min"
			and "sleep in 1 min" in main._overlay_text())
	await _wait_until(func() -> bool: return sl.fading, 2.0)
	await _frames(5)
	_check("fading: room, picture and sound going down (%.2f, %.2f dB)" % [rl.get_factor("sleep"),
			main.player.audio.volume_db], sl.fading and rl.get_factor("sleep") < 1.0
			and main.player.audio.volume_db < -0.5 and float(mat.get_shader_parameter("brightness")) < 1.0)
	await _wait_until(func() -> bool: return not sl.active, 2.0)
	_check("slept: paused, sound level back", not main.player.is_playing() and is_equal_approx(main.player.audio.volume_db, 0.0))
	_check("slept: room and picture stay dim", is_equal_approx(rl.get_factor("sleep"), sl.ROOM_DIM)
			and is_equal_approx(float(mat.get_shader_parameter("brightness")), sl.PICTURE_DIM))
	_check("slept: position saved for resume", f.resume.position_for("stub://flat_mono") > 100.0)
	main.player.play()
	await _wait_until(func() -> bool: return not rl.is_fading(), 2.0)
	_check("play again: room and picture back", is_equal_approx(rl.get_factor("sleep"), 1.0)
			and is_equal_approx(float(mat.get_shader_parameter("brightness")), 1.0))
	_check("room light applied as the product", is_equal_approx(rl.effective(), main.room_light))
	sl.start(1.0 / 60.0)
	await _wait_until(func() -> bool: return sl.fading, 2.0)
	main.player.seek(50.0)
	_check("a seek during the fade undoes it, timer stays armed", not sl.fading and sl.active
			and is_equal_approx(main.player.audio.volume_db, 0.0))
	sl.cancel()
	_check("cancel", not sl.active)
	sl.cycle()
	_check("cycle: 15 min", sl.active and sl.status_text() == "sleep in 15 min")
	sl.cycle()
	sl.cycle()
	sl.cycle()
	_check("cycle: 90 min", sl.status_text() == "sleep in 90 min")
	sl.cycle()
	_check("cycle: off", not sl.active)
	# End of file: fades over the last part of the file and pauses at the end (the pattern loops: the wrap counts).
	main.auto_advance = true
	main.player.seek(main.player.get_duration() - 1.0)
	sl.start_end_of_file()
	_check("end of file holds auto advance", not main.auto_advance and sl.status_text() == "sleep at end of file")
	await _wait_until(func() -> bool: return not sl.active, 3.0)
	_check("end of file: slept, auto advance back", not sl.active and not main.player.is_playing() and main.auto_advance)
	main.auto_advance = false
	main.player.play()
	await _wait_until(func() -> bool: return not rl.is_fading(), 2.0)
	sl.fade_seconds = sl.FADE_SECONDS

	# #20 room light follows playback: dim while playing, up on pause and with the menu open, off restores.
	var lf: Node = f.light_follow
	if main.ui != null:
		main.ui.hide_panel()
	main.set_environment("cinema")
	main.set_room_light(1.0)
	lf.set_enabled(true)
	main.player.play()
	await _wait_until(func() -> bool: return not rl.is_fading() and rl.get_factor("playback") < 1.0, 4.0)
	_check("playing: room at the play level (%.2f)" % rl.get_factor("playback"),
			is_equal_approx(rl.get_factor("playback"), lf.play_level))
	_check("applied to the environment (%.3f)" % rl._applied, is_equal_approx(rl._applied, lf.play_level))
	main.player.pause()
	await _frames(2)
	await _wait_until(func() -> bool: return not rl.is_fading(), 3.0)
	_check("paused: room up", is_equal_approx(rl.get_factor("playback"), 1.0))
	main.player.play()
	main.set_menu_shown(true)
	await _frames(2)
	await _wait_until(func() -> bool: return not rl.is_fading(), 3.0)
	_check("menu open while playing: room up", is_equal_approx(rl.get_factor("playback"), 1.0))
	main.set_menu_shown(false)
	await _frames(2)
	await _wait_until(func() -> bool: return not rl.is_fading(), 4.0)
	main.set_room_light(0.5)
	await _frames(2)
	_check("the user's room light still applies under the factor (%.3f)" % rl._applied,
			is_equal_approx(rl._applied, 0.5 * lf.play_level))
	lf.set_enabled(false)
	await _frames(2)
	await _wait_until(func() -> bool: return not rl.is_fading(), 3.0)
	_check("off: room back to the user's level", is_equal_approx(rl.effective(), 0.5))
	main.set_room_light(1.0)
	lf.set_enabled(true)
	main.set_environment("void")

	# #25 container metadata first: a stand-in source that reports spherical metadata wins over the name.
	var meta_src := _meta_source({"projection": "equirectangular", "stereo_mode": "2d"}, "/nowhere/clip_SBS.mkv")
	main.current_path = "/nowhere/clip_SBS.mkv"
	main.player.close()
	main.player._use_source(meta_src)
	await _frames(2)
	_check("metadata mode wins over the name (%s, %s)" % [main.mode.to_id(), main.mode_source],
			main.mode.to_id() == "360_mono" and main.mode_source == "metadata")
	var none_src := _meta_source({}, "/nowhere/clip_SBS.mkv")
	main.player.close()
	main.player._use_source(none_src)
	await _frames(2)
	_check("no metadata: the name's guess (%s, %s)" % [main.mode.to_id(), main.mode_source],
			main.mode.to_id() == "flat_sbs_half" and main.mode_source == "auto")
	main.open_path("stub://flat_mono")
	await _frames(2)

	# #27 picture controls: per environment, shader on only when not default, clamped, reset.
	var pc: Node = f.picture
	main.set_environment("cinema")
	_check("defaults: shader stage off", pc.is_default() and mat.get_shader_parameter("pc_enabled") == false)
	pc.set_value("lift", 0.1)
	pc.set_value("contrast", 9.0)
	_check("set: shader on, clamped (%s)" % pc.values, mat.get_shader_parameter("pc_enabled") == true
			and is_equal_approx(float(mat.get_shader_parameter("pc_lift")), 0.1) and is_equal_approx(pc.values["contrast"], 1.5))
	main.set_environment("dim_room")
	_check("another environment has its own (default)", pc.is_default() and mat.get_shader_parameter("pc_enabled") == false)
	main.set_environment("cinema")
	_check("back in the cinema: its values", is_equal_approx(pc.values["lift"], 0.1))
	pc.reset()
	_check("reset", pc.is_default() and not main.settings.has_value("picture_cinema", "lift"))
	main.set_environment("void")

	# #28 language memory: a user's audio and subtitle picks are remembered and applied on the next open.
	var lm: Node = f.languages
	lm.forget()
	main.open_path("stub://flat_mono")
	await _frames(2)
	_check("no preference: default audio track", main.player.source.get_audio_track() == 0)
	main.player.select_audio_track(1)
	_check("audio pick remembered (%s)" % lm.audio_language, lm.audio_language == "ja")
	sub.select_track(1)
	_check("subtitle pick remembered (%s)" % lm.subtitle_language, lm.subtitle_language == "fr")
	sub.set_enabled(false)
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("next file opens with the remembered audio", main.player.source.get_audio_track() == 1)
	sub.set_enabled(true)
	_check("subtitles on pick the remembered language", sub.track == 1)
	cu.replay()
	cu.cancel()
	_check("replay doesn't change the memory", lm.subtitle_language == "fr")
	_check("language groups", lm.same_language("fra", "fre") and lm.same_language("eng", "en-US")
			and lm.same_language("deu", "de") and not lm.same_language("eng", "fre") and not lm.same_language("", "")
			and not lm.same_language("pt-br", "pt-pt") and lm.same_language("German", "ger"))
	_check("forced tracks come after full ones", lm._pick([{"index": 0, "language": "fre", "forced": true},
			{"index": 1, "language": "fra", "forced": false}], "fre", true) == 1)
	_check("forced only picks the forced one", lm._pick([{"index": 0, "language": "fre", "forced": true},
			{"index": 1, "language": "fra", "forced": false}], "fre", true, true) == 0)
	_check("commentary loses", lm._pick([{"index": 0, "language": "en", "commentary": true, "default": true},
			{"index": 1, "language": "en"}], "en", false) == 1)
	_check("a list: the first language with a track wins", lm._pick([{"index": 0, "language": "de"},
			{"index": 1, "language": "fr"}], PackedStringArray(["it", "fr", "de"]), false) == 1)
	main.player.select_audio_track(0)
	_check("the list keeps the last choices, newest first (%s)" % lm.audio_languages,
			lm.audio_languages == PackedStringArray(["en", "ja"]))
	sub.set_enabled(false)
	lm.forget()

	# #31 curved screen: a cylinder section of the set radius, per environment, flat again at 0.
	var cs: Node = f.curve
	main.open_path("stub://flat_mono")
	await _frames(2)
	cs.match_distance()
	var flat_mesh: MeshInstance3D = main.screen.get_node("Flat")
	_check("curved mesh at the screen distance (%.2f)" % cs.radius, flat_mesh.mesh is ArrayMesh
			and is_equal_approx(main.screen.curve_radius, main.screen_distance))
	var aabb: AABB = flat_mesh.mesh.get_aabb()
	var size: Vector2 = main.screen.get_flat_size()
	var r_now: float = cs.radius
	var depth := r_now * (1.0 - cos(size.x / r_now * 0.5))
	_check("edges come toward the viewer by R(1 - cos(theta/2)) (%.3f vs %.3f)" % [aabb.size.z, depth],
			absf(aabb.size.z - depth) < 0.01 and aabb.position.z > -0.001)
	_check("chord narrower than the arc", aabb.size.x < size.x and aabb.size.x > size.x * 0.8)
	cs.set_radius(0.5)
	_check("below the minimum: flat", cs.radius == 0.0 and flat_mesh.mesh is QuadMesh)
	cs.set_radius(6.0)
	main.set_environment("dim_room")
	_check("another environment: its own radius (flat)", cs.radius == 0.0 and flat_mesh.mesh is QuadMesh)
	main.set_environment("void")
	_check("back: 6 m", is_equal_approx(cs.radius, 6.0) and flat_mesh.mesh is ArrayMesh)
	# The amount (the Picture tab's 0..100 %): radius = distance / amount, never below the distance; it holds when the
	# distance changes.
	var d0: float = main.screen_distance
	cs.set_amount(0.5)
	_check("50 %%: radius twice the distance (%.2f at %.2f m)" % [cs.radius, d0], is_equal_approx(cs.radius, d0 * 2.0))
	main.set_screen(main.screen_width, d0 + 1.0, main.screen_height_offset)
	_check("the distance changes: 50 %% holds (%.2f m)" % cs.radius, is_equal_approx(cs.amount, 0.5)
			and is_equal_approx(cs.radius, (d0 + 1.0) * 2.0) and is_equal_approx(main.screen.curve_radius, cs.radius)
			and is_equal_approx(float(main.settings.get_value("screen_void", "curve_radius", 0.0)), snappedf(cs.radius, 0.01)))
	main.set_screen(main.screen_width, d0, main.screen_height_offset)
	cs.set_radius(d0 * 0.4)
	_check("a radius below the distance is 100 %% (no tube)", is_equal_approx(cs.amount, 1.0)
			and is_equal_approx(cs.radius, d0))
	_check("radius_for / amount_for", is_equal_approx(cs.radius_for(12.0, 0.25), 48.0)
			and is_equal_approx(cs.amount_for(12.0, 2.5), 1.0) and cs.radius_for(12.0, 0.0) == 0.0)
	cs.set_amount(0.0)
	_check("0 %: flat", cs.radius == 0.0 and flat_mesh.mesh is QuadMesh)
	cs.set_radius(0.0)

	# #32 haptics: hover pulses, rate-limited; a seek with no stick sends none; a chapter press then seek sends one.
	var hp: Node = f.haptics
	var n0: int = hp.pulses
	_check("hover pulses", hp.hover(main.right_hand) == null and hp.pulses == n0 + 1)
	_check("rate-limited", not hp.tick(main.right_hand, "hover") and hp.pulses == n0 + 1)
	await _sleep(0.06)
	main.player.seek(30.0)
	_check("seek without a stick: no pulse", hp.pulses == n0 + 1)
	main.left_hand.button_pressed.emit("chapter_next")
	_check("chapter button pulses on that hand", hp.pulses == n0 + 2)
	hp.set_enabled(false)
	_check("off: nothing", not hp.tick(main.left_hand) and hp.pulses == n0 + 2)
	hp.set_enabled(true)

	# #35 zoom and pan: per file, pan limited by the zoom, ignored for spherical modes.
	var zp: Node = f.zoom
	main.open_path("stub://flat_mono")
	await _frames(2)
	zp.set_zoom(1.25)
	zp.set_pan(Vector2(0.5, -0.5))
	_check("pan limited to 0.5 - 0.5/zoom (%s)" % zp.pan, is_equal_approx(zp.pan.x, 0.1) and is_equal_approx(zp.pan.y, -0.1))
	_check("shader gets zoom and pan", is_equal_approx(float(mat.get_shader_parameter("zoom")), 1.25)
			and (mat.get_shader_parameter("pan") as Vector2).is_equal_approx(Vector2(0.1, -0.1)))
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("another file: no zoom; spherical ignores it", is_equal_approx(zp.zoom, 1.0)
			and is_equal_approx(float(mat.get_shader_parameter("zoom")), 1.0))
	main.open_path("stub://flat_mono")
	await _frames(2)
	_check("back: its zoom", is_equal_approx(zp.zoom, 1.25))
	zp.reset()
	_check("reset forgets it", not main.settings.has_value("zoom_files", preload("res://scripts/play/file_key.gd").key("stub://flat_mono")))

	# #59 2D from 3D: the shader gets the eye; cycle off -> left -> right -> off.
	var td: Node = f.two_d
	td.cycle()
	_check("left eye to both", td.eye == 0 and int(mat.get_shader_parameter("mono_eye")) == 0)
	td.cycle()
	_check("right eye to both", td.eye == 1 and td.describe() == "2D (right eye)")
	td.cycle()
	_check("off", td.eye == -1 and int(mat.get_shader_parameter("mono_eye")) == -1
			and not main.settings.has_value("stereo", "mono_eye"))

	# #77 horizon: roll and pitch turn the sphere in its own frame, per file.
	var hz: Node = f.horizon
	main.open_path("stub://360_mono")
	await _frames(2)
	hz.set_trim(0.0, 10.0)
	await _frames(2)
	var sphere: MeshInstance3D = main.screen.get_node("Sphere")
	var up: Vector3 = sphere.global_basis.y
	_check("roll 10 degrees tilts the sphere's up (%.1f°)" % rad_to_deg(up.angle_to(Vector3.UP)),
			absf(rad_to_deg(up.angle_to(Vector3.UP)) - 10.0) < 0.1)
	hz.set_trim(5.0, 0.0)
	await _frames(2)
	var fwd: Vector3 = -sphere.global_basis.z
	_check("pitch 5 tips the front (%.1f°)" % rad_to_deg(asin(fwd.y)), absf(rad_to_deg(asin(fwd.y)) - 5.0) < 0.1)
	hz.set_trim(99.0, -99.0)
	_check("clamped to ±20", is_equal_approx(hz.pitch, 20.0) and is_equal_approx(hz.roll, -20.0))
	main.open_path("stub://180_mono")
	await _frames(2)
	_check("another file: level", hz.pitch == 0.0 and hz.roll == 0.0 and main.screen.sphere_tilt == Vector2.ZERO)
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("back: its trim", is_equal_approx(hz.pitch, 20.0))
	hz.reset()

	# #79 edge fade: flat 3D only, off for mono, spherical and 2D-from-3D.
	var ef: Node = f.edge_fade
	main.open_path("stub://flat_sbs")
	await _frames(2)
	ef.set_width(0.03)
	_check("flat SBS: fade on", is_equal_approx(float(mat.get_shader_parameter("edge_fade")), 0.03))
	f.two_d.set_eye(0)
	_check("2D from 3D: off", float(mat.get_shader_parameter("edge_fade")) == 0.0)
	f.two_d.set_eye(-1)
	main.open_path("stub://flat_mono")
	await _frames(2)
	_check("mono: off", float(mat.get_shader_parameter("edge_fade")) == 0.0)
	main.open_path("stub://180_sbs")
	await _frames(2)
	_check("spherical 3D: off", float(mat.get_shader_parameter("edge_fade")) == 0.0)
	ef.set_width(0.0)

	# #61 subtitle delay: per file and track; the line shows later by the delay.
	var sd: Node = f.sub_delay
	f.languages.forget()
	main.open_path("stub://flat_mono")
	await _frames(2)
	sub.select_track(0)
	sd.set_delay(1.5)
	_check("delay reaches the subtitles", is_equal_approx(sub.delay, 1.5))
	sub.add_event(500.0, 503.0, "delayed line")
	main.player.pause()
	main.player.seek(500.5)
	await _frames(2)
	_check("not yet at 500.5 with +1.5 s ('%s')" % sub.text, sub.text == "")
	main.player.seek(501.6)
	await _frames(2)
	_check("shows at 501.6 ('%s')" % sub.text, sub.text == "delayed line")
	sub.select_track(1)
	_check("other track: its own (0)", is_zero_approx(sd.delay))
	sub.select_track(0)
	_check("back: 1.5", is_equal_approx(sd.delay, 1.5))
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("other file: 0", is_zero_approx(sd.delay) and is_zero_approx(sub.delay))
	main.open_path("stub://flat_mono")
	await _frames(2)
	sub.select_track(0)
	sd.reset()
	sub.set_enabled(false)
	f.languages.forget()
	main.player.play()

	# #60 sidecar: a user's mode is written next to a local file, read back when the settings forget it, removed by Auto.
	var dir := OS.get_user_data_dir().path_join("test_sidecar_mode")
	DirAccess.make_dir_recursive_absolute(dir)
	var clip := dir.path_join("clip.mkv")
	FileAccess.open(clip, FileAccess.WRITE).store_string("not a video")
	main.open_path(clip)
	await _frames(3)
	_check("sidecar writing is off by default", not f.sidecar.enabled)
	f.sidecar.set_enabled(true)
	var picked := preload("res://scripts/video_mode.gd").from_id("flat_tb_half")
	main.set_video_mode(picked)
	var sc_path: String = f.sidecar.sidecar_path(clip)
	_check("sidecar written (%s)" % sc_path.get_file(), FileAccess.file_exists(sc_path)
			and f.sidecar.read_mode(clip) == "flat_tb_half")
	main.settings.set_file_mode(clip, "")
	main.open_path(clip)
	await _frames(3)
	_check("read back when the settings don't know it (%s, %s)" % [main.mode.to_id(), main.mode_source],
			main.mode.to_id() == "flat_tb_half" and main.mode_source == "sidecar")
	main.auto_mode()
	_check("Auto removes our sidecar", not FileAccess.file_exists(sc_path))
	FileAccess.open(sc_path, FileAccess.WRITE).store_string("{\"mode\": \"flat_sbs\", \"note\": \"someone else's\"}")
	main.auto_mode()
	_check("a sidecar with other keys is not deleted", FileAccess.file_exists(sc_path))
	_check("network paths are never written", not f.sidecar.write_mode("smb://host/share/x.mkv", "flat_sbs"))
	f.sidecar.set_enabled(false)
	DirAccess.remove_absolute(sc_path)
	DirAccess.remove_absolute(clip)
	DirAccess.remove_absolute(dir)
	main.open_path("stub://flat_mono")
	await _frames(2)

	# #78 queue: shuffle keeps the current file first and restores the order; repeat one / all; editing.
	var q: Node = f.queue
	q.set_repeat("off")
	q.set_shuffle(false)
	q.set_continuous(false)
	# The up-next countdown (#34, tests/test_delight.gd) would hold each advance for seconds: off here.
	f.up_next.enabled = false
	main.open_path("stub://flat_mono")
	await _frames(2)
	var original: Array[String] = main.playlist.duplicate()
	q.seed_shuffle(7)
	q.set_shuffle(true)
	_check("shuffle: same files, current first, order changed", main.playlist.size() == original.size()
			and main.playlist[0] == "stub://flat_mono" and main.playlist_index == 0 and main.playlist != original
			and q._same_items(main.playlist, original))
	q.set_shuffle(false)
	_check("unshuffle restores the order", main.playlist == original)
	q.play_next("stub://360_tb")
	_check("play next: right after the current", main.playlist[main.playlist_index + 1] == "stub://360_tb")
	q.move(main.playlist.size() - 1, 1)
	q.remove(1)
	_check("move and remove keep the index on the current file", main.playlist[main.playlist_index] == main.current_path)
	q.set_repeat("one")
	main.player.seek(300.0)
	main.player.ended.emit()
	await _frames(1)
	_check("repeat one: back to the start", main.current_path == "stub://flat_mono" and main.player.get_position() < 1.0)
	q.set_repeat("off")
	main.player.ended.emit()
	await _frames(1)
	_check("not continuous: stays", main.current_path == "stub://flat_mono")
	q.set_continuous(true)
	main.player.ended.emit()
	await _frames(2)
	_check("continuous: the next file (%s)" % main.current_path, main.current_path == main.playlist[1] and main.playlist_index == 1)
	q.jump(main.playlist.size() - 1)
	await _frames(2)
	q.set_repeat("all")
	main.player.ended.emit()
	await _frames(2)
	_check("repeat all: after the last, the first", main.playlist_index == 0)
	f.sleep.start_end_of_file()
	main.player.ended.emit()
	await _frames(2)
	_check("an end-of-file sleep wins over the queue", main.playlist_index == 0)
	f.sleep.cancel()
	q.clear_upcoming()
	_check("clear upcoming", main.playlist.size() == 1)
	q.set_repeat("off")
	q.set_continuous(false)
	f.up_next.enabled = true
	main.open_path("stub://flat_mono")
	await _frames(2)

	# #80 frame step and A-B loop.
	var stl: Node = f.step_loop
	main.player.play()
	main.player.seek(100.0)
	stl.step(1)
	var fd: float = stl.frame_duration()
	_check("step forward: paused, one frame on (%.3f)" % main.player.get_position(), not main.player.is_playing()
			and is_equal_approx(main.player.get_position(), 100.0 + fd))
	stl.step(-2)
	_check("step back two frames", is_equal_approx(main.player.get_position(), 100.0 - fd))
	stl.mark()
	_check("first mark: A ('%s')" % stl.text(), not stl.active and stl.text().begins_with("A 0:01:39"))
	main.player.seek(102.0)
	stl.mark()
	_check("second mark: looping ('%s')" % stl.text(), stl.active and is_equal_approx(stl.b, 102.0)
			and "loop 0:01:39-0:01:42" in main._overlay_text())
	main.player.play()
	main.player.seek(101.9)
	await _wait_until(func() -> bool: return main.player.get_position() < 101.0, 2.0)
	_check("reaching B goes back to A (%.2f)" % main.player.get_position(), main.player.get_position() < 101.0)
	stl.mark()
	_check("third mark clears", not stl.active and stl.text() == "")
	stl.set_loop(50.0, 50.1)
	_check("minimum loop length", is_equal_approx(stl.b - stl.a, stl.MIN_LOOP))
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("another file clears it", not stl.active)

	# #76 favourites and search.
	var lib: Node = f.library
	_check("matching: words in any order, accents and separators", lib.matches("Le.Café_Bleu-2019.mkv", "bleu cafe")
			and not lib.matches("Le.Cafe.mkv", "bleu") and not lib.matches("x.mkv", "  "))
	_check("scores: start > word > inside", lib.score("Lantern 2019.mkv", "lant") == 3
			and lib.score("The Lantern.mkv", "lant") == 2 and lib.score("Thelantern.mkv", "lant") == 1)
	lib.add_favourite("/films/Holiday.mkv")
	lib.add_favourite("/films/Holiday.mkv")
	_check("favourite added once", lib.favourites().size() == 1 and lib.is_favourite("/films/Holiday.mkv"))
	_check("toggle off", lib.toggle_favourite("/films/Holiday.mkv") == false and not lib.is_favourite("/films/Holiday.mkv"))
	lib.add_favourite("/films/Holiday.mkv")
	lib.add_favourite("/films/Other.mkv")
	_check("newest first", lib.favourites()[0]["path"] == "/films/Other.mkv")
	var known: Array = lib.search_known("holiday")
	_check("search_known finds the favourite first (%d)" % known.size(), known.size() >= 1
			and known[0]["path"] == "/films/Holiday.mkv" and known[0]["source"] == "favourite")
	_check("search_known finds queued patterns", lib.search_known("360").any(func(e: Dictionary) -> bool:
			return e["source"] == "queue"))
	var sroot := OS.get_user_data_dir().path_join("test_search")
	DirAccess.make_dir_recursive_absolute(sroot.path_join("Season 1/extras"))
	for p in ["Season 1/Show.S01E01.mkv", "Season 1/Show.S01E02.mkv", "Season 1/extras/Show.Making.Of.mp4",
			"Season 1/notes.txt", "Other.mkv"]:
		FileAccess.open(sroot.path_join(p), FileAccess.WRITE).store_string("x")
	var got_results := [null]
	lib.folder_results.connect(func(q: String, r: Array) -> void: got_results[0] = r, CONNECT_ONE_SHOT)
	lib.search_folder(sroot, "show s01")
	await _wait_until(func() -> bool: return got_results[0] != null, 5.0)
	var res: Array = got_results[0] if got_results[0] != null else []
	_check("folder search on a worker: 2 episodes, no text file (%d)" % res.size(), res.size() == 2
			and res.all(func(e: Dictionary) -> bool: return str(e["title"]).begins_with("Show.S01")))
	_check("subfolders walked", lib.walk(sroot, "making").size() == 1)
	var smb_results := [null]
	lib.folder_results.connect(func(_q: String, r: Array) -> void: smb_results[0] = r, CONNECT_ONE_SHOT)
	lib.search_folder("smb://host/share", "show")
	_check("shares are not walked: empty answer at once", smb_results[0] != null and (smb_results[0] as Array).is_empty())
	for p in ["Season 1/extras/Show.Making.Of.mp4", "Season 1/Show.S01E01.mkv", "Season 1/Show.S01E02.mkv",
			"Season 1/notes.txt", "Other.mkv"]:
		DirAccess.remove_absolute(sroot.path_join(p))
	DirAccess.remove_absolute(sroot.path_join("Season 1/extras"))
	DirAccess.remove_absolute(sroot.path_join("Season 1"))
	DirAccess.remove_absolute(sroot)
	lib.remove_favourite("/films/Holiday.mkv")
	lib.remove_favourite("/films/Other.mkv")

	# #74 accessibility: monocular drives 2D from 3D; subtitles always on per file; scale clamped; left-handed stored.
	var acc: Node = f.access
	f.languages.forget()
	acc.set_value("monocular_eye", 1)
	acc.set_value("monocular", true)
	_check("monocular: right eye to both", f.two_d.eye == 1)
	acc.set_value("monocular", false)
	_check("monocular off: 2D from 3D off", f.two_d.eye == -1)
	sub.set_enabled(false)
	acc.set_value("subtitles_always", true)
	_check("subtitles always: on now", sub.enabled and sub.track == 0)
	sub.set_enabled(false)
	main.open_path("stub://flat_sbs")
	await _frames(2)
	_check("subtitles always: on for the next file", sub.enabled and sub.track == 0)
	_check("the user's own on/off setting is untouched", main.settings.get_value("subtitles", "enabled", false) == false)
	_check("language memory didn't learn from it", f.languages.subtitle_language == "")
	acc.set_value("subtitles_always", false)
	sub.set_enabled(false)
	var scale_seen := [0.0]
	acc.changed.connect(func(k: String, v: Variant) -> void:
		if k == "ui_scale":
			scale_seen[0] = v, CONNECT_ONE_SHOT)
	acc.set_value("ui_scale", 5.0)
	_check("ui scale clamped and signalled", is_equal_approx(acc.get_value("ui_scale"), 2.0) and is_equal_approx(scale_seen[0], 2.0))
	acc.set_value("ui_scale", 1.0)
	acc.set_value("left_handed", true)
	_check("left-handed stored", acc.get_value("left_handed") == true and main.settings.get_value("accessibility", "left_handed", false) == true)
	acc.set_value("left_handed", false)
	_check("defaults are not stored", not main.settings.has_value("accessibility", "left_handed"))

	# #69 playback speed: the pattern's clock runs at the speed; end time and status follow; steps and limits.
	var sp: Node = f.speed
	main.open_path("stub://flat_mono")
	await _frames(2)
	main.player.seek(10.0)
	main.player.play()
	sp.set_speed(2.0)
	var t0: float = main.player.get_position()
	var w0 := Time.get_ticks_msec()
	await _sleep(0.5)
	var rate: float = (main.player.get_position() - t0) / ((Time.get_ticks_msec() - w0) / 1000.0)
	_check("the clock runs at 2x (%.2f)" % rate, absf(rate - 2.0) < 0.3)
	_check("status line says so", "speed 2x" in main._overlay_text())
	_check("end time at the speed: half the remaining time", is_equal_approx(f.remaining_real(), f.remaining() / 2.0))
	sp.slower()
	_check("slower: 1.75", is_equal_approx(sp.speed, 1.75) and sp.text() == "1.75x")
	sp.set_speed(9.0)
	_check("clamped to 2", is_equal_approx(sp.speed, 2.0))
	main.open_path("stub://360_mono")
	await _frames(2)
	_check("kept on the next file", is_equal_approx(main.player.speed, 2.0))
	sp.reset()
	_check("reset: 1x, no status", is_equal_approx(main.player.speed, 1.0) and sp.text() == "")

	print("test_features: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## A test-pattern stand-in for `path` whose video info carries `meta` (as MediaSource will).
func _meta_source(meta: Dictionary, path: String) -> Object:
	var script := GDScript.new()
	script.source_code = "extends \"res://scripts/video/stub_video_source.gd\"\nvar meta := {}\n" \
			+ "func get_video_info() -> Dictionary:\n\tvar i := super()\n\ti.merge(meta, true)\n\treturn i\n"
	script.reload()
	var src: Object = script.new()
	src.attach(main.player)
	src.open_placeholder(path, "test stand-in")
	src.meta = meta
	return src


## #67 subtitle renderer and #65 second track, on the flat test pattern with a line showing.
func _subtitle_renderer_checks(main: Node3D, sub: Node, rd: Node3D) -> void:
	var quad: Node3D = rd.get_node("Quad")
	var size: Vector2 = main.screen.get_flat_size()
	var bottom: float = main.screen.global_position.y - size.y * 0.5
	var band: Vector2 = rd.get_band_size()
	_check("below the picture: band top %.3f under the bottom edge %.3f" % [quad.global_position.y + band.y * 0.5, bottom],
			quad.global_position.y + band.y * 0.5 < bottom and absf(band.x - size.x) < 0.001)
	var canvas: Vector2i = rd.get_canvas_size()
	_check("canvas pixels follow the angle (%s)" % canvas, canvas.x >= 512 and canvas.x <= 2048 and canvas.y < canvas.x / 2)
	var h1 := canvas.y
	rd.set_scale_factor(2.0)
	_check("size 2x: taller band (%d -> %d)" % [h1, rd.get_canvas_size().y], rd.get_canvas_size().y > h1 * 1.6)
	rd.set_scale_factor(1.0)
	band = rd.get_band_size()
	rd.set_position_mode("inside")
	_check("inside: band above the bottom edge", quad.global_position.y - band.y * 0.5 > bottom)
	rd.set_offset(0.1)
	_check("offset moves it up", quad.global_position.y - band.y * 0.5 > bottom + size.y * 0.1)
	rd.set_offset(0.0)
	rd.set_position_mode("below")
	var eye := Vector3(0.0, main.eye_height, 0.0)
	var d0: float = (quad.global_position - eye).length()
	var dir0: Vector3 = (quad.global_position - eye).normalized()
	rd.set_depth(1.0)
	var d1: float = (quad.global_position - eye).length()
	var k: float = quad.global_transform.basis.get_scale().x
	_check("depth 1 m: closer, same direction, same angular size (%.2f -> %.2f, k %.3f)" % [d0, d1, k],
			absf(d0 - d1 - 1.0) < 0.01 and dir0.dot((quad.global_position - eye).normalized()) > 0.9999
			and absf(k - d1 / d0) < 0.001)
	rd.set_depth(0.0)
	rd.set_background(0.5)
	var box: StyleBox = _labels(rd)[0].get_theme_stylebox("normal")
	_check("background box behind the line", box is StyleBoxFlat and is_equal_approx((box as StyleBoxFlat).bg_color.a, 0.5))
	rd.set_background(0.0)
	_check("settings kept", main.settings.get_value("subtitles", "position", "") == "below"
			and float(main.settings.get_value("subtitles", "size", 0.0)) == 1.0)
	# Styled text from an ASS line, and from the engine's parsed lines; a top-aligned line goes first.
	var t: float = main.player.get_position() - sub.delay
	sub.add_event(t - 0.2, t + 30.0, "Bold and red", {"ass": "0,0,Default,,0,0,0,,{\\b1}Bold{\\b0} and {\\c&H0000FF&}red"})
	sub.add_event(t - 0.1, t + 30.0, "Sign", {"styled": [{"alignment": 8, "runs": [{"text": "Sign", "italic": true,
			"size": 20.0}]}]})
	await _frames(2)
	var labels := _labels(rd)
	_check("three lines, the top-aligned sign first (%d)" % labels.size(), labels.size() == 3
			and labels[0].get_parsed_text() == "Sign" and labels[0].position.y < labels[1].position.y)
	var styled_ok := false
	for l: RichTextLabel in labels:
		styled_ok = styled_ok or (l.text.contains("[b]Bold[/b]") and l.text.contains("[color=#ff0000]red[/color]"))
	_check("ASS bold and colour reach the label", styled_ok)
	_check("the plain text joins all lines", sub.text.contains("Bold and red") and sub.text.contains("Sign"))
	# A picture line (the engine's bitmap event shape), on a 1920x1080 canvas.
	var img := Image.create_empty(200, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.8, 0, 1))
	sub.add_event(t - 0.05, -1.0, "", {"bitmap": true, "images": [{"rect": Rect2i(860, 1000, 200, 40), "image": img,
			"forced": false}], "canvas_size": Vector2i(1920, 1080)})
	await _frames(2)
	var rects := rd.find_children("*", "TextureRect", true, false)
	var scale_ok := false
	if rects.size() == 1:
		var tr: TextureRect = rects[0]
		var kk := float(rd.get_canvas_size().x) / 1920.0
		scale_ok = absf(tr.size.x - 200.0 * kk) < 1.0 \
				and absf(tr.position.x + tr.size.x * 0.5 - rd.get_canvas_size().x * 0.5) < 1.0
	_check("the picture line is drawn at the picture's scale, centred (%d)" % rects.size(), scale_ok)
	# A 3D rip: each eye's half of the canvas has its own copy of the caption; only the first half's is drawn.
	var R := preload("res://scripts/play/subtitle_renderer.gd")
	var VM := preload("res://scripts/video_mode.gd")
	var both := [{"rect": Rect2i(380, 1000, 200, 40)}, {"rect": Rect2i(1340, 1000, 200, 40)}]
	var sbs: Dictionary = R.eye_images(both, Vector2i(1920, 1080), VM.Layout.SBS, true)
	_check("half SBS rip: one caption, on a full-aspect eye canvas, stretched back (%s)" % [sbs],
			sbs["images"].size() == 1 and sbs["canvas"] == Vector2i(1920, 1080)
			and sbs["images"][0]["rect"] == Rect2i(760, 1000, 400, 40))
	var tb: Dictionary = R.eye_images([{"rect": Rect2i(860, 500, 200, 20)}, {"rect": Rect2i(860, 1040, 200, 20)}],
			Vector2i(1920, 1080), VM.Layout.TB, false)
	_check("full TB rip: the top half's caption on a 1920x540 canvas", tb["images"].size() == 1
			and tb["canvas"] == Vector2i(1920, 540) and tb["images"][0]["rect"] == Rect2i(860, 500, 200, 20))
	_check("mono: every image, the whole canvas", R.eye_images(both, Vector2i(1920, 1080), VM.Layout.MONO, false)
			["images"].size() == 2)
	var pictures := func(at: float) -> int:
		return sub.events_at(at).filter(func(e: Dictionary) -> bool: return bool(e.get("bitmap", false))).size()
	_check("open-ended picture lasts until the next picture event", pictures.call(t + 5.0) == 1)
	sub.add_event(t + 6.0, -1.0, "", {"bitmap": true, "images": [], "canvas_size": Vector2i(1920, 1080)})
	_check("an empty picture event ends it", pictures.call(t + 6.5) == 0 and pictures.call(t + 5.9) == 1)
	# #65 second track: track 1 of the pattern stands for a subtitle file next to the video.
	var srt_path := "user://test_second.srt"
	var fa := FileAccess.open(srt_path, FileAccess.WRITE)
	fa.store_string("1\n%s --> %s\nSecond <i>language</i>\n" % [_srt_time(t - 1.0), _srt_time(t + 30.0)])
	fa.close()
	var files: Node = main.features.sub_files
	var saved_loaded: Array = files.loaded
	files.loaded = [{"path": ProjectSettings.globalize_path(srt_path), "index": 1, "language": "fre"}]
	_check("second track candidates: track 1 only", sub.secondary_tracks().size() == 1
			and int(sub.secondary_tracks()[0]["index"]) == 1)
	sub.select_secondary(0)
	_check("the main track can't be the second", sub.secondary == -1)
	sub.select_secondary(1)
	await _wait_until(func() -> bool: return _labels(rd).size() == 4, 3.0)
	labels = _labels(rd)
	_check("second line drawn above the main ones (%d)" % labels.size(), labels.size() == 4
			and labels[0].get_parsed_text() == "Second language" and labels[0].text.contains("[i]language[/i]"))
	_check("second language remembered", str(main.settings.get_value("subtitles", "secondary_language", "")) != "")
	_check("second line is not in the main text", not sub.text.contains("Second"))
	sub.select_secondary(-1)
	await _frames(2)
	_check("second track off", _labels(rd).size() == 3
			and str(main.settings.get_value("subtitles", "secondary_language", "")) == "")
	files.loaded = saved_loaded
	DirAccess.remove_absolute(ProjectSettings.globalize_path(srt_path))
	# Only the pattern's own lines stay for the checks after this.
	var keep: Array = sub._list.events.filter(func(e: Array) -> bool: return str(e[2]).begins_with("Line "))
	sub._list.clear()
	for e: Array in keep:
		sub._list.add(e)


func _labels(rd: Node) -> Array:
	var out: Array = rd.find_children("*", "RichTextLabel", true, false)
	out.sort_custom(func(a: Control, b: Control) -> bool: return a.position.y < b.position.y)
	return out


func _srt_time(t: float) -> String:
	var ms := roundi(maxf(t, 0.0) * 1000.0)
	return "%02d:%02d:%02d,%03d" % [ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000]


func _wait_until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + what)
	else:
		print("PASS " + what)
