extends Node

## A system of the environments engine (docs/environments.md, "Systems and the registry"): trusted code that a room
## document names and gives parameters. A system reads its own parameters only: it never loads a file a document
## names, a script or a shader, and never evaluates text.
##
##   static func spec() -> Dictionary     {name, kind, description, params, actions, cost, provides, requires}
##   setup()                              build: nodes go into the room with own(node)
##   set_param(name, value)               a live parameter changed (a binding, a cue, a setting)
##   act(action, args)                    a cue's "do"
##   tick(delta)                          every frame the room shows (the host calls it)
##   on_state(state, previous)            the timeline's state changed
##   on_screen_changed(local, size)       the screen moved: its centre in the room's frame, its size
## Optional hooks (the host asks each system that has them): seats(), collision_shapes(), sound_room(),
## static_meshes(), bake_lights(), set_baking(on), set_baked(on).

## env_host.gd: signals, the timeline, the room's settings, the other systems (host.system(id)).
var host: Node
## The environment node the system builds into.
var room: Node3D
## Its id in the document (the system's name unless the document gives one).
var id := ""
## Its parameters: the defaults filled in, bindings at their current values.
var params := {}
## The nodes it added to the room (freed with it when the room builds again).
var _owned: Array[Node] = []


static func spec() -> Dictionary:
	return {}


func setup() -> void:
	pass


func set_param(param: String, value: Variant) -> void:
	params[param] = value
	_param_changed(param, value)


func _param_changed(_param: String, _value: Variant) -> void:
	pass


func act(_action: String, _args: Dictionary) -> void:
	pass


func tick(_delta: float) -> void:
	pass


func on_state(_state: String, _previous: String) -> void:
	pass


func on_screen_changed(_local: Transform3D, _size: Vector2) -> void:
	pass


## Adds a node to the room and remembers it as this system's. Two systems of one kind in a room (two kits) name their
## nodes alike: the second's takes its id after the name ("PieceStatic_furniture"), never the engine's "@...@" name,
## and keeps the plain name in the meta "env_name" (what a motion system's `node` finds among a system's nodes).
func own(node: Node) -> Node:
	var plain := String(node.name)
	if plain != "" and room.has_node(NodePath(plain)):
		var unique := "%s_%s" % [plain, id]
		var k := 2
		while room.has_node(NodePath(unique)):
			unique = "%s_%s%d" % [plain, id, k]
			k += 1
		node.name = unique
	node.set_meta("env_name", plain)
	room.add_child(node)
	_owned.append(node)
	return node


## Takes this system's nodes out of the room (before it builds again).
func clear_owned() -> void:
	for n in _owned:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_owned.clear()


func owned() -> Array[Node]:
	return _owned


## The app's main node, or null when the room stands alone (tests, tools).
func main_node() -> Node:
	return host.main_node() if host != null else null


func float_param(param: String) -> float:
	return float(params.get(param, 0.0))


func color_param(param: String) -> Color:
	var v: Variant = params.get(param)
	if v is Color:
		return v
	return RoomSchemaRef.to_color(v)


const RoomSchemaRef := preload("res://scripts/assistant/room_schema.gd")
