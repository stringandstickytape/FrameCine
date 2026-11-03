extends Node

## Night mode and dialogue boost (ideas #26), on the engine's audio dynamics (MediaSource, fork 0178dc9a02):
##   night mode       loud passages down, quiet ones up: the decoder's own DRC for AC-3 / E-AC-3, and on every track
##                    a compressor that levels the film towards -24 dBFS, with a limiter under -1 dBFS
##   strength         0..1, scales the DRC, the ratio and the lift
##   dialogue boost   0..12 dB on the centre channel; only for audio with one (boost_applies())
## Remembered for all files, applied when each file opens and at once on a change (heard after about 1 s, the
## audio queue). They reach the cinema speakers' channels too (#21). With night mode off the engine plays AC-3 at
## its full range (DRC off). Test patterns and windows have no such audio: nothing to do there.
##
##   night, strength, boost_db
##   set_night(on), set_strength(v), set_dialogue_boost(db)
##   available() -> bool           the engine has it
##   boost_applies() -> bool       the open file's audio has a centre channel (the engine's statistics)
##   stats() -> Dictionary         the engine's audio keys: audio_gain_db, audio_limiter_db, audio_typical_level_db,
##                                 night_mode_decoder_drc, dialogue_boost_applies
##   signal changed
## Settings: [sound] night_mode (default off), night_strength (default 1), dialogue_boost_db (default 0).

signal changed

const STAT_KEYS := ["audio_gain_db", "audio_limiter_db", "audio_typical_level_db", "night_mode_decoder_drc",
		"dialogue_boost_applies"]

static var _available := -1

var main: Node3D
var night := false
var strength := 1.0
var boost_db := 0.0


func _ready() -> void:
	night = bool(main.settings.get_value("sound", "night_mode", false))
	strength = clampf(float(main.settings.get_value("sound", "night_strength", 1.0)), 0.0, 1.0)
	boost_db = clampf(float(main.settings.get_value("sound", "dialogue_boost_db", 0.0)), 0.0, 12.0)
	main.file_opened.connect(func(_p: String) -> void: _apply())
	_apply()


static func available() -> bool:
	if _available < 0:
		var m: Object = ClassDB.instantiate("MediaSource") if ClassDB.class_exists("MediaSource") else null
		_available = 1 if m != null and "night_mode" in m and "dialogue_boost" in m else 0
	return _available == 1


func set_night(on: bool) -> void:
	night = on
	main.settings.set_value("sound", "night_mode", true if on else null)
	_apply()


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	main.settings.set_value("sound", "night_strength", null if is_equal_approx(strength, 1.0) else strength)
	_apply()


func set_dialogue_boost(db: float) -> void:
	boost_db = clampf(snappedf(db, 0.5), 0.0, 12.0)
	main.settings.set_value("sound", "dialogue_boost_db", null if is_zero_approx(boost_db) else boost_db)
	_apply()


func stats() -> Dictionary:
	var out := {}
	var src: Object = main.player.source
	if src != null and src.has_method("get_media_stats"):
		var s: Dictionary = src.get_media_stats()
		for k: String in STAT_KEYS:
			if s.has(k):
				out[k] = s[k]
	return out


func boost_applies() -> bool:
	return bool(stats().get("dialogue_boost_applies", false))


func _apply() -> void:
	var src: Object = main.player.source
	if src != null and src.has_method("set_audio_dynamics"):
		src.set_audio_dynamics(night, strength, boost_db)
	changed.emit()
