// room_material.gdshader in an assistant's room with real lighting (scripts/assistant/assistant_room.gd): lit by the
// engine's lights with the maps' colour, roughness and normals, plus room_lit.gdshader's fill, film light and contact
// darkening. Everything is in room_material.gdshaderinc (LIT defined).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#include "res://shaders/room_material.gdshaderinc"
