extends SceneTree

## Tests for the menus' languages (scripts/i18n.gd, docs/i18n.md) in the real main scene: the Chinese .po loads, and
## its keys and messages.pot agree for the shared parts; switching to Chinese changes the rail, the System tab and the
## built texts at once, and back; the pseudo-locale leaves no plain English on the rail, the transport, the footer or
## any section of the System tab; content (a name equal to a key) is never translated; plurals through tr_n; the
## controller legends in Chinese, every glyph in the atlas, which grows and keeps its UVs; the fonts (the fallback is
## there, covers every Chinese text, and keeps the line height); Chinese wraps.
## Run: godot --headless --xr-mode off --path app --script res://tests/test_i18n.gd

const I18n := preload("res://scripts/i18n.gd")
const W := preload("res://ui/pane_widgets.gd")
const PaneStyle := preload("res://ui/pane_style.gd")
const LabelFont := preload("res://scripts/xr/label_font.gd")
const LabelLayout := preload("res://scripts/xr/label_layout.gd")
const LabelSurface := preload("res://scripts/xr/label_surface.gd")
const TestLab := preload("res://scripts/dev/test_lab.gd")
const PO := "res://locale/zh_CN.po"
## The stage-1 files (docs/i18n.md): their keys are all in zh_CN.po.
const SHARED := ["ui/pane_ui.gd", "ui/pane_widgets.gd", "ui/tablet.gd", "ui/system_tab.gd", "ui/ui_layer.gd",
		"ui/help_texts.gd", "ui/hand_hint.gd", "ui/world_toast.gd", "ui/hw_video_row.gd", "ui/assistant_row.gd",
		"scripts/main.gd", "scripts/play/end_time.gd", "scripts/play/film_layer.gd", "scripts/play/real_windows.gd",
		"scripts/play/hw_video.gd", "scripts/xr/controller_look.gd", "scripts/assistant/assistant_switches.gd",
		"ui/themes/tablet.json"]

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
	_check("starts in English, whatever the OS says", I18n.language == "en" and TranslationServer.get_locale() == "en")
	_files()
	await _switching()
	await _pseudo()
	await _content()
	await _fits()
	_plural()
	await _legends()
	_fonts()
	_wrapping()
	I18n.set_language("en")
	print("test_i18n: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(_failures)


## The .po, the template and the font agree.
func _files() -> void:
	var t := load(PO) as Translation
	_check("zh_CN.po loads", t != null and t.get_message("Source") == "片源")
	_check("it is loaded for zh_CN", "zh_CN" in TranslationServer.get_loaded_locales())
	_check("no entry is fuzzy (Godot would skip it)", not FileAccess.get_file_as_string(PO).contains("#, fuzzy"))
	var pot := _pot_refs()
	var po_keys := {}
	for e: Array in I18n.pot_entries(PO):
		po_keys[e[0]] = true
	var extra: Array = po_keys.keys().filter(func(k: String) -> bool: return not pot.has(k))
	_check("every key of zh_CN.po is in messages.pot (%s)" % ", ".join(extra), extra.is_empty())
	var missing: Array = []
	for k: String in pot:
		var shared := (pot[k] as Array).any(func(ref: String) -> bool: return ref.get_slice(":", 0) in SHARED)
		if shared and not po_keys.has(k):
			missing.append(k)
	_check("every key of the shared parts is in zh_CN.po (%s)" % ", ".join(missing), missing.is_empty())
	_check("the pot has the shared parts' keys", pot.has("Source") and pot.has("PLAY / PAUSE") and pot.has("Plum & gold")
			and pot.has("Let the assistant run apps") and pot.has("Black") and pot.has("%d item"))
	_check("no setting key or dev command is a key", not pot.has("trigger") and not pot.has("section")
			and not pot.has("next_file"))


## Switching to Chinese and back, live.
func _switching() -> void:
	var pui: Node = main.ui.ui
	var rail: Button = pui.tablet_tab_buttons[0]
	var system: Node = pui.system
	var heading := _find(system, func(c: Node) -> bool: return c is Label and c.get_meta("section", "") == "Language")
	var engine := _find(system, func(c: Node) -> bool: return c is Label and str(c.get("text")).begins_with("Engine "))
	_check("English: the rail says Source", _shown(rail) == "Source" and heading != null and _shown(heading) == "Language")
	I18n.choose(main.settings, "zh_CN")
	await _frames(1)
	_check("Chinese: the rail says 片源 (%s)" % _shown(rail), _shown(rail) == "片源")
	_check("the System tab's heading in Chinese", heading != null and _shown(heading) == "语言")
	_check("a built line is built again (%s)" % (engine.text if engine != null else "none"),
			engine != null and str(engine.text).begins_with("引擎 "))
	_check("the choice is kept as [language] ui", main.settings.get_value("language", "ui", "") == "zh_CN")
	var row: Node = system.get("_language_row")
	var names: Array = row.get_children().map(func(b: Button) -> String: return _shown(b))
	_check("the languages in their own names (%s)" % [names], names.has("English") and names.has("简体中文"))
	_check("the pressed one is Chinese", row.get_children().any(func(b: Button) -> bool:
			return b.button_pressed and b.get_meta("language") == "zh_CN"))
	var legends: Dictionary = main.controller_labels(main.PREVIEW_PROFILE, "right", false)
	_check("the controller legends in Chinese (%s)" % legends.get("trigger"), legends.get("trigger") == "播放 / 暂停")
	_check("a pushed stick says so in Chinese", str(legends.get("thumbstick", "")).contains("按下：菜单"))
	_check("the header's times in Chinese", main.features.end_text(true) == "" or main.features.end_text(true).contains("结束"))
	I18n.choose(main.settings, "en")
	await _frames(1)
	_check("back to English: Source", _shown(rail) == "Source" and _shown(heading) == "Language")
	_check("the built line too", engine != null and str(engine.text).begins_with("Engine "))
	_check("English is not written down", main.settings.get_value("language", "ui", "none") == "none")
	_check("English legends", main.controller_labels(main.PREVIEW_PROFILE, "right", false).get("trigger") == "PLAY / PAUSE")


## The pseudo-locale: every visible text of the shared parts and of each System section is pseudo, a number, or
## content.
func _pseudo() -> void:
	_check("pseudo text: accented, bracketed, about a third longer (%s)" % I18n.pseudo_text("Settings"),
			I18n.pseudo_text("Settings").begins_with("[Šéţţîñĝš") and I18n.pseudo_text("Settings").length() >= 11)
	_check("placeholders kept", I18n.pseudo_text("Delete %s from the library?").contains("%s"))
	_check("not offered outside dev mode", not I18n.languages().any(func(l: Array) -> bool: return l[0] == I18n.PSEUDO)
			or main.get_tree().root.has_node("DevHost"))
	var pui: Node = main.ui.ui
	main.ui.show_panel()
	I18n.set_language(I18n.PSEUDO)
	await _frames(1)
	var plain: Array[String] = []
	pui.show_tab(pui.Tab.SYSTEM)
	await _frames(2)
	# The rail, the transport, the footer: everything of the menu but the tabs. The footer's mode line is the
	# Picture tab's (mode_text(), to be wrapped with that tab).
	var skip: Array = pui.tabs.filter(func(t: Node) -> bool: return t != pui.system)
	skip.append(pui._footer_text)
	_plain_under(pui, skip, plain)
	var sections: Array[String] = W.shown_sections(pui.system.box)
	for s in sections:
		pui.show_section(s)
		await _frames(1)
		_plain_under(pui.system, [], plain)
	_check("System has its sections (%d)" % sections.size(), sections.size() >= 10)
	_check("pseudo: no plain English (%s)" % " | ".join(plain), plain.is_empty())
	I18n.set_language("en")
	await _frames(1)
	_check("English again after pseudo", _shown(pui.tablet_tab_buttons[0]) == "Source")
	pui.show_tab(pui.Tab.FILES)


## Content stays as it is, even when it is a key.
func _content() -> void:
	var pui: Node = main.ui.ui
	var box: VBoxContainer = pui.system.box
	var name_label := W.label("Room")
	W.content(name_label)
	var word := W.label("Room")
	box.add_child(name_label)
	box.add_child(word)
	I18n.set_language("zh_CN")
	await _frames(1)
	_check("a name that is a key stays (%s)" % _shown(name_label), _shown(name_label) == "Room")
	_check("the same word as a fixed text translates (%s)" % _shown(word), _shown(word) == "房间")
	var tablet: Node = main.ui.tablet
	_check("the tablet's title is content", tablet.title_label.atr("Room") == "Room")
	pui.show_toast("Room")
	_check("a toast shows as given", _shown(pui._toast_label) == "Room")
	pui.hide_toast()
	main.ui.world_toast.show_text("Room")
	_check("a notice in the world shows as given", main.ui.world_toast.atr("Room") == "Room")
	main.ui.hand_hint.text = "Room"
	_check("the hand hint shows as given", main.ui.hand_hint.atr("Room") == "Room")
	I18n.set_language("en")
	name_label.queue_free()
	word.queue_free()


## In Chinese and in the pseudo-locale the menu still fits the tablet's main pane, as test_tablet.gd checks in English.
func _fits() -> void:
	var layer: Node = main.ui
	var pui: Node = layer.ui
	layer.show_panel()
	for code: String in ["zh_CN", I18n.PSEUDO]:
		I18n.set_language(code)
		pui.show_tab(pui.Tab.FILES)
		await _frames(3)
		var rail_scroll: Control = pui._tablet_row.get_node("RailScroll")
		var rail_rows: Control = rail_scroll.get_node("Rail")
		var footer_end: float = pui._footer_count.get_parent().get_global_rect().end.y
		_check("%s: the menu fits (rail %.0f of %.0f px, footer to %.0f of %d)" % [code,
				rail_rows.get_combined_minimum_size().y, rail_scroll.size.y, footer_end, layer.tablet.panel_pixels().y],
				rail_rows.get_combined_minimum_size().y <= rail_scroll.size.y + 0.5
				and footer_end <= layer.tablet.panel_pixels().y)
	I18n.set_language("en")
	await _frames(1)


func _plural() -> void:
	_check("English plurals", TranslationServer.translate_plural("%d item", "%d items", 1) == "%d item"
			and TranslationServer.translate_plural("%d item", "%d items", 3) == "%d items")
	I18n.set_language("zh_CN")
	_check("Chinese has one form (%s)" % TranslationServer.translate_plural("%d item", "%d items", 3),
			TranslationServer.translate_plural("%d item", "%d items", 3) == "%d 个项目"
			and TranslationServer.translate_plural("%d item", "%d items", 1) == "%d 个项目")
	I18n.set_language(I18n.PSEUDO)
	_check("pseudo plurals (%s)" % TranslationServer.translate_plural("%d item", "%d items", 3),
			TranslationServer.translate_plural("%d item", "%d items", 3).begins_with("[%d îţéṁš".replace("ṁ", "m"))
			and TranslationServer.translate_plural("%d item", "%d items", 1).begins_with("[%d îţém "))
	I18n.set_language("en")


## The controller legends: Chinese shaped from the fallback, every glyph in the atlas; many glyphs grow it.
func _legends() -> void:
	var a_before: Dictionary = LabelFont.shape("A")
	var legend := "播放 / 暂停"
	var shaped: Dictionary = LabelFont.shape(legend)
	var quads: Array = shaped["quads"]
	_check("a Chinese legend: a quad for each of its 5 glyphs (%d)" % quads.size(), quads.size() == 5)
	_check("each in the atlas", quads.all(func(q: Array) -> bool: return (q[1] as Rect2).size.x > 0.0))
	_check("it is about one em per character", (shaped["size"] as Vector2).x > 4.0 and (shaped["size"] as Vector2).x < 6.5)
	# Every Chinese character of the translation: hundreds of glyphs.
	var chars := {}
	var t := load(PO) as Translation
	for s: String in t.get_translated_message_list():
		for c in s:
			if c.unicode_at(0) >= 0x4E00 and c.unicode_at(0) <= 0x9FFF:
				chars[c] = true
	# 400 of them: far more than every legend in every language needs (a few dozen), and the atlas still has room.
	var some: Array = chars.keys().slice(0, 400)
	var many: Array = LabelFont.shape("".join(some))["quads"]
	_check("%d characters: every one laid (%d), the atlas grown to %d px" % [some.size(), many.size(),
			LabelFont.atlas_size()], some.size() == 400 and many.size() == some.size() and LabelFont.atlas_size() > 512)
	var a_after: Dictionary = LabelFont.shape("A")
	_check("a glyph from before keeps its UV", (a_before["quads"][0][1] as Rect2).is_equal_approx(a_after["quads"][0][1]))
	var tex := LabelFont.texture()
	_check("the texture is the grown atlas", tex != null and tex.get_width() == LabelFont.atlas_size())
	# A legend too wide for its room is printed smaller (label_layout.gd), a longer pseudo one too.
	var entry := {"line_height": 0.0045, "width": 0.012}
	var long := I18n.pseudo_text("SCROLL / KEYS")
	_check("a long legend is printed smaller", LabelLayout.fitted_line(entry, long) < 0.0045
			and LabelLayout.fitted_line(entry, "菜单") == 0.0045)
	# Printed on a plate as on the controller (label_surface.gd): every glyph kept.
	var plate := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	plate.mesh = mesh
	root.add_child(plate)
	var surface := LabelSurface.new()
	surface.add_part(plate, Transform3D())
	var line := 0.0045
	var scale := LabelLayout.metres_per_em(line)
	var size: Vector2 = shaped["size"] * scale
	var laid := surface.lay(Transform3D(), Vector3(size.x, 0.012, size.y), quads, scale)
	_check("printed on a plate with all its glyphs (%d of %d)" % [(laid.get("kept", []) as Array).size(), quads.size()],
			not laid.is_empty() and (laid["kept"] as PackedInt32Array).size() == quads.size())
	plate.queue_free()
	await _frames(1)


func _fonts() -> void:
	var cjk := I18n.cjk_font()
	_check("the Chinese font loads", cjk.data.size() > 0 and cjk.has_char("片".unicode_at(0)))
	var medium := PaneStyle.font(&"medium") as FontVariation
	_check("the menu's fonts fall back to it", medium != null and (medium.base_font as FontFile).fallbacks.has(cjk))
	var t := load(PO) as Translation
	var missing := {}
	for s: String in t.get_translated_message_list():
		for c in s:
			if c.unicode_at(0) > 0x7F and not cjk.has_char(c.unicode_at(0)) \
					and not (medium.base_font as FontFile).has_char(c.unicode_at(0)):
				missing[c] = true
	_check("it has every character of the Chinese texts (%s)" % "".join(missing.keys()), missing.is_empty())
	var fira := FontFile.new()
	fira.load_dynamic_font("res://ui/fonts/FiraSansCondensed-Regular.ttf")
	_check("its line is no taller than Fira's (%.1f, %.1f)" % [cjk.get_height(22), fira.get_height(22)],
			cjk.get_height(22) <= fira.get_height(22) + 0.5)
	_check("so the menu's rows keep their height", absf(medium.get_height(22) - fira.get_height(22)) < 0.5)
	PaneStyle.reload()
	var again := PaneStyle.theme().get_font(&"medium", PaneStyle.TOKENS) as FontVariation
	_check("a theme read again keeps the fallback", again != null and (again.base_font as FontFile).fallbacks.has(cjk))


## Chinese wraps between characters (the TextServer's line breaking), within the width.
func _wrapping() -> void:
	var p := TextParagraph.new()
	p.add_string("每次更改都会立即显示，并作为一个房间保存在房间页中。可以让助手改回来，或用重置房间恢复原装房间。",
			PaneStyle.font(&"regular"), 20)
	p.width = 200.0
	p.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var widest := 0.0
	for i in p.get_line_count():
		widest = maxf(widest, p.get_line_width(i))
	_check("a Chinese sentence wraps into lines (%d, widest %.0f px)" % [p.get_line_count(), widest],
			p.get_line_count() >= 4 and widest <= 200.0)


## The visible Labels and Buttons under `n` (not under `skip`) whose text is plain English in the pseudo-locale.
func _plain_under(n: Node, skip: Array, out: Array[String]) -> void:
	var cards := {}
	for c: Dictionary in TestLab.cards():
		cards[str(c["label"])] = true
	for c in n.find_children("*", "", true, false):
		if not (c is Label or c is Button) or not (c as CanvasItem).is_visible_in_tree():
			continue
		if skip.any(func(s: Node) -> bool: return s == c or s.is_ancestor_of(c)):
			continue
		var s := _shown(c)
		if not RegEx.create_from_string("[A-Za-z]{2,}").search(s) or s.begins_with("["):
			continue
		# Content left as it is on purpose: the player's name, the lab's card names (to have keys in stage 2), the
		# languages' own names, an assistant service's own status line.
		if s.begins_with("VR Video Player") or cards.has(s) or s == "English":
			continue
		var line := "%s '%s'" % [c.name, s]
		if not out.has(line):
			out.append(line)


func _shown(c: Node) -> String:
	return c.atr(str(c.get("text")))


func _find(n: Node, test: Callable) -> Node:
	for c in n.find_children("*", "", true, false):
		if test.call(c):
			return c
	return null


## msgid -> ["file:line", ...] of messages.pot.
func _pot_refs() -> Dictionary:
	var out := {}
	var refs: Array = []
	var entries := I18n.pot_entries()
	var i := 0
	for raw in FileAccess.get_file_as_string(I18n.POT).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#: "):
			refs.append_array(line.substr(3).split(" ", false))
		elif line.begins_with("msgid ") and line != "msgid \"\"" or line == "msgid \"\"" and not refs.is_empty():
			if i < entries.size():
				out[entries[i][0]] = refs
			i += 1
			refs = []
	return out


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
