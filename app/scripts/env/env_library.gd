extends RefCounted

## The environments beyond main.gd's first three (ideas #52, #18, #53), in main.all_environments()' entry form
## [id, display name, path, aliases]:
##   built-in rooms from primitives   drive-in, home theatre, planetarium, dome (environments/*.tscn)
##   photo rooms (#18)                every picture in user://skyboxes: "sky:<file name>", shown by skybox_room.gd
##   glTF rooms (#53)                 every .glb / .gltf in user://rooms: "room:<file name>", gltf_room.gd
##                                    (the convention: app/docs/rooms.md)
##   (recipes.gd lists kept assistant rooms, <name>.room.json; instantiate() builds them with assistant_room.gd)
## instantiate(entry) builds any of them, or a scene path's scene (main.set_environment() calls it for every entry).
## add_skybox(picture) copies a picture into user://skyboxes and returns its id ("use this photo as the room").
## Static; preload to use.

const SkyboxRoom := preload("res://scripts/env/skybox_room.gd")
const GltfRoom := preload("res://scripts/env/gltf_room.gd")
const ImageSource := preload("res://scripts/play/image_source.gd")

const SKY_DIR := "user://skyboxes"
const ROOM_DIR := "user://rooms"
const SKY_PREFIX := "sky:"
const ROOM_PREFIX := "room:"

const BUILT_IN: Array = [
	["home_theatre", "Home theatre", "res://environments/home_theatre.tscn", ["home", "hometheatre", "lounge"]],
	["drive_in", "Drive-in", "res://environments/drive_in.tscn", ["drivein", "drive", "car"]],
	["planetarium", "Planetarium", "res://environments/planetarium.tscn", ["stars"]],
	["dome", "Dome", "res://environments/dome.tscn", ["geodesic", "dusk"]],
]


static func environments() -> Array:
	var out: Array = BUILT_IN.duplicate()
	for f in _files(SKY_DIR, ImageSource.EXTENSIONS):
		out.append([SKY_PREFIX + f, f.get_basename() + " (photo)", SKY_DIR.path_join(f), []])
	for f in _files(ROOM_DIR, ["glb", "gltf"]):
		out.append([ROOM_PREFIX + f, f.get_basename(), ROOM_DIR.path_join(f), []])
	return out


static func _files(dir: String, extensions: Array) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in extensions:
			out.append(f)
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


## The environment node for an entry; a failed glTF room falls back to an empty one (with the reason printed).
static func instantiate(entry: Array) -> Node3D:
	var id := str(entry[0])
	var path := str(entry[2])
	if id.begins_with(SKY_PREFIX):
		var sky: Node3D = SkyboxRoom.new(path)
		sky.name = "Skybox"
		sky.display_name = str(entry[1])
		return sky
	if id.begins_with(ROOM_PREFIX):
		var room := GltfRoom.load_room(path)
		if room != null:
			return room
		push_warning("glTF room: %s; showing the void instead" % GltfRoom.last_error)
		path = "res://environments/void.tscn"
	if path.ends_with(".room.json"):
		# A room an assistant made and the viewer kept: data, built by scripts/assistant/assistant_room.gd.
		var made: Node3D = (load("res://scripts/assistant/assistant_room.gd") as GDScript).call("load_saved", path)
		if made != null:
			return made
		path = "res://environments/void.tscn"
	return (load(path) as PackedScene).instantiate() as Node3D


## Copies a picture into the photo rooms; returns its id ("sky:<file>") or "" when it can't.
static func add_skybox(picture: String) -> String:
	if not ImageSource.is_image_path(picture) or picture.begins_with("smb://"):
		return ""
	DirAccess.make_dir_recursive_absolute(SKY_DIR)
	var f := picture.get_file()
	var dest := ProjectSettings.globalize_path(SKY_DIR.path_join(f))
	if ProjectSettings.globalize_path(picture) == dest:
		return SKY_PREFIX + f
	if DirAccess.copy_absolute(picture, dest) != OK:
		return ""
	return SKY_PREFIX + f
