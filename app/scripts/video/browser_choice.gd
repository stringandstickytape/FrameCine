extends RefCounted

## Which browser the Browser source starts (scripts/video/window_video_source.gd): one of the flatpak browsers the app
## knows how to drive, of those installed. Chromium is the Frame's own; another (signed in, with its own profile) may
## be installed beside it and chosen in the Browser place (ui/files_tab.gd). Static, like WebPages; main.gd calls
## load_from() once. Kept as [browser] app (the flatpak id; none: the first installed).
##
##   BROWSERS            the known ones: {id, name, history (its profile's History database under the home folder)}
##   installed() -> Array[Dictionary]   those with an install on this machine (the system's or the user's)
##   current() -> Dictionary            the one in use: the chosen one if it is installed, else the first installed,
##                                      else the first known
##   choose(id), next()                 kept in the settings; next(): the one after the current, round the end
## The names are the programs' own (content, never translated).

const BROWSERS: Array[Dictionary] = [
	{"id": "org.chromium.Chromium", "name": "Chromium",
			"history": ".var/app/org.chromium.Chromium/config/chromium/Default/History"},
	{"id": "com.google.Chrome", "name": "Google Chrome",
			"history": ".var/app/com.google.Chrome/config/google-chrome/Default/History"},
]
## Where a flatpak's apps are installed: the system's, then the user's (under the home folder).
const INSTALL_DIRS: Array[String] = ["/var/lib/flatpak/app", "~/.local/share/flatpak/app"]

static var chosen := ""
static var _settings: Object
## Tests: the installed ids, instead of looking on the disk ([""]: look).
static var installed_override: Array = [""]


static func load_from(settings: Object) -> void:
	_settings = settings
	chosen = str(settings.get_value("browser", "app", ""))


static func installed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BROWSERS:
		if _is_installed(str(b["id"])):
			out.append(b)
	return out


static func _is_installed(id: String) -> bool:
	if installed_override != [""]:
		return id in installed_override
	for dir in INSTALL_DIRS:
		var d := dir.replace("~", OS.get_environment("HOME"))
		if DirAccess.dir_exists_absolute(d.path_join(id)):
			return true
	return false


static func current() -> Dictionary:
	var have := installed()
	for b in have:
		if b["id"] == chosen:
			return b
	return have[0] if not have.is_empty() else BROWSERS[0]


static func choose(id: String) -> void:
	for b in BROWSERS:
		if b["id"] == id:
			chosen = id
			if _settings != null:
				# The first one is the default: nothing is kept for it.
				_settings.set_value("browser", "app", null if id == BROWSERS[0]["id"] else id)
			return


static func next() -> Dictionary:
	var have := installed()
	if have.is_empty():
		return current()
	var i := have.find(current())
	choose(str(have[(i + 1) % have.size()]["id"]))
	return current()
