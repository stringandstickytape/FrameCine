// room_material_house.gdshader as a wall mosaic (MOSAIC in room_material.gdshaderinc; since 2026-11-08, for the Palace
// of Culture 1974): tesserae of glass, gold and stone laid in courses from a map of one texel each, grout between
// them, each pressed in a little askew so the lamps and the picture glint off it tile by tile as the head moves.
// Opaque, one extra texture read. scripts/env/systems/kit/palace_culture.gd makes the material and draws the map.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#define HOUSE
#define MOSAIC
#include "res://shaders/room_material.gdshaderinc"
