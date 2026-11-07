// Haze, dust and smoke in the projector's beam (scripts/env/systems/atmosphere.gd): a beam-shaped volume, drawn
// additively on the cone's four sides and on two planes through its axis (a cross), so the beam reads as a volume from
// any seat. No raymarch and no depth texture: each surface samples a slowly drifting noise field at its own point,
// and the six surfaces together stand in for the light's path through the air.
//   haze     the even veil (0..1); smoke billows it into slow, rising clouds (a 1983 multiplex)
//   dust     motes that twinkle where they cross the light
// Brightest near the lens and gone before the screen, so the picture stays clean. It shows more as the house lights
// go down (env_light over house_reference, as room_beam.gdshader) and takes the picture's colour and brightness from
// the bias light (spill_tint) when follow_picture is 1. UV.y runs along the beam (0 at the lens); UV2.x across a
// surface (0..1); UV2.y is 1 on the two inner planes, which fade where the view grazes them (no lines).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float haze = 0.5;
uniform float dust = 0.0;
uniform float smoke = 0.0;
uniform float follow_picture = 1.0;
uniform float house_reference = 0.05;
uniform float strength = 0.05;
// Metres a second the air drifts.
uniform float drift = 0.04;

#include "res://shaders/env_spill.gdshaderinc"

varying float along;
varying vec2 side;
varying vec3 world_pos;

void vertex() {
	along = UV.y;
	side = UV2;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float haze_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float haze_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(haze_hash(i), haze_hash(i + vec3(1, 0, 0)), f.x),
			mix(haze_hash(i + vec3(0, 1, 0)), haze_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(haze_hash(i + vec3(0, 0, 1)), haze_hash(i + vec3(1, 0, 1)), f.x),
			mix(haze_hash(i + vec3(0, 1, 1)), haze_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Motes: one point in some cells of a fine grid drifting with the air; a soft dot where the surface passes it.
float motes(vec3 p, float amount) {
	vec3 q = p * 9.0;
	vec3 cell = floor(q);
	float h = haze_hash(cell);
	if (h < 1.0 - 0.35 * amount) {
		return 0.0;
	}
	vec3 at = vec3(haze_hash(cell + 3.1), haze_hash(cell + 7.7), haze_hash(cell + 1.9)) * 0.6 + 0.2;
	float d = length(q - cell - at);
	float twinkle = 0.55 + 0.45 * sin(TIME * (0.6 + 1.4 * h) + h * 40.0);
	return (1.0 - smoothstep(0.0, 0.07, d)) * twinkle;
}

void fragment() {
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	float dark = clamp(1.25 - level, 0.2, 1.0);
	float edge = smoothstep(0.0, 0.25, min(side.x, 1.0 - side.x));
	float facing = abs(dot(NORMAL, VIEW));
	// The sides weigh by how squarely they are seen (the path through the light); the inner planes fade when grazed.
	float seen = side.y > 0.5 ? smoothstep(0.08, 0.4, facing) * 0.6 : facing * facing;
	vec3 flow = vec3(TIME * drift * 0.4, TIME * drift * 0.25, TIME * drift);
	vec3 p = world_pos * 0.7 + flow;
	float n = haze_noise(p) * 0.6 + haze_noise(p * 2.3 + vec3(4.1, 1.7, 2.9)) * 0.4;
	float even = mix(0.55, 1.35, n);
	// Smoke: big slow billows that rise, with thin gaps between them.
	vec3 s = world_pos * 0.32 + vec3(TIME * 0.012, -TIME * 0.035, TIME * 0.008);
	float b = haze_noise(s + 0.6 * vec3(haze_noise(s * 1.7), haze_noise(s * 1.7 + 5.0), 0.0));
	float billows = smoothstep(0.3, 0.85, b) * 2.2;
	float density = haze * mix(even, billows, clamp(smoke, 0.0, 1.0)) + 0.6 * smoke * billows;
	float path = (1.0 - smoothstep(0.6, 0.95, along)) * (0.45 + 0.55 * (1.0 - along));
	float a = strength * dark * path * edge * seen * density;
	a += strength * 6.0 * dark * path * edge * motes(world_pos + flow * 2.0, dust) * dust;
	vec3 tint = mix(vec3(1.0), spill_tint(screen_center), clamp(follow_picture, 0.0, 1.0));
	ALBEDO = colour * tint * a;
}
