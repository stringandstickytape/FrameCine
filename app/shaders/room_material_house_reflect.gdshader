// room_material_house.gdshader with reflections (REFLECT in room_material.gdshaderinc; since 2026-11-08): lacquered
// paint and chrome that show the sky, a skyline, the ground, the screen and a glint without a probe. The drive-in's car
// and the cars parked round it (scripts/env/systems/kit/reflect.gd sets the uniforms every frame).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

#define LIT
#define HOUSE
#define REFLECT
#include "res://shaders/room_material.gdshaderinc"
