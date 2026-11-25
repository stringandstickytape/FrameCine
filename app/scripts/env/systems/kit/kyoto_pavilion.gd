extends RefCounted

## Kyoto garden pavilion kit (Cozy retreats: app/environments/kyoto_pavilion.env.json;
## docs/environments/rooms/kyoto_pavilion.md).
## A serene traditional hinoki-cypress engawa pavilion open on three sides to a lantern-lit Kyoto night garden with
## animated koi pond, raked Zen gravel, arched vermilion footbridge, carved granite yukimi-doro stone lanterns,
## bamboo shishi-odoshi water basin, backlit sliding shoji screens, recessed tokonoma alcove, and seasonal weeping
## cherry / Japanese maple trees.
##
## Pieces (pieces.gd dispatches here):
##   kyoto_engawa   raised timber pavilion inlaid with procedural tatami_weave matting and warm hinoki verandah planks,
##                  slender square hinoki posts, cantilevered timber eave ceiling with exposed parallel rafters (taruki)
##                  and upturned smoked-clay kawara roof eaves, aft backlit rice-paper sliding shoji screens with fine
##                  dark-cedar kumiko lattice mullions, recessed tokonoma display alcove with ceramic ikebana vase and
##                  minimalist hanging scroll, low lacquered chabudai tea table with kyusu teapot and matcha cups, four
##                  square hinoki-and-washi andon floor lanterns, and a freestanding dark-cypress torii/pavilion garden
##                  frame cradling the cinema screen across the far edge of the koi pond.
##   kyoto_garden   surrounding lantern-lit Kyoto night garden and KyotoGardenHall (c.halls):
##                  - KyotoPondWater (env_world_water.gdshader, opaque 1 draw): animated mirror-emerald koi pond
##                    wrapping past the front and starboard engawa, rimmed with mossy boulders, lily pads, and stepping
##                    stones, plus smooth pond-level guidance & Nishikigoi tinting for the 18 living koi (life fish).
##                  - Curved vermilion-lacquered wooden garden footbridge (taiko-bashi) with gleaming brass giboshi
##                    finials, three carved granite yukimi-doro snow-viewing stone lanterns, port bamboo shishi-odoshi
##                    water-clack basin (with live tipping BambooRocker), raked karesansui Zen gravel courtyard with
##                    mossy sanzon-seki feature rocks, tsukiji-bei plaster-and-tile garden enclosure wall, bamboo groves,
##                    sculpted weeping cherry / Japanese maple trees with live seasonal canopy tinting (KyotoCanopy),
##                    and distant moonlit Higashiyama mountain ridges (KyotoHills).

const RoomMesh := preload("res://scripts/env/room_mesh.gd")
const Shapes := preload("res://scripts/env/systems/kit/shapes.gd")
const Procedural := preload("res://scripts/env/systems/kit/procedural.gd")
const PhysicsShapes := preload("res://scripts/play/physics_shapes.gd")
const SkySys := preload("res://scripts/env/systems/sky.gd")
const WATER_SHADER := preload("res://shaders/env_world_water.gdshader")

## Floor, verandah, pond, and ground heights (metres; viewer sits dead-centre at (0, 0, 0) facing -Z).
const TATAMI_Y := 0.0
const ENGAWA_Y := -0.022
const WATER_Y := -0.46
const GRAVEL_Y := -0.45
const GROUND_Y := -0.49
const EAVE_BEAM_Y := 3.34
const RIDGE_Y := 4.58

## Tatami and engawa verandah bounds (strictly non-overlapping for zero Z-fighting).
const TATAMI_X := 2.30
const TATAMI_Z0 := -1.18
const TATAMI_Z1 := 2.72
const ENGAWA_X := 3.20
const ENGAWA_Z0 := -2.38
const ENGAWA_Z1 := 2.94
const SHOJI_Z := 2.84

## Cinema screen geometry (matches app/environments/kyoto_pavilion.env.json).
const SCREEN_C := Vector3(0.0, 2.25, -8.40)
const SCREEN_W := 5.00
const SCREEN_H := 2.81

## Garden landmarks.
const SPOUT_AT := Vector3(-4.25, GRAVEL_Y, -1.65)
const BRIDGE_X := 5.65
const BRIDGE_Z0 := -3.85
const BRIDGE_Z1 := 0.55
const BRIDGE_W := 1.32
const BRIDGE_CROWN_Y := 0.50

## Four andon corner floor lanterns on the engawa verandah and three granite yukimi-doro lanterns by the pond.
const ANDON_POS: Array[Vector3] = [
	Vector3(-2.68, ENGAWA_Y, -1.96),
	Vector3(2.68, ENGAWA_Y, -1.96),
	Vector3(-2.68, ENGAWA_Y, 2.32),
	Vector3(2.68, ENGAWA_Y, 2.32),
]
const YUKIMI_POS: Array[Vector3] = [
	Vector3(-4.55, WATER_Y, -5.85),
	Vector3(4.85, WATER_Y, -6.25),
	Vector3(7.55, WATER_Y, 1.55),
]
## Four sculptural cherry / maple trees framing the garden corners (strictly clear of the screen sight line).
const TREE_SPECS: Array = [
	# [base_pos, lean_dir, height, crown_radius, yaw_deg, seed]
	[Vector3(-6.35, GROUND_Y, -6.45), Vector3(0.55, 0.0, 0.25), 4.6, 2.45, 22.0, 101],
	[Vector3(6.75, GROUND_Y, -6.55), Vector3(-0.50, 0.0, 0.22), 4.8, 2.55, 148.0, 207],
	[Vector3(8.55, GROUND_Y, -1.65), Vector3(-0.62, 0.0, 0.08), 4.9, 2.70, 236.0, 313],
	[Vector3(-8.35, GROUND_Y, 2.55), Vector3(0.45, 0.0, -0.35), 4.5, 2.40, 310.0, 419],
]

## Palette (sRGB; helper _lin converts cleanly to linear for tinted house materials).
const HINOKI_WARM := Color(0.68, 0.50, 0.30)
const HINOKI_DECK := Color(0.48, 0.32, 0.18)
const CEDAR_DARK := Color(0.24, 0.16, 0.10)
const CEDAR_DEEP := Color(0.15, 0.10, 0.068)
const LACQUER_DARK := Color(0.18, 0.072, 0.048)
const VERMILION := Color(0.58, 0.095, 0.055)
const VERMILION_DARK := Color(0.42, 0.070, 0.045)
const TATAMI_TINT := Color(0.68, 0.66, 0.46)
const KAWARA_TILE := Color(0.16, 0.17, 0.20)
const KAWARA_RIDGE := Color(0.24, 0.25, 0.29)
const PLASTER_EARTHEN := Color(0.66, 0.60, 0.50)
const PLASTER_TOKO := Color(0.54, 0.49, 0.40)
const GRANITE_LIGHT := Color(0.56, 0.55, 0.52)
const GRANITE_MID := Color(0.38, 0.39, 0.37)
const GRANITE_WET := Color(0.22, 0.25, 0.23)
const MOSS_GREEN := Color(0.16, 0.28, 0.14)
const MOSS_BRIGHT := Color(0.24, 0.38, 0.18)
const GRAVEL_PALE := Color(0.78, 0.77, 0.73)
const GRAVEL_SHADE := Color(0.42, 0.43, 0.42)
const BAMBOO_GREEN := Color(0.26, 0.44, 0.20)
const BAMBOO_NODE := Color(0.46, 0.56, 0.32)
const BAMBOO_LEAF := Color(0.18, 0.34, 0.15)
const BARK_DARK := Color(0.18, 0.13, 0.10)
const LILY_PAD := Color(0.15, 0.34, 0.16)
const LOTUS_PINK := Color(0.92, 0.68, 0.76)
const BRASS_GOLD := Color(0.88, 0.70, 0.30)
const WASHI_CREAM := Color(0.96, 0.90, 0.76)
const WASHI_LAMP := Color(1.0, 0.80, 0.48)
const MATCHA_JADE := Color(0.26, 0.48, 0.20)
const CELADON := Color(0.52, 0.62, 0.56)
const INDIGO_SILK := Color(0.13, 0.19, 0.34)
const BACKING_CHARCOAL := Color(0.035, 0.038, 0.045)

## Nishikigoi per-fish colour palette (vermilion-orange Kohaku, yamabuki gold, ivory platinum, calico orange-gold).
const KOI_TINTS: Array[Color] = [
	Color(1.00, 0.34, 0.12), # bright Kohaku vermilion-orange
	Color(1.00, 0.76, 0.18), # Yamabuki Ogon gold
	Color(0.98, 0.95, 0.88), # Platinum Ogon ivory
	Color(0.96, 0.44, 0.14), # Hi Utsuri flame orange
	Color(0.98, 0.62, 0.16), # Kin Matsuba amber-gold
	Color(0.94, 0.28, 0.10), # Beni deep crimson-orange
]


## Live Kyoto garden hall (registered in c.halls): drives animated mirror-emerald koi pond water, seasonal cherry/maple
## canopy tinting & falling petals hue, moonlit Higashiyama hills, pivoting bamboo shishi-odoshi arm, and graceful
## pond-clamped multi-colour swimming Nishikigoi.
class KyotoGardenHall:
	var kit: Node
	var water_mat: ShaderMaterial
	var canopy_mat: ShaderMaterial
	var hills_mat: StandardMaterial3D
	var water_mi: MeshInstance3D
	var canopy_mi: MeshInstance3D
	var hills_mi: MeshInstance3D
	var rocker_node: Node3D

	var water_clock := 0.0
	var _season_cur := Color(1.0, 0.78, 0.85)
	var _petal_cur := Color(1.0, 0.78, 0.86)
	var _glint_cur := Color(0.95, 0.78, 0.48)
	var _caustic_cur := Color(0.32, 0.58, 0.44)
	var _caustic_lvl := 0.18
	var _glint_lvl := 0.22
	var _sky_refl_cur := Color(0.045, 0.135, 0.145)
	var _inited := false

	## Shishi-odoshi bamboo rocker animation state (reacts smoothly to spout.plays).
	var _last_spout_plays := -1
	var _rock_timer := -1.0

	## Koi pond initialization flag (flattens 3D school slots cleanly onto the koi pond plane once).
	var _koi_init := false

	func finish(k: Node) -> void:
		kit = k
		_build_pond_water(k)
		_build_canopy(k)
		_build_hills(k)
		_build_bamboo_rocker(k)
		tick(0.0)

	func tick(delta: float) -> void:
		if kit == null:
			return
		var host: Node = kit.host
		var motion := 1.0
		var season := "sakura"
		var lanterns := "washi"
		if host != null and host.has_method("setting"):
			var mv: Variant = host.setting("motion")
			if mv != null:
				motion = clampf(float(mv), 0.0, 1.0)
			var sv: Variant = host.setting("season")
			if sv != null and str(sv) != "":
				season = str(sv)
			var lv: Variant = host.setting("lanterns")
			if lv != null and str(lv) != "":
				lanterns = str(lv)

		water_clock += delta * motion

		# 1. Seasonal canopy & drifting petal colour targets (Sakura pink / Autumn maple crimson-gold / Summer emerald).
		var t_canopy: Color
		var t_petal: Color
		match season:
			"maple":
				t_canopy = Color(0.98, 0.35, 0.14)
				t_petal = Color(0.96, 0.42, 0.16)
			"summer":
				t_canopy = Color(0.24, 0.56, 0.28)
				t_petal = Color(0.75, 0.92, 0.65)
			_: # sakura
				t_canopy = Color(1.0, 0.76, 0.84)
				t_petal = Color(1.0, 0.80, 0.88)

		# 2. Lantern mood targets for deep mirror-emerald koi pond reflections.
		var t_glint: Color
		var t_caustic: Color
		var t_caustic_lvl: float
		var t_glint_lvl: float
		var t_sky_refl: Color
		match lanterns:
			"moonlight":
				t_glint = Color(0.72, 0.88, 1.0)
				t_caustic = Color(0.24, 0.54, 0.76)
				t_caustic_lvl = 0.20
				t_glint_lvl = 0.26
				t_sky_refl = Color(0.058, 0.145, 0.245)
			"dim":
				t_glint = Color(0.56, 0.46, 0.32)
				t_caustic = Color(0.16, 0.32, 0.28)
				t_caustic_lvl = 0.10
				t_glint_lvl = 0.10
				t_sky_refl = Color(0.030, 0.075, 0.095)
			_: # washi
				t_glint = Color(0.95, 0.78, 0.48)
				t_caustic = Color(0.32, 0.58, 0.44)
				t_caustic_lvl = 0.18
				t_glint_lvl = 0.22
				t_sky_refl = Color(0.045, 0.135, 0.145)

		var k := 1.0 if (not _inited or delta <= 0.0) else clampf(1.0 - exp(-delta / 1.4), 0.0, 1.0)
		_inited = true
		_season_cur = _season_cur.lerp(t_canopy, k)
		_petal_cur = _petal_cur.lerp(t_petal, k)
		_glint_cur = _glint_cur.lerp(t_glint, k)
		_caustic_cur = _caustic_cur.lerp(t_caustic, k)
		_caustic_lvl = lerpf(_caustic_lvl, t_caustic_lvl, k)
		_glint_lvl = lerpf(_glint_lvl, t_glint_lvl, k)
		_sky_refl_cur = _sky_refl_cur.lerp(t_sky_refl, k)

		if canopy_mat != null:
			canopy_mat.set_shader_parameter("tint", _season_cur)
		if canopy_mi != null and is_instance_valid(canopy_mi):
			canopy_mi.set_meta("season", season)
			canopy_mi.set_meta("canopy_tint", _season_cur)

		if water_mat != null:
			water_mat.set_shader_parameter("clock", water_clock)
			water_mat.set_shader_parameter("sky_colour", _sky_refl_cur)
			water_mat.set_shader_parameter("caustic_colour", _caustic_cur)
			water_mat.set_shader_parameter("caustic_level", _caustic_lvl)
			water_mat.set_shader_parameter("glint_colour", _glint_cur)
			water_mat.set_shader_parameter("glint_level", _glint_lvl)
		if water_mi != null and is_instance_valid(water_mi):
			water_mi.set_meta("clock", water_clock)
			water_mi.set_meta("lanterns", lanterns)

		# Sync drifting petal shader colour with season (pink sakura petals -> crimson-gold autumn maple leaves).
		if host != null:
			var petals: Node = host.system("petals")
			if petals != null and petals.has_method("fall_material"):
				var fm: ShaderMaterial = petals.fall_material()
				if fm != null:
					fm.set_shader_parameter("colour", _petal_cur)

		# 3. Animate the bamboo shishi-odoshi rocker arm when the bamboo_clack sound plays.
		_sync_rocker(host, delta, motion)

		# 4. Keep the 18 living koi gliding cleanly inside the shallow koi pond water in vivid Nishikigoi colours.
		_sync_koi(host, lanterns)

	func _sync_rocker(host: Node, delta: float, motion: float) -> void:
		if rocker_node == null or not is_instance_valid(rocker_node):
			return
		var plays := 0
		if host != null:
			var spout: Node = host.system("spout")
			if spout != null:
				plays = int(spout.get("plays"))
		if _last_spout_plays < 0:
			_last_spout_plays = plays
		elif plays != _last_spout_plays:
			_last_spout_plays = plays
			_rock_timer = 0.0
		var tilt_deg := 14.0
		if _rock_timer >= 0.0:
			_rock_timer += delta * motion
			# 0.0..0.45 s: filled tip (+X) dips down to pour water; 0.45..0.90 s: snaps back onto the striker stone!
			if _rock_timer < 0.45:
				var f := smoothstep(0.0, 0.45, _rock_timer)
				tilt_deg = lerpf(14.0, -26.0, f)
			elif _rock_timer < 0.90:
				var f := smoothstep(0.45, 0.90, _rock_timer)
				tilt_deg = lerpf(-26.0, 14.0, f)
			else:
				_rock_timer = -1.0
				tilt_deg = 14.0
		rocker_node.rotation.z = deg_to_rad(tilt_deg)

	## Keeps all 18 koi cleanly flat on the koi pond water surface, well clear of the verandah (z <= -3.15 when
	## x < 3.90), gently separated from one another (zero bunching/overlap), and coloured in vivid Nishikigoi hues.
	func _sync_koi(host: Node, lanterns: String) -> void:
		if host == null:
			return
		var koi_sys: Node = host.system("koi")
		if koi_sys == null or koi_sys.get("creature") == null:
			return
		var cr: Object = koi_sys.creature
		var n := int(cr.count)
		var pond_y := WATER_Y + 0.014
		var inlet_n := mini(6, n)
		var main_n := n - inlet_n
		if not _koi_init:
			_koi_init = true
			# Spread main pond koi slots cleanly in a horizontal plane well inside the open front pond.
			var rng := RandomNumberGenerator.new()
			rng.seed = 7717
			for i in n:
				if i < main_n:
					var ang := TAU * float(i) / float(maxi(main_n, 1)) + rng.randf_range(-0.18, 0.18)
					var rad := lerpf(0.65, 1.95, float(i % 4) / 3.0) + rng.randf_range(-0.12, 0.12)
					cr.slot[i] = Vector3(cos(ang) * rad, 0.0, sin(ang) * rad * 0.62)
					cr.pos[i] = _clamp_to_pond(Vector3(0.4 + cos(ang) * rad * 1.35, pond_y,
							-5.25 + sin(ang) * 1.25))
					cr.vel[i] = Vector3(cos(ang + 1.3), 0.0, sin(ang + 1.3)) * 0.24
				else:
					# Six koi glide along the starboard pond inlet beneath the curved vermilion footbridge!
					var k := i - main_n
					var ang := TAU * float(k) / float(maxi(inlet_n, 1))
					cr.slot[i] = Vector3(0.0, 0.0, 0.0)
					cr.pos[i] = _clamp_to_pond(Vector3(5.55 + cos(ang) * 1.15, pond_y, -1.65 + sin(ang) * 2.55))
					cr.vel[i] = Vector3(-sin(ang), 0.0, cos(ang)).normalized() * 0.22
			cr.centre = Vector3(0.5, pond_y, -5.25)
			cr.centre_vel = Vector3(0.16, 0.0, 0.03)
			cr._wander = Vector3(2.2, pond_y, -5.10)

		# Keep front-pond school centre & wander targets deep inside the open front pond (never pressing the verandah!).
		cr.centre = Vector3(clampf(cr.centre.x, -2.1, 3.3), pond_y, clampf(cr.centre.z, -6.35, -4.35))
		cr.centre_vel.y = 0.0
		cr._wander = Vector3(clampf(cr._wander.x, -2.4, 3.6), pond_y, clampf(cr._wander.z, -6.55, -4.25))
		if cr.heading.length() > 0.01:
			cr.heading = Vector3(cr.heading.x, 0.0, cr.heading.z).normalized()

		# 1. Keep every koi smoothly inside its pond zone with flat horizontal velocity (smooth turn away from edges).
		for i in n:
			var p: Vector3 = cr.pos[i]
			var v: Vector3 = cr.vel[i]
			v.y = 0.0
			if i >= main_n:
				# Gentle independent figure-8 / elliptical loop beneath the vermilion footbridge (no verandah corner jam!).
				var k := i - main_n
				var phase_a := water_clock * (0.20 + 0.03 * float(k % 3)) + TAU * float(k) / float(maxi(inlet_n, 1))
				var goal := Vector3(5.55 + cos(phase_a) * 1.20, pond_y, -1.65 + sin(phase_a) * 2.65)
				var steer := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
				if steer.length() > 0.02:
					v = v.lerp(steer.normalized() * 0.24, 0.25)
				p = Vector3(lerpf(p.x, goal.x, 0.14), pond_y, lerpf(p.z, goal.z, 0.14))
			else:
				# Softly steer main-pond koi away from the front verandah boundary well before they touch it.
				if p.x < 3.95 and p.z > -3.40:
					v.z = minf(v.z, -0.14)
				if p.z < -6.95:
					v.z = maxf(v.z, 0.12)
				if p.x < -3.45:
					v.x = maxf(v.x, 0.12)
				if p.x > 4.25:
					v.x = minf(v.x, -0.12)
			p.y = pond_y
			p = _clamp_to_pond(p)
			cr.pos[i] = p
			cr.vel[i] = v

		# 2. Pairwise horizontal separation pass so koi never stack, bunch, or intersect one another!
		var min_sep := 0.62
		for _pass in 2:
			for i in n:
				for j in range(i + 1, n):
					var diff := Vector3(cr.pos[i].x - cr.pos[j].x, 0.0, cr.pos[i].z - cr.pos[j].z)
					var d := diff.length()
					if d < min_sep:
						var push_dir := diff / d if d > 0.001 else Vector3(cos(float(i) * 1.7), 0.0, sin(float(i) * 1.7))
						var half_push := push_dir * ((min_sep - d) * 0.52)
						cr.pos[i] = _clamp_to_pond(cr.pos[i] + half_push)
						cr.pos[j] = _clamp_to_pond(cr.pos[j] - half_push)

		# 3. Write strictly flat horizontal transforms + vivid Nishikigoi tints to the MultiMesh buffer.
		var lit_boost := 0.26 if lanterns == "washi" else (0.20 if lanterns == "moonlight" else 0.12)
		var sz := float(cr.size())
		var sys_fade := float(koi_sys.fade)
		for i in n:
			var p: Vector3 = cr.pos[i]
			p.y = pond_y + 0.003 * sin(float(cr.phase[i]) * TAU + float(i) * 0.9)
			cr.pos[i] = p
			var v: Vector3 = cr.vel[i]
			var dir := Vector3(v.x, 0.0, v.z)
			if dir.length() < 0.02:
				dir = Vector3(cr.heading.x, 0.0, cr.heading.z)
			if dir.length() < 0.02:
				dir = Vector3.RIGHT
			dir = dir.normalized()
			var flat_basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(sz, sz * 0.72, sz))
			var tint_c: Color = KOI_TINTS[i % KOI_TINTS.size()]
			var a := float(cr.fades[i]) * sys_fade
			cr.put(i, Transform3D(flat_basis, p), Color(tint_c.r, tint_c.g, tint_c.b, a),
					Color(float(cr.phase[i]), 1.0, lit_boost, 0.0))
		cr.flush()

	## Projects an XZ point cleanly inside the open L-shaped koi pond (front pond bay + starboard bridge inlet),
	## strictly >= 0.77 m clear in front of the engawa verandah (z <= -3.15 when x < 3.90) and clear of stone piers.
	static func _clamp_to_pond(p: Vector3) -> Vector3:
		var x := clampf(p.x, -3.55, 7.05)
		var z := clampf(p.z, -7.15, 2.25)
		# Keep koi strictly outside the pavilion verandah & port Zen gravel zone (generous margin past ENGAWA_Z0/X!).
		if x < 3.90 and z > -3.15:
			var dx := 3.90 - x
			var dz := z - (-3.15)
			if dx < dz:
				x = 3.90
			else:
				z = -3.15
		# Keep clear of front-port stone lantern promontory.
		if x < -3.35 and z < -5.15:
			x = -3.35
		return Vector3(x, p.y, z)

	## Builds the mirror-emerald animated koi pond water surface (1 opaque draw, 0 blend overdraw).
	func _build_pond_water(k: Node) -> void:
		var m := ShaderMaterial.new()
		m.shader = WATER_SHADER
		m.set_shader_parameter("caustic_map", Procedural.caustic_map())
		m.set_shader_parameter("house_reference", float(k.room.get("ambient_level")))
		m.set_shader_parameter("deep_colour", Color(0.007, 0.038, 0.032))
		m.set_shader_parameter("shallow_colour", Color(0.018, 0.088, 0.066))
		m.set_shader_parameter("sky_colour", _sky_refl_cur)
		m.set_shader_parameter("caustic_colour", _caustic_cur)
		m.set_shader_parameter("caustic_level", _caustic_lvl)
		m.set_shader_parameter("ripple_scale", 2.1)
		m.set_shader_parameter("spill_strength", 0.95)
		m.set_shader_parameter("glint_dir", Vector3(0.22, 0.62, -0.75).normalized())
		m.set_shader_parameter("glint_colour", _glint_cur)
		m.set_shader_parameter("glint_level", _glint_lvl)
		m.set_shader_parameter("ambient_floor", 0.34)
		water_mat = m

		var b := RoomMesh.new()
		b.surface(m)
		# Two seamlessly adjoining subdivided pond water grids forming the organic L-shaped Kyoto koi pond:
		# 1. Front main koi pond basin (x = -5.35..+8.45, z = -9.45..-2.15), tucking cleanly under the front verandah!
		_pond_grid(b, -5.35, 8.45, -9.45, -2.15, 22, 14)
		# 2. Starboard pond inlet sweeping past the right engawa under the curved vermilion footbridge!
		_pond_grid(b, 2.85, 8.45, -2.15, 4.35, 12, 14)
		water_mi = k._add_unbaked("KyotoPondWater", b)

	static func _pond_grid(b: RoomMesh, x0: float, x1: float, z0: float, z1: float, nx: int, nz: int) -> void:
		var rows: Array = []
		var norms: Array = []
		var cols: Array = []
		for iz in nz + 1:
			var vz := float(iz) / float(nz)
			var z := lerpf(z0, z1, vz)
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			var crow := PackedColorArray()
			for ix in nx + 1:
				var vx := float(ix) / float(nx)
				var x := lerpf(x0, x1, vx)
				row.append(Vector3(x, WATER_Y, z))
				nrow.append(Vector3.UP)
				# Subtle shallow emerald tint right along the mossy boulder shoreline (COLOR.r).
				var edge_d := minf(minf(x - x0, x1 - x), minf(z - z0, z1 - z))
				var shallow := clampf(1.0 - edge_d / 1.15, 0.0, 1.0) * 0.48
				# Focused lantern reflection shimmer pools beneath each lantern and the arched footbridge (COLOR.g).
				var pool := 0.0
				for lp: Vector3 in [
					Vector3(-4.55, WATER_Y, -5.85),
					Vector3(4.85, WATER_Y, -6.25),
					Vector3(7.55, WATER_Y, 1.55),
					Vector3(-2.68, WATER_Y, -2.35),
					Vector3(2.68, WATER_Y, -2.35),
					Vector3(5.65, WATER_Y, -1.65),
				]:
					var d2 := (x - lp.x) * (x - lp.x) + (z - lp.z) * (z - lp.z)
					pool = maxf(pool, exp(-d2 / 1.45))
				crow.append(Color(shallow, clampf(pool * 0.36, 0.0, 1.0), 0.0, 1.0))
			rows.append(row)
			norms.append(nrow)
			cols.append(crow)
		b.grid(rows, norms, cols)

	## Builds feathery, multi-tiered weeping cherry / Japanese maple foliage canopies using airy botanical leaf-fan
	## rosettes and delicate cascading weeping blossom curtains hugging the arching boughs (1 house-lit opaque draw
	## whose tint shifts live with setting.season: sakura / maple / summer).
	func _build_canopy(k: Node) -> void:
		var m: ShaderMaterial = k._light.library("felt", Color.WHITE, {"tiling": 0.9, "spill": 0.85}, true)
		m.set_shader_parameter("instance_tint", true)
		m.set_shader_parameter("tint", _season_cur)
		canopy_mat = m

		var b := RoomMesh.new()
		b.surface(m)
		for spec: Array in TREE_SPECS:
			var base: Vector3 = spec[0]
			var lean: Vector3 = spec[1]
			var h: float = spec[2]
			var cr: float = spec[3]
			# Reconstruct the exact primary limb tips from _build_tree_trunks (same deterministic seed!) so every
			# blossom/maple cluster grows organically directly out of real branches.
			var trunk_rng := RandomNumberGenerator.new()
			trunk_rng.seed = int(spec[5])
			var p2 := base + Vector3(lean.x * h * 0.34, h * 0.62, lean.z * h * 0.34)
			var p3 := base + Vector3(lean.x * h * 0.50, h * 0.84, lean.z * h * 0.50)
			for rk in 4:
				trunk_rng.randf_range(-0.25, 0.25)

			var hubs: Array = [] # [pos, radius, tier_0_to_1, is_outer_tip]
			for bi in 6:
				var a := TAU * float(bi) / 6.0 + trunk_rng.randf_range(-0.25, 0.25)
				var fork := p2.lerp(p3, float(bi % 3) / 2.0)
				var reach := cr * trunk_rng.randf_range(0.68, 0.96)
				var b_mid := fork + Vector3(cos(a) * reach * 0.55 + lean.x * 0.3, trunk_rng.randf_range(0.28, 0.58),
						sin(a) * reach * 0.55 + lean.z * 0.3)
				var b_tip := b_mid + Vector3(cos(a) * reach * 0.45, trunk_rng.randf_range(-0.18, 0.36),
						sin(a) * reach * 0.45)
				if b_tip.z < -6.2 and absf(b_tip.x) < 3.65:
					b_tip.x = signf(base.x) * 3.85
				hubs.append([b_mid + Vector3(0.0, 0.14, 0.0), 0.78, 0.55, false])
				hubs.append([b_mid.lerp(b_tip, 0.58) + Vector3(0.0, 0.10, 0.0), 0.84, 0.65, false])
				hubs.append([b_tip, 0.88, 0.42, true])
			# Four airy upper crown blossom clouds crowning the central leader.
			hubs.append([p3 + Vector3(0.0, 0.72, 0.0), 0.92, 1.0, false])
			hubs.append([p3 + Vector3(0.62, 0.52, 0.35), 0.76, 0.85, false])
			hubs.append([p3 + Vector3(-0.58, 0.56, -0.32), 0.76, 0.85, false])
			hubs.append([p3 + Vector3(0.15, 0.45, -0.64), 0.74, 0.82, false])

			var rng := RandomNumberGenerator.new()
			rng.seed = int(spec[5]) + 700
			for hub: Array in hubs:
				var hc: Vector3 = hub[0]
				var hr: float = hub[1]
				var tier: float = hub[2]
				var is_tip: bool = hub[3]
				# Keep every blossom strictly clear of the cinema screen rectangle & sight line.
				if hc.z < -6.1 and absf(hc.x) < 3.75:
					hc.x = signf(hc.x if absf(hc.x) > 0.01 else base.x) * 3.95
				# Layered airy starburst of 22 double-sided blossom/maple leaf blades per branch hub!
				for li in 22:
					var az := TAU * float(li) / 22.0 + rng.randf_range(-0.28, 0.28)
					var elev := rng.randf_range(-0.34, 0.52)
					var radial := rng.randf_range(0.05, hr * 0.58)
					var root_p := hc + Vector3(cos(az) * radial, rng.randf_range(-0.24, 0.28), sin(az) * radial)
					var dir := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev)).normalized()
					var side_dir := Vector3(-sin(az), rng.randf_range(-0.22, 0.22), cos(az)).normalized()
					var nrm := side_dir.cross(dir).normalized()
					var llen := rng.randf_range(0.42, 0.72) * (hr / 0.82)
					var lwid := llen * rng.randf_range(0.36, 0.52)
					# Organic crown lighting + warm gold/crimson tip variation (multiplied by live season tint).
					var lit := lerpf(0.62, 1.08, tier) * rng.randf_range(0.84, 1.08)
					var gold_lift := rng.randf_range(0.88, 1.24)
					b.colour = Color(minf(lit * 1.04, 1.15), minf(lit * gold_lift, 1.15),
							lit * rng.randf_range(0.82, 1.02)).srgb_to_linear()
					Shapes.leaf(b, root_p, dir * llen, side_dir * lwid, nrm)
				# Graceful cascading weeping blossom curtains hanging delicately from outer bough tips!
				if is_tip:
					for wi in 2:
						var wa := rng.randf_range(0.0, TAU)
						var w_top := hc + Vector3(cos(wa) * 0.36, -0.05, sin(wa) * 0.36)
						var w_len := rng.randf_range(0.95, 1.45)
						var sway := Vector3(lean.x * 0.14 + cos(wa) * 0.10, 0.0, lean.z * 0.14 + sin(wa) * 0.10)
						for seg in 6:
							var f0 := float(seg) / 6.0
							var f1 := float(seg + 1) / 6.0
							var p_a := w_top + sway * f0 + Vector3(0.0, -w_len * f0, 0.0)
							var p_b := w_top + sway * f1 + Vector3(0.0, -w_len * f1, 0.0)
							var taper := lerpf(1.0, 0.42, f0)
							var blade_a := wa + float(seg) * 1.15
							var across := Vector3(cos(blade_a), 0.0, sin(blade_a)) * (0.14 * taper)
							var down_v := (p_b - p_a) * 1.35
							var wn := across.cross(down_v).normalized()
							var w_lit := lerpf(0.94, 0.72, f0)
							b.colour = Color(w_lit * 1.04, w_lit * 0.98, w_lit * 0.96).srgb_to_linear()
							Shapes.leaf(b, p_a, down_v, across, wn)
		canopy_mi = k._add_unbaked("KyotoCanopy", b)

	## Builds the soft moonlit Kyoto Higashiyama mountain silhouette circling behind the garden wall (1 opaque draw).
	func _build_hills(k: Node) -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		hills_mat = m

		var b := RoomMesh.new()
		b.surface(m)
		var segs := 64
		# Two layered undulating mountain ranges (near foothills r=48 m, far Higashiyama peaks r=82 m).
		for layer: Array in [
			[82.0, 14.5, 5.2, Color(0.040, 0.058, 0.105), Color(0.082, 0.115, 0.185), 1.3],
			[48.0, 8.2, 3.0, Color(0.025, 0.040, 0.068), Color(0.052, 0.075, 0.118), 3.7],
		]:
			var r := float(layer[0])
			var base_h := float(layer[1])
			var amp := float(layer[2])
			var col_lo: Color = layer[3]
			var col_hi: Color = layer[4]
			var ph := float(layer[5])
			var bot := PackedVector3Array()
			var top := PackedVector3Array()
			var nrm := PackedVector3Array()
			var c_bot := PackedColorArray()
			var c_top := PackedColorArray()
			for i in segs + 1:
				var ang := TAU * float(i % segs) / float(segs)
				var d := Vector3(sin(ang), 0.0, -cos(ang))
				var ridge := base_h + amp * (0.55 * sin(ang * 3.0 + ph) + 0.30 * cos(ang * 5.0 - ph * 1.4)
						+ 0.18 * sin(ang * 9.0 + ph * 0.7))
				bot.append(d * r + Vector3(0.0, -2.5, 0.0))
				top.append(d * r + Vector3(0.0, ridge, 0.0))
				nrm.append(-d)
				c_bot.append(col_lo.srgb_to_linear())
				c_top.append(col_hi.srgb_to_linear())
			b.grid([bot, top], [nrm, nrm], [c_bot, c_top])
		hills_mi = k._add_unbaked("KyotoHills", b)
		if hills_mi != null:
			hills_mi.extra_cull_margin = 120.0

	## Builds the pivoting green bamboo shishi-odoshi rocker tube as its own tiny Node3D pivot (1 draw, ~60 tris).
	func _build_bamboo_rocker(k: Node) -> void:
		var pivot_pos := SPOUT_AT + Vector3(-0.34, 0.36, 0.0)
		rocker_node = Node3D.new()
		rocker_node.name = "BambooRocker"
		rocker_node.position = pivot_pos
		k.own(rocker_node)

		var wood_m: ShaderMaterial = k._light.from_param(k.params["wood"], true)
		wood_m.set_shader_parameter("instance_tint", true)
		var b := RoomMesh.new()
		b.surface(wood_m)
		b.colour = BAMBOO_GREEN.srgb_to_linear()
		# Hollow bamboo rocker tube pivoted at local (0, 0, 0), spanning -0.32 (striker tail) to +0.38 (water mouth).
		var tube_basis := Basis(Vector3.BACK, -PI * 0.5)
		Shapes.cylinder(b, Vector3(-0.32, 0.0, 0.0), 0.036, 0.70, 8, tube_basis, true)
		# Bamboo node collar rings along the rocker arm.
		b.colour = BAMBOO_NODE.srgb_to_linear()
		for ox: float in [-0.20, 0.0, 0.22]:
			Shapes.cylinder(b, Vector3(ox - 0.01, 0.0, 0.0), 0.041, 0.02, 8, tube_basis, true)
		var mi := MeshInstance3D.new()
		mi.name = "BambooRockerTube"
		mi.mesh = b.commit(false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		rocker_node.add_child(mi)


static func build(piece: String, c: Object, _xf: Transform3D, _size: Vector3, _e: Dictionary) -> void:
	var h := _hall(c)
	match piece:
		"kyoto_engawa":
			_build_engawa(c)
		"kyoto_garden":
			_build_garden(c, h)
	for b: RoomMesh in [c.s, c.u, c.lit, c.cove]:
		b.colour = Color.WHITE


static func _hall(c: Object) -> KyotoGardenHall:
	for h: Object in c.halls:
		if h is KyotoGardenHall:
			return h
	var h := KyotoGardenHall.new()
	h.kit = c.kit
	c.halls.append(h)
	return h


static func _lin(col: Color, alpha := 1.0) -> Color:
	var l := col.srgb_to_linear()
	return Color(l.r, l.g, l.b, clampf(alpha, 0.0, 1.0))


static func _solid(c: Object, centre: Vector3, size: Vector3, basis := Basis()) -> void:
	c.shapes.append(PhysicsShapes.box(centre, size, basis))


## Shared glossy Urushi lacquer and antique Kyoto brass helpers (consolidates PieceSoft draws cleanly).
static func _lacquer(c: Object) -> Material:
	return c.shiny("wood", 0.0, 0.28, 0.18)


static func _gilt(c: Object) -> Material:
	return c.shiny("gilt", 1.0, 0.76, 0.22)


# --- Piece 1: kyoto_engawa --------------------------------------------------------------------------------------------

static func _build_engawa(c: Object) -> void:
	# Compact lightmap atlas (<= 1024x1024, fast build).
	c.s.texel = 0.18
	_build_floor_and_verandah(c)
	_build_posts_and_roof(c)
	_build_shoji_and_tokonoma(c)
	_build_chabudai_and_tea_set(c)
	_build_andon_lanterns(c)
	_build_screen_torii_frame(c)


## Raised traditional tatami floor (procedural tatami_weave) framed by glossy dark-hinoki engawa verandah planks,
## stone foundation footings, and stepped granite garden entry stones (strictly zero coplanar face overlap).
static func _build_floor_and_verandah(c: Object) -> void:
	var wood_s: Material = c.tinted("wood")
	var wood_u: Material = c.soft("wood")
	var lacquer: Material = _lacquer(c)
	var stone_s: Material = c.tinted("stone")
	var tatami: ShaderMaterial = c.tinted("fabric", "tatami_weave")
	# Fit 3 crisp tatami widths across -2.30..+2.30 (1.5333 m repeat) with the centre seat squarely centred on a mat.
	tatami.set_shader_parameter("tiling", 1.5333)
	tatami.set_shader_parameter("uv_offset", Vector2(0.5, 0.25))

	# 1. Interior tatami floor slab (y = 0.000, strictly bounded by [-TATAMI_X..+TATAMI_X, TATAMI_Z0..TATAMI_Z1]).
	c.s.surface(tatami)
	c.s.colour = _lin(TATAMI_TINT)
	c.s.face([
		Vector3(-TATAMI_X, TATAMI_Y, TATAMI_Z0),
		Vector3(TATAMI_X, TATAMI_Y, TATAMI_Z0),
		Vector3(TATAMI_X, TATAMI_Y, TATAMI_Z1),
		Vector3(-TATAMI_X, TATAMI_Y, TATAMI_Z1),
	], Vector3.UP)

	# 2. Dark-hinoki kamachi sill border frame strictly surrounding the tatami (no overlap; 8 cm wide, top y = +0.004).
	c.s.surface(wood_s)
	c.s.colour = _lin(CEDAR_DARK)
	var kw := 0.08
	var kh := 0.044
	var ky := TATAMI_Y + 0.004 - kh * 0.5
	# Front & aft kamachi borders.
	c.s.box(Vector3(0.0, ky, TATAMI_Z0 - kw * 0.5), Vector3(TATAMI_X * 2.0 + kw * 2.0, kh, kw), Basis(), [RoomMesh.DOWN])
	c.s.box(Vector3(0.0, ky, TATAMI_Z1 + kw * 0.5), Vector3(TATAMI_X * 2.0 + kw * 2.0, kh, kw), Basis(), [RoomMesh.DOWN])
	# Port & starboard kamachi borders.
	for sx: float in [-1.0, 1.0]:
		c.s.box(Vector3(sx * (TATAMI_X + kw * 0.5), ky, (TATAMI_Z0 + TATAMI_Z1) * 0.5),
				Vector3(kw, kh, TATAMI_Z1 - TATAMI_Z0), Basis(), [RoomMesh.DOWN])

	# 3. Four strictly non-overlapping engawa hinoki verandah deck strips at y = ENGAWA_Y (-0.022 m, 12 cm thick).
	var deck_h := 0.11
	var deck_cy := ENGAWA_Y - deck_h * 0.5
	var ix0 := -(TATAMI_X + kw)
	var ix1 := (TATAMI_X + kw)
	var iz0 := TATAMI_Z0 - kw
	var iz1 := TATAMI_Z1 + kw
	c.s.surface(wood_s)
	c.s.colour = _lin(HINOKI_DECK)
	# Front verandah deck overlooking the koi pond.
	c.s.box(Vector3(0.0, deck_cy, (ENGAWA_Z0 + iz0) * 0.5),
			Vector3(ENGAWA_X * 2.0, deck_h, iz0 - ENGAWA_Z0))
	# Port & starboard verandah decks flanking the tatami room.
	for sx: float in [-1.0, 1.0]:
		var cx := sx * (ix1 + ENGAWA_X) * 0.5
		c.s.box(Vector3(cx, deck_cy, (iz0 + ENGAWA_Z1) * 0.5),
				Vector3(ENGAWA_X - ix1, deck_h, ENGAWA_Z1 - iz0))
	# Aft verandah skirt under the shoji wall.
	c.s.box(Vector3(0.0, deck_cy, (iz1 + ENGAWA_Z1) * 0.5),
			Vector3(ix1 - ix0, deck_h, ENGAWA_Z1 - iz1))

	# Outer bevelled dark-hinoki verandah fascia trim beam & under-floor joists (nebiki) + support posts (tsuka).
	c.s.colour = _lin(CEDAR_DEEP)
	# Front & side fascia aprons dipping cleanly below the verandah edge.
	c.s.box(Vector3(0.0, ENGAWA_Y - 0.14, ENGAWA_Z0 + 0.08), Vector3(ENGAWA_X * 2.0 - 0.06, 0.16, 0.10))
	for sx: float in [-1.0, 1.0]:
		c.s.box(Vector3(sx * (ENGAWA_X - 0.08), ENGAWA_Y - 0.14, (ENGAWA_Z0 + ENGAWA_Z1) * 0.5),
				Vector3(0.10, 0.16, ENGAWA_Z1 - ENGAWA_Z0 - 0.06))
	# Recessed dark under-pavilion crawlspace plinth box so no daylight leaks under the tatami floor!
	c.s.box(Vector3(0.0, -0.34, 0.55), Vector3(4.95, 0.42, 4.35), Basis(), [RoomMesh.UP, RoomMesh.DOWN])

	# Exposed timber floor-support posts resting on mossy granite foundation stones (kiso-ishi) around the perimeter.
	for px: float in [-2.98, -1.50, 0.0, 1.50, 2.98]:
		for pz: float in [-2.18, 2.74]:
			c.u.surface(wood_u)
			c.u.colour = _lin(CEDAR_DEEP)
			c.u.box(Vector3(px, -0.26, pz), Vector3(0.13, 0.34, 0.13), Basis(), [RoomMesh.UP])
			c.s.surface(stone_s)
			c.s.colour = _lin(GRANITE_WET)
			c.s.box(Vector3(px, -0.47, pz), Vector3(0.28, 0.14, 0.28), Basis(), [RoomMesh.DOWN])
	for pz: float in [-0.70, 1.05]:
		for sx: float in [-1.0, 1.0]:
			c.u.surface(wood_u)
			c.u.colour = _lin(CEDAR_DEEP)
			c.u.box(Vector3(sx * 2.98, -0.26, pz), Vector3(0.13, 0.34, 0.13), Basis(), [RoomMesh.UP])
			c.s.surface(stone_s)
			c.s.colour = _lin(GRANITE_WET)
			c.s.box(Vector3(sx * 2.98, -0.47, pz), Vector3(0.28, 0.14, 0.28), Basis(), [RoomMesh.DOWN])

	# 4. Bespoke low vermilion-lacquer & silk trim borders framing each of the 6 zabuton floor cushions cleanly!
	#    (Cushions sit at x = -1.15, 0.0, +1.15; z = 0.0, +1.55; height 8 mm, bottom skipped, zero Z-fighting!)
	c.u.surface(lacquer)
	c.u.colour = _lin(VERMILION_DARK)
	for rz: float in [0.0, 1.55]:
		for rx: float in [-1.15, 0.0, 1.15]:
			c.u.box(Vector3(rx, TATAMI_Y + 0.004, rz - 0.05), Vector3(0.68, 0.008, 0.68), Basis(), [RoomMesh.DOWN])

	# 5. Broad granite kutsunugi-ishi (shoe-removing step stone) off the port verandah descending to the Zen garden.
	c.s.surface(stone_s)
	c.s.colour = _lin(GRANITE_MID)
	c.s.box(Vector3(-3.58, -0.32, -0.35), Vector3(0.64, 0.26, 1.18), Basis(), [RoomMesh.DOWN])
	# Stepped granite tobi-ishi garden stepping stones curving from the step stone toward the bamboo spout & pond!
	var step_stones: Array = [
		[Vector3(-4.22, -0.42, -0.65), Vector3(0.46, 0.12, 0.42), 0.18],
		[Vector3(-4.58, -0.42, -1.25), Vector3(0.42, 0.12, 0.48), -0.22],
		[Vector3(-4.10, -0.41, -2.55), Vector3(0.50, 0.12, 0.44), 0.35],
		[Vector3(-4.42, -0.41, -3.28), Vector3(0.46, 0.12, 0.44), -0.15],
		[Vector3(-4.72, -0.41, -4.05), Vector3(0.52, 0.12, 0.46), 0.28],
	]
	c.u.surface(c.soft("stone"))
	c.u.colour = _lin(GRANITE_LIGHT)
	for st: Array in step_stones:
		c.u.rounded_box(Vector3.ZERO, st[1], 0.045, Transform3D(Basis(Vector3.UP, float(st[2])), st[0]), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])


## Slender square hinoki corner posts, mortise-and-tenon perimeter tie-beams, open-eave vaulted timber ceiling with
## exposed parallel rafters (taruki), purlins, ridge beam, warm cove uplight, and upturned dark kawara clay roof eaves.
static func _build_posts_and_roof(c: Object) -> void:
	var wood_s: Material = c.tinted("wood")
	var wood_u: Material = c.soft("wood")
	var stone_s: Material = c.tinted("stone")
	var roof_s: Material = c.tinted("roof", "roof_tiles")
	var gilt: Material = _gilt(c)
	var cove_m: Material = c.kit.cove_material()

	# 1. Six slender square hinoki verandah posts (front corners, mid-aft flanks, aft corners) with bronze collars.
	var post_xz: Array[Vector2] = [
		Vector2(-2.98, -2.16),
		Vector2(2.98, -2.16),
		Vector2(-2.98, 1.15),
		Vector2(2.98, 1.15),
		Vector2(-2.98, SHOJI_Z),
		Vector2(2.98, SHOJI_Z),
	]
	for p2: Vector2 in post_xz:
		var h := EAVE_BEAM_Y - ENGAWA_Y
		c.s.surface(wood_s)
		c.s.colour = _lin(HINOKI_WARM)
		c.s.box(Vector3(p2.x, ENGAWA_Y + h * 0.5, p2.y), Vector3(0.17, h, 0.17), Basis(), [RoomMesh.DOWN])
		# Carved dark base shoe & gilt-bronze kugikakushi top collar bracket.
		c.u.surface(gilt)
		c.u.colour = _lin(BRASS_GOLD * 0.65)
		c.u.box(Vector3(p2.x, ENGAWA_Y + 0.06, p2.y), Vector3(0.19, 0.11, 0.19), Basis(), [RoomMesh.DOWN])
		c.u.box(Vector3(p2.x, EAVE_BEAM_Y - 0.10, p2.y), Vector3(0.195, 0.08, 0.195))
		# Stepped timber bracket block (masugumi) supporting the eave beam.
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DARK)
		c.u.box(Vector3(p2.x, EAVE_BEAM_Y + 0.04, p2.y), Vector3(0.28, 0.10, 0.28))
		# Physics box strictly around each post (well clear of viewer origin >= 2.9 m).
		_solid(c, Vector3(p2.x, ENGAWA_Y + h * 0.5, p2.y), Vector3(0.22, h, 0.22))

	# 2. Continuous perimeter tie-beams (keta / hari) kept strictly beneath the concave roof boarding!
	c.s.surface(wood_s)
	c.s.colour = _lin(HINOKI_WARM * 0.88)
	# Front & aft tie-beams along X.
	for bz: float in [-2.16, SHOJI_Z]:
		c.s.box(Vector3(0.0, EAVE_BEAM_Y + 0.06, bz), Vector3(6.36, 0.20, 0.20))
	# Port & starboard tie-beams along Z.
	for sx: float in [-1.0, 1.0]:
		c.s.box(Vector3(sx * 2.98, EAVE_BEAM_Y + 0.06, 0.34), Vector3(0.20, 0.20, 5.44))
	# Two exposed heavy transverse dark-hinoki cross-beams spanning inside the pavilion (z = -0.55 and z = +1.15).
	c.s.colour = _lin(CEDAR_DARK)
	for cz: float in [-0.55, 1.15]:
		c.s.box(Vector3(0.0, EAVE_BEAM_Y + 0.14, cz), Vector3(5.90, 0.18, 0.18))
		# Traditional wagoya purlin struts (tsuka) supporting the ceiling purlins cleanly below the concave soffit!
		for tx: float in [-1.62, 1.62]:
			var sh := 3.74 - (EAVE_BEAM_Y + 0.22)
			c.s.box(Vector3(tx, EAVE_BEAM_Y + 0.22 + sh * 0.5, cz), Vector3(0.13, sh, 0.13))
	# Central longitudinal tie-beam at z = 0.34 carrying twin king-posts cleanly up to the central ridge beam!
	c.s.box(Vector3(0.0, 3.76, 0.34), Vector3(3.24, 0.14, 0.14))
	for kx: float in [-0.75, 0.75]:
		var kh := (RIDGE_Y - 0.12) - 3.82
		c.s.box(Vector3(kx, 3.82 + kh * 0.5, 0.34), Vector3(0.14, kh, 0.14))
	# Central longitudinal ridge beam (munagi) & flanking interior purlins (moya) cleanly under the concave soffit!
	c.s.box(Vector3(0.0, RIDGE_Y - 0.08, 0.34), Vector3(2.80, 0.18, 0.18))
	for side: float in [-1.0, 1.0]:
		c.s.box(Vector3(0.0, 3.74, 0.34 + side * 1.48), Vector3(4.10, 0.12, 0.12))
		c.s.box(Vector3(side * 1.62, 3.74, 0.34), Vector3(0.12, 0.12, 2.70))

	# 3. Vaulted hipped timber roof soffit (noji-ita) + overhanging cantilevered eaves (outer eave at y = 3.12 m,
	#    curving subtly UP at the four hip corners to y = 3.24 m!) + smoked dark kawara clay tile upper roof!
	var rx := 1.42 # ridge half-length along X (z = 0.34)
	var rz_c := 0.34
	var ex := 4.18 # cantilevered outer eave X
	var ez0 := -3.32 # cantilevered outer front eave Z (well above sight line: y_eave = 3.12 vs sight_y = 2.18!)
	var ez1 := 3.96 # cantilevered outer aft eave Z
	var ey := 3.10
	var ey_corner := 3.24

	# Helper points for the 4 roof slope skirts (underside warm hinoki boarding, topside dark kawara clay tiles).
	var p_fl := Vector3(-ex, ey_corner, ez0)
	var p_fr := Vector3(ex, ey_corner, ez0)
	var p_al := Vector3(-ex, ey_corner, ez1)
	var p_ar := Vector3(ex, ey_corner, ez1)
	var p_rl := Vector3(-rx, RIDGE_Y + 0.08, rz_c)
	var p_rr := Vector3(rx, RIDGE_Y + 0.08, rz_c)

	# Build each of the 4 curved-corner roof slopes as a clean 5-column x 3-row curved grid (both underside timber
	# soffit AND upper kawara roof surface separated by 0.11 m thickness!).
	_roof_slope(c, wood_s, roof_s, p_fl, p_fr, p_rl, p_rr, ey, Vector3(0.0, 0.0, -1.0))
	_roof_slope(c, wood_s, roof_s, p_ar, p_al, p_rr, p_rl, ey, Vector3(0.0, 0.0, 1.0))
	_roof_triangle_slope(c, wood_s, roof_s, p_al, p_fl, p_rl, ey)
	_roof_triangle_slope(c, wood_s, roof_s, p_fr, p_ar, p_rr, ey)

	# 4. Crisp exposed parallel hinoki rafters (taruki) radiating outward beneath all four cantilevered eaves!
	c.u.surface(wood_u)
	c.u.colour = _lin(HINOKI_WARM * 0.94)
	# Front and aft parallel rafters (15 rafters per slope!).
	for i in 15:
		var t := float(i) / 14.0
		var x_e := lerpf(-ex + 0.32, ex - 0.32, t)
		var x_r := clampf(x_e * 0.45, -rx, rx)
		var y_e := lerpf(ey, ey_corner, pow(absf(t * 2.0 - 1.0), 2.2))
		# Front slope rafter
		Shapes.beam(c.u, Vector3(x_r, RIDGE_Y - 0.10, rz_c - 0.06), Vector3(x_e, y_e - 0.10, ez0 + 0.06),
				Vector2(0.055, 0.070))
		# Aft slope rafter
		Shapes.beam(c.u, Vector3(x_r, RIDGE_Y - 0.10, rz_c + 0.06), Vector3(x_e, y_e - 0.10, ez1 - 0.06),
				Vector2(0.055, 0.070))
	# Port and starboard parallel rafters (11 rafters per side!).
	for i in 11:
		var t := float(i) / 10.0
		var z_e := lerpf(ez0 + 0.36, ez1 - 0.36, t)
		var y_e := lerpf(ey, ey_corner, pow(absf(t * 2.0 - 1.0), 2.2))
		for sx: float in [-1.0, 1.0]:
			var r_end := p_rl if sx < 0.0 else p_rr
			Shapes.beam(c.u, r_end + Vector3(0.0, -0.15, 0.0), Vector3(sx * (ex - 0.06), y_e - 0.10, z_e),
					Vector2(0.055, 0.070))
	# Four strong diagonal hip rafters (sumigi) + curved kawara roof corner ridge tiles & upturned onigawara finials!
	var hip_pairs: Array = [
		[p_rl, p_fl], [p_rr, p_fr], [p_rl, p_al], [p_rr, p_ar],
	]
	for hp: Array in hip_pairs:
		var a: Vector3 = hp[0]
		var b_pt: Vector3 = hp[1]
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DARK)
		Shapes.beam(c.u, a + Vector3(0.0, -0.09, 0.0), b_pt + Vector3(0.0, -0.04, 0.0), Vector2(0.11, 0.13))
		# Dark smoked-clay hip ridge beam on top of the kawara tiles.
		c.u.surface(c.soft("stone"))
		c.u.colour = _lin(KAWARA_RIDGE)
		Shapes.beam(c.u, a + Vector3(0.0, 0.14, 0.0), b_pt + Vector3(0.0, 0.15, 0.0), Vector2(0.14, 0.14))
		# Sculpted upturned kawara corner finial (onigawara) kicking gracefully upward at each corner tip!
		c.u.box(b_pt + Vector3(0.0, 0.25, 0.0), Vector3(0.22, 0.24, 0.22),
				Basis(Vector3.UP, atan2(b_pt.x, b_pt.z)))
	# Main horizontal roof ridge tile cap & twin ridge-end onigawara ornaments.
	c.u.surface(c.soft("stone"))
	c.u.colour = _lin(KAWARA_RIDGE)
	c.u.box(Vector3(0.0, RIDGE_Y + 0.24, rz_c), Vector3(rx * 2.0 + 0.26, 0.22, 0.22))
	for sx: float in [-1.0, 1.0]:
		c.u.box(Vector3(sx * (rx + 0.16), RIDGE_Y + 0.36, rz_c), Vector3(0.16, 0.34, 0.28))

	# 5. Warm subtle architectural cove uplight tucked inside the perimeter tie-beams sloping inward up the ceiling!
	c.cove.surface(cove_m)
	var cove_lin := _lin(HINOKI_WARM * 1.15)
	for side_def: Array in [
		[Vector3(-2.78, EAVE_BEAM_Y + 0.17, -2.02), Vector3(2.78, EAVE_BEAM_Y + 0.17, -2.02), Vector3(0.0, -0.35, 0.94)],
		[Vector3(2.78, EAVE_BEAM_Y + 0.17, SHOJI_Z - 0.14), Vector3(-2.78, EAVE_BEAM_Y + 0.17, SHOJI_Z - 0.14), Vector3(0.0, -0.35, -0.94)],
		[Vector3(-2.78, EAVE_BEAM_Y + 0.17, SHOJI_Z - 0.14), Vector3(-2.78, EAVE_BEAM_Y + 0.17, -2.02), Vector3(0.94, -0.35, 0.0)],
		[Vector3(2.78, EAVE_BEAM_Y + 0.17, -2.02), Vector3(2.78, EAVE_BEAM_Y + 0.17, SHOJI_Z - 0.14), Vector3(-0.94, -0.35, 0.0)],
	]:
		var p0: Vector3 = side_def[0]
		var p1: Vector3 = side_def[1]
		var n_in: Vector3 = (side_def[2] as Vector3).normalized()
		var up_off := Vector3(0.0, 0.22, 0.0) + Vector3(n_in.x, 0.0, n_in.z).normalized() * 0.28
		var r0 := PackedVector3Array([p0, p0.lerp(p1, 0.5), p1])
		var r1 := PackedVector3Array([p0 + up_off, p0.lerp(p1, 0.5) + up_off, p1 + up_off])
		var nr := PackedVector3Array([n_in, n_in, n_in])
		var c0 := PackedColorArray([Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.65),
				Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.78), Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.65)])
		var c1 := PackedColorArray([Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.04),
				Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.06), Color(cove_lin.r, cove_lin.g, cove_lin.b, 0.04)])
		c.cove.grid([r0, r1], [nr, nr], [c0, c1])
	# Add subtle stone foundation collar under screen & pavilion eave fascia trim.
	c.s.surface(stone_s)
	c.s.colour = _lin(GRANITE_MID)


## Builds one trapezoidal hip roof slope (front or aft) with gracefully upturned corner eaves (underside hinoki boarding
## + topside smoked kawara clay tiles, separated by 0.11 m thickness).
static func _roof_slope(c: Object, wood_s: Material, roof_s: Material, e0: Vector3, e1: Vector3, r0: Vector3,
		r1: Vector3, ey_mid: float, out_dir: Vector3) -> void:
	var nu := 6
	var nv := 3
	var under_rows: Array = []
	var under_norms: Array = []
	var under_cols: Array = []
	var top_rows: Array = []
	var top_norms: Array = []
	var top_cols: Array = []
	var thick := Vector3(0.0, 0.11, 0.0)
	for iv in nv + 1:
		var v := float(iv) / float(nv) # 0 = eave lip, 1 = ridge
		var ur := PackedVector3Array()
		var un := PackedVector3Array()
		var uc := PackedColorArray()
		var tr := PackedVector3Array()
		var tn := PackedVector3Array()
		var tc := PackedColorArray()
		for iu in nu + 1:
			var u := float(iu) / float(nu)
			var edge_k := pow(absf(u * 2.0 - 1.0), 2.2)
			var pe := e0.lerp(e1, u)
			pe.y = lerpf(ey_mid, e0.y, edge_k)
			var pr := r0.lerp(r1, u)
			var p := pe.lerp(pr, v)
			# Subtle traditional Japanese concave roof sag (sori) midway down the slope.
			p.y -= 0.09 * sin(PI * v)
			var n_up := (Vector3.UP * 1.45 + out_dir * 0.55).normalized()
			ur.append(p)
			un.append(-n_up)
			uc.append(_lin(HINOKI_WARM * lerpf(0.74, 0.92, v)))
			tr.append(p + thick)
			tn.append(n_up)
			tc.append(_lin(KAWARA_TILE * lerpf(0.92, 1.10, v)))
		under_rows.append(ur)
		under_norms.append(un)
		under_cols.append(uc)
		top_rows.append(tr)
		top_norms.append(tn)
		top_cols.append(tc)
	c.s.surface(wood_s)
	c.s.sheet(under_rows, under_norms, under_cols, (e1 - e0).normalized(), (r0 - e0).normalized())
	c.s.surface(roof_s)
	c.s.sheet(top_rows, top_norms, top_cols, (e1 - e0).normalized(), (r0 - e0).normalized())


## Builds one triangular hip roof slope (port or starboard) with gracefully upturned corner eaves.
static func _roof_triangle_slope(c: Object, wood_s: Material, roof_s: Material, e0: Vector3, e1: Vector3,
		apex: Vector3, ey_mid: float) -> void:
	var nu := 6
	var nv := 3
	var under_rows: Array = []
	var under_norms: Array = []
	var under_cols: Array = []
	var top_rows: Array = []
	var top_norms: Array = []
	var top_cols: Array = []
	var thick := Vector3(0.0, 0.11, 0.0)
	var out_x := signf(e0.x)
	var n_up := Vector3(out_x * 0.55, 1.45, 0.0).normalized()
	for iv in nv + 1:
		var v := float(iv) / float(nv)
		var ur := PackedVector3Array()
		var un := PackedVector3Array()
		var uc := PackedColorArray()
		var tr := PackedVector3Array()
		var tn := PackedVector3Array()
		var tc := PackedColorArray()
		for iu in nu + 1:
			var u := float(iu) / float(nu)
			var edge_k := pow(absf(u * 2.0 - 1.0), 2.2)
			var pe := e0.lerp(e1, u)
			pe.y = lerpf(ey_mid, e0.y, edge_k)
			# Keep tiny non-zero width at the ridge vertex so UV2 chart never degenerates.
			var pa := apex + (e1 - e0).normalized() * ((u - 0.5) * 0.04)
			var p := pe.lerp(pa, v)
			p.y -= 0.08 * sin(PI * v)
			ur.append(p)
			un.append(-n_up)
			uc.append(_lin(HINOKI_WARM * lerpf(0.74, 0.92, v)))
			tr.append(p + thick)
			tn.append(n_up)
			tc.append(_lin(KAWARA_TILE * lerpf(0.92, 1.10, v)))
		under_rows.append(ur)
		under_norms.append(un)
		under_cols.append(uc)
		top_rows.append(tr)
		top_norms.append(tn)
		top_cols.append(tc)
	c.s.surface(wood_s)
	c.s.sheet(under_rows, under_norms, under_cols, (e1 - e0).normalized(), (apex - e0).normalized())
	c.s.surface(roof_s)
	c.s.sheet(top_rows, top_norms, top_cols, (e1 - e0).normalized(), (apex - e0).normalized())


## Aft wall: softly backlit translucent washi sliding shoji screens with fine dark-cedar kumiko lattice mullions,
## carved cedar ranma transom grille, and a central recessed tokonoma display alcove holding a minimalist Zen hanging
## scroll (kakejiku) and ceramic ikebana vase with blossoming plum/cherry branch.
static func _build_shoji_and_tokonoma(c: Object) -> void:
	var wood_s: Material = c.tinted("wood")
	var wood_u: Material = c.soft("wood")
	var lacquer: Material = _lacquer(c)
	var plaster_s: Material = c.tinted("plaster")
	var stone_u: Material = c.soft("stone")
	var leaf_u: Material = c.soft("leaves")
	var cove_m: Material = c.kit.cove_material()

	# 1. Grooved cedar floor track (shikii), upper sliding track (kamoi), and vertical tokonoma cheek posts.
	c.s.surface(wood_s)
	c.s.colour = _lin(CEDAR_DARK)
	c.s.box(Vector3(0.0, 0.03, SHOJI_Z), Vector3(5.96, 0.06, 0.18), Basis(), [RoomMesh.DOWN])
	c.s.box(Vector3(0.0, 2.40, SHOJI_Z), Vector3(5.96, 0.10, 0.18))
	# Right tokonoma square cedar post & left natural round gnarled toko-bashira alcove pillar!
	c.s.box(Vector3(0.96, 1.66, SHOJI_Z), Vector3(0.14, 3.32, 0.15), Basis(), [RoomMesh.DOWN])
	c.u.surface(wood_u)
	c.u.colour = _lin(HINOKI_WARM * 0.72)
	Shapes.lathe(c.u, [
		Vector2(0.088, 0.0), Vector2(0.082, 0.85), Vector2(0.076, 1.72),
		Vector2(0.072, 2.55), Vector2(0.078, 3.32),
	], Vector3(-0.96, 0.0, SHOJI_Z), 10)

	# 2. Left and right sliding shoji panel bays (2 overlapping leaves each: backlit washi + crisp kumiko lattice!).
	for bay_side: float in [-1.0, 1.0]:
		var x_a := -2.88 if bay_side < 0.0 else 1.04
		var x_b := -1.04 if bay_side < 0.0 else 2.88
		var mid := (x_a + x_b) * 0.5
		var leaf_w := (x_b - x_a) * 0.53
		var leaves_x: Array = [
			[x_a + leaf_w * 0.5, SHOJI_Z - 0.028],
			[x_b - leaf_w * 0.5, SHOJI_Z + 0.022],
		]
		for ld: Array in leaves_x:
			var lx: float = ld[0]
			var lz: float = ld[1]
			# Outer dark-cedar stiles & rails of the sliding shoji door.
			c.u.surface(wood_u)
			c.u.colour = _lin(CEDAR_DARK)
			for s: float in [-1.0, 1.0]:
				c.u.box(Vector3(lx + s * (leaf_w * 0.5 - 0.028), 1.20, lz), Vector3(0.056, 2.30, 0.036))
			c.u.box(Vector3(lx, 0.08, lz), Vector3(leaf_w, 0.06, 0.036))
			c.u.box(Vector3(lx, 2.33, lz), Vector3(leaf_w, 0.06, 0.036))
			# Lower solid hinoki kick-panel (koshita, y = 0.11..0.52).
			c.u.colour = _lin(HINOKI_WARM * 0.82)
			c.u.box(Vector3(lx, 0.315, lz), Vector3(leaf_w - 0.10, 0.41, 0.022))
			c.u.colour = _lin(CEDAR_DARK)
			c.u.box(Vector3(lx, 0.53, lz), Vector3(leaf_w - 0.06, 0.04, 0.036))

			# Translucent softly backlit washi rice-paper sheet in PieceCove (warm glowing centre, soft edge falloff!).
			var pw := leaf_w - 0.11
			var py0 := 0.55
			var py1 := 2.30
			var pz := lz + 0.002
			c.cove.surface(cove_m)
			var washi_lin := _lin(WASHI_CREAM)
			var p_rows: Array = []
			var p_norms: Array = []
			var p_cols: Array = []
			for iy in 5:
				var vy := float(iy) / 4.0
				var yy := lerpf(py0, py1, vy)
				var wy := sin(PI * lerpf(0.14, 0.86, vy))
				var r_v := PackedVector3Array()
				var r_n := PackedVector3Array()
				var r_c := PackedColorArray()
				for ix in 4:
					var vx := float(ix) / 3.0
					var xx := lerpf(lx - pw * 0.5, lx + pw * 0.5, vx)
					var wx := sin(PI * lerpf(0.18, 0.82, vx))
					var glow_w := clampf(0.42 + 0.54 * wx * wy, 0.32, 0.96)
					r_v.append(Vector3(xx, yy, pz))
					r_n.append(Vector3.FORWARD)
					r_c.append(Color(washi_lin.r, washi_lin.g, washi_lin.b, glow_w))
				p_rows.append(r_v)
				p_norms.append(r_n)
				p_cols.append(r_c)
			c.cove.grid(p_rows, p_norms, p_cols)
			# Solid backing behind shoji so no sky peeks through the aft wall when viewed from behind!
			c.s.surface(plaster_s)
			c.s.colour = _lin(PLASTER_EARTHEN * 0.55)
			c.s.face([
				Vector3(lx - pw * 0.5, py0, lz + 0.026),
				Vector3(lx + pw * 0.5, py0, lz + 0.026),
				Vector3(lx + pw * 0.5, py1, lz + 0.026),
				Vector3(lx - pw * 0.5, py1, lz + 0.026),
			], Vector3.BACK)

			# Fine dark-cedar kumiko lattice mullions cleanly proud of the washi paper (z = lz - 0.010, zero Z-fight!).
			c.u.surface(wood_u)
			c.u.colour = _lin(CEDAR_DARK)
			var kz := lz - 0.011
			for k in 3:
				var mx := lx - pw * 0.5 + pw * float(k + 1) / 4.0
				c.u.box(Vector3(mx, (py0 + py1) * 0.5, kz), Vector3(0.016, py1 - py0, 0.016))
			for k in 6:
				var my := py0 + (py1 - py0) * float(k + 1) / 7.0
				c.u.box(Vector3(lx, my, kz), Vector3(pw, 0.016, 0.016))

		# Carved openwork cedar ranma transom lattice above the shoji tracks (y = 2.46..3.24).
		c.u.surface(wood_u)
		c.u.colour = _lin(HINOKI_WARM * 0.78)
		var rw := x_b - x_a
		for k in 2:
			c.u.box(Vector3(mid, 2.66 + float(k) * 0.34, SHOJI_Z), Vector3(rw, 0.026, 0.04))
		for k in 7:
			var rx := lerpf(x_a + 0.14, x_b - 0.14, float(k) / 6.0)
			c.u.box(Vector3(rx, 2.84, SHOJI_Z), Vector3(0.024, 0.76, 0.04))
		# Recessed warm earthen plaster transom backing wall behind the ranma grille.
		c.s.surface(plaster_s)
		c.s.colour = _lin(PLASTER_TOKO * 0.78)
		c.s.box(Vector3(mid, 2.86, SHOJI_Z + 0.08), Vector3(rw, 0.84, 0.08))

	# Physics box for the aft shoji wall (strictly behind z = 2.80, well clear of seats!).
	_solid(c, Vector3(0.0, 1.65, SHOJI_Z + 0.12), Vector3(6.0, 3.30, 0.24))

	# 3. Central Recessed Tokonoma Display Alcove (x = -0.89..+0.89, z = SHOJI_Z..SHOJI_Z + 0.72).
	var tz0 := SHOJI_Z
	var tz1 := SHOJI_Z + 0.72
	# Raised glossy dark-lacquered hinoki toko-ita display dais (y = 0.0..0.14 m).
	c.u.surface(lacquer)
	c.u.colour = _lin(LACQUER_DARK)
	c.u.box(Vector3(0.0, 0.07, (tz0 + tz1) * 0.5), Vector3(1.80, 0.14, tz1 - tz0), Basis(), [RoomMesh.DOWN])
	# Warm sand-plaster juraku alcove back wall, side cheeks, ceiling cap (strictly <= 3.00 m beneath the aft eave
	# roof soffit!), and lowered header brow (otoshigake).
	c.s.surface(plaster_s)
	c.s.colour = _lin(PLASTER_TOKO)
	c.s.box(Vector3(0.0, 1.50, tz1 + 0.06), Vector3(2.04, 3.00, 0.12))
	for sx: float in [-1.0, 1.0]:
		c.s.box(Vector3(sx * 0.94, 1.50, (tz0 + tz1) * 0.5), Vector3(0.10, 3.00, tz1 - tz0))
	c.s.box(Vector3(0.0, 2.94, (tz0 + tz1) * 0.5), Vector3(2.04, 0.12, tz1 - tz0 + 0.14))
	c.s.box(Vector3(0.0, 2.86, tz0 + 0.05), Vector3(1.84, 0.78, 0.10))
	c.s.colour = _lin(CEDAR_DARK)
	c.s.box(Vector3(0.0, 2.47, tz0 + 0.04), Vector3(1.86, 0.08, 0.12))

	# Warm recessed tokonoma alcove back-wall cove glow (PieceCove) illuminating the scroll & ikebana!
	c.cove.surface(cove_m)
	var tc_lin := _lin(PLASTER_TOKO * 1.25)
	var t_r0 := PackedVector3Array([Vector3(-0.84, 2.46, tz1 - 0.015), Vector3(0.0, 2.46, tz1 - 0.015),
			Vector3(0.84, 2.46, tz1 - 0.015)])
	var t_r1 := PackedVector3Array([Vector3(-0.84, 1.15, tz1 - 0.015), Vector3(0.0, 1.15, tz1 - 0.015),
			Vector3(0.84, 1.15, tz1 - 0.015)])
	var t_n := PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	var t_c0 := PackedColorArray([Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.72), Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.92),
			Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.72)])
	var t_c1 := PackedColorArray([Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.08), Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.14),
			Color(tc_lin.r, tc_lin.g, tc_lin.b, 0.08)])
	c.cove.grid([t_r0, t_r1], [t_n, t_n], [t_c0, t_c1])
	# Hidden warm tokonoma alcove bake/stand-in lamp (lamp #8 of 8!).
	c.lamps.append([Vector3(0.0, 2.28, tz0 + 0.34), WASHI_LAMP, 0.65])

	# 4. Minimalist Zen Hanging Scroll (Kakejiku) on the tokonoma back wall (x = -0.20, y = 0.94..2.22).
	var sx_s := -0.20
	var sz_s := tz1 - 0.032
	# Indigo-brocade silk scroll mount.
	c.u.surface(leaf_u)
	c.u.colour = _lin(INDIGO_SILK)
	c.u.box(Vector3(sx_s, 1.58, sz_s), Vector3(0.64, 1.28, 0.010))
	# Warm ivory parchment artwork field (strictly proud by 7 mm, zero Z-fighting).
	c.u.colour = _lin(WASHI_CREAM * 0.95)
	c.u.face([
		Vector3(sx_s - 0.25, 1.12, sz_s - 0.008),
		Vector3(sx_s + 0.25, 1.12, sz_s - 0.008),
		Vector3(sx_s + 0.25, 2.02, sz_s - 0.008),
		Vector3(sx_s - 0.25, 2.02, sz_s - 0.008),
	], Vector3.FORWARD)
	# Minimalist sumi-e ink-wash mountain peaks + Zen enso brush ring + tiny vermilion artist seal (hanko).
	var iz := sz_s - 0.013
	c.u.colour = _lin(Color(0.24, 0.25, 0.27))
	c.u.face([Vector3(sx_s - 0.23, 1.14, iz), Vector3(sx_s + 0.06, 1.14, iz), Vector3(sx_s - 0.10, 1.42, iz)],
			Vector3.FORWARD)
	c.u.colour = _lin(Color(0.14, 0.15, 0.17))
	c.u.face([Vector3(sx_s - 0.06, 1.14, iz - 0.002), Vector3(sx_s + 0.23, 1.14, iz - 0.002),
			Vector3(sx_s + 0.10, 1.35, iz - 0.002)], Vector3.FORWARD)
	# Brushed Zen enso ink circle (open arc of 14 crisp segments!).
	Shapes.arch(c.u, Vector3(sx_s, 1.72, iz - 0.002), 0.125, 0.155, 0.004, 14, Basis(), 0.35, TAU - 0.22, ["back"])
	# Tiny vermilion hanko stamp in lower-left corner.
	c.u.colour = _lin(VERMILION)
	c.u.face([
		Vector3(sx_s - 0.20, 1.18, iz - 0.003), Vector3(sx_s - 0.16, 1.18, iz - 0.003),
		Vector3(sx_s - 0.16, 1.22, iz - 0.003), Vector3(sx_s - 0.20, 1.22, iz - 0.003),
	], Vector3.FORWARD)
	# Turned dark-lacquer bottom scroll roller rod (jiku) with ivory jikusaki end-caps, top dowel & silk hanging cord!
	c.u.surface(wood_u)
	c.u.colour = _lin(LACQUER_DARK)
	var rod_b := Basis(Vector3.BACK, -PI * 0.5)
	Shapes.cylinder(c.u, Vector3(sx_s - 0.34, 0.94, sz_s - 0.010), 0.016, 0.68, 8, rod_b, true)
	Shapes.cylinder(c.u, Vector3(sx_s - 0.33, 2.22, sz_s - 0.006), 0.010, 0.66, 8, rod_b, true)
	c.u.surface(stone_u)
	c.u.colour = _lin(WASHI_CREAM)
	Shapes.cylinder(c.u, Vector3(sx_s - 0.375, 0.94, sz_s - 0.010), 0.017, 0.036, 8, rod_b, true)
	Shapes.cylinder(c.u, Vector3(sx_s + 0.339, 0.94, sz_s - 0.010), 0.017, 0.036, 8, rod_b, true)
	c.u.surface(wood_u)
	c.u.colour = _lin(CEDAR_DARK)
	Shapes.beam(c.u, Vector3(sx_s - 0.24, 2.22, sz_s - 0.008), Vector3(sx_s, 2.38, sz_s - 0.008), Vector2(0.006, 0.006))
	Shapes.beam(c.u, Vector3(sx_s + 0.24, 2.22, sz_s - 0.008), Vector3(sx_s, 2.38, sz_s - 0.008), Vector2(0.006, 0.006))

	# 5. Ceramic Ikebana Vase with Blossoming Plum/Cherry Branch on dark-lacquer stand (x = +0.44, z = tz0 + 0.36).
	var vx := 0.44
	var vz := tz0 + 0.36
	c.u.surface(lacquer)
	c.u.colour = _lin(LACQUER_DARK)
	c.u.box(Vector3(vx, 0.165, vz), Vector3(0.32, 0.05, 0.24), Basis(), [RoomMesh.DOWN])
	# Lathed celadon stoneware ikebana vase (y = 0.19 .. 0.55 m).
	c.u.surface(stone_u)
	c.u.colour = _lin(CELADON)
	Shapes.lathe(c.u, [
		Vector2(0.065, 0.0), Vector2(0.105, 0.08), Vector2(0.118, 0.18),
		Vector2(0.072, 0.27), Vector2(0.052, 0.32), Vector2(0.064, 0.36), Vector2(0.044, 0.36),
	], Vector3(vx, 0.19, vz), 12)
	# Gracefully arching dark plum/cherry twigs rising out of the vase with delicate blossom petals!
	c.u.surface(wood_u)
	c.u.colour = _lin(BARK_DARK)
	var v_mouth := Vector3(vx, 0.53, vz)
	var b1 := v_mouth + Vector3(-0.14, 0.30, -0.06)
	var b1t := b1 + Vector3(-0.22, 0.28, -0.08)
	var b2 := v_mouth + Vector3(0.12, 0.24, -0.05)
	var b2t := b2 + Vector3(0.16, 0.22, 0.04)
	var b3 := v_mouth + Vector3(-0.02, 0.36, 0.08)
	Shapes.beam(c.u, v_mouth, b1, Vector2(0.016, 0.016))
	Shapes.beam(c.u, b1, b1t, Vector2(0.010, 0.010))
	Shapes.beam(c.u, v_mouth, b2, Vector2(0.014, 0.014))
	Shapes.beam(c.u, b2, b2t, Vector2(0.009, 0.009))
	Shapes.beam(c.u, v_mouth, b3, Vector2(0.012, 0.012))
	c.u.surface(leaf_u)
	for bp: Vector3 in [b1, b1.lerp(b1t, 0.55), b1t, b2, b2t, b3, b1 + Vector3(0.04, 0.08, -0.04),
			b2 + Vector3(-0.05, 0.06, -0.04)]:
		c.u.colour = _lin(LOTUS_PINK)
		c.u.rounded_box(Vector3.ZERO, Vector3(0.075, 0.055, 0.075), 0.024, Transform3D(Basis(), bp), 1)


## Low dark-lacquered cedar chabudai tea table (height = 0.30 m <= 0.34 m, strictly clear of every sight line and
## >= 1.25 m clear of viewer origin!) resting on the front engawa overlooking the koi pond, holding a cypress tray,
## cast-iron kyusu teapot, two stoneware matcha cups, and a wagashi sweet plate.
static func _build_chabudai_and_tea_set(c: Object) -> void:
	var lacquer: Material = _lacquer(c)
	var wood_u: Material = c.soft("wood")
	var stone_u: Material = c.soft("stone")
	var leaf_u: Material = c.soft("leaves")

	var tc := Vector3(0.0, ENGAWA_Y, -1.56) # z = -1.84..-1.28 on the front engawa -> clearly framed & > 0.65 m below sight!
	var tw := 1.12
	var td := 0.56
	var th := 0.30 # strictly <= 0.34 m!

	# Glossy dark-lacquered tabletop with gentle rounded edge & recessed skirt apron.
	c.u.surface(lacquer)
	c.u.colour = _lin(LACQUER_DARK)
	c.u.rounded_box(Vector3.ZERO, Vector3(tw, 0.042, td), 0.014,
			Transform3D(Basis(), tc + Vector3(0.0, th - 0.021, 0.0)), 1)
	c.u.surface(wood_u)
	c.u.colour = _lin(CEDAR_DEEP)
	c.u.box(tc + Vector3(0.0, th - 0.062, 0.0), Vector3(tw - 0.14, 0.044, td - 0.12))
	# Four graceful slightly bowed chabudai legs.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var top_p := tc + Vector3(sx * (tw * 0.5 - 0.10), th - 0.04, sz * (td * 0.5 - 0.09))
			var mid_p := tc + Vector3(sx * (tw * 0.5 - 0.075), th * 0.52, sz * (td * 0.5 - 0.07))
			var foot_p := tc + Vector3(sx * (tw * 0.5 - 0.11), 0.0, sz * (td * 0.5 - 0.095))
			Shapes.beam(c.u, top_p, mid_p, Vector2(0.044, 0.044))
			Shapes.beam(c.u, mid_p, foot_p, Vector2(0.036, 0.036))
	_solid(c, tc + Vector3(0.0, th * 0.5, 0.0), Vector3(tw, th, td))

	# Warm hinoki wooden tea tray resting cleanly flush on top of the chabudai (relative offset ty = th).
	var ty := th
	c.u.surface(wood_u)
	c.u.colour = _lin(HINOKI_WARM * 0.88)
	c.u.box(tc + Vector3(-0.04, ty + 0.008, 0.0), Vector3(0.46, 0.016, 0.30), Basis(), [RoomMesh.DOWN])
	# Raised tray rim rails.
	c.u.colour = _lin(CEDAR_DARK)
	for sz: float in [-1.0, 1.0]:
		c.u.box(tc + Vector3(-0.04, ty + 0.020, sz * 0.142), Vector3(0.46, 0.016, 0.016))
	for sx: float in [-1.0, 1.0]:
		c.u.box(tc + Vector3(-0.04 + sx * 0.222, ty + 0.020, 0.0), Vector3(0.016, 0.016, 0.27))

	# Cast-iron / dark-stoneware kyusu teapot (lathed body, lid knob, spout, side handle; top y = 0.45 m).
	var kp := tc + Vector3(-0.14, ty + 0.016, -0.02)
	c.u.surface(stone_u)
	c.u.colour = _lin(Color(0.14, 0.135, 0.14))
	Shapes.lathe(c.u, [
		Vector2(0.055, 0.0), Vector2(0.088, 0.032), Vector2(0.092, 0.068),
		Vector2(0.066, 0.102), Vector2(0.052, 0.108), Vector2(0.048, 0.116),
		Vector2(0.014, 0.122), Vector2(0.018, 0.134), Vector2(0.0, 0.138),
	], kp, 12)
	# Pouring spout & traditional side-grip kyusu handle.
	Shapes.beam(c.u, kp + Vector3(0.072, 0.052, 0.0), kp + Vector3(0.135, 0.095, 0.0), Vector2(0.020, 0.020))
	Shapes.beam(c.u, kp + Vector3(0.0, 0.064, 0.075), kp + Vector3(0.0, 0.072, 0.155), Vector2(0.022, 0.022))

	# Two handcrafted stoneware matcha yunomi cups filled with vivid jade-green matcha!
	for cup_off: Vector3 in [Vector3(0.07, ty + 0.016, -0.05), Vector3(0.11, ty + 0.016, 0.06)]:
		var cp := tc + cup_off
		c.u.surface(stone_u)
		c.u.colour = _lin(Color(0.32, 0.28, 0.24))
		Shapes.lathe(c.u, [
			Vector2(0.026, 0.0), Vector2(0.038, 0.020), Vector2(0.041, 0.064),
			Vector2(0.037, 0.068), Vector2(0.034, 0.062),
		], cp, 10)
		c.u.surface(leaf_u)
		c.u.colour = _lin(MATCHA_JADE)
		var tea_pts: Array = []
		for k in 8:
			var a := TAU * float(k) / 8.0
			tea_pts.append(cp + Vector3(cos(a) * 0.033, 0.056, sin(a) * 0.033))
		c.u.face(tea_pts, Vector3.UP)

	# Small lacquered wagashi sweet plate resting to the right of the tray.
	c.u.surface(lacquer)
	c.u.colour = _lin(VERMILION_DARK)
	c.u.box(tc + Vector3(0.34, ty + 0.008, 0.03), Vector3(0.16, 0.014, 0.12), Basis(), [RoomMesh.DOWN])
	c.u.surface(leaf_u)
	c.u.colour = _lin(LOTUS_PINK)
	c.u.rounded_box(Vector3.ZERO, Vector3(0.052, 0.032, 0.052), 0.015,
			Transform3D(Basis(), tc + Vector3(0.34, ty + 0.028, 0.03)), 1)


## Four traditional square hinoki-and-washi andon floor lanterns glowing warmly at the engawa verandah corners.
static func _build_andon_lanterns(c: Object) -> void:
	var wood_u: Material = c.soft("wood")
	var shade_m: Material = c.shade(WASHI_LAMP)

	for pos: Vector3 in ANDON_POS:
		var w := 0.28
		var h := 0.62
		var hw := w * 0.5
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DARK)
		# Square base plinth & four tiny corner feet.
		c.u.box(pos + Vector3(0.0, 0.045, 0.0), Vector3(w + 0.04, 0.036, w + 0.04))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				c.u.box(pos + Vector3(sx * hw, 0.016, sz * hw), Vector3(0.032, 0.032, 0.032), Basis(), [RoomMesh.DOWN])
				# Slender corner uprights rising to the open crown rim.
				c.u.box(pos + Vector3(sx * (hw - 0.012), h * 0.5 + 0.02, sz * (hw - 0.012)),
						Vector3(0.024, h - 0.04, 0.024))
		# Horizontal upper, middle, and lower kumiko lantern frame bars.
		for ry: float in [0.10, 0.34, h - 0.015]:
			for sz: float in [-1.0, 1.0]:
				c.u.box(pos + Vector3(0.0, ry, sz * (hw - 0.012)), Vector3(w, 0.022, 0.022))
			for sx: float in [-1.0, 1.0]:
				c.u.box(pos + Vector3(sx * (hw - 0.012), ry, 0.0), Vector3(0.022, 0.022, w))
		# Glowing translucent square washi shade core inside the frame (PieceLamps, house group!).
		c.lit.surface(shade_m)
		c.lit.box(pos + Vector3(0.0, 0.34, 0.0), Vector3(w - 0.056, 0.47, w - 0.056), Basis(),
				[RoomMesh.UP, RoomMesh.DOWN])
		# Warm stand-in & hidden bake lamp inside each andon!
		c.lamps.append([pos + Vector3(0.0, 0.42, 0.0), WASHI_LAMP, 0.85])
		_solid(c, pos + Vector3(0.0, h * 0.5, 0.0), Vector3(w + 0.04, h, w + 0.04))


## Elegant freestanding dark-cypress torii / garden pavilion frame rising directly out of the far edge of the koi pond
## around SCREEN_C = (0.0, 2.25, -8.40), keeping the picture 100% unobstructed from every seat!
static func _build_screen_torii_frame(c: Object) -> void:
	var wood_s: Material = c.tinted("wood")
	var wood_u: Material = c.soft("wood")
	var stone_s: Material = c.tinted("stone")
	var roof_s: Material = c.tinted("roof", "roof_tiles")
	var gilt: Material = _gilt(c)
	var cove_m: Material = c.kit.cove_material()

	var sc := SCREEN_C
	var hw := SCREEN_W * 0.5 # 2.50 m
	var hh := SCREEN_H * 0.5 # 1.405 m
	var y_bot := sc.y - hh # 0.845 m
	var y_top := sc.y + hh # 3.655 m
	var fz := sc.z - 0.06 # strictly behind the screen picture plane z = -8.40!

	# 1. Dark charcoal matte backing slab directly behind the screen picture (zero reflection/bleed).
	c.s.surface(wood_s)
	c.s.colour = _lin(BACKING_CHARCOAL)
	c.s.box(Vector3(sc.x, sc.y, sc.z - 0.11), Vector3(SCREEN_W + 0.26, SCREEN_H + 0.24, 0.12))

	# 2. Crisp bevelled dark-hinoki picture border surround (strictly outside [-2.50..+2.50, 0.845..3.655]!).
	c.s.colour = _lin(CEDAR_DARK)
	var mw := 0.13
	c.s.box(Vector3(0.0, y_bot - mw * 0.5, fz), Vector3(SCREEN_W + mw * 2.0, mw, 0.14))
	c.s.box(Vector3(0.0, y_top + mw * 0.5, fz), Vector3(SCREEN_W + mw * 2.0, mw, 0.14))
	for sx: float in [-1.0, 1.0]:
		c.s.box(Vector3(sx * (hw + mw * 0.5), sc.y, fz), Vector3(mw, SCREEN_H, 0.14))

	# 3. Monumental twin dark-cypress torii/pavilion columns rising out of submerged granite bases in the koi pond!
	var col_x := hw + 0.34 # +-2.84 m
	var col_top := y_top + 0.72 # 4.375 m
	for sx: float in [-1.0, 1.0]:
		var cx := sx * col_x
		# Broad submerged & emergent mossy granite pier stone in the pond.
		c.s.surface(stone_s)
		c.s.colour = _lin(GRANITE_WET)
		c.s.box(Vector3(cx, -0.34, fz - 0.04), Vector3(0.68, 0.68, 0.68), Basis(), [RoomMesh.DOWN])
		c.s.colour = _lin(GRANITE_MID)
		c.s.box(Vector3(cx, 0.05, fz - 0.04), Vector3(0.54, 0.14, 0.54), Basis(), [RoomMesh.DOWN])
		# Sturdy tapered cylindrical dark-cypress column (hashira) with dark bronze base & capital collar.
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DEEP)
		Shapes.lathe(c.u, [
			Vector2(0.165, 0.12), Vector2(0.155, 1.50), Vector2(0.145, 3.20), Vector2(0.140, col_top),
		], Vector3(cx, 0.0, fz - 0.04), 12)
		c.u.surface(gilt)
		c.u.colour = _lin(BRASS_GOLD * 0.75)
		Shapes.lathe(c.u, [
			Vector2(0.172, 0.12), Vector2(0.172, 0.24), Vector2(0.155, 0.26),
		], Vector3(cx, 0.0, fz - 0.04), 12)
		# Aft diagonal timber brace struts anchoring the freestanding garden frame cleanly into the rear bank.
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DEEP)
		Shapes.beam(c.u, Vector3(cx, 2.35, fz - 0.12), Vector3(cx, -0.45, fz - 1.15), Vector2(0.12, 0.12))
		_solid(c, Vector3(cx, col_top * 0.5, fz - 0.04), Vector3(0.36, col_top, 0.36))

	# 4. Lower tie-beam (nuki) beneath the screen & iconic sweeping upturned kasagi torii/pavilion roof crown above!
	c.s.surface(wood_s)
	c.s.colour = _lin(CEDAR_DARK)
	c.s.box(Vector3(0.0, 0.56, fz - 0.04), Vector3(col_x * 2.0 + 1.05, 0.20, 0.20))
	# Secondary upper nuki cross-beam with vermilion-gold accent tie wedges (kusabi) & central plaque block (gakuzuka).
	c.s.box(Vector3(0.0, y_top + 0.30, fz - 0.04), Vector3(col_x * 2.0 + 1.25, 0.18, 0.20))
	c.s.colour = _lin(VERMILION_DARK)
	c.s.box(Vector3(0.0, y_top + 0.52, fz - 0.02), Vector3(0.34, 0.34, 0.16))
	c.u.surface(gilt)
	c.u.colour = _lin(BRASS_GOLD)
	c.u.box(Vector3(0.0, y_top + 0.52, fz + 0.065), Vector3(0.18, 0.18, 0.02), Basis(Vector3.BACK, PI * 0.25))

	# Sweeping upturned kasagi beam & pitched dark-kawara rain-hood eaves crowning the screen frame!
	var segs := 10
	var span_hw := col_x + 1.05 # 3.89 m each side!
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var tm := (t0 + t1) * 0.5
		var xm := lerpf(-span_hw, span_hw, tm)
		var u := (tm - 0.5) * 2.0 # -1..+1
		var u0 := (t0 - 0.5) * 2.0
		var u1 := (t1 - 0.5) * 2.0
		var lift := 0.26 * pow(absf(u), 2.4)
		var slope_ang := atan2(0.26 * (pow(absf(u1), 2.4) - pow(absf(u0), 2.4)),
				(span_hw * 2.0) / float(segs))
		var bs := Basis(Vector3.BACK, slope_ang)
		var seg_w := (span_hw * 2.0) / float(segs) + 0.04
		c.s.surface(wood_s)
		c.s.colour = _lin(CEDAR_DEEP)
		c.s.box(Vector3(xm, col_top + 0.04 + lift, fz - 0.04), Vector3(seg_w, 0.20, 0.58), bs)
		c.s.surface(roof_s)
		c.s.colour = _lin(KAWARA_TILE)
		c.s.box(Vector3(xm, col_top + 0.20 + lift, fz - 0.04), Vector3(seg_w + 0.02, 0.14, 0.88), bs)

	# Soft warm PieceCove wash along the underside of the overhanging upper screen lintel (frames the screen subtly!).
	c.cove.surface(cove_m)
	var fc_lin := _lin(HINOKI_WARM * 1.1)
	var f_r0 := PackedVector3Array([Vector3(-2.60, y_top + 0.19, fz + 0.04), Vector3(0.0, y_top + 0.19, fz + 0.04),
			Vector3(2.60, y_top + 0.19, fz + 0.04)])
	var f_r1 := PackedVector3Array([Vector3(-2.60, y_top + 0.19, fz - 0.20), Vector3(0.0, y_top + 0.19, fz - 0.20),
			Vector3(2.60, y_top + 0.19, fz - 0.20)])
	var f_n := PackedVector3Array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	var f_c0 := PackedColorArray([Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.42), Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.62),
			Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.42)])
	var f_c1 := PackedColorArray([Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.05), Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.08),
			Color(fc_lin.r, fc_lin.g, fc_lin.b, 0.05)])
	c.cove.grid([f_r0, f_r1], [f_n, f_n], [f_c0, f_c1])


# --- Piece 2: kyoto_garden --------------------------------------------------------------------------------------------

static func _build_garden(c: Object, _h: KyotoGardenHall) -> void:
	_build_garden_ground_and_gravel(c)
	_build_pond_boulders_and_lilies(c)
	_build_vermilion_footbridge(c)
	_build_yukimi_lanterns(c)
	_build_shishi_odoshi_basin(c)
	_build_enclosure_wall_and_bamboo(c)
	_build_tree_trunks(c)


## Garden earth apron, dry raked karesansui Zen gravel courtyard on the port flank with sculpted harmonic wave ridges
## and concentric ripples around three mossy dark-andesite sanzon-seki feature rocks.
static func _build_garden_ground_and_gravel(c: Object) -> void:
	var plaster_s: Material = c.tinted("plaster")
	var stone_s: Material = c.tinted("stone")
	var stone_u: Material = c.soft("stone")
	var leaf_u: Material = c.soft("leaves")

	# 1. Dark mossy Kyoto garden earth apron extending all the way under the walls & pond banks (y = GROUND_Y = -0.49).
	c.s.surface(stone_s)
	c.s.colour = _lin(Color(0.11, 0.16, 0.10))
	c.s.face([
		Vector3(-12.5, GROUND_Y, -12.5),
		Vector3(12.5, GROUND_Y, -12.5),
		Vector3(12.5, GROUND_Y, 8.0),
		Vector3(-12.5, GROUND_Y, 8.0),
	], Vector3.UP)

	# 2. Port raked-sand karesansui Zen gravel courtyard (x = -11.65 .. -3.35, z = -3.60 .. +5.40, y = GRAVEL_Y = -0.45).
	#    Three mossy dark-andesite feature boulders (sanzon-seki triad) with concentric raked sand ripples around them!
	var zen_rocks: Array = [
		[Vector3(-6.35, GRAVEL_Y, -0.55), Vector3(0.95, 1.18, 0.78), 0.35, 1.35],  # tall central guardian boulder
		[Vector3(-7.35, GRAVEL_Y, 0.65), Vector3(1.18, 0.64, 0.82), -0.45, 1.25],  # low reclining horizontal stone
		[Vector3(-5.65, GRAVEL_Y, 1.05), Vector3(0.68, 0.52, 0.62), 0.80, 1.05],   # smaller companion accent stone
	]
	var nx := 36
	var nz := 40
	var g_rows: Array = []
	var g_norms: Array = []
	var g_cols: Array = []
	for iz in nz + 1:
		var z := lerpf(-3.60, 5.40, float(iz) / float(nz))
		var r_p := PackedVector3Array()
		var r_n := PackedVector3Array()
		var r_c := PackedColorArray()
		for ix in nx + 1:
			var x := lerpf(-11.65, -3.35, float(ix) / float(nx))
			# Crisp parallel raked wave flutes running gracefully along Z.
			var wave := sin(x * TAU / 0.28)
			# Blend smoothly into concentric raked ripple rings around the Zen feature boulders!
			var ring_w := 0.0
			var ring_v := 0.0
			for zr: Array in zen_rocks:
				var rp: Vector3 = zr[0]
				var rad_inf: float = zr[3]
				var dist := Vector2(x - rp.x, z - rp.z).length()
				var w := 1.0 - smoothstep(0.55, rad_inf + 0.90, dist)
				if w > ring_w:
					ring_w = w
					ring_v = sin(dist * TAU / 0.26)
			var ridge := lerpf(wave, ring_v, ring_w)
			var y := GRAVEL_Y + 0.024 * ridge
			r_p.append(Vector3(x, y, z))
			r_n.append(Vector3(-0.24 * cos(x * TAU / 0.28), 1.0, 0.0).normalized())
			var gcol := GRAVEL_SHADE.lerp(GRAVEL_PALE, 0.5 + 0.5 * ridge)
			r_c.append(_lin(gcol))
		g_rows.append(r_p)
		g_norms.append(r_n)
		g_cols.append(r_c)
	c.s.surface(plaster_s)
	c.s.sheet(g_rows, g_norms, g_cols, Vector3.RIGHT, Vector3.BACK)

	# Dark mossy granite curbing neatly separating the dry Zen gravel courtyard from the koi pond & garden perimeter.
	c.s.surface(stone_s)
	c.s.colour = _lin(GRANITE_WET)
	c.s.box(Vector3(-7.50, GRAVEL_Y + 0.04, -3.65), Vector3(8.35, 0.14, 0.18), Basis(), [RoomMesh.DOWN])
	c.s.box(Vector3(-7.50, GRAVEL_Y + 0.04, 5.45), Vector3(8.35, 0.14, 0.18), Basis(), [RoomMesh.DOWN])
	c.s.box(Vector3(-3.32, GRAVEL_Y + 0.04, 0.90), Vector3(0.16, 0.14, 9.10), Basis(), [RoomMesh.DOWN])

	# Sculpt the three mossy Zen feature boulders (sanzon-seki) sitting on emerald-moss cushion mounds!
	for zr: Array in zen_rocks:
		var rp: Vector3 = zr[0]
		var sz: Vector3 = zr[1]
		var yaw: float = zr[2]
		var bs := Basis(Vector3.UP, yaw)
		c.u.surface(leaf_u)
		c.u.colour = _lin(MOSS_GREEN)
		c.u.rounded_box(Vector3.ZERO, Vector3(sz.x * 1.48, 0.18, sz.z * 1.48), 0.08,
				Transform3D(bs, rp + Vector3(0.0, 0.05, 0.0)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		c.u.surface(stone_u)
		c.u.colour = _lin(GRANITE_MID * 0.78)
		c.u.rounded_box(Vector3.ZERO, sz, minf(sz.x, sz.z) * 0.28,
				Transform3D(bs * Basis(Vector3.RIGHT, 0.12), rp + Vector3(0.0, sz.y * 0.42, 0.0)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		# Secondary shoulder facet for natural fractured Kyoto andesite character.
		c.u.colour = _lin(GRANITE_LIGHT * 0.72)
		c.u.rounded_box(Vector3.ZERO, sz * Vector3(0.68, 0.62, 0.74), 0.12,
				Transform3D(bs * Basis(Vector3.BACK, -0.18), rp + bs * Vector3(sz.x * 0.24, sz.y * 0.28, 0.06)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])


## Smooth mossy Kyoto river boulders rimming the koi pond shoreline, floating emerald lily pads, and pale-pink lotus buds.
static func _build_pond_boulders_and_lilies(c: Object) -> void:
	var stone_u: Material = c.soft("stone")
	var leaf_u: Material = c.soft("leaves")

	# Organic river boulder shoreline framing the front, port, far, and starboard koi pond banks!
	var rng := RandomNumberGenerator.new()
	rng.seed = 1603
	var bank_pts: Array[Vector3] = [
		# Front-port shoreline curving from pavilion to front-port stone lantern & beyond screen.
		Vector3(-3.75, WATER_Y, -2.55), Vector3(-4.85, WATER_Y, -3.55), Vector3(-5.25, WATER_Y, -4.65),
		Vector3(-5.15, WATER_Y, -5.85), Vector3(-5.35, WATER_Y, -7.10), Vector3(-5.10, WATER_Y, -8.35),
		Vector3(-4.15, WATER_Y, -9.25),
		# Far bank behind the koi pond & screen frame.
		Vector3(-2.60, WATER_Y, -9.45), Vector3(-0.90, WATER_Y, -9.55), Vector3(0.95, WATER_Y, -9.55),
		Vector3(2.85, WATER_Y, -9.40), Vector3(4.55, WATER_Y, -9.25), Vector3(6.35, WATER_Y, -9.15),
		Vector3(7.95, WATER_Y, -8.45),
		# Far starboard shoreline sweeping past the footbridge & starboard lantern.
		Vector3(8.45, WATER_Y, -6.85), Vector3(8.35, WATER_Y, -5.05), Vector3(8.55, WATER_Y, -3.15),
		Vector3(8.45, WATER_Y, -1.25), Vector3(8.50, WATER_Y, 0.75), Vector3(8.20, WATER_Y, 2.65),
		Vector3(7.15, WATER_Y, 3.95), Vector3(5.35, WATER_Y, 4.35), Vector3(3.65, WATER_Y, 3.85),
		# Inner boulder accent cluster by the front-starboard bridge abutment.
		Vector3(4.25, WATER_Y, -3.95), Vector3(4.35, WATER_Y, 0.65),
	]
	for bp: Vector3 in bank_pts:
		var sx := rng.randf_range(0.75, 1.45)
		var sy := rng.randf_range(0.32, 0.76)
		var sz := rng.randf_range(0.68, 1.35)
		var yaw := rng.randf_range(0.0, TAU)
		var bs := Basis(Vector3.UP, yaw)
		c.u.surface(stone_u)
		c.u.colour = _lin(GRANITE_WET.lerp(GRANITE_MID, rng.randf_range(0.15, 0.75)))
		c.u.rounded_box(Vector3.ZERO, Vector3(sx, sy, sz), minf(sy * 0.45, 0.24),
				Transform3D(bs, bp + Vector3(0.0, sy * 0.24, 0.0)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		# Companion smaller stone + mossy emerald cap on roughly half the boulders.
		if rng.randf() < 0.65:
			c.u.surface(leaf_u)
			c.u.colour = _lin(MOSS_GREEN.lerp(MOSS_BRIGHT, rng.randf()))
			c.u.rounded_box(Vector3.ZERO, Vector3(sx * 0.68, 0.11, sz * 0.66), 0.045,
					Transform3D(bs, bp + Vector3(0.0, sy * 0.62, 0.0)), 1, Vector3i.ZERO, 0.0, [RoomMesh.DOWN])

	# Floating emerald lily pads resting cleanly 7 mm above WATER_Y (zero Z-fighting!) + delicate pink/ivory lotus buds.
	var lily_clusters: Array = [
		[Vector3(-2.45, WATER_Y + 0.008, -4.35), 0.22, true],
		[Vector3(-2.10, WATER_Y + 0.008, -4.65), 0.18, false],
		[Vector3(-2.72, WATER_Y + 0.008, -4.78), 0.16, false],
		[Vector3(2.85, WATER_Y + 0.008, -4.85), 0.23, true],
		[Vector3(3.22, WATER_Y + 0.008, -5.15), 0.17, false],
		[Vector3(2.55, WATER_Y + 0.008, -5.28), 0.19, false],
		[Vector3(-0.95, WATER_Y + 0.008, -6.55), 0.21, false],
		[Vector3(-0.55, WATER_Y + 0.008, -6.78), 0.18, true],
		[Vector3(1.65, WATER_Y + 0.008, -6.85), 0.20, false],
		[Vector3(4.35, WATER_Y + 0.008, -2.45), 0.22, false],
		[Vector3(4.05, WATER_Y + 0.008, -2.10), 0.17, true],
		[Vector3(6.85, WATER_Y + 0.008, -3.15), 0.21, false],
		[Vector3(6.65, WATER_Y + 0.008, 0.35), 0.20, false],
		[Vector3(4.85, WATER_Y + 0.008, 2.25), 0.22, true],
	]
	c.u.surface(leaf_u)
	for lc: Array in lily_clusters:
		var lp: Vector3 = lc[0]
		var r: float = lc[1]
		var has_lotus: bool = lc[2]
		c.u.colour = _lin(LILY_PAD.lerp(MOSS_BRIGHT, rng.randf_range(0.0, 0.35)))
		# Notched 10-point lily pad polygon.
		var notch := rng.randf_range(0.0, TAU)
		var pts: Array = [lp]
		for k in 9:
			var a := notch + 0.22 + (TAU - 0.44) * float(k) / 8.0
			pts.append(lp + Vector3(cos(a) * r, 0.0, sin(a) * r))
		c.u.face(pts, Vector3.UP)
		if has_lotus:
			c.u.colour = _lin(LOTUS_PINK)
			var bp := lp + Vector3(0.0, 0.025, 0.0)
			for p_i in 6:
				var pa := TAU * float(p_i) / 6.0
				var dir := Vector3(cos(pa), 0.48, sin(pa)).normalized()
				var side := Vector3(-sin(pa), 0.0, cos(pa)) * 0.032
				Shapes.leaf(c.u, bp, dir * 0.09, side, Vector3(cos(pa), 0.85, sin(pa)).normalized())


## Iconic sculpted curved vermilion-lacquered wooden garden footbridge (taiko-bashi) arching over the starboard pond
## inlet with dark-cypress plank deck, twin arched stringers, sweeping vermilion handrails, balusters & brass giboshi!
static func _build_vermilion_footbridge(c: Object) -> void:
	var wood_s: Material = c.tinted("wood")
	var wood_u: Material = c.soft("wood")
	var lacquer: Material = _lacquer(c)
	var stone_s: Material = c.tinted("stone")
	var gilt: Material = _gilt(c)

	var z0 := BRIDGE_Z0
	var z1 := BRIDGE_Z1
	var zm := (z0 + z1) * 0.5
	var half_l := (z1 - z0) * 0.5 # 2.20 m
	var hw := BRIDGE_W * 0.5 # 0.66 m
	var y_end := -0.30
	var y_top := BRIDGE_CROWN_Y # +0.50 m -> graceful 0.80 m arch rise over the mirror water!

	var arch_y := func(z: float) -> float:
		var u := clampf((z - zm) / half_l, -1.0, 1.0)
		return lerpf(y_top, y_end, u * u)

	# 1. Granite bridge abutment foundation piers at both ends.
	c.s.surface(stone_s)
	c.s.colour = _lin(GRANITE_MID)
	for ez: float in [z0 - 0.24, z1 + 0.24]:
		c.s.box(Vector3(BRIDGE_X, -0.40, ez), Vector3(BRIDGE_W + 0.44, 0.30, 0.62), Basis(), [RoomMesh.DOWN])

	# 2. Submerged dark-cypress support pilings under the bridge arch quarters.
	c.u.surface(wood_u)
	c.u.colour = _lin(CEDAR_DEEP)
	for qz: float in [lerpf(z0, z1, 0.24), lerpf(z0, z1, 0.76)]:
		var py := float(arch_y.call(qz))
		for sx: float in [-1.0, 1.0]:
			Shapes.cylinder(c.u, Vector3(BRIDGE_X + sx * (hw - 0.10), WATER_Y - 0.22, qz), 0.068,
					py - (WATER_Y - 0.22), 8)
		Shapes.beam(c.u, Vector3(BRIDGE_X - hw + 0.04, py - 0.12, qz),
				Vector3(BRIDGE_X + hw - 0.04, py - 0.12, qz), Vector2(0.10, 0.12))

	# 3. Slatted curved dark-hinoki deck planks & twin arched vermilion-trimmed stringer beams (18 crisp segments!).
	var segs := 18
	for i in segs:
		var za := lerpf(z0, z1, float(i) / float(segs))
		var zb := lerpf(z0, z1, float(i + 1) / float(segs))
		var zc := (za + zb) * 0.5
		var ya := float(arch_y.call(za))
		var yb := float(arch_y.call(zb))
		var yc := (ya + yb) * 0.5
		var pitch := atan2(yb - ya, zb - za)
		var bs := Basis(Vector3.RIGHT, -pitch)
		var seg_len := Vector2(zb - za, yb - ya).length()

		# Deck tread plank.
		c.s.surface(wood_s)
		c.s.colour = _lin(HINOKI_DECK * (0.94 if i % 2 == 0 else 1.04))
		c.s.box(Vector3(BRIDGE_X, yc, zc), Vector3(BRIDGE_W - 0.04, 0.055, seg_len - 0.025), bs)

		# Twin arched vermilion-lacquered fascia stringers along both deck edges.
		c.u.surface(lacquer)
		c.u.colour = _lin(VERMILION)
		for sx: float in [-1.0, 1.0]:
			c.u.box(Vector3(BRIDGE_X + sx * hw, yc - 0.03, zc), Vector3(0.08, 0.16, seg_len + 0.02), bs)
			# Sweeping arched upper vermilion handrail (y + 0.78) & middle rail (y + 0.40)!
			c.u.box(Vector3(BRIDGE_X + sx * hw, yc + 0.78, zc), Vector3(0.075, 0.068, seg_len + 0.03), bs)
			c.u.box(Vector3(BRIDGE_X + sx * hw, yc + 0.42, zc), Vector3(0.052, 0.044, seg_len + 0.02), bs)

	# 4. Five pairs of vermilion newel posts crowned with gleaming brass giboshi onion finials + intermediate balusters!
	var post_ts: Array[float] = [0.0, 0.25, 0.50, 0.75, 1.0]
	for pt: float in post_ts:
		var pz := lerpf(z0, z1, pt)
		var py := float(arch_y.call(pz))
		for sx: float in [-1.0, 1.0]:
			var px := BRIDGE_X + sx * hw
			c.u.surface(lacquer)
			c.u.colour = _lin(VERMILION)
			c.u.box(Vector3(px, py + 0.42, pz), Vector3(0.095, 0.90, 0.095))
			# Gleaming lathed brass giboshi jewel-onion finial atop each newel post!
			c.u.surface(gilt)
			c.u.colour = _lin(BRASS_GOLD)
			Shapes.lathe(c.u, [
				Vector2(0.054, 0.0), Vector2(0.058, 0.055), Vector2(0.042, 0.085),
				Vector2(0.064, 0.125), Vector2(0.048, 0.175), Vector2(0.018, 0.215), Vector2(0.0, 0.235),
			], Vector3(px, py + 0.86, pz), 10)
	# Intermediate slender vermilion balusters between newel posts.
	c.u.surface(wood_u)
	c.u.colour = _lin(VERMILION_DARK)
	for i in 12:
		var bt := (float(i) + 0.5) / 12.0
		var bz := lerpf(z0, z1, bt)
		var by := float(arch_y.call(bz))
		for sx: float in [-1.0, 1.0]:
			c.u.box(Vector3(BRIDGE_X + sx * hw, by + 0.40, bz), Vector3(0.04, 0.76, 0.04))

	_solid(c, Vector3(BRIDGE_X, 0.15, zm), Vector3(BRIDGE_W + 0.2, 1.2, z1 - z0))


## Three iconic carved granite yukimi-doro (snow-viewing) stone lanterns along the koi pond edge, each with three
## arched stone legs, hexagonal carved firebox glowing warmly inside (PieceLamps + bake lamp), wide hexagonal umbrella
## snow-cap roof (kasa), and lotus-bud finial (hoju).
static func _build_yukimi_lanterns(c: Object) -> void:
	var stone_u: Material = c.soft("stone")
	var leaf_u: Material = c.soft("leaves")
	var shade_m: Material = c.shade(WASHI_LAMP)

	for pos: Vector3 in YUKIMI_POS:
		# Broad wet mossy granite base boulder rising gently out of the pond water.
		c.u.surface(stone_u)
		c.u.colour = _lin(GRANITE_WET)
		c.u.rounded_box(Vector3.ZERO, Vector3(1.10, 0.34, 1.04), 0.14,
				Transform3D(Basis(Vector3.UP, pos.x * 0.4), pos + Vector3(0.0, 0.04, 0.0)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])
		var base_y := pos.y + 0.20

		# Three gracefully arched granite tripod legs straddling the pond stone (y = base_y .. base_y + 0.46).
		c.u.colour = _lin(GRANITE_MID)
		for k in 3:
			var a := TAU * float(k) / 3.0 + 0.35
			var foot := Vector3(pos.x + cos(a) * 0.34, base_y - 0.02, pos.z + sin(a) * 0.34)
			var knee := Vector3(pos.x + cos(a) * 0.26, base_y + 0.24, pos.z + sin(a) * 0.26)
			var hip := Vector3(pos.x + cos(a) * 0.14, base_y + 0.44, pos.z + sin(a) * 0.14)
			Shapes.beam(c.u, foot, knee, Vector2(0.095, 0.095))
			Shapes.beam(c.u, knee, hip, Vector2(0.090, 0.090))

		# Carved hexagonal middle platform (chudai) supporting the firebox.
		c.u.colour = _lin(GRANITE_LIGHT * 0.86)
		Shapes.lathe(c.u, [
			Vector2(0.18, 0.40), Vector2(0.32, 0.48), Vector2(0.34, 0.54), Vector2(0.24, 0.56),
		], Vector3(pos.x, base_y, pos.z), 6)

		# Hexagonal carved stone firebox frame (6 slender stone corner mullions around the glowing candle core).
		var fb_y0 := base_y + 0.55
		var fb_y1 := base_y + 0.88
		c.u.colour = _lin(GRANITE_MID)
		for k in 6:
			var a := TAU * float(k) / 6.0
			var mp := Vector3(pos.x + cos(a) * 0.20, (fb_y0 + fb_y1) * 0.5, pos.z + sin(a) * 0.20)
			c.u.box(mp, Vector3(0.042, fb_y1 - fb_y0, 0.042), Basis(Vector3.UP, -a))

		# Warm glowing inner candle/washi firebox core (PieceLamps, house group!).
		c.lit.surface(shade_m)
		Shapes.cylinder(c.lit, Vector3(pos.x, fb_y0 + 0.02, pos.z), 0.145, fb_y1 - fb_y0 - 0.04, 6, Basis(), false)

		# Wide sweeping hexagonal yukimi-doro snow-viewing umbrella roof (kasa) + lotus-bud finial (hoju)!
		c.u.surface(stone_u)
		c.u.colour = _lin(GRANITE_LIGHT * 0.90)
		Shapes.lathe(c.u, [
			Vector2(0.22, 0.87), Vector2(0.58, 0.89), Vector2(0.60, 0.94),
			Vector2(0.42, 1.05), Vector2(0.18, 1.15), Vector2(0.09, 1.18),
			Vector2(0.11, 1.24), Vector2(0.06, 1.32), Vector2(0.0, 1.37),
		], Vector3(pos.x, base_y, pos.z), 6)
		# Delicate patch of velvet garden moss on the weathered granite snow-roof!
		c.u.surface(leaf_u)
		c.u.colour = _lin(MOSS_GREEN)
		c.u.rounded_box(Vector3.ZERO, Vector3(0.26, 0.05, 0.22), 0.022,
				Transform3D(Basis(Vector3.UP, 0.5), Vector3(pos.x - 0.14, base_y + 1.06, pos.z + 0.10)), 1)

		# Stand-in & hidden bake lamp inside each yukimi-doro stone lantern (lamps #5, #6, #7 of 8!).
		c.lamps.append([Vector3(pos.x, (fb_y0 + fb_y1) * 0.5, pos.z), WASHI_LAMP, 0.90])
		_solid(c, Vector3(pos.x, base_y + 0.65, pos.z), Vector3(0.80, 1.35, 0.80))


## Port bamboo shishi-odoshi (deer-scarer) water-clack basin tucked beside mossy stones right off the port verandah!
## The pivoting green bamboo rocker tube itself is animated live in KyotoGardenHall.BambooRocker.
static func _build_shishi_odoshi_basin(c: Object) -> void:
	var stone_u: Material = c.soft("stone")
	var wood_u: Material = c.soft("wood")
	var leaf_u: Material = c.soft("leaves")

	var at := SPOUT_AT
	# Pebble drainage bed (umi) & flanking mossy garden stones.
	c.u.surface(stone_u)
	c.u.colour = _lin(GRANITE_WET)
	Shapes.cylinder(c.u, at + Vector3(0.0, -0.02, 0.0), 0.78, 0.05, 12)
	for b_off: Array in [
		[Vector3(-0.68, 0.24, -0.45), Vector3(0.76, 0.58, 0.64), 0.3],
		[Vector3(-0.62, 0.18, 0.52), Vector3(0.68, 0.44, 0.58), -0.4],
		[Vector3(-0.60, 0.08, 0.0), Vector3(0.24, 0.18, 0.24), 0.2], # wet striker stone under bamboo rocker tail!
	]:
		c.u.colour = _lin(GRANITE_MID * 0.82)
		c.u.rounded_box(Vector3.ZERO, b_off[1], 0.09,
				Transform3D(Basis(Vector3.UP, float(b_off[2])), at + (b_off[0] as Vector3)), 1,
				Vector3i.ZERO, 0.0, [RoomMesh.DOWN])

	# Lathed mossy granite tsukubai water basin (chozubachi) with dark reflecting water surface inside.
	c.u.colour = _lin(GRANITE_MID)
	Shapes.lathe(c.u, [
		Vector2(0.26, 0.0), Vector2(0.35, 0.12), Vector2(0.36, 0.34),
		Vector2(0.32, 0.42), Vector2(0.22, 0.42), Vector2(0.20, 0.34),
	], at + Vector3(0.14, 0.0, 0.0), 12)
	c.u.surface(leaf_u)
	c.u.colour = _lin(Color(0.05, 0.16, 0.14))
	var w_pts: Array = []
	for k in 10:
		var a := TAU * float(k) / 10.0
		w_pts.append(at + Vector3(0.14 + cos(a) * 0.21, 0.38, sin(a) * 0.21))
	c.u.face(w_pts, Vector3.UP)

	# Green bamboo supply post (kakehi), horizontal pouring spout, and twin bamboo pivot fork uprights.
	c.u.surface(wood_u)
	c.u.colour = _lin(BAMBOO_GREEN)
	Shapes.cylinder(c.u, at + Vector3(-0.56, 0.0, 0.0), 0.044, 0.92, 8)
	Shapes.beam(c.u, at + Vector3(-0.56, 0.78, 0.0), at + Vector3(0.02, 0.64, 0.0), Vector2(0.048, 0.048))
	for sz: float in [-0.085, 0.085]:
		Shapes.cylinder(c.u, at + Vector3(-0.34, 0.0, sz), 0.028, 0.42, 8)
	# Cross-axle pin supporting the live BambooRocker.
	c.u.colour = _lin(BAMBOO_NODE)
	Shapes.beam(c.u, at + Vector3(-0.34, 0.36, -0.10), at + Vector3(-0.34, 0.36, 0.10), Vector2(0.018, 0.018))
	# Delicate glistening water trickle pouring from the kakehi spout tip into the bamboo rocker & granite basin!
	c.u.surface(leaf_u)
	c.u.colour = _lin(Color(0.68, 0.88, 0.88))
	Shapes.beam(c.u, at + Vector3(0.02, 0.63, 0.0), at + Vector3(0.05, 0.38, 0.0), Vector2(0.014, 0.014))
	# Subtle pale water splash ring on the basin mirror surface.
	Shapes.arch(c.u, at + Vector3(0.08, 0.386, 0.0), 0.055, 0.072, 0.004, 12, Basis(Vector3.RIGHT, PI * 0.5), 0.0, TAU,
			["front"])

	# Low woven bamboo privacy screen (takegaki) tucked gracefully behind the shishi-odoshi basin!
	c.u.surface(wood_u)
	c.u.colour = _lin(BAMBOO_NODE * 0.85)
	for i in 12:
		var fz := at.z - 0.82 + float(i) * 0.15
		Shapes.cylinder(c.u, Vector3(at.x - 0.92, GRAVEL_Y, fz), 0.032, 1.38, 6)
	c.u.colour = _lin(CEDAR_DARK)
	for ry: float in [0.32, 0.96, 1.36]:
		c.u.box(Vector3(at.x - 0.92, GRAVEL_Y + ry, at.z), Vector3(0.085, 0.05, 1.85))


## Traditional Kyoto tsukiji-bei plaster-and-kawara-tile garden enclosure wall circling the sanctuary, backed by
## slender segmented Kyoto bamboo groves with feathery leaf crowns.
static func _build_enclosure_wall_and_bamboo(c: Object) -> void:
	var plaster_s: Material = c.tinted("plaster")
	var stone_s: Material = c.tinted("stone")
	var roof_s: Material = c.tinted("roof", "roof_tiles")
	var wood_u: Material = c.soft("wood")
	var leaf_u: Material = c.soft("leaves")

	var wx := 12.0
	var wz0 := -12.0
	var wz1 := 7.6
	var wy0 := GROUND_Y
	var wall_h := 2.18

	# Four sides of the warm weathered earthen-plaster garden wall on dark stone footings with dark kawara tile coping!
	var wall_segs: Array = [
		# [centre_xz, length, yaw_deg]
		[Vector2(0.0, wz0), wx * 2.0 + 0.4, 0.0],
		[Vector2(0.0, wz1), wx * 2.0 + 0.4, 180.0],
		[Vector2(-wx, (wz0 + wz1) * 0.5), wz1 - wz0 + 0.4, 90.0],
		[Vector2(wx, (wz0 + wz1) * 0.5), wz1 - wz0 + 0.4, -90.0],
	]
	for ws: Array in wall_segs:
		var xz: Vector2 = ws[0]
		var wlen: float = ws[1]
		var bs := Basis(Vector3.UP, deg_to_rad(float(ws[2])))
		# Stone base plinth.
		c.s.surface(stone_s)
		c.s.colour = _lin(GRANITE_WET)
		c.s.box(Vector3(xz.x, wy0 + 0.24, xz.y), Vector3(wlen, 0.48, 0.46), bs, [RoomMesh.DOWN])
		# Weathered earthen-cream Kyoto plaster wall body.
		c.s.surface(plaster_s)
		c.s.colour = _lin(PLASTER_EARTHEN)
		c.s.box(Vector3(xz.x, wy0 + 0.48 + (wall_h - 0.48) * 0.5, xz.y), Vector3(wlen, wall_h - 0.48, 0.34), bs)
		# Overhanging pitched smoked-clay kawara coping roof crowning the garden wall!
		c.s.surface(roof_s)
		c.s.colour = _lin(KAWARA_TILE)
		var ry := wy0 + wall_h + 0.12
		c.s.box(Vector3(xz.x, ry, xz.y) + bs * Vector3(0.0, 0.0, 0.18), Vector3(wlen + 0.2, 0.09, 0.52),
				bs * Basis(Vector3.RIGHT, deg_to_rad(22.0)))
		c.s.box(Vector3(xz.x, ry, xz.y) + bs * Vector3(0.0, 0.0, -0.18), Vector3(wlen + 0.2, 0.09, 0.52),
				bs * Basis(Vector3.RIGHT, deg_to_rad(-22.0)))
		c.s.colour = _lin(KAWARA_RIDGE)
		c.s.box(Vector3(xz.x, ry + 0.14, xz.y), Vector3(wlen + 0.2, 0.12, 0.14), bs)
		# Rhythmic vertical timber wall buttress posts along the inner plaster face.
		c.u.surface(wood_u)
		c.u.colour = _lin(CEDAR_DEEP)
		var n_posts := int(wlen / 3.2)
		for k in n_posts:
			var lx := -wlen * 0.5 + (float(k) + 0.5) * wlen / float(n_posts)
			c.u.box(Vector3(xz.x, wy0 + wall_h * 0.5, xz.y) + bs * Vector3(lx, 0.0, 0.19),
					Vector3(0.12, wall_h, 0.08), bs)

	# 2. Clusters of tall slender segmented Kyoto bamboo stalks rising gracefully around the garden perimeter!
	var rng := RandomNumberGenerator.new()
	rng.seed = 2407
	var grove_centres: Array[Vector3] = [
		Vector3(-10.8, GROUND_Y, -9.8),  # far port-front grove
		Vector3(-11.0, GROUND_Y, -4.4),  # port Zen wall grove
		Vector3(-10.6, GROUND_Y, 4.6),   # port-aft bamboo cluster
		Vector3(-5.8, GROUND_Y, -11.0),  # far left behind pond
		Vector3(5.6, GROUND_Y, -10.9),   # far right behind screen
		Vector3(10.8, GROUND_Y, -9.2),   # far starboard-front grove
		Vector3(10.9, GROUND_Y, -3.2),   # starboard behind bridge
		Vector3(10.7, GROUND_Y, 3.8),    # starboard-aft grove
	]
	for gc: Vector3 in grove_centres:
		for si in 5:
			var bx := gc.x + rng.randf_range(-1.15, 1.15)
			var bz := gc.z + rng.randf_range(-1.05, 1.05)
			var bh := rng.randf_range(4.4, 7.1)
			var tilt := Vector3(rng.randf_range(-0.32, 0.32), 0.0, rng.randf_range(-0.32, 0.32))
			var base := Vector3(bx, GROUND_Y, bz)
			var mid := base + Vector3(tilt.x * 0.45, bh * 0.52, tilt.z * 0.45)
			var tip := base + Vector3(tilt.x, bh, tilt.z)
			c.u.surface(wood_u)
			c.u.colour = _lin(BAMBOO_GREEN * rng.randf_range(0.84, 1.12))
			Shapes.beam(c.u, base, mid, Vector2(0.068, 0.068))
			Shapes.beam(c.u, mid, tip, Vector2(0.046, 0.046))
			# Feathery bamboo leaf sprays clustered gracefully near the upper stalks.
			c.u.surface(leaf_u)
			c.u.colour = _lin(BAMBOO_LEAF * rng.randf_range(0.85, 1.18))
			for lf in 6:
				var f := rng.randf_range(0.48, 0.96)
				var lp := base.lerp(tip, f)
				var ang := rng.randf_range(0.0, TAU)
				var dir := Vector3(cos(ang), rng.randf_range(-0.35, 0.25), sin(ang)).normalized()
				var across := Vector3(-sin(ang), 0.0, cos(ang)) * rng.randf_range(0.09, 0.14)
				Shapes.leaf(c.u, lp, dir * rng.randf_range(0.45, 0.72), across, Vector3.UP)


## Builds the gnarled multi-level dark-bark trunks and arching boughs of the four Kyoto weeping cherry / Japanese maple
## trees (their seasonal foliage canopies live in KyotoGardenHall.KyotoCanopy so setting.season tints them live!).
static func _build_tree_trunks(c: Object) -> void:
	var wood_u: Material = c.soft("wood")
	c.u.surface(wood_u)
	for spec: Array in TREE_SPECS:
		var base: Vector3 = spec[0]
		var lean: Vector3 = spec[1]
		var h: float = spec[2]
		var cr: float = spec[3]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(spec[5])
		c.u.colour = _lin(BARK_DARK)
		# Gnarled 3-segment curving Kyoto trunk rising & leaning gracefully over the pond/bridge/gravel!
		var p1 := base + Vector3(lean.x * h * 0.14, h * 0.34, lean.z * h * 0.14)
		var p2 := base + Vector3(lean.x * h * 0.34, h * 0.62, lean.z * h * 0.34)
		var p3 := base + Vector3(lean.x * h * 0.50, h * 0.84, lean.z * h * 0.50)
		Shapes.beam(c.u, base + Vector3(0.0, -0.10, 0.0), p1, Vector2(0.36, 0.36))
		Shapes.beam(c.u, p1, p2, Vector2(0.26, 0.26))
		Shapes.beam(c.u, p2, p3, Vector2(0.18, 0.18))
		# Exposed surface root buttresses gripping the mossy earth bank.
		for rk in 4:
			var ra := TAU * float(rk) / 4.0 + rng.randf_range(-0.25, 0.25)
			Shapes.beam(c.u, base + Vector3(0.0, 0.34, 0.0),
					base + Vector3(cos(ra) * 0.62, -0.06, sin(ra) * 0.62), Vector2(0.14, 0.12))
		# Six sweeping primary & secondary limbs spreading into the seasonal canopy crown.
		for bi in 6:
			var a := TAU * float(bi) / 6.0 + rng.randf_range(-0.25, 0.25)
			var fork := p2.lerp(p3, float(bi % 3) / 2.0)
			var reach := cr * rng.randf_range(0.68, 0.96)
			var b_mid := fork + Vector3(cos(a) * reach * 0.55 + lean.x * 0.3, rng.randf_range(0.28, 0.58),
					sin(a) * reach * 0.55 + lean.z * 0.3)
			var b_tip := b_mid + Vector3(cos(a) * reach * 0.45, rng.randf_range(-0.18, 0.36),
					sin(a) * reach * 0.45)
			# Keep limbs clear of the cinema screen rectangle.
			if b_tip.z < -6.2 and absf(b_tip.x) < 3.65:
				b_tip.x = signf(base.x) * 3.85
			Shapes.beam(c.u, fork, b_mid, Vector2(0.12, 0.12))
			Shapes.beam(c.u, b_mid, b_tip, Vector2(0.068, 0.068))
		_solid(c, base + Vector3(lean.x * 0.4, h * 0.4, lean.z * 0.4), Vector3(0.55, h * 0.8, 0.55))
