extends RefCounted

## Dev plumbing's entry point (docs/dev/). main.gd calls attach() at the end of _ready(). It reads three settings and
## returns null, making nothing and loading nothing, unless one of these is on:
##   --dev, or [dev] hot_reload = true          hot-reload of the app folder (scripts/dev/hot_reload.gd)
##   --listener=HOST[:PORT], or [dev] listener_host (and listener_port, default 47800)
##                                              the link to the listener on the PC (scripts/dev/dev_link.gd): events
##                                              out, commands in. The headset connects out; nothing listens here.
## Then it loads scripts/dev/dev_tools.gd, the node that holds the tools, under the scene root as "DevHost". This
## file has no dependencies, so an error in a dev script can never stop the app from starting with dev mode off.
## Other options: --dev-allow=MINUTES (permission ring: allow remote changes for that long), --dev-code (allow `run`).

const NODE_NAME := "DevHost"
const TOOLS := "res://scripts/dev/dev_tools.gd"
const DEFAULT_PORT := 47800


## Makes (or, after a scene reload, re-points) the dev node when dev mode is on. Returns it, or null when off.
static func attach(p_main: Node, args: Dictionary) -> Node:
	var settings: RefCounted = p_main.settings
	var want_reload: bool = args.has("dev") or bool(settings.get_value("dev", "hot_reload", false))
	var listener := str(args["listener"]) if args.get("listener") is String else ""
	var host := listener.get_slice(":", 0) if listener != "" else str(settings.get_value("dev", "listener_host", ""))
	var port := int(settings.get_value("dev", "listener_port", DEFAULT_PORT))
	if listener.contains(":"):
		port = listener.get_slice(":", 1).to_int()
	if not want_reload and host == "":
		return null
	var tree := p_main.get_tree()
	var dev: Node = tree.root.get_node_or_null(NODE_NAME)
	if dev != null:
		dev.main = p_main
		dev._on_main_changed()
		return dev
	var script := load(TOOLS) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Dev tools: %s did not load; dev mode is off for this run" % TOOLS)
		return null
	dev = script.new()
	dev.name = NODE_NAME
	dev.main = p_main
	dev.set_meta("want_reload", want_reload)
	dev.set_meta("listener", [host, port])
	dev.set_meta("allow_minutes", float(args["dev-allow"]) if args.get("dev-allow") is String else 0.0)
	dev.set_meta("allow_code", args.has("dev-code"))
	# The root is busy adding the main scene while main's _ready() runs.
	tree.root.add_child.call_deferred(dev)
	return dev


## The dev node (scripts/dev/dev_tools.gd), or null when dev mode is off. For the pane: instance().permissions.
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NODE_NAME) if tree != null else null
