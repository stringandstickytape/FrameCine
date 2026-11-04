extends RefCounted

## The showrooms (docs/showrooms.md): rooms that ship with the app to show what the room system can do (every effect,
## every library material, the parts a room document can place, lights, each sky) and to measure what each costs the
## GPU (room_perf.gd, perf_rooms). Each is a room document as a kept room is saved (assistant_room.gd), read-only under
## res://environments/showrooms with the models and pictures in <file>.files/, and listed by index.json in the order
## the Room tab shows them, under "Showrooms". tools/showrooms.gd writes them all; run it again when a library grows.
##
##   Showrooms.environments() -> [[id, name, path, aliases], ...]    main.gd's environment rows ("showroom:<id>")
##   Showrooms.entries() -> [{id, name, file, description, shows, budget}]    index.json's rows
##   Showrooms.is_showroom(id) -> bool

const DIR := "res://environments/showrooms"
const INDEX := "index.json"
const PREFIX := "showroom:"

static var _entries: Array = []


## index.json's rows, read once ([] when it is missing or unreadable).
static func entries() -> Array:
	if _entries.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(DIR.path_join(INDEX))) == OK and j.data is Dictionary \
				and (j.data as Dictionary).get("showrooms") is Array:
			for e: Variant in j.data["showrooms"]:
				if e is Dictionary and e.get("id") is String and e.get("file") is String:
					_entries.append(e)
	return _entries


## [id, display name, path, aliases] per showroom, as main.gd's ENVIRONMENTS rows; EnvLibrary.instantiate() builds a
## .room.json path with assistant_room.gd.
static func environments() -> Array:
	var out: Array = []
	for e: Dictionary in entries():
		out.append([PREFIX + str(e["id"]), str(e.get("name", e["id"])), DIR.path_join(str(e["file"])), []])
	return out


static func is_showroom(id: String) -> bool:
	return id.begins_with(PREFIX)
