extends SceneTree

## Tests for music files (scripts/play/music_source.gd, ideas #64) in the real main scene, on the fork's MediaSource
## and the music clips of spikes/03-player/demux-test/make-feature-files.sh: the tags and cover, the card on the
## screen, the audio as the clock, seeking, the visualiser, the end, and a file without a cover. Needs the fork and a
## renderer (the audio clock starts with the first frame); otherwise only the file-type checks run.
## Run: godot --xr-mode off --path app --script res://tests/test_music.gd

const Factory := preload("res://scripts/video/video_source_factory.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")
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
	var lv: PackedFloat32Array = src.levels()
	var top := 0.0
	for v in lv:
		top = maxf(top, v)
	_check("the visualiser hears it (%d bars, top %.2f)" % [lv.size(), top], lv.size() == 32 and top > 0.2)
	await RenderingServer.frame_post_draw
	var card: Image = src.get_rgb_texture().get_image()
	var c := card.get_pixel(int(card.get_width() * 0.2), int(card.get_height() * 0.4))
	_check("the card shows the cover on the left (%s)" % c, c.v > 0.15 and not c.is_equal_approx(Color(0.06, 0.06, 0.08)))
	# The visualiser's styles: each draws something of its own in the visualiser's area; "off" draws nothing there.
	var f: Node = main.features
	_check("visualiser: bars by default, five styles", f.visualiser() == "bars" and src.STYLES.size() == 5)
	var painted := {}
	var looks := {}
	for s: String in src.STYLES:
		f.set_visualiser(s)
		await _frames(2)
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
	_check("visualiser: off draws nothing; the others draw", painted["off"] == 0 and painted["bars"] > 0
			and painted["mirror"] > 0 and painted["line"] > 0 and painted["radial"] > 0)
	_check("visualiser: each style looks different", looks.values().filter(func(v: int) -> bool: return true).size() == 5
			and looks["bars"] != looks["mirror"] and looks["bars"] != looks["line"] and looks["bars"] != looks["radial"]
			and looks["mirror"] != looks["radial"] and looks["line"] != looks["radial"])
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
	main.open_path("stub://flat_mono")
	await _frames(3)


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
