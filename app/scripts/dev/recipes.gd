extends RefCounted

## Scene recipes (idea #30; docs/recipes.md): what was built over the dev link, saved as a scene under user://recipes,
## and offered as an environment from then on. This file is the part main.gd needs (the list); it has no dependencies
## and costs one folder listing when the environment list is read. Saving and the commands are in
## recipe_commands.gd (dev mode).

const DIR := "user://recipes"
const PREFIX := "recipe:"
const ROOM_SUFFIX := ".room.json"


## [id, display name, scene path, aliases] for each saved recipe, as main.gd's ENVIRONMENTS rows.
static func environments() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	var files := Array(DirAccess.get_files_at(DIR))
	files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for f: String in files:
		if f.get_extension() in ["tscn", "scn"]:
			var name := f.get_basename()
			out.append([PREFIX + name, name, DIR.path_join(f), []])
		elif f.ends_with(ROOM_SUFFIX):
			# A room an assistant made and the viewer kept (scripts/assistant/assistant_room.gd, docs/assistant.md).
			var room := f.trim_suffix(ROOM_SUFFIX)
			out.append([PREFIX + room, room, DIR.path_join(f), []])
	return out


## "My room" -> "My room"; anything but letters, digits, space, - and _ dropped; at most 40 characters.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.is_valid_identifier() or c in " -_" or c.is_valid_int():
			out += c
	return out.strip_edges().left(40)


static func path_of(name: String) -> String:
	return DIR.path_join(clean_name(name) + ".tscn")
