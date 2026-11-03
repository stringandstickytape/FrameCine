extends RefCounted

## Worker-thread jobs for the dev commands, awaited frame by frame so the frame never blocks.
##
## Every task is waited for exactly once, also when its caller stops waiting: after a timeout, or when the app quits
## while a command still waits. Those tasks are waited for when the scene tree's root leaves the tree. The engine frees
## tasks that nobody waited for at its very end, after the script runtime has shut down, and freeing a script lambda then
## corrupts the heap (an abort at exit). A task still running at quit holds the quit until it ends, which the engine's
## own thread shutdown would do anyway.
##
##   const WorkerTask := preload("res://scripts/dev/worker_task.gd")
##   var r: Dictionary = await WorkerTask.run(get_tree(), func() -> Variant: return slow(), 10.0)
##   if r["done"]: use(r["result"])

## Tasks a caller is waiting for now.
static var _running: Array[int] = []
## Tasks whose caller gave up (timeout); waited for once they end, or at exit.
static var _abandoned: Array[int] = []
static var _hooked := false


## Runs `f` on a worker thread. {"done": true, "result": f's return value}, or {"done": false} when `timeout` seconds
## pass first (0: no limit); the task then runs on and is waited for later.
## high_priority: a job the user waits on (speech to text). Low-priority tasks share a few of the pool's threads, so
## long ones queued there can keep a new one from starting at all.
static func run(tree: SceneTree, f: Callable, timeout := 0.0, high_priority := false) -> Dictionary:
	_hook(tree)
	_reap()
	var box := {}
	var task := WorkerThreadPool.add_task(func() -> void: box["r"] = f.call(), high_priority, "dev command")
	_running.append(task)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not WorkerThreadPool.is_task_completed(task):
		if timeout > 0.0 and Time.get_ticks_msec() > deadline:
			_running.erase(task)
			_abandoned.append(task)
			return {"done": false}
		await tree.process_frame
	_running.erase(task)
	WorkerThreadPool.wait_for_task_completion(task)
	return {"done": true, "result": box.get("r")}


## Tasks not yet waited for: {running, abandoned}. For the tests.
static func pending() -> Dictionary:
	_reap()
	return {"running": _running.size(), "abandoned": _abandoned.size()}


## Waits for the abandoned tasks that have ended.
static func _reap() -> void:
	for i in range(_abandoned.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_abandoned[i]):
			WorkerThreadPool.wait_for_task_completion(_abandoned[i])
			_abandoned.remove_at(i)


static func _hook(tree: SceneTree) -> void:
	if _hooked or tree == null or tree.root == null:
		return
	_hooked = true
	tree.root.tree_exiting.connect(func() -> void: _wait_all())


static func _wait_all() -> void:
	for t in _running + _abandoned:
		WorkerThreadPool.wait_for_task_completion(t)
	_running.clear()
	_abandoned.clear()
	_hooked = false
