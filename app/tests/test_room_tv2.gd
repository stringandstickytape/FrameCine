extends "res://tests/test_room_tv.gd"

## The rest of the history of television (docs/environments.md, "Room: TV 1937", "TV 1966", "TV 2002", "TV today"):
## four more living rooms over the domestic builder with a telly, checked as test_room_tv.gd checks the first seven
## (its _built and _common: the schema, comfort, licences, names, no people, the headset's budget, a clear sight line
## from every seat, the Television group, the era's preset, the telly's shape and its size from the viewer's own seat,
## 17 to 23 degrees across, the picture on the set's glass) and each for its own things: the 1937 drawing room's
## walnut set, marble fireplace and tea tray; the 1966 rented set on splayed legs with its channel dial, the teak
## sideboard and the orange settee; the 2002 lounge's big deep set, the leather sofa and the glass table (see-through,
## under the sight line); the present's thin panel on a dark wall over a media unit and a soundbar, the floor lamp, a
## clean picture. Each room's settings and what they do, its cues, its sound (tests/room_sound.gd: the beds on the
## room's bus, a bound bed on its setting or channel, the level under the film). Tomorrow's bare room, where a part of
## the wall wakes and becomes the picture. And the whole TV group's names sort as time travel takes them.
## godot --headless --xr-mode off --path app --script res://tests/test_room_tv2.gd

const TimeTravel := preload("res://scripts/env/time_travel.gd")
## The speculative future: a wall, not a telly (its own checks).
const FUTURE := "tv_future"

## id -> [year (a word for the present), preset, aspect of the picture]
const ROOMS2 := {
	"tv_1937": ["1937", "mirrorlid_1937", 1.25],
	"tv_1966": ["1966", "rental_1966", 4.0 / 3.0],
	"tv_2002": ["2002", "projection_2002", 16.0 / 9.0],
	"tv_today": ["today", "slimline_present", 16.0 / 9.0],
}
## Each room's sound beds: id -> {bed: sound}.
const SOUND2 := {
	"tv_1937": {"fire": "fire", "clock": "clock", "whine": "tube_whine"},
	"tv_1966": {"radiator": "radiator", "clock": "clock", "whine": "tube_whine"},
	"tv_2002": {"fan": "hum"},
	"tv_today": {"rain": "rain_glass"},
}


func era(id: String) -> Array:
	return ROOMS2[id] if ROOMS2.has(id) else ROOMS[id]


func run_tests() -> void:
	test_name = "test_room_tv2"
	for id: String in ROOMS2:
		var r := EnvDoc.load_file("res://environments/%s.env.json" % id)
		check("%s: the document reads %s" % [id, r["errors"]], (r["errors"] as Array).is_empty())
		var doc: Dictionary = r["doc"]
		if doc.is_empty():
			continue
		check("%s: named for its year (%s)" % [id, doc["name"]], str(doc["name"]).begins_with("TV %s - "
				% ROOMS2[id][0]))
		check("%s: in the Television group, described" % id, str(doc["room"].get("category", "")) == "tv"
				and str(doc["room"].get("description", "")).length() > 40)
		var room := await _built(id, doc)
		await _common(id, room, doc)
		match id:
			"tv_1937":
				await _tv_1937(room)
			"tv_1966":
				await _tv_1966(room)
			"tv_2002":
				await _tv_2002(room)
			"tv_today":
				await _tv_today(room)
		await switches(id, room, id == "tv_1966")
		var p := _p(room)
		check("%s: the set's window the picture's shape (tube %.3f)" % [id, float(p.value("tube"))],
				absf(float(p.value("tube")) - float(ROOMS2[id][2])) < 0.01)
		RoomSound.check_beds(self, id, room, SOUND2[id], "small_room")
		await sounds(id, room, SOUND2[id])
		await done(room)
		await RoomSound.check_level(self, self, id, doc)
	await _tv_future()
	_timeline()


## The whole group sorts as a timeline: every TV room's name in the order time travel takes them (its year_of: the
## years, then today, then tomorrow), the present and the future last.
func _timeline() -> void:
	var ids: Array[String] = []
	for id: String in ROOMS:
		ids.append(id)
	for id: String in ROOMS2:
		ids.append(id)
	ids.append(FUTURE)
	ids.sort_custom(func(a: String, b: String) -> bool: return TimeTravel.year_of(a) < TimeTravel.year_of(b))
	var names: Array[String] = []
	for id in ids:
		names.append(str(EnvDoc.load_file("res://environments/%s.env.json" % id)["doc"].get("name", "")))
	var sorted := names.duplicate()
	sorted.sort()
	check("the TV group's %d names sort as time travel takes them %s" % [names.size(), names], sorted == names
			and names.size() == ROOMS.size() + ROOMS2.size() + 1 and ids[-2] == "tv_today" and ids[-1] == FUTURE)


## Tomorrow: a calm bare room with no set at all; a part of the wall becomes the picture, 17 to 23 degrees across, and
## wakes as the film starts (the picture's light from half to full, then the film untouched); stars in the long window.
func _tv_future() -> void:
	var r := EnvDoc.load_file("res://environments/%s.env.json" % FUTURE)
	check("future: the document reads %s" % [r["errors"]], (r["errors"] as Array).is_empty())
	var doc: Dictionary = r["doc"]
	if doc.is_empty():
		return
	check("future: named, in the Television group (%s)" % doc["name"], str(doc["name"]).begins_with("TV tomorrow - ")
			and str(doc["room"].get("category", "")) == "tv")
	var room := await _built("tv_future", doc)
	var b: Node = room.host.system("room")
	var p := _p(room)
	check("future: no set: the picture on the wall itself", str(b.params["screen"]) == "wall"
			and room.get_node_or_null("Telly") == null and int(b.params["lamps"]) == 0
			and str(b.params["heater"]) == "none")
	var sc: Dictionary = b.screen()
	var ds: Dictionary = doc["screen"]
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var w := float(sc["size"][0])
	check("future: the document's screen is the wall's (%s, %s)" % [ds, sc], c.is_equal_approx(Vector3(
			float(ds["center"][0]), float(ds["center"][1]), float(ds["center"][2]))))
	var deg := rad_to_deg(2.0 * atan(w * 0.5 / -c.z))
	check("future: %.2f m wide at %.2f m: %.1f degrees" % [w, -c.z, deg], deg >= MIN_DEG and deg <= MAX_DEG
			and absf(w / float(sc["size"][1]) - 16.0 / 9.0) < 0.01)
	check("future: the film untouched outside the waking", not p.picture_on())
	room.host.auto = false
	await _play(room, 1.0, STOPPED)
	room.host.snapshot_override = PLAYING
	var least := _extreme(room, "gain", false)
	check("future: the wall wakes: the picture half lit at first (%.2f)" % least, least < 0.6)
	await _play(room, 7.0)
	check("future: then the film itself, untouched (%.2f)" % float(p.value("gain")), not p.picture_on())
	room.host.set_setting("stars", 0.0)
	await _play(room, 0.5, STOPPED)
	check("future: Stars in the window at the bottom: none (%.2f)" % float(room.host.param("sky.stars")),
			float(room.host.param("sky.stars")) < 0.01)
	room.host.set_setting("stars", 0.8)
	check("future: a settee of three, the viewer in its middle", _model_count(room, "settee") == 3)
	await sounds("future", room, {})
	await done(room)


func _pieces(room: Node3D) -> Array:
	return room.host.system("kit").params["pieces"]


func _piece(room: Node3D, piece: String) -> Dictionary:
	for e: Dictionary in _pieces(room):
		if str(e["piece"]) == piece:
			return e
	return {}


func _model_count(room: Node3D, model: String) -> int:
	return (room.host.system("seats").drawn() as Array).filter(func(d: Dictionary) -> bool:
			return d["model"] == model).size()


## 1937: a well-to-do drawing room: a walnut mirror-lid set (the picture the tube's face in its lid's mirror), black
## and white at 405 lines, the Wrong way round setting, a marble fireplace with a coal fire, parquet and a rug, two
## velvet armchairs, a standard lamp, the tea tray on the sideboard.
func _tv_1937(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("1937: a mirror-lid cabinet on the floor, its lid open over the tube", str(t["form"]) == "mirror_lid"
			and t.has("lid") and t.has("tube") and float(t["foot"]) < 0.01)
	check("1937: a valve set's long warm-up (%.0f s)" % float(p.value("warm_up")), p.switch_style() == "valve"
			and float(p.value("warm_up")) >= 8.0)
	check("1937: the set turns the mirror's picture round (Wrong way round off)", not bool(p.value("mirror")))
	room.host.set_setting("wrong_way", true)
	await _play(room, 0.5, STOPPED)
	check("1937: Wrong way round: left and right swapped", bool(p.value("mirror")))
	room.host.set_setting("wrong_way", false)
	await _play(room, 0.5, STOPPED)
	check("1937: black and white broadcast", is_equal_approx(float(p.value("colour")), 0.0)
			and str(p.value("source")) == "broadcast")
	check("1937: Snow from the aerial at its default (%.2f)" % float(p.value("snow")),
			absf(float(p.value("snow")) - 0.16) < 0.01)
	room.host.set_setting("aerial", 0.0)
	await _play(room, 0.5, STOPPED)
	check("1937: Snow at the bottom: a clean picture", float(p.value("snow")) < 0.001)
	room.host.set_setting("aerial", 0.16)
	check("1937: a walnut set, a marble fireplace, parquet", str(b.params["telly_material"]["library"])
			== "walnut_veneer" and str(b.params["surround"]["library"]) == "white_marble"
			and str(b.params["floor"]["library"]) == "herringbone_parquet" and room.get_node_or_null("Fire") != null)
	RoomSound.check_setting(self, "1937", room, "fire", "fire", false, true)
	var board := _piece(room, "sideboard")
	var tea := _piece(room, "tea_set")
	check("1937: the tea tray on the sideboard", not tea.is_empty() and absf(float(tea["at"][1])
			- float(board["size"][1])) < 0.005 and absf(float(tea["at"][0]) - float(board["at"][0])) < 0.01)
	check("1937: a rug, a standard lamp (house group: the ritual dims it)", not _piece(room, "rug").is_empty()
			and room.get_node_or_null("PieceLamps") != null)
	check("1937: three velvet armchairs", _model_count(room, "club_chair") == 3)
	check("1937: no problems placing the pieces", (room.host.system("kit").problems() as Array).is_empty())
	await _lamps("1937", room, 0.25)


## 1966: the rented set on splayed legs, its channel dial, a teak sideboard, an orange settee, orange and teak.
func _tv_1966(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("1966: a console on splayed legs, its doors folded back", str(t["form"]) == "console"
			and t.has("legs") and float(t["foot"]) > 0.3 and bool(b.params["telly_doors"]))
	var body: Vector3 = t["body"][0]
	var outer: Vector3 = t["body"][1]
	var pic: Array = t["pic"]
	var dial := _piece(room, "channel_dial")
	var at := Vector3(float(dial["at"][0]), float(dial["at"][1]), float(dial["at"][2]))
	var r := float(dial["size"][0]) * 0.5
	var side := at.x - float(pic[0].x) - float(pic[1].x) * 0.5
	check("1966: the channel dial on the set's front, in the strip beside the picture (%s)" % at, not dial.is_empty()
			and absf(at.z - float(pic[0].z)) < 0.002 and side > r and at.x + r < body.x + outer.x * 0.5
			and at.y - r * 3.6 > float(t["foot"]) and at.y + r < body.y + outer.y * 0.5)
	check("1966: black and white", is_equal_approx(float(p.value("colour")), 0.0))
	room.host.set_setting("aerial", 0.5)
	await _play(room, 0.5, STOPPED)
	check("1966: Snow from the aerial up (%.2f)" % float(p.value("snow")), absf(float(p.value("snow")) - 0.5) < 0.01)
	room.host.set_setting("aerial", 0.12)
	var board := _piece(room, "sideboard")
	check("1966: a teak sideboard along the wall", not board.is_empty() and float(board["size"][0]) > 1.5)
	check("1966: an orange settee of three, the viewer in its middle, and an armchair", _model_count(room, "settee")
			== 3 and _model_count(room, "club_chair") == 1)
	var cover: Dictionary = room.host.system("seats").params["upholstery"]
	var orange := Color(float(cover["color"][0]), float(cover["color"][1]), float(cover["color"][2]))
	check("1966: the settee orange (%s)" % orange, orange.r > 0.6 and orange.g < orange.r * 0.6 and orange.b < 0.2)
	check("1966: a valve set, a film panned and scanned to fill the tube", p.switch_style() == "valve"
			and str(p.value("aspect_mode")) == "pan_and_scan")
	room.host.set_setting("lamps", 0.6)
	await _lamps("1966", room, 0.6)
	room.host.set_setting("lamps", 0.3)


## 2002: a big deep set filling the end of the lounge, a leather sofa, a glass coffee table under the sight line.
func _tv_2002(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	var body: Vector3 = t["body"][1]
	check("2002: a big deep rear projection set from the floor (%.2f m wide, %.2f m deep)" % [body.x, body.z],
			str(t["form"]) == "rear_projection" and body.x > 1.2 and body.z > 0.6 and float(t["foot"]) < 0.01)
	check("2002: the picture dims seen from off its axis (%.2f)" % float(p.value("off_axis")),
			str(p.value("display")) == "rear_projection" and float(p.value("off_axis")) >= 0.5)
	var cover: Dictionary = room.host.system("seats").params["upholstery"]
	check("2002: a leather sofa of three and an armchair", _model_count(room, "settee") == 3
			and _model_count(room, "club_chair") == 1 and str(cover["library"]).ends_with("leather"))
	var glass := room.get_node_or_null("PieceGlass") as MeshInstance3D
	var table := _piece(room, "glass_table")
	check("2002: a glass coffee table (see-through), low under the sight line", glass != null
			and glass.is_in_group("env_see_through") and float(table["size"][1]) <= 0.45
			and float(table["at"][2]) < -0.5)
	room.host.set_setting("brightness", 0.8)
	await _play(room, 0.5, STOPPED)
	check("2002: Lamp in the set: an old lamp, a dimmer picture (%.2f)" % float(p.value("gain")),
			absf(float(p.value("gain")) - 0.8) < 0.01)
	room.host.set_setting("brightness", 0.95)
	room.host.set_setting("lamps", 0.0)
	await _lamps("2002", room, 0.0)
	room.host.set_setting("lamps", 0.25)


## The present: a thin panel on a dark wall, a media unit and a soundbar under it, a floor lamp by the sofa, rain on
## the window now and then, a clean picture.
func _tv_today(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("today: a very thin OLED panel on the wall (%.2f m deep)" % float(t["body"][1].z), str(t["form"]) == "oled"
			and str(t["stand"]) == "wall" and float(t["body"][1].z) < 0.05)
	var wall: Dictionary = b.params["walls"]
	check("today: dark walls", Color(float(wall["color"][0]), float(wall["color"][1]),
			float(wall["color"][2])).get_luminance() < 0.25)
	var unit := _piece(room, "media_unit")
	var bar := _piece(room, "soundbar")
	var bottom := float(t["pic"][0].y) - float(t["pic"][1].y) * 0.5
	check("today: a soundbar on the media unit under the picture", not unit.is_empty() and not bar.is_empty()
			and absf(float(bar["at"][1]) - float(unit["size"][1])) < 0.005 and float(bar["at"][1])
			+ float(bar["size"][1]) < float(t["foot"]))
	check("today: a clean picture on an OLED, letterboxed, the film's own sound", str(p.value("display")) == "oled"
			and str(p.value("aspect_mode")) == "letterbox" and str(p.value("speaker")) == "none")
	check("today: a floor lamp by the sofa (house group)", not _piece(room, "floor_lamp").is_empty()
			and room.get_node_or_null("PieceLamps") != null and float(room.host.system("light").group_energy("house"))
			> 0.0)
	check("today: no wall lamps, no heater", int(b.params["lamps"]) == 0 and str(b.params["heater"]) == "none")
	RoomSound.check_follows(self, "today", room, "rain", "weather.rain")
	room.host.set_setting("lamp", 0.4)
	await _lamps("today", room, 0.4)
	room.host.set_setting("lamp", 0.15)
	await _lamps("today", room, 0.15)
	check("today: the picture's bottom over the soundbar (%.2f m)" % bottom, bottom > 0.55)
