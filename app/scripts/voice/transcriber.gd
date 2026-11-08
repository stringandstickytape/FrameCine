extends RefCounted
## Speech to text on the headset. A backend registers itself; without one, available() is false.
##
## The assistant service (scripts/assistant/assistant_service.gd) uses it for push-to-talk: live partials while the
## button is held, then the final text. Without a backend, a viewer message carries no text but an audio link the
## assistant can transcribe itself (docs/assistant.md).
##
##   const Transcriber := preload("res://scripts/voice/transcriber.gd")
##   Transcriber.instance().done.connect(_on_done)        # (id, text, final); text "" on failure
##   var id := Transcriber.transcribe(pcm_16k_mono_s16, true)
##
## A backend (on the headset: scripts/voice/whisper_backend.gd) is any object with ready() -> bool,
## describe() -> String and transcribe(id: int, pcm: PackedByteArray, final: bool) -> bool (false: not taken, e.g. a
## partial while one runs). Its methods are called with call(): a Node already has a `ready` signal. It sets
## Transcriber.backend = self and, for every id it took, calls Transcriber.emit_done(id, text, final) exactly once
## (on any thread). `done` is always emitted on the main thread, deferred.
##
## A backend that cannot run yet but can get ready by itself (the whisper backend without its model, which it
## downloads once) sets Transcriber.waiting = self instead. available() is asked only when voice is used, so when it
## answers false it calls waiting.wanted(): that is the backend's cue to start the download or to say how far it is.
## waiting.why() is the line for the viewer ("" for none), English (callers translate it with tr() if they show it in
## the menus); waiting.describe() is for the status.

signal done(id: int, text: String, final: bool)   # text "" on failure

const SCRIPT_PATH := "res://scripts/voice/transcriber.gd"

static var backend: Object = null                  # set by the backend
static var waiting: Object = null                  # set by a backend that gets ready later (above)
static var _instance: RefCounted = null
static var _next_id := 1


## The object that emits `done` (one for the whole app).
static func instance() -> RefCounted:
	if _instance == null:
		_instance = (load(SCRIPT_PATH) as GDScript).new()
	return _instance


## The same object (the name the whisper backend's tests use).
static func events() -> RefCounted:
	return instance()


## True when a backend takes clips now. Asked when voice is used; false tells a waiting backend (wanted()).
static func available() -> bool:
	if backend != null and is_instance_valid(backend) and bool(backend.call("ready")):
		return true
	if _waiting():
		waiting.call("wanted")
	return false


## Why voice is not available, for the viewer ("" when nothing is known: no backend at all, or it is ready).
static func why_unavailable() -> String:
	if available_now() or not _waiting():
		return ""
	return str(waiting.call("why"))


## available() without the cue to a waiting backend (for status displays).
static func available_now() -> bool:
	return backend != null and is_instance_valid(backend) and bool(backend.call("ready"))


static func describe() -> String:
	if backend == null or not is_instance_valid(backend):
		return str(waiting.call("describe")) if _waiting() else "none"
	return str(backend.call("describe"))


static func _waiting() -> bool:
	return waiting != null and is_instance_valid(waiting)


## Queues 16 kHz mono 16-bit PCM; final=false for live partials (may be skipped when busy). Returns an id, which
## `done` carries once; -1 when nothing took it (no backend, or a partial skipped): then no `done` comes.
static func transcribe(pcm: PackedByteArray, final: bool) -> int:
	instance()
	if not available():
		return -1
	var id := _next_id
	_next_id += 1
	return id if bool(backend.call("transcribe", id, pcm, final)) else -1


## The backend's answer for `id` ("" when it failed). Safe from any thread.
static func emit_done(id: int, text: String, final: bool) -> void:
	instance().call_deferred(&"emit_signal", &"done", id, text, final)
