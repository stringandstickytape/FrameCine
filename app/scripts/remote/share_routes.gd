extends RefCounted

const Uri := preload("res://scripts/net/uri.gd")

## The headset as a media server (idea #89; docs/share.md): the phone remote's server (remote_server.gd) also serves
## the Frame's own folders on the LAN when sharing is on. Off by default: --share, [share] enabled = true, or the pane
## (remote.gd start_share()). Same rules as the remote: private addresses only, and the pairing code on every request
## (?k=CODE or X-Remote-Key).
##
##   GET /share                      a page: the folders, their files, an upload box, a screenshot link
##   GET /share/list?root=N&path=P   JSON {root, path, entries: [{name, is_dir, size, modified}]}
##   GET /share/file/N/PATH          a file; Range requests (players can seek); streamed from disk
##   PUT /share/upload/NAME          the body is saved in the Drop folder (never over a file: "name (2).mkv")
##   GET /share/screenshot.png       a new screenshot of both eyes (also kept in the Screenshots folder)
##
## The shared folders (roots), each read-only except Drop: [share] folders = ["/path", ...] if set, else Videos and
## Downloads; then Drop ([share] drop, default ~/Videos/Drop) and Screenshots (user://screenshots).

const MIME := {"mkv": "video/x-matroska", "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime",
		"webm": "video/webm", "avi": "video/x-msvideo", "divx": "video/x-msvideo", "ts": "video/mp2t", "m2ts": "video/mp2t",
		"mpg": "video/mpeg", "mpeg": "video/mpeg", "vob": "video/mpeg", "wmv": "video/x-ms-wmv", "asf": "video/x-ms-asf",
		"flv": "video/x-flv", "rm": "application/vnd.rn-realmedia", "rmvb": "application/vnd.rn-realmedia-vbr",
		"ogv": "video/ogg", "3gp": "video/3gpp", "3g2": "video/3gpp2", "mxf": "application/mxf", "png": "image/png",
		"jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "srt": "text/plain; charset=utf-8",
		"vtt": "text/vtt", "ass": "text/plain; charset=utf-8", "txt": "text/plain; charset=utf-8",
		"json": "application/json", "log": "text/plain; charset=utf-8"}
const SCREENSHOTS := "user://screenshots"
const MAX_UPLOAD := 64 * 1024 * 1024 * 1024


## [{name, path, writable}] for these settings.
static func roots(settings: RefCounted) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = settings.get_value("share", "folders", [])
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE").replace("\\", "/")
	var folders: Array = listed if listed is Array and not (listed as Array).is_empty() else \
			[OS.get_system_dir(OS.SYSTEM_DIR_MOVIES), OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)]
	for f: Variant in folders:
		var p := str(f)
		if p != "" and DirAccess.dir_exists_absolute(p):
			out.append({"name": p.trim_suffix("/").get_file(), "path": p.trim_suffix("/"), "writable": false})
	out.append({"name": "Drop", "path": drop_folder(settings), "writable": true})
	out.append({"name": "Screenshots", "path": ProjectSettings.globalize_path(SCREENSHOTS), "writable": false})
	return out


static func drop_folder(settings: RefCounted) -> String:
	var d := str(settings.get_value("share", "drop", ""))
	if d == "":
		var movies := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
		if movies == "":
			movies = OS.get_environment("HOME").path_join("Videos")
		d = movies.path_join("Drop")
	return d.trim_suffix("/")


## A path inside a root, or "" when `rel` would leave it (.., absolute, backslashes, NUL).
static func resolve(root: Dictionary, rel: String) -> String:
	var r := Uri.decode(rel).replace("\\", "/")
	if r.contains("\u0000") or r.begins_with("/") or (r.length() > 1 and r[1] == ":"):
		return ""
	for part in r.split("/", false):
		if part == ".." or part == ".":
			return ""
	var base: String = root["path"]
	var full := base.path_join(r).simplify_path() if r != "" else base
	if full != base and not full.begins_with(base + "/"):
		return ""
	return full


static func list(root: Dictionary, rel: String) -> Dictionary:
	var dir := resolve(root, rel)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return {"error": "no such folder"}
	var entries: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return {"error": "can't open the folder"}
	d.include_hidden = false
	for name in d.get_directories():
		entries.append({"name": name, "is_dir": true, "size": 0, "modified": FileAccess.get_modified_time(dir.path_join(name))})
	for name in d.get_files():
		var p := dir.path_join(name)
		var f := FileAccess.open(p, FileAccess.READ)
		entries.append({"name": name, "is_dir": false, "size": f.get_length() if f != null else 0,
				"modified": FileAccess.get_modified_time(p)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["is_dir"] != b["is_dir"]:
			return a["is_dir"]
		return str(a["name"]).naturalnocasecmp_to(b["name"]) < 0)
	return {"root": root["name"], "path": Uri.decode(rel), "entries": entries}


static func mime_of(path: String) -> String:
	return MIME.get(path.get_extension().to_lower(), "application/octet-stream")


## "bytes=START-END" against a size: [start, end] inclusive, [] for a bad range, [0, size - 1] without one.
static func parse_range(header: String, size: int) -> Array:
	if header == "":
		return [0, size - 1]
	var m := RegEx.create_from_string("^bytes=(\\d*)-(\\d*)$").search(header.strip_edges())
	if m == null or size <= 0:
		return []
	var a := m.get_string(1)
	var b := m.get_string(2)
	var start := 0
	var end := size - 1
	if a == "" and b == "":
		return []
	if a == "":
		start = maxi(size - b.to_int(), 0)
	else:
		start = a.to_int()
		if b != "":
			end = mini(b.to_int(), size - 1)
	if start > end or start >= size:
		return []
	return [start, end]


## A file name for an upload that is not there yet: "name (2).ext", "name (3).ext", ...
static func free_name(folder: String, name: String) -> String:
	var clean := Uri.decode(name).get_file().validate_filename()
	if clean == "" or clean.begins_with("."):
		clean = "upload.bin"
	var path := folder.path_join(clean)
	var n := 2
	while FileAccess.file_exists(path):
		path = folder.path_join("%s (%d).%s" % [clean.get_basename(), n, clean.get_extension()]) \
				if clean.get_extension() != "" else folder.path_join("%s (%d)" % [clean, n])
		n += 1
	return path


## The share page (plain HTML; the code rides in every link).
static func page(settings: RefCounted, key: String, root_index: int, rel: String) -> String:
	var all := roots(settings)
	var k := "?k=" + key.uri_encode()
	var html := "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>" \
			+ "<title>Headset files</title><style>body{font:15px system-ui;margin:16px;background:#111;color:#eee}" \
			+ "a{color:#7cf;text-decoration:none}li{margin:4px 0}.s{color:#999;font-size:13px}</style>" \
			+ "<h2>Headset files</h2><p>"
	for i in all.size():
		html += "<a href='/share%s&root=%d'>%s</a> &nbsp; " % [k, i, str(all[i]["name"]).xml_escape()]
	html += "| <a href='/share/screenshot.png%s'>Screenshot now</a></p>" % k
	if root_index >= 0 and root_index < all.size():
		var r := list(all[root_index], rel)
		html += "<h3>%s/%s</h3><ul>" % [str(all[root_index]["name"]).xml_escape(), Uri.decode(rel).xml_escape()]
		if r.has("error"):
			html += "<li>%s</li>" % str(r["error"]).xml_escape()
		else:
			if rel != "":
				html += "<li><a href='/share%s&root=%d&path=%s'>..</a></li>" % [k, root_index,
						Uri.decode(rel).get_base_dir().uri_encode()]
			for e: Dictionary in r["entries"]:
				var child := (Uri.decode(rel) + "/" + str(e["name"])).trim_prefix("/")
				if e["is_dir"]:
					html += "<li><a href='/share%s&root=%d&path=%s'>%s/</a></li>" % [k, root_index, child.uri_encode(),
							str(e["name"]).xml_escape()]
				else:
					html += "<li><a href='/share/file/%d/%s%s'>%s</a> <span class=s>%s</span></li>" % [root_index,
							child.uri_encode(), k, str(e["name"]).xml_escape(), String.humanize_size(int(e["size"]))]
		html += "</ul>"
	html += "<h3>Upload to Drop</h3><input type=file id=f multiple> <span id=st class=s></span><script>" \
			+ "document.getElementById('f').onchange=async e=>{const st=document.getElementById('st');" \
			+ "for(const f of e.target.files){st.textContent='Sending '+f.name+'...';" \
			+ "const r=await fetch('/share/upload/'+encodeURIComponent(f.name)+'%s',{method:'PUT',body:f});" % k \
			+ "st.textContent=r.ok?'Saved '+f.name:'Failed: '+await r.text();}}</script>"
	return html


## The shared command (command_host.gd): share_files {on}. Change level: the PC link needs the allowed window, and
## the phone can't turn it on. The reply has the address but not the pairing code (it stays out of logs).
static func register_commands(host: Node) -> void:
	var DevCommands: GDScript = load("res://scripts/dev/dev_commands.gd")
	DevCommands.register("share_files", func(args: Dictionary, ctx: RefCounted) -> Variant:
		var remote: GDScript = load("res://scripts/remote/remote.gd")
		if args["on"]:
			var server: Node = remote.start_share(host.main, args["remember"])
			if server == null:
				return ctx.fail("the server did not start")
			ctx.summary = "the headset's files shared on the LAN"
		else:
			remote.stop_share(host.main, args["remember"])
			ctx.summary = "file sharing off"
		var running: Node = remote.call("_running", host.main)
		return {"on": args["on"], "address": "http://%s:%d/share" % [running.call("_url_host"), running.port]
				if running != null and args["on"] else "", "code": "shown in the pane (Settings, Phone remote)"}, {
		"description": "Shares the headset's folders on the LAN (downloads, uploads to Drop, screenshots; docs/share.md).",
		"params": [{"name": "on", "type": "bool", "required": true},
				{"name": "remember", "type": "bool", "default": false}],
		"level": "change", "returns": "{on, address}"})
