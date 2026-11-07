extends "res://scripts/env/systems/env_system.gd"

## The showing (docs/environments.md, "Timeline and cues"): the curtains' part in a room's ritual. The curtains are the
## pre-show's (scripts/env/preshow.gd: two panels in front of the flat screen); this system lets a cue part and close
## them. With by_cue on, the pre-show waits for the cue (at most preshow.CUE_GRACE seconds) before it parts them itself.

static func spec() -> Dictionary:
	return {
		"kind": "showing",
		"description": "The curtains in front of the screen as a cue moves them: they part when the ritual says, and "
				+ "close at the end.",
		"params": {
			"by_cue": {"type": "bool", "default": true,
					"description": "a cue parts the curtains (the pre-show waits for it a few seconds)"},
		},
		"actions": {"open_curtains": "the curtains part (args: seconds, default 4)",
				"close_curtains": "the curtains close (args: seconds, default 3)"},
		"cost": {"draws": 2, "triangles": 24, "lights": 0, "particles": 0, "texture_mb": 0},
	}


## The actions run, for the tests: [[action, args], ...].
var log: Array = []


func act(action: String, args: Dictionary) -> void:
	log.append([action, args])
	var main := main_node()
	var preshow: Node = main.features.get("preshow") if main != null and main.get("features") != null else null
	if preshow == null:
		return
	match action:
		"open_curtains":
			if preshow.available():
				preshow.open_curtains(float(args.get("seconds", 4.0)))
		"close_curtains":
			if preshow.available():
				preshow.close_curtains(float(args.get("seconds", 3.0)))


func curtains_by_cue() -> bool:
	return bool(params["by_cue"])
