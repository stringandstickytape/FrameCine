extends SceneTree

## Pictures of the Library place, drawn by the real panel from the generated library (tests/library_fixture.gd), and the
## checks only a renderer can make: the views lay out inside the panel, and opening a wall of posters doesn't hold up
## the frames of a playing test pattern. Saved to ROOM_SNAPSHOT_OUT: library-home.png, library-show.png,
## library-season.png, library-film.png. Needs a renderer:
##
## ROOM_SNAPSHOT_OUT=dir godot --display-driver x11 --rendering-driver vulkan --xr-mode off --path app \
##     --script res://tests/test_library_view.gd

const LibraryIndex := preload("res://scripts/library/library_index.gd")
const LibraryFixture := preload("res://tests/library_fixture.gd")
const FileKey := preload("res://scripts/play/file_key.gd")

## A frame at the headset's 72 Hz.
const FRAME_BUDGET_MS := 13.9

var _failures := 0
var _checks := 0
var main: Node3D
var files: Control
var root_dir := ""


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	if DisplayServer.get_name() == "headless":
		print("test_library_view: skipped (needs a renderer)")
		quit(0)
		return
	root_dir = OS.get_user_data_dir().path_join("test_library_view")
	_clear(root_dir)
	LibraryIndex.root_override = root_dir
	LibraryFixture.make(root_dir)
	files = main.ui.ui.files
	files._build_places()
	main.open_path("stub://flat_sbs")
	await _frames(5)
	main.ui.show_panel()
	await _frames(5)
	var season := root_dir.path_join("TV Shows/Harbour Lights (2011)/Season 01")
	var resume: Node = main.features.resume
	var one := FileKey.key(season.path_join("Harbour Lights - S01E01 - The Long Tide.mkv"))
	var two := FileKey.key(season.path_join("Harbour Lights - S01E02 - Salt.mkv"))
	resume._cfg.set_value(one, "finished", true)
	resume._cfg.set_value(one, "duration", 2700.0)
	resume._cfg.set_value(two, "position", 754.0)
	resume._cfg.set_value(two, "duration", 2700.0)

	# The renderer here is software on a shared machine, so a frame's length says little by itself: what the library
	# adds to the main thread is the time to build the view, and that is measured directly.
	var quiet := await _worst_frame()
	var worst := await _open_timed(root_dir)
	var built: float = files._library_view.last_draw_usec / 1000.0
	print("test_library_view: worst frame %.1f ms with nothing happening, %.1f ms opening the wall; building it %.1f ms"
			% [quiet, worst, built])
	_check("building the poster wall takes a few ms (%.1f)" % built, built < FRAME_BUDGET_MS)
	_check("the grid fits the panel's width", _fits())
	await _shot("library-home.png")
	files.open_folder(root_dir.path_join("TV Shows/Harbour Lights (2011)"))
	await _settled()
	_check("the show's page fits", _fits())
	await _shot("library-show.png")
	files.open_folder(season)
	await _settled()
	_check("the season's rows fit", _fits())
	await _shot("library-season.png")
	files.open_folder(root_dir.path_join("Movies/Quiet Water (2019)"))
	await _settled()
	_check("the film's page fits", _fits())
	await _shot("library-film.png")
	resume._cfg.erase_section(one)
	resume._cfg.erase_section(two)
	LibraryIndex.root_override = ""
	_clear(root_dir)
	print("test_library_view: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _worst_frame() -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	return worst


## Opens a folder and gives the longest frame until its pictures are in, ms.
func _open_timed(path: String) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	files.open_folder(path)
	var end := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	return worst


func _settled() -> void:
	var end := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < end:
		await process_frame


func _fits() -> bool:
	var scroll: ScrollContainer = files.list_scroll()
	var list: Control = scroll.get_child(0)
	return list.get_combined_minimum_size().x <= scroll.size.x + 1.0


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out_dir := OS.get_environment("ROOM_SNAPSHOT_OUT")
	if out_dir == "":
		return
	var view: SubViewport = main.ui.panel.viewport
	var img := view.get_texture().get_image()
	img.save_png(out_dir.path_join(file))


func _clear(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_clear(p.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
