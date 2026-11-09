// Where the passing system's items stand now (scripts/env/systems/passing.gd; docs/environments/passing.md): the one
// placing that the scenery and its points of light share, so a lamp's light is always on its lamp.
//
// passing_foot(CUSTOM0, CUSTOM1, grow) gives an item's foot in the way's frame (x across, y up, z along, ahead
// positive) and how much of the item is there (grow: 0 none, 1 whole; an item is scaled about its foot by it).
// passing_colour() takes a vertex colour as it was written (sRGB, as every colour in a room's document and in
// passing/shapes.gd is) to the linear light the shaders work in: one rule for every colour in these meshes.

// For band b: how far its loop has come round (metres), fposmod(travel / seems, loop), on the CPU in 64 bits.
uniform float phase[10];
// For band b: how far one of its items runs on along the way from its foot (a row's piece: its length; else 0).
uniform float band_extent[10];
// For landmark k: its place along the way now (metres, ahead positive).
uniform float landmark_along[12];
// For landmark k: the ground it stands on (passing/shapes.gd clearing()): half its length along, and its edges
// across (signed). x = 0: none.
uniform vec3 landmark_clear[12];
uniform float travel = 0.0;
// The route's length (0: no end), and with none, the travel at which half of it is behind.
uniform float route = 0.0;
uniform float endless_half = 3600.0;
// Row b: band b's presence along the route.
uniform sampler2D presence_tex : filter_linear, repeat_disable;
uniform float band_count = 1.0;
uniform float far = 188.0;
uniform float edge = 0.82;

vec3 passing_colour(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 passing_foot(vec4 c0, vec4 c1, out float grow) {
	float loop = c1.x;
	float pace = c1.y;
	int index = int(c1.z + 0.5);
	float t;
	grow = 1.0;
	if (c1.w > 0.5) {
		t = landmark_along[index];
	} else {
		float half_loop = loop * 0.5;
		t = mod(c0.z - phase[index] + half_loop, loop) - half_loop;
		grow = 1.0 - smoothstep(half_loop * edge, half_loop, abs(t));
		// Its own place on the route does not change while it goes by (travel rises as t falls), so neither does
		// whether it is there: nothing appears or goes while it is in view.
		float s = travel + t / pace;
		float u = route > 0.0 ? clamp(s / route, 0.0, 1.0) : 1.0 - exp2(-max(s, 0.0) / endless_half);
		float p = textureLod(presence_tex, vec2(u, (float(index) + 0.5) / band_count), 0.0).r;
		if (c0.w > 0.0 && p < c0.w) {
			grow = 0.0;
		}
		// Nothing of a band stands on a landmark's ground. A band that goes by at the landmark's own pace (seems 1)
		// keeps its place against it, so this too holds for the whole time both are in view.
		float extent = band_extent[index];
		for (int k = 0; k < 12; k++) {
			vec3 cl = landmark_clear[k];
			float rel = t - landmark_along[k];
			if (cl.x > 0.0 && rel < cl.x && rel + extent > -cl.x && c0.x > cl.y && c0.x < cl.z) {
				grow = 0.0;
			}
		}
	}
	vec3 foot = vec3(c0.x, c0.y, t);
	// The last of the way that is drawn: a thing comes out of the horizon's haze, it is not switched on.
	grow *= 1.0 - smoothstep(far * 0.94, far, length(foot.xz));
	return foot;
}
