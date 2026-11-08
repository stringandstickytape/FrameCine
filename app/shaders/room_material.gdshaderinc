// A library material on a room surface (scripts/env/material_library.gd, docs/materials.md): base colour, normal and
// packed (ambient occlusion, roughness, metallic) maps, lit the way env_unlit.gdshader lights a room: the room's
// ambient level plus the screen's fall-off spill (env_spill.gdshaderinc), darker towards the floor. No lights, no
// shadows, no light pass: everything is computed here, so the maps add detail without changing the room's levels.
//   - The normal map tilts the light: a bump facing the screen catches more of its spill, one facing up more of the
//     ambient; the flat surface gets exactly env_unlit's light.
//   - Ambient occlusion from the packed map darkens grooves and grout.
//   - A highlight from the screen (a soft lobe around its reflection, sharper for smooth surfaces, in the picture's
//     colour), and a sheen at grazing angles for velvet and other pile fabrics.
//   - Pleats (curtains): folds across the surface, shaded, without geometry.
// Texture coordinates: by default the surface's own axes in metres ("box": each face takes the two axes across it,
// one fetch per map, exact on boxes and planes), or the mesh's UVs; room_material_triplanar.gdshader blends three
// projections for meshes without either (three times the fetches).
// LIT defined (room_material_lit.gdshader, room_material_lit_triplanar.gdshader): the same maps in an assistant's room
// with real lighting, as room_lit.gdshader lights it: the engine's lights and shadows on the maps' colour, roughness,
// metalness and normals, plus the hemisphere fill, the film's light and the contact darkening added as emission.
// HOUSE defined too (room_material_house.gdshader): a built-in room lit that way on the stock rooms' room light,
// ready for a baked lightmap (the cinema; see the HOUSE uniforms).
// Included by room_material.gdshader and room_material_triplanar.gdshader (TRIPLANAR defined) and their lit forms,
// after their shader_type and render_mode.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// X in RGB, Y in alpha (the packer's normal mode); Z is rebuilt.
uniform sampler2D normal_map : filter_linear_mipmap_anisotropic, repeat_enable;
// R ambient occlusion, G roughness, B metallic.
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Multiplies the base colour (the room's own colour as a tint).
uniform vec3 tint : source_color = vec3(1.0);
// Metres per repeat of the maps (box and triplanar), and a shift in metres.
uniform float tiling = 1.0;
uniform vec2 uv_offset = vec2(0.0);
// The pattern turned on the surface (radians; the Objects tab's apply mode turns it with the stick).
uniform float uv_turn = 0.0;
// The mesh's UVs instead of its axes, repeated this often across the UV square.
uniform bool use_mesh_uv = false;
uniform vec2 uv_repeat = vec2(1.0);
uniform float roughness_scale = 1.0;
uniform float normal_strength = 1.0;
uniform float ao_strength = 1.0;
// How strongly the normal map's tilt shows in the light.
uniform float relief = 0.8;
// The screen's highlight and the grazing sheen (0 = none).
uniform float specular = 0.5;
uniform float sheen = 0.0;
// Folds per metre across the surface (0 = flat), and how deep they look.
uniform float pleats = 0.0;
uniform float pleat_depth = 0.5;
// As env_unlit: how much this surface catches the screen's light, and the darkening towards the floor.
uniform float spill = 1.0;
uniform float floor_darkening = 0.2;
// Added on top (the room document's emission x emission_strength): a library surface can glow too.
uniform vec3 emission : source_color = vec3(0.0);
#ifdef LIT
// As room_lit.gdshader: the hemisphere fill (colours as picked, times light.sky.energy), the film's light, and the
// contact darkening near the floor.
uniform vec3 sky_top = vec3(0.0);
uniform vec3 sky_bottom = vec3(0.0);
uniform float screen_light = 0.0;
uniform float contact_height = 0.5;
uniform float contact_strength = 0.35;
uniform float floor_y = 0.0;
#endif
#ifdef HOUSE
// HOUSE (with LIT, room_material_house.gdshader): a built-in room lit for real and ready for a baked lightmap (the
// cinema, environments/cinema.gd), on the stock rooms' room light. The house lights' level is env_light over
// house_reference (the room's own ambient level), squared: 1 as designed, 12 % while the film plays (room light
// 0.35), up to 4 with the user's room light. It scales the engine's light on the surface (a baked lightmap's, a
// light's) and the fill (sky_top, sky_bottom). The screen's light is the stock rooms' spill (screen_glow, the bias light's tint, `spill`), not
// screen_light. Until a lightmap is baked, lamps stand in for the room's lights: up to HOUSE_LAMPS soft point lights
// without shadows, added as emission (lamp_position: xyz in the world, w the range; lamp_colour: rgb times energy, w
// > 0 makes it shine only up and down, w the cosine of the cones' half angle: a wall sconce's scallops).
// instance_tint: the MultiMesh instance's colour multiplies the base colour (seats). bake_pass: what the lightmapper
// renders of the surface (the colour at level 1; no fill, film or lamps, which would bake in as light).
#define HOUSE_LAMPS 8
uniform float house_reference = 0.05;
// The least the house lights give (a share of the designed level): a cinema with the film on still shows its steps,
// aisles and walls, however far the room light is turned down (the user's "dimmed to" can be 0).
uniform float house_floor = 0.04;
uniform int lamp_count = 0;
uniform vec4 lamp_position[HOUSE_LAMPS];
uniform vec4 lamp_colour[HOUSE_LAMPS];
// Caustics (the light system's `caustics`, docs/environments.md "The systems"): the light of a water's surface above,
// focused into a slowly drifting web on whatever faces up (a glass dome under the sea). Light from outside: the house
// lights' level does not scale it, and a bake does not take it. caustic_map: a cellular map, near 0 on the walls
// between cells (procedural.gd caustic_map()); two copies drift apart, brightest where their walls meet. Every point
// changes at well under 1 Hz (caustic_speed, which the Motion setting scales).
uniform float caustics = 0.0;
uniform vec3 caustic_colour : source_color = vec3(0.55, 0.85, 1.0);
uniform float caustic_scale = 1.6;
uniform float caustic_speed = 1.0;
uniform sampler2D caustic_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool bake_pass = false;
uniform bool instance_tint = false;
// Light worked out in code and carried in the vertex colours' alpha (since 2026-11-08, Reclaimed's Moon: its shadows
// traced against the ruin's open roof, walls and trusses as the room is built, kit/reclaimed.gd). The surface's colour
// times this times the alpha, as bright as the house level; in the bake too, as an emitter, so its light bounces on.
// 0 (every other room): nothing.
uniform vec3 vertex_light = vec3(0.0);
#endif
#ifdef REFLECT
// REFLECT (with LIT and HOUSE, room_material_house_reflect.gdshader; since 2026-11-08, for the drive-in's car: "chrome
// needs believable reflections done cheaply"): a lacquered or chromed surface shows what is round it without a probe:
// the sky's gradient and the sunset's glow (the sky system's colours, set every frame by the builder), a dark skyline
// of low hills, the ground, the screen with the picture's colours where the reflected ray meets it (the bias light's
// copy), and one glint (a neon sign). A few dot products and one texture read. reflect_metal 0: a clear coat
// (Fresnel, 4 % head on, a mirror at grazing angles: the long bonnet); 1: chrome (the base colour times the
// reflection everywhere). Rough surfaces see a blurred, averaged world.
uniform float reflect_amount = 0.0;
uniform float reflect_metal = 0.0;
uniform vec3 refl_zenith : source_color = vec3(0.02, 0.03, 0.06);
uniform vec3 refl_horizon : source_color = vec3(0.06, 0.07, 0.1);
uniform vec3 refl_ground : source_color = vec3(0.01);
uniform vec3 refl_glow : source_color = vec3(0.0);
uniform vec3 refl_glow_dir = vec3(0.0, 0.0, -1.0);
// The screen in the world: its centre, its right and up half extents.
uniform vec3 refl_screen_centre = vec3(0.0, 8.0, -50.0);
uniform vec3 refl_screen_x = vec3(12.0, 0.0, 0.0);
uniform vec3 refl_screen_y = vec3(0.0, 5.0, 0.0);
// The picture's brightness in the reflection (0 with the screen dark).
uniform float refl_screen_level = 1.0;
// A glint: its place in the world, its colour times energy, its half size (metres across, up).
uniform vec3 refl_glint_pos = vec3(0.0, 3.0, 16.0);
uniform vec3 refl_glint_colour = vec3(0.0);
uniform vec2 refl_glint_size = vec2(2.5, 0.4);
#endif

#ifdef ICE
// ICE (with LIT and HOUSE, room_material_house_ice.gdshader; since 2026-11-08, for the Ice cinema: "translucent so
// light sits *inside* it rather than on it ... a good ice shader with fake depth on opaque geometry, not stacked
// transparency", the brief): a block of ice. Its face is the library's maps, glassy; under it two layers of what is
// frozen inside (ice_map: R bubbles, G cracks and veils, B milky cloud, A the saw's marks on the face) drawn at two
// depths along the view, so they shift against the face as the head moves (and each eye sees them at their depth).
// What lights the inside: the fill, the candles near it (scattered: a soft glow round each, whichever way the face
// looks, ice_glow_*), and round the screen the film's own colours seeping through the front wall (ice_film). Points
// are in the room's frame: the ice's meshes sit at the room's origin, so their VERTEX is the room's frame.
// COLOR.a: the block's own seed (its inside differs from the next block's), and how clear it is (0.5 up: clearer).
#define ICE_GLOWS 12
uniform sampler2D ice_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 ice_deep : source_color = vec3(0.03, 0.1, 0.14);
uniform float ice_scale = 0.45;
uniform float ice_depth = 0.12;
uniform float ice_inner = 1.0;
uniform float ice_marks = 0.5;
uniform int ice_glow_count = 0;
uniform vec4 ice_glow_pos[ICE_GLOWS];
uniform vec4 ice_glow_col[ICE_GLOWS];
uniform float ice_glow_level = 1.0;
uniform vec3 ice_screen_c = vec3(0.0, 1.7, -6.0);
uniform vec2 ice_screen_half = vec2(1.6, 0.9);
uniform float ice_film = 0.0;
uniform float ice_film_reach = 0.7;
// The face's gloss: the candles' glints and the picture's soft reflection, strongest at grazing angles.
uniform float ice_gloss = 1.0;
// The picture's share of that gloss (its colours mirrored in the walls at a glancing look).
uniform float ice_shine = 1.0;
// How much of the hemisphere fill the ice takes (its depth and what is inside it).
uniform float ice_fill = 1.0;
// The night outside seen through the walls: the deep's colour lit this much by the snow and the Moon (not the house
// lights'; it stays while the film plays).
uniform float ice_night = 0.0;
// The candles' light on the face itself (frosted faces take more): a niche lit warm from inside.
uniform float ice_glow_face = 0.0;
// A vault laid in courses of blocks (the coordinator, 2026-11-08: "the vault ... should be ice/snow-ice with the same
// life as the walls: block courses curving over, frost"): x the vault's half width, y its springing's height, z its
// rise, w a course's height along the arch (metres; 0: off). The blocks' joints, their frosted edges, each block's
// own seed and tilt come from the point's place on the arch, so the vault's mesh stays a few smooth strips.
uniform vec4 ice_vault = vec4(0.0);
uniform float ice_vault_block = 0.9;
// Packed snow instead of ice (the floor): no inside, footprints pressed into it and a sparkle where a crystal catches
// the eye; no candle loop (the bake lights it).
uniform float ice_snow = 0.0;
#endif

// env_light, screen_center, screen_glow and the bias light's tint (ideas #29).
#include "res://shaders/env_spill.gdshaderinc"

#ifdef REFLECT
// What a mirror at p sees along r (world, unit): sky, skyline, ground, the screen, the glint; rough: 0..1.
vec3 reflect_world(vec3 p, vec3 r, float rough) {
	float up = r.y;
	vec3 level = normalize(vec3(r.x, 0.0, r.z) + vec3(1e-5));
	vec3 sky = mix(refl_horizon, refl_zenith, pow(clamp(up, 0.0, 1.0), 0.5));
	sky += refl_glow * pow(max(dot(level, refl_glow_dir), 0.0), 4.0) * exp(-max(up, 0.0) * 7.0);
	// Low hills all round, a few degrees high, dark against the sky.
	float az = atan(level.z, level.x);
	float hills = 0.03 + 0.018 * sin(az * 5.0 + 1.3) * sin(az * 3.0 + 0.4) + 0.008 * sin(az * 17.0);
	float blur = 0.004 + rough * 0.25;
	vec3 c = mix(sky, refl_ground, smoothstep(hills + blur, hills - blur, up));
	// The screen where the ray meets its plane, in front of the mirror.
	vec3 sn = normalize(cross(refl_screen_x, refl_screen_y));
	float den = dot(r, sn);
	if (abs(den) > 1e-4 && refl_screen_level > 0.0) {
		float t = dot(refl_screen_centre - p, sn) / den;
		if (t > 0.0) {
			vec3 h = p + r * t - refl_screen_centre;
			vec2 q = vec2(dot(h, refl_screen_x) / dot(refl_screen_x, refl_screen_x),
					dot(h, refl_screen_y) / dot(refl_screen_y, refl_screen_y));
			float soft = 0.03 + rough * 0.8;
			float inside = (1.0 - smoothstep(1.0 - soft, 1.0 + soft, abs(q.x)))
					* (1.0 - smoothstep(1.0 - soft, 1.0 + soft, abs(q.y)));
			if (inside > 0.0) {
				vec3 film = vec3(0.35);
				if (screen_tint > 0.0) {
					film = spill_srgb_to_linear(textureLod(screen_thumb,
							vec2(clamp(0.5 + 0.5 * q.x, 0.125, 0.875), clamp(0.5 - 0.5 * q.y, 0.25, 0.75)), 0.0).rgb);
				}
				c = mix(c, film * screen_glow * refl_screen_level, inside);
			}
		}
	}
	// The glint: an ellipse round its place, as seen from p.
	if (dot(refl_glint_colour, vec3(1.0)) > 0.0) {
		vec3 to = refl_glint_pos - p;
		float d = length(to);
		vec3 g = to / d;
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), g) + vec3(1e-5));
		vec3 off = r - g * dot(r, g);
		vec2 e = vec2(dot(off, side) * d / refl_glint_size.x, off.y * d / refl_glint_size.y);
		float k = (1.0 - smoothstep(0.6 - rough * 0.5, 1.0 + rough * 3.0, length(e))) * step(0.0, dot(r, g));
		c += refl_glint_colour * k / (1.0 + rough * 6.0);
	}
	// A rough surface: the world averaged.
	vec3 mean = mix(refl_horizon, refl_zenith, 0.5) * 0.7 + refl_ground * 0.3;
	return mix(c, mean, clamp(rough * 1.4 - 0.1, 0.0, 1.0));
}
#endif

varying vec3 world_pos;
// Object space in metres (the instance's scale applied), and the object's axes in world space for the normal map.
varying vec3 obj_pos;
varying vec3 obj_normal;
varying vec3 world_normal;
varying vec3 world_tangent;
varying vec3 world_binormal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	obj_pos = VERTEX * scale;
	obj_normal = NORMAL;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_tangent = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
	world_binormal = normalize((MODEL_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

// One projection's samples: base colour, the tangent-space normal, the packed map.
struct Texel {
	vec3 albedo;
	vec3 normal;
	vec3 orm;
};

Texel sample_maps(vec2 uv) {
	Texel t;
	t.albedo = texture(albedo_map, uv).rgb;
	vec2 xy = texture(normal_map, uv).ga * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.0));
	t.normal = normalize(vec3(xy * normal_strength, z));
	t.orm = texture(orm_map, uv).rgb;
	return t;
}

// The box projection's frame for a face whose object-space normal is mainly along `axis` (0 x, 1 y, 2 z): across
// (u) and up (v) in object space, so the picture reads upright and unmirrored from the front.
void face_frame(int axis, float side, out vec3 u_axis, out vec3 v_axis) {
	if (axis == 0) {
		u_axis = vec3(0.0, 0.0, -side);
		v_axis = vec3(0.0, 1.0, 0.0);
	} else if (axis == 1) {
		u_axis = vec3(1.0, 0.0, 0.0);
		v_axis = vec3(0.0, 0.0, -side);
	} else {
		u_axis = vec3(side, 0.0, 0.0);
		v_axis = vec3(0.0, 1.0, 0.0);
	}
}

vec3 to_world(mat3 model, vec3 v) {
	return normalize(model * v);
}

// The pattern's coordinates turned by uv_turn, and the frame its normals are read in turned with them (u: where uv.x
// grows, v: where uv.y falls).
vec2 turn_uv(vec2 uv) {
	float c = cos(uv_turn);
	float s = sin(uv_turn);
	return vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
}

void turn_frame(inout vec3 u, inout vec3 v) {
	float c = cos(uv_turn);
	float s = sin(uv_turn);
	vec3 a = c * u + s * v;
	vec3 b = c * v - s * u;
	u = a;
	v = b;
}

void fragment() {
	mat3 model = mat3(MODEL_MATRIX);
	vec3 geo_n = normalize(world_normal);
	Texel t;
	vec3 n;
	// Metres across the surface, for the pleats.
	float across = 0.0;
	vec3 across_dir = world_tangent;
#ifdef TRIPLANAR
	vec3 on = normalize(obj_normal);
	vec3 w = pow(abs(on), vec3(4.0));
	w /= (w.x + w.y + w.z);
	t.albedo = vec3(0.0);
	t.orm = vec3(0.0);
	n = vec3(0.0);
	for (int axis = 0; axis < 3; axis++) {
		vec3 u_axis;
		vec3 v_axis;
		face_frame(axis, on[axis] < 0.0 ? -1.0 : 1.0, u_axis, v_axis);
		vec2 uv = turn_uv(vec2(dot(obj_pos, u_axis), -dot(obj_pos, v_axis)) / tiling) + uv_offset;
		turn_frame(u_axis, v_axis);
		Texel s = sample_maps(uv);
		t.albedo += s.albedo * w[axis];
		t.orm += s.orm * w[axis];
		n += (to_world(model, u_axis) * s.normal.x + to_world(model, v_axis) * s.normal.y + geo_n * s.normal.z) * w[axis];
	}
	n = normalize(n);
	across = dot(obj_pos, vec3(1.0, 0.0, 1.0));
#else
	vec2 uv;
	vec3 tan_u;
	vec3 tan_v;
	if (use_mesh_uv) {
		uv = turn_uv(UV * uv_repeat) + uv_offset;
		tan_u = normalize(world_tangent);
		tan_v = normalize(world_binormal);
		turn_frame(tan_u, tan_v);
		across = UV.x * uv_repeat.x;
	} else {
		vec3 on = abs(obj_normal);
		int axis = on.x > on.y ? (on.x > on.z ? 0 : 2) : (on.y > on.z ? 1 : 2);
		vec3 u_axis;
		vec3 v_axis;
		face_frame(axis, obj_normal[axis] < 0.0 ? -1.0 : 1.0, u_axis, v_axis);
		across = dot(obj_pos, u_axis);
		uv = turn_uv(vec2(across, -dot(obj_pos, v_axis)) / tiling) + uv_offset;
		tan_u = to_world(model, u_axis);
		tan_v = to_world(model, v_axis);
		turn_frame(tan_u, tan_v);
	}
	t = sample_maps(uv);
	n = normalize(tan_u * t.normal.x + tan_v * t.normal.y + geo_n * t.normal.z);
	across_dir = tan_u;
#endif

#ifdef LIT
	float fold = 1.0;
	if (pleats > 0.0) {
		float phase = across * pleats * TAU;
		n = normalize(n + across_dir * cos(phase) * pleat_depth);
		fold = 1.0 - pleat_depth * 0.35 * (1.0 - sin(phase));
	}
	vec3 base = tint * t.albedo;
	float level = 1.0;
#ifdef HOUSE
	if (instance_tint) {
		base *= COLOR.rgb;
	}
	// The house lights give the square of the room light: dimmed to 0.35 while the film plays, 12 %.
	level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	level = bake_pass ? 1.0 : max(level, house_floor);
#endif
	float metallic = t.orm.b;
	float ao = mix(1.0, t.orm.r, ao_strength) * fold;
	float occlusion = mix(1.0 - contact_strength, 1.0, smoothstep(0.0, contact_height, world_pos.y - floor_y));
	// Metals: no environment to reflect, so a dimmer copy of their colour stands in for it (as unlit).
	vec3 diffuse = base * mix(1.0, 0.45, metallic);
#ifdef REFLECT
	// Chrome shows its reflection, little light of its own.
	diffuse *= mix(1.0, 0.3, reflect_metal * min(reflect_amount, 1.0));
#endif
#ifdef ICE
	vec3 ice_vw = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ice_seed = COLOR.a;
	float ice_edge = 0.0;
	float ice_groove = 0.0;
	float ice_shade = 1.0;
	float ice_frost = 0.0;
	float bubbles = 0.0;
	float cracks = 0.0;
	float cloud = 0.0;
	float snow_sparkle = 0.0;
	if (ice_vault.w > 0.0) {
		// The vault's courses: the point's place along the arch (an ellipse: its angle from the springing, in
		// metres by the mean radius) and down the room; each course's blocks their own length and set off from
		// the last's (sawn by hand, not tiles).
		vec2 e = vec2(obj_pos.x / ice_vault.x, max(obj_pos.y - ice_vault.y, 0.0) / ice_vault.z);
		float c = atan(e.y, e.x) * (ice_vault.x + ice_vault.z) * 0.5 / ice_vault.w;
		float course = floor(c);
		float ch = fract(sin(course * 91.7 + 3.1) * 43758.5453);
		float len = ice_vault_block * (0.75 + 0.5 * ch);
		float z = obj_pos.z / len + ch * 7.3;
		float blk = floor(z);
		vec2 f = vec2(fract(c) * ice_vault.w, fract(z) * len);
		vec2 to_edge = min(f, vec2(ice_vault.w, len) - f);
		float m = min(to_edge.x, to_edge.y);
		vec2 h = fract(sin(vec2(dot(vec2(course, blk), vec2(12.9898, 78.233)),
				dot(vec2(course, blk), vec2(39.346, 11.135)))) * 43758.5453);
		ice_seed = 0.6 + 0.38 * h.x;
		// The joint packed with snow (pale, a hairline shadow at its edge), the sawn edges frosted a little.
		ice_groove = 1.0 - smoothstep(0.002, 0.006, m);
		ice_shade = 0.8 + 0.4 * h.y;
		ice_edge = (1.0 - smoothstep(0.006, 0.022, m)) * 0.45;
		// Each block set by hand: its face turned a little its own way (the candles glint block by block).
		n = normalize(n + (tan_u * (h.x - 0.5) + tan_v * (h.y - 0.5)) * 0.12);
	}
	if (ice_snow > 0.0) {
		// Packed snow: in cells of half a metre, some with a boot's oval pressed in, each turned its own way.
		vec2 q = obj_pos.xz / 0.5;
		vec2 cell = floor(q);
		vec2 h = fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
		float a = h.x * 6.2832;
		vec2 lp = (fract(q) - 0.3 - 0.4 * h.yx) * 0.5;
		vec2 r = vec2(cos(a) * lp.x + sin(a) * lp.y, -sin(a) * lp.x + cos(a) * lp.y);
		float press = step(0.68, h.y) * (1.0 - smoothstep(0.55, 1.0, length(r / vec2(0.05, 0.13)))) * ice_snow;
		// Its slopes tilt the normal (the height's change across the pixel), and the room's light from the screen's
		// side shades them: the far wall of the print lit, the near one in shadow.
		float height = -press * 0.012;
		vec3 dpx = dFdx(world_pos);
		vec3 dpy = dFdy(world_pos);
		vec3 r1 = cross(dpy, n);
		vec3 r2 = cross(n, dpx);
		float det = dot(dpx, r1);
		if (abs(det) > 1e-10) {
			n = normalize(abs(det) * n - sign(det) * (dFdx(height) * r1 + dFdy(height) * r2));
		}
		float print_shade = dot(n - geo_n, normalize(screen_center - world_pos + vec3(0.0, 2.0, 0.0)));
		diffuse *= clamp(1.0 + 1.2 * print_shade - 0.05 * press, 0.75, 1.25);
		// Sparkle: a crystal here and there catches the eye, which ones by where it looks from (still in the world;
		// near only, where a crystal is a few pixels wide).
		vec2 g = obj_pos.xz / 0.012;
		vec2 gc = floor(g);
		float k = fract(sin(dot(gc + floor(ice_vw.xz * 9.0) * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
		float dot_in = 1.0 - smoothstep(0.12, 0.32, length(fract(g) - 0.5));
		float near = 1.0 - smoothstep(2.0, 4.5, length(CAMERA_POSITION_WORLD - world_pos));
		snow_sparkle = step(0.993, k) * dot_in * near * ice_snow;
	} else {
		// The inside, seen through the face: two layers at their depths along the view (metres on the face).
		float ice_vz = max(dot(ice_vw, geo_n), 0.25);
		vec2 ice_par = vec2(-dot(ice_vw, tan_u), dot(ice_vw, tan_v)) / ice_vz;
		vec2 ice_q = uv * tiling / ice_scale + vec2(ice_seed * 13.7, ice_seed * 5.3);
		vec4 near_l = texture(ice_map, ice_q + ice_par * (ice_depth * 0.3 / ice_scale));
		vec4 far_l = texture(ice_map, ice_q * 0.73 + vec2(0.41, 0.17) + ice_par * (ice_depth * 0.73 / ice_scale));
		// COLOR.a: under 0.5 a carved, frosted surface (white where the chisel went); 0.5 to 1 a block, milky to
		// clear. A vault's blocks: frosted at their edges.
		ice_frost = max(clamp(1.0 - ice_seed * 2.0, 0.0, 1.0), max(ice_edge, ice_groove * 0.9));
		float ice_clear = clamp(ice_seed * 2.0 - 1.0, 0.0, 1.0);
		bubbles = near_l.r * 0.7 + far_l.r * 0.45;
		cracks = max(near_l.g, far_l.g * 0.8);
		cloud = mix(near_l.b, far_l.b, 0.5) * (1.3 - ice_clear);
		// The light that reaches the ice (a lightmap's, the stand-in lamps') shows on what is frozen inside it, at
		// its depth; the clear face itself takes little of it.
		float ice_scatter = (0.04 + 0.25 * cloud + 0.5 * bubbles + 0.22 * cracks) * (1.0 - 0.6 * ice_frost)
				+ 0.75 * ice_frost;
		diffuse = (diffuse * 0.3 + vec3(0.62, 0.84, 1.0) * ice_scatter * 0.55) * (1.0 - 0.3 * ice_groove) * ice_shade;
	}
#endif
	// HOUSE: the house lights' level scales what the engine lights (a baked lightmap included).
	ALBEDO = diffuse * level;
	METALLIC = metallic * 0.5;
	ROUGHNESS = clamp(t.orm.g * roughness_scale, 0.05, 1.0);
	SPECULAR = clamp(specular * 0.5, 0.0, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 fill = mix(sky_bottom, sky_top, n.y * 0.5 + 0.5) * level;
	vec3 film = vec3(0.0);
#ifdef HOUSE
	{
		// The stock rooms' spill, facing as the lit form's film light.
		vec3 to = screen_center - world_pos;
		float d = length(to);
		float facing = clamp(dot(n, to / max(d, 0.001)) * 0.75 + 0.25, 0.0, 1.0);
		film = spill * screen_glow * spill_tint(world_pos) * facing / (1.0 + 0.05 * d * d);
	}
	// The lamps standing in for the room's lights until a lightmap is baked.
	for (int i = 0; i < min(lamp_count, HOUSE_LAMPS); i++) {
		vec3 to = lamp_position[i].xyz - world_pos;
		float d2 = dot(to, to);
		float range = lamp_position[i].w;
		float window = clamp(1.0 - d2 / (range * range), 0.0, 1.0);
		if (window <= 0.0) {
			continue;
		}
		vec3 l = to * inversesqrt(max(d2, 0.0001));
		float lambert = max(dot(n, l), 0.0);
		float cone = 1.0;
		if (lamp_colour[i].w > 0.0) {
			// Up and down only, soft-edged; light grazing the wall it hangs on still shows (the scallops).
			cone = smoothstep(lamp_colour[i].w, mix(lamp_colour[i].w, 1.0, 0.6), abs(l.y));
			lambert = sqrt(lambert);
		}
		fill += lamp_colour[i].rgb * level * (lambert * cone * window * window / (1.0 + d2));
	}
	if (caustics > 0.0 && !bake_pass) {
		float ct = TIME * 0.045 * caustic_speed;
		vec2 cuv = world_pos.xz / (caustic_scale * 4.0);
		float ca = 1.0 - smoothstep(0.0, 0.28, texture(caustic_map, cuv + vec2(ct, ct * 0.37)).r);
		float cb = 1.0 - smoothstep(0.0, 0.28, texture(caustic_map, cuv * 1.31 + vec2(-ct * 0.71, ct * 0.53) + 0.37).r);
		float web = clamp(0.5 * (ca * ca + cb * cb) + 1.5 * ca * cb, 0.0, 1.5);
		film += caustic_colour * caustics * (0.1 + 1.4 * web) * clamp(n.y * 0.8 + 0.2, 0.0, 1.0);
	}
#else
	if (screen_light > 0.0) {
		vec3 to = screen_center - world_pos;
		float d = length(to);
		float facing = clamp(dot(n, to / max(d, 0.001)) * 0.75 + 0.25, 0.0, 1.0);
		// The picture's colour nearest this point (room_lit.gdshader's film_colour()).
		float u = clamp(0.5 + dot(world_pos - screen_center, screen_axis), 0.125, 0.875);
		vec3 c = spill_srgb_to_linear(textureLod(screen_thumb, vec2(u, 0.5), 0.0).rgb);
		film = min(c / SPILL_REFERENCE, vec3(SPILL_MAX)) * screen_light * facing / (1.0 + 0.08 * d * d);
	}
#endif
#ifdef ICE
	// The fill reaches into the ice less than onto a wall: the clear blocks stay dark away from the candles.
	vec3 own = diffuse * (fill * ice_fill + film) * occlusion * ao;
#else
	vec3 own = diffuse * (fill + film) * occlusion * ao;
#endif
	if (sheen > 0.0) {
		float rim = 1.0 - max(dot(n, normalize(CAMERA_POSITION_WORLD - world_pos)), 0.0);
		own += base * (fill + film) * sheen * rim * rim * rim * 2.0;
	}
#ifdef ICE
	if (!bake_pass && ice_snow > 0.0) {
		own += snow_sparkle * (fill * 6.0 + film * 2.0 + vec3(0.012));
	} else if (!bake_pass) {
		vec3 vw = ice_vw;
		vec3 mirror = reflect(-vw, n);
		vec3 glow = vec3(0.0);
		vec3 glint = vec3(0.0);
		vec3 on_face = vec3(0.0);
		for (int i = 0; i < min(ice_glow_count, ICE_GLOWS); i++) {
			vec3 to = (MODEL_MATRIX * vec4(ice_glow_pos[i].xyz, 1.0)).xyz - world_pos;
			float d = length(to);
			float reach = max(ice_glow_pos[i].w, 0.01);
			glow += ice_glow_col[i].rgb * exp(-d / reach);
			// A candle's reflection on the wet face: a small bright lobe, smaller the farther the flame (the wavy
			// face's normals break it into a streak).
			vec3 l = to / max(d, 0.001);
			float lobe = pow(max(dot(mirror, l), 0.0), 60.0 + 160.0 * d * d);
			glint += ice_glow_col[i].rgb * lobe / (1.0 + 0.3 * d * d);
			// Its light on the face (a niche's walls round it).
			on_face += ice_glow_col[i].rgb * max(dot(n, l), 0.0) * reach * reach / (reach * reach + d * d);
		}
		glow *= ice_glow_level;
		glint *= ice_glow_level;
		own += on_face * ice_glow_level * ice_glow_face * mix(0.3, 1.0, ice_frost) * (1.0 - 0.5 * ice_groove);
		vec3 seep = vec3(0.0);
		if (ice_film > 0.0) {
			// Round the picture, the film's own colours carried through the front wall's ice.
			vec2 r = abs(obj_pos.xy - ice_screen_c.xy) - ice_screen_half;
			float out_d = length(max(r, vec2(0.0)));
			float wall = 1.0 - smoothstep(0.2, 0.7, abs(obj_pos.z - ice_screen_c.z));
			seep = spill_tint(world_pos) * screen_glow * ice_film * wall * exp(-out_d / ice_film_reach);
		}
		// The cold depth (the fill seen far into the ice, its own blue-green), the warm light scattered inside (by
		// the milky cloud, the bubbles and the cracks, a little by the clear ice itself), the flecks faintly always.
		vec3 warm = glow + seep;
		vec3 inside = (fill * ice_fill * 2.5 + vec3(ice_night)) * ice_deep * (1.0 + 0.4 * cloud)
				+ warm * (0.25 + 0.3 * cloud + 0.45 * bubbles + 0.25 * cracks + 0.3 * ice_frost);
		float nv = clamp(dot(n, vw), 0.0, 1.0);
		float fresnel = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
		// The picture's soft reflection on the face, in its colours, mostly at grazing angles.
		vec3 to_s = normalize(screen_center - world_pos);
		float shine = pow(max(dot(mirror, to_s), 0.0), 18.0);
		vec3 gloss = (glint * 1.5 + spill_tint(world_pos) * screen_glow * shine * 0.5 * ice_shine) * ice_gloss
				* (0.3 + fresnel);
		// The room in the wet face at a glancing look: the snow overhead, the floor below (the fill, as dim as the
		// house).
		vec3 room_seen = mix(sky_bottom, sky_top, clamp(mirror.y * 0.5 + 0.5, 0.0, 1.0)) * level * 2.0;
		own += inside * ice_inner * (1.0 - fresnel * 0.5) * (1.0 - 0.3 * ice_groove) * ice_shade + gloss
				+ room_seen * fresnel * ice_gloss;
	}
#endif
#ifdef REFLECT
	if (reflect_amount > 0.0) {
		vec3 rv = normalize(CAMERA_POSITION_WORLD - world_pos);
		float nv = clamp(dot(n, rv), 0.0, 1.0);
		float rough = clamp(t.orm.g * roughness_scale, 0.0, 1.0);
		vec3 seen = reflect_world(world_pos, reflect(-rv, n), rough);
		float fresnel = 0.04 + 0.96 * pow(1.0 - nv, 5.0);
		vec3 f = mix(vec3(fresnel), base * (0.75 + 0.25 * fresnel), reflect_metal);
		own += seen * f * reflect_amount * ao;
	}
#endif
#ifdef HOUSE
	if (bake_pass) {
		own = vec3(0.0);
	}
	own += diffuse * vertex_light * COLOR.a * (bake_pass ? 1.0 : level);
#endif
	EMISSION = own + emission;
	AO = occlusion * ao;
	AO_LIGHT_AFFECT = 0.6;
#else
	// The room's light, split as env_unlit has it: ambient, and the screen's spill towards the screen.
	vec3 to_screen = screen_center - world_pos;
	float d = length(to_screen);
	vec3 l = to_screen / max(d, 0.001);
	vec3 spill_light = spill * screen_glow / (1.0 + 0.05 * d * d) * spill_tint(world_pos);
	float fold = 1.0;
	if (pleats > 0.0) {
		float phase = across * pleats * TAU;
		n = normalize(n + across_dir * cos(phase) * pleat_depth);
		fold = 1.0 - pleat_depth * 0.35 * (1.0 - sin(phase));
	}
	vec3 tilt = (n - geo_n) * relief;
	vec3 light = vec3(env_light) * (1.0 + tilt.y) + spill_light * (1.0 + dot(tilt, l));
	light *= mix(1.0 - floor_darkening, 1.0, clamp(world_pos.y / 3.0, 0.0, 1.0));
	light *= mix(1.0, t.orm.r, ao_strength) * fold;

	vec3 base = tint * t.albedo;
	float metallic = t.orm.b;
	float rough = clamp(t.orm.g * roughness_scale, 0.05, 1.0);
	// Metals: no environment to reflect, so a dimmer copy of their colour stands in for it.
	vec3 colour = base * mix(1.0, 0.45, metallic) * light;

	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float nv = max(dot(n, v), 0.0);
	if (specular > 0.0) {
		vec3 h = normalize(l + v);
		// The screen is a wide light: even a polished surface shows a soft patch, not a pin-point.
		float shine = exp2(6.0 * (1.0 - rough) + 1.0);
		float lobe = min(pow(max(dot(n, h), 0.0), shine) * (shine + 2.0) * 0.125, 2.0);
		vec3 f0 = mix(vec3(0.04), base, metallic);
		colour += f0 * spill_light * lobe * specular * (1.0 - rough * 0.7);
	}
	if (sheen > 0.0) {
		float rim = 1.0 - nv;
		colour += base * light * sheen * rim * rim * rim * 2.0;
	}
	ALBEDO = min(colour + emission, vec3(1.0));
#endif
}
