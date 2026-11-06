extends SceneTree

## The panel's logic without the app (docs/ui-design.md, "Revision 2"): the front pose (level, looking down, lying
## back), the lazy head follow, the menu button's press / hold / release, the mode chips; and the theming rule that no
## panel script writes a colour or a font itself (they all come from ui/themes/default.tres).
##
##   godot --headless --xr-mode off --path app --script res://tests/test_pane.gd

const PanePose := preload("res://ui/pane_pose.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const FilesTab := preload("res://ui/files_tab.gd")
const PaneUI := preload("res://ui/pane_ui.gd")
const HelpTexts := preload("res://ui/help_texts.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const ControllerBattery := preload("res://scripts/xr/controller_battery.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_menu_press()
	_chips()
	_controller_battery()
	_theme()
	_help_texts()
	print("Pane test: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The menu button: press, short release, hold.
func _menu_press() -> void:
	var m := PanePose.MenuPress.new()
	var left := RefCounted.new()
	var right := RefCounted.new()
	_check("menu: a press on a closed panel opens it at once", m.press(right, false) == "open")
	m.step(0.8)
	_check("menu: held after opening, no recentre", m.step(0.1) == "" and m.release(right) == "")
	_check("menu: a press on an open panel waits", m.press(right, true) == "")
	m.step(0.2)
	_check("menu: a short press closes on release", m.release(right) == "close")
	m.press(left, true)
	var fired := ""
	for i in 30:
		var r := m.step(0.016)
		if r != "":
			fired = r
	_check("menu: 0.48 s held, nothing yet", fired == "")
	for i in 10:
		var r := m.step(0.016)
		if r != "":
			fired = r
	_check("menu: 0.64 s held: recentre", fired == "recentre" and m.hand == left)
	_check("menu: recentre once only", m.step(1.0) == "")
	_check("menu: released after a recentre: stays open", m.release(left) == "")
	m.hold = 1.0
	m.press(right, true)
	m.step(0.7)
	_check("menu: [pane] recentre_hold 1 s: 0.7 s still a short press", m.release(right) == "close")
	m.hold = PanePose.RECENTRE_HOLD
	_check("menu: seat picking takes the press", m.press(right, true, true) == "cancel" and m.step(1.0) == "")
	m.release(right)
	_check("menu: a release with nothing pressed does nothing", m.release(left) == "" and not m.is_held())


func _chips() -> void:
	for case: Array in [["Movie.2019.1080p.mkv", ""], ["Animated.Feature.2019.HSBS.mkv", "SBS"],
			["Trip_180_SBS.mp4", "180 SBS"], ["Tour.360.TB.mp4", "360 TB"], ["Dome_fisheye_200_sbs.mp4", "FISHEYE SBS"]]:
		var chip := FilesTab.chip_text(VideoMode.guess(case[0]))
		_check("mode chip for %s: '%s'" % [case[0], chip], chip == case[1])


## Controller batteries (#75): Device batteries under a fake power-supply tree, the side from the name, and one
## warning per threshold.
func _controller_battery() -> void:
	var root := ProjectSettings.globalize_path("user://test_power_supply")
	for entry: Array in [["hid-ctrl_l", "Battery", "Device", "12", "Controller L"],
			["hid-ctrl-right", "Battery", "Device", "80", "Controller"], ["gauge", "Battery", "System", "55", "gauge"],
			["usb", "USB", "Device", "", ""]]:
		var dir := root.path_join(entry[0])
		DirAccess.make_dir_recursive_absolute(dir)
		for pair: Array in [["type", entry[1]], ["scope", entry[2]], ["capacity", entry[3]], ["model_name", entry[4]]]:
			var f := FileAccess.open(dir.path_join(pair[0]), FileAccess.WRITE)
			f.store_string(str(pair[1]) + "\n")
	var levels := ControllerBattery.read_levels(root)
	_check("controller batteries from Device entries only (%s)" % levels, levels == {"left": 12, "right": 80})
	var cb := ControllerBattery.new()
	var warnings: Array = []
	cb.low.connect(func(side: String, pct: int) -> void: warnings.append([side, pct]))
	cb._fake = {"left": 14}
	cb.poll()
	cb.poll()
	_check("15 %: one warning, not again", warnings == [["left", 14]])
	cb._fake = {"left": 4}
	cb.poll()
	_check("5 %: a second warning", warnings.size() == 2 and warnings[1] == ["left", 4])
	cb._fake = {"left": 90}
	cb.poll()
	cb._fake = {"left": 14}
	cb.poll()
	_check("charged and low again: warns again", warnings.size() == 3)
	_check("text lists the levels", cb.text() == "Controller battery: left 14 %")
	cb.free()


## Theming: the theme has the doc's tokens, and no pane script sets a colour or a font itself.
func _theme() -> void:
	var t := PaneStyle.theme()
	_check("theme loads", t != null and t.default_font != null)
	for token in ["surface", "edge", "text", "muted", "accent", "hairline", "laser", "laser_dot", "seek_played"]:
		_check("token colour %s" % token, t.has_color(token, PaneStyle.TOKENS))
	_check("accent is pale ice #9CCBE8", PaneStyle.color(&"accent").to_html(false) == "9ccbe8")
	_check("pane 740 x 600 px at 3080 px/m is 24 x 19.5 cm", PaneStyle.pane_metres().is_equal_approx(Vector2(740, 600) / 3080.0))
	_check("labels are 11 px, body 15, title 22", PaneStyle.font_size(&"label") == 11 and t.default_font_size == 15
			and PaneStyle.font_size(&"title") == 22)
	_check("header status line: clock, time left and end, battery", PaneUI.status_text("21:42", "1:12 left",
			"ends 22:54", 74, false) == "21:42  ·  1:12 left, ends 22:54  ·  battery 74 %")
	_check("header status line: nothing playing, no battery, low controller, listening", PaneUI.status_text("21:42", "",
			"", -1, false, "Left controller 12 %", true) == "21:42  ·  Left controller 12 %  ·  Listening")
	var banned := RegEx.create_from_string(
			"Color\\(|Color\\.[A-Z]|add_theme_color_override|add_theme_font_override|add_theme_font_size_override|load\\(.*\\.(ttf|otf|woff)|FontFile|FontVariation|SystemFont")
	var dir := DirAccess.open("res://ui")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string("res://ui/" + f).split("\n")
		var hits: Array[String] = []
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			if banned.search(line) != null:
				hits.append("%d: %s" % [i + 1, line])
		_check("ui/%s writes no colour or font itself%s" % [f, ("  " + "; ".join(hits)) if not hits.is_empty() else ""],
				hits.is_empty())


## Help lines (ui/help_texts.gd): the Picture and Sound tabs have them, each fits one line of the panel ("Name: "
## included), and each is a sentence.
func _help_texts() -> void:
	_check("help texts for Picture and Sound", HelpTexts.PICTURE.size() >= 30 and HelpTexts.SOUND.size() >= 8)
	var long: Array[String] = []
	var unfinished: Array[String] = []
	for tab: Dictionary in [HelpTexts.PICTURE, HelpTexts.SOUND]:
		for key: String in tab:
			var text := str(tab[key])
			if key.length() + 2 + text.length() > 84:
				long.append(key)
			if not text.ends_with("."):
				unfinished.append(key)
	_check("help texts fit one line (%s)" % ", ".join(long), long.is_empty())
	_check("help texts are sentences (%s)" % ", ".join(unfinished), unfinished.is_empty())


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
