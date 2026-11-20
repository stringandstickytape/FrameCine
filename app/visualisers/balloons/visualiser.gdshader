// Balloons (visualiser.json): hot-air balloons over a valley at dawn, ray-marched. Eight balloons, each a part of
// the spectrum: it climbs with its part and its burner roars (the mouth glows, the cloth above it lights from inside).
// Each envelope is a teardrop found by a short march inside its bounding sphere, patterned by its gores and bands
// (stripes, zigzags, rings, each balloon its own), sunlight coming through the cloth on the far side; a basket hangs
// below. The land is a height field: a patchwork of fields with hedges, woods on the slopes, a river that mirrors
// the sky, mist lying in the hollows (thicker with the bass), the balloons' shadows on the ground. Far mountains with
// snow, thin cloud, the sun low ahead. The camera drifts along the valley on the music's clock (drive). `night` turns
// it to a night glow: dark land, stars, the balloons as lanterns. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float lift = 0.6;
uniform float mist = 0.5;
uniform float night = 0.0;
uniform vec4 sky : source_color = vec4(0.45, 0.65, 0.92, 1.0);
uniform vec4 dawn : source_color = vec4(1.0, 0.72, 0.45, 1.0);
uniform vec4 fields : source_color = vec4(0.42, 0.58, 0.24, 1.0);
uniform vec4 cloth_a : source_color = vec4(0.9, 0.2, 0.15, 1.0);
uniform vec4 cloth_b : source_color = vec4(1.0, 0.82, 0.2, 1.0);

const int BALLOONS = 8;
const float R = 1.7;
const vec3 SUN = vec3(0.37, 0.24, 0.9);


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

// The land's height: a valley running away from us between rolling hills.
float land(vec2 p) {
	float v = p.x * 0.045 + 0.5 * sin(p.y * 0.035);
	return 5.0 * (1.0 - exp(-v * v)) + 1.3 * sin(p.x * 0.13 + 1.0) * sin(p.y * 0.11) + 0.5 * sin(p.x * 0.31 + p.y * 0.23) - 1.2;
}

// Balloon i's envelope centre: its place in the flight, its height with its part of the spectrum.
vec3 balloon(int i, float z0) {
	float fi = float(i);
	float b = band(0.04 + fi / float(BALLOONS - 1) * 0.86);
	float x = (fract(fi * 0.618 + 0.2) - 0.5) * 30.0 + 1.5 * sin(drive * 0.05 + fi * 2.0);
	float z = z0 + 9.0 + fract(fi * 0.382 + 0.1) * 46.0 + 2.0 * sin(drive * 0.04 + fi);
	float y = 5.0 + 5.0 * fract(fi * 0.77 + 0.3) + lift * 5.0 * b + 0.3 * sin(vis_time * 0.5 + fi * 1.7);
	return vec3(x, y, z);
}

// The envelope and basket round the origin (the envelope's centre): a sphere drawn down into a cone to the mouth.
float balloon_sd(vec3 q) {
	float sph = length(q) - R;
	float t = clamp(-q.y / (R * 1.75), 0.0, 1.0);
	float cone = length(vec3(q.x, q.y + t * R * 1.75, q.z)) - mix(R * 0.86, R * 0.2, t);
	float h = clamp(0.5 + 0.5 * (cone - sph) / 0.5, 0.0, 1.0);
	float env = mix(cone, sph, h) - 0.5 * h * (1.0 - h);
	vec3 bq = abs(q + vec3(0.0, R * 2.25, 0.0)) - vec3(0.28, 0.22, 0.28);
	float basket = length(max(bq, 0.0)) + min(max(bq.x, max(bq.y, bq.z)), 0.0) - 0.04;
	return min(env, basket);
}

// The sky along rd: day or night, the sun, thin cloud, far mountains.
vec3 sky_at(vec3 rd) {
	float up = max(rd.y, 0.0);
	vec3 day = mix(mix(dawn.rgb, sky.rgb, smoothstep(0.0, 0.3, up)), sky.rgb * 0.75, smoothstep(0.2, 0.9, up));
	float sd = max(dot(rd, SUN), 0.0);
	day += dawn.rgb * (pow(sd, 6.0) * 0.35 + pow(sd, 60.0) * 0.5) + vec3(1.0, 0.95, 0.85) * pow(sd, 1500.0) * 3.0;
	vec3 dark = mix(sky.rgb * 0.16, sky.rgb * 0.04, smoothstep(0.0, 0.6, up)) + dawn.rgb * 0.08 * pow(1.0 - up, 6.0);
	vec2 sc = floor(rd.xy / (rd.z + 1.2) * 90.0);
	float sh = hash1(sc);
	dark += vec3(0.8, 0.85, 1.0) * step(0.985, sh) * (sh - 0.985) * 40.0 * smoothstep(0.05, 0.3, up);
	vec3 c = mix(day, dark, night);
	float cl = vnoise(rd.xz / (up + 0.25) * 2.0 + vec2(drive * 0.004, 0.0)) * 0.6 + vnoise(rd.xz / (up + 0.25) * 5.0) * 0.4;
	c = mix(c, mix(vec3(1.0, 0.9, 0.82), sky.rgb * 0.2, night), smoothstep(0.55, 0.85, cl) * 0.45 * smoothstep(0.02, 0.2, up));
	// Mountains along the horizon, snow on the tops.
	float az = atan(rd.x, rd.z);
	float ridge = 0.03 + 0.08 * vnoise(vec2(az * 6.0, 1.0)) + 0.035 * vnoise(vec2(az * 19.0, 5.0)) + 0.012 * vnoise(vec2(az * 60.0, 2.0));
	if (rd.y < ridge) {
		vec3 mc = mix(sky.rgb * 0.7, dawn.rgb * 0.75, 0.3) * (0.85 + 0.15 * vnoise(vec2(az * 60.0, rd.y * 200.0))) * (0.75 + 2.5 * max(rd.y, 0.0));
		mc = mix(mc, vec3(0.95, 0.93, 0.95), smoothstep(0.085, 0.11, rd.y + 0.02 * vnoise(vec2(az * 30.0, 9.0))));
		c = mix(c, mix(mc, mc * 0.12, night), smoothstep(ridge, ridge - 0.004, rd.y) * 0.9);
	}
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float z0 = drive * 0.5;
	vec3 ro = vec3(1.5 * sin(drive * 0.03), 7.5 + 0.4 * sin(drive * 0.05), z0);
	vec3 rd = normalize(vec3(uv.x + 0.04 * sin(drive * 0.02), uv.y - 0.03, 1.2));
	vec3 col = sky_at(rd);
	float depth = 1e9;
	float daylight = 1.0 - night;

	// The balloons' places, once.
	vec3 pos_b[8];
	for (int i = 0; i < BALLOONS; i++) {
		pos_b[i] = balloon(i, z0);
	}

	// The land.
	if (rd.y < 0.1) {
		float tt = 0.5;
		bool ground = false;
		for (int i = 0; i < 56; i++) {
			vec3 p = ro + rd * tt;
			float d = p.y - land(p.xz);
			if (d < 0.004 * tt) {
				ground = true;
				break;
			}
			tt += d * 0.55 + 0.01 * tt;
			if (tt > 260.0) {
				break;
			}
		}
		if (ground) {
			depth = tt;
			vec3 p = ro + rd * tt;
			float e = 0.05 + 0.004 * tt;
			float h0 = land(p.xz);
			vec3 n = normalize(vec3(h0 - land(p.xz + vec2(e, 0.0)), e, h0 - land(p.xz + vec2(0.0, e))));
			// Fields: a patchwork of plots, each its own crop, hedges between; woods where it is steep or high.
			vec2 fq = p.xz * 0.3 + 0.6 * vec2(vnoise(p.xz * 0.07), vnoise(p.xz * 0.07 + 5.0));
			vec2 fc = floor(fq);
			vec2 ff = fract(fq);
			float crop = hash1(fc);
			vec3 gc = fields.rgb * mix(vec3(0.75, 0.95, 0.6), vec3(1.5, 1.25, 0.55), crop);
			gc *= 0.85 + 0.15 * sin((ff.x * (crop > 0.5 ? 1.0 : 0.0) + ff.y * (crop > 0.5 ? 0.0 : 1.0)) * 40.0) * smoothstep(120.0, 20.0, tt);
			float hedge = min(min(ff.x, 1.0 - ff.x), min(ff.y, 1.0 - ff.y));
			gc = mix(fields.rgb * 0.3, gc, smoothstep(0.02, 0.06, hedge));
			float wood = smoothstep(0.75, 0.9, 1.0 - n.y + 0.25 * vnoise(p.xz * 0.3)) + smoothstep(2.2, 3.4, h0 + vnoise(p.xz * 0.2));
			gc = mix(gc, fields.rgb * 0.32 * (0.7 + 0.6 * vnoise(p.xz * 2.5)), clamp(wood, 0.0, 1.0));
			// The river along the valley floor, mirroring the sky.
			float river = smoothstep(-1.0, -1.04, h0 + 0.05 * vnoise(p.xz * 0.5));
			vec3 rr = reflect(rd, normalize(vec3(0.03 * sin(p.z * 3.0 + vis_time), 1.0, 0.03 * sin(p.x * 3.0))));
			gc = mix(gc, sky_at(vec3(rr.x, abs(rr.y), rr.z)) * 0.85, river);
			// Sun and the balloons' shadows.
			float sun_l = clamp(dot(n, SUN), 0.0, 1.0);
			float shadow = 1.0;
			for (int i = 0; i < BALLOONS; i++) {
				vec3 oc = p - pos_b[i];
				float bq = dot(oc, SUN);
				float c2 = dot(oc, oc) - bq * bq;
				shadow *= 1.0 - 0.6 * smoothstep(R * R * 1.3, R * R * 0.5, c2) * step(bq, 0.0);
			}
			vec3 lit = dawn.rgb * sun_l * 1.5 * shadow + sky.rgb * 0.45 * (0.6 + 0.4 * n.y);
			vec3 night_lit = sky.rgb * 0.07 * (0.6 + 0.4 * n.y);
			// At night the burners light the land below each balloon.
			for (int i = 0; i < BALLOONS; i++) {
				vec3 to_b = pos_b[i] - vec3(0.0, R * 1.7, 0.0) - p;
				float bb = band(0.04 + float(i) / float(BALLOONS - 1) * 0.86);
				night_lit += dawn.rgb * 6.0 * (0.25 + bb) / (dot(to_b, to_b) + 4.0) * max(dot(n, normalize(to_b)), 0.0);
			}
			gc *= mix(lit, night_lit, night);
			// Mist in the hollows and haze with distance.
			float low = smoothstep(1.2, -1.0, h0) * (0.3 + 0.8 * mist) * (0.75 + 0.35 * bass);
			float fog = 1.0 - exp(-tt * (0.004 + 0.012 * low));
			vec3 fog_c = mix(mix(dawn.rgb, sky.rgb, 0.45) * 1.05, sky.rgb * 0.1, night);
			col = mix(gc, fog_c, clamp(fog, 0.0, 1.0));
		}
	}

	// The balloons, nearest first where they overlap.
	for (int i = 0; i < BALLOONS; i++) {
		vec3 c = pos_b[i];
		vec3 oc = ro - c + vec3(0.0, R * 0.55, 0.0);
		float bound = R * 1.95;
		float bq = dot(oc, rd);
		float disc = bq * bq - dot(oc, oc) + bound * bound;
		if (disc < 0.0) {
			continue;
		}
		float tt = max(-bq - sqrt(disc), 0.0);
		float t_end = -bq + sqrt(disc);
		if (tt > depth) {
			continue;
		}
		bool hit = false;
		for (int k = 0; k < 20; k++) {
			float d = balloon_sd(ro + rd * tt - c);
			if (d < 0.002 * tt) {
				hit = true;
				break;
			}
			tt += d;
			if (tt > t_end) {
				break;
			}
		}
		if (!hit || tt > depth) {
			continue;
		}
		depth = tt;
		vec3 q = ro + rd * tt - c;
		float fi = float(i);
		float b = band(0.04 + fi / float(BALLOONS - 1) * 0.86);
		float e = 0.01;
		vec3 n = normalize(vec3(balloon_sd(q + vec3(e, 0.0, 0.0)), balloon_sd(q + vec3(0.0, e, 0.0)), balloon_sd(q + vec3(0.0, 0.0, e))) - balloon_sd(q));
		vec3 bc;
		float glow_in = 0.0;
		if (q.y < -R * 1.9) {
			bc = vec3(0.3, 0.2, 0.1) * (0.7 + 0.3 * sin(q.y * 60.0) * sin(atan(q.z, q.x) * 12.0));
		} else {
			// The cloth: gores round it, bands down it; each balloon its own two colours and pattern.
			float lon = atan(q.z, q.x) / TAU + 0.5;
			float lat = clamp(q.y / R * 0.5 + 0.5, -0.5, 1.0);
			vec3 ca = mix(cloth_a.rgb, 0.5 + 0.5 * cos(TAU * (fi * 0.37 + vec3(0.0, 0.33, 0.67))), 0.55);
			vec3 cb = mix(cloth_b.rgb, 0.5 + 0.5 * cos(TAU * (fi * 0.37 + 0.45 + vec3(0.0, 0.33, 0.67))), 0.4);
			int style = i % 4;
			float pat;
			if (style == 0) {
				pat = step(0.5, fract(lon * 8.0));
			} else if (style == 1) {
				pat = step(0.5, fract(lat * 4.0 + abs(fract(lon * 12.0) - 0.5) * 1.2));
			} else if (style == 2) {
				pat = step(0.5, fract(lon * 6.0 + lat * 1.5));
			} else {
				pat = step(0.5, fract(lat * 3.5)) * step(0.25, fract(lon * 16.0));
			}
			bc = mix(ca, cb, pat);
			bc *= 0.88 + 0.12 * smoothstep(0.0, 0.08, abs(fract(lon * 16.0) - 0.5));
			bc = mix(bc, vec3(0.9), step(lat, -0.26) * 0.6);
			// The burner lights the cloth from inside, most near the mouth.
			glow_in = (0.15 + 1.1 * b * b) * smoothstep(1.0, -0.6, lat);
		}
		float diff = clamp(dot(n, SUN), 0.0, 1.0);
		float through = clamp(dot(n, -SUN) * 0.5 + 0.3, 0.0, 1.0) * step(-R * 1.9, q.y);
		vec3 day_c = bc * (dawn.rgb * diff * 1.3 + sky.rgb * 0.5 * (0.6 + 0.4 * n.y) + dawn.rgb * through * 0.75);
		day_c += bc * dawn.rgb * glow_in * 0.35;
		vec3 night_c = bc * (sky.rgb * 0.06 + dawn.rgb * glow_in * 1.5);
		vec3 oc_c = mix(day_c, night_c, night);
		float haze_b = 1.0 - exp(-tt * 0.004);
		col = mix(oc_c, mix(mix(dawn.rgb, sky.rgb, 0.45), sky.rgb * 0.1, night), haze_b);
	}
	// The burners' flames: a glow at each mouth.
	for (int i = 0; i < BALLOONS; i++) {
		vec3 fp = pos_b[i] - vec3(0.0, R * 1.85, 0.0);
		vec3 oc = fp - ro;
		float along = dot(oc, rd);
		if (along > 0.0 && along < depth + 1.0) {
			float d = length(oc - rd * along);
			float b = band(0.04 + float(i) / float(BALLOONS - 1) * 0.86);
			col += vec3(1.0, 0.7, 0.3) * exp(-d * d * 14.0) * (0.15 + 1.3 * b * b) * (0.5 + 0.5 * night + 0.2 * daylight);
		}
	}

	col *= 1.0 - 0.25 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
