extends RefCounted

## The browser's saved pages and the last URL opened: the core's store for the file browser's "Browser" place. Static
## like NetworkHosts; main.gd calls load_from() once. Stored in user://settings.cfg, section "browser", keys "pages"
## (an array of URLs) and "last_url". No pages are built in.

const AppSettings := preload("res://scripts/app_settings.gd")

static var pages: Array[String] = []
static var last_url := ""
static var _settings: AppSettings


static func load_from(settings: AppSettings) -> void:
	_settings = settings
	pages.clear()
	for p: Variant in settings.get_value("browser", "pages", []):
		var u := normalized(str(p))
		if u != "" and not pages.has(u):
			pages.append(u)
	last_url = str(settings.get_value("browser", "last_url", ""))


## Trims the text and adds https:// when there is no scheme ("example.com" -> "https://example.com"). "" stays "".
static func normalized(text: String) -> String:
	var u := text.strip_edges()
	if u == "":
		return ""
	if not u.contains("://") and not u.begins_with("about:") and not u.begins_with("file:"):
		u = "https://" + u
	return u


static func add_page(page_url: String) -> void:
	var u := normalized(page_url)
	if u != "" and not pages.has(u):
		pages.append(u)
		_persist()


static func remove_page(page_url: String) -> void:
	if pages.has(page_url):
		pages.erase(page_url)
		_persist()


static func set_last_url(page_url: String) -> void:
	last_url = page_url
	if _settings != null:
		_settings.set_value("browser", "last_url", page_url)


static func _persist() -> void:
	if _settings != null:
		_settings.set_value("browser", "pages", pages.duplicate())
