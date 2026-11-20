// Storm sea (visualiser.json): a heavy sea at night from a boat, ray-marched as a height field. The swell is the
// spectrum: four trains of waves, the longest the bass, each as high as its own part; two finer ones (in the surface's
// slope only) with the high notes. Each train pushes the water towards its crests, so they are sharp and the troughs
// round. The water mirrors the sky by the angle it is seen at, glows green where a crest is thin, and carries foam.
// A lighthouse stands on a rock (drawn flat, far off): its lamp turns on the music's clock (drive) and its two beams
// are worked out exactly (the nearest approach of each pixel's ray to the beam's line), so they brighten as they
// swing past, and light the water under them. Storm clouds cross the moon. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float swell = 0.6;
uniform float sweep = 0.5;
uniform float mist = 0.5;
uniform vec4 sea : source_color = vec4(0.04, 0.18, 0.2, 1.0);
uniform vec4 sky : source_color = vec4(0.11, 0.14, 0.22, 1.0);
uniform vec4 moon : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform vec4 lamp : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform vec4 stripe : source_color = vec4(0.72, 0.13, 0.1, 1.0);

const vec3 LH = vec3(24.0, 0.0, 90.0);
const vec3 MOON_DIR = vec3(-0.42, 0.33, 0.845);


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
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

float fbm3(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 1.7) * 0.15;
}

// The sea's height at p: oct trains of waves, amplitudes a (the four big ones) and fine (the rest).
float waves(vec2 p, float t, vec4 a, float fine, int oct) {
	float h = 0.0;
	float f = 0.2;
	vec2 d = vec2(0.6, 0.8);
	for (int i = 0; i < oct; i++) {
		float w = i == 0 ? a.x : (i == 1 ? a.y : (i == 2 ? a.z : (i == 3 ? a.w : fine * (i == 4 ? 1.0 : 0.55))));
		float ph = dot(p, d) * f + t * sqrt(f) * 2.2 + float(i) * 1.7;
		float s = sin(ph);
		float sa = sqrt(s * s + 0.03);
		h += w * (1.0 - 2.0 * sa);
		p += d * cos(ph) * s / sa * w * 0.7;
		d = vec2(d.x * 0.42 - d.y * 0.91, d.x * 0.91 + d.y * 0.42);
		f *= 1.75;
	}
	return h;
}

// The storm sky along rd: clouds crossing the moon.
vec3 sky_at(vec3 rd, float t, float disc) {
	float up = max(rd.y, 0.0);
	vec3 c = mix(sky.rgb * 1.25, sky.rgb * 0.45, smoothstep(0.0, 0.7, up));
	float md = max(dot(rd, MOON_DIR), 0.0);
	vec2 cp = rd.xz / (up + 0.22) * 1.1 + vec2(t * 0.03, t * 0.012);
	float n = fbm3(cp);
	float cov = smoothstep(0.3, 0.62, n);
	vec3 moonlight = moon.rgb * (pow(md, 1500.0) * 5.0 * disc + pow(md, 160.0) * 0.5 * disc + pow(md, 8.0) * 0.12) * (0.8 + 0.3 * level);
	c += moonlight * (1.0 - cov * 0.93);
	// Clouds: dark bellies, silver where they thin near the moon.
	vec3 cloud = sky.rgb * (0.2 + 0.9 * n * n) + moon.rgb * (pow(md, 5.0) * 0.45 * (1.0 - cov) + 0.1 * smoothstep(0.45, 0.2, n)) * (0.6 + 0.6 * mid);
	c = mix(c, cloud, cov * 0.85);
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float t = vis_time * 0.45 + drive * 0.3;
	float A = 0.25 + 1.1 * swell;
	vec4 a = A * vec4(0.5, 0.3, 0.17, 0.1) * (0.7 + 0.5 * vec4(band(0.05), band(0.22), band(0.42), band(0.62)));
	float fine = A * 0.05 * (0.5 + 1.0 * treble);
	float top = A * 1.4;

	// The boat: riding the swell, rolling a little.
	vec3 ro = vec3(0.0, top + 0.9 + 0.3 * sin(t * 0.7), 0.0);
	float roll = 0.035 * sin(t * 0.43);
	uv = vec2(uv.x * cos(roll) - uv.y * sin(roll), uv.x * sin(roll) + uv.y * cos(roll));
	vec3 rd = normalize(vec3(uv.x + 0.12, uv.y + 0.07 + 0.025 * sin(t * 0.5), 1.25));

	vec3 col = sky_at(rd, t, 1.0);
	float hit = 1e9;
	vec3 lp = LH + vec3(0.0, 20.6, 0.0);
	float phi = drive * sweep * 0.6;

	if (rd.y < -0.002) {
		float tt = (ro.y - top) / -rd.y;
		float far_t = ro.y / -rd.y * 1.6 + 400.0;
		for (int i = 0; i < 44; i++) {
			vec3 pos = ro + rd * tt;
			float d = pos.y - waves(pos.xz, t, a, fine, 4);
			if (d < 0.003 * tt || tt > far_t) {
				break;
			}
			tt += d * 0.6 + 0.002 * tt;
		}
		hit = tt;
		vec3 pos = ro + rd * tt;
		float e = 0.03 + 0.004 * tt;
		float h0 = waves(pos.xz, t, a, fine, 6);
		vec3 n = normalize(vec3(h0 - waves(pos.xz + vec2(e, 0.0), t, a, fine, 6), e, h0 - waves(pos.xz + vec2(0.0, e), t, a, fine, 6)));
		n = normalize(mix(n, vec3(0.0, 1.0, 0.0), smoothstep(40.0, 320.0, tt) * 0.85));
		float fres = 0.03 + 0.97 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
		vec3 refl = reflect(rd, n);
		refl.y = abs(refl.y);
		vec3 wc = sea.rgb * (0.25 + 0.35 * clamp(h0 / top * 0.5 + 0.5, 0.0, 1.0));
		// Thin crests let the light through.
		wc += sea.rgb * vec3(0.6, 1.5, 1.2) * smoothstep(0.35, 1.0, h0 / top) * 0.5;
		wc = mix(wc, sky_at(refl, t, 0.25), fres);
		wc += moon.rgb * pow(max(dot(refl, MOON_DIR), 0.0), 60.0) * 0.3;
		// Foam: on the crests, and in streaks left behind them.
		float fn = vnoise(pos.xz * 1.6 + vec2(t * 0.3, 0.0)) * 0.6 + vnoise(pos.xz * 5.0 - vec2(0.0, t * 0.4)) * 0.4;
		float foam = smoothstep(0.45, 0.95, h0 / top + 0.35 * (fn - 0.5)) * smoothstep(0.3, 0.7, fn);
		foam += smoothstep(0.72, 0.9, fn) * 0.25 * smoothstep(-0.6, 0.3, h0 / top);
		foam *= smoothstep(260.0, 60.0, tt);
		vec3 foam_c = (moon.rgb * 0.5 + sky.rgb * 0.6) * (0.7 + 0.3 * treble);
		wc = mix(wc, foam_c, clamp(foam, 0.0, 0.85));
		// The beams on the water: brightest along each beam's line from the lamp.
		vec2 from_l = pos.xz - lp.xz;
		float az = atan(from_l.y, from_l.x);
		float bl = pow(abs(cos(az - phi)), 90.0) / (1.0 + length(from_l) * 0.03);
		wc += lamp.rgb * bl * (0.25 + 0.5 * foam + 0.3 * fres);
		float fog = 1.0 - exp(-tt * 0.0035 * (0.4 + 1.6 * mist));
		col = mix(wc, sky_at(normalize(vec3(rd.x, 0.02, rd.z)), t, 0.0) * 0.9, fog);
	}

	// The lighthouse on its rock, a flat cut-out far off.
	float tb = (LH.z - ro.z) / rd.z;
	if (tb < hit) {
		vec3 pb = ro + rd * tb;
		float lx = pb.x - LH.x;
		float ly = pb.y;
		float px_m = tb / (size.y * 1.25);
		float rock = 3.6 * exp(-lx * lx / 60.0) + 1.2 * vnoise(vec2(lx * 0.8, 3.0)) + 0.5 * vnoise(vec2(lx * 3.0, 7.0)) - 0.6;
		vec3 lc = col;
		float la = 0.0;
		if (ly < rock) {
			lc = sky.rgb * 0.25 * (0.6 + 0.6 * vnoise(vec2(lx * 2.0, ly * 2.0)));
			lc += (moon.rgb * 0.4 + sky.rgb * 0.4) * smoothstep(1.2, 0.0, ly + 0.5 * sin(t * 1.3 + lx)) * (0.5 + 0.5 * vnoise(vec2(lx * 2.0 + t, ly * 3.0)));
			la = smoothstep(0.0, px_m * 1.5, rock - ly);
		}
		float ty = (ly - 3.0) / 16.0;
		if (ty > -0.1 && ly < 23.5) {
			float w = mix(1.55, 1.0, clamp(ty, 0.0, 1.0));
			vec3 tc = mod(floor(ty * 5.0), 2.0) < 1.0 ? stripe.rgb : vec3(0.85, 0.84, 0.8);
			float shade = 0.25 + 0.45 * smoothstep(1.0, -1.0, lx / w) + 0.15 * (0.5 + 0.5 * level);
			float body = abs(lx) - w;
			if (ty > 1.0) {
				// The gallery, the lantern room with the lamp in it, the dome.
				float gy = ly - 19.0;
				if (gy < 0.5) {
					body = abs(lx) - 1.5;
					tc = vec3(0.12);
				} else if (gy < 2.8) {
					body = abs(lx) - 0.85;
					float facing = abs(cos(phi - atan(ro.z - lp.z, ro.x - lp.x)));
					tc = lamp.rgb * (1.2 + 2.0 * pow(facing, 30.0));
					tc *= 0.6 + 0.4 * step(0.12, abs(fract(lx / 0.57 + 0.5) - 0.5));
					shade = 1.0;
				} else {
					body = length(vec2(lx, gy - 2.8)) - 1.0;
					tc = vec3(0.1);
				}
			}
			float ta = smoothstep(px_m, -px_m, body) * step(-0.1, ty);
			lc = mix(lc, tc * shade, ta);
			la = max(la, ta);
		}
		col = mix(col, mix(lc, sky.rgb * 0.9, (1.0 - exp(-tb * 0.0035 * (0.4 + 1.6 * mist))) * 0.7), la);
	}

	// The two beams through the mist: the ray's nearest approach to each beam's line.
	vec3 w0 = ro - lp;
	float haze = 0.35 + 0.65 * mist;
	for (int k = 0; k < 2; k++) {
		float ang = phi + float(k) * PI;
		vec3 bd = normalize(vec3(cos(ang), -0.03, sin(ang)));
		float b = dot(rd, bd);
		float d0 = dot(rd, w0);
		float e0 = dot(bd, w0);
		float den = max(1.0 - b * b, 0.0005);
		float s = (b * e0 - d0) / den;
		float u = (e0 - b * d0) / den;
		if (u > 0.0 && s > 0.0 && s < hit) {
			float dist = length(w0 + rd * s - bd * u);
			float wd = 0.5 + 0.04 * u;
			float g = exp(-dist * dist / (wd * wd)) / (1.0 + 0.012 * u);
			g *= min(1.0 / sqrt(den), 5.0) * 0.16;
			g *= 0.8 + 0.4 * vnoise(vec2(u * 0.08 - t * 0.3, float(k) * 9.0));
			col += lamp.rgb * g * haze;
		}
	}
	// The lamp's own glare when a beam looks at us.
	vec3 to_l = normalize(lp - ro);
	float ang_l = length(cross(rd, to_l));
	float facing = pow(abs(cos(phi - atan(ro.z - lp.z, ro.x - lp.x))), 40.0);
	if (tb < hit || rd.y > -0.002) {
		col += lamp.rgb * (exp(-ang_l * 300.0) * 0.8 + exp(-ang_l * 45.0) * 0.5 * facing * haze + exp(-ang_l * 9.0) * 0.12 * facing * haze);
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
