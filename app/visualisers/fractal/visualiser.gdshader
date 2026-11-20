// Fractal halls (visualiser.json): a flight through an endless fractal building, ray-marched. Space is folded into
// a cell and turned inside out through a sphere, seven times over (an Apollonian packing in 3D): the result is halls
// of arches inside arches, pillars made of smaller halls, down to the pixel. The fold remembers how near each point
// came to the cell's planes and its middle (the orbit trap); that paints the stone, two kinds of inlay and the dark
// in the corners. The inlays are the spectrum: the first kind glows with the low half (which part by how deep in the
// folds the point lies), the second with the high half, so the sound runs through the building's seams. The
// camera drifts along on the music's clock (drive); a glow gathers where the ray passes close to walls, with the bass.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float glow = 0.6;
uniform float shape = 0.4;
uniform vec4 stone : source_color = vec4(0.5, 0.46, 0.42, 1.0);
uniform vec4 inlay_a : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 inlay_b : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 haze : source_color = vec4(0.03, 0.04, 0.08, 1.0);


// The distance to the building from p (s: how hard each fold turns space inside out), and the orbit trap.
float map(vec3 p, float s, out vec4 trap) {
	float scale = 1.0;
	trap = vec4(1000.0);
	for (int i = 0; i < 5; i++) {
		p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
		float r2 = dot(p, p);
		trap = min(trap, vec4(abs(p), r2));
		float k = s / r2;
		p *= k;
		scale *= k;
	}
	return 0.25 * abs(p.y) / scale;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float t = drive * speed * 0.1 + 4.0;
	float s = 1.08 + 0.3 * shape + 0.02 * sin(drive * 0.013);

	vec3 ro = vec3(2.8 * cos(0.1 + 0.33 * t), 0.4 + 0.3 * cos(0.37 * t), 2.8 * cos(0.5 + 0.35 * t));
	vec3 ta = vec3(1.9 * cos(1.2 + 0.41 * t), 0.4 + 0.1 * cos(0.27 * t), 1.9 * cos(2.0 + 0.38 * t));
	float roll = 0.2 * cos(0.1 * t);
	vec3 cw = normalize(ta - ro);
	vec3 cu = normalize(cross(cw, vec3(sin(roll), cos(roll), 0.0)));
	vec3 cv = cross(cu, cw);
	vec3 rd = normalize(uv.x * cu + uv.y * cv + 1.1 * cw);

	vec4 tr = vec4(0.0);
	float tt = 0.01;
	float h_last = 0.0;
	float near = 0.0;
	bool hit = false;
	for (int i = 0; i < 40; i++) {
		float h = map(ro + rd * tt, s, tr);
		h_last = h;
		near += exp(-h * 60.0);
		if (h < 0.001 * tt + 0.0003) {
			hit = true;
			break;
		}
		tt += h;
		if (tt > 16.0) {
			break;
		}
	}

	vec3 col = haze.rgb;
	if (hit) {
		vec3 pos = ro + rd * tt;
		vec4 tmp = vec4(0.0);
		float e = 0.0006 * tt + 0.0002;
		vec3 n = normalize(vec3(map(pos + vec3(e, 0.0, 0.0), s, tmp), map(pos + vec3(0.0, e, 0.0), s, tmp),
				map(pos + vec3(0.0, 0.0, e), s, tmp)) - h_last);
		float wa = clamp(6.0 * tr.y, 0.0, 1.0);
		float wb = pow(clamp(1.0 - 2.0 * tr.z, 0.0, 1.0), 8.0);
		vec3 base = mix(stone.rgb, inlay_a.rgb * 0.7 + stone.rgb * 0.3, wa * 0.75);
		base = mix(base, inlay_b.rgb * 0.8, wb);
		float ao = 0.3 + 0.7 * pow(clamp(tr.w * 2.2, 0.0, 1.0), 0.8);
		float key = clamp(dot(n, normalize(vec3(0.58, 0.58, -0.58))), 0.0, 1.0);
		float back = clamp(0.2 + 0.8 * dot(n, normalize(vec3(-0.58, -0.3, 0.58))), 0.0, 1.0);
		vec3 lit = vec3(1.0, 0.92, 0.8) * key * 1.9 + vec3(0.3, 0.38, 0.55) * back * 0.9 + vec3(0.32, 0.32, 0.38) * (0.6 + 0.4 * n.y);
		col = base * lit * ao;
		// The seams carry the sound.
		float ba = band(0.04 + 0.42 * clamp(tr.w * 1.2, 0.0, 1.0));
		float bb = band(0.5 + 0.46 * clamp(tr.x * 2.5, 0.0, 1.0));
		col += inlay_a.rgb * smoothstep(0.55, 1.0, wa) * (1.0 - wb) * (0.3 + ba * 1.2) * glow * ao;
		col += inlay_b.rgb * wb * (0.35 + bb * 1.4) * glow;
		col = mix(col, haze.rgb, 1.0 - exp(-0.1 * tt));
	}
	// Light hangs in the air where the ray passed close to the walls.
	col += mix(inlay_a.rgb, inlay_b.rgb, 0.5 + 0.5 * sin(tt * 0.7)) * near * 0.02 * glow * (0.5 + 0.5 * bass);

	col = pow(clamp(col, 0.0, 1.0), vec3(0.9));
	col *= 1.0 - 0.35 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(col, 1.0);
}
