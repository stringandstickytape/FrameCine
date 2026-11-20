// Event horizon (visualiser.json): a black hole and its disc of glowing gas, with the light bent as it truly is.
// Each pixel's ray is a photon stepped through the hole's gravity (the pull that gives the right bending for light:
// -1.5 h^2 r / |r|^5, h the ray's angular momentum, the horizon at radius 1). So the far side of the disc shows
// lifted over the top of the hole and tucked under it, a thin ring of light hugs the shadow, and the stars behind
// are smeared round it. Where a step crosses the disc's plane the crossing is found between the two ends.
// The disc is the spectrum from the inside (low notes) to the rim (high): each ring glows with its part. Its gas
// turns faster the nearer the hole (rings of streaks, each turning whole so nothing winds up), and the side coming
// towards the eye is brighter and the side going away dimmer, as it is. Two jets leave the poles with the bass.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float tilt = 0.4;
uniform float spin = 0.5;
uniform float jets = 0.6;
uniform vec4 hot : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform vec4 cool : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform vec4 jet : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform vec4 space : source_color = vec4(0.05, 0.04, 0.1, 1.0);

const float R_IN = 2.6;
const float R_OUT = 9.0;

vec3 hash3v(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash3v(i).x;
	float b = hash3v(i + vec2(1.0, 0.0)).x;
	float c = hash3v(i + vec2(0.0, 1.0)).x;
	float d = hash3v(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The sky in direction d: dust, a band of far stars, and two sizes of star.
vec3 sky_at(vec3 d) {
	float n = vnoise(d.xy * 5.0 + d.z * 3.1) * vnoise(d.zy * 7.0 - d.x * 2.3);
	vec3 c = space.rgb * (0.3 + 1.0 * n);
	float lane = d.y * 0.8 + d.x * 0.5 + 0.1;
	c += space.rgb * 1.3 * exp(-lane * lane * 9.0) * (0.4 + 0.8 * vnoise(d.xz * 40.0 + d.y * 17.0));
	vec2 sp = vec2(atan(d.z, d.x) / TAU + 0.5, asin(clamp(d.y, -1.0, 1.0)) / PI + 0.5);
	for (int i = 0; i < 2; i++) {
		vec2 g = sp * (i == 0 ? vec2(180.0, 90.0) : vec2(64.0, 32.0));
		vec3 h = hash3v(floor(g) + float(i) * 37.0);
		vec2 f = fract(g) - 0.2 - 0.6 * h.xy;
		float rr = i == 0 ? 0.1 : 0.14;
		vec3 tint = mix(vec3(1.0, 0.8, 0.6), vec3(0.7, 0.85, 1.0), h.y);
		c += tint * smoothstep(rr, 0.0, length(f)) * step(i == 0 ? 0.55 : 0.8, h.z) * (0.5 + 0.7 * h.x);
	}
	return c;
}

// One ring of streaks, turning whole: 0..1 round the angle.
float streak(float k, float ang) {
	vec3 h = hash3v(vec2(k, 7.0));
	float rr = max(k, 1.0) / 2.5;
	float a = ang - drive * spin * 0.55 / (rr * sqrt(rr)) + h.x * TAU;
	return 0.5 + 0.5 * sin(a * (2.0 + floor(h.y * 3.0))) * sin(a * (5.0 + floor(h.z * 6.0)) + h.y * 9.0);
}

// The disc where a ray crosses it at hp (radius r), the ray going vdir: its light and how much it hides.
vec4 disc_at(vec3 hp, float r, vec3 vdir) {
	float u = (r - R_IN) / (R_OUT - R_IN);
	float b = band(0.03 + 0.9 * u);
	float ang = atan(hp.z, hp.x);
	float rk = r * 2.5;
	float k0 = floor(rk);
	float s = mix(streak(k0, ang), streak(k0 + 1.0, ang), smoothstep(0.0, 1.0, fract(rk)));
	float lane = 0.78 + 0.22 * sin(r * 9.0 + 3.0 * sin(r * 1.7));
	float edge = smoothstep(0.0, 0.06, u) * smoothstep(1.0, 0.5, u);
	float temp = (1.0 - u) * (1.0 - u);
	vec3 c = mix(cool.rgb, hot.rgb, temp) * (0.3 + 1.5 * temp);
	c *= (0.5 + 0.8 * b) * (0.35 + 0.65 * s) * lane;
	vec3 tang = normalize(vec3(-hp.z, 0.0, hp.x));
	float dop = clamp(1.0 - 0.55 * dot(tang, vdir), 0.35, 1.6);
	c *= dop * dop * dop * 0.7;
	return vec4(c, edge * (0.55 + 0.4 * s));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float orbit = drive * 0.011;
	float elev = 0.05 + 0.3 * tilt + 0.04 * sin(drive * 0.021);
	vec3 ro = 17.0 * vec3(sin(orbit) * cos(elev), sin(elev), -cos(orbit) * cos(elev));
	vec3 fw = normalize(-ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	float roll = 0.18;
	vec2 pr = vec2(cos(roll) * p.x - sin(roll) * p.y, sin(roll) * p.x + cos(roll) * p.y);
	vec3 rd = normalize(fw * 1.45 + rt * pr.x + up * pr.y);

	vec3 pos = ro;
	vec3 vel = rd;
	vec3 hv = cross(pos, vel);
	float h2 = dot(hv, hv);
	vec3 col = vec3(0.0);
	float trans = 1.0;
	bool fell = false;
	float jet_k = jets * (0.12 + 0.9 * bass);
	for (int i = 0; i < 72; i++) {
		float r2 = dot(pos, pos);
		if (r2 < 1.0) {
			fell = true;
			break;
		}
		if (r2 > 420.0 && dot(pos, vel) > 0.0) {
			break;
		}
		float r1 = sqrt(r2);
		float dt = clamp(0.12 * r1, 0.05, 1.2);
		vel += -1.5 * h2 * pos / (r2 * r2 * r1) * dt;
		vec3 np = pos + vel * dt;
		if (pos.y * np.y < 0.0) {
			vec3 hp = mix(pos, np, pos.y / (pos.y - np.y));
			float r = length(hp.xz);
			if (r > R_IN && r < R_OUT) {
				vec4 d = disc_at(hp, r, normalize(vel));
				col += trans * d.rgb * d.a;
				trans *= 1.0 - d.a;
			}
		}
		// The jets: a narrow cone of glow up and down the axis, in knots that travel outwards.
		float ay = abs(np.y);
		float w = 0.3 + 0.1 * ay;
		float ax = dot(np.xz, np.xz);
		float dens = exp(-ax / (w * w)) * exp(-ay * 0.13) * smoothstep(1.0, 2.6, ay) * (0.65 + 0.35 * sin(ay * 1.4 - drive * 0.7));
		col += trans * jet.rgb * dens * dt * jet_k * 0.5;
		pos = np;
	}
	if (!fell) {
		col += trans * sky_at(normalize(vel)) * 0.7;
		// The glare of the disc in the eye.
		col += trans * hot.rgb * cool.rgb * 0.006 / (dot(p, p) + 0.05) * (0.5 + 0.5 * level);
	}
	col = 1.0 - exp(-col * 1.5);
	COLOR = vec4(col, 1.0);
}
