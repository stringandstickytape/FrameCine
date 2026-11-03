extends RefCounted

## The Library place (docs/library.md): a view of the folder ~/Videos/Library, laid out as Kodi and Jellyfin expect. No
## database: each view is read from the folder when it opens, and network shares are never scanned.
##
##   <root>/TV Shows/<Show> (<Year>)/tvshow.nfo, poster.jpg, fanart.jpg
##   <root>/TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>.<ext>, .nfo, -thumb.jpg
##   <root>/Movies/<Title> (<Year>)/<Title> (<Year>).<ext>, .nfo, poster.jpg, fanart.jpg
##
## read() runs on a worker thread (the file tab's): it reads the NFOs and the folders, and touches nothing shared. What
## it gives is plain data; ui/library_view.gd draws it. A folder with no NFO is a plain folder, listed as any other.
##
##   read(path) -> {view: home | shelf | show | season | movie | plain, title, parent, ...}
##   title_for(path), details_for(path): what the player shows for a file of the library
##   playlist_for(path): the file's folder in playing order (videos only: posters and thumbnails sit beside them)

const LibraryNfo := preload("res://scripts/library/library_nfo.gd")
const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")
const FileKey := preload("res://scripts/play/file_key.gd")

const FOLDER_NAME := "Library"
const TV_SHOWS := "TV Shows"
const MOVIES := "Movies"
const SHOW_NFO := "tvshow.nfo"
const MOVIE_NFO := "movie.nfo"
const IMAGES := ["jpg", "jpeg", "png", "webp"]

## Tests: another folder.
static var root_override := ""
static var _root := ""


static func root() -> String:
	if root_override != "":
		return root_override
	if _root == "":
		var videos := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
		if videos == "":
			videos = OS.get_environment("HOME").path_join("Videos")
		_root = videos.path_join(FOLDER_NAME)
	return _root


## Makes the folders the first time the place opens.
static func ensure_root() -> bool:
	return DirAccess.make_dir_recursive_absolute(root().path_join(TV_SHOWS)) == OK \
			and DirAccess.make_dir_recursive_absolute(root().path_join(MOVIES)) == OK


static func is_inside(path: String) -> bool:
	return path != "" and (path == root() or path.begins_with(root() + "/"))


# --- The views -------------------------------------------------------------------------------------------------------

static func read(path: String) -> Dictionary:
	var p := path.trim_suffix("/")
	if p == root():
		return _home(p)
	if p.get_base_dir() == root() and p.get_file() in [TV_SHOWS, MOVIES]:
		return _shelf(p)
	if FileAccess.file_exists(p.path_join(SHOW_NFO)):
		return _show(p)
	if FileAccess.file_exists(p.get_base_dir().path_join(SHOW_NFO)):
		return _season(p)
	var film := _film(p)
	if not film.is_empty():
		return {"view": "movie", "title": film["title"], "parent": p.get_base_dir(), "film": film}
	return {"view": "plain", "title": p.get_file(), "parent": p.get_base_dir()}


static func _home(p: String) -> Dictionary:
	var shows: Dictionary = _shelf(p.path_join(TV_SHOWS))
	var films: Dictionary = _shelf(p.path_join(MOVIES))
	var plain: Array = (shows["plain"] as Array) + (films["plain"] as Array)
	for d: String in _folders(p):
		if not d.get_file() in [TV_SHOWS, MOVIES]:
			plain.append({"name": d.get_file(), "path": d})
	return {"view": "home", "title": FOLDER_NAME, "parent": "", "shows": shows["cards"], "films": films["cards"],
			"plain": plain, "files": (_episodes(p) + (shows["files"] as Array) + (films["files"] as Array))}


## One of the two top folders: its shows and films as cards. A folder with neither NFO stays a plain folder.
static func _shelf(p: String) -> Dictionary:
	var cards: Array = []
	var plain: Array = []
	for d: String in _folders(p):
		var card := _show_card(d) if FileAccess.file_exists(d.path_join(SHOW_NFO)) else _film(d)
		if card.is_empty():
			plain.append({"name": d.get_file(), "path": d})
		else:
			cards.append(card)
	cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["sort"]).naturalnocasecmp_to(str(b["sort"])) < 0)
	return {"view": "shelf", "title": p.get_file(), "parent": p.get_base_dir(), "cards": cards, "plain": plain,
			"files": _episodes(p)}


static func _show_card(d: String) -> Dictionary:
	var nfo := LibraryNfo.read(d.path_join(SHOW_NFO))
	var title := str(nfo.get("title", _clean_name(d.get_file())))
	var keys: Array = []
	for season: String in [d] + _folders(d):
		for f: String in _videos(season):
			keys.append(_key(f))
	var y := LibraryNfo.year(nfo)
	return {"kind": "show", "path": d, "title": title, "sort": _sort_name(nfo, title),
			"year": y if y > 0 else _folder_year(d.get_file()), "plot": str(nfo.get("plot", "")),
			"genre": nfo.get("genre", []), "poster": _image(d, "poster"), "fanart": _image(d, "fanart"), "keys": keys}


## A film's card: a video in the folder with an NFO. {} when there is none.
static func _film(d: String) -> Dictionary:
	var vids := _videos(d)
	if vids.is_empty():
		return {}
	var nfo := {}
	var video := ""
	for v: String in vids:
		nfo = LibraryNfo.read(v.get_basename() + ".nfo")
		if nfo.get("kind", "") == "movie":
			video = v
			break
	if video == "":
		nfo = LibraryNfo.read(d.path_join(MOVIE_NFO))
		if nfo.get("kind", "") != "movie":
			return {}
		video = vids[0]
	var title := str(nfo.get("title", _clean_name(d.get_file())))
	var y := LibraryNfo.year(nfo)
	return {"kind": "movie", "path": d, "title": title, "sort": _sort_name(nfo, title),
			"year": y if y > 0 else _folder_year(d.get_file()), "plot": str(nfo.get("plot", "")),
			"tagline": str(nfo.get("tagline", "")), "genre": nfo.get("genre", []),
			"runtime": maxi(LibraryNfo.number(nfo, "runtime"), 0), "video": video, "keys": [_key(video)],
			"poster": _image(d, "poster"), "fanart": _image(d, "fanart")}


static func _show(p: String) -> Dictionary:
	var card := _show_card(p)
	var nfo := LibraryNfo.read(p.path_join(SHOW_NFO))
	var named: Dictionary = nfo.get("named_seasons", {})
	var seasons: Array = []
	for d: String in _folders(p):
		var vids := _videos(d)
		if vids.is_empty():
			continue
		var n := _season_number(d.get_file())
		var keys: Array = []
		for f: String in vids:
			keys.append(_key(f))
		seasons.append({"path": d, "number": n, "title": str(named.get(n, _season_title(d.get_file(), n))),
				"keys": keys})
	seasons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["number"]) != int(b["number"]):
			# Specials (season 0) go after the seasons, as most people expect them.
			return (int(a["number"]) if int(a["number"]) != 0 else 99999) \
					< (int(b["number"]) if int(b["number"]) != 0 else 99999)
		return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return {"view": "show", "title": card["title"], "parent": p.get_base_dir(), "card": card, "seasons": seasons,
			"episodes": _episodes(p)}


static func _season(p: String) -> Dictionary:
	var show_dir := p.get_base_dir()
	var nfo := LibraryNfo.read(show_dir.path_join(SHOW_NFO))
	var show := str(nfo.get("title", _clean_name(show_dir.get_file())))
	var n := _season_number(p.get_file())
	var named: Dictionary = nfo.get("named_seasons", {})
	return {"view": "season", "title": str(named.get(n, _season_title(p.get_file(), n))), "show": show,
			"parent": show_dir, "fanart": _image(show_dir, "fanart"), "episodes": _episodes(p, show)}


## The videos of a folder with what their NFOs and names say, in episode order.
static func _episodes(dir: String, show := "") -> Array:
	var out: Array = []
	for f: String in _videos(dir):
		out.append(_episode(f, show))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if [a["season"], a["episode"]] != [b["season"], b["episode"]]:
			return _order(a) < _order(b)
		return str(a["path"]).naturalnocasecmp_to(str(b["path"])) < 0)
	return out


## Numbers first in order, then the files that have none.
static func _order(e: Dictionary) -> int:
	return 1 << 40 if int(e["episode"]) < 0 else int(e["season"]) * 100000 + int(e["episode"])


static func _episode(f: String, show := "") -> Dictionary:
	var nfo := LibraryNfo.read(f.get_basename() + ".nfo")
	var from_name := episode_numbers(f.get_file())
	var season := LibraryNfo.number(nfo, "season")
	var episode := LibraryNfo.number(nfo, "episode")
	if season < 0 or episode < 0:
		season = from_name[0]
		episode = from_name[1]
	var titles: PackedStringArray = []
	var last := episode
	for e: Dictionary in nfo.get("episodes", [nfo]):
		if str(e.get("title", "")) != "":
			titles.append(str(e["title"]))
		last = maxi(last, LibraryNfo.number(e, "episode"))
	var title := " / ".join(titles)
	if title == "":
		title = _title_in_name(f.get_basename().get_file())
	var label := ""
	if episode >= 0:
		label = "S%02dE%02d" % [maxi(season, 0), episode]
		if last > episode:
			label += "-E%02d" % last
	return {"path": f, "season": season, "episode": episode, "label": label, "title": title, "show": show,
			"plot": LibraryNfo.summary(nfo), "aired": str(nfo.get("aired", nfo.get("premiered", ""))),
			"runtime": maxi(LibraryNfo.number(nfo, "runtime"), 0), "thumb": _image_named(f.get_basename() + "-thumb"),
			"key": _key(f)}


# --- A file of the library -------------------------------------------------------------------------------------------

## {kind, title, show, season, episode, label, year, plot} for a file in the library, or {} when nothing says more than
## its name. Reads one or two small files: called once when a file opens.
static func details_for(path: String) -> Dictionary:
	if not is_inside(path) or path == root():
		return {}
	var dir := path.get_base_dir()
	var show_dir := ""
	if FileAccess.file_exists(dir.path_join(SHOW_NFO)):
		show_dir = dir
	elif FileAccess.file_exists(dir.get_base_dir().path_join(SHOW_NFO)):
		show_dir = dir.get_base_dir()
	if show_dir != "":
		var e := _episode(path)
		var nfo := LibraryNfo.read(path.get_basename() + ".nfo")
		var show := str(nfo.get("showtitle", ""))
		if show == "":
			show = str(LibraryNfo.read(show_dir.path_join(SHOW_NFO)).get("title", _clean_name(show_dir.get_file())))
		if e["label"] == "" and e["title"] == "":
			return {}
		return {"kind": "episode", "title": e["title"], "show": show, "season": e["season"], "episode": e["episode"],
				"label": e["label"], "plot": e["plot"]}
	var film := _film(dir)
	if film.is_empty() or film["video"] != path:
		return {}
	return {"kind": "movie", "title": film["title"], "year": film["year"], "plot": film["plot"]}


## What the overlay and /state call a file of the library: "Show S01E02: Title", "Title (2001)"; "" for its file name.
static func title_for(path: String) -> String:
	var d := details_for(path)
	match str(d.get("kind", "")):
		"episode":
			var name := " ".join(PackedStringArray([d["show"], d["label"]])).strip_edges()
			return "%s: %s" % [name, d["title"]] if str(d["title"]) != "" else name
		"movie":
			return "%s (%d)" % [d["title"], d["year"]] if int(d["year"]) > 0 else str(d["title"])
	return ""


## The videos of the file's folder: episodes by the numbers in their names, others by name.
static func playlist_for(path: String) -> Array[String]:
	var vids := _videos(path.get_base_dir())
	var key := func(f: String) -> int:
		var n: Array = episode_numbers(f.get_file())
		return 1 << 40 if n[1] < 0 else maxi(n[0], 0) * 100000 + n[1]
	vids.sort_custom(func(a: String, b: String) -> bool:
		var ka: int = key.call(a)
		var kb: int = key.call(b)
		return ka < kb if ka != kb else a.naturalnocasecmp_to(b) < 0)
	return vids


# --- Names ------------------------------------------------------------------------------------------------------------

## [season, episode] in a file's name (S01E02, s1e2), [-1, -1] without them.
static func episode_numbers(file_name: String) -> Array:
	var re := RegEx.create_from_string("(?i)(?:^|[^a-z0-9])s(\\d{1,3})e(\\d{1,4})")
	var m := re.search(file_name)
	return [m.get_string(1).to_int(), m.get_string(2).to_int()] if m != null else [-1, -1]


## "Show - S01E02 - The Title" -> "The Title"; "" when the numbers are all it has; a name without numbers is its own.
static func _title_in_name(stem: String) -> String:
	var m := RegEx.create_from_string("(?i)(?:^|[^a-z0-9])s\\d{1,3}e\\d{1,4}(?:-?e\\d{1,4})*\\s*-\\s*(.+)$").search(stem)
	if m != null:
		return m.get_string(1).strip_edges()
	return "" if episode_numbers(stem)[1] >= 0 else stem


## "Show (2001)" -> "Show".
static func _clean_name(folder: String) -> String:
	var re := RegEx.create_from_string("\\s*\\((?:19|20)\\d\\d\\)\\s*$")
	return re.sub(folder, "").strip_edges()


static func _folder_year(folder: String) -> int:
	var m := RegEx.create_from_string("\\(((?:19|20)\\d\\d)\\)\\s*$").search(folder)
	return m.get_string(1).to_int() if m != null else 0


## A sort title, or the title without a leading "The ".
static func _sort_name(nfo: Dictionary, title: String) -> String:
	return str(nfo.get("sorttitle", title.trim_prefix("The ")))


## "Season 01" -> 1, "Specials" -> 0, anything else -1.
static func _season_number(folder: String) -> int:
	if folder.to_lower() == "specials":
		return 0
	var m := RegEx.create_from_string("(?i)^(?:season|series)\\s*(\\d+)$").search(folder.strip_edges())
	return m.get_string(1).to_int() if m != null else -1


static func _season_title(folder: String, n: int) -> String:
	if n > 0:
		return "Season %d" % n
	return "Specials" if n == 0 else folder


# --- Files ------------------------------------------------------------------------------------------------------------

static func _folders(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.include_hidden = false
	for name in d.get_directories():
		out.append(dir.path_join(name))
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


static func _videos(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.include_hidden = false
	for name in d.get_files():
		if VideoSourceFactory.is_video_file(name):
			out.append(dir.path_join(name))
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


static func _image(dir: String, stem: String) -> String:
	return _image_named(dir.path_join(stem))


static func _image_named(stem_path: String) -> String:
	for ext: String in IMAGES:
		if FileAccess.file_exists(stem_path + "." + ext):
			return stem_path + "." + ext
	return ""


## The resume data's key, worked out here without FileKey's cache of sizes: that cache belongs to the main thread.
static func _key(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return FileKey.key_for_size(path, f.get_length() if f != null else -1)
