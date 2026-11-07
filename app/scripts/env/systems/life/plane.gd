extends "res://scripts/env/systems/life/creature.gd"

## A plane's lights crossing a night sky (the Athens rooftop): red on the left wing, green on the right, a white tail
## light and a white strobe that blinks softly every 1.5 s (a 0.3 s swell: far under the photosensitivity ceiling;
## steady with blink off or Flickering lights off). Each plane crosses on a great circle 160 m out (inside the
## camera's 200 m), 17 to 52 degrees up, at about a degree a second, so a crossing takes a minute or two. count: how
## many may be up at once; every: seconds between them on average (75); activity: how much they show (bind it to
## time.of_day, inverted, for night only). pass: one now (args: side, the side it comes from).

const DISTANCE := 160.0
const DEG_PER_S := 1.1
const LIGHT := 0.5
const STROBE_EVERY := 1.5
const STROBE := 0.3
const COLOURS: Array[Color] = [Color(1.0, 0.15, 0.1), Color(0.2, 1.0, 0.35), Color(1.0, 1.0, 0.95),
		Color(1.0, 1.0, 1.0)]

var up := []
var next_plane := 0.0
var _activity := 1.0
## Planes so far (tests).
var flown := 0


static func defaults() -> Dictionary:
	return {"count": 2, "max": 6}


func build() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	multimesh(q, count * 4, glow_material(Color.WHITE, 0), WIDE, "PlaneLights")
	for i in count:
		up.append({})
	next_plane = _gap() * rng.randf()
	_activity = float(life.params["activity"])


func _gap() -> float:
	var every: float = life.every_or(75.0)
	return every * rng.randf_range(0.5, 1.5) if every > 0.0 else INF


func param_changed(param: String) -> void:
	if param == "glow" and material != null:
		material.set_shader_parameter("glow", float(life.params["glow"]))


static func _sky(az: float, el: float) -> Vector3:
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## A plane now, from the given side (-1 left, 1 right, 0 either), along the screen's direction as azimuth 0.
func launch(side := 0) -> bool:
	for i in count:
		if (up[i] as Dictionary).is_empty():
			var f: Vector3 = life.forward()
			var base := atan2(f.x, -f.z)
			var from := float(side if side != 0 else (1 if rng.randf() < 0.5 else -1))
			var az0 := base + from * rng.randf_range(0.6, 1.9)
			var az1 := base - from * rng.randf_range(0.6, 1.9)
			var a := _sky(az0, rng.randf_range(0.3, 0.9))
			var b := _sky(az1, rng.randf_range(0.3, 0.9))
			var angle := a.angle_to(b)
			up[i] = {"a": a, "b": b, "t": 0.0, "seconds": rad_to_deg(angle) / (DEG_PER_S * speed()),
					"strobe": rng.randf() * STROBE_EVERY}
			flown += 1
			return true
	return false


func step(delta: float) -> void:
	_activity = move_toward(_activity, float(life.params["activity"]), delta / 3.0)
	if _activity > 0.05:
		next_plane -= delta
	if next_plane <= 0.0:
		next_plane = _gap()
		launch()
	var blink := bool(life.params["blink"])
	var eye: Vector3 = life.seat_eye()
	for i in count:
		var p: Dictionary = up[i]
		if not p.is_empty():
			p["t"] = float(p["t"]) + delta / float(p["seconds"])
			p["strobe"] = fmod(float(p["strobe"]) + delta, STROBE_EVERY)
			if float(p["t"]) >= 1.0:
				up[i] = {}
				p = {}
		if p.is_empty():
			for k in 4:
				put(i * 4 + k, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO), Color(0, 0, 0, 0),
						Color())
			continue
		var f := float(p["t"])
		var d: Vector3 = (p["a"] as Vector3).slerp(p["b"], f)
		var d2: Vector3 = (p["a"] as Vector3).slerp(p["b"], minf(f + 0.01, 1.0))
		var at := eye + d * DISTANCE
		var heading := (d2 - d).normalized() if (d2 - d).length() > 1e-6 else Vector3.RIGHT
		var right := heading.cross(Vector3.UP).normalized()
		# Fading in at the start and out at the end, as from beyond the haze.
		var edge: float = clampf(minf(f, 1.0 - f) / 0.08, 0.0, 1.0) * _activity * life.fade
		var sp := float(p["strobe"])
		var strobe := 0.5
		if blink:
			var x := clampf(sp / STROBE, 0.0, 1.0)
			strobe = sin(PI * x) * sin(PI * x) if sp < STROBE else 0.0
		var lights := [[at - right * 1.2, 0.9], [at + right * 1.2, 0.9], [at - heading * 1.4, 0.6], [at, strobe]]
		for k in 4:
			var scale := LIGHT * size() * (1.4 if k == 3 else 1.0)
			put(i * 4 + k, Transform3D(Basis.from_scale(Vector3.ONE * scale), lights[k][0]),
					Color(COLOURS[k].r, COLOURS[k].g, COLOURS[k].b, edge), Color(0.0, 0.0, float(lights[k][1]), 0.0))
	flush()


func act(action: String, args: Dictionary) -> bool:
	if action == "pass":
		launch(side_arg(args))
		return true
	return false


func positions() -> Array:
	var out: Array = []
	var eye: Vector3 = life.seat_eye()
	for p: Dictionary in up:
		if not p.is_empty():
			out.append(eye + (p["a"] as Vector3).slerp(p["b"], float(p["t"])) * DISTANCE)
	return out


func radius() -> float:
	return 3.0
