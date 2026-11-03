extends Node

## Language memory (ideas #28): remembers the audio and subtitle languages the user chose, so multi-language releases
## open right. On open, the audio track in a remembered language is selected when the file's default is another
## one, and subtitles (when on) pick a remembered subtitle language (through Subtitles.pick_override). With subtitles
## off, a forced track in the audio's language is shown (the foreign-language parts of a film), unless turned off.
##
##   audio_languages, subtitle_languages   the last MAX_REMEMBERED choices, most recent first, normalised codes
##   audio_language, subtitle_language     the first of each ("" = no preference)
##   forced_auto                            forced tracks with subtitles off ([subtitles] forced_auto, default on)
##   normalize(code)                        "ger" / "deu" / "German" / "de" -> "de"; regions kept ("pt-br")
##   same_language(preference, track)       a preference without a region matches every region
##   pick_audio(tracks) / pick_subtitle(tracks, forced_only) -> index or -1
##   forget(), set_forced_auto(on)
## The picks use the engine's MediaSource.pick_audio_track / pick_subtitle_track and normalize_language when the
## source has them (commentary and audio description lose ties; text before bitmap, full before forced, without
## hearing-impaired notes first), and the same rules in GDScript otherwise (test patterns, older engines).
## A choice is remembered when the user picks a track (PlaybackController.select_audio_track; the subtitles'
## track_changed with by_user); picks made by features are not. A track without a language changes nothing.
## Settings: [language] audio, subtitles (the lists), [subtitles] forced_auto.

signal changed(audio: String, subtitles: String)

const MAX_REMEMBERED := 3
## 639-1 code first, then the 639-2 forms and names that mean the same, for when the engine can't normalise.
const SAME := [
	["en", "eng", "english"], ["fr", "fre", "fra", "french"], ["de", "ger", "deu", "german"], ["es", "spa", "spanish"],
	["it", "ita", "italian"], ["ja", "jpn", "japanese"], ["zh", "chi", "zho", "cmn", "chinese"], ["ko", "kor", "korean"],
	["ru", "rus", "russian"], ["pt", "por", "portuguese"], ["nl", "dut", "nld", "dutch"], ["sv", "swe", "swedish"],
	["no", "nor", "nob", "nno", "nb", "nn", "norwegian"], ["da", "dan", "danish"], ["fi", "fin", "finnish"],
	["pl", "pol", "polish"], ["cs", "cze", "ces", "czech"], ["el", "gre", "ell", "greek"], ["tr", "tur", "turkish"],
	["ar", "ara", "arabic"], ["he", "heb", "hebrew"], ["hi", "hin", "hindi"], ["hu", "hun", "hungarian"],
	["ro", "rum", "ron", "romanian"], ["uk", "ukr", "ukrainian"], ["th", "tha", "thai"], ["vi", "vie", "vietnamese"],
	["id", "ind", "indonesian"],
]

var main: Node3D
var audio_languages := PackedStringArray()
var subtitle_languages := PackedStringArray()
var forced_auto := true
var audio_language: String:
	get:
		return audio_languages[0] if not audio_languages.is_empty() else ""
var subtitle_language: String:
	get:
		return subtitle_languages[0] if not subtitle_languages.is_empty() else ""
var _own := false


func _ready() -> void:
	audio_languages = _load_list("audio")
	subtitle_languages = _load_list("subtitles")
	forced_auto = bool(main.settings.get_value("subtitles", "forced_auto", true))
	main.features.subtitles.pick_override = func(tracks: Array) -> int: return pick_subtitle(tracks)
	main.player.audio_track_selected.connect(_on_audio_selected)
	main.features.subtitles.track_changed.connect(_on_subtitle_changed)
	main.file_opened.connect(_on_file_opened)


## Older settings hold one code as a String; now a list.
func _load_list(key: String) -> PackedStringArray:
	var v: Variant = main.settings.get_value("language", key, PackedStringArray())
	var out := PackedStringArray()
	if v is String:
		if v != "":
			out.append(normalize(v))
	elif v is PackedStringArray or v is Array:
		for c: Variant in v:
			if str(c) != "":
				out.append(normalize(str(c)))
	return out


func _on_file_opened(path: String) -> void:
	var src: Object = main.player.source
	if src == null or path == "":
		return
	var tracks: Array[Dictionary] = src.get_audio_tracks()
	var want := pick_audio(tracks)
	if want >= 0 and want != int(src.get_audio_track()):
		_own = true
		main.player.select_audio_track(want)
		_own = false
		print("Language memory: audio track %d (%s)" % [want, ", ".join(audio_languages)])
	_show_forced()


## Subtitle files were added (scripts/play/external_subtitles.gd): a forced one may be among them.
func tracks_added() -> void:
	_show_forced()


## Subtitles off: the forced track (foreign-language parts) in the audio's language, as a feature's change.
func _show_forced() -> void:
	var subs: Node = main.features.subtitles
	if not forced_auto or subs.enabled or bool(main.features.access.get_value("subtitles_always")):
		return
	var lang := _current_audio_language()
	if lang == "":
		return
	var t := pick_subtitle(subs.tracks, true, PackedStringArray([lang]))
	if t >= 0:
		subs.set_state({"enabled": true, "track": t})
		print("Language memory: forced subtitles (track %d, %s)" % [t, lang])


func _current_audio_language() -> String:
	var src: Object = main.player.source
	var cur := int(src.get_audio_track())
	for t: Dictionary in src.get_audio_tracks():
		if int(t.get("index", -1)) == cur:
			return normalize(str(t.get("language_code", t.get("language", ""))))
	return ""


func pick_audio(tracks: Array, languages := PackedStringArray()) -> int:
	var langs := languages if not languages.is_empty() else audio_languages
	if langs.is_empty():
		return -1
	var src: Object = main.player.source if main.player.has_source() else null
	var engine: int = src.pick_audio_track(langs) if src != null else -2
	return engine if engine != -2 else _pick(tracks, langs, false, false)


func pick_subtitle(tracks: Array, forced_only := false, languages := PackedStringArray()) -> int:
	var langs := languages if not languages.is_empty() else subtitle_languages
	if langs.is_empty():
		return -1
	var src: Object = main.player.source if main.player.has_source() else null
	var engine: int = src.pick_subtitle_track(langs, forced_only) if src != null else -2
	return engine if engine != -2 else _pick(tracks, langs, true, forced_only)


## The app's own pick, the engine's rules: the first preferred language with any track wins; among its tracks, not
## commentary / audio description, then (subtitles) text, full before forced, without hearing-impaired notes, then
## the default flag, then more channels.
static func _pick(tracks: Array, languages: Variant, subtitles: bool, forced_only := false) -> int:
	var langs: PackedStringArray = PackedStringArray([languages]) if languages is String else languages
	for pref in langs:
		var best := -1
		var best_score := -1
		for t: Dictionary in tracks:
			if not same_language(pref, str(t.get("language_code", t.get("language", "")))):
				continue
			var forced := bool(t.get("forced", false))
			if forced_only and not forced:
				continue
			var score := 0
			score += 0 if bool(t.get("commentary", false)) or bool(t.get("visual_impaired", false)) else 64
			if subtitles:
				score += 32 if bool(t.get("text", true)) else 0
				score += 16 if not forced or forced_only else 0
				score += 8 if not bool(t.get("hearing_impaired", false)) else 0
			score += 4 if bool(t.get("default", false)) else 0
			score += mini(int(t.get("channels", 0)), 3)
			if score > best_score:
				best_score = score
				best = int(t.get("index", -1))
		if best >= 0:
			return best
	return -1


## ISO 639-1 code (lower case, region kept after a hyphen), "" for none / undetermined.
static func normalize(code: String) -> String:
	if code.strip_edges() == "":
		return ""
	if ClassDB.class_has_method("MediaSource", "normalize_language"):
		return str(ClassDB.class_call_static("MediaSource", "normalize_language", code))
	var c := code.strip_edges().to_lower().replace("_", "-")
	var parts := c.split("-", true, 1)
	var base := parts[0]
	if base in ["und", "zxx", "mis", "mul", "none"]:
		return ""
	for group: Array in SAME:
		if base in group:
			base = group[0]
			break
	return base + ("-" + parts[1] if parts.size() > 1 else "")


## A preference without a region matches every region of its language; with a region, only that region.
static func same_language(preference: String, track: String) -> bool:
	var p := normalize(preference)
	var t := normalize(track)
	if p == "" or t == "":
		return false
	return t == p if p.contains("-") else t.split("-")[0] == p


func _remember(list: PackedStringArray, code: String) -> PackedStringArray:
	var n := normalize(code)
	var out := PackedStringArray([n])
	for c in list:
		if c != n and out.size() < MAX_REMEMBERED:
			out.append(c)
	return out


func _on_audio_selected(index: int) -> void:
	if _own or not main.player.has_source():
		return
	for t: Dictionary in main.player.source.get_audio_tracks():
		if int(t.get("index", -1)) == index:
			var lang := normalize(str(t.get("language_code", t.get("language", ""))))
			if lang != "":
				audio_languages = _remember(audio_languages, lang)
				main.settings.set_value("language", "audio", audio_languages)
				changed.emit(audio_language, subtitle_language)


func _on_subtitle_changed(_index: int, enabled: bool) -> void:
	# The automatic pick on open and features' changes (catch-up, forced parts) aren't user choices.
	if not enabled or not main.features.subtitles.by_user:
		return
	var t: Dictionary = main.features.subtitles.current_track()
	var lang := normalize(str(t.get("language_code", t.get("language", ""))))
	if lang == "":
		return
	subtitle_languages = _remember(subtitle_languages, lang)
	main.settings.set_value("language", "subtitles", subtitle_languages)
	changed.emit(audio_language, subtitle_language)


func set_forced_auto(on: bool) -> void:
	forced_auto = on
	main.settings.set_value("subtitles", "forced_auto", on)


func forget() -> void:
	audio_languages = PackedStringArray()
	subtitle_languages = PackedStringArray()
	main.settings.set_value("language", "audio", null)
	main.settings.set_value("language", "subtitles", null)
	changed.emit("", "")
