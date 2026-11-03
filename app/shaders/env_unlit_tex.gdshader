// env_unlit.gdshader with a texture, for rooms loaded from glTF files at runtime (scripts/env/gltf_room.gd, ideas #53):
// the file's base colour (factor times texture) lit only by the room's ambient level and the screen's spill, plus its
// emission unscaled (lamps, signs). No lights, shadows or GI. The assistant's rooms (scripts/assistant/assistant_room.gd)
// also use it with a transparent picture: compiled again with ALPHA_CUT defined (cut-outs: alpha-tested in the opaque
// pass, edges smoothed by MSAA's alpha to coverage) or ALPHA_BLEND (see-through, drawn in the transparent pass).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;
#ifdef ALPHA_CUT
render_mode alpha_to_coverage;
#endif

uniform vec3 albedo : source_color = vec3(1.0);
// The colour's own alpha times the picture's (ALPHA_CUT, ALPHA_BLEND only).
uniform float alpha = 1.0;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform vec3 emission : source_color = vec3(0.0);
uniform float spill = 1.0;
uniform float floor_darkening = 0.0;
// The surface shows at its own brightness, not darkened by the room's light (an assistant's picture or poster,
// scripts/assistant/assistant_room.gd).
uniform bool self_lit = false;

// env_light, screen_center, screen_glow and the bias light's tint (ideas #29).
#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 light = vec3(1.0);
	if (!self_lit) {
		light = room_light_at(world_pos, spill);
		light *= mix(1.0 - floor_darkening, 1.0, clamp(world_pos.y / 3.0, 0.0, 1.0));
	}
	vec4 tex = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	ALBEDO = albedo * tex.rgb * light + emission;
#if defined(ALPHA_CUT)
	ALPHA = alpha * tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
#elif defined(ALPHA_BLEND)
	ALPHA = alpha * tex.a;
#endif
}
