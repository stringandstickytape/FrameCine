extends RefCounted

## The assistant's levels behind a switch (docs/assistant.md, "Levels and switches"): its [assistant] key in
## settings.cfg, its row in the System tab, what a refusal says the viewer has not allowed, and what the level covers.
## Each is off until the viewer turns it on. read and card have none: they always work. A small file of its own, so
## the pane (ui/assistant_row.gd) and the agents' first-start card read it without loading the command registry.

## The labels are keys of the menus' languages (the System tab's switches; docs/i18n.md).
# i18n: begin label
const SWITCHES := {
	"control": {"key": "allow_control", "label": "Let the assistant control playback", "doing": "control playback",
			"what": "playback: play, pause, seek, open a file, tracks, volume, recentring"},
	"room": {"key": "allow_room", "label": "Let the assistant change the room", "doing": "change the room",
			"what": "the room around the screen; each change shows at once and is kept"},
	"settings": {"key": "allow_settings", "label": "Let the assistant change settings", "doing": "change settings",
			"what": "the viewer's lasting preferences in the Picture, Sound, Subtitles and System tabs"},
	"files": {"key": "allow_files", "label": "Let the assistant manage files", "doing": "manage files",
			"what": "the Library and files: copies, downloads, places, saved hosts"},
	"apps": {"key": "allow_apps", "label": "Let the assistant run apps", "doing": "run apps",
			"what": "Android apps and the agents on the headset: start, stop, show, hide"},
}
# i18n: end
## The levels with no switch.
const ALWAYS := {
	"read": "what plays, places and folders, chapters, tracks, the room, the measured cost",
	"card": "the card beside the screen: how the assistant answers",
}


## Whether a level is on in these settings (an AppSettings, or null: every switch off).
static func is_on(settings: RefCounted, level: String) -> bool:
	if ALWAYS.has(level):
		return true
	if not SWITCHES.has(level) or settings == null:
		return false
	return bool(settings.get_value("assistant", SWITCHES[level]["key"], false))


## The switches that are off, as the rows say them ("control playback", "manage files", ...).
static func off(settings: RefCounted) -> Array[String]:
	var out: Array[String] = []
	for level: String in SWITCHES:
		if not is_on(settings, level):
			out.append(SWITCHES[level]["doing"])
	return out
