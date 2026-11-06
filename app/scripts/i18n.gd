extends RefCounted

## The menus' languages (docs/i18n.md). Godot's TranslationServer does the work: one gettext file per language in
## res://locale (zh_CN.po), keyed by the English text. setup() loads them, adds the Simplified Chinese font behind the
## menu's fonts, and applies [language] ui from the settings (default English; the OS locale is not used: the headset
## starts the app with LC_ALL=C). set_language() switches at once: every control that shows a fixed English text
## translates it itself (Godot's auto-translate), and changed() tells the code that builds texts to build them again.
##
## The rules for menu code, in short (docs/i18n.md has the rest):
##   fixed words    give the control the English: W.label("Room"), b.text = "Play". It translates them, live.
##   built text     tr() / tr_n() on the whole sentence: tr("Delete %s from the library?") % name. Build it again on
##                  changed() (PaneUI calls each tab's sync()).
##   content        file and film names, host names, what the viewer typed: on a control made with W.content(), never
##                  through tr().
##
## The pseudo-locale (PSEUDO, dev mode or --pseudo-locale only, never saved) is made here from the English of
## messages.pot: accented, about a third longer, in brackets. Text it leaves plain English is text the extraction
## (tools/i18n.py) does not know.

const LOCALE_DIR := "res://locale"
const POT := "res://locale/messages.pot"
const PSEUDO := "pseudo"
## [code, the name in its own language]. A language is a .po file in LOCALE_DIR and a line here.
const LANGUAGES := [["en", "English"], ["zh_CN", "简体中文"]]
const PSEUDO_NAME := "[Ƥšéûðö] (dev)"
## Settings: [language] ui, null for English.
const SECTION := "language"
const KEY := "ui"

## The Simplified Chinese font (SIL OFL 1.1, ui/fonts/LICENSE.NotoSansSC.txt; tools/i18n.py font makes it), behind
## the menu's own fonts: Fira has no CJK glyphs. The FontFiles of ui/fonts that get it as their fallback.
const CJK_FONT := "res://ui/fonts/NotoSansSC-Medium-subset.woff2"
const MENU_FONTS: Array[String] = ["res://ui/fonts/fira_sans_condensed_light.res",
		"res://ui/fonts/fira_sans_condensed_regular.res", "res://ui/fonts/fira_sans_condensed_medium.res",
		"res://ui/fonts/fira_sans_condensed_semibold.res"]

## The language on show (a LANGUAGES code or PSEUDO).
static var language := "en"
static var _translations := {}
static var _pseudo: Translation
static var _cjk: FontFile
## The menu fonts with the fallback set: held, so the resource cache keeps these very objects.
static var _menu_fonts: Array[FontFile] = []
static var _holder: Holder
## --pseudo-locale on the command line, or dev mode: the System tab offers PSEUDO.
static var pseudo_allowed := false


class Holder:
	extends RefCounted
	## The language changed: build texts again.
	signal changed(code: String)


static func holder() -> Holder:
	if _holder == null:
		_holder = Holder.new()
	return _holder


## Loads the languages and the fonts, and applies the saved language (`pseudo`: --pseudo-locale, for this run only).
static func setup(settings: RefCounted, pseudo := false) -> void:
	load_translations()
	add_font_fallbacks()
	pseudo_allowed = pseudo_allowed or pseudo
	var code := str(settings.get_value(SECTION, KEY, "en")) if settings != null else "en"
	set_language(PSEUDO if pseudo else code)


## The .po files of LOCALE_DIR, once. Fuzzy entries are skipped by Godot's loader.
static func load_translations() -> void:
	if not _translations.is_empty():
		return
	for entry: Array in LANGUAGES:
		var code: String = entry[0]
		var path := LOCALE_DIR.path_join(code + ".po")
		if code == "en" or not ResourceLoader.exists(path):
			continue
		var t := load(path) as Translation
		if t == null:
			push_error("i18n: %s did not load" % path)
			continue
		t.locale = code
		_translations[code] = t
		TranslationServer.add_translation(t)


## The language codes to offer, with their own names: [[code, name], ...].
static func languages() -> Array:
	var out: Array = []
	for entry: Array in LANGUAGES:
		if entry[0] == "en" or _translations.has(entry[0]):
			out.append(entry)
	if pseudo_allowed or _dev_mode():
		out.append([PSEUDO, PSEUDO_NAME])
	return out


## Switches the menus to a language (a LANGUAGES code or PSEUDO; anything else is English) and tells changed().
static func set_language(code: String) -> void:
	load_translations()
	if code != PSEUDO and code != "en" and not _translations.has(code):
		code = "en"
	if _pseudo != null and code != PSEUDO:
		TranslationServer.remove_translation(_pseudo)
	if code == PSEUDO:
		# English underneath: the pseudo translation is the only one for "en", and only while it is chosen.
		TranslationServer.add_translation(pseudo_translation())
	var changed := code != language
	language = code
	var locale := "en" if code == PSEUDO else code
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)
	else:
		# Same locale (English to pseudo and back): the controls are told by hand.
		var loop := Engine.get_main_loop()
		if loop != null:
			loop.notification(MainLoop.NOTIFICATION_TRANSLATION_CHANGED)
	if changed:
		holder().changed.emit(code)


## Saves the choice ([language] ui; PSEUDO is never saved) and switches.
static func choose(settings: RefCounted, code: String) -> void:
	if code != PSEUDO and settings != null:
		settings.set_value(SECTION, KEY, code if code != "en" else null)
	set_language(code)


## Dev mode is on (scripts/dev/dev_host.gd made its node).
static func _dev_mode() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.get_node_or_null("DevHost") != null


# --- Pseudo-locale ----------------------------------------------------------------------------------------------

const _ACCENTS := {"A": "Å", "C": "Ç", "D": "Ð", "E": "É", "G": "Ĝ", "H": "Ĥ", "I": "Î", "J": "Ĵ", "K": "Ķ", "L": "Ļ",
		"N": "Ñ", "O": "Ö", "R": "Ŕ", "S": "Š", "T": "Ţ", "U": "Û", "W": "Ŵ", "Y": "Ý", "Z": "Ž", "a": "å", "c": "ç",
		"d": "ð", "e": "é", "g": "ĝ", "h": "ĥ", "i": "î", "j": "ĵ", "k": "ķ", "l": "ļ", "n": "ñ", "o": "ö", "p": "þ",
		"r": "ŕ", "s": "š", "t": "ţ", "u": "û", "w": "ŵ", "y": "ý", "z": "ž"}
## Share of the length added (translations run longer than English).
const PSEUDO_GROWTH := 0.35
static var _placeholder: RegEx


## "[Šéţţîñĝš ~~~]" for "Settings": letters accented, placeholders (%s, %d, %.1f, %%) and line breaks kept.
static func pseudo_text(s: String) -> String:
	if s == "":
		return s
	if _placeholder == null:
		_placeholder = RegEx.create_from_string("%[-+0 #]*[0-9]*(?:\\.[0-9]+)?[a-zA-Z%]|\\n")
	var out := ""
	var at := 0
	for m in _placeholder.search_all(s):
		out += _accented(s.substr(at, m.get_start() - at)) + m.get_string()
		at = m.get_end()
	out += _accented(s.substr(at))
	return "[" + out + " " + "~".repeat(maxi(1, ceili(s.length() * PSEUDO_GROWTH) - 2)) + "]"


static func _accented(s: String) -> String:
	var out := ""
	for c in s:
		out += str(_ACCENTS.get(c, c))
	return out


## The pseudo translation of every key of messages.pot (made once).
static func pseudo_translation() -> Translation:
	if _pseudo != null:
		return _pseudo
	_pseudo = Translation.new()
	_pseudo.locale = "en"
	_pseudo.set_plural_rules_override("nplurals=2; plural=(n != 1);")
	for entry: Array in pot_entries():
		if entry[1] == "":
			_pseudo.add_message(entry[0], pseudo_text(entry[0]))
		else:
			_pseudo.add_plural_message(entry[0], PackedStringArray([pseudo_text(entry[0]), pseudo_text(entry[1])]))
	return _pseudo


## [[msgid, msgid_plural or ""], ...] of a gettext template (the header entry left out).
static func pot_entries(path := POT) -> Array:
	var out: Array = []
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return out
	var id := ""
	var plural := ""
	var field := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid_plural "):
			field = "plural"
			plural = _unquote(line.substr(13))
		elif line.begins_with("msgid "):
			if id != "":
				out.append([id, plural])
			field = "id"
			id = _unquote(line.substr(6))
			plural = ""
		elif line.begins_with("msgstr"):
			field = ""
		elif line.begins_with("\"") and field == "id":
			id += _unquote(line)
		elif line.begins_with("\"") and field == "plural":
			plural += _unquote(line)
	if id != "":
		out.append([id, plural])
	return out


static func _unquote(s: String) -> String:
	s = s.strip_edges()
	if s.length() < 2:
		return ""
	return s.substr(1, s.length() - 2).c_unescape()


# --- Fonts ------------------------------------------------------------------------------------------------------

## The Simplified Chinese font, as the menu draws it (the same settings as Fira's FontFiles).
static func cjk_font() -> FontFile:
	if _cjk == null:
		_cjk = FontFile.new()
		if not FileAccess.file_exists(CJK_FONT) or _cjk.load_dynamic_font(CJK_FONT) != OK:
			push_error("i18n: %s did not load; Chinese shows only where the system has a font" % CJK_FONT)
		_cjk.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_cjk.hinting = TextServer.HINTING_LIGHT
		_cjk.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_cjk.generate_mipmaps = true
	return _cjk


## Puts the CJK font behind each menu font (MENU_FONTS), once. Every FontVariation of the theme and the tablet's
## Label3Ds (ui/pane_style.gd font()) reads its base font's fallbacks, so this one place covers them all.
static func add_font_fallbacks() -> void:
	if not _menu_fonts.is_empty():
		return
	var cjk := cjk_font()
	for path in MENU_FONTS:
		var f := load(path) as FontFile
		if f == null:
			continue
		if not f.fallbacks.has(cjk):
			var fb := f.fallbacks.duplicate()
			fb.append(cjk)
			f.fallbacks = fb
		_menu_fonts.append(f)
