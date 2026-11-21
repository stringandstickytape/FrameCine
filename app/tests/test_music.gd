extends SceneTree

## Tests for music files (scripts/play/music_source.gd, ideas #64) in the real main scene, on the fork's MediaSource
## and the music clips of spikes/03-player/demux-test/make-feature-files.sh: the tags and cover, the card on the
## screen, the audio as the clock, seeking, the visualisers on the card, the end, and a file without a cover. Needs the
## fork and a renderer (the audio clock starts with the first frame); otherwise only the file-type checks run. The
## visualisers in detail: test_visualisers.gd.
## Run: godot --xr-mode off --path app --script res://tests/test_music.gd

const Factory := preload("res://scripts/video/video_source_factory.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")
const Registry := preload("res://scripts/visualisers/visualiser_registry.gd")
var DIR := OS.get_environment("HOME") + "/media-tests/features/music/"

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
	_check("music files are media files", Factory.is_media_file("a/b.flac") and Factory.is_media_file("x.M4A")
			and Factory.is_music_file("y.mp3") and not Factory.is_music_file("z.mkv"))
	if not MusicSource.available() or not FileAccess.file_exists(DIR + "aac_cover.m4a") \
			or DisplayServer.get_name() == "headless":
		print("SKIP playback checks (needs the fork, the music clips and a renderer)")
	else:
		await _playback()
	print("test_music: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


func _playback() -> void:
	main.set_environment("void")
	main.open_path(DIR + "aac_cover.m4a")
	await _until(func() -> bool: return main.player.audio.playing, 5.0)
	var src: Object = main.player.source
	_check("opened as music (%s)" % src.get_kind(), src.get_kind() == "music")
	_check("tags: Test Song, Test Artist, Test Album", src.title == "Test Song" and src.artist == "Test Artist"
			and src.album == "Test Album")
	_check("the cover from the file", src.cover != null and src.cover.get_width() > 0)
	var m: ShaderMaterial = main.screen.material
	_check("the card is the screen's picture, flat and shown (%s, %s, %s, %s)" % [main.screen.is_shown(),
			main.mode.to_id(), m.get_shader_parameter("rgb_source"), m.get_shader_parameter("rgb_tex")],
			main.screen.is_shown() and not main.mode.is_spherical() and not main.mode.is_stereo()
			and m.get_shader_parameter("rgb_source") == true and m.get_shader_parameter("rgb_tex") == src.get_rgb_texture())
	await create_timer(1.5).timeout
	var p: float = main.player.get_position()
	_check("the audio is the clock (%.2f s, audio %.2f s)" % [p, main.player.audio.get_playback_position()],
			p > 1.0 and absf(p - main.player.audio.get_playback_position()) < 0.15)
	# The clip is quiet for about its first second: wait for its sound rather than look at one moment.
	var top_level := func() -> float:
		var most := 0.0
		for v: float in src.levels():
			most = maxf(most, v)
		return most
	await _until(func() -> bool: return top_level.call() > 0.2, 3.0)
	var top: float = top_level.call()
	_check("the visualiser hears it (%d bars, top %.2f)" % [src.levels().size(), top], src.levels().size() == 32
			and top > 0.2)
	await RenderingServer.frame_post_draw
	var card: Image = src.get_rgb_texture().get_image()
	var c := card.get_pixel(int(card.get_width() * 0.2), int(card.get_height() * 0.4))
	_check("the card shows the cover on the left (%s)" % c, c.v > 0.15 and not c.is_equal_approx(Color(0.06, 0.06, 0.08)))
	# The visualisers (res://visualisers, docs/visualisers.md): each draws something of its own in its area; "off"
	# draws nothing there.
	var f: Node = main.features
	var styles: Array[String] = src.styles()
	_check("visualiser: bars by default; the app's fifty-five and off (%s)" % [styles],
			f.visualiser() == "bars" and styles == ["bars", "mirror", "line", "radial", "aurora", "halftone", "tiles",
			"runner", "sakura", "ink", "planet", "rose", "clockwork", "chrome", "circuit", "deep", "cymatics", "vinyl",
			"fireworks", "rain", "topo", "koi", "candles", "paper", "bubbles", "carousel",
			"microscope", "volcano", "web", "starlings", "lighthouse", "fractal", "balloons", "crystals", "stage",
			"stadium", "city", "clouds", "organ", "kaleidoscope",
			"blackhole", "musicbox", "pinball", "fountains", "snowglobe",
			"piano", "lavalamp", "cradle", "tapedeck", "zen",
			"speakers", "engine", "wheat", "neon", "honeycomb", "off"])
	var painted := {}
	var looks := {}
	for s: String in styles:
		f.set_visualiser(s)
		# One that keeps its own last frame ("feedback") builds its picture up over a second or two.
		await _frames(90 if bool(Registry.entry(s).get("feedback", false)) else 4)
		await RenderingServer.frame_post_draw
		var img: Image = src.get_rgb_texture().get_image()
		var n := 0
		var sig := ""
		# The area right of the cover, between the album line and the time line.
		for y in range(int(img.get_height() * 0.5), int(img.get_height() * 0.8), 6):
			for x in range(int(img.get_width() * 0.5), int(img.get_width() * 0.94), 6):
				var px := img.get_pixel(x, y)
				if px.s > 0.3 and px.v > 0.3:
					n += 1
					sig += "%d,%d;" % [x / 30, y / 30]
		painted[s] = n
		looks[s] = sig.hash()
	print("  coloured samples per style: %s" % painted)
	var drawn := styles.filter(func(st: String) -> bool: return st != "off" and painted[st] > 0)
	_check("visualiser: off draws nothing; the others draw", painted["off"] == 0 and drawn.size() == styles.size() - 1)
	var distinct := {}
	for st: String in drawn:
		distinct[looks[st]] = true
	_check("visualiser: each style looks different", distinct.size() == drawn.size())
	f.set_visualiser("nonsense")
	_check("visualiser: an unknown style is ignored", f.visualiser() == "off")
	f.set_visualiser("bars")
	main.player.seek(10.0)
	await _until(func() -> bool: return main.player.audio.playing and not main.player.audio.stream_paused, 3.0)
	await create_timer(0.5).timeout
	_check("seek to 10 s (%.2f)" % main.player.get_position(), absf(main.player.get_position() - 10.5) < 0.4)
	_check("up next does not count down for music", not main.features.up_next.begin("x.flac", func() -> void: pass))
	var ended := [false]
	main.player.ended.connect(func() -> void: ended[0] = true, CONNECT_ONE_SHOT)
	main.player.seek(src.get_duration() - 1.0)
	await _until(func() -> bool: return ended[0], 4.0)
	_check("the end is reported", ended[0])

	main.open_path(DIR + "tone_steps.wav")
	await _until(func() -> bool: return main.player.audio.playing, 5.0)
	src = main.player.source
	_check("a file without a cover: music, the name as the title (%s)" % src.title, src.get_kind() == "music"
			and src.cover == null and src.title != "")
	# A video's container with only sound in it: the music card, not the test-pattern stand-in.
	var sound_only := OS.get_user_data_dir().path_join("test_sound_only.mp4")
	DirAccess.copy_absolute(DIR + "aac_cover.m4a", sound_only)
	main.open_path(sound_only)
	await _until(func() -> bool: return main.player.audio.playing, 5.0)
	src = main.player.source
	_check("an .mp4 with only sound plays as music (%s, %s)" % [src.get_kind(), src.title], src.get_kind() == "music"
			and src.title == "Test Song")
	main.open_path("stub://flat_mono")
	await _frames(3)
	DirAccess.remove_absolute(sound_only)
	await _still_picture()
	main.open_path("stub://flat_mono")
	await _frames(3)


## A video at 1 frame a second (made by ffmpeg: testsrc2 and a tone, title "Still Test"): the card with its picture
## dimmed behind it and the visualiser; the switch in Picture, Visualisations shows it as a video and back.
func _still_picture() -> void:
	var still := DIR.get_base_dir().get_base_dir().path_join("still/still_1fps.mkv")
	if not FileAccess.file_exists(still):
		print("SKIP still pictures (no %s)" % still)
		return
	var f: Node = main.features
	f.set_visualiser("bars")
	main.open_path(still)
	await _until(_card_on, 6.0)
	var src: Object = main.player.source
	var m: ShaderMaterial = main.screen.material
	_check("a 1 frame a second video shows as the card (%s)" % src.get_video_info().get("fps"), src.get_kind() == "hw"
			and src.shows_card() and m.get_shader_parameter("rgb_source") == true
			and m.get_shader_parameter("rgb_tex") == src.get_rgb_texture() and not main.mode.is_stereo())
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var card: Image = src.get_rgb_texture().get_image()
	# testsrc2's colours, dimmed, at the card's left middle (the words are at the left top, the visualiser lower).
	var c := card.get_pixel(int(card.get_width() * 0.5), int(card.get_height() * 0.08))
	_check("its picture is behind the card, dimmed (%s)" % c, c.v > 0.05 and c.v < 0.6
			and not c.is_equal_approx(MusicSource.BACKGROUND))
	_check("the card's title is the file's (%s)" % src._card.title, src._card.title == "Still Test")
	_check("the visualiser runs on it", src.visualiser() != null and src.visualiser().id == "bars")
	# The film layer (scripts/play/film_layer.gd) redraws when frame_key() changes: the card must count as new each frame.
	_check("the film layer redraws the card every frame (frame_key %s)" % src.frame_key(), is_nan(src.frame_key()))
	var layer: Node = f.get("film_layer")
	if layer != null and layer.get("updates") != null:
		var before: int = layer.updates
		await _frames(30)
		print("  film layer: %d updates in 30 frames (%s)" % [layer.updates - before, layer.get("kind")])
	var pic: Node = main.ui.ui.picture
	pic.sync()
	_check("Picture shows Visualisations with the switch on", pic._vis_box.visible and pic._still.visible
			and pic._still.button_pressed and pic._vis_body.visible)
	var at: float = main.player.get_position()
	f.set_still_card(false)
	await _until(func() -> bool: return main.player.source != src and main.player.source.has_frame(), 6.0)
	await _frames(5)
	src = main.player.source
	pic.sync()
	# Where it was: asked for, not checked. A seek in a 1 frame a second file comes out at the next keyframe (the audio
	# clock runs ahead of the frame shown; an engine matter, docs/visualisers.md "Still pictures").
	_check("switched off: the same file as a video (%.1f, was %.1f); only the switch shows" % [
			main.player.get_position(), at], not src.shows_card() and m.get_shader_parameter("rgb_source") == false
			and pic._vis_box.visible and not pic._vis_body.visible)
	f.set_still_card(true)
	await _until(func() -> bool: return main.player.source != src and main.player.source.shows_card(), 6.0)
	_check("switched on again: the card", main.player.source.shows_card())
	main.settings.set_value("music", "still_card", null)


func _card_on() -> bool:
	var s: Object = main.player.source
	return s != null and s.has_method("shows_card") and s.shows_card()


func _until(cond: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", what)
	else:
		print("PASS ", what)
