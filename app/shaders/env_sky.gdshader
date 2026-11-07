// The sky system's dome (scripts/env/systems/sky.gd; docs/environments.md, "The sky"): the twilight to night gradient,
// the Milky Way where the galaxy really lies (from the stars' time and latitude), clouds lit by the screen, an aurora
// low over the north, and a shooting star now and then. Drawn round the camera at the far end of the room, so the
// room's own walls and the screen always cover it. One draw; every layer is skipped when it is off.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, specular_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"
#include "res://shaders/env_spill.gdshaderinc"

// Room frame -> galactic (x to the galaxy's centre, z its north pole).
uniform mat3 galactic = mat3(1.0);
uniform float milky_way = 0.5;
uniform vec3 milky_colour : source_color = vec3(0.9, 0.86, 0.78);
// The clouds' own colour in the night's light (a binding can take it towards the film's colour) and how much the
// clouds near the screen catch its light (the picture's colour from the bias light).
uniform vec3 cloud_colour : source_color = vec3(0.07, 0.075, 0.09);
uniform float cloud_screen = 1.0;
uniform float aurora = 0.0;
uniform vec3 aurora_low : source_color = vec3(0.2, 1.0, 0.55);
uniform vec3 aurora_high : source_color = vec3(0.65, 0.25, 0.85);
// The aurora's middle (a horizontal unit direction, room frame) and its slow clock (seconds x speed, from sky.gd).
uniform vec3 aurora_dir = vec3(0.0, 0.0, -1.0);
uniform float aurora_time = 0.0;
// A shooting star: from, to (unit directions) and how far along it is (w < 0: none).
uniform vec4 meteor_from = vec4(0.0, 1.0, 0.0, -1.0);
uniform vec3 meteor_to = vec3(0.0, 1.0, 0.0);

const float MILKY_GAIN = 0.05;
const float AURORA_GAIN = 0.22;

varying vec3 dir;
varying vec3 wdir;

void vertex() {
	dir = normalize(VERTEX);
	wdir = sky_room_basis(MODEL_MATRIX) * dir;
	vec3 world = CAMERA_POSITION_WORLD + wdir * radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 base = sky_base(d);
	vec3 c = base;
	float above = mix(smoothstep(-0.01, 0.14, d.y), step(-0.02, d.y), space);
	float dark = mix(clamp(1.0 - lum(base) * 14.0, 0.0, 1.0), 1.0, space);
	if (milky_way > 0.0) {
		vec3 g = galactic * d;
		float l = atan(g.y, g.x);
		float b = asin(clamp(g.z, -1.0, 1.0));
		float lc = cos(l);
		float width = 0.12 + 0.16 * pow(max(lc, 0.0), 6.0);
		float band = exp(-(b * b) / (width * width));
		float along = 0.3 + 0.7 * pow(0.5 + 0.5 * lc, 2.0) + 0.25 * exp(-pow((l - 1.35) / 0.35, 2.0));
		float mottle = texture(sky_noise, vec2(l / (2.0 * SKY_PI) * 5.0, b * 1.4 + 0.5)).b;
		float rift = 1.0 - 0.75 * exp(-pow((b - 0.03) / 0.045, 2.0)) * smoothstep(-0.35, 0.05, l)
				* (1.0 - smoothstep(1.2, 1.6, l));
		float mw = band * along * (0.45 + 0.9 * mottle) * rift;
		c += milky_colour * mw * milky_way * MILKY_GAIN * dark * above;
	}
	if (aurora > 0.0 && d.y > -0.02) {
		vec2 h = normalize(vec2(d.x, d.z) + vec2(1e-5));
		vec2 a = normalize(aurora_dir.xz);
		float rel = atan(h.x * a.y - h.y * a.x, dot(h, a));
		float spread = exp(-rel * rel / 1.6);
		float alt = asin(clamp(d.y, -1.0, 1.0));
		float wave = textureLod(sky_noise, vec2(rel * 0.22 + aurora_time * 0.004, 0.31), 2.0).r - 0.5;
		float bottom = 0.13 + 0.12 * wave;
		float hh = alt - bottom;
		float vert = smoothstep(-0.015, 0.02, hh) * exp(-max(hh, 0.0) / 0.32);
		float rays = texture(sky_noise, vec2(rel * 1.6 + wave * 0.6 + aurora_time * 0.006, hh * 0.08)).a;
		rays = 0.35 + 1.1 * rays * rays;
		float swell = 0.75 + 0.25 * textureLod(sky_noise, vec2(aurora_time * 0.002, 0.77), 0.0).g;
		vec3 col = mix(aurora_low, aurora_high, smoothstep(0.05, 0.55, hh));
		c += col * aurora * spread * vert * rays * swell * AURORA_GAIN * dark;
	}
	if (meteor_from.w >= 0.0) {
		float t = meteor_from.w;
		vec3 head = normalize(mix(meteor_from.xyz, meteor_to, t));
		vec3 tail = normalize(mix(meteor_from.xyz, meteor_to, max(t - 0.3, 0.0)));
		vec3 ab = head - tail;
		float k = clamp(dot(d - tail, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
		float dist = length(d - (tail + ab * k));
		c += vec3(0.85, 0.9, 1.0) * exp(-dist * dist / 1.6e-6) * k * sin(t * SKY_PI) * 0.6 * dark;
	}
	if (clouds > 0.0) {
		float cover = sky_cloud_cover(d, -1.0);
		if (cover > 0.0) {
			float g = max(dot(normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5)), glow_dir), 0.0);
			vec3 lit = cloud_colour + glow_colour * pow(g, 3.0) * (1.0 - smoothstep(0.0, 1.0, dusk)) * 0.5;
			if (cloud_screen > 0.0) {
				vec3 to_screen = normalize(screen_center - CAMERA_POSITION_WORLD);
				float f = max(dot(normalize(wdir), to_screen), 0.0);
				lit += cloud_screen * screen_glow * pow(f, 3.0) * 0.18
						* spill_tint(CAMERA_POSITION_WORLD + normalize(wdir) * 20.0);
			}
			lit *= mix(1.0, 0.65, cover);
			c = mix(c, lit, cover);
		}
	}
	ALBEDO = c;
}
