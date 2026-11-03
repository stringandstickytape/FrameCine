extends RefCounted

## The procedural materials (shaders/fx/fx_materials.gdshader): surfaces that look like a real material, polished,
## woven or cut, drawn by the shader from noise (the texture material library, materials/, is the other kind). The
## shiny ones reflect a made-up studio and the screen's glint, as the first eight's metal does. Only liquid_chrome and
## marble's flow move, very slowly.

const SHADER := "res://shaders/fx/fx_materials.gdshader"

const EFFECTS := {
	"iridescent": {
		"name": "Iridescent",
		"description": "thin-film rainbow colours over the surface's own colour, the hue turning with the angle "
				+ "like a soap bubble or a beetle's shell; ornaments, vases, a sci-fi trim",
		"tags": ["material", "reflective", "rainbow", "colourful"],
		"layers": true, "cost": "light", "cost_ratio": 1.72,
		"define": "FX_IRIDESCENT",
		"options": {
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how strong the film's colours are over the surface", "uniform": "fx_strength"},
			"thickness": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "the film's thickness: thin gives golds and blues, thick pinks and greens",
				"uniform": "fx_param"},
			"size": {"type": "float", "min": 0.1, "max": 5.0, "default": 1.0,
				"description": "metres across the film's swirls of thickness", "uniform": "fx_scale"}}},
	"pearl": {
		"name": "Pearl",
		"description": "soft lustrous white with a faint pink and green sheen that turns with the angle and a gentle "
				+ "highlight; beads, a bowl, an elegant lamp or trim",
		"tags": ["material", "lustrous", "soft", "calm", "elegant"],
		"cost": "light", "cost_ratio": 2.2,
		"define": "FX_PEARL",
		"options": {
			"color": {"type": "color", "default": "#efe8de", "description": "the pearl's body colour (cream, white, "
					+ "grey, a dark pearl's charcoal)", "uniform": "fx_color"},
			"sheen": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how strong the coloured sheen and highlight are", "uniform": "fx_strength"}}},
	"velvet": {
		"name": "Velvet",
		"description": "the surface's colour as soft velvet: darker facing you, a bright soft sheen at the edges; "
				+ "sofas, cushions, curtains, a theatre's seats",
		"tags": ["material", "fabric", "soft", "calm", "cosy"],
		"layers": true, "cost": "light", "cost_ratio": 1.71,
		"define": "FX_VELVET",
		"options": {
			"sheen": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how bright the sheen at the edges is", "uniform": "fx_strength"},
			"sheen_color": {"type": "color", "default": "#ffffff",
				"description": "a tint over the sheen (white: the cloth's own colour, lighter)", "uniform": "fx_color"}}},
	"brushed_metal": {
		"name": "Brushed metal",
		"description": "metal with fine brushed streaks and a highlight stretched across them, tinted by the surface's "
				+ "colour (grey steel, gold brass); posts, panels, appliances, a modern kitchen",
		"tags": ["material", "metal", "reflective", "modern"],
		"layers": true, "cost": "medium", "cost_ratio": 2.94,
		"define": "FX_BRUSHED_METAL",
		"options": {
			"direction": {"type": "enum", "values": ["around", "along"], "default": "around",
				"description": "streaks around the part's upright axis (a turned post) or along it (a brushed panel)",
				"uniform": "fx_mode"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how bright the highlight and the screen's glint are", "uniform": "fx_strength"}}},
	"carbon_fibre": {
		"name": "Carbon fibre",
		"description": "dark woven twill of carbon fibre under a glossy clear coat, the weave catching the light by "
				+ "direction; racing seats, a sports car's trim, modern furniture",
		"tags": ["material", "woven", "reflective", "modern", "dark"],
		"cost": "medium", "cost_ratio": 3.5,
		"define": "FX_CARBON_FIBRE",
		"preview_options": {"size": 0.06},
		"options": {
			"color": {"type": "color", "default": "#34373c",
				"description": "the fibre's colour (near black; deep blue or red for a dyed weave)", "uniform": "fx_color"},
			"size": {"type": "float", "min": 0.004, "max": 0.1, "default": 0.012,
				"description": "metres across one band of the weave", "uniform": "fx_scale"},
			"coat": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how glossy the clear coat is", "uniform": "fx_strength"}}},
	"marble": {
		"name": "Marble",
		"description": "polished veined stone, still unless flow is set; floors, columns, a table top, a lobby or "
				+ "bathroom (white with grey veins, green, or black with gold)",
		"tags": ["material", "stone", "polished", "elegant", "calm"],
		"cost": "medium", "cost_ratio": 2.9,
		"animation": {"hz": [0.0, 1.0], "swing": 0.75},
		"define": "FX_MARBLE",
		"photo_test": {"flow": 1.0},
		"options": {
			"color": {"type": "color", "default": "#e6e1d8", "description": "the stone's colour",
				"uniform": "fx_color"},
			"vein_color": {"type": "color", "default": "#5a5a62", "description": "the veins' colour",
				"uniform": "fx_color2"},
			"size": {"type": "float", "min": 0.1, "max": 5.0, "default": 0.6,
				"description": "metres between the main veins, about", "uniform": "fx_scale"},
			"polish": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how glossy the polish is", "uniform": "fx_strength"},
			"flow": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0,
				"description": "how fast the veins creep, very slowly at most; 0 keeps the stone still",
				"uniform": "fx_speed"}}},
	"crystal": {
		"name": "Crystal",
		"description": "see-through cut crystal: flat facets, sharp glints, faint rainbow tints along the facets' "
				+ "edges; gems, a chandelier's drops, an award, a magical object",
		"tags": ["material", "transparent", "reflective", "sparkle", "elegant"],
		"blend": "alpha", "cost": "medium", "cost_ratio": 3.09,
		"define": "FX_CRYSTAL",
		"options": {
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how strong the rainbow tints are", "uniform": "fx_strength"},
			"size": {"type": "float", "min": 0.05, "max": 2.0, "default": 0.6,
				"description": "metres over which the facets' cut wanders (small: an irregular natural crystal)",
				"uniform": "fx_scale"}}},
	"liquid_chrome": {
		"name": "Liquid chrome",
		"description": "a mirror whose reflection slowly flows and bends as if the metal were liquid; a sci-fi "
				+ "sculpture, a dreamlike object, a centrepiece",
		"tags": ["material", "metal", "reflective", "animated", "sci-fi"],
		"cost": "light", "cost_ratio": 2.04,
		"animation": {"hz": [0.0, 0.8], "swing": 0.75},
		"define": "FX_LIQUID_CHROME",
		"options": {
			"color": {"type": "color", "default": "#e4e6ea",
				"description": "the metal's tint (white for chrome, gold, a coloured alloy)", "uniform": "fx_color"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "description": "how fast it flows",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.1, "max": 4.0, "default": 0.8,
				"description": "metres across the flowing ripples", "uniform": "fx_scale"}}},
	"frosted_glass": {
		"name": "Frosted glass",
		"description": "see-through milky glass, more opaque at the edges, with a soft fine grain, tinted by the "
				+ "surface's colour; shower screens, lamp shades, office partitions",
		"tags": ["material", "transparent", "glass", "soft", "calm"],
		"blend": "alpha", "layers": true, "cost": "light", "cost_ratio": 2.35,
		"define": "FX_FROSTED_GLASS",
		"options": {
			"frost": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how milky: 0 lightly frosted, 1 nearly opaque", "uniform": "fx_param"}}},
}
