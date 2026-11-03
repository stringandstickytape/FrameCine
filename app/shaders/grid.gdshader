// Floor with a 1 m grid, unlit, antialiased lines from screen-space derivatives, fading with distance.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.05);
uniform vec3 line_color : source_color = vec3(0.35, 0.4, 0.45);
uniform float cell = 1.0;
uniform float fade_distance = 12.0;

// env_light, screen_center, screen_glow and the bias light's tint (ideas #29).
#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / cell;
	vec2 w = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-4));
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, length(world_pos.xz));
	vec3 light = room_light_at(world_pos, 1.0);
	ALBEDO = mix(base_color, line_color, line * fade) * light;
}
