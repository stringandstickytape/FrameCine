extends Node

## The home of the built-in commands (builtin_commands.gd) for every client of the command registry: the dev link to
## the PC (dev_tools.gd) and the phone remote (scripts/remote/remote_server.gd). Whichever needs it first makes it with
## ensure(); it lives under the scene root as "CommandHost", so it survives `reload app`, and `main` is always the
## current scene. It costs nothing until a client exists: main.gd never makes it.

const BuiltinCommands := preload("res://scripts/dev/builtin_commands.gd")
const BrowseCommands := preload("res://scripts/dev/browse_commands.gd")
const TestLab := preload("res://scripts/dev/test_lab.gd")
const Benchmark := preload("res://scripts/dev/benchmark.gd")
const Tour := preload("res://scripts/dev/tour.gd")
const Director := preload("res://scripts/director/director.gd")
const PlayerCommands := preload("res://scripts/dev/player_commands.gd")
const PlaybackTabCommands := preload("res://scripts/dev/playback_tab_commands.gd")
const ShareRoutes := preload("res://scripts/remote/share_routes.gd")
const PCAudio := preload("res://scripts/dev/pc_audio.gd")
const RoomPerf := preload("res://scripts/assistant/room_perf.gd")
const EffectLibrary := preload("res://scripts/effects/effect_library.gd")
const AndroidApps := preload("res://scripts/android/android_apps.gd")
const RoomTabCommands := preload("res://scripts/dev/room_tab_commands.gd")
const SystemTabCommands := preload("res://scripts/dev/system_tab_commands.gd")
const FilesCommands := preload("res://scripts/dev/files_commands.gd")
const ObjectCommands := preload("res://scripts/assistant/object_commands.gd")
const FabStore := preload("res://scripts/assistant/fab_store.gd")
const MaterialLibrary := preload("res://scripts/env/material_library.gd")
const SurfaceStore := preload("res://scripts/env/surface_store.gd")
const PartApply := preload("res://scripts/assistant/part_apply.gd")
const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")
const NODE_NAME := "CommandHost"

## The main scene (scripts/main.gd): the tree's current scene.
var main: Node:
	get:
		var tree := Engine.get_main_loop() as SceneTree
		return tree.current_scene if tree != null else null
var builtins: BuiltinCommands
var browse: BrowseCommands
var files: FilesCommands
var test_lab: TestLab
var room_tab: RoomTabCommands
var system_tab: SystemTabCommands


## The command host, made (and the built-ins registered) on first use.
static func ensure(tree: SceneTree) -> Node:
	var host := tree.root.get_node_or_null(NODE_NAME)
	if host != null:
		return host
	# Made this frame but not in the tree yet (the add is deferred).
	if tree.root.has_meta(NODE_NAME) and is_instance_valid(tree.root.get_meta(NODE_NAME)):
		return tree.root.get_meta(NODE_NAME)
	host = (load("res://scripts/dev/command_host.gd") as GDScript).new()
	host.name = NODE_NAME
	host._register()
	# The root may be busy adding the main scene (called from main's _ready()).
	tree.root.set_meta(NODE_NAME, host)
	tree.root.add_child.call_deferred(host)
	return host


func _register() -> void:
	builtins = BuiltinCommands.new()
	builtins.host = self
	builtins.register_all()
	browse = BrowseCommands.new()
	browse.host = self
	browse.register_all()
	test_lab = TestLab.new()
	test_lab.host = self
	test_lab.register_all()
	Benchmark.register_commands(self)
	Tour.register_commands()
	Director.register_commands(self)
	PlayerCommands.register_commands(self)
	PlaybackTabCommands.register_commands(self)
	ShareRoutes.register_commands(self)
	PCAudio.register_commands(self)
	RoomPerf.register_commands(self)
	EffectLibrary.register_commands(self)
	AndroidApps.register_commands(self)
	MaterialLibrary.register_commands(self)
	room_tab = RoomTabCommands.new()
	room_tab.host = self
	room_tab.register_all()
	system_tab = SystemTabCommands.new()
	system_tab.host = self
	system_tab.register_all()
	files = FilesCommands.new()
	files.host = self
	files.register_all()
	# The object library (scripts/assistant/object_library.gd): the Room tab's objects as commands.
	ObjectCommands.register_commands(self)
	# Fab in the app (scripts/assistant/fab_store.gd): its search and import as commands.
	FabStore.register_commands(self)
	SurfaceStore.register_commands(self)
	PartApply.register_commands(self)
	PictureLibrary.register_commands(self)
	# Loaded, not preloaded: the agents reach the assistant service, which preloads this file.
	load("res://scripts/agents/local_agents.gd").register_commands(self)


## What the app is doing now: the `state` event and the `get` command with no setting.
func app_state() -> Dictionary:
	return state_of(main)


static func state_of(m: Node) -> Dictionary:
	if m == null or not is_instance_valid(m) or not ("player" in m):
		return {}
	var p: Node = m.player
	return {
		"path": m.current_path,
		"title": m.display_title() if m.current_path != "" else "",
		"playing": p.is_playing(),
		"position": snappedf(p.get_position(), 0.01),
		"duration": snappedf(p.get_duration(), 0.01),
		"can_seek": p.can_seek(),
		"auto_paused": m.auto_paused,
		"mode": m.mode.to_id(),
		"mode_source": m.mode_source,
		"environment": m.env_id,
		"volume": m.volume,
		"playlist_index": m.playlist_index,
		"playlist_size": m.playlist.size(),
		"menu_shown": m.menu_shown,
		"xr": m.use_xr,
		"session_focused": m.session_focused,
	}


## The dev link (for events), or null when dev mode is off.
var link: Node:
	get:
		var dev := get_tree().root.get_node_or_null("DevHost") if is_inside_tree() else null
		return dev.link if dev != null else null


## Hot-reload, through the dev tools; null when dev mode is off.
func ensure_hot_reload() -> Node:
	var dev := get_tree().root.get_node_or_null("DevHost")
	return dev.ensure_hot_reload() if dev != null else null
