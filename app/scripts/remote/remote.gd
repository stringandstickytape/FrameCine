extends RefCounted

## The phone remote's entry point (idea #13; docs/remote.md). Off until the user turns it on: --remote on the command
## line, or the pane's switch (start(main, true) remembers it as [remote] enabled = true). main.gd calls attach() at
## the end of _ready(); with the remote off it reads two values and returns, and remote_server.gd is not even loaded.
##
## For the pane:
##   var r := preload("res://scripts/remote/remote.gd")
##   r.start(main, true)              # on (and remembered); r.stop(main, true) off (and remembered)
##   var server := r.instance()       # null when off
##   server.address_changed.connect(func(url: String, qr: Image) -> void: ...)   # show the URL and the QR code
##   server.get_url(), server.get_qr_image(8), server.status()
## The same server shares the headset's files when that is on (docs/share.md; --share, [share] enabled):
##   r.start_share(main, true) / r.stop_share(main, true); server.get_share_url() for its QR code

const NODE_NAME := "PhoneRemote"
const SERVER := "res://scripts/remote/remote_server.gd"


static func attach(main: Node, args: Dictionary) -> Node:
	var server: Node = null
	if args.has("remote") or bool(main.settings.get_value("remote", "enabled", false)):
		server = start(main, false)
	# The headset's files on the LAN (docs/share.md): the same server, off by default.
	if args.has("share") or bool(main.settings.get_value("share", "enabled", false)):
		server = start_share(main, false)
	return server


## Starts the phone remote (no-op when running). remember: [remote] enabled = true in the settings.
static func start(main: Node, remember := false) -> Node:
	if remember:
		main.settings.set_value("remote", "enabled", true)
	var server := _server_for(main)
	if server != null:
		server.remote_enabled = true
	return server


## Shares the headset's folders on the LAN (share_routes.gd). remember: [share] enabled = true.
static func start_share(main: Node, remember := false) -> Node:
	if remember:
		main.settings.set_value("share", "enabled", true)
	var fresh := _running(main) == null
	var server := _server_for(main)
	if server != null:
		server.share_enabled = true
		if fresh:
			server.remote_enabled = args_or_setting_remote(main)
	return server


## Stops sharing; the server stops too when the remote is off. remember: [share] enabled = false.
static func stop_share(main: Node, remember := false) -> void:
	if remember:
		main.settings.set_value("share", "enabled", false)
	var server := _running(main)
	if server == null:
		return
	server.share_enabled = false
	if not server.remote_enabled:
		_stop_server(main)


static func args_or_setting_remote(main: Node) -> bool:
	return bool(main.settings.get_value("remote", "enabled", false)) or "--remote" in OS.get_cmdline_user_args()


static func _running(main: Node) -> Node:
	var tree := main.get_tree()
	var server := instance()
	if server == null and tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		server = tree.root.get_meta(NODE_NAME)
	return server


## The server, made (deferred) when there is none.
static func _server_for(main: Node) -> Node:
	var tree := main.get_tree()
	var server := _running(main)
	if server != null:
		return server
	var script := load(SERVER) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Phone remote: %s did not load" % SERVER)
		return null
	server = script.new()
	server.name = NODE_NAME
	server.settings = main.settings
	tree.root.set_meta(NODE_NAME, server)
	tree.root.add_child.call_deferred(server)
	return server


## Stops the phone remote; the server stops too unless sharing is on. remember: [remote] enabled = false.
static func stop(main: Node, remember := false) -> void:
	if remember:
		main.settings.set_value("remote", "enabled", false)
	var server := _running(main)
	if server != null and server.share_enabled:
		server.remote_enabled = false
		return
	_stop_server(main)


static func _stop_server(main: Node) -> void:
	var server := _running(main)
	if server != null and is_instance_valid(server):
		server.queue_free()
	main.get_tree().root.remove_meta(NODE_NAME)


## The running server (scripts/remote/remote_server.gd), or null.
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NODE_NAME) if tree != null else null
