extends RefCounted

## Film signals (docs/environments.md, "Bindings and film signals"): normalised channels a room's parameters can
## follow, read from the app once a frame by the room's host (env_host.gd).
##   film.colour        the picture's dominant colour: the mean of the bias light's 4 x 2 copy of the video planes
##                      (scripts/env/bias_light.gd), read back from the GPU without a stall (the rendering device's
##                      asynchronous read, COLOUR_SECONDS apart), only while a binding wants it
##   film.brightness    that colour's luminance
##   film.bass          the low end between film_react.gd's floor and full levels; film.transient: 1 at a sudden loud
##                      jump, falling to 0 over TRANSIENT_FALL. film_react's analyser runs while a room asks for it,
##                      with [react] on or off
##   film.quiet         low sound (under QUIET_DB) and little picture change, held QUIET_HOLD seconds; 0 at once when
##                      either ends
##   film.progress      position over duration; film.minutes: the position in minutes
##   time.of_day        daylight from scripts/env/time_of_day.gd: 0 at -12 degrees of sun, 1 at +12
##   playback.state     the timeline's state (the host sets it); playback.playing 1 while playing
##   comfort.motion     the room's Motion setting (the host sets it)
##
##   update(main, delta, wanted)     one step; wanted: the channels a binding or cue uses
##   value(channel) -> Variant       a channel's value now (fakes first)
##   fake(channel, value)            tests: a channel's value until clear_fakes(); fake_audio(bass_db, broad_db) feeds
##                                   the bass, transient and quiet maths as film_react's levels would

const QUIET_DB := -38.0
const QUIET_HOLD := 3.0
## A picture change under this (colour distance a second) counts as little.
const QUIET_PICTURE := 0.08
const TRANSIENT_FALL := 0.5
const COLOUR_SECONDS := 0.2
## film_react.gd's bass levels (dBFS): the floor (0) and full (1); a transient: this far over the slow average.
const BASS_FLOOR_DB := -30.0
const BASS_FULL_DB := -10.0
const JUMP_DB := 14.0
const LOUD_DB := -24.0
const AVERAGE_SECONDS := 2.0

var values := {
	"film.colour": Color(0, 0, 0), "film.brightness": 0.0, "film.bass": 0.0, "film.transient": 0.0,
	"film.quiet": 0.0, "film.progress": 0.0, "film.minutes": 0.0, "time.of_day": 0.0, "playback.state": "preshow",
	"playback.playing": 0.0, "comfort.motion": 1.0,
}
var _fakes := {}
var _fake_audio: Variant = null
var _quiet_for := 0.0
var _last_colour := Color(0, 0, 0)
var _picture_change := 0.0
var _avg_db := -60.0
var _broad_now := -120.0
var _since_colour := 10.0
var _reading := false
var _sampling_from: Node = null
## Colour reads done (tests, the overlay).
var colour_reads := 0


func fake(channel: String, v: Variant) -> void:
	_fakes[channel] = v


func fake_audio(bass_db: float, broad_db: float) -> void:
	_fake_audio = [bass_db, broad_db]


func clear_fakes() -> void:
	_fakes.clear()
	_fake_audio = null


func value(channel: String) -> Variant:
	if _fakes.has(channel):
		return _fakes[channel]
	return values.get(channel, 0.0)


func update(main: Node, delta: float, wanted: Dictionary) -> void:
	var playing := false
	if main != null and main.get("player") != null:
		var p: Node = main.player
		playing = p.is_playing()
		var d: float = p.get_duration() if p.has_source() else 0.0
		var pos: float = p.get_position() if p.has_source() else 0.0
		values["film.progress"] = clampf(pos / d, 0.0, 1.0) if d > 0.0 else 0.0
		values["film.minutes"] = pos / 60.0
		var tod: Node = main.features.get("time_of_day") if main.get("features") != null else null
		if tod != null:
			values["time.of_day"] = clampf((float(tod.elevation()) + 12.0) / 24.0, 0.0, 1.0)
	elif _fakes.has("playback.playing"):
		playing = float(_fakes["playback.playing"]) > 0.5
	values["playback.playing"] = 1.0 if playing else 0.0
	_audio(main, delta, playing, wanted)
	if wanted.has("film.colour") or wanted.has("film.brightness") or wanted.has("film.quiet"):
		_colour(main, delta)
	var c: Color = value("film.colour")
	values["film.brightness"] = clampf(c.get_luminance(), 0.0, 1.0)
	var change := Vector3(c.r - _last_colour.r, c.g - _last_colour.g, c.b - _last_colour.b).length()
	_last_colour = c
	_picture_change = lerpf(_picture_change, change / maxf(delta, 0.001), 1.0 - exp(-delta / 0.5)) \
			if delta > 0.0 else _picture_change
	# Quiet: the level now and its slow average both low (one loud moment ends it at once).
	var quiet_now := playing and _avg_db < QUIET_DB and _broad_now < QUIET_DB and _picture_change < QUIET_PICTURE
	_quiet_for = _quiet_for + delta if quiet_now else 0.0
	values["film.quiet"] = clampf(_quiet_for - QUIET_HOLD, 0.0, 1.0) if _quiet_for >= QUIET_HOLD else 0.0


## The bass, transient and broad level, from film_react's analyser (asked for while a channel wants them).
func _audio(main: Node, delta: float, playing: bool, wanted: Dictionary) -> void:
	var levels: Variant = _fake_audio
	var react: Node = null
	if main != null and main.get("features") != null:
		react = main.features.get("react")
	var want := wanted.has("film.bass") or wanted.has("film.transient") or wanted.has("film.quiet")
	if react != null and react.has_method("request_analysis"):
		react.request_analysis(self, want)
		if levels == null and want and playing:
			levels = react.levels()
	values["film.transient"] = maxf(float(values["film.transient"]) - delta / TRANSIENT_FALL, 0.0)
	if levels == null:
		values["film.bass"] = 0.0
		_broad_now = -120.0
		_avg_db = lerpf(_avg_db, -80.0, 1.0 - exp(-delta / AVERAGE_SECONDS)) if delta > 0.0 else _avg_db
		return
	var bass_db := float(levels[0])
	var broad_db := float(levels[1])
	_broad_now = broad_db
	values["film.bass"] = clampf((bass_db - BASS_FLOOR_DB) / (BASS_FULL_DB - BASS_FLOOR_DB), 0.0, 1.0)
	if broad_db - _avg_db > JUMP_DB and broad_db > LOUD_DB:
		values["film.transient"] = 1.0
	_avg_db = lerpf(_avg_db, broad_db, 1.0 - exp(-delta / AVERAGE_SECONDS)) if delta > 0.0 else broad_db


## film.colour: the bias light's copy read back (asynchronously) every COLOUR_SECONDS.
func _colour(main: Node, delta: float) -> void:
	_since_colour += delta
	if main == null or main.get("features") == null or _reading or _since_colour < COLOUR_SECONDS:
		return
	var bias: Node = main.features.get("bias")
	if bias == null:
		return
	if _sampling_from != bias:
		bias.request_sampling(self, true)
		_sampling_from = bias
	if not bias.sampling():
		return
	var rd := RenderingServer.get_rendering_device()
	var tex: Texture2D = bias.thumbnail()
	if rd == null or tex == null:
		return
	var rid := RenderingServer.texture_get_rd_texture(tex.get_rid())
	if not rid.is_valid() or not rd.texture_is_valid(rid):
		return
	_since_colour = 0.0
	_reading = true
	var fmt := rd.texture_get_format(rid).format
	rd.texture_get_data_async(rid, 0, func(data: PackedByteArray) -> void:
		_reading = false
		var col: Variant = mean_colour(data, fmt)
		if col is Color:
			values["film.colour"] = col
			colour_reads += 1)


## The mean colour of a small texture's bytes in one of the formats a viewport gives; null for another.
static func mean_colour(data: PackedByteArray, fmt: int) -> Variant:
	var sum := Vector3.ZERO
	var n := 0
	match fmt:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			for i in range(0, data.size() - 3, 4):
				sum += Vector3(data[i], data[i + 1], data[i + 2]) / 255.0
				n += 1
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			for i in range(0, data.size() - 7, 8):
				sum += Vector3(data.decode_half(i), data.decode_half(i + 2), data.decode_half(i + 4))
				n += 1
		RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32:
			for i in range(0, data.size() - 3, 4):
				var v := data.decode_u32(i)
				sum += Vector3(v & 1023, (v >> 10) & 1023, (v >> 20) & 1023) / 1023.0
				n += 1
		_:
			return null
	if n == 0:
		return null
	sum /= n
	return Color(clampf(sum.x, 0.0, 1.0), clampf(sum.y, 0.0, 1.0), clampf(sum.z, 0.0, 1.0))


func release(main: Node) -> void:
	if _sampling_from != null and is_instance_valid(_sampling_from):
		_sampling_from.request_sampling(self, false)
	_sampling_from = null
	if main != null and main.get("features") != null:
		var react: Node = main.features.get("react")
		if react != null and react.has_method("request_analysis"):
			react.request_analysis(self, false)
