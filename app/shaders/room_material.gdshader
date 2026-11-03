// Room surfaces with a library material (scripts/env/material_library.gd): one fetch per map, on the surface's own
// axes in metres or the mesh's UVs. Everything is in room_material.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

#include "res://shaders/room_material.gdshaderinc"
