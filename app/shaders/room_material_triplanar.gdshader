// room_material.gdshader for meshes with neither flat faces nor usable UVs (spheres, cylinders, scanned models): three
// projections blended by the normal, so three fetches per map. Use it only where the plain one shows seams.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

#define TRIPLANAR
#include "res://shaders/room_material.gdshaderinc"
