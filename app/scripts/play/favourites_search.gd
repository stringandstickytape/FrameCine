extends Node

## Favourites and search (ideas #76), the data side; the pane shows them, with the on-pane keyboard for the query.
##
## Favourites: files (and folders) the user starred, newest first.
##   favourites()                 [{path, title, is_dir, added}]
##   is_favourite(path), add_favourite(path, title, is_dir), remove_favourite(path), toggle_favourite(path, is_dir)
##   signal favourites_changed
##
## Search: every word of the query must appear in the name (case and accents ignored; dots, dashes and underscores
## count as spaces). Names that start with the query, and favourites, come first.
##   search_known(query) -> [{path, title, is_dir, source}]   favourites, watch history (resume) and the queue
##   search_folder(root, query)    a local folder and its subfolders, on a worker thread; the answer comes as
##                                 folder_results(query, results); a newer search drops an older one's answer.
##                                 At most MAX_DEPTH levels and MAX_VISITED folders. Shares (smb://) are not walked:
##                                 each listing is a network round trip and the browser holds the connection; their
##                                 known files are still found by search_known.
##   static matches(name, query), static score(name, query)
## Settings: [favourites] items (an array of dictionaries).

const VideoSourceFactory := preload("res://scripts/video/video_source_factory.gd")

signal favourites_changed
signal folder_results(query: String, results: Array)

const MAX_DEPTH := 6
const MAX_VISITED := 2000
const MAX_RESULTS := 200

var main: Node3D
var _favs: Array = []
var _search_id := 0
var _tasks: Array[int] = []


func _ready() -> void:
	var stored: Variant = main.settings.get_value("favourites", "items", [])
	_favs = stored if stored is Array else []


func favourites() -> Array:
	return _favs.duplicate(true)


func is_favourite(path: String) -> bool:
	return _index(path) >= 0


func add_favourite(path: String, title := "", is_dir := false) -> void:
	if path == "" or is_favourite(path):
		return
	_favs.push_front({"path": path, "title": title if title != "" else _title(path), "is_dir": is_dir,
			"added": int(Time.get_unix_time_from_system())})
	_store()


func remove_favourite(path: String) -> void:
	var i := _index(path)
	if i >= 0:
		_favs.remove_at(i)
		_store()


func toggle_favourite(path: String, is_dir := false) -> bool:
	if is_favourite(path):
		remove_favourite(path)
		return false
	add_favourite(path, "", is_dir)
	return true


func _index(path: String) -> int:
	for i in _favs.size():
		if str(_favs[i].get("path", "")) == path:
			return i
	return -1


func _store() -> void:
	main.settings.set_value("favourites", "items", _favs.duplicate(true))
	favourites_changed.emit()


static func _title(path: String) -> String:
	var t := path.trim_suffix("/").get_file()
	return t if t != "" else path


## Favourites, watch history and the queue, matched against the query, best first, no duplicates.
func search_known(query: String) -> Array:
	var seen := {}
	var out: Array = []
	var add := func(path: String, title: String, is_dir: bool, source: String) -> void:
		if path == "" or seen.has(path) or not matches(title, query):
			return
		seen[path] = true
		out.append({"path": path, "title": title, "is_dir": is_dir, "source": source,
				"_score": score(title, query) + (100 if source == "favourite" else 0)})
	for f: Dictionary in _favs:
		add.call(str(f["path"]), str(f.get("title", _title(str(f["path"])))), bool(f.get("is_dir", false)), "favourite")
	for e: Dictionary in main.features.resume.continue_watching(1000):
		add.call(str(e["path"]), str(e["path"]).get_file(), false, "history")
	for p: String in main.playlist:
		add.call(p, p.get_file() if not p.begins_with("stub://") else p, false, "queue")
	return _ranked(out)


## Walks a local folder on a worker thread; folder_results(query, results) follows (results as search_known's,
## source "folder").
func search_folder(root: String, query: String) -> void:
	_search_id += 1
	var id := _search_id
	if root.contains("://") or query.strip_edges() == "":
		folder_results.emit(query, [])
		return
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var found := walk(root, query, MAX_DEPTH, MAX_VISITED, MAX_RESULTS)
		_on_folder_done.call_deferred(id, query, found), false, "search " + root))


func _on_folder_done(id: int, query: String, found: Array) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
	if id == _search_id:
		folder_results.emit(query, found)


## Blocking walk (worker thread): video files and folders whose names match, breadth first.
static func walk(root: String, query: String, max_depth := MAX_DEPTH, max_visited := MAX_VISITED,
		max_results := MAX_RESULTS) -> Array:
	var out: Array = []
	var queue: Array = [[root, 0]]
	var visited := 0
	while not queue.is_empty() and visited < max_visited and out.size() < max_results:
		var item: Array = queue.pop_front()
		var dir := DirAccess.open(str(item[0]))
		visited += 1
		if dir == null:
			continue
		dir.include_hidden = false
		for d in dir.get_directories():
			var p := str(item[0]).path_join(d)
			if matches(d, query):
				out.append({"path": p, "title": d, "is_dir": true, "source": "folder", "_score": score(d, query)})
			if int(item[1]) + 1 <= max_depth:
				queue.append([p, int(item[1]) + 1])
		for f in dir.get_files():
			if VideoSourceFactory.is_video_file(f) and matches(f, query):
				out.append({"path": str(item[0]).path_join(f), "title": f, "is_dir": false, "source": "folder",
						"_score": score(f, query)})
	return _ranked(out)


static func _ranked(list: Array) -> Array:
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["_score"] != y["_score"]:
			return x["_score"] > y["_score"]
		return str(x["title"]).naturalnocasecmp_to(str(y["title"])) < 0)
	for e: Dictionary in list:
		e.erase("_score")
	return list


static func normalise(text: String) -> String:
	var t := text.to_lower()
	for c in [".", "_", "-", "(", ")", "[", "]", ","]:
		t = t.replace(c, " ")
	# Common accents, so "cafe" finds "Café".
	var from := "àáâäãåèéêëìíîïòóôöõùúûüçñÿ"
	var to := "aaaaaaeeeeiiiiooooouuuucny"
	for i in from.length():
		t = t.replace(from[i], to[i])
	return " ".join(t.split(" ", false))


static func matches(name: String, query: String) -> bool:
	var n := normalise(name)
	var words := normalise(query).split(" ", false)
	if words.is_empty():
		return false
	for w in words:
		if not n.contains(w):
			return false
	return true


## Higher is better: the name starts with the query, then a word starts with it, then anywhere.
static func score(name: String, query: String) -> int:
	var n := normalise(name)
	var q := normalise(query)
	if n.begins_with(q):
		return 3
	if (" " + n).contains(" " + q):
		return 2
	return 1


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
