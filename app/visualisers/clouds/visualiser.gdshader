// Above the clouds (visualiser.json): a flight over a sea of cloud at dusk, ray-marched as a height field. The
// cloud tops roll away to the horizon; out of them stand towers of cumulus, one to a cell of a wide grid, each a part
// of the spectrum: it climbs with its part and glows from inside as storms do (a soft light, never a flash). The low
// sun lights one side of every billow gold and leaves the other in blue shade (each point looks towards the sun to
// see if a higher top stands in the way), with a silver edge where a top stands against the sun. Above: the sky from
// the sun's band of colour up to the dark, the first stars, a wisp of high cloud, and an airliner drawing its
// trail across. The camera flies on the music's clock (drive). No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float towers = 0.6;
uniform float speed = 0.5;
uniform float storm = 0.6;
uniform vec4 zenith : source_color = vec4(0.08, 0.12, 0.3, 1.0);
uniform vec4 sunset : source_color = vec4(1.0, 0.55, 0.3, 1.0);
uniform vec4 shade : source_color = vec4(0.3, 0.33, 0.5, 1.0);
uniform vec4 inner : source_color = vec4(0.75, 0.85, 1.0, 1.0);

const vec3 SUN = vec3(0.45, 0.1, 0.887);
const float GRID = 21.0;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec3 hash3(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	uint h2 = h * 2654435761u + 12345u;
	h2 ^= h2 >> 15u;
	return vec3(float(h & 65535u), float(h >> 16u), float(h2 & 65535u)) / 65535.0;
}

float hash1(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	return float(h & 16777215u) / 16777215.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The tower of the cell p is in: x how far inside it p is (0 outside .. 1 at its middle), y its part's level.
vec2 tower(vec2 p) {
	vec2 c = floor(p / GRID);
	vec3 h = hash3(c);
	vec2 mid_p = (c + 0.32 + 0.36 * h.xy) * GRID;
	float d = length(p - mid_p) / (5.0 + 2.5 * h.z);
	float k = max(1.0 - d * d, 0.0);
	return vec2(k * k * step(0.3, h.z), band(0.04 + 0.9 * fract(h.x * 7.0 + h.y)));
}

// The height of the cloud tops at p; fine: with the small billows too.
float tops(vec2 p, bool fine, out vec2 tw) {
	float n = vnoise(p * 0.11);
	float n2 = vnoise(p * 0.31 + 7.0);
	float h = 1.7 * n + 0.9 * n2;
	tw = tower(p);
	h += tw.x * (2.0 + 5.5 * towers * (0.8 + 0.2 * tw.y)) * (0.6 + 0.8 * n2);
	if (fine) {
		h += (0.45 + 0.9 * tw.x) * (1.0 - abs(2.0 * vnoise(p * 0.6 + 1.0) - 1.0)) + 0.2 * vnoise(p * 1.7);
	}
	return h;
}

vec3 sky_at(vec3 rd) {
	float up = max(rd.y, 0.0);
	float sd = max(dot(rd, SUN), 0.0);
	vec3 c = mix(sunset.rgb, mix(sunset.rgb, zenith.rgb, 0.6) * vec3(1.05, 0.8, 1.0), smoothstep(0.0, 0.16, up));
	c = mix(c, zenith.rgb, smoothstep(0.08, 0.5, up));
	c = mix(c, zenith.rgb * 0.35, smoothstep(0.4, 1.0, up));
	c += sunset.rgb * (pow(sd, 10.0) * 0.45 + pow(sd, 90.0) * 0.6) + vec3(1.0, 0.95, 0.85) * smoothstep(0.9994, 0.9997, sd) * 2.0;
	vec2 sc = floor(rd.xy / (rd.z + 1.6) * 110.0);
	float sh = hash3(sc).x;
	c += vec3(0.85, 0.9, 1.0) * step(0.985, sh) * (sh - 0.985) * 45.0 * smoothstep(0.3, 0.7, up);
	// A wisp of high cloud, pink underneath.
	vec2 hp = rd.xz / (up + 0.3);
	float wisp = smoothstep(0.55, 0.9, vnoise(hp * vec2(1.2, 5.0) + vec2(drive * 0.004, 0.0)) * 0.65 + vnoise(hp * vec2(3.0, 11.0)) * 0.35);
	c = mix(c, mix(sunset.rgb, vec3(1.0, 0.8, 0.85), 0.5), wisp * 0.35 * smoothstep(0.08, 0.3, up));
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float z0 = drive * speed * 1.2;
	vec3 ro = vec3(3.0 * sin(z0 * 0.02), 13.6 + 0.5 * sin(z0 * 0.05), z0);
	float bank = 0.06 * sin(z0 * 0.03);
	uv = vec2(uv.x * cos(bank) - uv.y * sin(bank), uv.x * sin(bank) + uv.y * cos(bank));
	vec3 rd = normalize(vec3(uv.x + 0.15 * sin(z0 * 0.015), uv.y - 0.2, 1.15));
	vec3 col = sky_at(rd);

	// The airliner and its trail, high and far.
	float line = rd.y - (0.34 + 0.22 * rd.x);
	float plane_x = fract(drive * 0.006) * 2.6 - 1.3;
	float behind = plane_x - rd.x;
	col += vec3(1.0, 0.85, 0.8) * smoothstep(0.004, 0.0, abs(line) - 0.0005 - 0.003 * clamp(behind, 0.0, 1.0)) * step(0.0, behind) * exp(-behind * 2.5) * 0.5 * step(0.0, rd.z);
	col = mix(col, vec3(0.04, 0.04, 0.06), smoothstep(0.004, 0.002, length(vec2((rd.x - plane_x) * 0.4, line))) * step(0.0, rd.z));

	if (rd.y < -0.004) {
		float tt = (ro.y - 12.6) / -rd.y;
		vec2 tw = vec2(0.0);
		bool hit = false;
		float d_was = 1.0;
		float t_was = tt;
		for (int i = 0; i < 28; i++) {
			vec3 p = ro + rd * tt;
			float d = p.y - tops(p.xz, false, tw);
			if (d < 0.0) {
				// Between the last step and this one: where the ray went under.
				tt = mix(t_was, tt, d_was / (d_was - d));
				hit = true;
				break;
			}
			d_was = d;
			t_was = tt;
			tt += max(d * 0.7, 0.25) + 0.022 * tt;
			if (tt > 220.0) {
				break;
			}
		}
		if (hit) {
			vec3 p = ro + rd * tt;
			float e = 0.35 + 0.01 * tt;
			vec2 tmp = vec2(0.0);
			float h0 = tops(p.xz, true, tw);
			vec3 n = normalize(vec3(h0 - tops(p.xz + vec2(e, 0.0), true, tmp), e * 1.4, h0 - tops(p.xz + vec2(0.0, e), true, tmp)));
			// Towards the sun: is a higher top in the way?
			float ahead = tops(p.xz + SUN.xz * 3.5, false, tmp);
			float sun_vis = smoothstep(2.2, -0.6, ahead - (h0 + 3.5 * SUN.y));
			float diff = clamp(dot(n, SUN) * 0.55 + 0.5, 0.0, 1.0) * sun_vis;
			vec3 c = shade.rgb * (0.55 + 0.35 * n.y) + sunset.rgb * diff * 1.25;
			// Deep between the billows it is darker.
			c *= 0.7 + 0.3 * smoothstep(0.5, 3.0, h0);
			c += vec3(1.0, 0.92, 0.85) * 0.18 * smoothstep(3.0, 8.0, h0) * sun_vis;
			// A silver edge against the sun, and the towers' own light.
			float rim = pow(max(dot(rd, SUN), 0.0), 6.0) * pow(1.0 - max(dot(n, -rd), 0.0), 2.0);
			c += vec3(1.0, 0.9, 0.75) * rim * 0.9;
			float flick = 0.6 + 0.4 * vnoise(p.xz * 0.4 + vec2(vis_time * 0.7, 0.0));
			c += inner.rgb * tw.x * tw.y * (0.3 + 0.7 * tw.y) * storm * 1.0 * flick * (1.0 - 0.6 * diff);
			float fogk = 1.0 - exp(-tt * 0.016);
			col = mix(c, sky_at(normalize(vec3(rd.x, 0.015, rd.z))), fogk);
		}
	}

	col *= 1.0 - 0.28 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
