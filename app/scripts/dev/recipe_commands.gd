extends RefCounted

## Scene recipe commands (idea #30; docs/recipes.md): save_recipe, list_recipes, load_recipe and delete_recipe. Saving
## packs the current environment's base and the main scene's Remote node (everything built over the dev link) into
## one scene, user://recipes/<name>.tscn, rooted in recipe_environment.gd, with a ScreenAnchor where the screen is now
## and the current room light. recipes.gd lists the files as environments, so the room comes back next time from the
## pane's Room tab, --env=recipe:<name>, or `set environment recipe:<name>`.

const DevCommands := preload("res://scripts/dev/dev_commands.gd")
const Recipes := preload("res://scripts/dev/recipes.gd")
const RecipeEnvironment := preload("res://scripts/dev/recipe_environment.gd")
const VREnvironment := preload("res://environments/vr_environment.gd")

## scripts/dev/dev_tools.gd
var host: Node


func register_all() -> void:
	DevCommands.register("save_recipe", _cmd_save, {
		"description": "Saves the current room plus everything under the main scene's Remote node as an environment "
				+ "(user://recipes/<name>.tscn), with the screen where it is now.",
		"params": [{"name": "name", "type": "string", "required": true},
				{"name": "replace", "type": "bool", "default": false}],
		"level": "change", "returns": "{id, path, nodes, bytes}"})
	DevCommands.register("list_recipes", _cmd_list, {
		"description": "The saved recipes.", "returns": "[{id, name, path, bytes}]"})
	DevCommands.register("load_recipe", _cmd_load, {
		"description": "Switches to a saved recipe as the environment (as set environment recipe:<name>).",
		"params": [{"name": "name", "type": "string", "required": true}],
		"level": "control", "returns": "{environment}"})
	DevCommands.register("delete_recipe", _cmd_delete, {
		"description": "Deletes a saved recipe.",
		"params": [{"name": "name", "type": "string", "required": true}],
		"level": "change", "returns": "{deleted}"})


func _cmd_save(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var name := Recipes.clean_name(args["name"])
	if name == "":
		return ctx.fail("give a name (letters, digits, space, - and _)")
	var path := Recipes.path_of(name)
	if FileAccess.file_exists(path) and not args["replace"]:
		return ctx.fail("%s exists; add replace=true" % path)
	var r := save(host.main, name, path)
	if r.has("error"):
		return ctx.fail(r["error"])
	ctx.summary = "saved recipe %s" % name
	return r


## Builds the recipe scene from the live one and saves it. {id, path, nodes, bytes} or {error}.
static func save(main: Node, name: String, path: String) -> Dictionary:
	var env: Node = main.env
	if env == null:
		return {"error": "no environment"}
	# The base: the built-in environment under the current one (a recipe's own base when a recipe is shown).
	var base_path: String = env.scene_file_path
	if env.get_script() == RecipeEnvironment:
		base_path = env.get_node("Base").scene_file_path if env.get_node_or_null("Base") != null else ""
	var root := Node3D.new()
	root.name = name.replace(" ", "_")
	root.set_script(RecipeEnvironment)
	root.set("display_name", name)
	root.set("ambient_level", float(env.get("ambient_level")) * float(main.room_light))
	root.set("screen_glow", float(env.get("screen_glow")) * float(main.room_light))
	root.set("default_screen_width", float(main.screen_width))
	var anchor := Marker3D.new()
	anchor.name = "ScreenAnchor"
	var yaw: float = main.screen_yaw
	var d: float = main.screen_distance
	anchor.transform = Transform3D(Basis(Vector3.UP, -yaw),
			Vector3(sin(yaw) * d, VREnvironment.NOMINAL_EYE_HEIGHT + float(main.screen_height_offset), -cos(yaw) * d))
	root.add_child(anchor)
	anchor.owner = root
	root.set("screen_anchor", anchor)
	if base_path != "":
		var base := (load(base_path) as PackedScene).instantiate()
		base.name = "Base"
		root.add_child(base)
		base.owner = root
	var count := 0
	var remote: Node = main.get_node_or_null("Remote")
	if remote != null and remote.get_child_count() > 0:
		var built := remote.duplicate()
		built.name = "Built"
		root.add_child(built)
		built.owner = root
		count = _own(built, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return {"error": "can't pack the scene: %s" % error_string(err)}
	DirAccess.make_dir_recursive_absolute(Recipes.DIR)
	err = ResourceSaver.save(packed, path)
	if err != OK:
		return {"error": "can't save %s: %s" % [path, error_string(err)]}
	var f := FileAccess.open(path, FileAccess.READ)
	print("Recipe saved: %s (%d nodes built, base %s)" % [path, count, base_path])
	return {"id": Recipes.PREFIX + Recipes.clean_name(name), "path": ProjectSettings.globalize_path(path),
			"nodes": count, "bytes": f.get_length() if f != null else 0}


## Gives every node under `n` to `owner`, so pack() keeps it, except inside instanced scenes (they are saved as a
## reference to their file). Returns the number of nodes.
static func _own(n: Node, new_owner: Node) -> int:
	var count := 0
	for c in n.get_children():
		c.owner = new_owner
		count += 1
		if c.scene_file_path == "":
			count += _own(c, new_owner)
	return count


func _cmd_list(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
	var out: Array = []
	for e: Array in Recipes.environments():
		var f := FileAccess.open(e[2], FileAccess.READ)
		out.append({"id": e[0], "name": e[1], "path": ProjectSettings.globalize_path(e[2]),
				"bytes": f.get_length() if f != null else 0})
	return out


func _cmd_load(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var name := Recipes.clean_name(args["name"]).trim_prefix(Recipes.PREFIX)
	if not FileAccess.file_exists(Recipes.path_of(name)):
		return ctx.fail("no recipe %s" % name)
	var m: Node = host.main
	var old: String = m.env_id
	m.set_environment(Recipes.PREFIX + name)
	if m.env_id != Recipes.PREFIX + name:
		return ctx.fail("this build's main.gd does not list recipes as environments")
	ctx.summary = "room %s" % name
	ctx.undo = func() -> void: host.main.set_environment(old)
	return {"environment": m.env_id}


func _cmd_delete(args: Dictionary, ctx: DevCommands.Call) -> Variant:
	var path := Recipes.path_of(args["name"])
	if not FileAccess.file_exists(path):
		return ctx.fail("no recipe %s" % args["name"])
	if host.main.env_id == Recipes.PREFIX + Recipes.clean_name(args["name"]):
		return ctx.fail("it is the room now; switch to another first")
	DirAccess.remove_absolute(path)
	ctx.summary = "deleted recipe %s" % args["name"]
	return {"deleted": ProjectSettings.globalize_path(path)}
