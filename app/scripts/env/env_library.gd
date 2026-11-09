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
const EnvDoc := preload("res://scripts/env/env_doc.gd")

const SKY_DIR := "user://skyboxes"
const ROOM_DIR := "user://rooms"
const DOC_DIR := "res://environments"
const DOC_SUFFIX := ".env.json"
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
	out.append_array(document_rooms())
	for f in _files(SKY_DIR, ImageSource.EXTENSIONS):
		out.append([SKY_PREFIX + f, f.get_basename() + " (photo)", SKY_DIR.path_join(f), []])
	for f in _files(ROOM_DIR, ["glb", "gltf"]):
		out.append([ROOM_PREFIX + f, f.get_basename(), ROOM_DIR.path_join(f), []])
	return out


## Rooms that ship as version 4 documents with no scene of their own (docs/environments.md): every
## res://environments/<id>.env.json without a <id>.tscn beside it (the cinema and the Void have scenes and are main.gd's
## rows) is a room "<id>", named by its document (a translation key). A new room is its document alone.
static func document_rooms() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DOC_DIR):
		if not f.ends_with(DOC_SUFFIX):
			continue
		var id := f.trim_suffix(DOC_SUFFIX)
		if FileAccess.file_exists(DOC_DIR.path_join(id + ".tscn")) or ResourceLoader.exists(DOC_DIR.path_join(id + ".tscn")):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(DOC_DIR.path_join(f)))
		var name := str(j.get("name", id)) if j is Dictionary else id
		out.append([id, name, DOC_DIR.path_join(f), []])
	return out


## A room's group in the Room tab: its document's `room.category` (one of EnvDoc.ROOM_GROUPS), EnvDoc.OTHER for a
## room with no document or none of those. Read once per id.
static func category_of(id: String) -> String:
	var v := str(_room_section(id).get("category", EnvDoc.OTHER))
	return v if EnvDoc.ROOM_GROUPS.has(v) else EnvDoc.OTHER


## A shipped room's line about itself (its document's room.description, a key; the scene rooms' own below; "" when
## it has none).
static func description_of(id: String) -> String:
	if SCENE_DESCRIPTIONS.has(id):
		return SCENE_DESCRIPTIONS[id]
	var v: Variant = _room_section(id).get("description", "")
	return v if v is String else ""


## The rooms that are scenes, not documents (main.gd ENVIRONMENTS, BUILT_IN above).
const SCENE_DESCRIPTIONS := {
	"dim_room": "A small dark room with nothing in it to look at but the film.", # i18n
	"passthrough": "Your own room through the headset's cameras, with the film in front of you.", # i18n
	"home_theatre": "A small home theatre: a sofa in a dark room, the screen above a low cabinet, tower speakers either side.", # i18n
	"drive_in": "A drive-in at night, seen from a car in the middle of the lot: other cars, speaker posts and stars.", # i18n
	"planetarium": "A planetarium: reclined seats under a dark dome full of stars, a skyline round its foot.", # i18n
	"dome": "An open geodesic dome on a wide plain at dusk, the first stars coming out overhead.", # i18n
}


## A shipped room document's "room" section, read once ({} for a room that isn't a document).
static func _room_section(id: String) -> Dictionary:
	if _rooms.has(id):
		return _rooms[id]
	var r := {}
	var path := DOC_DIR.path_join(id + DOC_SUFFIX)
	if FileAccess.file_exists(path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if j is Dictionary and (j as Dictionary).get("room") is Dictionary:
			r = j["room"]
	_rooms[id] = r
	return r


static var _rooms := {}


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
	if path.ends_with(DOC_SUFFIX):
		# A room that ships as a document (docs/environments.md), built by its systems.
		var room: Node3D = (load("res://scripts/env/env_room.gd") as GDScript).new()
		room.set("document", path)
		room.name = id.capitalize().replace(" ", "")
		return room
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
