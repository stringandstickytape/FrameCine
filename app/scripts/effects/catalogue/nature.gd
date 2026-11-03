extends RefCounted

## The natural effects (shaders/fx/fx_nature.gdshader): water, fire, smoke, sky and wind, all slow and soft. Patterns
## are laid on the part's own three planes, so they suit spheres, boxes and models alike; sizes are in metres.

const SHADER := "res://shaders/fx/fx_nature.gdshader"

const EFFECTS := {
	"caustics": {
		"name": "Caustics",
		"description": "underwater light dancing over the surface in soft bright lines, two layers drifting apart; "
				+ "keeps the surface's colour; pool walls and floors, an aquarium room, a calm blue space",
		"tags": ["water", "light", "glow", "animated", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 2.56,
		"animation": {"hz": [0.02, 0.5], "swing": 1.0},
		"define": "FX_CAUSTICS",
		# Big enough that the lines are drawn in the clip's 24 pixels (smaller, they fade to their average).
		"photo_test": {"strength": 2.0, "speed": 1.0, "size": 4.0},
		"options": {
			"color": {"type": "color", "default": "#a8e4ff", "description": "the light's colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6,
				"description": "how bright the light is", "uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how fast the light drifts and wobbles (0 still)", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.2, "max": 6.0, "default": 1.0,
				"description": "metres the pattern spans, about four lines across", "uniform": "fx_scale"}}},
	"water": {
		"name": "Water",
		"description": "a calm rippling water surface: deep colour where you look into it, the room and the screen's "
				+ "glint reflected where you look across it; pools, ponds, a fountain's basin",
		"tags": ["water", "reflective", "animated", "calm"],
		"cost": "medium", "cost_ratio": 3.44,
		"animation": {"hz": [0.02, 0.8], "swing": 0.5},
		"define": "FX_WATER",
		"options": {
			"color": {"type": "color", "default": "#14505e", "description": "the water's deep colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how strong the reflections are", "uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "how fast the ripples drift (0 still)", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.2, "max": 8.0, "default": 1.0, "description": "metres across a ripple",
				"uniform": "fx_scale"},
			"ripple": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "how rough the surface is, 0 glassy to 1 choppy", "uniform": "fx_param"}}},
	"lava": {
		"name": "Lava",
		"description": "dark cooled crust plates with glowing molten cracks between them, the heat wandering slowly "
				+ "along the cracks; a volcanic floor, a forge, a fire pit's bed",
		"tags": ["fire", "glow", "hot", "animated", "calm"],
		"cost": "light", "cost_ratio": 2.41,
		"animation": {"hz": [0.01, 0.2], "swing": 0.8},
		"define": "FX_LAVA",
		"options": {
			"color": {"type": "color", "default": "#ff5a1a", "description": "the molten glow's colour",
				"uniform": "fx_color"},
			"crust": {"type": "color", "default": "#1c1512", "description": "the cooled crust's colour",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.2,
				"description": "how bright the glow is", "uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how fast the heat wanders (0 still)", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.1, "max": 4.0, "default": 0.5, "description": "metres across a plate",
				"uniform": "fx_scale"},
			"molten": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "how much molten shows, 0 thin cracks to 1 wide rivers", "uniform": "fx_param"}}},
	"embers": {
		"name": "Embers",
		"description": "a dark charred surface with glowing seams and scattered specks that brighten and dim slowly, "
				+ "each at its own pace; a hearth's bed, burnt logs, a brazier",
		"tags": ["fire", "glow", "hot", "sparkle", "animated", "calm"],
		"cost": "light", "cost_ratio": 2.6,
		"animation": {"hz": [0.01, 1.0], "swing": 0.7},
		"define": "FX_EMBERS",
		"options": {
			"color": {"type": "color", "default": "#ff6a1e", "description": "the glow's colour", "uniform": "fx_color"},
			"char": {"type": "color", "default": "#1a1310", "description": "the charred surface's colour",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.5,
				"description": "how bright the specks and seams are", "uniform": "fx_strength"},
			"rate": {"type": "float", "min": 0.05, "max": 1.0, "default": 0.4,
				"description": "the fastest speck's rhythm, in times a second (others slower)", "uniform": "fx_rate"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.3,
				"description": "how far a speck brightens and dims, at most 0.4", "uniform": "fx_depth"},
			"size": {"type": "float", "min": 0.02, "max": 1.0, "default": 0.08, "description": "metres between specks",
				"uniform": "fx_scale"},
			"density": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how many specks glow, 0 a few to 1 many", "uniform": "fx_param"}}},
	"smoke": {
		"name": "Smoke",
		"description": "soft smoke rising and curling slowly on a see-through surface, its outline hidden; a box or "
				+ "sphere around a hearth, a chimney's top, a misty corner",
		"tags": ["smoke", "fire", "transparent", "animated", "calm"],
		"blend": "alpha", "cost": "medium", "cost_ratio": 3.94,
		"animation": {"hz": [0.05, 0.4], "swing": 1.0},
		"define": "FX_SMOKE",
		"options": {
			"color": {"type": "color", "default": "#a7a9ad", "description": "the smoke's colour, lit by the room",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 1.5, "default": 0.8, "description": "how thick it is",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how fast it rises and curls (0 still)", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.1, "max": 4.0, "default": 0.6, "description": "metres across a puff",
				"uniform": "fx_scale"}}},
	"clouds": {
		"name": "Clouds",
		"description": "soft white clouds drifting slowly over a sky colour, forming and thinning; a window, a dome, "
				+ "a painted ceiling",
		"tags": ["sky", "clouds", "animated", "calm"],
		"cost": "light", "cost_ratio": 1.94,
		"animation": {"hz": [0.01, 0.3], "swing": 1.0},
		"define": "FX_CLOUDS",
		"options": {
			"color": {"type": "color", "default": "#f4f6fa", "description": "the clouds' colour",
				"uniform": "fx_color"},
			"sky": {"type": "color", "default": "#6b9ad6", "description": "the sky behind them",
				"uniform": "fx_color2"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how fast they drift (0 still)", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.3, "max": 20.0, "default": 0.6,
				"description": "metres across a cloud (a few metres on a big dome)", "uniform": "fx_scale"},
			"cover": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how much of the sky is cloud, 0 a few wisps to 1 overcast", "uniform": "fx_param"}}},
	"starfield": {
		"name": "Starfield",
		"description": "tiny stars on a night colour, each twinkling gently at its own pace, with a faint band of "
				+ "dust; a dome, a ceiling, a panel or a globe",
		"tags": ["sky", "night", "stars", "sparkle", "animated", "calm"],
		"cost": "light", "cost_ratio": 0.9,
		"animation": {"hz": [0.15, 1.0], "swing": 0.4},
		"define": "FX_STARFIELD",
		# Stars big enough to be drawn in the clip's 24 pixels (smaller, they fade to their average) and many, so
		# enough pixels are bright enough to be counted.
		"photo_test": {"strength": 3.0, "twinkle": 0.4, "size": 0.15, "density": 1.0},
		"options": {
			"color": {"type": "color", "default": "#ffffff", "description": "the stars' colour", "uniform": "fx_color"},
			"night": {"type": "color", "default": "#060a17", "description": "the night behind them",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0,
				"description": "how bright the stars and the dust are", "uniform": "fx_strength"},
			"twinkle": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.25,
				"description": "how far each star brightens and dims, at most 0.4", "uniform": "fx_depth"},
			"size": {"type": "float", "min": 0.01, "max": 1.0, "default": 0.06,
				"description": "metres between stars (more on a far dome)", "uniform": "fx_scale"},
			"density": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how many stars, 0 sparse to 1 crowded", "uniform": "fx_param"}}},
	"wind_sway": {
		"name": "Wind sway",
		"description": "the part bends from its foot in slow gusts of wind, keeping its colour; plants, grass, flags, "
				+ "lanterns on a cord; needs a shape with many vertices (sphere, model), not a box",
		"tags": ["wind", "motion", "plant", "animated", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 0.78,
		"animation": {"hz": [0.03, 0.6], "swing": 0.4},
		"define": "FX_WIND_SWAY",
		"preview_options": {"sway": 0.15},
		# The silhouette's motion is the part moving, not a brightness pattern (a hard edge crossing a pixel jumps
		# in one picture however slow it is): the clip checks the gusts' sheen at its fastest, the part still.
		"photo_test": {"speed": 1.0, "sway": 0.0, "sheen": 0.4},
		"options": {
			"sway": {"type": "float", "min": 0.0, "max": 0.2, "default": 0.05,
				"description": "metres the top moves in a gust", "uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "how quick the gusts are, 0 a slow breeze to 1 a lively wind", "uniform": "fx_speed"},
			"height": {"type": "float", "min": 0.1, "max": 5.0, "default": 1.0,
				"description": "metres from the foot to where the bend is full", "uniform": "fx_scale"},
			"base": {"type": "float", "min": -5.0, "max": 5.0, "default": -0.5,
				"description": "the still foot's height in the part's own space, metres: minus half the height for "
						+ "a sphere, box or cylinder, 0 for a model standing on its origin", "uniform": "sway_base"},
			"sheen": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.12,
				"description": "a pale sheen in the gusts, as leaves turning", "uniform": "sway_sheen"},
			"color": {"type": "color", "default": "#e4efd6", "description": "the sheen's colour",
				"uniform": "fx_color"}}},
}
