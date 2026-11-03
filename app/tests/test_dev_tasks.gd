extends SceneTree

## Dev command worker tasks are always waited for: a normal run, a run that times out, and the app quitting while one
## task still runs and another was given up on. The quit must exit cleanly; run it a few times on the fork build, where
## a task nobody waited for aborted at exit ("corrupted size vs. prev_size"). Judge it by the exit code: that abort
## comes after "OK" is printed.
## godot --headless --xr-mode off --path app --script res://tests/test_dev_tasks.gd

const WorkerTask := preload("res://scripts/dev/worker_task.gd")

var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _run() -> void:
	var r: Dictionary = await WorkerTask.run(self, func() -> Variant: return 6 * 7)
	_check(r["done"] and r["result"] == 42, "a run returns its result: %s" % r)
	_check(WorkerTask.pending() == {"running": 0, "abandoned": 0}, "nothing pending after a run: %s" % WorkerTask.pending())

	r = await WorkerTask.run(self, func() -> Variant:
		OS.delay_msec(300)
		return 1, 0.05)
	_check(not r["done"] and not r.has("result"), "a slow run times out: %s" % r)
	_check(WorkerTask.pending()["abandoned"] == 1, "the timed-out task is kept: %s" % WorkerTask.pending())
	var until := Time.get_ticks_msec() + 3000
	while WorkerTask.pending()["abandoned"] > 0 and Time.get_ticks_msec() < until:
		await process_frame
	_check(WorkerTask.pending()["abandoned"] == 0, "the timed-out task is waited for when it ends")

	# Quit with one task given up on and one still awaited: both are waited for as the tree goes away.
	await WorkerTask.run(self, func() -> Variant:
		OS.delay_msec(400)
		return 2, 0.01)
	WorkerTask.run(self, func() -> Variant:
		OS.delay_msec(400)
		return 3)
	await process_frame
	_check(WorkerTask.pending() == {"running": 1, "abandoned": 1}, "one running, one given up: %s" % WorkerTask.pending())
	print("test_dev_tasks: OK" if _fails == 0 else "test_dev_tasks: %d failed" % _fails)
	quit(1 if _fails > 0 else 0)
