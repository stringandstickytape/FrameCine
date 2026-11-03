extends SceneTree

## The app with its assistant service on 127.0.0.1, for tools/assistant/test_assistant.py (an assistant from outside,
## over HTTPS). Runs the real main scene with read-only settings and test files; opens "Let an assistant find me" at
## once. A folder passed with --assistant-dir is how the test plays the viewer: this writes state.json there (the code
## the headset shows, the card's text) a few times a second, and runs the lines of control.txt (then deletes it):
##   speak             a 1 s push-to-talk clip, "heard" as "what is this" by a stand-in speech to text (a clip
##                     with no words is never sent to the assistant)
##   allow_control 1   "Let the assistant control playback" on (0: off)
##   open PATH         opens a file
##   quit
## godot --headless --xr-mode off --path app --script res://tests/assistant_host.gd -- --assistant-port=P
##       --assistant-dir=/tmp/x

const Assistant := preload("res://scripts/assistant/assistant.gd")
const PushToTalk := preload("res://scripts/dev/push_to_talk.gd")
const Transcriber := preload("res://scripts/voice/transcriber.gd")
const FILES := ["user://test_e2e_clients.cfg", "user://test_e2e_tls.key", "user://test_e2e_tls.crt"]

var main: Node3D
var service: Node
var dir := ""
var _next := 0


func _init() -> void:
	var port := 47801
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--assistant-port="):
			port = a.get_slice("=", 1).to_int()
		elif a.begins_with("--assistant-dir="):
			dir = a.get_slice("=", 1)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	main.settings.set_value("assistant", "port", port)
	main.settings.set_value("assistant", "allow_control", false)
	main.settings.set_value("assistant", "allow_room", false)
	root.add_child(main)
	current_scene = main
	_start.call_deferred()


func _start() -> void:
	for f in FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	service = Assistant.start(main, false)
	service.bind_address = "127.0.0.1"
	service.clients_path = FILES[0]
	service.tls_key_path = FILES[1]
	service.tls_cert_path = FILES[2]
	service.start_whisper = false
	await process_frame
	await process_frame
	service.open_window()
	main.open_path("stub://flat_sbs")


func _process(_delta: float) -> bool:
	if service == null or not is_instance_valid(service) or not service.is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	if now < _next:
		return false
	_next = now + 150
	if dir == "":
		return false
	var card: Node = main.ui.card
	var p: Dictionary = service.pairing()
	var st := {"listening": service.is_listening(), "code": p.get("code", ""), "client": p.get("client", ""),
			"card_visible": card.visible, "card_title": card._title.text, "card_text": card._text.text,
			"conversation": service.conversation.text(), "connected": service.is_link_connected(),
			"playing": main.player.is_playing()}
	var f := FileAccess.open(dir.path_join("state.json.tmp"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(st))
		f.close()
		DirAccess.rename_absolute(dir.path_join("state.json.tmp"), dir.path_join("state.json"))
	var ctl := dir.path_join("control.txt")
	if FileAccess.file_exists(ctl):
		var text := FileAccess.get_file_as_string(ctl)
		DirAccess.remove_absolute(ctl)
		for line in text.split("\n", false):
			_run(line.strip_edges())
	return false


func _run(line: String) -> void:
	var word := line.get_slice(" ", 0)
	var rest := line.substr(word.length()).strip_edges()
	match word:
		"speak":
			Transcriber.backend = HeardBackend.new()
			var pcm := PackedByteArray()
			pcm.resize(16000 * 2)
			service.send_event("voice_state", {"recording": true})
			service.send_event("voice_state", {"recording": false})
			service.send_event("voice_clip", {"wav_b64": Marshalls.raw_to_base64(PushToTalk.wav_bytes(pcm, 16000)),
					"seconds": 1.0})
		"allow_control":
			service.set_allow_control(rest == "1")
		"open":
			main.open_path(rest)
		"quit":
			for f in FILES:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
			quit(0)


## Speech to text that hears every clip as "what is this".
class HeardBackend:
	extends RefCounted

	func ready() -> bool:
		return true

	func describe() -> String:
		return "a stand-in"

	func transcribe(id: int, _pcm: PackedByteArray, final: bool) -> bool:
		Transcriber.emit_done(id, "what is this", final)
		return true
