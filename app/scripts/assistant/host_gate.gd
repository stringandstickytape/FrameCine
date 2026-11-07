extends RefCounted

## The go-slow rules for the sites the app asks things of (Fab, fab_store.gd; Poly Haven and ambientCG,
## scripts/env/surface_store.gd; docs/features.md "Fab in the app" and "Surfaces"), in one place:
##   - one request at a time through its transport (so one at a time per host);
##   - a site's pages ("api") at least api_gap (1 s) after its last request ended, its thumbnails and downloads
##     thumb_gap; a thumbnail waits while a page or a download is waiting;
##   - a 429 or a 5xx: nothing more is asked of that site for Retry-After seconds, else BACKOFF_BASE doubled with each
##     one in a row (at most BACKOFF_MAX); a success starts the count again.
## Caching is the caller's (each source keeps its own answers).
##
##   var gate := HostGate.new(); gate.transport = <fetch(url, headers, file), progress(), cancel()>
##   var r: Dictionary = await gate.request(url, headers, kind, site, file, job)
##       the transport's {code, headers, body, error}, or {ok: false, error: backoff | cancelled, message, wait?}

signal changed
signal _free

const API_GAP := 1.0
const THUMB_GAP := 0.25
const BACKOFF_BASE := 2.0
const BACKOFF_MAX := 300.0

## fetch(url, headers, file) -> {code, headers, body, error} (await), progress() -> [bytes, total], cancel().
var transport: Object
var api_gap := API_GAP
var thumb_gap := THUMB_GAP
## Requests sent (the tests count them).
var requests := 0
## site -> its name in a back-off message ("Fab", "Poly Haven").
var names := {}

var _busy := false
var _waiting_first := 0
## site -> when its last request ended (seconds).
var _last_end := {}
## site -> {until, level, code}.
var _backoff := {}


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func busy() -> bool:
	return _busy


## Seconds left of a site's back-off (0: none); site "": the longest of any.
func backoff_left(site := "") -> float:
	var left := 0.0
	for s: String in _backoff:
		if site == "" or s == site:
			left = maxf(left, float(_backoff[s]["until"]) - _now())
	return maxf(0.0, left)


func backoff_code(site: String) -> int:
	return int(_backoff.get(site, {}).get("code", 0))


## How long a back-off lasts: Retry-After when it says (seconds), else BACKOFF_BASE doubled for each in a row.
static func backoff_seconds(level: int, retry_after: String) -> float:
	if retry_after.strip_edges().is_valid_int():
		return clampf(float(retry_after.strip_edges().to_int()), 1.0, 3600.0)
	return minf(BACKOFF_MAX, BACKOFF_BASE * pow(2.0, level))


func _back_off(site: String, code: int, retry_after: String) -> void:
	var b: Dictionary = _backoff.get(site, {"until": 0.0, "level": 0, "code": 0})
	var s := backoff_seconds(int(b["level"]), retry_after)
	b["level"] = int(b["level"]) + 1
	b["until"] = _now() + s
	b["code"] = code
	_backoff[site] = b
	changed.emit()


func backoff_error(site: String) -> Dictionary:
	var left := ceili(backoff_left(site))
	var code := backoff_code(site)
	return {"ok": false, "error": "backoff", "message": "%s is busy (HTTP %d): the app asks it nothing for %d s" % [
			names.get(site, site), code, left], "wait": left, "http": code}


## One GET in its turn (the rules above). kind: "api" (a page), "thumb" or "file" (a download). job: its "cancel"
## stops it before it is sent.
func request(url: String, headers: PackedStringArray, kind := "api", site := "", file := "", job := {}) -> Dictionary:
	var first := kind != "thumb"
	if first:
		_waiting_first += 1
	while _busy or (not first and _waiting_first > 0):
		await _free
	if first:
		_waiting_first -= 1
	_busy = true
	var out: Dictionary = await _request_now(url, headers, kind, site, file, job)
	_busy = false
	_last_end[site] = _now()
	_free.emit()
	return out


func _request_now(url: String, headers: PackedStringArray, kind: String, site: String, file: String,
		job: Dictionary) -> Dictionary:
	var gap := api_gap if kind == "api" else thumb_gap
	var last := float(_last_end.get(site, -1.0e9))
	while _now() - last < gap and backoff_left(site) <= 0.0:
		await _tree().create_timer(gap - (_now() - last)).timeout
	if backoff_left(site) > 0.0:
		return backoff_error(site)
	if bool(job.get("cancel", false)):
		return {"ok": false, "error": "cancelled", "message": "cancelled"}
	requests += 1
	changed.emit()
	var r: Dictionary = await transport.fetch(url, headers, file)
	var code := int(r.get("code", 0))
	if str(r.get("error", "")) == "" and (code == 429 or code >= 500):
		_back_off(site, code, str((r.get("headers", {}) as Dictionary).get("retry-after", "")))
		return backoff_error(site)
	if str(r.get("error", "")) == "" and code >= 200 and code < 300 and _backoff.has(site):
		_backoff[site]["level"] = 0
	return r
