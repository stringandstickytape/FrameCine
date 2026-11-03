extends RefCounted

## The assistant service's entry point (docs/assistant.md). Off until the user turns on System, Assistant, which is
## remembered as [assistant] enabled = true. main.gd calls attach() at the end of _ready(); with the service off it
## reads one value and returns: no node, no socket. With it on, the port opens only while "Let an assistant find me"
## runs or once an assistant is paired (scripts/assistant/assistant_service.gd).
##
## For the pane:
##   var a := preload("res://scripts/assistant/assistant.gd")
##   a.start(main, true) / a.stop(main, true)      # on / off, remembered
##   var service := a.instance()                  # null when off (scripts/assistant/assistant_service.gd)
##   a.push_to_talk()                             # the push-to-talk node while an assistant is paired, else null

const NODE_NAME := "AssistantService"
const SERVICE := "res://scripts/assistant/assistant_service.gd"


static func attach(main: Node) -> Node:
	if bool(main.settings.get_value("assistant", "enabled", false)):
		return start(main, false)
	return null


## Starts the service (no-op when running). remember: [assistant] enabled = true.
static func start(main: Node, remember := false) -> Node:
	if remember:
		main.settings.set_value("assistant", "enabled", true)
	var tree := main.get_tree()
	var service := _running(tree)
	if service != null:
		return service
	var script := load(SERVICE) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Assistant: %s did not load" % SERVICE)
		return null
	service = script.new()
	service.name = NODE_NAME
	service.settings = main.settings
	# Under the root, so it survives `reload app`; added deferred (main may be in its _ready()).
	tree.root.set_meta(NODE_NAME, service)
	tree.root.add_child.call_deferred(service)
	return service


## Stops the service. remember: [assistant] enabled = false.
static func stop(main: Node, remember := false) -> void:
	if remember:
		main.settings.set_value("assistant", "enabled", false)
	var tree := main.get_tree()
	var service := _running(tree)
	if service != null and is_instance_valid(service):
		service.queue_free()
	tree.root.remove_meta(NODE_NAME)
	print("Assistant: off")


static func _running(tree: SceneTree) -> Node:
	var service := tree.root.get_node_or_null(NODE_NAME)
	if service == null and tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		service = tree.root.get_meta(NODE_NAME)
	if service != null and service.is_queued_for_deletion():
		return null
	return service


## The running service, or null.
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return _running(tree) if tree != null else null


## Push-to-talk while an assistant is paired, else null (the pane binds it to the pointer hand's bumper).
static func push_to_talk() -> Node:
	var service := instance()
	# While an assistant is paired, not only while one is connected: after an app restart the button did nothing until
	# the assistant reconnected, and the viewer can't see that. Spoken with nobody listening, the message waits and the
	# card says so.
	if service == null or not service.is_inside_tree() or (service.clients.clients.is_empty()
			and not service.is_link_connected()):
		return null
	return service.ptt
