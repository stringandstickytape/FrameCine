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
const FilesTab := preload("res://ui/files_tab.gd")
const LibraryView := preload("res://ui/library_view.gd")
const LibraryIndex := preload("res://scripts/library/library_index.gd")
const VideoMode := preload("res://scripts/video_mode.gd")
const PO := "res://locale/zh_CN.po"
## The stage-1 files (docs/i18n.md): their keys are all in zh_CN.po.
const SHARED := ["ui/pane_ui.gd", "ui/pane_widgets.gd", "ui/tablet.gd", "ui/system_tab.gd", "ui/ui_layer.gd",
		"ui/help_texts.gd", "ui/hand_hint.gd", "ui/world_toast.gd", "ui/hw_video_row.gd", "ui/assistant_row.gd",
		"scripts/main.gd", "scripts/play/end_time.gd", "scripts/play/film_layer.gd", "scripts/play/real_windows.gd",
		"scripts/play/hw_video.gd", "scripts/xr/controller_look.gd", "scripts/assistant/assistant_switches.gd",
		"ui/themes/tablet.json"]
## Stage 2, set B: the Picture, Sound and Subtitles tabs and the texts they show.
const SET_B := ["ui/picture_tab.gd", "ui/sound_tab.gd", "ui/subtitles_tab.gd", "ui/mode_diagram.gd",
		"scripts/video_mode.gd", "scripts/play/container_mode.gd", "scripts/play/hdr_tone_map.gd",
		"scripts/play/frame_step_loop.gd", "scripts/play/auto_crop.gd", "scripts/play/dual_fisheye.gd",
		"scripts/comfort/screen_angle.gd", "scripts/play/spatial_audio.gd"]
const ContainerMode := preload("res://scripts/play/container_mode.gd")
const SoundTab := preload("res://ui/sound_tab.gd")
## Stage 2, set C: the Room, Objects and Mixed reality tabs, and what they show from elsewhere.
const SET_C := ["ui/room_tab.gd", "ui/objects_tab.gd", "ui/object_section.gd", "ui/object_placer.gd",
		"ui/mixed_reality_tab.gd", "ui/agent_pane.gd", "scripts/comfort/sleep_timer.gd",
		"scripts/assistant/assistant_service.gd", "scripts/assistant/object_builtins.gd",
		"environments/showrooms/index.json"]
const EnvLibrary := preload("res://scripts/env/env_library.gd")
const Showrooms := preload("res://scripts/env/showrooms.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")

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
	await _set_b()
	await _set_c()
	await _source_tab()
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


## Stage 2, set A: the Source tab. Its headings, rows and counts follow the language, live; names (an agent, a drive, a
## folder the viewer added, the rows' file names) are content; the test patterns, the calibration cards, the chips,
## the Library's words and the forms translate; in the pseudo-locale no plain English is left in its lists.
func _source_tab() -> void:
	var layer: Node = main.ui
	var pui: Node = layer.ui
	var files: Node = pui.files
	layer.show_panel()
	pui.show_tab(pui.Tab.FILES)
	files.open_folder(FilesTab.PATTERNS_FOLDER)
	await _frames(2)
	var heading: Label = files.get("_path_label")
	_check("English: the patterns' heading and names", heading.text == "Test patterns (generated, no decoder)"
			and files.row_texts().has("Flat 2D"))
	I18n.set_language("zh_CN")
	await _frames(2)
	_check("Chinese: the heading is built again (%s)" % heading.text, heading.text == "测试图案（程序生成，不用解码器）")
	_check("the patterns' names in Chinese (%s)" % ", ".join(files.row_texts().slice(0, 2)),
			files.row_texts().has("平面 2D") and files.row_texts().has("双鱼眼 360°（前后镜头）"))
	var row: Button = files.row_button("平面 2D")
	_check("a row is a content control: a file called Room stays Room", row != null
			and bool(row.get_meta("content", false)) and not row.can_auto_translate())
	_check("the footer's count in Chinese (%s)" % files.count_text(), files.count_text().ends_with("个项目"))
	var by_path := {}
	for b in (files.get("_places_box") as Node).get_children():
		if b is Button and b.has_meta("path"):
			by_path[str(b.get_meta("path"))] = b
	_check("the app's places in Chinese (%s, %s)" % [_shown(by_path.get("network://", heading)),
			_shown(by_path.get(LibraryIndex.root(), heading))], _shown(by_path.get("network://", heading)) == "网络"
			and _shown(by_path.get(LibraryIndex.root(), heading)) == "片库"
			and _shown(by_path.get("search://", heading)) == "搜索")
	var agent: Button = by_path.get("agent://claude")
	_check("an agent's place keeps its name", agent != null and _shown(agent) == agent.text
			and bool(agent.get_meta("content", false)))
	_check("a drive or a folder the viewer added is named by itself", not FilesTab.is_named_place("/run/media/Room")
			and not FilesTab.is_named_place("smb://nas/films") and FilesTab.is_named_place(FilesTab.BROWSER_FOLDER))
	var list_view: Button = pui._view_buttons[1]
	_check("the view buttons' tooltips (%s)" % list_view.atr(list_view.tooltip_text),
			list_view.atr(list_view.tooltip_text) == "列表")
	_check("the chips in Chinese (%s)" % FilesTab.chip_text(VideoMode.guess("Trip_180_SBS.mp4")),
			FilesTab.chip_text(VideoMode.guess("Trip_180_SBS.mp4")) == "180 左右")
	_check("the Library's own season names translate, an NFO's stay",
			LibraryView.season_name("Season 2", 2) == "第 2 季" and LibraryView.season_name("Specials", 0) == "特别篇"
			and LibraryView.season_name("The Early Years", 3) == "The Early Years")
	var card: Dictionary = TestLab.cards()[0]
	# The System tab's cards (its section in the tree only while it shows).
	pui.show_tab(pui.Tab.SYSTEM)
	pui.show_section("Test and setup")
	await _frames(1)
	var card_button := _find(pui.system, func(c: Node) -> bool: return c is Button and c.text == str(card["label"]))
	_check("a calibration card's name is a key (%s)" % (_shown(card_button) if card_button != null else "none"),
			card_button != null and _shown(card_button) == "每眼对齐")
	pui.show_tab(pui.Tab.FILES)
	await _frames(1)
	var form: Node = files.get_form()
	var password := _find(form, func(c: Node) -> bool: return c is Label and c.text == "Password")
	var share: LineEdit = form.get_field("share")
	_check("the host form's labels and hints (%s, %s)" % [_shown(password) if password != null else "none",
			share.atr(share.placeholder_text)], password != null and _shown(password) == "密码"
			and share.atr(share.placeholder_text) == "可选")
	var search_title := _find(files.get_search_form(), func(c: Node) -> bool: return c is Label)
	_check("the search form's line (%s)" % _shown(search_title), _shown(search_title).begins_with("搜索收藏"))
	files.open_folder(FilesTab.SEARCH_FOLDER)
	await _frames(1)
	_check("built rows: Search: %s (%s)" % ["type a name...", files.row_texts()[0]],
			files.row_texts()[0] == "搜索：输入名称……" and heading.text == "搜索")
	files.open_folder(FilesTab.QUEUE_FOLDER)
	await _frames(1)
	var repeat: Button = files.get("_repeat")
	_check("the Repeat button (%s)" % _shown(repeat), _shown(repeat).begins_with("重复："))
	I18n.set_language("en")
	await _frames(1)
	_check("back to English: the queue's heading and Repeat", heading.text.begins_with("Queue")
			and _shown(repeat).begins_with("Repeat: "))
	# The pseudo-locale: nothing plain in the lists that hold no names (the patterns, Search), nor in their bar.
	I18n.set_language(I18n.PSEUDO)
	await _frames(1)
	var plain: Array[String] = []
	# The places named by a drive or an agent stay as they are (built again on the switch, so looked up now).
	var named_places: Array = (files.get("_places_box") as Node).get_children().filter(func(b: Node) -> bool:
		return b is Button and bool(b.get_meta("content", false)))
	for place: String in [FilesTab.PATTERNS_FOLDER, FilesTab.SEARCH_FOLDER]:
		files.open_folder(place)
		await _frames(1)
		_plain_under(files, named_places, plain)
	_check("pseudo: no plain English in the Source tab (%s)" % " | ".join(plain), plain.is_empty())
	I18n.set_language("en")
	files.open_folder(FilesTab.PATTERNS_FOLDER)
	await _frames(1)
	_check("English again: Flat 2D", files.row_texts().has("Flat 2D") and heading.text.begins_with("Test patterns"))


## Stage 2, set B: the Picture, Sound and Subtitles tabs. Their keys are in zh_CN.po; the mode line, the container's
## reason and the tabs' built lines in Chinese, the English for the dev link unchanged; content stays; the pseudo-locale
## leaves no plain English in any of their sections or the footer, and no card is wider than its tab.
func _set_b() -> void:
	var pot := _pot_refs()
	var po_keys := {}
	for e: Array in I18n.pot_entries(PO):
		po_keys[e[0]] = true
	var missing: Array = []
	for k: String in pot:
		if (pot[k] as Array).any(func(ref: String) -> bool: return ref.get_slice(":", 0) in SET_B) and not po_keys.has(k):
			missing.append(k)
	_check("set B: every key is in zh_CN.po (%s)" % ", ".join(missing), missing.is_empty())
	_check("set B: the pot has its keys", pot.has("%s, side by side") and pot.has("Large format") and pot.has("SDH")
			and pot.has("%d line with \"%s\"") and pot.has("Brightness") and pot.has("Dummy head A"))
	_check("set B: no id is a key", not pot.has("visual_impaired") and not pot.has("hearing_impaired")
			and not pot.has("large_format") and not pot.has("camera360"))

	var m := VideoMode.make(VideoMode.Proj.FLAT, VideoMode.Layout.SBS, true, true)
	var fish := VideoMode.make(VideoMode.Proj.FISHEYE, VideoMode.Layout.TB, false, false, 200.0)
	var info := {"projection": "equirectangular", "stereo_mode": "tb"}
	_check("the mode in English (%s)" % m.describe(true), m.describe(true) == m.describe()
			and m.describe() == "Flat, side by side (half), eyes swapped")
	_check("the container's reason in English", ContainerMode.from_info(info, "a.mkv", 4096, 4096)["local"]
			== "container: 360°, top / bottom")
	var pui: Node = main.ui.ui
	var layer: Node = main.ui
	layer.show_panel()
	I18n.set_language("zh_CN")
	pui.show_tab(pui.Tab.PICTURE)
	await _frames(3)
	_check("the mode in Chinese (%s)" % m.describe(true), m.describe(true) == "平面，左右并排（半幅），左右眼互换")
	_check("a fisheye in Chinese (%s)" % fish.describe(true), fish.describe(true) == "鱼眼 200°，上下排列")
	_check("the dev link's mode stays English (%s)" % m.describe(),
			m.describe() == "Flat, side by side (half), eyes swapped")
	var cm := ContainerMode.from_info(info, "a.mkv", 4096, 4096)
	_check("the container's reason in Chinese (%s), English kept (%s)" % [cm["local"], cm["reason"]],
			cm["local"] == "容器：360°, 上下排列" and cm["reason"] == "container: 360°, top / bottom")
	var footer: String = pui._footer_text.text
	_check("the footer's mode line in Chinese (%s)" % footer, footer != "" and _cjk(footer)
			and not RegEx.create_from_string("Flat|mono|choice|Auto").search(footer))
	var diagram: Button = pui.picture._layout_buttons[1]
	_check("a mode diagram's word in Chinese (%s), the button wide enough" % _shown(diagram.word),
			_shown(diagram.word) == "左右" and diagram.custom_minimum_size.x >= diagram.word.get_combined_minimum_size().x)
	# The presets' card may be out of the tree (one section shows at a time): the row itself.
	var presets: Array = (pui.picture._presets as Node).get_children().map(func(b: Node) -> String: return _shown(b))
	_check("the size presets in Chinese (%s)" % [presets], presets == ["巨幕", "客厅", "床上"])
	_check("the sound tab's status in Chinese (%s)" % pui.sound._speakers_status.text,
			_cjk(pui.sound._speakers_status.text))
	_check("the PC's address in Chinese (%s)" % pui.sound._pc_address.text,
			str(pui.sound._pc_address.text).begins_with("电脑："))
	_check("a track flag in Chinese", tr("SDH") == "听障" and SoundTab.track_flags({"hearing_impaired": true}) == ["SDH"])
	_check("the subtitle files line in Chinese (%s)" % pui.subtitles._files_label.text,
			_cjk(pui.subtitles._files_label.text))
	# A line of the subtitles that is also a key stays as it is; the heading is built in Chinese.
	pui.subtitles._show_lines([{"start": 62.0, "text": "Room", "i": 0}],
			tr_n("%d line with \"%s\"", "%d lines with \"%s\"", 1) % [1, "Room"])
	var row: Button = pui.subtitles._script_rows.get_child(0)
	_check("a subtitle line is content (%s)" % _shown(row), _shown(row).ends_with("Room") and row.has_meta("content"))
	_check("the find heading in Chinese, the words as typed (%s)" % _shown(pui.subtitles._script_label),
			_shown(pui.subtitles._script_label) == "1 行含有“Room”")
	pui.subtitles._clear_script()
	for tab: int in [pui.Tab.PICTURE, pui.Tab.SOUND, pui.Tab.SUBTITLES]:
		pui.show_tab(tab)
		await _frames(2)
		_check("zh_CN: no card of %s wider than the tab" % pui.tabs[tab].name, _cards_fit(pui, tab))

	I18n.set_language(I18n.PSEUDO)
	await _frames(2)
	var plain: Array[String] = []
	for tab: int in [pui.Tab.PICTURE, pui.Tab.SOUND, pui.Tab.SUBTITLES]:
		pui.show_tab(tab)
		await _frames(2)
		var box: VBoxContainer = pui.tabs[tab].get("box")
		var sections: Array[String] = W.shown_sections(box)
		var wide: Array[String] = []
		for s in sections:
			pui.show_section(s)
			await _frames(1)
			_plain_under(pui.tabs[tab], [], plain)
			if not _cards_fit(pui, tab):
				wide.append(s)
		_check("pseudo: %s has its sections (%d), each fits the tab (%s)" % [pui.tabs[tab].name, sections.size(),
				", ".join(wide)], sections.size() >= 3 and wide.is_empty())
	pui.show_tab(pui.Tab.PICTURE)
	await _frames(2)
	_plain_under(pui._footer_text, [], plain)
	if not str(pui._footer_text.text).begins_with("["):
		plain.append("footer '%s'" % pui._footer_text.text)
	_check("pseudo: no plain English in Picture, Sound, Subtitles or the footer (%s)" % " | ".join(plain), plain.is_empty())
	I18n.set_language("en")
	await _frames(2)
	_check("English again: the footer's mode line (%s)" % pui._footer_text.text,
			not _cjk(pui._footer_text.text) and not str(pui._footer_text.text).begins_with("["))
	pui.show_tab(pui.Tab.FILES)
	await _frames(1)


## No card of the tab is wider than the tab.
func _cards_fit(pui: Node, tab: int) -> bool:
	var width: float = (pui.tabs[tab] as Control).size.x
	return pui.cards(tab).all(func(c: Control) -> bool:
			return c.get_parent() == null or not c.is_visible_in_tree() or c.get_combined_minimum_size().x <= width + 0.5)


func _cjk(s: String) -> bool:
	return RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]").search(s) != null


## Stage 2, set C: the Room, Objects and Mixed reality tabs. Their keys are all in zh_CN.po, the names of what ships
## (rooms, showrooms, objects) are keys; their built lines switch to Chinese and back, while what an assistant reads
## stays English; content stays; the pseudo-locale leaves no plain English on any of their sections; every card fits.
func _set_c() -> void:
	var pot := _pot_refs()
	var po_keys := {}
	for e: Array in I18n.pot_entries(PO):
		po_keys[e[0]] = true
	var missing: Array = []
	for k: String in pot:
		if (pot[k] as Array).any(func(ref: String) -> bool: return ref.get_slice(":", 0) in SET_C) and not po_keys.has(k):
			missing.append(k)
	_check("set C: every key of its files is in zh_CN.po (%s)" % ", ".join(missing), missing.is_empty())
	var shipped: Array = []
	for e: Array in main.ENVIRONMENTS + EnvLibrary.BUILT_IN + Showrooms.environments():
		shipped.append(str(e[1]))
	for e: Dictionary in ObjectBuiltins.ENTRIES:
		shipped.append(str(e["name"]))
	var no_key: Array = shipped.filter(func(n: String) -> bool: return not po_keys.has(n))
	_check("set C: each room, showroom and built-in object that ships has its name as a key (%d; %s)" % [shipped.size(),
			", ".join(no_key)], shipped.size() > 15 and no_key.is_empty())

	var layer: Node = main.ui
	var pui: Node = layer.ui
	var room: Node = pui.room
	var section: Node = pui.objects.section
	var mr: Node = pui.mixed_reality
	var sleep: Node = main.features.sleep
	main.set_environment("cinema")
	layer.show_panel()
	pui.show_tab(pui.Tab.OBJECTS)
	section.sync_objects()
	for i in 600:
		await process_frame
		if not section._ids.is_empty() and not section._loading:
			break
	pui.show_tab(pui.Tab.ROOM)
	await _frames(2)
	sleep.start(15.0)
	I18n.set_language("zh_CN")
	await _frames(2)
	var cinema: Button = room._env_rows[room._env_ids.find("cinema")]
	_check("Chinese: a room that ships by its name (%s)" % _shown(cinema), _shown(cinema) == "影院")
	var showroom: int = room._env_ids.find("showroom:objects")
	_check("a showroom too (%s)" % (_shown(room._env_rows[showroom]) if showroom >= 0 else "none"),
			showroom >= 0 and _shown(room._env_rows[showroom]) == "物品")
	_check("the seat line (%s)" % room._seat_label.text, str(room._seat_label.text).contains("座位")
			or str(room._seat_label.text).contains("房间默认位置"))
	_check("the party's line (%s)" % room._party_status.text, str(room._party_status.text).begins_with("“主持”"))
	_check("the party's name and PIN (%s, %s)" % [room._party_name.text, room._party_pin.text],
			str(room._party_name.text).begins_with("名字：") and str(room._party_pin.text).begins_with("PIN："))
	_check("the sleep timer's line (%s), an assistant's English (%s)" % [room._sleep_status.text, sleep.status_text()],
			room._sleep_status.text == "15 分钟后睡眠" and sleep.status_text() == "sleep in 15 min")
	_check("why a party ended (%s; %s)" % [room.end_reason("left"), room.end_reason("the host refused: wrong PIN")],
			room.end_reason("left") == "你离开了" and room.end_reason("the host refused: wrong PIN") == "主持方拒绝了：wrong PIN")
	_check("a numbered seat translates, a named one is content (%s, %s)" % [room.seat_name(["Seat 1", "Seat"], 0),
			room.seat_name(["Seat 1", "Seat"], 1)], room.seat_name(["Seat 1", "Seat"], 0) == "座位 1"
			and room.seat_name(["Seat 1", "Seat"], 1) == "Seat")
	var slider: Label = room._intermission_minutes.get_meta("value_label")
	_check("a slider's value in Chinese (%s)" % slider.text, slider.text.ends_with("分钟"))
	section._selected = "pot_plant"
	section._sync_chosen()
	_check("Objects: a built-in's line (%s)" % section._chosen.text, section._chosen.text == "盆栽  ·  地面  ·  %d 个部件"
			% (_parts_of("pot_plant")))
	section._selected = ""
	section._sync_chosen()
	_check("Objects: the pick line (%s)" % section._chosen.text, section._chosen.text == "选择一个物品，然后放置。")
	var tile: Button = section._tiles.get("pot_plant")
	var title: Label = tile.find_children("*", "Label", true, false)[0] if tile != null else null
	_check("Objects: a built-in tile's name (%s)" % (_shown(title) if title != null else "none"),
			title != null and _shown(title) == "盆栽")
	var area: String = mr._row_text({"name": "Room", "size": [1.0, 0.5, 0.2]})
	_check("Mixed reality: an area's name stays, its size in Chinese (%s)" % area, area == "Room  ·  100 x 50 x 20 厘米")
	sleep.cancel()
	I18n.set_language("en")
	await _frames(2)
	_check("English again: the room's row and the party's line (%s; %s)" % [_shown(cinema), room._party_status.text],
			_shown(cinema) == "Cinema" and str(room._party_status.text).begins_with("Host plays"))
	_check("English: the seat line (%s)" % room._seat_label.text, str(room._seat_label.text).begins_with("The room's own")
			or str(room._seat_label.text).begins_with("Seat "))

	# The pseudo-locale on every section of the three tabs; content (names) is skipped.
	I18n.set_language(I18n.PSEUDO)
	var plain: Array[String] = []
	var wide: Array[String] = []
	for tab: int in [pui.Tab.ROOM, pui.Tab.OBJECTS, pui.Tab.MIXED_REALITY]:
		pui.show_tab(tab)
		await _frames(2)
		var sections: Array[String] = W.shown_sections(pui.tabs[tab].box)
		for s in sections:
			pui.show_section(s)
			await _frames(2)
			_plain_content_skipped(pui.tabs[tab], plain)
	_check("pseudo: no plain English on the Room, Objects and Mixed reality tabs (%s)" % " | ".join(plain), plain.is_empty())
	# Every card fits its tab in Chinese and in the pseudo-locale (the longest), or is no wider than in English (the
	# Objects tab's grid of four thumbnails is wider than the tab in English too).
	var english := {}
	for code: String in ["en", "zh_CN", I18n.PSEUDO]:
		I18n.set_language(code)
		for tab: int in [pui.Tab.ROOM, pui.Tab.OBJECTS, pui.Tab.MIXED_REALITY]:
			pui.show_tab(tab)
			await _frames(2)
			var width: float = pui.tabs[tab].size.x
			for s in W.shown_sections(pui.tabs[tab].box):
				pui.show_section(s)
				await _frames(2)
				for c: Control in pui.cards(tab):
					if c.get_parent() == null or not c.is_visible_in_tree():
						continue
					var key := "%d %s" % [tab, W.card_section(c)]
					var w := c.get_combined_minimum_size().x
					if code == "en":
						english[key] = w
					elif w > maxf(width, float(english.get(key, 0.0))) + 0.5:
						wide.append("%s %s %.0f of %.0f (English %.0f)" % [code, W.card_section(c), w, width,
								float(english.get(key, 0.0))])
	_check("every card of the three tabs fits, in Chinese and pseudo (%s)" % " | ".join(wide), wide.is_empty())
	I18n.set_language("en")
	pui.show_tab(pui.Tab.FILES)
	await _frames(1)


func _parts_of(id: String) -> int:
	return ((load("res://scripts/assistant/object_library.gd") as GDScript).call("get_object", id).get("parts", [])
			as Array).size()


## As _plain_under(), but a control marked content (or inside one) is left out: names, and lines the code built.
func _plain_content_skipped(n: Node, out: Array[String]) -> void:
	for c in n.find_children("*", "", true, false):
		if not (c is Label or c is Button) or not (c as CanvasItem).is_visible_in_tree():
			continue
		var p: Node = c
		var marked := false
		while p != null and p != n:
			if p.has_meta("content"):
				marked = true
				break
			p = p.get_parent()
		var s := _shown(c)
		if marked and s.contains("["):
			continue
		if not RegEx.create_from_string("[A-Za-z]{2,}").search(s) or s.begins_with("["):
			continue
		# A content line the code built from parts holds a pseudo part; one that is only a name has none.
		if marked and not _is_built(c):
			continue
		var line := "%s '%s'" % [c.name, s]
		if not out.has(line):
			out.append(line)


## A control that shows a line the code built (its text should hold a translated part), not a bare name.
func _is_built(c: Node) -> bool:
	var room: Node = main.ui.ui.room
	var section: Node = main.ui.ui.objects.section
	return c in [room._seat_label, room._party_status, room._sleep_status, room._party_name, room._party_pin,
			room._react_note, room._curtains_note, room._intermission_note, section._chosen, section._yours_chosen]


## The visible Labels and Buttons under `n` (not under `skip`) whose text is plain English in the pseudo-locale.
func _plain_under(n: Node, skip: Array, out: Array[String]) -> void:
	for c in n.find_children("*", "", true, false):
		if not (c is Label or c is Button) or not (c as CanvasItem).is_visible_in_tree():
			continue
		if skip.any(func(s: Node) -> bool: return s == c or s.is_ancestor_of(c)):
			continue
		var s := _shown(c)
		if not RegEx.create_from_string("[A-Za-z]{2,}").search(s) or s.begins_with("["):
			continue
		# Content left as it is on purpose: the player's name, the languages' own names, an assistant service's own
		# status line. (The lab's card names are keys since stage 2.)
		if s.begins_with("VR Video Player") or s == "English":
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
