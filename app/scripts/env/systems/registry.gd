extends RefCounted

## The registry of the environments engine (docs/environments.md, "Systems and the registry"): the systems a room
## document may name, by name. Each is a script that extends env_system.gd and declares its spec(). Adding a system is
## one line here and its script; the assistant's schema (room_systems) and the docs' tables come from the specs.
## Static; preload to use.
##
##   Registry.names() -> Array[String]
##   Registry.has(name) -> bool
##   Registry.script_of(name) -> GDScript (null when unknown)
##   Registry.spec(name) -> Dictionary
##   Registry.describe() -> Array      every spec, for the assistant

const SYSTEMS := {
	"light": "res://scripts/env/systems/house_light.gd",
	"auditorium": "res://scripts/env/systems/auditorium.gd",
	"screen_frame": "res://scripts/env/systems/screen_frame.gd",
	"showing": "res://scripts/env/systems/showing.gd",
	"mirror_floor": "res://scripts/env/systems/mirror_floor.gd",
	"atmosphere": "res://scripts/env/systems/atmosphere.gd",
	"weather": "res://scripts/env/systems/weather.gd",
}
## The kinds a system may be (spec().kind).
const KINDS: Array[String] = ["builder", "kit", "light", "sky", "atmosphere", "life", "sound", "music", "screen",
		"seats", "motion", "showing"]

static var _specs := {}


static func names() -> Array[String]:
	var out: Array[String] = []
	for k: String in SYSTEMS:
		out.append(k)
	return out


static func has(system_name: String) -> bool:
	return SYSTEMS.has(system_name)


static func script_of(system_name: String) -> GDScript:
	if not SYSTEMS.has(system_name):
		return null
	return load(SYSTEMS[system_name]) as GDScript


static func spec(system_name: String) -> Dictionary:
	if not _specs.has(system_name):
		var s := script_of(system_name)
		_specs[system_name] = s.call("spec") if s != null else {}
	return _specs[system_name]


## Every system's spec, sorted by name: {name, kind, description, params, actions, cost, provides, requires}.
static func describe() -> Array:
	var out: Array = []
	for n: String in names():
		var s := spec(n).duplicate(true)
		s["name"] = n
		for k: String in ["actions", "provides", "requires"]:
			if not s.has(k):
				s[k] = {} if k == "actions" else []
		out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out
