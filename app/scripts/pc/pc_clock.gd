extends RefCounted

## One PC's clock as the headset sees it (docs/pc-windows.md, "Stream connections": every packet plays at its time
## plus a fixed delay, the same for picture and sound). Every packet's arrival is a sample of "headset ticks minus PC
## time"; the smallest is the one that waited least on the network, so it is the offset. The PC time to show now is
## the headset's ticks minus that offset minus the delay: a frame that arrived late by less than the delay is still
## on time, and the sound, played against the same number, stays with the picture.
##
## The two clocks drift apart (tens of microseconds a second): the smallest sample of each WINDOW seconds is compared
## with the offset, and a later one moves the offset by at most SLEW (so the picture never jumps); one more than
## RESET later (the PC restarted) replaces it.
## Thread-safe: the stream readers observe(), the main thread asks now().

const WINDOW_USEC := 5_000_000
const SLEW_USEC := 2_000
const RESET_USEC := 1_000_000
const DEFAULT_DELAY := 0.15

## Seconds behind the PC's own time that everything plays.
var delay := DEFAULT_DELAY
var _mutex := Mutex.new()
var _offset := 0
var _known := false
var _window_min := 0
var _window_start := 0
var _samples := 0


## A packet stamped `pc_usec` arrived at `ticks_usec` (Time.get_ticks_usec()).
func observe(pc_usec: int, ticks_usec := -1) -> void:
	var t := ticks_usec if ticks_usec >= 0 else Time.get_ticks_usec()
	var s := t - pc_usec
	_mutex.lock()
	_samples += 1
	if not _known:
		_offset = s
		_known = true
		_window_min = s
		_window_start = t
	else:
		if s < _offset:
			_offset = s
		if t - _window_start >= WINDOW_USEC:
			# The window's best is later than the offset: the PC's clock runs slow against ours.
			if _window_min - _offset > RESET_USEC:
				_offset = _window_min
			elif _window_min > _offset:
				_offset += mini(_window_min - _offset, SLEW_USEC)
			_window_min = s
			_window_start = t
		else:
			_window_min = mini(_window_min, s)
	_mutex.unlock()


func known() -> bool:
	_mutex.lock()
	var k := _known
	_mutex.unlock()
	return k


## The PC time (seconds) whose packets play now, or -1 before the first packet.
func now(ticks_usec := -1) -> float:
	var t := ticks_usec if ticks_usec >= 0 else Time.get_ticks_usec()
	_mutex.lock()
	var k := _known
	var o := _offset
	_mutex.unlock()
	if not k:
		return -1.0
	return float(t - o) / 1e6 - delay


## How late (seconds) a packet stamped `pc_usec` arrived compared with the best one so far.
func lateness(pc_usec: int, ticks_usec := -1) -> float:
	var t := ticks_usec if ticks_usec >= 0 else Time.get_ticks_usec()
	_mutex.lock()
	var o := _offset
	_mutex.unlock()
	return float(t - pc_usec - o) / 1e6


func reset() -> void:
	_mutex.lock()
	_known = false
	_samples = 0
	_mutex.unlock()
