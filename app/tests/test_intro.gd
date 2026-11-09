extends SceneTree

## The first start's introduction (ui/intro.gd) and the speech model: the download starts as soon as the introduction
## opens (once, quietly: the backend's own notices are off meanwhile), every step shows how far it is, Start waits for
## it, a failure offers Retry and Start without voice, and a model that is already there changes nothing. A stand-in
## backend; no network, no renderer. Run:
##   godot --headless --xr-mode off --path app --script res://tests/test_intro.gd

const Intro := preload("res://ui/intro.gd")

var _failures := 0
var _checks := 0


## Stands in for scripts/voice/whisper_backend.gd: model_status(), fetch_model(), quiet.
class FakeVoice extends Node:
	var state := "needed"
	var percent := 0
	var offline := false
	var quiet := false
	var fetches := 0

	func model_status() -> Dictionary:
		return {"state": state, "percent": percent, "offline": offline}

	func fetch_model() -> void:
		if state in ["needed", "failed"]:
			fetches += 1
			state = "running"
			percent = 0


func _initialize() -> void:
	await process_frame
	await _test_download()
	await _test_failure()
	await _test_model_there()
	print("test_intro: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)


func _make(voice: FakeVoice) -> Intro:
	var intro := Intro.new()
	root.add_child(voice)
	root.add_child(intro)
	intro._voice = voice
	intro.begin(["keys", "start"] as Array[String])
	return intro


## Past the guard, one frame's update.
func _tick(intro: Intro) -> void:
	intro._process(Intro.GUARD + 0.1)
	await process_frame


func _test_download() -> void:
	var voice := FakeVoice.new()
	var intro := _make(voice)
	await _tick(intro)
	_check("the download starts when the introduction opens", voice.fetches == 1 and voice.state == "running")
	_check("the backend's own notices are off meanwhile", voice.quiet)
	voice.percent = 40
	await _tick(intro)
	_check("the first step shows the progress", intro._model.visible and intro._model.text.contains("40"))
	await _tick(intro)
	_check("only one download", voice.fetches == 1)
	intro.next()
	await _tick(intro)
	_check("on to the last step", intro.step() == "start")
	_check("Start waits for the model", intro._primary.disabled)
	_check("the last step says Start waits", intro._model.text.begins_with("Start comes on"))
	intro._on_primary()
	_check("pressing Start meanwhile does nothing", intro.active)
	voice.state = "done"
	await _tick(intro)
	_check("the model is here: Start comes on", not intro._primary.disabled)
	_check("and says so", intro._model.text == Intro.MODEL_READY)
	var finished := [false]
	intro.finished.connect(func() -> void: finished[0] = true)
	intro._on_primary()
	_check("Start finishes the introduction", finished[0] and not intro.active)
	_check("the backend's notices are on again", not voice.quiet)
	intro.queue_free()
	voice.queue_free()


func _test_failure() -> void:
	var voice := FakeVoice.new()
	var intro := _make(voice)
	await _tick(intro)
	intro.next()
	await _tick(intro)
	voice.state = "failed"
	voice.offline = true
	await _tick(intro)
	_check("no network: it says so", intro._model.text == Intro.MODEL_OFFLINE)
	_check("the main button is Retry, and on", intro._primary.text == Intro.MODEL_RETRY and not intro._primary.disabled)
	_check("Start without voice shows", intro._without.visible)
	intro._on_primary()
	_check("Retry fetches again", voice.fetches == 2 and voice.state == "running")
	await _tick(intro)
	_check("while it runs again: no Retry, no Start without voice", intro._primary.text != Intro.MODEL_RETRY
			and not intro._without.visible and intro._primary.disabled)
	voice.state = "failed"
	await _tick(intro)
	var finished := [false]
	intro.finished.connect(func() -> void: finished[0] = true)
	intro._without.pressed.emit()
	_check("Start without voice finishes it", finished[0] and not intro.active)
	_check("and leaves the notices on (voice fetches it when used)", not voice.quiet)
	intro.queue_free()
	voice.queue_free()


func _test_model_there() -> void:
	var voice := FakeVoice.new()
	voice.state = ""
	var intro := _make(voice)
	await _tick(intro)
	_check("a model already there: no download", voice.fetches == 0 and not voice.quiet)
	_check("and no line about it", not intro._model.visible)
	intro.next()
	await _tick(intro)
	_check("Start is on at once", not intro._primary.disabled and not intro._without.visible)
	intro.queue_free()
	voice.queue_free()
