extends Node

## The Fab store's transport (fab_store.gd): one HTTPS GET at a time through an HTTPRequest, its body in memory or
## streamed to a file. The tests put a fake with the same three methods in its place (tests/test_fab_store.gd), so no
## test reaches the network.
##
##   fetch(url, headers, file) -> {code, headers: {lower-case name: value}, body: PackedByteArray, error: ""}
##       (await it). file "": the body in memory (at most MAX_BODY); else written there (at most MAX_FILE).
##       error: "" or why: "cancelled", "stalled", "network: <the engine's reason>".
##   progress() -> [bytes so far, bytes in all or -1]
##   cancel()   ends the request in flight; its fetch() returns error "cancelled"

## A search page is about 125 KB; the asset formats and the link a few KB.
const MAX_BODY := 4 << 20
## Fab's zip limit is the importer's (fab_import.gd MAX_ZIP_BYTES).
const MAX_FILE := 200 << 20
## A request in memory: all of it within this; a download: no data for this long ends it.
const TIMEOUT := 20.0
const STALL := 30.0

signal _done(out: Dictionary)

var _http: HTTPRequest
var _bytes := -1
var _stalled_since := 0.0


func fetch(url: String, headers: PackedStringArray, file := "") -> Dictionary:
	if _http != null:
		return {"code": 0, "headers": {}, "body": PackedByteArray(), "error": "network: a request is in flight"}
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.max_redirects = 4
	_http.timeout = 0.0 if file != "" else TIMEOUT
	_http.body_size_limit = MAX_FILE if file != "" else MAX_BODY
	if file != "":
		_http.download_file = file
	add_child(_http)
	_bytes = -1
	_stalled_since = Time.get_ticks_msec() / 1000.0
	_http.request_completed.connect(func(result: int, code: int, h: PackedStringArray, body: PackedByteArray) -> void:
		_finish(_result(result, code, h, body)))
	var err := _http.request(url, headers)
	if err != OK:
		_finish({"code": 0, "headers": {}, "body": PackedByteArray(),
				"error": "network: the request could not start (%s)" % error_string(err)})
	set_process(file != "")
	return await _done


func progress() -> Array:
	if _http == null:
		return [0, -1]
	return [_http.get_downloaded_bytes(), _http.get_body_size()]


func cancel() -> void:
	if _http != null:
		_http.cancel_request()
		_finish({"code": 0, "headers": {}, "body": PackedByteArray(), "error": "cancelled"})


func _ready() -> void:
	set_process(false)


## A download that stops sending ends: HTTPRequest's own timeout is for the whole request, too short for a big file.
func _process(_delta: float) -> void:
	if _http == null:
		set_process(false)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var b := _http.get_downloaded_bytes()
	if b != _bytes:
		_bytes = b
		_stalled_since = now
	elif now - _stalled_since > STALL:
		_http.cancel_request()
		_finish({"code": 0, "headers": {}, "body": PackedByteArray(), "error": "stalled"})


func _finish(out: Dictionary) -> void:
	if _http == null:
		return
	var h := _http
	_http = null
	set_process(false)
	h.queue_free()
	# Emitted after fetch() is waiting: a request that fails to start finishes before its await.
	_emit_later.call_deferred(out)


func _emit_later(out: Dictionary) -> void:
	_done.emit(out)


static func _result(result: int, code: int, h: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var headers := {}
	for line in h:
		var i := line.find(":")
		if i > 0:
			headers[line.substr(0, i).strip_edges().to_lower()] = line.substr(i + 1).strip_edges()
	var error := ""
	match result:
		HTTPRequest.RESULT_SUCCESS:
			pass
		HTTPRequest.RESULT_CANT_RESOLVE:
			error = "network: the name could not be looked up (is the headset online?)"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			error = "network: could not connect"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			error = "network: the secure connection failed"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			error = "network: the answer is too big"
		HTTPRequest.RESULT_TIMEOUT:
			error = "network: no answer in time"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			error = "network: too many redirects"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			error = "network: the file could not be written"
		_:
			error = "network: the request failed (%d)" % result
	return {"code": code, "headers": headers, "body": body, "error": error}
