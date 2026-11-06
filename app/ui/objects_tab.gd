extends ScrollContainer

## The Objects tab: the object library (ui/object_section.gd; docs/assistant.md "Objects", docs/USAGE.md "Objects"):
## the library's thumbnails, Place with the laser, and what this room has from the library with its parts. Three
## sections (the user, 2026-11-06): Built-in objects, Your objects (with Fab's downloads), In this room. The section
## node is the tab's box, so its sections are the tab's (cards on the tablet, one at a time).

const W := preload("res://ui/pane_widgets.gd")
const ObjectSection := preload("res://ui/object_section.gd")

var app: Node
var box: VBoxContainer
var section: ObjectSection


func _init() -> void:
	name = "Objects"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	section = ObjectSection.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(section)
	box = section


func bind(p_app: Node) -> void:
	app = p_app
	section.bind(app)
	app.environment_changed.connect(func(_id: String, _l: float) -> void: sync())
	sync()


func sync() -> void:
	sync_objects()


## Reads the library and the room again (object_commands.gd calls it after a change).
func sync_objects() -> void:
	if section != null:
		section.sync_objects()
