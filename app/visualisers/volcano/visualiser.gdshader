// Volcano (visualiser.json): a lava field at night under an erupting cone. A river of lava runs from the foot of the
// cone towards us, its crust broken into plates that drift with the flow (on the music's clock, drive) over glowing
// cracks. The river is the spectrum along its length (the bass where it reaches us, the high notes far up): each
// stretch's cracks widen and blaze with its part. The rubble on either side is lit by it. At the summit a fountain
// throws glowing bombs that cool as they fall, higher when it is loud; the crater glows with the bass and lights the
// plume of ash from below; two streams run down the cone with the level. Embers rise with the high notes; the air
// shimmers over the heat. Stars where the plume does not hide them. The ground is a plane in perspective: each pixel
// below the horizon is worked out back into the field. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float flow = 0.5;
uniform float heat = 0.6;
uniform float eruption = 0.6;
uniform vec4 lava : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform vec4 crust : source_color = vec4(0.1, 0.08, 0.075, 1.0);
uniform vec4 sky : source_color = vec4(0.05, 0.06, 0.13, 1.0);
uniform vec4 ash : source_color = vec4(0.35, 0.29, 0.27, 1.0);

const float HORIZON = 0.4;
const float CAM = 0.06;
const int BOMBS = 40;


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

vec2 hash2(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	return vec2(float(h & 65535u), float(h >> 16u)) / 65535.0;
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

// Lava's colour at temperature T (0 cold .. 1 white hot).
vec3 glow_ramp(float T) {
	vec3 deep = lava.rgb * vec3(0.55, 0.18, 0.12);
	vec3 c = mix(vec3(0.0), deep, smoothstep(0.0, 0.35, T));
	c = mix(c, lava.rgb, smoothstep(0.3, 0.72, T));
	return mix(c, mix(lava.rgb, vec3(1.0, 0.95, 0.75), 0.75), smoothstep(0.75, 1.0, T));
}

// The river's middle (world x) and half width at distance Z.
float river_x(float Z) {
	return -0.12 + 0.2 * Z + 0.08 * sin(Z * 1.6);
}

float river_w(float Z) {
	return 0.07 + 0.018 * sin(Z * 2.3 + 1.0) + 0.025 * (vnoise(vec2(Z * 5.0, 3.0)) - 0.5);
}

// Crust plates: the distance to the nearest crack (between the two nearest cells) and the plate's own number.
vec2 plates(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	vec2 m1 = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = g + 0.15 + 0.7 * hash2(i + g) - f;
			float d = dot(o, o);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash1(i + g + vec2(5.0, 1.0));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), id);
}

// The cone's skyline at x.
float cone_y(float x, float vx) {
	float u = abs(x - vx) / 0.66;
	float y = HORIZON + 0.33 * pow(1.0 - min(max(u, 0.035), 1.0), 1.7);
	y -= 0.008 * smoothstep(0.035, 0.0, u);
	return y + 0.006 * (vnoise(vec2(x * 30.0, 2.0)) - 0.5) * smoothstep(1.0, 0.2, u);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float cx = aspect * 0.5;
	float vx = aspect * 0.62;
	float peak = cone_y(vx, vx);
	float hot = heat * (0.75 + 0.5 * bass);
	vec3 col;

	// The air shimmers over the heat: the far scene is seen through it.
	vec2 pb = p;
	float shim = smoothstep(HORIZON + 0.35, HORIZON, p.y) * smoothstep(HORIZON - 0.08, HORIZON, p.y);
	pb.x += (vnoise(p * vec2(45.0, 22.0) + vec2(0.0, -vis_time * 1.2)) - 0.5) * 0.0025 * shim * heat;

	if (p.y >= HORIZON - 0.002 || pb.y > cone_y(pb.x, vx) - 0.002) {
		// The sky: night, glowing low over the eruption; stars.
		col = mix(sky.rgb * 1.5 + lava.rgb * 0.1 * hot, sky.rgb * 0.6, smoothstep(HORIZON, 1.0, pb.y));
		col += lava.rgb * 0.12 * hot * exp(-length((pb - vec2(vx, peak)) * vec2(0.7, 1.2)) * 3.0);
		vec2 sc = floor(pb * 70.0);
		float sh = hash1(sc + vec2(11.0, 4.0));
		if (sh > 0.968 && pb.y > HORIZON + 0.1) {
			vec2 sp = (sc + 0.25 + 0.5 * hash2(sc)) / 70.0;
			col += vec3(0.8, 0.85, 1.0) * smoothstep(1.4 * px, 0.2 * px, length(pb - sp)) * (sh - 0.968) * 20.0;
		}
		// The cone.
		float cy = cone_y(pb.x, vx);
		if (pb.y < cy) {
			float below = cy - pb.y;
			// Ridges and gullies radiating down from the summit, lit from below by the field.
			vec2 rq = pb - vec2(vx, peak);
			float ang = atan(rq.x, -rq.y);
			float ridge = vnoise(vec2(ang * 26.0, length(rq) * 6.0)) * 0.6 + vnoise(vec2(ang * 70.0, length(rq) * 18.0)) * 0.4;
			vec3 cc = crust.rgb * (0.3 + 0.6 * ridge);
			cc += lava.rgb * 0.1 * hot * smoothstep(HORIZON + 0.14, HORIZON, pb.y) * ridge;
			cc += lava.rgb * 0.5 * hot * exp(-length((pb - vec2(vx, peak)) * vec2(1.0, 1.4)) * 14.0);
			// Two streams down its flanks, pulses running down them.
			for (int i = 0; i < 2; i++) {
				float side = i == 0 ? -1.0 : 1.0;
				float down = peak - pb.y;
				float sx = vx + side * (0.015 + 0.55 * pow(max(down, 0.0), 1.25)) + 0.012 * sin(down * 38.0 + float(i) * 2.0);
				float w = 0.0018 + 0.01 * down;
				float sd = abs(pb.x - sx) - w;
				float pulse_ = 0.6 + 0.4 * sin(down * 50.0 - vis_time * 1.8 + float(i) * 3.0);
				float T = smoothstep(px * 1.5, -px, sd) * (0.55 + 0.45 * level) * pulse_ * smoothstep(0.3, 0.0, down) * step(0.0, down);
				cc = mix(cc, glow_ramp(0.5 + 0.45 * T), T);
				cc += lava.rgb * 0.25 * exp(-max(sd, 0.0) * 120.0) * smoothstep(0.3, 0.0, down) * step(0.0, down) * (0.5 + 0.5 * level);
			}
			col = mix(col, cc, smoothstep(0.0, 1.5 * px, below));
		}
		// The crater's glow.
		col += glow_ramp(0.7) * 0.5 * hot * exp(-length((pb - vec2(vx, peak + 0.004)) * vec2(1.0, 2.2)) * 55.0);

		// The plume: ash rising and drifting right, lit orange from below.
		float hgt = pb.y - peak;
		if (hgt > -0.01) {
			float xp = vx + 0.12 * hgt + 0.45 * hgt * hgt;
			float wp = 0.03 + 0.5 * hgt;
			float u = (pb.x - xp) / wp;
			if (abs(u) < 1.3) {
				float n = fbm3(vec2(u * 1.6 + hgt * 2.0, hgt * 5.0 - vis_time * 0.18));
				float d0 = smoothstep(1.2, 0.2, abs(u)) * smoothstep(-0.01, 0.04, hgt);
				float dens = d0 * smoothstep(0.25, 0.7, n + 0.35 * d0) * smoothstep(0.66, 0.4, hgt);
				vec3 pc = ash.rgb * (0.3 + 0.45 * n);
				pc += glow_ramp(0.6) * 1.1 * hot * exp(-hgt * 5.0) * (0.35 + 0.65 * n);
				pc += lava.rgb * 0.15 * mid * exp(-hgt * 3.0);
				col = mix(col, pc, dens * 0.95);
			}
		}

		// The fountain: bombs thrown from the crater, cooling from white to red as they fall.
		if (abs(pb.x - vx) < 0.25 && hgt > -0.12 && hgt < 0.32) {
			float lift = eruption * (0.75 + 0.35 * level);
			for (int j = 0; j < BOMBS; j++) {
				float fj = float(j);
				float h = hash1(vec2(fj, 3.0));
				float ph = fract(drive * 0.4 + h);
				float t = ph * 1.6;
				vec2 v0 = vec2((fract(h * 7.3) - 0.5) * 0.28, (0.35 + 0.3 * fract(h * 13.1)) * lift);
				vec2 a = vec2(vx, peak + 0.004) + v0 * t + vec2(0.0, -0.35 * t * t);
				float tb = max(t - 0.05, 0.0);
				vec2 b = vec2(vx, peak + 0.004) + v0 * tb + vec2(0.0, -0.35 * tb * tb);
				vec2 pa = pb - a;
				vec2 ba = b - a;
				float k = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
				float d = length(pa - ba * k);
				float T = (1.0 - ph) * smoothstep(peak - 0.1, peak - 0.02, a.y) * lift;
				col += glow_ramp(0.35 + 0.65 * T) * (smoothstep(0.003, 0.001, d) * 1.2 + exp(-d * 200.0) * 0.3) * T * 1.4;
			}
			col += lava.rgb * 0.12 * eruption * exp(-length(pb - vec2(vx, peak + 0.05)) * 18.0) * (0.5 + 0.8 * bass);
		}
	} else {
		// The ground, worked back into the field: Z away from us, X across.
		float Z = CAM / max(HORIZON - p.y, 0.0005);
		float X = (p.x - cx) * Z;
		float u = X - river_x(Z);
		float W = river_w(Z);
		float along = clamp((Z - 0.15) / 3.0, 0.0, 1.0);
		float b = band(0.04 + 0.86 * along);
		float far = smoothstep(2.0, 12.0, Z);
		vec2 fw = vec2(X, Z);
		if (abs(u) < W) {
			// The river: crust plates drifting towards us over the glowing lava. They bulge downstream in the middle,
			// where it runs fastest, and are warped so no two are alike.
			float v = Z + drive * flow * 0.05;
			float across = abs(u) / W;
			vec2 pq = vec2(u * 30.0, (v - 0.05 * (1.0 - across * across)) * 24.0);
			pq += 0.45 * (vec2(vnoise(pq * 0.6), vnoise(pq * 0.6 + 9.0)) - 0.5);
			vec2 pl = plates(pq);
			float wcrack = (0.05 + 0.16 * heat * b) * (1.0 - 0.45 * across);
			float crack = exp(-pl.x / max(wcrack, 0.01));
			float thin = smoothstep(0.7, 1.0, pl.y) * 0.4;
			float T = clamp(crack * (0.75 + 0.35 * b) + thin * (0.55 + 0.5 * b), 0.0, 1.0);
			// Cooler and crusted at the margins, glowing where they tear.
			float margin = smoothstep(0.7, 1.0, across);
			T *= 1.0 - 0.55 * margin;
			T += 0.45 * margin * smoothstep(0.55, 0.85, vnoise(vec2(v * 60.0, u * 40.0))) * (0.6 + 0.5 * b);
			T = mix(T, 0.35 + 0.35 * b, far);
			// The crust: ropes across each plate; plates tilted this way and that catch the glow from the cracks.
			float rope = 0.5 + 0.5 * sin(pq.y * 9.0 + pq.x * pq.x * 0.05 + pl.y * 20.0);
			float tilt = 0.6 + 0.4 * sin(pl.y * 40.0);
			vec3 rc = crust.rgb * (0.45 + 0.35 * rope * (1.0 - far)) * tilt;
			rc += lava.rgb * (0.08 + 0.22 * exp(-pl.x * 5.0)) * hot * tilt;
			col = mix(rc, glow_ramp(T), smoothstep(0.08, 0.5, T));
			col += lava.rgb * 0.05 * hot;
		} else {
			// The rubble on the banks and the field: lumps of cooled lava lit by the river; a few hot spots.
			float dist = abs(u) - W;
			float rough = vnoise(fw * vec2(70.0, 45.0)) * 0.6 + vnoise(fw * vec2(190.0, 120.0)) * 0.4;
			rough = mix(rough, 0.5, far);
			float lit = exp(-dist * 9.0) * hot * (0.7 + 0.5 * b);
			col = crust.rgb * (0.35 + 0.65 * rough) * (1.0 - 0.6 * far);
			col += lava.rgb * lit * (0.25 + 0.6 * rough * rough);
			float spot = smoothstep(0.82, 0.95, vnoise(fw * vec2(30.0, 22.0))) * smoothstep(0.55, 0.85, vnoise(fw * vec2(9.0, 7.0) + 4.0));
			col += glow_ramp(0.55) * spot * 0.7 * (0.5 + 0.5 * heat) * (1.0 - far);
			col += glow_ramp(0.45) * exp(-dist / max(W * 0.08, 0.002)) * 0.6 * hot;
			col += lava.rgb * 0.05 * hot * far;
		}
		// Haze over the far field, glowing.
		col = mix(col, sky.rgb * 1.5 + lava.rgb * 0.12 * hot, smoothstep(3.0, 30.0, Z) * 0.8);
	}

	// Embers rising off the river, more with the high notes.
	if (p.y < 0.75) {
		float yr = min(p.y, HORIZON - 0.01);
		float Zr = CAM / (HORIZON - yr);
		float xr = cx + river_x(Zr) / Zr;
		float near = exp(-abs(p.x - xr) * 5.0);
		if (near > 0.05) {
			vec2 eq = vec2(p.x, p.y - vis_time * 0.045) / 0.03;
			vec2 ec = floor(eq);
			float eh = hash1(ec + vec2(2.0, 8.0));
			if (eh > 0.45) {
				vec2 ep = ec + 0.5 + 0.35 * vec2(sin(vis_time * 0.9 + eh * 40.0), cos(vis_time * 0.7 + eh * 30.0));
				float d = length(eq - ep) * 0.03;
				float e = (smoothstep(2.0 * px, 0.4 * px, d) + 0.3 * exp(-d / (3.0 * px))) * near * (0.35 + 0.9 * treble) * (eh - 0.45) * 2.0;
				col += glow_ramp(0.8) * e * smoothstep(0.75, 0.3, p.y);
			}
		}
	}

	// A rock in the near right corner, dark against it all, its edge caught by the glow.
	float rock = p.y - (0.06 + 0.07 * smoothstep(1.3, aspect, p.x) + 0.02 * vnoise(vec2(p.x * 9.0, 1.0)) + 0.008 * vnoise(vec2(p.x * 40.0, 3.0)));
	if (rock < 0.004 && p.x > 1.15) {
		vec3 rk = crust.rgb * 0.25 * (0.6 + 0.4 * vnoise(p * 80.0));
		rk += lava.rgb * 0.35 * hot * smoothstep(-0.012, 0.0, rock);
		col = mix(col, rk, smoothstep(px, -px, rock) * smoothstep(1.15, 1.25, p.x));
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.3, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
