// The runtime's controller model, unlit: its glTF materials are lit PBR, and the environments have no lights, so
// they render black. This keeps the model's base colour, albedo texture, vertex colours and emission, and fakes a
// soft key light and a rim so the shape reads in any environment. A light fixed to the view (from above-left, a
// little in front) costs one dot product; no light, shadow or GI pass.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform vec3 emission : source_color = vec3(0.0);
// The controllers' look (scripts/xr/controller_look.gd) on the shell: a finish colour in place of the moulded plastic,
// with a library material's picture over it if one is given (three projections in the part's own space, pattern_scale
// metres a repeat: the shell's UVs are an atlas), and for metal a made-up surroundings reflected (reflection 0..1: a
// dim floor, a bright band at the horizon, a sky above, as the effect library's fx_studio). Off: the model's own colours.
uniform bool use_finish = false;
uniform vec3 finish : source_color = vec3(0.02);
uniform bool use_pattern = false;
uniform sampler2D pattern : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float pattern_scale = 0.08;
uniform float reflection = 0.0;
// Dark plastic would stay near-black: lift every colour a little so the body reads against a black void.
uniform float lift = 0.07;
// 1: fake key light and rim; 0: colours as they are (the hand-built controller has its shading baked in).
uniform float fake_light = 1.0;
// The rim's strength, and a broad sheen where the surface faces the light: black plastic has little else to show its shape.
uniform float rim_gain = 0.18;
uniform float sheen = 0.0;
// The runtime model's buttons (controller_visual.gd, INK_PARTS): their moulded art turns white, the white of the printed
// legends. The atlas is two values and nothing between but edges: plastic to 0.098, art at 0.404 (linear 0.0097, 0.136). A
// straight ramp between keeps the edges and the small mips as the coverage they are.
uniform bool use_ink = false;
uniform vec3 ink_colour : source_color = vec3(1.0);
const float INK_FROM = 0.012;
const float INK_TO = 0.13;
// The right controller's Y cap (controller_visual.gd, MARK_*): the moulded letter in the atlas is painted out, here and not
// over it, so nothing can show through, and a sparkle takes its place. It moves with the cap, and is the only colour on
// the controller: unlit as the print is, one gradient from the big one's foot to the small one's tip.
uniform bool use_mark = false;
// 0: the bare cap (tools/label_proof.gd).
uniform float mark_ink = 1.0;
uniform vec2 mark_centre = vec2(0.0);
uniform float mark_mm_per_uv = 1.0;
uniform float mark_erase_mm = 0.0;
uniform vec3 mark_cap : source_color = vec3(0.07);
const vec3 MARK_FROM = vec3(0.12, 0.45, 1.0);
const vec3 MARK_VIA = vec3(0.52, 0.25, 1.0);
const vec3 MARK_TO = vec3(1.0, 0.30, 0.68);

#include "res://shaders/controller_print.gdshaderinc"

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

// A four-point star of radius r, more than zero inside: a square with a circle out of each corner.
float sparkle(vec2 p, float r) {
	vec2 a = abs(p);
	float k = 1.5 * r;
	return min(length(a - vec2(k)) - length(vec2(k - r, k)), r - max(a.x, a.y));
}

void fragment() {
	vec4 c = albedo;
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	}
	float mark = 0.0;
	vec3 mark_rgb = vec3(0.0);
	if (use_mark) {
		// The letter lies in the atlas with its top towards -U and its right towards +V.
		vec2 d = (UV - mark_centre) * mark_mm_per_uv;
		vec2 p = vec2(d.y, -d.x);
		float ink = max(sparkle(p - vec2(-0.21, -0.34), 1.75), sparkle(p - vec2(1.24, 1.37), 0.72));
		float painted = step(length(d), mark_erase_mm);
		c.rgb = mix(c.rgb, mark_cap, painted);
		mark = clamp(ink / max(fwidth(ink), 0.001) + 0.5, 0.0, 1.0) * mark_ink * painted;
		float t = clamp(dot(p - vec2(-1.96, -2.09), vec2(0.684, 0.729)) / 5.73, 0.0, 1.0);
		mark_rgb = mix(mix(MARK_FROM, MARK_VIA, t), mix(MARK_VIA, MARK_TO, t), t);
	}
	if (use_vertex_color) {
		c *= COLOR;
	}
	if (use_finish) {
		c.rgb = finish;
		if (use_pattern) {
			vec3 w = pow(abs(local_normal), vec3(4.0));
			w /= max(w.x + w.y + w.z, 1e-4);
			vec3 q = local_pos / max(pattern_scale, 0.005);
			c.rgb *= texture(pattern, q.zy).rgb * w.x + texture(pattern, q.xz).rgb * w.y + texture(pattern, q.xy).rgb * w.z;
		}
	}
	vec3 light_dir = normalize(vec3(-0.35, 0.8, 0.5));
	float key = max(dot(NORMAL, light_dir), 0.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base = c.rgb + vec3(lift);
	vec3 lit = base * mix(1.0, 0.45 + 0.75 * key, fake_light) + (vec3(rim_gain) * rim + vec3(sheen) * key * key * key) * fake_light + emission;
	if (use_ink) {
		lit = mix(lit, ink_colour, clamp((dot(c.rgb, vec3(0.2126, 0.7152, 0.0722)) - INK_FROM) / (INK_TO - INK_FROM), 0.0, 1.0));
	}
	if (reflection > 0.0) {
		// The metal tints what it reflects; the key light's highlight stays for the shape.
		float up = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).y;
		vec3 around = mix(vec3(0.05), vec3(0.16), smoothstep(-1.0, -0.05, up));
		around = mix(around, mix(vec3(0.42), vec3(0.95), smoothstep(0.05, 0.95, up)), smoothstep(-0.06, 0.05, up));
		around += vec3(0.5) * exp(-pow((up - 0.02) / 0.1, 2.0));
		lit = mix(lit, base * around * 1.3 + vec3(sheen) * key * key * key, clamp(reflection, 0.0, 1.0));
	}
	lit = controller_print(lit, UV);
	ALBEDO = mix(lit, mark_rgb, mark);
}
