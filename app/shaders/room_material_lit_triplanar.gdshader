// room_material_triplanar.gdshader in an assistant's room with real lighting: as room_material_lit.gdshader, with the
// three blended projections (three fetches per map).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#define TRIPLANAR
#include "res://shaders/room_material.gdshaderinc"
