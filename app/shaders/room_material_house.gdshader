// room_material_lit.gdshader for a built-in room lit for real (the cinema, environments/cinema.gd): the engine's light
// (a baked lightmap once there is one) on the maps, the house lights' level from the room light, the stock rooms'
// screen spill, lamps standing in for the room's lights before a bake, and a pass for the lightmapper. Everything is
// in room_material.gdshaderinc (LIT and HOUSE defined).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#define HOUSE
#include "res://shaders/room_material.gdshaderinc"
