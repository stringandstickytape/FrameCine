// Microscope (visualiser.json): a drop of pond water seen down a microscope, the round field of the eyepiece with its
// pointer and a scale. Volvox colonies roll by, hundreds of cells on each sphere (the far side seen faintly through)
// round daughter colonies inside; round diatoms with rings of pores and ribs of glass; boat-shaped ones glide along
// their slits; two slipper-shaped ciliates swim loops, their cilia beating in waves; crescent desmids. Each is a part of
// the spectrum: the volvox breathe with the low notes, the diatoms' pores and oil drops glow with theirs, the ciliates'
// cilia beat harder with the high notes and their star-shaped vacuoles swell with the bass. `dark` turns bright field
// (things dark on light) into dark field (things glowing on black). Drawn as filters over the light: each thing absorbs
// a little and bends light at its edges. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float dark = 0.0;
uniform float swim = 0.5;
uniform float pulse = 0.6;
uniform vec4 water : source_color = vec4(0.93, 0.92, 0.86, 1.0);
uniform vec4 algae : source_color = vec4(0.3, 0.62, 0.22, 1.0);
uniform vec4 silica : source_color = vec4(0.78, 0.6, 0.3, 1.0);
uniform vec4 protist : source_color = vec4(0.72, 0.7, 0.86, 1.0);

const float FR = 0.47;


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

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

vec3 rot_x(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

// One thing over the light: a (0..1) absorbs towards tint; edge and detail are lines where it bends light (dark in
// bright field, glowing in dark field, in glow's colour).
void layer(inout vec3 ab, inout vec3 sc, float a, vec3 tint, float edge, float detail, vec3 glow) {
	ab *= mix(vec3(1.0), tint, clamp(a, 0.0, 1.0));
	ab *= 1.0 - clamp(0.55 * edge + 0.35 * detail, 0.0, 0.9);
	sc += glow * (edge * 0.9 + detail * 0.6 + a * 0.12);
}

// The cells on a volvox's sphere near the direction m (in the colony's own frame), in latitude rings.
float sphere_cells(vec3 m) {
	float D = 0.13;
	float lat = asin(clamp(m.y, -1.0, 1.0));
	float lon = atan(m.z, m.x);
	float i = floor((lat + PI * 0.5) / D);
	float lat_c = (i + 0.5) * D - PI * 0.5;
	float n = max(1.0, floor(cos(lat_c) * TAU / D));
	float j = floor((lon / TAU + 0.5) * n + 0.5 * mod(i, 2.0));
	float lon_c = (j + 0.5 - 0.5 * mod(i, 2.0)) / n * TAU - PI;
	vec3 cd = vec3(cos(lat_c) * cos(lon_c), sin(lat_c), cos(lat_c) * sin(lon_c));
	return smoothstep(0.05, 0.028, length(m - cd));
}

void volvox(vec2 p, vec2 c, float R, float spin_a, float b, float px, inout vec3 ab, inout vec3 sc) {
	vec2 q = (p - c) / R;
	float rr = dot(q, q);
	if (rr > 1.15) {
		return;
	}
	float r1 = sqrt(rr);
	float edge = smoothstep(2.0 * px / R, 0.0, abs(r1 - 1.0));
	float tilt = 0.45;
	vec3 glow = algae.rgb * 1.4 + 0.1;
	if (rr < 1.0) {
		float z = sqrt(1.0 - rr);
		vec3 front = rot_x(rot_y(vec3(q, z), spin_a), tilt);
		vec3 back = rot_x(rot_y(vec3(q, -z), spin_a), tilt);
		float cells = sphere_cells(front) * (0.55 + 0.45 * z) + sphere_cells(back) * 0.3;
		float shell = 0.12 + 0.25 * pow(1.0 - z, 3.0);
		layer(ab, sc, shell, algae.rgb, 0.0, cells * (0.6 + 0.6 * b * pulse), glow * (0.7 + 0.8 * b * pulse));
		// Daughter colonies, turning with the sphere.
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			vec3 dpos = normalize(vec3(sin(fi * 2.4 + 0.3), cos(fi * 1.7 + 1.0) * 0.8, sin(fi * 3.1 + 2.0))) * 0.48;
			vec3 dv = rot_y(rot_x(dpos, -tilt), -spin_a);
			float dr = 0.2 * (1.0 + 0.1 * b * pulse);
			float dl = length(q - dv.xy) / dr;
			if (dl < 1.05) {
				float dz = sqrt(max(1.0 - dl * dl, 0.0));
				float tex = smoothstep(0.55, 0.75, vnoise((q - dv.xy) / dr * 5.0 + fi * 7.0));
				layer(ab, sc, 0.45 * smoothstep(1.0, 0.85, dl) * (0.6 + 0.4 * dz), algae.rgb * 0.55, smoothstep(0.12, 0.0, abs(dl - 0.97)) * 0.7, tex * 0.4, glow * (0.6 + 0.8 * b * pulse));
			}
		}
	}
	layer(ab, sc, 0.0, vec3(1.0), edge, 0.0, glow);
}

// A round diatom: rings of pores, ribs of glass, golden plastids inside. kind 0 pores, 1 ribs and rings, 2 sectors.
void centric(vec2 p, vec2 c, float R, float ang, float b, int kind, float px, inout vec3 ab, inout vec3 sc) {
	vec2 q = p - c;
	float l = length(q);
	if (l > R + 0.004) {
		return;
	}
	float rho = l / R;
	float a = atan(q.y, q.x) - ang;
	vec3 glow = mix(silica.rgb, vec3(1.0), 0.55);
	float edge = smoothstep(1.6 * px, 0.0, abs(l - R)) + 0.6 * smoothstep(1.4 * px, 0.0, abs(l - R * 0.92));
	if (l < R) {
		float nr = 10.0;
		float ri = floor(rho * nr);
		float rc = (ri + 0.5) / nr;
		float cnt = max(1.0, floor(TAU * rc * nr * 0.95));
		float f = fract(a / TAU * cnt + 0.5 * mod(ri, 2.0)) - 0.5;
		float hd = length(vec2(f * TAU / cnt * l, (rho - rc) * R));
		float hr = 0.33 * R / nr;
		float pore = smoothstep(hr, hr * 0.45, hd) * step(0.2, rho) * step(rho, 0.9);
		float rib = smoothstep(1.2 * px, 0.2 * px, abs(fract(a / TAU * 15.0) - 0.5) * TAU / 15.0 * l) * step(0.22, rho);
		float ring = smoothstep(1.2 * px, 0.2 * px, abs(fract(rho * 5.0) - 0.5) * R / 5.0);
		float marg = (0.5 + 0.5 * sin(a * 90.0)) * step(0.92, rho) * 0.5;
		float rose = smoothstep(0.06 * R, 0.03 * R, length(q - rot(vec2(0.12 * R, 0.0), ang + floor(a / TAU * 6.0 + 0.5) / 6.0 * TAU))) * step(rho, 0.2);
		float detail = marg + rose;
		float sector = 0.0;
		if (kind == 0) {
			detail += pore * 1.4 + rib * 0.2;
		} else if (kind == 1) {
			detail += rib * 1.1 + ring * 0.6 + pore * 0.6;
		} else {
			sector = step(0.5, fract(a / TAU * 6.0)) * step(0.22, rho);
			detail += pore * (0.7 + 0.7 * sector);
		}
		// The pores light in rings running outwards with this diatom's part of the spectrum.
		float ripple = 0.7 + 0.3 * sin(rho * 14.0 - vis_time * 1.6) * b * pulse;
		layer(ab, sc, 0.16 + 0.1 * sector, silica.rgb, 0.0, detail * ripple, glow * (0.6 + 0.9 * b * pulse));
		// Plastids.
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			vec2 pc = rot(vec2(0.55 * R, 0.0), ang * 0.6 + fi / 5.0 * TAU + 0.3);
			float pl = length(q - pc) / (R * 0.17 * (1.0 + 0.12 * b * pulse));
			if (pl < 1.0) {
				layer(ab, sc, 0.35 * smoothstep(1.0, 0.6, pl), silica.rgb * vec3(0.8, 0.6, 0.35), 0.0, 0.0, silica.rgb * (0.4 + 1.2 * b * pulse));
			}
		}
	}
	layer(ab, sc, 0.0, vec3(1.0), edge, 0.0, glow);
}

// A boat-shaped diatom gliding along its slit: striae, the raphe and its nodules, two golden plates with oil drops.
void pennate(vec2 p, vec2 c, float L, float Wd, float ang, float b, float px, inout vec3 ab, inout vec3 sc) {
	vec2 q = rot(p - c, -ang);
	if (abs(q.x) > L + 0.004 || abs(q.y) > Wd + 0.004) {
		return;
	}
	float cc = (L * L - Wd * Wd) / (2.0 * Wd);
	float d = length(vec2(q.x, abs(q.y) + cc)) - (cc + Wd);
	vec3 glow = mix(silica.rgb, vec3(1.0), 0.55);
	float edge = smoothstep(1.6 * px, 0.0, abs(d)) + 0.5 * smoothstep(1.4 * px, 0.0, abs(d + Wd * 0.14));
	if (d < 0.0) {
		float s = q.x + abs(q.y) * 0.35 * sign(q.x);
		float sp = 0.0052;
		float striae = smoothstep(1.1 * px, 0.25 * px, abs(fract(s / sp) - 0.5) * sp) * step(Wd * 0.2, abs(q.y)) * step(Wd * 0.14, -d);
		float raphe = smoothstep(1.2 * px, 0.2 * px, abs(q.y)) * step(0.012, abs(q.x)) * step(abs(q.x), L * 0.86);
		float nod = smoothstep(0.009, 0.006, length(q / vec2(1.0, 0.7))) + smoothstep(0.006, 0.004, length(vec2(abs(q.x) - L * 0.88, q.y)));
		layer(ab, sc, 0.14, silica.rgb, 0.0, striae * 0.55 + raphe + nod * 0.7, glow * (0.6 + 0.6 * b * pulse));
		float plate = step(0.24 * Wd, abs(q.y)) * smoothstep(-Wd * 0.12, -Wd * 0.22, d) * step(abs(q.x), L * 0.72);
		layer(ab, sc, 0.38 * plate, silica.rgb * vec3(0.8, 0.6, 0.32), 0.0, 0.0, silica.rgb * 0.5);
		// Oil drops: bright little lenses that glow with this diatom's part of the spectrum.
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			vec2 oc = vec2((fi < 2.0 ? -1.0 : 1.0) * L * 0.42, (mod(fi, 2.0) < 1.0 ? -1.0 : 1.0) * Wd * 0.5);
			float ol = length(q - oc);
			float orr = Wd * 0.18;
			if (ol < orr * 1.4) {
				layer(ab, sc, 0.0, vec3(1.0), smoothstep(1.4 * px, 0.0, abs(ol - orr)), 0.0, vec3(1.0, 0.9, 0.6) * (0.6 + 1.2 * b * pulse));
				sc += vec3(1.0, 0.9, 0.6) * smoothstep(orr, 0.0, ol) * (0.3 + 0.8 * b * pulse) * 0.5;
				ab *= 1.0 + 0.12 * smoothstep(orr, 0.0, ol);
			}
		}
	}
	layer(ab, sc, 0.0, vec3(1.0), edge, 0.0, glow);
}

// A slipper-shaped ciliate swimming: cilia all round in beating waves, granular inside, the nucleus, food vacuoles
// going round, two star-shaped contractile vacuoles.
void ciliate(vec2 p, vec2 c, float L, float Wd, float ang, float t, float b, float px, inout vec3 ab, inout vec3 sc) {
	vec2 q = rot(p - c, -ang);
	float CL = 0.011;
	if (abs(q.x) > L + CL || abs(q.y) > Wd + CL) {
		return;
	}
	float wq = Wd * (1.0 - 0.18 * q.x / L);
	vec2 e = q / vec2(L, wq);
	float d = (length(e) - 1.0) * min(L, wq) * 1.1;
	d = max(d, -(length(q - vec2(0.15 * L, wq * 1.08)) - wq * 0.42));
	vec3 glow = mix(protist.rgb, vec3(1.0), 0.4);
	float edge = smoothstep(1.6 * px, 0.0, abs(d));
	if (d > -0.002 && d < CL) {
		float s = atan(e.y, e.x) / TAU * PI * (L + Wd) * 2.0;
		float spc = 0.0042;
		float i = floor(s / spc + 0.5);
		float off = s - i * spc;
		float tilt = sin(i * 0.33 - t * 6.0) * (0.3 + 0.35 * treble * pulse) + 0.25;
		float dd = max(d, 0.0);
		float cil = smoothstep(0.9 * px, 0.15 * px, abs(off - dd * tilt - dd * dd * 20.0 * tilt)) * (1.0 - dd / CL) * step(0.0, d);
		layer(ab, sc, 0.0, vec3(1.0), 0.0, cil * 0.7, glow * 0.8);
	}
	if (d < 0.0) {
		float gran = smoothstep(0.62, 0.8, vnoise(q * 260.0 + vec2(t * 0.6, 0.0)));
		float pell = smoothstep(0.75, 1.0, sin((q.x * 0.6 + q.y * 1.4 + t * 0.002) / 0.0035)) * smoothstep(-0.012, 0.0, d);
		layer(ab, sc, 0.2, protist.rgb, 0.0, gran * 0.35 + pell * 0.25, glow * 0.6);
		vec2 nq = (q - vec2(-0.05 * L, -0.05 * Wd)) / vec2(0.3 * L, 0.42 * Wd);
		float nl = length(nq);
		if (nl < 1.05) {
			layer(ab, sc, 0.22 * smoothstep(1.0, 0.85, nl), protist.rgb * 0.75, smoothstep(0.12, 0.0, abs(nl - 0.97)) * 0.5, smoothstep(0.6, 0.8, vnoise(nq * 9.0)) * 0.3, glow * 0.7);
		}
		// Food vacuoles, carried round the cell.
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			float fa = fi / 6.0 * TAU + t * 0.35;
			vec2 fc = vec2(0.55 * L * cos(fa), 0.5 * Wd * sin(fa));
			float fr = Wd * (0.11 + 0.05 * fract(fi * 0.61));
			float fl = length(q - fc);
			if (fl < fr * 1.3) {
				layer(ab, sc, 0.4 * smoothstep(fr, fr * 0.7, fl), mix(protist.rgb, vec3(0.55, 0.45, 0.25), 0.7), smoothstep(1.3 * px, 0.0, abs(fl - fr)) * 0.6, 0.0, vec3(0.9, 0.8, 0.55));
			}
		}
		// Contractile vacuoles: they swell with the bass, their canals radiating.
		for (int i = 0; i < 2; i++) {
			vec2 vc = vec2((i == 0 ? 0.55 : -0.6) * L, 0.12 * Wd);
			vec2 vq = q - vc;
			float vl = length(vq);
			float rv = Wd * (0.13 + 0.08 * bass * pulse);
			float canal = smoothstep(1.2 * px, 0.2 * px, abs(sin(atan(vq.y, vq.x) * 3.0)) * vl * 0.33) * step(vl, rv * 2.6) * step(rv, vl);
			layer(ab, sc, 0.0, vec3(1.0), smoothstep(1.3 * px, 0.0, abs(vl - rv)), canal * 0.5, glow);
			ab *= 1.0 + 0.1 * smoothstep(rv, 0.0, vl);
		}
	}
	layer(ab, sc, 0.0, vec3(1.0), edge, 0.0, glow);
}

// A crescent desmid: a green chloroplast with ridges, a row of pyrenoids, the nucleus between the halves, and at each
// tip a clear vacuole where tiny crystals dance.
void closterium(vec2 p, vec2 c, float Ra, float T, float ang, float b, float px, inout vec3 ab, inout vec3 sc) {
	vec2 q = rot(p - c, -ang);
	float rho = length(q);
	float a = atan(q.x, q.y);
	float span = 0.85;
	if (abs(a) > span + 0.05 || abs(rho - Ra) > T + 0.005) {
		return;
	}
	float hw = T * pow(max(cos(a / span * PI * 0.5), 0.0), 0.65);
	float d = abs(rho - Ra) - hw;
	vec3 glow = algae.rgb * 1.3 + 0.1;
	float edge = smoothstep(1.6 * px, 0.0, abs(d)) * step(abs(a), span);
	if (d < 0.0 && abs(a) < span) {
		float u = (rho - Ra) / max(hw, 1e-4);
		float tip = smoothstep(span * 0.78, span * 0.86, abs(a));
		float gap = smoothstep(0.06, 0.03, abs(a));
		float ridges = smoothstep(0.2, 0.0, abs(fract(u * 2.5 + 0.5) - 0.5) - 0.3);
		float pf = fract(a / 0.085 + 0.5) - 0.5;
		float pyr = smoothstep(0.32 * T, 0.18 * T, length(vec2(pf * 0.085 * Ra, rho - Ra))) * (1.0 - tip) * (1.0 - gap);
		float chl = (1.0 - tip) * (1.0 - gap * 0.8);
		layer(ab, sc, 0.5 * chl, algae.rgb, 0.0, ridges * chl * 0.25 + pyr * 0.6, glow * (0.5 + 0.9 * b * pulse));
		if (tip > 0.0) {
			for (int i = 0; i < 3; i++) {
				float fi = float(i);
				float side = a > 0.0 ? 1.0 : -1.0;
				vec2 cp = vec2(sin(side * (span * 0.93)), cos(side * (span * 0.93))) * Ra;
				cp += (vec2(vnoise(vec2(vis_time * (1.2 + 0.8 * treble), fi * 7.0)), vnoise(vec2(fi * 5.0, vis_time * (1.2 + 0.8 * treble)))) - 0.5) * T * 0.7;
				sc += vec3(1.0, 0.95, 0.8) * smoothstep(1.6 * px, 0.4 * px, length(q - cp)) * (0.6 + 0.8 * treble);
				ab *= 1.0 - 0.4 * smoothstep(1.6 * px, 0.4 * px, length(q - cp));
			}
		}
	}
	layer(ab, sc, 0.0, vec3(1.0), edge, 0.0, glow);
}

// The eyepiece's pointer: a tapered needle in from the right.
float sd_needle(vec2 p, vec2 fc) {
	vec2 a = fc + vec2(FR + 0.02, 0.03);
	vec2 b = fc + vec2(0.1, 0.045);
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(0.006, 0.0007, h);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	vec2 FC = vec2(aspect * 0.5, 0.5);
	vec2 f = p - FC;
	float rf = length(f);
	float t = drive * swim;

	vec3 ab = vec3(1.0);
	vec3 sc = vec3(0.0);
	if (rf < FR + 0.01) {
		// Out-of-focus debris and in-focus grains drifting slowly.
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			vec2 dc = vec2(sin(fi * 2.3 + t * 0.03) * 0.33, cos(fi * 1.7 + t * 0.025) * 0.3);
			float dl = length(f - dc) / (0.05 + 0.03 * fract(fi * 0.7));
			layer(ab, sc, 0.1 * smoothstep(1.0, 0.2, dl), vec3(0.75, 0.68, 0.55), 0.0, 0.0, vec3(0.5, 0.45, 0.35) * 0.4);
		}
		vec2 gq = (f + vec2(t * 0.006, t * 0.002)) / 0.028;
		float gh = hash1(floor(gq) + vec2(41.0, 3.0));
		if (gh > 0.72) {
			vec2 gc = (floor(gq) + 0.2 + 0.6 * vec2(fract(gh * 31.0), fract(gh * 77.0))) * 0.028;
			float gr = (0.6 + 1.2 * fract(gh * 13.0)) * px;
			float gl = length(f + vec2(t * 0.006, t * 0.002) - gc);
			layer(ab, sc, 0.0, vec3(1.0), smoothstep(gr + px, gr, gl) * 0.8, 0.0, vec3(0.8, 0.85, 1.0));
		}
		// Bacteria: little rods, wandering.
		vec2 bq = f / 0.06;
		vec2 bcell = floor(bq);
		float bh = hash1(bcell + vec2(9.0, 17.0));
		if (bh > 0.6) {
			vec2 bc = (bcell + 0.5 + 0.3 * vec2(sin(vis_time * 0.4 + bh * 30.0), cos(vis_time * 0.33 + bh * 20.0))) * 0.06;
			vec2 bd = rot(f - bc, -(bh * 20.0 + vis_time * 0.2));
			float rod = length(vec2(max(abs(bd.x) - 0.0035, 0.0), bd.y)) - 0.0011;
			layer(ab, sc, 0.0, vec3(1.0), smoothstep(px, -px, rod) * 0.6, 0.0, vec3(0.85, 0.9, 1.0));
		}

		closterium(f, vec2(0.02, -0.29) + 0.02 * vec2(sin(t * 0.11), cos(t * 0.09)), 0.17, 0.021, 0.35 + 0.15 * sin(t * 0.05), band(0.88), px, ab, sc);
		closterium(f, vec2(-0.12, 0.33) + 0.02 * vec2(cos(t * 0.1), sin(t * 0.12)), 0.12, 0.015, 2.9 + 0.2 * sin(t * 0.06), band(0.95), px, ab, sc);
		pennate(f, vec2(-0.05, -0.04) + rot(vec2(0.035 * sin(t * 0.3), 0.0), 0.4), 0.1, 0.022, 0.4, band(0.32), px, ab, sc);
		pennate(f, vec2(0.17, -0.02) + rot(vec2(0.03 * sin(t * 0.37 + 2.0), 0.0), 2.0), 0.08, 0.018, 2.0, band(0.55), px, ab, sc);
		pennate(f, vec2(-0.34, 0.07) + rot(vec2(0.025 * sin(t * 0.33 + 4.0), 0.0), 1.2), 0.07, 0.02, 1.2, band(0.78), px, ab, sc);
		centric(f, vec2(0.06, 0.24) + 0.02 * vec2(sin(t * 0.07), cos(t * 0.08)), 0.062, t * 0.05, band(0.4), 0, px, ab, sc);
		centric(f, vec2(-0.29, -0.19) + 0.02 * vec2(cos(t * 0.06), sin(t * 0.07)), 0.05, -t * 0.04, band(0.5), 1, px, ab, sc);
		centric(f, vec2(0.31, 0.13) + 0.02 * vec2(sin(t * 0.08 + 1.0), cos(t * 0.05)), 0.045, t * 0.06, band(0.62), 2, px, ab, sc);
		volvox(f, vec2(-0.18, 0.11) + 0.04 * vec2(sin(t * 0.09), cos(t * 0.07)), 0.095 * (1.0 + 0.025 * band(0.04) * pulse), t * 0.35, band(0.04), px, ab, sc);
		volvox(f, vec2(0.25, -0.21) + 0.04 * vec2(cos(t * 0.08), sin(t * 0.1)), 0.066 * (1.0 + 0.025 * band(0.14) * pulse), -t * 0.45 + 1.0, band(0.14), px, ab, sc);
		for (int i = 0; i < 2; i++) {
			float fi = float(i);
			float w = t * (0.16 + 0.04 * fi) + fi * 3.0;
			vec2 cc = vec2(0.27 * cos(w), 0.2 * sin(w * 1.3 + fi));
			vec2 vel = vec2(-0.27 * sin(w), 0.26 * cos(w * 1.3 + fi));
			ciliate(f, cc, 0.1 - 0.015 * fi, 0.034 - 0.004 * fi, atan(vel.y, vel.x), t + fi * 5.0, band(0.7 + 0.15 * fi), px, ab, sc);
		}
	}

	// Bright field: the lamp through it all, brightest in the middle. Dark field: only what the things scatter.
	float lamp = (0.82 + 0.18 * (1.0 - rf * rf / (FR * FR))) * (0.94 + 0.08 * level);
	vec3 bf = water.rgb * lamp * ab;
	vec3 df = water.rgb * 0.03 + sc * 0.55 * (0.9 + 0.2 * level);
	vec3 col = mix(bf, df, dark);

	// The scale in the eyepiece, and its pointer.
	vec3 ink = mix(vec3(0.03), vec3(0.45), dark);
	float sy = FC.y - 0.36;
	float sx = p.x - FC.x;
	if (abs(sx) < 0.221 && p.y > sy - 0.02 && p.y < sy + 0.02) {
		float tick = abs(fract(sx / 0.022 + 0.5) - 0.5) * 0.022;
		float tall = mod(floor(sx / 0.022 + 0.5), 5.0) < 0.5 ? 0.016 : 0.008;
		float sd = min(abs(p.y - sy) - 0.0006, max(tick - 0.0006, abs(p.y - sy - tall * 0.5) - tall * 0.5));
		col = mix(col, ink, smoothstep(px, -px, sd) * 0.8);
	}
	float needle = sd_needle(p, FC);
	col = mix(col, ink * 0.6, smoothstep(px, -px, needle));

	// The edge of the field: soft, with a little colour fringe; beyond it the dark of the eyepiece.
	float fe = smoothstep(FR, FR - 0.008, rf);
	col *= fe;
	col += vec3(0.25, 0.12, 0.02) * smoothstep(0.01, 0.0, abs(rf - FR - 0.002)) * mix(0.25, 0.08, dark);
	col += vec3(0.02, 0.06, 0.15) * smoothstep(0.012, 0.0, abs(rf - FR + 0.006)) * mix(0.3, 0.1, dark);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
