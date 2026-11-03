extends SceneTree

## The Library place (docs/library.md) on a small generated library: NFOs read with what is missing, broken or hostile in
## them; the views; a season's order; titles on the overlay and in /state; next and previous; watched marks from the
## resume data; pictures on a worker with a cache at display size; copy_to_library with a stand-in for the SMB read.
##
## godot --headless --xr-mode off --path app --script res://tests/test_library.gd

const LibraryNfo := preload("res://scripts/library/library_nfo.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const LibraryImages := preload("res://scripts/library/library_images.gd")
const LibraryCopy := preload("res://scripts/library/library_copy.gd")
const AssistantCommands := preload("res://scripts/assistant/assistant_commands.gd")
const AssistantFetch := preload("res://scripts/assistant/assistant_fetch.gd")
const AssistantGuide := preload("res://scripts/assistant/assistant_guide.gd")
const NetworkHosts := preload("res://scripts/net/network_hosts.gd")
const FileKey := preload("res://scripts/play/file_key.gd")
const LibraryFixture := preload("res://tests/library_fixture.gd")
const DirectoryLister := preload("res://scripts/net/directory_lister.gd")
const FakeMediaBrowser := preload("res://scripts/net/fake_media_browser.gd")

const SHOW := "TV Shows/Harbour Lights (2011)"


## Reads a made-up file in pieces, as MediaBrowser does.
class FakeReader:
	extends RefCounted
	static var content := PackedByteArray()
	static var fail_after := -1
	static var error := ""
	static var slow_msec := 0
	var at := 0
	var last_error := ""

	func open_read(_path: String) -> int:
		last_error = error
		return -1 if error != "" else content.size()

	func read_next(max_bytes: int) -> PackedByteArray:
		OS.delay_msec(slow_msec)
		if fail_after >= 0 and at >= fail_after:
			last_error = "the share went away"
			return PackedByteArray()
		var piece := content.slice(at, at + mini(max_bytes, 4096))
		at += piece.size()
		return piece

	func close_read() -> void:
		pass

	func get_last_error() -> String:
		return last_error


var _failures := 0
var _checks := 0
var main: Node3D
var files: Control
var commands: AssistantCommands
var root_dir := ""


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	root_dir = OS.get_user_data_dir().path_join("test_library")
	_clear(root_dir)
	LibraryIndex.root_override = root_dir
	files = main.ui.ui.files
	files._build_places()
	commands = AssistantCommands.new()
	commands.allow_control = func() -> bool: return true
	commands.allow_files = func() -> bool: return true
	_nfo_checks()
	_place_checks()
	LibraryFixture.make(root_dir)
	_index_checks()
	await _view_checks()
	await _play_checks()
	await _image_checks()
	await _copy_checks()
	_engine_checks()
	_guide_checks()
	LibraryIndex.root_override = ""
	_clear(root_dir)
	print("test_library: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _parse(text: String) -> Dictionary:
	return LibraryNfo.parse(text.to_utf8_buffer())


func _nfo_checks() -> void:
	var d := _parse("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!-- written by hand -->
<tvshow>
	<title>Fish &amp; Chips: &lt;The Show&gt;</title>
	<plot><![CDATA[A plot with <angle> brackets & all.]]></plot>
	<premiered>2011-03-04</premiered>
	<year>1999</year>
	<genre>Drama</genre><genre>Comedy</genre>
	<namedseason number="2">The Second Tide</namedseason>
	<actor><name>Not A Title</name><title>Nor this</title></actor>
	<thumb aspect="poster">http://example.invalid/never-fetched.jpg</thumb>
	<ratings><rating name="x"><value>9</value></rating></ratings>
</tvshow>
""")
	_check("root and entities (%s)" % d.get("title", ""), d.get("kind") == "tvshow"
			and d.get("title") == "Fish & Chips: <The Show>")
	_check("CDATA as it is", d.get("plot") == "A plot with <angle> brackets & all.")
	_check("a repeated field is a list", d.get("genre") == ["Drama", "Comedy"])
	_check("premiered wins over year, as in Kodi", LibraryNfo.year(d) == 2011)
	_check("a named season", (d.get("named_seasons", {}) as Dictionary).get(2) == "The Second Tide")
	_check("nested elements aren't fields", d.get("title") != "Not A Title" and not d.has("name") and not d.has("value"))
	_check("no URL is kept from a file", not str(d).contains("example.invalid"))
	var two := _parse("<episodedetails><title>One</title><season>1</season><episode>1</episode></episodedetails>\n"
			+ "<episodedetails><title>Two</title><season>1</season><episode>2</episode></episodedetails>\n")
	_check("two episodes in one file", two.get("title") == "One" and (two.get("episodes", []) as Array).size() == 2)
	var hybrid := _parse("<movie><title>Kept</title></movie>\nhttps://example.invalid/movie/1\n")
	_check("a URL line after the XML is ignored", hybrid.get("title") == "Kept")
	_check("a URL alone is no NFO", _parse("https://example.invalid/movie/1\n").is_empty())
	_check("empty and rubbish", _parse("").is_empty() and _parse("\u0000\u0001<<<>").is_empty())
	_check("another root is no NFO", _parse("<musicvideo><title>x</title></musicvideo>").is_empty())
	var broken := _parse("<movie><title>Got this far</title><plot>and then the file st")
	_check("a cut file gives what was read (%s)" % str(broken), broken.get("title") == "Got this far")
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	bom.append_array("<movie><title>BOM</title></movie>".to_utf8_buffer())
	_check("a byte order mark", LibraryNfo.parse(bom).get("title") == "BOM")
	var wide := "<movie><title>Wide</title></movie>".to_utf16_buffer()
	var u16 := PackedByteArray([0xFF, 0xFE])
	u16.append_array(wide)
	_check("UTF-16", LibraryNfo.parse(u16).get("title") == "Wide")
	var entity := _parse("<!DOCTYPE movie [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><movie><title>&x;</title></movie>")
	_check("an external entity is not followed (%s)" % str(entity), not str(entity).contains("root:"))
	var big := PackedByteArray()
	big.resize(LibraryNfo.MAX_BYTES + 1)
	var f := FileAccess.open(root_dir.get_base_dir().path_join("too_big.nfo"), FileAccess.WRITE)
	f.store_buffer(big)
	f.close()
	_check("an oversized file isn't read", LibraryNfo.read(f.get_path()).is_empty())
	DirAccess.remove_absolute(f.get_path())
	_check("no number is -1", LibraryNfo.number({"season": "x"}, "season") == -1
			and LibraryNfo.number({}, "season") == -1 and LibraryNfo.number({"season": "7"}, "season") == 7)
	_check("names: numbers", LibraryIndex.episode_numbers("Show - S02E10 - Title.mkv") == [2, 10]
			and LibraryIndex.episode_numbers("show.s1e2.mkv") == [1, 2]
			and LibraryIndex.episode_numbers("Glasses2e4.mkv") == [-1, -1])
	_check("names: a title with a dash in it", LibraryIndex._title_in_name("Show - S01E02 - Part - Two") == "Part - Two")
	_check("names: nothing but numbers", LibraryIndex._title_in_name("Show - S01E02") == "")


func _place_checks() -> void:
	var places: Array = files.get_places()
	_check("Library is a place before it exists", places.any(func(p: Dictionary) -> bool:
		return p["label"] == "Library" and p["path"] == root_dir) and not DirAccess.dir_exists_absolute(root_dir))
	files.open_folder("")
	_check("opening nothing doesn't make the Library", not DirAccess.dir_exists_absolute(root_dir)
			and files.current != root_dir)
	files.open_folder(root_dir)
	_check("made on first use", DirAccess.dir_exists_absolute(root_dir.path_join("TV Shows"))
			and DirAccess.dir_exists_absolute(root_dir.path_join("Movies")))


func _index_checks() -> void:
	var home := LibraryIndex.read(root_dir)
	_check("home: shows and films as cards (%d, %d)" % [(home["shows"] as Array).size(), (home["films"] as Array).size()],
			home["view"] == "home" and (home["shows"] as Array).size() == 2 and (home["films"] as Array).size() == 2)
	var names: Array = (home["films"] as Array).map(func(c: Dictionary) -> String: return c["title"])
	_check("sorted without the leading The (%s)" % str(names), names == ["The Long Weekend", "Quiet Water"])
	var plain: Array = (home["plain"] as Array).map(func(c: Dictionary) -> String: return c["name"])
	_check("a folder with no NFO is a plain folder (%s)" % str(plain), plain.has("Holiday Clips")
			and plain.has("Odds and Ends"))
	_check("and opens as one", LibraryIndex.read(root_dir.path_join("Movies/Holiday Clips"))["view"] == "plain")
	var show := LibraryIndex.read(root_dir.path_join(SHOW))
	_check("a show", show["view"] == "show" and show["title"] == "Harbour Lights" and show["card"]["year"] == 2011
			and str(show["card"]["poster"]).ends_with("poster.jpg") and str(show["card"]["fanart"]).ends_with("fanart.jpg"))
	var seasons: Array = (show["seasons"] as Array).map(func(s: Dictionary) -> String: return s["title"])
	_check("seasons in order, named, specials last (%s)" % str(seasons), seasons == ["Season 1", "The Second Tide",
			"Specials"])
	var season := LibraryIndex.read(root_dir.path_join(SHOW).path_join("Season 01"))
	var labels: Array = (season["episodes"] as Array).map(func(e: Dictionary) -> String: return e["label"])
	_check("episodes in number order, not name order (%s)" % str(labels), labels == ["S01E01", "S01E02", "S01E03",
			"S01E10"])
	var e: Dictionary = season["episodes"][0]
	_check("an episode", e["title"] == "The Long Tide" and str(e["plot"]).begins_with("Anna comes home")
			and str(e["thumb"]).ends_with("-thumb.jpg"))
	var no_nfo: Dictionary = season["episodes"][2]
	_check("no NFO: what the name says (%s)" % str(no_nfo["title"]), no_nfo["label"] == "S01E03"
			and no_nfo["title"] == "Fog Signal" and no_nfo["plot"] == "" and no_nfo["thumb"] == "")
	var bad: Dictionary = season["episodes"][3]
	_check("a broken NFO doesn't lose the episode", bad["label"] == "S01E10")
	var film := LibraryIndex.read(root_dir.path_join("Movies/Quiet Water (2019)"))
	_check("a film", film["view"] == "movie" and film["film"]["title"] == "Quiet Water" and film["film"]["runtime"] == 104
			and str(film["film"]["video"]).ends_with("Quiet Water (2019).mkv"))
	_check("a film's movie.nfo works too", LibraryIndex.read(root_dir.path_join("Movies/The Long Weekend (1987)"))["view"]
			== "movie")
	var multi := LibraryIndex.read(root_dir.path_join(SHOW).path_join("Season 02"))
	var two: Dictionary = multi["episodes"][0]
	_check("two episodes in one file (%s, %s)" % [two["label"], two["title"]], two["label"] == "S02E01-E02"
			and two["title"] == "Double Bill / Second Half")
	_check("the walk looked at no network path", not str(LibraryIndex.read(root_dir)).contains("smb://"))


func _view_checks() -> void:
	files.open_folder(root_dir)
	await _listed()
	var lit: Array = files._places_box.get_children().filter(func(b: Node) -> bool:
		return b is Button and (b as Button).button_pressed)
	_check("only the Library's place lights up, not a folder it sits in", lit.size() == 1
			and lit[0].get_meta("path") == root_dir)
	_check("posters for the shows and films, plain folders after (%s)" % str(files.row_texts()),
			files.row_button("Harbour Lights") != null and files.row_button("Quiet Water") != null
			and files.row_button("Holiday Clips/") != null)
	_check("no file rows at home but the loose one", files.get_video_paths().size() == 1)
	files.row_button("Harbour Lights").pressed.emit()
	await _listed()
	_check("a poster opens the show (%s)" % str(files.row_texts()), files.current == root_dir.path_join(SHOW)
			and files.row_button("Season 1") != null and files.row_button("..") != null)
	files.row_button("Season 1").pressed.emit()
	await _listed()
	_check("a season opens its episodes (%s)" % str(files.row_texts()), files.get_video_paths().size() == 4)
	_check("the playlist is in episode order", files.get_video_paths()[3].contains("S01E10"))
	files.open_folder(root_dir.path_join("Movies/Holiday Clips"))
	await _listed()
	_check("a plain folder lists as any other (%s)" % str(files.row_texts()), files.row_button("beach.mkv") != null)
	files.open_folder(root_dir.path_join("Movies/Quiet Water (2019)"))
	await _listed()
	_check("a film's page has Play", files.row_button("Play") != null and files.get_video_paths().size() == 1)
	_check("no poster or NFO in its playlist", files.get_video_paths()[0].ends_with(".mkv"))


func _play_checks() -> void:
	var dir := root_dir.path_join(SHOW).path_join("Season 01")
	var first := dir.path_join("Harbour Lights - S01E01 - The Long Tide.mkv")
	main.open_path(first)
	await _frames(2)
	_check("the playlist skips thumbnails and posters (%s)" % str(main.playlist.map(func(p: String) -> String:
		return p.get_file())), main.playlist.size() == 4 and main.playlist.all(func(p: String) -> bool:
			return p.ends_with(".mkv")))
	_check("in episode order, S01E10 last", main.playlist[3].contains("S01E10") and main.playlist[2].contains("S01E03"))
	_check("the title from the NFO (%s)" % main.display_title(), main.display_title()
			== "Harbour Lights S01E01: The Long Tide")
	var st: Dictionary = (await commands.run("state", {}))["result"]
	_check("in /state too (%s)" % str(st.get("title")), st.get("title") == "Harbour Lights S01E01: The Long Tide")
	_check("and what the NFO says (%s)" % str(st.get("library")), st.get("library") is Dictionary
			and st["library"]["kind"] == "episode" and st["library"]["season"] == 1 and st["library"]["episode"] == 1)
	main.next_file()
	await _frames(2)
	_check("next is the next episode (%s)" % main.display_title(), main.current_path.contains("S01E02")
			and main.display_title() == "Harbour Lights S01E02: Salt")
	main.previous_file()
	await _frames(2)
	_check("previous goes back", main.current_path.contains("S01E01"))
	main.open_path(dir.path_join("Harbour Lights - S01E03 - Fog Signal.mkv"))
	await _frames(2)
	_check("no NFO: the name's title (%s)" % main.display_title(), main.display_title()
			== "Harbour Lights S01E03: Fog Signal")
	main.open_path(root_dir.path_join("Movies/Quiet Water (2019)/Quiet Water (2019).mkv"))
	await _frames(2)
	_check("a film's title (%s)" % main.display_title(), main.display_title() == "Quiet Water (2019)")
	var plain := root_dir.path_join("Movies/Holiday Clips/beach.mkv")
	main.open_path(plain)
	await _frames(2)
	_check("a plain file keeps its name (%s)" % main.display_title(), main.display_title() == "beach.mkv")
	# Watched: the resume data's finished and position, in place.
	var resume: Node = main.features.resume
	var season_dir := dir
	var one := season_dir.path_join("Harbour Lights - S01E01 - The Long Tide.mkv")
	var two := season_dir.path_join("Harbour Lights - S01E02 - Salt.mkv")
	FileKey.clear_cache()
	resume._cfg.set_value(FileKey.key(one), "finished", true)
	resume._cfg.set_value(FileKey.key(one), "duration", 2700.0)
	resume._cfg.set_value(FileKey.key(two), "position", 754.0)
	resume._cfg.set_value(FileKey.key(two), "duration", 2700.0)
	_check("a worker's key is the resume data's", LibraryIndex._key(one) == FileKey.key(one))
	files.open_folder(season_dir)
	await _listed()
	var texts := _marks()
	_check("watched, and how far (%s)" % str(texts), texts.has("Watched") and texts.has("0:12 ▶"))
	var row_count: int = files.row_texts().size()
	resume._cfg.set_value(FileKey.key(two), "finished", true)
	resume._cfg.set_value(FileKey.key(two), "position", 0.0)
	files.refresh_markers()
	_check("marks update in place (%s)" % str(_marks()), _marks().count("Watched") == 2
			and files.row_texts().size() == row_count)
	files.open_folder(root_dir.path_join(SHOW))
	await _listed()
	_check("a season says how much (%s)" % str(_marks()), _marks().has("2 of 4"))
	files.open_folder(root_dir)
	await _listed()
	_check("a poster too (%s)" % str(_marks()), _marks().any(func(t: String) -> bool: return t.contains("2 of 6")))
	files.open_folder(root_dir.path_join("TV Shows/Night Ferry (2018)/Season 01"))
	await _listed()
	_check("a row not begun says its length (%s)" % str(_marks()), _marks().has("44 min"))
	resume._cfg.erase_section(FileKey.key(one))
	resume._cfg.erase_section(FileKey.key(two))


func _marks() -> Array:
	var out: Array = []
	for m: Dictionary in files._library_view._marks:
		out.append((m["label"] as Label).text)
	return out


func _image_checks() -> void:
	var images: LibraryImages = LibraryImages.new()
	root.add_child(images)
	DirAccess.make_dir_recursive_absolute(LibraryImages.CACHE_DIR)
	for f in DirAccess.get_files_at(LibraryImages.CACHE_DIR):
		DirAccess.remove_absolute(LibraryImages.CACHE_DIR.path_join(f))
	var poster := root_dir.path_join(SHOW).path_join("poster.jpg")
	var got: Array[Texture2D] = []
	var on_ready := func(t: Texture2D) -> void: got.append(t)
	var frame := Engine.get_process_frames()
	images.request(poster, Vector2i(130, 195), on_ready)
	_check("no picture work on the asking frame", got.is_empty() and Engine.get_process_frames() == frame)
	await _until(func() -> bool: return not got.is_empty(), 5.0)
	_check("a picture at display size", got.size() == 1 and got[0].get_size() == Vector2(130, 195))
	_check("decoded once, cached on disk", images.decoded == 1 and DirAccess.get_files_at(LibraryImages.CACHE_DIR).size()
			== 1)
	images.request(poster, Vector2i(130, 195), on_ready)
	_check("from memory the second time", got.size() == 2)
	images.queue_free()
	await _frames(2)
	var fresh: LibraryImages = LibraryImages.new()
	root.add_child(fresh)
	got.clear()
	fresh.request(poster, Vector2i(130, 195), on_ready)
	await _until(func() -> bool: return not got.is_empty(), 5.0)
	_check("after a restart from the cache, not the source", fresh.cached == 1 and fresh.decoded == 0)
	# Rubbish and a wrong extension.
	var junk := root_dir.path_join("junk.jpg")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("this is not a picture at all, not even a little bit")
	f.close()
	var gotjunk := [false]
	fresh.request(junk, Vector2i(10, 10), func(_t: Texture2D) -> void: gotjunk[0] = true)
	await _seconds(0.3)
	_check("rubbish gives no picture and no crash", not gotjunk[0])
	var fake_ext := root_dir.path_join("really_a_jpeg.png")
	DirAccess.copy_absolute(poster, fake_ext)
	got.clear()
	fresh.request(fake_ext, Vector2i(30, 30), on_ready)
	await _until(func() -> bool: return not got.is_empty(), 5.0)
	_check("a picture named wrongly still shows", got.size() == 1)
	# Many at once reach the GPU one a frame.
	var many := Time.get_ticks_msec()
	var per_frame := 0
	var most := [0]
	got.clear()
	for i in 12:
		fresh.request(poster, Vector2i(40 + i, 60), on_ready)
	var last_count := 0
	while got.size() < 12 and Time.get_ticks_msec() - many < 8000:
		await process_frame
		per_frame = got.size() - last_count
		last_count = got.size()
		most[0] = maxi(most[0], per_frame)
	_check("one a frame (at most %d)" % most[0], got.size() == 12 and most[0] == 1)
	fresh.request(poster, Vector2i(200, 200), on_ready)
	fresh.request(poster, Vector2i(201, 200), on_ready)
	fresh.forget_waiting()
	fresh.queue_free()
	await _frames(2)


func _copy_checks() -> void:
	LibraryCopy.reader_override = func() -> Object: return FakeReader.new()
	AssistantFetch.free_space_override = 100 * 1024 * 1024 * 1024
	var copy: Node = LibraryCopy.ensure(self)
	await _frames(2)
	var events: Array[Dictionary] = []
	copy.event.connect(func(d: Dictionary) -> void: events.append(d))
	NetworkHosts.hosts.append({"host": "nas", "user": "", "password": "", "domain": "", "share": "", "label": ""})
	await _share_checks()
	var content := PackedByteArray()
	content.resize(100000)
	for i in 100000:
		content[i] = i % 251
	FakeReader.content = content
	var to := "TV Shows/New Show (2020)/Season 01/New Show - S01E01 - Pilot.mkv"
	var r: Dictionary = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to})
	_check("copy_to_library starts (%s)" % str(r), r.get("ok") == true and copy.busy())
	await _until(func() -> bool: return not copy.busy(), 5.0)
	var path := root_dir.path_join(to)
	_check("the file is there, whole", FileAccess.get_file_as_bytes(path) == content)
	_check("no .part left", not FileAccess.file_exists(path + ".part"))
	_check("the events (%s)" % str(events.map(func(e: Dictionary) -> String: return e["state"])),
			events[0]["state"] == "started" and events[-1]["state"] == "done" and events[-1]["path"] == path)
	var again: Dictionary = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to})
	_check("a file already there is refused", again.get("refused") == true)
	for bad: String in ["/etc/passwd", "../../outside.mkv", "TV Shows/../../outside.mkv", "TV Shows/.hidden/x.mkv",
			"Movies/x/run.sh", "Elsewhere/x.mkv", "~/x.mkv", "TV Shows/a\\b.mkv", "Movies/x.mkv/../../y.mkv", "",
			"smb://nas/x.mkv", "Movies/a/b/c/d/e.mkv"]:
		var refused: Dictionary = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": bad})
		_check("to refused: %s" % bad, refused.get("refused") == true)
	var unsaved: Dictionary = await commands.run("copy_to_library", {"from": "smb://elsewhere/tv/x.mkv", "to": to + "2"})
	_check("a host not saved is refused (%s)" % str(unsaved.get("error")), unsaved.get("refused") == true)
	var local: Dictionary = await commands.run("copy_to_library", {"from": "/etc/passwd", "to": "Movies/a/passwd.nfo"})
	_check("a local path isn't a source", local.get("refused") == true)
	commands.allow_files = func() -> bool: return false
	var off: Dictionary = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": "Movies/b/b.mkv"})
	_check("files level", off.get("refused") == true)
	commands.allow_files = func() -> bool: return true
	# The share going away, the disk, cancel: nothing left behind.
	events.clear()
	FakeReader.fail_after = 8192
	var to2 := "Movies/Cut (2001)/Cut (2001).mkv"
	r = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to2})
	await _until(func() -> bool: return not copy.busy(), 5.0)
	_check("a broken read fails with the reason and leaves nothing (%s)" % str(events[-1]), events[-1]["state"] == "failed"
			and str(events[-1]["reason"]).contains("went away") and not FileAccess.file_exists(root_dir.path_join(to2))
			and not FileAccess.file_exists(root_dir.path_join(to2) + ".part"))
	FakeReader.fail_after = -1
	FakeReader.error = "NT_STATUS_ACCESS_DENIED"
	events.clear()
	r = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to2})
	await _until(func() -> bool: return not copy.busy(), 5.0)
	_check("a file that won't open", events[-1]["state"] == "failed" and str(events[-1]["reason"]).contains("DENIED"))
	FakeReader.error = ""
	AssistantFetch.free_space_override = AssistantFetch.KEEP_FREE
	events.clear()
	r = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to2})
	await _until(func() -> bool: return not copy.busy(), 5.0)
	_check("keeps 2 GB free (%s)" % str(events[-1]), events[-1]["state"] == "failed"
			and str(events[-1]["reason"]).contains("keeps"))
	AssistantFetch.free_space_override = 100 * 1024 * 1024 * 1024
	FakeReader.slow_msec = 20
	events.clear()
	r = await commands.run("copy_to_library", {"from": "smb://nas/tv/x.mkv", "to": to2})
	await _frames(2)
	var state: Dictionary = (await commands.run("state", {}))["result"]
	_check("/state shows it (%s)" % str(state.get("library_copy")), state.get("library_copy") is Dictionary
			and state["library_copy"]["to"] == to2)
	var two: Dictionary = await commands.run("copy_to_library", {"from": "smb://nas/tv/y.mkv", "to": "Movies/c/c.mkv"})
	_check("one at a time", two.get("refused") == true)
	var stop: Dictionary = await commands.run("copy_cancel", {})
	await _until(func() -> bool: return not copy.busy(), 5.0)
	_check("cancel leaves nothing", stop.get("ok") == true and events[-1]["state"] == "cancelled"
			and not FileAccess.file_exists(root_dir.path_join(to2) + ".part"))
	FakeReader.slow_msec = 0
	# An older engine: only read_file(), so a video is refused with the reason.
	var whole := LibraryCopy.WholeFile.new()
	whole.browser = FakeBrowser.new()
	_check("the old read in pieces", whole.open_read("smb://x/y/z") == 10 and whole.read_next(4).size() == 4
			and whole.read_next(100).size() == 6 and whole.read_next(4).is_empty())
	NetworkHosts.hosts.pop_back()
	LibraryCopy.reader_override = Callable()
	AssistantFetch.free_space_override = -1


class FakeBrowser:
	extends RefCounted

	func read_file(_path: String) -> PackedByteArray:
		var b := PackedByteArray()
		b.resize(10)
		return b

	func get_last_error() -> String:
		return ""


## Finding a file on a share through the API, as an agent must: a stand-in for the host, none of the login.
func _share_checks() -> void:
	DirectoryLister._browsers["nas"] = [FakeMediaBrowser.new(), Mutex.new()]
	var hosts: Dictionary = (await commands.run("list_dir", {"path": "network://"}))["result"]
	var saved: Array = hosts["entries"]
	var is_nas := func(e: Dictionary) -> bool: return e["path"] == "smb://nas"
	_check("the saved hosts, with their paths (%s)" % str(saved), saved.any(is_nas))
	var shares: Dictionary = (await commands.run("list_dir", {"path": "smb://nas"}))["result"]
	_check("a host's shares (%s)" % str(shares["entries"]), (shares["entries"] as Array).any(func(e: Dictionary) -> bool:
		return e["path"] == "smb://nas/Movies"))
	var folder: Dictionary = (await commands.run("list_dir", {"path": "smb://nas/Movies"}))["result"]
	var names: Array = (folder["entries"] as Array).map(func(e: Dictionary) -> String: return e["name"])
	_check("a folder: its videos, each with its exact path", names.has("Comedy.1980.1080p.mkv")
			and not names.has("notes.txt") and (folder["entries"] as Array).any(func(e: Dictionary) -> bool:
				return e["path"] == "smb://nas/Movies/Comedy.1980.1080p.mkv"))
	var everything: Dictionary = (await commands.run("list_dir", {"path": "smb://nas/Movies", "all": true}))["result"]
	_check("all: the other files too", (everything["entries"] as Array).any(func(e: Dictionary) -> bool:
		return e["name"] == "notes.txt"))
	DirectoryLister._browsers.erase("nas")


## The engine's own read in pieces, on local files: over the 64 MiB read_file() stops at, as a video is. Over SMB it
## goes through the same calls and SmbFile, which is what plays videos from a share.
func _engine_checks() -> void:
	if not ClassDB.class_has_method("MediaBrowser", "open_read"):
		print("test_library: this engine has no MediaBrowser.open_read; its checks are skipped")
		return
	var path := root_dir.path_join("big.bin")
	var f := FileAccess.open(path, FileAccess.WRITE)
	var tail := "the last bytes".to_utf8_buffer()
	f.resize(70 * 1048576)
	f.seek(70 * 1048576 - tail.size())
	f.store_buffer(tail)
	f.close()
	var b: Object = ClassDB.instantiate("MediaBrowser")
	_check("read_file stops at 64 MiB", (b.call("read_file", path) as PackedByteArray).is_empty()
			and str(b.call("get_last_error")) != "")
	var size: int = b.call("open_read", path)
	_check("open_read gives the size (%d)" % size, size == 70 * 1048576 and str(b.call("get_last_error")) == "")
	var total := 0
	var last := PackedByteArray()
	var pieces := 0
	while true:
		var piece: PackedByteArray = b.call("read_next", 4194304)
		if piece.is_empty():
			break
		_check_once(piece.size() <= 4194304)
		total += piece.size()
		last = piece
		pieces += 1
	_check("read in pieces to the end (%d in %d)" % [total, pieces], total == size and pieces >= 17)
	_check("the end is the end", last.slice(last.size() - tail.size()) == tail and str(b.call("get_last_error")) == "")
	b.call("close_read")
	_check("nothing open reads nothing", (b.call("read_next", 16) as PackedByteArray).is_empty())
	_check("a missing file (%s)" % str(b.call("get_last_error")), int(b.call("open_read", path + ".nope")) == -1
			and str(b.call("get_last_error")) != "")
	b.call("close_read")
	DirAccess.remove_absolute(path)


func _check_once(ok: bool) -> void:
	if not ok:
		_check("a piece larger than asked", false)


func _guide_checks() -> void:
	var g := AssistantGuide.guide("https://127.0.0.1:47802", "now")
	_check("the guide has the layout", g.contains("TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>.<ext>")
			and g.contains("Movies/<Title> (<Year>)/<Title> (<Year>).<ext>") and g.contains("tvshow.nfo"))
	_check("no placeholder left", not g.contains("<<LIBRARY>>"))
	_check("how to fill it", g.contains("copy_to_library") and g.contains("--write-info-json")
			and g.contains("--metadata") and g.contains("--thumb") and g.contains("-frames:v 1"))
	_check("the year is checked", g.contains("not a guess"))
	_check("shares only through the player", g.contains("Never mount a share") and g.contains("~/.smb-password")
			and g.contains("path=network://") and g.contains("all=true"))
	_check("get_iplayer beyond its search", g.contains("--pid-recursive-list") and g.contains("--metadata-only")
			and g.contains("--thumbnail-only"))
	var doc := AssistantCommands.describe()
	_check("the commands are listed", str(doc).contains("copy_to_library") and str(doc).contains("copy_cancel"))


func _listed() -> void:
	await _until(func() -> bool: return not files.is_busy(), 5.0)
	await _frames(2)


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


func _until(f: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and not bool(f.call()):
		await process_frame


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
