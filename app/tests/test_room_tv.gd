extends "res://tests/env_builder_harness.gd"

## The TV-era rooms (docs/environments.md, "Room: TV 1930" to "Room: TV 2005"): seven living rooms,
## one for each preset of the presentation system's TV eras, each a document over the domestic builder with a telly.
## Each is built headless as it ships and checked: the schema, comfort, licences, names, no people, the headset's
## budget, a clear sight line from every seat; the Television group; the era's preset on a telly; the telly's shape
## (4:3 before 2000, 16:9 for the flat panel) and its size from the viewer's own seat (small, but 17 to 23 degrees
## across); the room's own settings and what each does to its system; the cues (the set warming up, tuning in, a tape
## starting; the lamps down in the film and up after it); the era's own things (a fire, the cat; a radiogram, a
## sideboard, a rug and a standard lamp; a portable on a desk beside a computer; a video recorder under the set
## flashing 12:00 and a settee; a bed and fairy lights; a flat panel on a tv unit, a coffee table; rain on the pane);
## the picture on the set's glass in every room. The 1930, 1953 and 1993 rooms' sound (tests/room_sound.gd): their
## beds on the room's bus, each bound bed on its setting or channel, the tape going in, the level.
## godot --headless --xr-mode off --path app --script res://tests/test_room_tv.gd

const Presentation := preload("res://scripts/env/systems/presentation.gd")
const Domestic := preload("res://scripts/env/systems/domestic.gd")
const Furniture := preload("res://scripts/env/systems/kit/furniture.gd")

## id -> [year, preset, aspect of the tube]
const ROOMS := {
	"tv_1930": [1930, "glowbox_1930", 4.0 / 3.0],
	"tv_1953": [1953, "fireside_1953", 4.0 / 3.0],
	"tv_1972": [1972, "colourstar_1972", 4.0 / 3.0],
	"tv_1983": [1983, "sirclive_1983", 4.0 / 3.0],
	"tv_1987": [1987, "rewinder_1987", 4.0 / 3.0],
	"tv_1993": [1993, "nightowl_1993", 4.0 / 3.0],
	"tv_2005": [2005, "freedtv_2005", 16.0 / 9.0],
}
const EYE := 1.2
## The picture's width from the viewer's own seat, degrees: small sets are small, but the film stays watchable.
const MIN_DEG := 17.0
const MAX_DEG := 23.0

const RoomSound := preload("res://tests/room_sound.gd")
## The rooms' sound beds checked here: id -> {bed: sound}.
const SOUND := {
	"tv_1930": {"fire": "fire", "clock": "clock", "motor": "hum"},
	"tv_1953": {"fire": "fire", "clock": "clock", "rain": "rain_glass", "whine": "tube_whine"},
	"tv_1993": {"radiator": "radiator", "rain": "rain_glass", "vcr": "vcr", "whine": "tube_whine"},
}

const PLAYING := {"open": true, "playing": true, "position": 0.0, "duration": 5400.0}
const STOPPED := {"open": false}


func run_tests() -> void:
	test_name = "test_room_tv"
	var names: Array[String] = []
	for id: String in ROOMS:
		var r := EnvDoc.load_file("res://environments/%s.env.json" % id)
		check("%s: the document reads %s" % [id, r["errors"]], (r["errors"] as Array).is_empty())
		var doc: Dictionary = r["doc"]
		if doc.is_empty():
			continue
		names.append(str(doc["name"]))
		check("%s: named for its year (%s)" % [id, doc["name"]], str(doc["name"]).begins_with("TV %d - "
				% ROOMS[id][0]))
		check("%s: in the Television group" % id, str(doc["room"].get("category", "")) == "tv")
		var room := await _built(id, doc)
		await _common(id, room, doc)
		match id:
			"tv_1930":
				await _tv_1930(room)
			"tv_1953":
				await _tv_1953(room)
			"tv_1972":
				await _tv_1972(room)
			"tv_1983":
				await _tv_1983(room)
			"tv_1987":
				await _tv_1987(room)
			"tv_1993":
				await _tv_1993(room)
			"tv_2005":
				await _tv_2005(room)
		if SOUND.has(id):
			_sound(id, room)
		await done(room)
		if SOUND.has(id):
			await RoomSound.check_level(self, self, id, doc)
	var sorted := names.duplicate()
	sorted.sort()
	check("the names sort by year, so the group reads as a timeline %s" % [names], sorted == names)


## The room built as it ships and checked as test_environments.gd checks it: the static checks, the headset's budget
## (measured), a clear sight line from every seat. (The harness's check_room also compares the seats listed before the
## build with the built room's; the seats system's own places exist only once it is built, so these rooms, whose
## armchairs are its places, list only the builder's seats before then.)
func _built(label: String, doc: Dictionary) -> Node3D:
	var s := EnvChecks.static_checks(doc)
	for k: String in s:
		check("%s: %s %s" % [label, k, s[k]], (s[k] as Array).is_empty())
	var room: Node3D = EnvRoom.new()
	room.doc = doc
	root.add_child(room)
	await process_frame
	var stats := EnvChecks.measure(room)
	figures.append([label, stats])
	var over := EnvChecks.budget(stats)
	check("%s: within the headset's budget %s %s" % [label, stats, over], over.is_empty())
	check("%s: well inside it (at most 30 draws, 1000 particles)" % label, int(stats["draws"]) <= 30
			and int(stats["particles"]) <= 1000)
	var blocked: Array = await EnvChecks.sight_line(self, room)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("%s: a clear sight line from every seat (%d seats) %s" % [label, seats.size(), blocked], blocked.is_empty())
	return room


## What every TV room has: the domestic builder with a telly, the era's preset, the telly's shape and size, the
## viewer's own seat at the origin, object physics.
func _common(id: String, room: Node3D, doc: Dictionary) -> void:
	var b: Node = room.host.system("room")
	var p: Node = room.host.system("presentation")
	check("%s: a domestic room and a presentation" % id, b != null and p != null and p.get_script() == Presentation)
	if b == null or p == null:
		return
	check("%s: the telly" % id, str(b.params["screen"]) == "telly" and room.get_node_or_null("Telly") != null)
	check("%s: the era's preset (%s)" % [id, p.params["preset"]], str(p.params["preset"]) == ROOMS[id][1])
	check("%s: a picture stage on (the film drawn on the telly)" % id, p.picture_on())
	var sc: Dictionary = b.screen()
	var size := Vector2(float(sc["size"][0]), float(sc["size"][1]))
	var c := Vector3(float(sc["center"][0]), float(sc["center"][1]), float(sc["center"][2]))
	var ds: Dictionary = doc["screen"]
	check("%s: the document's screen is the telly's (%s, %s)" % [id, ds, sc], c.is_equal_approx(Vector3(
			float(ds["center"][0]), float(ds["center"][1]), float(ds["center"][2]))) and size.is_equal_approx(
			Vector2(float(ds["size"][0]), float(ds["size"][1]))))
	check("%s: the tube's shape (%.3f)" % [id, size.aspect()], absf(size.aspect() - float(ROOMS[id][2])) < 0.01)
	var why := telly_glass(room, sc)
	check("%s: the picture on the set's glass %s" % [id, why], why == "")
	var deg := rad_to_deg(2.0 * atan(size.x * 0.5 / -c.z))
	check("%s: %.2f m wide at %.2f m: %.1f degrees from the viewer's seat" % [id, size.x, -c.z, deg],
			deg >= MIN_DEG and deg <= MAX_DEG)
	check("%s: the picture a little under the eyes (centre %.2f m)" % [id, c.y], c.y < EYE and c.y > 0.85)
	var seats: Array[Transform3D] = room.room_seat_transforms()
	check("%s: the viewer's own seat at the origin, facing the telly" % id, seats.any(
			func(s: Transform3D) -> bool: return s.origin.length() < 0.05))
	check("%s: every seat in front of the telly, at least 0.7 m away" % id, seats.all(
			func(s: Transform3D) -> bool: return s.origin.z > c.z + 0.7))
	check("%s: object physics (%d shapes)" % [id, room.collision_shapes().size()], room.collision_shapes().size() > 8)
	room.host.auto = false


## A one-shot bed's plays so far.
func _plays(room: Node3D, bed: String) -> int:
	return int(room.host.system(bed).get("plays"))


func _play(room: Node3D, seconds: float, snap := PLAYING) -> void:
	room.host.snapshot_override = snap
	var t := 0.0
	while t < seconds:
		room.host.step(0.1)
		t += 0.1


func _p(room: Node3D) -> Node:
	return room.host.system("presentation")


## The highest (or lowest) value a presentation parameter takes over the next second and a half.
func _extreme(room: Node3D, param: String, highest: bool) -> float:
	var v := float(_p(room).value(param))
	for i in 30:
		room.host.step(0.05)
		var now := float(_p(room).value(param))
		v = maxf(v, now) if highest else minf(v, now)
	return v


## The lamps go down in the film and come up after it.
func _lamps(id: String, room: Node3D, down: float) -> void:
	await _play(room, 1.0, STOPPED)
	await _play(room, 5.0)
	var lamps := float(room.host.param("light.house_lamps"))
	check("%s: the lamps down in the film (%.2f)" % [id, lamps], absf(lamps - down) < 0.02)
	await _play(room, 9.0, {"open": true, "playing": false, "position": 0.0, "duration": 5400.0, "ended": true})
	lamps = float(room.host.param("light.house_lamps"))
	check("%s: and up again after it (%.2f)" % [id, lamps], lamps > 0.98)


## 1930: a mechanical set's orange glow, 30 lines (or more by the setting), a coal fire, tuning in.
func _tv_1930(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	check("1930: thirty lines as it was", int(p.value("mech_lines")) == 30 and str(p.value("display")) == "mechanical")
	room.host.set_setting("lines", "sharpest")
	await _play(room, 0.5, STOPPED)
	check("1930: Lines in the picture: 120 (%s)" % p.value("mech_lines"), int(p.value("mech_lines")) == 120)
	room.host.set_setting("lines", "as_it_was")
	check("1930: a fireplace, its fire lit", room.get_node_or_null("Fire") != null and float(b.params["fire"]) > 0.9)
	room.host.set_setting("fire", false)
	await _play(room, 8.0, STOPPED)
	check("1930: Fire in the grate off: the grate cold (%.2f)" % float(b.params["fire"]), float(b.params["fire"]) < 0.05)
	room.host.set_setting("fire", true)
	await _play(room, 1.0, STOPPED)
	room.host.snapshot_override = PLAYING
	var most := _extreme(room, "weak", true)
	check("1930: tuning in, the signal weak at the start (%.2f)" % most, most > 0.9)
	await _play(room, 8.0)
	check("1930: then the set's own (%.2f)" % float(p.value("weak")), absf(float(p.value("weak")) - 0.2) < 0.02)
	await _lamps("1930", room, 0.15)
	check("1930: three club chairs", room.room_seat_transforms().size() == 3)


## 1953: a black and white set by the fire, the family's armchairs round it, the cat on the hearth, rain at the window.
func _tv_1953(room: Node3D) -> void:
	var p := _p(room)
	check("1953: black and white, 405-line broadcast", is_equal_approx(float(p.value("colour")), 0.0)
			and str(p.value("source")) == "broadcast")
	check("1953: Aerial noise at its default (%.2f)" % float(p.value("snow")), absf(float(p.value("snow")) - 0.22) < 0.01)
	room.host.set_setting("aerial", 0.0)
	await _play(room, 0.5, STOPPED)
	check("1953: Aerial noise at the bottom: a clean picture (%.2f)" % float(p.value("snow")), float(p.value("snow")) < 0.001)
	room.host.set_setting("aerial", 0.22)
	check("1953: four armchairs round the set", room.room_seat_transforms().size() == 4)
	var cat: Node = room.host.system("cat")
	check("1953: the cat", cat != null and str(cat.params["creature"]) == "cat")
	var w: Node = room.host.system("weather")
	check("1953: rain on the pane, falling outside the window", w != null and bool(w.params["pane"])
			and not (w.params["areas"] as Array).is_empty())
	check("1953: an evening sky and hills beyond the window", room.host.system("sky") != null
			and room.host.system("vista") != null and room.get_node_or_null("Window") != null)
	room.host.snapshot_override = PLAYING
	var least := _extreme(room, "gain", false)
	check("1953: the set warms up: dim at first (%.2f)" % least, least < 0.6)
	await _play(room, 9.0)
	check("1953: then full (%.2f)" % float(p.value("gain")), absf(float(p.value("gain")) - 1.0) < 0.01)
	await _lamps("1953", room, 0.25)


## 1972: an early colour set, the colour knob, 1970s bands on the wall and a swirling carpet.
func _tv_1972(room: Node3D) -> void:
	var p := _p(room)
	check("1972: colour on a shadow mask", str(p.value("mask")) == "shadow" and absf(float(p.value("colour")) - 1.15) < 0.01)
	room.host.set_setting("colour", 0.5)
	await _play(room, 0.5, STOPPED)
	check("1972: the Colour knob turned down (%.2f)" % float(p.value("colour")), absf(float(p.value("colour")) - 0.5) < 0.01)
	room.host.set_setting("colour", 1.15)
	room.host.set_setting("aerial", 0.4)
	await _play(room, 0.5, STOPPED)
	check("1972: Aerial noise up (%.2f)" % float(p.value("snow")), absf(float(p.value("snow")) - 0.4) < 0.01)
	room.host.set_setting("aerial", 0.06)
	var kit: Node = room.host.system("kit")
	var names := (kit.params["pieces"] as Array).map(func(e: Dictionary) -> String: return str(e["piece"]))
	check("1972: the bands, the carpet, a rug, a sideboard, a standard lamp %s" % [names], names == ["carpet", "curves",
			"rug", "sideboard", "standard_lamp"] and (kit.problems() as Array).is_empty())
	check("1972: the set on a radiogram", str(room.host.system("room").params["telly_stand"]) == "radiogram")
	var shade := room.get_node_or_null("PieceLamps") as MeshInstance3D
	check("1972: the standard lamp's shade glows (house group: the ritual dims it)", shade != null
			and float(room.host.system("light").group_energy("house")) > 0.0)
	check("1972: a bean bag beside three club chairs", room.room_seat_transforms().size() == 4)
	await _lamps("1972", room, 0.3)
	await sounds("1972", room, {"radiator": "radiator", "clock": "clock", "whine": "tube_whine"})


## 1983: a portable telly on a desk beside a home computer, the aerial lead's noise, bold lines.
func _tv_1983(room: Node3D) -> void:
	var p := _p(room)
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("1983: a portable on a desk", str(t["form"]) == "portable" and str(t["stand"]) == "desk")
	var desk: Transform3D = b.slots()["telly_stand"][0]["transform"]
	check("1983: the telly stands on the desk (desk %.3f, the telly's foot %.3f)" % [desk.origin.y, float(t["foot"])],
			absf(desk.origin.y - float(t["foot"])) < 0.001 and desk.origin.y > 0.7 and desk.origin.y < 0.78)
	var kit: Node = room.host.system("kit")
	var pc: Dictionary = kit.params["pieces"][0]
	check("1983: the computer on the desk, the telly its screen (no monitor)", str(pc["piece"]) == "computer"
			and str(pc["slot"]) == "telly_stand" and str(pc["holds"]) == "none" and (kit.problems() as Array).is_empty())
	var boxes: Array = kit.collision_shapes()
	var on_desk := boxes.any(func(sh: Array) -> bool: return absf((sh[1] as Transform3D).origin.y - (desk.origin.y
			+ 0.055)) < 0.01)
	check("1983: its case's box on the desk's top (%d boxes)" % boxes.size(), on_desk)
	check("1983: bold lines", absf(float(p.value("scanlines")) - 0.65) < 0.01)
	room.host.set_setting("bold_lines", false)
	await _play(room, 0.5, STOPPED)
	check("1983: Bold lines off (%.2f)" % float(p.value("scanlines")), absf(float(p.value("scanlines")) - 0.2) < 0.01)
	room.host.set_setting("bold_lines", true)
	room.host.snapshot_override = PLAYING
	room.host.step(0.1)
	room.host.step(0.1)
	check("1983: the set tunes in to the computer's channel (a glitch)", float(p.get("_glitch")) > 0.5)
	check("1983: a desk chair and a bean bag", room.room_seat_transforms().size() == 2)
	await sounds("1983", room, {"rain": "rain_glass", "tape": "tape_load", "whine": "tube_whine"})
	var w: Node = room.host.system("weather")
	await _play(room, 20.0, STOPPED)
	check("1983: rain on the glass as loud as the rain (%.2f, the weather's %.2f)" % [
			float(room.host.system("rain").params["level"]), w.rain_amount()],
			absf(float(room.host.system("rain").params["level"]) - w.rain_amount()) < 0.1 and w.rain_amount() > 0.1)
	var loads := _plays(room, "tape")
	await _play(room, 2.0)
	await _play(room, 4.0, STOPPED)
	check("1983: back in the pre-show, the computer loads from its cassette (%d plays)" % _plays(room, "tape"),
			_plays(room, "tape") > loads)


## 1987: the family telly, a video recorder under it, a rented tape.
func _tv_1987(room: Node3D) -> void:
	var p := _p(room)
	check("1987: a tape with tracking wobble", str(p.value("source")) == "tape" and float(p.value("tracking")) > 0.3)
	check("1987: the tape rented (%.2f)" % float(p.value("tape_noise")), absf(float(p.value("tape_noise")) - 0.4) < 0.01)
	room.host.set_setting("tape", "worn")
	await _play(room, 0.5, STOPPED)
	check("1987: a worn tape: more noise, the tear at the bottom", absf(float(p.value("tape_noise")) - 0.75) < 0.01
			and absf(float(p.value("head_switch")) - 1.0) < 0.01)
	room.host.set_setting("tape", "rented")
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	var shelf: Transform3D = b.slots()["telly_shelf"][0]["transform"]
	var vcr: Dictionary = room.host.system("kit").params["pieces"][1]
	check("1987: the video recorder in the tv unit's shelf under the telly (%.3f, the set's foot %.3f)" % [
			shelf.origin.y, float(t["foot"])], str(t["stand"]) == "tv_unit" and str(vcr["piece"]) == "video_recorder"
			and str(vcr["slot"]) == "telly_shelf" and shelf.origin.y > 0.3 and shelf.origin.y + 0.09
			< float(t["foot"]) - Furniture.TOP_T + 0.001)
	await clock_flashes("1987", room)
	var drawn: Array = room.host.system("seats").drawn()
	var settee := drawn.filter(func(d: Dictionary) -> bool: return d["model"] == "settee")
	check("1987: a settee of three places, the viewer's in the middle, and an armchair (%d, %d)" % [settee.size(),
			drawn.size()], settee.size() == 3 and drawn.size() == 4 and settee.any(func(d: Dictionary) -> bool:
			return (d["xf"] as Transform3D).origin.length() < 0.05) and room.get_node_or_null("SeatEnds") != null)
	room.host.snapshot_override = PLAYING
	room.host.step(0.1)
	room.host.step(0.1)
	check("1987: the tape goes in first, no tear yet (%.2f)" % float(p.get("_glitch")), float(p.get("_glitch")) < 0.01)
	for i in 26:
		room.host.step(0.1)
	check("1987: then the picture starts with a tear (%.2f)" % float(p.get("_glitch")), float(p.get("_glitch")) > 1.0)
	room.host.set_setting("lamps", 0.5)
	await _lamps("1987", room, 0.5)
	room.host.set_setting("lamps", 0.3)
	await _lamps("1987", room, 0.3)
	await sounds("1987", room, {"vcr": "vcr", "clock": "clock", "whine": "tube_whine", "fire": "fire",
			"rain": "rain_glass"})
	var takes := _plays(room, "vcr")
	await _play(room, 2.0, STOPPED)
	await _play(room, 1.0)
	check("1987: the tape goes in as the film starts (%d plays)" % _plays(room, "vcr"), _plays(room, "vcr") > takes)


## 1993: a teenager's bedroom: no fort, fairy lights, a bean bag and the bed, rain or not.
func _tv_1993(room: Node3D) -> void:
	var b: Node = room.host.system("room")
	check("1993: a bedroom without the pillow fort", room.get_node_or_null("Fort") == null
			and room.get_node_or_null("Bed") != null and room.get_node_or_null("FairyLights") != null)
	check("1993: a bean bag and a place on the bed", room.room_seat_transforms().size() == 2
			and room.room_seat_transforms().any(func(s: Transform3D) -> bool: return s.origin.y > 0.4))
	var w: Node = room.host.system("weather")
	room.host.set_setting("weather", "clear")
	await _play(room, 0.5, STOPPED)
	check("1993: Weather clear (%s)" % w.params["mode"], str(w.params["mode"]) == "clear")
	room.host.set_setting("weather", "rain")
	await _play(room, 0.5, STOPPED)
	check("1993: Weather rain (%s)" % w.params["mode"], str(w.params["mode"]) == "heavy")
	room.host.set_setting("weather", "changing")
	var bulbs := (room.get_node("FairyLights") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var lit := float(bulbs.get_shader_parameter("energy"))
	room.host.set_setting("fairy", 0.0)
	await _play(room, 4.0, STOPPED)
	var off := float(bulbs.get_shader_parameter("energy"))
	check("1993: Fairy lights at the bottom: off (glow %.3f, the bulbs %.3f from %.3f)" % [
			float(b.params["fairy_glow"]), off, lit], float(b.params["fairy_glow"]) < 0.02 and off < 0.02 and lit > 0.5)
	check("1993: and nothing else dims with them (the accent group %.2f)" % float(room.host.param("light.accent")),
			float(room.host.param("light.accent")) > 0.99)
	room.host.set_setting("fairy", 0.7)
	await _play(room, 4.0, STOPPED)
	check("1993: Fairy lights back (glow %.2f)" % float(b.params["fairy_glow"]),
			absf(float(b.params["fairy_glow"]) - 1.05) < 0.02)
	check("1993: no lamps of its own to dim", int(b.params["lamps"]) <= 0)


## 2005: an early flat panel on a stand, a 16:9 picture, the backlight's bleed.
func _tv_2005(room: Node3D) -> void:
	var p := _p(room)
	check("2005: a flat panel", str(p.value("display")) == "panel")
	var b: Node = room.host.system("room")
	var t: Dictionary = Domestic._telly(Domestic.resolved(b.params))
	check("2005: the set itself a thin flat panel on a pedestal on a tv unit (%.2f m deep)" % float(t["body"][1].z),
			str(t["form"]) == "flat_panel" and str(t["stand"]) == "tv_unit" and bool(t["pedestal"])
			and float(t["body"][1].z) < 0.1)
	var pieces: Array = room.host.system("kit").params["pieces"]
	check("2005: a coffee table in front of the settee", pieces.any(func(e: Dictionary) -> bool:
			return str(e["piece"]) == "coffee_table" and float(e["at"][2]) < -0.5))
	var drawn: Array = room.host.system("seats").drawn()
	check("2005: a settee of three and an armchair", drawn.filter(func(d: Dictionary) -> bool:
			return d["model"] == "settee").size() == 3 and drawn.size() == 4)
	room.host.set_setting("backlight", 0.0)
	await _play(room, 0.5, STOPPED)
	check("2005: Backlight bleed off (%.2f)" % float(p.value("panel_bleed")), float(p.value("panel_bleed")) < 0.001)
	room.host.set_setting("backlight", 0.5)
	room.host.set_setting("lamps", 0.0)
	await _lamps("2005", room, 0.0)
	room.host.set_setting("lamps", 0.3)
	await sounds("2005", room, {})


## The room's sound (docs/environments.md, "Sound and music", "For the rooms"): its beds on the room's bus, a small
## room's acoustics, the fire on the Fire setting, rain on the glass with the weather's rain, the tube's whine at the
## era's line pitch (none for the 1930 disc), the tape going in as the film starts.
func _sound(id: String, room: Node3D) -> void:
	var h: Node = room.host
	RoomSound.check_beds(self, id, room, SOUND[id], "small_room")
	if h.system("fire") != null:
		RoomSound.check_setting(self, id, room, "fire", "fire", false, true)
	if h.system("rain") != null:
		RoomSound.check_follows(self, id, room, "rain", "weather.rain")
	var whine: Node = h.system("whine")
	if id == "tv_1953":
		check("1953: the tube's whine at a 405-line set's pitch, low (%.3f, %.0f dB)" % [float(whine.params["pitch"]),
				float(whine.params["gain_db"])], is_equal_approx(float(whine.params["pitch"]), 0.648)
				and float(whine.params["gain_db"]) < 0.0)
	if id == "tv_1993":
		check("1993: the tube's whine at 625 lines (%.3f)" % float(whine.params["pitch"]),
				is_equal_approx(float(whine.params["pitch"]), 1.0))
		var vcr: Node = h.system("vcr")
		h.set_setting("ritual", true)
		_play(room, 1.0, STOPPED)
		var v0: int = vcr.plays
		_play(room, 2.0)
		check("1993: the film starts: the tape goes in (%d, %s)" % [vcr.plays - v0, h.timeline.state],
				vcr.plays - v0 == 1)
		_play(room, 1.0, STOPPED)
