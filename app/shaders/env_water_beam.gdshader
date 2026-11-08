// A floodlight's beam in the water outside a glass dome (scripts/env/systems/kit/seabed.gd): the light the murk
// scatters out of the cone. The mesh is the cone itself; each fragment works out the eye's ray's chord through the
// cone (where it enters and leaves it, the beam's end included) and adds the light scattered along that chord: the
// light per metre falls as the beam widens (it spreads over a larger section), and the murk between the beam and the
// eye takes its share. So the beam reads as a soft shaft from the side and as a glowing cone seen along it from
// behind the lamp, as the seats see it; its edges fade to nothing (the chord there is short). Added over what is
// behind, never darkening; the sea floor where the beam meets it cuts it off (the depth test). Only the nearer of a
// chord's two faces draws it. Per vertex: UV.x the lamp's index (flood_pos, flood_aim), UV.y 0 at the lamp, 1 at the
// beam's end.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_water.gdshaderinc"

uniform float strength = 0.22;
uniform float reach = 15.0;
// The cone: tan of its half angle, and its radius at the lamp.
uniform float spread = 0.3;
uniform float lens = 0.1;

varying vec3 world_pos;
varying float lamp;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lamp = UV.x;
}

void fragment() {
	int i = clamp(int(lamp + 0.5), 0, FLOODS - 1);
	vec3 o = flood_pos[i].xyz;
	vec3 d = flood_aim[i].xyz;
	vec3 apex = o - d * (lens / spread);
	float cap = reach + lens / spread;
	float k = 1.0 / (1.0 + spread * spread);
	vec3 c = CAMERA_POSITION_WORLD;
	vec3 r = normalize(world_pos - c);
	float sf = distance(world_pos, c);
	vec3 co = c - apex;
	float rd = dot(r, d);
	float cd = dot(co, d);
	// The ray against the cone (d.(X - apex))^2 = k |X - apex|^2: the other place it crosses the surface.
	float qa = rd * rd - k;
	float qb = 2.0 * (rd * cd - k * dot(r, co));
	float qc = cd * cd - k * dot(co, co);
	float disc = qb * qb - 4.0 * qa * qc;
	float so = -1.0;
	if (abs(qa) > 1e-5 && disc > 0.0) {
		float sq = sqrt(disc);
		float s1 = (-qb - sq) / (2.0 * qa);
		float s2 = (-qb + sq) / (2.0 * qa);
		so = abs(s1 - sf) > abs(s2 - sf) ? s1 : s2;
		if (so < 0.0 || dot(c + r * so - apex, d) < 0.0) {
			so = -1.0;
		}
	}
	float s_cap = abs(rd) > 1e-4 ? (cap - cd) / rd : -1.0;
	if (so < 0.0) {
		// No second crossing: the chord runs out through the beam's end, or back to the eye.
		so = rd > 0.0 ? max(s_cap, sf) : 0.0;
	} else if (so < sf) {
		discard;
	}
	float a = min(sf, so);
	float b = max(sf, so);
	if (s_cap > 0.0) {
		if (rd > 0.0) {
			b = min(b, s_cap);
		} else {
			a = max(a, s_cap);
		}
	}
	a = max(a, 0.0);
	float chord = max(b - a, 0.0);
	vec3 mid = c + r * (a + b) * 0.5;
	float t = clamp(dot(mid - o, d), 0.0, reach);
	float radius = lens + spread * t;
	float along = t / reach;
	float ends = smoothstep(0.0, 0.04, along) * (1.0 - along) * (1.0 - along);
	float drift = 0.85 + 0.15 * sin(t * 1.1 - TIME * 0.3 * water_motion + float(i) * 2.0);
	ALBEDO = flood_colour * flood * flood_pos[i].w * strength * chord / (1.0 + 2.0 * radius * radius) * ends * drift
			* exp(-(a + b) * 0.5 * murk * 0.6);
}
