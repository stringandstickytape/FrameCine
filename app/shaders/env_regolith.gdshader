// The Moon round the Crater's dome (scripts/env/systems/kit/lunar_surface.gd; docs/environments.md "Room: Crater"):
// the regolith, its rocks and their shadows, the rover's tracks and the footprints, the crater's wall, and what stands
// on the plain (painted modules, gold foil, solar cells, dark glass). Unshaded and never baked: the light is computed
// here, all in the room's frame:
//   Earth's   from Earth's place in the sky (earth_dir), blue-white; the regolith's own way with it (it scatters the
//             light back where it came from: bright with the light behind the eye, dim looking into it, and no darkening
//             at a grazing view), so the plain ahead, lit from beyond it, is dim and its rocks show their shadows
//   the sun's only on what stands over the shadow's line (the sun is just under the rim behind the room): the
//             crater wall's peaks and the tops of the tallest things on the plain
//   the dome's lamps on the berm round its foot (the house lights' level), the film's light a little near the glass
// Per vertex: COLOR the surface's tone (or for a track or prints the path's direction in r, g and its fade in b), UV2.x
// the material (lunar_surface.gd M_*), UV2.y a seed; UV a track's or prints' metres along and across.
// The craterlets' map (`detail`): R, G a slope, B a tone, A a grain's glint. Two reads near, one far. Nothing moves.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_spill.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 earth_dir = vec3(0.18, 0.5, -0.85);
uniform vec3 earth_colour : source_color = vec3(0.62, 0.7, 0.86);
uniform float earth_energy = 0.85;
uniform vec3 sun_dir = vec3(0.1, 0.02, 1.0);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.97, 0.92);
uniform float sun_energy = 1.1;
// The shadow's line: over y = w + dot(xyz, p) a point sees the sun.
uniform vec4 sun_line = vec4(0.0, 0.0, 0.018, 15.5);
// The faint fill from the black sky and the stars (and Earth's light off the plain round about).
uniform vec3 fill : source_color = vec3(0.012, 0.014, 0.02);
// The whole scene's level: 1 in the pre-show, lower in the film (the eye adjusts to the dimmed room; terrace.gd).
uniform float level = 1.0;
uniform vec3 dome_centre = vec3(0.0, -1.26, -9.0);
uniform float dome_radius = 18.0;
uniform vec3 lamp_colour : source_color = vec3(0.85, 0.9, 1.0);
uniform float lamps = 1.0;
uniform float sparkle = 1.0;

const int M_REGOLITH = 0;
const int M_ROCK = 1;
const int M_SHADOW = 2;
const int M_TRACK = 3;
const int M_PRINTS = 4;
const int M_PAINT = 5;
const int M_FOIL = 6;
const int M_SOLAR = 7;
const int M_RIM = 8;
const int M_GLASS = 9;

varying vec3 pos;
varying vec3 nrm;
varying vec3 world_pos;
varying flat int mat;
varying float seed;
varying vec3 cam;

void vertex() {
	pos = VERTEX;
	nrm = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mat = int(UV2.x + 0.5);
	seed = UV2.y;
	// The eye in the room's frame (the same for every vertex; once a vertex, not once a pixel).
	cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

// The regolith's way with light: Lommel-Seeliger blended with Lambert, and the phase's fall (dim into the light).
float lunar(vec3 n, vec3 l, vec3 v) {
	float ci = max(dot(n, l), 0.0);
	float ce = max(dot(n, v), 0.05);
	float ls = 2.0 * ci / (ci + ce);
	float g = acos(clamp(dot(l, v), -1.0, 1.0));
	float phase = mix(1.15, 0.45, smoothstep(0.0, 2.7, g));
	return mix(ci, ls * 0.6, 0.55) * phase;
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A boot's print in the band's own metres (x along, y across from its middle): 0 outside, 1 at the bottom; its
// slope (towards the wall) in grad.
float boot(vec2 q, out vec2 grad) {
	// Toe wider than the heel, a waist between.
	float w = 0.055 + 0.012 * smoothstep(-0.05, 0.1, q.x) - 0.01 * exp(-pow((q.x + 0.03) / 0.04, 2.0));
	vec2 e = vec2(q.x / 0.15, q.y / w);
	float d = length(e) - 1.0;
	grad = normalize(vec2(e.x / 0.15, e.y / w) + vec2(1e-5));
	return smoothstep(0.05, -0.25, d);
}

void fragment() {
	vec3 v = normalize(cam - pos);
	vec3 n = normalize(nrm);
	if (!FRONT_FACING && dot(n, v) < 0.0) {
		n = -n;
	}
	float dist = length(cam - pos);
	vec3 l = normalize(earth_dir);
	vec3 s = normalize(sun_dir);
	vec3 albedo = vec3(0.162, 0.159, 0.151);
	float earth_k = 1.0;
	bool ground = mat == M_REGOLITH || mat == M_SHADOW || mat == M_TRACK || mat == M_PRINTS || mat == M_RIM;
	float spec = 0.0;
	float gloss = 0.0;
	if (ground || mat == M_ROCK) {
		// The craterlets: two scales near, one far; their slope bends the normal (most where the ground is flat).
		vec2 uv1 = pos.xz * 0.31 + vec2(seed * 0.13);
		vec4 d1 = texture(detail, uv1);
		vec4 d2 = texture(detail, pos.xz * 1.37 + vec2(0.31, 0.77));
		float near = 1.0 - smoothstep(12.0, 60.0, dist);
		vec2 slope = (d1.rg - 0.5) * 1.1 + (d2.rg - 0.5) * 0.9 * near;
		if (mat == M_ROCK) {
			slope = (texture(detail, pos.xy * 0.9 + pos.zx * 0.7).rg - 0.5) * 1.6;
		}
		if (mat == M_RIM) {
			// The wall's crags: the relief laid on its steep faces along the wall and up it.
			vec4 cr = texture(detail, vec2(pos.x - pos.z, pos.y) * 0.09);
			vec4 cr2 = texture(detail, vec2(pos.x + pos.z, pos.y) * 0.031 + vec2(0.4));
			slope = (cr.rg - 0.5) * 1.4 + (cr2.rg - 0.5) * 1.8;
			n = normalize(n + vec3(slope.x, slope.y * 0.6, -slope.x * 0.5));
		} else {
			n = normalize(n + vec3(slope.x, 0.0, slope.y));
		}
		float tone = mix(0.86, 1.1, d1.b) * mix(1.0, mix(0.9, 1.08, d2.b), near);
		albedo *= tone * (mat == M_TRACK || mat == M_PRINTS ? 1.0 : COLOR.r);
		if (mat == M_ROCK) {
			albedo = vec3(0.13, 0.127, 0.123) * COLOR.rgb * tone;
		}
		// A grain's glint: the glassy beads in the dust, only near, only when the light and the eye line up.
		if (sparkle > 0.0 && near > 0.0 && mat != M_ROCK) {
			float grain = texture(detail, pos.xz * 4.1 + vec2(0.5)).a;
			vec3 h = normalize(l + v);
			float lined = pow(max(dot(normalize(nrm), h), 0.0), 3.0);
			spec += smoothstep(0.96, 1.0, grain) * lined * near * 1.8 * sparkle;
		}
	}
	if (mat == M_SHADOW) {
		earth_k = 0.0;
	} else if (mat == M_TRACK) {
		// The tread: chevrons pressed across the band, the band smoother and darker than the dust beside it, a lip
		// along its edges; it fades out along the last of the path.
		vec2 dir = COLOR.rg * 2.0 - 1.0;
		vec3 along = normalize(vec3(dir.x, 0.0, dir.y));
		vec3 side = vec3(-along.z, 0.0, along.x);
		float a = UV.y * 2.0 - 1.0;
		float band = (1.0 - smoothstep(0.7, 1.0, abs(a))) * COLOR.b;
		float w = fract(UV.x * 4.5 + abs(a) * 0.55);
		float ridge = smoothstep(0.0, 0.12, w) - smoothstep(0.45, 0.6, w);
		float lip = exp(-pow((abs(a) - 0.92) / 0.08, 2.0)) * COLOR.b;
		n = normalize(n + along * (ridge - 0.5) * 0.5 * band + side * sign(a) * lip * 0.6);
		albedo *= 1.0 - 0.16 * band;
	} else if (mat == M_PRINTS) {
		vec2 dir = COLOR.rg * 2.0 - 1.0;
		vec3 along = normalize(vec3(dir.x, 0.0, dir.y));
		vec3 side = vec3(-along.z, 0.0, along.x);
		float stride = 0.78;
		float k = floor(UV.x / stride);
		float lr = mod(k, 2.0) < 1.0 ? -1.0 : 1.0;
		float jit = hash1(vec2(k, seed)) - 0.5;
		vec2 q = vec2(UV.x - (k + 0.5) * stride + jit * 0.06, (UV.y - 0.5) * 0.7 - lr * 0.12 - jit * 0.03);
		vec2 grad;
		float in_print = boot(q, grad) * COLOR.b * step(0.12, hash1(vec2(k * 1.7, 3.1)));
		// The print's floor pressed flat and darker, its walls lit on the side towards Earth; the sole's bars.
		float wall = in_print * (1.0 - in_print) * 4.0;
		float bars = smoothstep(0.3, 0.5, abs(fract(q.x * 38.0) - 0.5));
		n = normalize(n - (along * grad.x + side * grad.y) * wall * 0.9 + along * (bars - 0.5) * 0.25 * in_print);
		albedo *= 1.0 - 0.2 * in_print;
	} else if (mat == M_PAINT) {
		albedo = COLOR.rgb * 0.75;
		gloss = 0.25;
	} else if (mat == M_FOIL) {
		// Gold foil, crinkled: the crinkles catch Earth's light in small glints.
		vec4 cr = texture(detail, pos.xy * 1.9 + pos.zx * 1.3 + vec2(seed * 0.21));
		n = normalize(n + vec3(cr.r - 0.5, cr.g - 0.5, cr.b - 0.5) * 1.6);
		albedo = vec3(0.55, 0.36, 0.1) * COLOR.rgb;
		gloss = 1.0;
	} else if (mat == M_SOLAR) {
		vec2 cell = fract(vec2(pos.x + pos.z, pos.y) * 3.0);
		float grid = step(0.06, cell.x) * step(0.06, cell.y);
		albedo = mix(vec3(0.35), vec3(0.02, 0.03, 0.07), grid);
		gloss = 0.6;
	} else if (mat == M_GLASS) {
		albedo = vec3(0.01);
		gloss = 1.4;
	}
	vec3 light = fill;
	if (ground || mat == M_ROCK) {
		light += earth_colour * earth_energy * lunar(n, l, v) * earth_k;
	} else {
		light += earth_colour * earth_energy * max(dot(n, l), 0.0);
	}
	// The sun, over its shadow's line only (a soft edge half a metre deep).
	// The line wanders a few metres up and down along the rim (the far ridges behind are not a straight edge).
	float wander = (textureLod(detail, pos.xz * 0.0031, 4.0).b - 0.5) * 9.0
			+ (texture(detail, vec2(pos.x + pos.z, pos.y) * 0.05).b - 0.5) * 3.0;
	float over = smoothstep(-0.4, 0.4, pos.y - (sun_line.w + dot(sun_line.xyz, pos) + wander));
	if (over > 0.0) {
		float sl = (ground || mat == M_ROCK) ? lunar(n, s, v) * 1.4 : max(dot(n, s), 0.0);
		light += sun_colour * sun_energy * sl * over;
	}
	// The dome's lamps on its berm, falling off over a few metres.
	float rho = length(pos.xz - dome_centre.xz) - dome_radius;
	light += lamp_colour * lamps * 0.22 * exp(-max(rho, 0.0) / 2.2) * (0.35 + 0.65 * max(n.y, 0.0));
	// The film's light through the glass, a little (it falls off quickly).
	light += (room_light_at(world_pos, 0.35) - vec3(env_light)) * 0.5;
	vec3 c = albedo * light * level;
	if (gloss > 0.0) {
		vec3 r = reflect(-v, n);
		float sp = pow(max(dot(r, l), 0.0), mat == M_FOIL ? 18.0 : 40.0);
		c += earth_colour * earth_energy * sp * gloss * (mat == M_FOIL ? vec3(1.0, 0.7, 0.3) : vec3(1.0)) * level;
		c += sun_colour * pow(max(dot(r, s), 0.0), 30.0) * over * gloss * level;
	}
	c += earth_colour * spec * earth_energy * level * earth_k;
	ALBEDO = c;
}
