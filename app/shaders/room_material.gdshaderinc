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
// Included by room_material.gdshader and room_material_triplanar.gdshader (TRIPLANAR defined), after their
// shader_type and render_mode.

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

// env_light, screen_center, screen_glow and the bias light's tint (ideas #29).
#include "res://shaders/env_spill.gdshaderinc"

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
		vec2 uv = vec2(dot(obj_pos, u_axis), -dot(obj_pos, v_axis)) / tiling + uv_offset;
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
		uv = UV * uv_repeat + uv_offset;
		tan_u = normalize(world_tangent);
		tan_v = normalize(world_binormal);
		across = UV.x * uv_repeat.x;
	} else {
		vec3 on = abs(obj_normal);
		int axis = on.x > on.y ? (on.x > on.z ? 0 : 2) : (on.y > on.z ? 1 : 2);
		vec3 u_axis;
		vec3 v_axis;
		face_frame(axis, obj_normal[axis] < 0.0 ? -1.0 : 1.0, u_axis, v_axis);
		across = dot(obj_pos, u_axis);
		uv = vec2(across, -dot(obj_pos, v_axis)) / tiling + uv_offset;
		tan_u = to_world(model, u_axis);
		tan_v = to_world(model, v_axis);
	}
	t = sample_maps(uv);
	n = normalize(tan_u * t.normal.x + tan_v * t.normal.y + geo_n * t.normal.z);
	across_dir = tan_u;
#endif

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
	ALBEDO = min(colour, vec3(1.0));
}
