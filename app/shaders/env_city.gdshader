// A city at night round a roof (scripts/env/systems/kit/athens_roof.gd; docs/environments.md, "Room: Athens rooftop"):
// one mesh for every building, street, hill and far light outside the terrace, each vertex naming its material
// (UV2.x). Unshaded and cheap, never baked. The light is the night's: the sky overhead and at the horizon (the sky
// system's colours, read each frame), the city's own glow, the Moon's cool light from its side, the street lamps'
// warm light low on the walls, and the windows. The windows are drawn here from the wall's own coordinates (UV: metres
// along the wall and up from its foot), never from a picture: shutters, frames, curtains, a lit room or a dark one,
// each window its own by a hash. Edges are filtered by their screen size (fwidth), so nothing shimmers in a headset;
// far away a window becomes its average. A warm haze takes the distance. Nothing moves.
//
//   COLOR.rgb  the surface's own colour (linear); COLOR.a  occlusion (1 open, less in a corner or under a slab)
//   UV         metres: along the face, up from the building's foot (a wall); along the street (a street)
//   UV2        x: the material (M_* below); y: the material's own number (a floodlight's strength)
//   CUSTOM0    a wall: bay width (metres; 0 no windows), the windows' top (metres up), the building's seed, its style
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_spill.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// The sky's light (sRGB): overhead and at the horizon.
uniform vec3 sky_top : source_color = vec3(0.03, 0.04, 0.08);
uniform vec3 sky_low : source_color = vec3(0.08, 0.07, 0.08);
uniform float sky_gain = 1.0;
// The city's own glow on everything (its lamps' light scattered back), and the Moon's light from its side.
uniform vec3 city_glow : source_color = vec3(0.12, 0.1, 0.095);
uniform vec3 moon_colour : source_color = vec3(0.3, 0.36, 0.48);
uniform vec3 moon_dir = vec3(-0.9, 0.35, 0.2);
// The street lamps' light low on the walls, the streets' pools.
uniform vec3 street_colour : source_color = vec3(1.0, 0.62, 0.3);
uniform float street_light = 1.0;
// The windows: how many are lit (0..1 of the designed share), the floodlights on the citadel and on the churches, the
// far lamps.
uniform float windows = 1.0;
uniform float lit_share = 0.38;
uniform float floodlight = 1.0;
uniform vec3 flood_colour : source_color = vec3(1.0, 0.7, 0.36);
uniform float church_light = 1.0;
uniform vec3 church_colour : source_color = vec3(1.0, 0.86, 0.66);
uniform float lamps = 1.0;
// The haze: its colour comes from the sky's horizon; how thick, and the most it takes.
uniform float haze_density = 0.006;
uniform float haze_max = 0.55;
uniform vec3 haze_tint : source_color = vec3(1.0, 0.86, 0.74);
// The screen's light on the nearest walls.
uniform float spill = 0.25;

const int M_WALL = 0;
const int M_ROOF = 1;
const int M_METAL = 2;
const int M_PANEL = 3;
const int M_ROCK = 4;
const int M_FLOOD = 5;
const int M_FOLIAGE = 6;
const int M_LAMP = 7;
const int M_STREET = 8;
const int M_CLOTH = 9;
const int M_TILE = 10;
const int M_DARK = 11;
const int M_CHURCH = 12;
const int M_GLASS = 13;
const int M_WATER = 14;

varying vec3 world_pos;
varying vec3 world_normal;
varying flat int mat;
varying flat float extra;
varying float haze;
// Flat: the same on every pixel of a face, exactly (the hashes would turn an interpolation's last bit into noise).
varying flat vec4 wall;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat = int(UV2.x + 0.5);
	extra = UV2.y;
	wall = CUSTOM0;
	float d = distance(world_pos, CAMERA_POSITION_WORLD);
	haze = (1.0 - exp(-d * haze_density)) * haze_max;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 1 inside [a, b] along x, filtered by the screen size of x (w).
float band(float x, float a, float b, float w) {
	return clamp(min(x - a, b - x) / max(w, 1e-4) + 0.5, 0.0, 1.0);
}

// A window or a balcony door in a wall's cell: its look, and its light. f: the position in the cell (0..1 both ways),
// fw: the cell's screen size per pixel, h: the window's hash, kind: 0 a window, 1 a balcony door, 2 a tall window.
// Returns the colour; emit gets the light it gives.
vec3 window(vec2 f, vec2 fw, vec2 cell, float seed, float kind, vec3 wall_c, vec3 light, float share, out vec3 emit) {
	emit = vec3(0.0);
	float h = hash12(cell + seed * 113.0);
	float h2 = hash12(cell.yx * 1.7 + seed * 71.0 + 3.1);
	float h3 = hash12(cell * 2.3 + seed * 19.0 + 7.7);
	// The opening.
	vec2 lo = kind > 0.5 ? vec2(0.24, kind > 1.5 ? 0.12 : 0.0) : vec2(0.27, 0.3);
	vec2 hi = kind > 0.5 ? vec2(0.76, 0.8) : vec2(0.73, 0.8);
	float inside = band(f.x, lo.x, hi.x, fw.x) * band(f.y, lo.y, hi.y, fw.y);
	// Its frame (a little lighter than the wall: painted wood or aluminium), the sill under it.
	float fr = band(f.x, lo.x - 0.035, hi.x + 0.035, fw.x) * band(f.y, lo.y - 0.03, hi.y + 0.02, fw.y);
	float sill = band(f.x, lo.x - 0.06, hi.x + 0.06, fw.x) * band(f.y, lo.y - 0.05, lo.y - 0.01, fw.y)
			* step(0.5, 1.0 - kind);
	vec3 frame_c = mix(vec3(0.72, 0.7, 0.66), vec3(0.32, 0.3, 0.28), step(0.6, h3));
	vec3 c = mix(wall_c, frame_c * light, max(fr - inside, 0.0));
	c = mix(c, wall_c * 1.2, sill);
	// Lit or dark: the designed share times `windows`, each window fading over its own twentieth of the travel.
	float on = 1.0 - smoothstep(windows * lit_share * share - 0.012, windows * lit_share * share + 0.012, h);
	// Shutters: about two in five closed, louvred, in one of the street's colours.
	float shut = step(0.58, h2);
	vec3 shutter = h3 < 0.35 ? vec3(0.12, 0.24, 0.15) : (h3 < 0.6 ? vec3(0.3, 0.2, 0.12) : (h3 < 0.8
			? vec3(0.62, 0.6, 0.55) : vec3(0.16, 0.25, 0.34)));
	float louvre = 0.5 + 0.5 * sin(f.y * 110.0);
	louvre = mix(louvre, 0.5, clamp(fw.y * 110.0 / 2.0, 0.0, 1.0));
	// The room behind: a lamp's warm light, brighter up by the ceiling; some cooler; a curtain's folds.
	vec3 lamp = h3 < 0.62 ? vec3(1.0, 0.66, 0.36) : (h3 < 0.86 ? vec3(1.0, 0.82, 0.6) : vec3(0.62, 0.74, 1.0));
	lamp *= 0.4 + 0.45 * h2;
	float depth = smoothstep(lo.y, hi.y, f.y);
	float folds = 0.8 + 0.2 * sin((f.x - lo.x) * 30.0 + h * 20.0);
	folds = mix(folds, 0.8, clamp(fw.x * 30.0 / 2.0, 0.0, 1.0));
	float curtain_side = smoothstep(0.0, 0.3, abs(f.x - mix(lo.x, hi.x, step(0.5, h3))) / (hi.x - lo.x));
	vec3 room_c = lamp * (0.5 + 0.5 * depth) * mix(0.55, folds, step(0.3, h2)) * (0.45 + 0.55 * curtain_side);
	vec3 dark = vec3(0.012, 0.013, 0.018) + sky_top * 0.25 * (1.0 - depth);
	vec3 glass = mix(dark, room_c, on);
	vec3 closed = shutter * light * (0.7 + 0.3 * louvre) + lamp * on * 0.12 * louvre;
	vec3 opening = mix(glass, closed, shut);
	c = mix(c, opening, inside);
	emit = (on * (1.0 - shut * 0.88)) * inside * (shut > 0.5 ? lamp * 0.12 * louvre : room_c);
	// A lit window's light on the wall round it and on the sill.
	vec2 q = (f - clamp(f, lo, hi)) * vec2(1.0, 1.4);
	emit += on * lamp * (1.0 - inside) * 0.09 * exp(-dot(q, q) * 60.0) * (1.0 - shut * 0.7);
	return c;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 sky = mix(sky_low, sky_top, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * sky_gain;
	float moon = max(dot(n, normalize(moon_dir)), 0.0);
	vec3 light = (sky + city_glow * (0.6 + 0.4 * (1.0 - abs(n.y))) + moon_colour * moon) * COLOR.a;
	vec3 screen = (room_light_at(world_pos, spill) - vec3(env_light)) * max(dot(n, normalize(screen_center
			- world_pos)), 0.0);
	vec3 albedo = COLOR.rgb;
	vec3 c;
	vec3 emit = vec3(0.0);
	if (mat == M_WALL) {
		vec2 m = UV;
		// Plaster: blotches, streaks run down from the top and the sills, the dirt of the street low down.
		float blot = texture(noise_tex, m * 0.045 + wall.z * 7.0).r;
		float streak = texture(noise_tex, vec2(m.x * 0.08 + wall.z * 3.0, m.y * 0.01)).g;
		float top_dirt = smoothstep(2.2, 0.0, wall.y + 1.0 - m.y) * 0.18;
		vec3 a = albedo * (0.84 + 0.3 * blot) * (1.0 - 0.14 * smoothstep(0.55, 0.85, streak) - top_dirt);
		a *= 1.0 - 0.3 * smoothstep(1.2, 0.0, m.y);
		float h = m.y;
		vec3 street = street_colour * street_light * 0.55 * exp(-max(h, 0.0) / 5.5);
		vec3 lit = light + street + screen;
		c = a * lit;
		float bay = abs(wall.x);
		// A party wall (negative bay): blind but for a few small windows, no shops.
		bool party = wall.x < -0.1;
		if (bay > 0.1 && h < wall.y) {
			// Floors: a ground floor 3.6 m, then 3.1 m each.
			float fl = h < 3.6 ? 0.0 : 1.0 + floor((h - 3.6) / 3.1);
			float fy = h < 3.6 ? h / 3.6 : fract((h - 3.6) / 3.1);
			float fx = fract(m.x / bay);
			vec2 cell = vec2(floor(m.x / bay), fl);
			vec2 fw = vec2(fwidth(m.x / bay), fwidth(h / 3.1));
			// A style of 10 or more: a quiet building (most of its windows dark: the near ones facing the screen).
			float style = mod(wall.w, 10.0);
			float share = wall.w > 9.5 ? 0.35 : 1.0;
			float detail = 1.0 - smoothstep(0.12, 0.35, max(fw.x, fw.y));
			if (party) {
				// One cell in four or so has a small window (a bathroom's, a stair's), the rest blind.
				float hp = hash12(cell * 1.31 + wall.z * 57.0);
				if (fl > 0.5 && hp < 0.22) {
					vec3 e;
					vec2 f2 = vec2(fx, fy);
					vec2 q = (f2 - vec2(0.5, 0.55)) * vec2(2.2, 2.6) + 0.5;
					vec3 wc = window(q, fw * vec2(2.2, 2.6), cell, wall.z + 0.5, 0.0, c, lit, share, e);
					c = mix(c, wc, detail);
					emit += e * detail;
				}
			} else if (fl < 0.5) {
				// The ground floor: shops behind roller shutters, an entrance's lit hall now and then.
				float hs = hash12(cell + wall.z * 31.0);
				float open = band(fx, 0.08, 0.92, fw.x) * band(fy, 0.0, 0.78, fw.y);
				vec3 roller = vec3(0.34, 0.33, 0.32) * (0.8 + 0.2 * sin(fy * 140.0)) * lit;
				vec3 shopc = hs < 0.18 ? vec3(1.0, 0.85, 0.6) * 0.7 : (hs < 0.26 ? vec3(0.7, 0.85, 1.0) * 0.5 : vec3(0));
				float shops = style > 2.5 && style < 3.5 ? 0.0 : 1.0;
				c = mix(c, hs < 0.26 ? shopc : roller, open * shops * detail);
				emit += hs < 0.26 ? shopc * open * shops * detail : vec3(0.0);
			} else {
				float kind = style > 0.5 && style < 1.5 ? 1.0 : (style > 1.5 && style < 2.5 ? 2.0 : (style > 3.5 ? 1.0 : 0.0));
				vec3 e;
				vec3 wc = window(vec2(fx, fy), fw, cell, wall.z, kind, c, lit, share, e);
				// Far off: the cell's average (no shimmer).
				float on = 1.0 - smoothstep(windows * lit_share * share - 0.012, windows * lit_share * share + 0.012,
						hash12(cell + wall.z * 113.0));
				vec3 avg = c * 0.8 + on * vec3(1.0, 0.7, 0.42) * 0.16;
				c = mix(avg, wc, detail);
				emit += mix(on * vec3(1.0, 0.7, 0.42) * 0.16, e, detail);
				if (style > 0.5 && style < 1.5) {
					// Balconies painted on (far buildings): a slab's lit edge, its shadow, the railing's band.
					float slab = band(fy, 0.0, 0.05, fw.y);
					float rail = band(fy, 0.05, 0.36, fw.y);
					float under = band(fy, 0.9, 1.0, fw.y);
					c = mix(c, albedo * lit * 1.1, slab);
					c = mix(c, c * 0.55 + albedo * lit * 0.15, rail * 0.8);
					c *= 1.0 - 0.45 * under;
				}
			}
		}
	} else if (mat == M_ROOF) {
		float v = texture(noise_tex, world_pos.xz * 0.08).b;
		c = albedo * (0.8 + 0.35 * v) * (light + screen);
	} else if (mat == M_METAL) {
		c = albedo * (light * 1.1 + screen) + sky_top * 0.15;
	} else if (mat == M_PANEL) {
		// A solar heater's glass: the sky in it, a dark blue under.
		vec3 v = normalize(world_pos - CAMERA_POSITION_WORLD);
		float fres = pow(1.0 - max(dot(-v, n), 0.0), 3.0);
		c = vec3(0.01, 0.015, 0.03) + mix(sky_top, sky_low, 0.5) * (0.6 + 1.4 * fres) * sky_gain;
	} else if (mat == M_ROCK) {
		// Rock in the floodlights' reach (UV.y: 1 at the walls' foot, falling away down the slope), strata.
		float s = texture(noise_tex, vec2(world_pos.x * 0.03 + world_pos.z * 0.03, world_pos.y * 0.25)).g;
		float flood = floodlight * smoothstep(0.0, 1.0, UV.y) * extra;
		c = albedo * (0.75 + 0.5 * s) * (light * 0.8 + flood_colour * flood + screen);
	} else if (mat == M_FLOOD) {
		// Floodlit stone: brighter low down (the lamps at its foot), the face towards the eye a little brighter.
		vec3 to_eye = CAMERA_POSITION_WORLD - world_pos;
		float facing = 0.6 + 0.4 * max(dot(n, normalize(vec3(to_eye.x, 0.0, to_eye.z) + vec3(1e-4))), 0.0);
		float s = texture(noise_tex, vec2(world_pos.x * 0.1 + world_pos.z * 0.1, world_pos.y * 0.3)).r;
		float flood = floodlight * extra * (1.3 - 0.6 * clamp(UV.y / 16.0, 0.0, 1.0)) * facing;
		c = albedo * (0.85 + 0.3 * s) * (light * 0.6 + flood_colour * flood);
	} else if (mat == M_CHURCH) {
		vec3 to_eye = CAMERA_POSITION_WORLD - world_pos;
		float facing = 0.55 + 0.45 * max(dot(n, normalize(vec3(to_eye.x, 0.0, to_eye.z) + vec3(1e-4))), 0.0);
		float flood = church_light * extra * (1.25 - 0.5 * clamp(UV.y, 0.0, 1.0)) * facing;
		c = albedo * (light + church_colour * flood + screen);
	} else if (mat == M_FOLIAGE) {
		float v = texture(noise_tex, world_pos.xz * 0.35 + world_pos.y * 0.2).r;
		c = albedo * (0.55 + 0.9 * v) * (light + street_colour * street_light * 0.2 * extra + flood_colour * floodlight
				* 0.25 * UV.y + screen);
	} else if (mat == M_LAMP) {
		c = albedo * lamps;
		emit = vec3(0.0);
	} else if (mat == M_STREET) {
		// Asphalt or paving; the lamps' pools along the street (UV.x along it, a lamp every CUSTOM0.x metres).
		float along = UV.x / max(wall.x, 1.0) + wall.y;
		float pool = exp(-pow((fract(along) - 0.5) * wall.x, 2.0) / 40.0);
		float v = texture(noise_tex, world_pos.xz * 0.2).g;
		c = albedo * (0.8 + 0.3 * v) * (light * 0.6 + street_colour * street_light * (0.08 + 0.55 * pool));
	} else if (mat == M_CLOTH) {
		float h = UV.y;
		c = albedo * (light + street_colour * street_light * 0.45 * exp(-max(h, 0.0) / 5.5) + screen);
	} else if (mat == M_TILE) {
		// Barrel tiles or a dome's: rows of them.
		float r = 0.75 + 0.25 * sin(UV.x * 26.0);
		r = mix(r, 0.85, clamp(fwidth(UV.x * 26.0) / 3.0, 0.0, 1.0));
		c = albedo * r * (light + church_colour * church_light * extra * 0.5 + screen);
	} else if (mat == M_DARK) {
		c = albedo * light * 0.5;
	} else if (mat == M_GLASS) {
		// A lit window of its own (a lantern, a lit stair head's door, a kiosk): its colour is its light.
		c = albedo * windows;
	} else if (mat == M_WATER) {
		vec3 v = normalize(world_pos - CAMERA_POSITION_WORLD);
		float fres = pow(1.0 - max(dot(-v, n), 0.0), 4.0);
		c = albedo * light * 0.3 + sky_low * fres * 1.5;
	} else {
		c = albedo * light;
	}
	c += emit;
	// The haze over the distance, the colour of the sky low down warmed by the city's lamps.
	vec3 hz = mix(sky_low * sky_gain, city_glow, 0.35) * haze_tint;
	float hk = mat == M_LAMP ? haze * 0.4 : haze;
	ALBEDO = mix(c, hz, hk);
}
