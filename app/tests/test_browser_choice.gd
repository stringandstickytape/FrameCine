extends SceneTree

## Tests for the choice of browser (scripts/video/browser_choice.gd): the installed ones, the one in use, choosing and
## stepping, what is kept in the settings, and the history database read for it. Starting a real browser needs the
## headset.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_browser_choice.gd

const BrowserChoice := preload("res://scripts/video/browser_choice.gd")
const AppSettings := preload("res://scripts/app_settings.gd")

var _failures := 0
var _checks := 0


func _init() -> void:
	var s := AppSettings.new()
	s.read_only = true
	var first: String = BrowserChoice.BROWSERS[0]["id"]
	var second: String = BrowserChoice.BROWSERS[1]["id"]
	BrowserChoice.load_from(s)
	BrowserChoice.installed_override = []
	_check("none installed: the first known stands in", BrowserChoice.installed().is_empty()
			and BrowserChoice.current()["id"] == first)
	BrowserChoice.installed_override = [first]
	_check("one installed: it is the one", BrowserChoice.installed().size() == 1 and BrowserChoice.current()["id"] == first)
	_check("next with one: the same", BrowserChoice.next()["id"] == first)
	BrowserChoice.installed_override = [first, second]
	_check("two installed: the first by default, nothing kept", BrowserChoice.current()["id"] == first
			and not s.has_value("browser", "app"))
	_check("next: the second, kept", BrowserChoice.next()["id"] == second and s.get_value("browser", "app", "") == second)
	var again := AppSettings.new()
	again.read_only = true
	again.set_value("browser", "app", second)
	BrowserChoice.load_from(again)
	_check("read back from the settings", BrowserChoice.current()["id"] == second)
	_check("its own profile's history is the one read", str(BrowserChoice.current()["history"]).contains(second))
	_check("next again: round to the first, the key goes", BrowserChoice.next()["id"] == first
			and not again.has_value("browser", "app"))
	BrowserChoice.choose("no.such.Browser")
	_check("an unknown one is not chosen", BrowserChoice.current()["id"] == first)
	BrowserChoice.choose(second)
	BrowserChoice.installed_override = [first]
	_check("the chosen one uninstalled: the first installed", BrowserChoice.current()["id"] == first)
	BrowserChoice.installed_override = [""]
	BrowserChoice.chosen = ""
	# Other programs' sound while the microphone records (scripts/play/other_sound.gd): which streams are muted.
	var OtherSound := load("res://scripts/play/other_sound.gd") as GDScript
	var listing := JSON.stringify([{"index": 3, "mute": false, "properties": {"application.name": "FrameCine"}},
			{"index": 4, "mute": false, "properties": {}},
			{"index": 5, "mute": false, "properties": {"application.name": "Google Chrome"}},
			{"index": 6, "mute": true, "properties": {"application.name": "A player"}}])
	_check("the browser's stream is muted; not the app's, a nameless one or one muted already",
			OtherSound.targets(listing) == [5] and OtherSound.targets("[]").is_empty())
	print("test_browser_choice: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL %s" % what)
