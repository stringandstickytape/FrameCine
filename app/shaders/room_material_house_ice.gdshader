// room_material_house.gdshader as ice (ICE in room_material.gdshaderinc; since 2026-11-08, for the Ice cinema): blocks
// of ice with what is frozen inside them drawn at depth, lit from within by the candles near them and, round the
// screen, by the film's own colours; the candles' glints and the picture's soft reflection on the face. Opaque: no
// stacked transparency. scripts/env/systems/kit/ice_hall.gd makes the materials and sets the candles.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#define HOUSE
#define ICE
#include "res://shaders/room_material.gdshaderinc"
