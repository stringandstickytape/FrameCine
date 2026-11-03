extends RefCounted

## The energy effects (shaders/fx/fx_energy.gdshader): light that seems to come from the surface itself, for science
## fiction rooms, night scenes and quiet glowing accents. Each is calm: slow, soft, two colours at most.

const SHADER := "res://shaders/fx/fx_energy.gdshader"

const EFFECTS := {
	"plasma": {
		"name": "Plasma",
		"description": "slowly flowing plasma in a deep colour and a bright one, soft veins, brighter toward the "
				+ "silhouette; an energy core, an orb, a reactor wall",
		"tags": ["energy", "glow", "sci-fi", "animated", "calm"],
		"cost": "light", "cost_ratio": 1.24,
		"animation": {"hz": [0.0, 0.4], "swing": 1.0},
		"define": "FX_PLASMA",
		"options": {
			"color": {"type": "color", "default": "#ff4fd2", "description": "the bright colour of the flow",
				"uniform": "fx_color"},
			"color2": {"type": "color", "default": "#2a0b72", "description": "the deep colour between the flows",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "description": "how fast it flows",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.1, "max": 4.0, "default": 1.0,
				"description": "metres across one swirl", "uniform": "fx_scale"},
			"rim": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.6,
				"description": "how much brighter it gets toward the silhouette", "uniform": "fx_param"}}},
	"aurora": {
		"name": "Aurora",
		"description": "soft curtains of light on a dark night, drifting sideways, fine vertical rays, green at the foot "
				+ "and violet above, fading top and bottom; night walls, a calm backdrop",
		"tags": ["energy", "glow", "night", "sky", "animated", "calm"],
		"cost": "light", "cost_ratio": 1.22,
		"animation": {"hz": [0.0, 0.4], "swing": 1.0},
		"define": "FX_AURORA",
		"options": {
			"color": {"type": "color", "default": "#3dffb0", "description": "the light at the curtains' foot",
				"uniform": "fx_color"},
			"color2": {"type": "color", "default": "#8c5cff", "description": "the light toward their top",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.9, "description": "how bright",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3,
				"description": "how fast the curtains drift and fold", "uniform": "fx_speed"},
			"height": {"type": "float", "min": 0.3, "max": 8.0, "default": 1.6,
				"description": "metres from the curtains' foot to where they fade out, centred on the part",
				"uniform": "fx_scale"}}},
	"nebula": {
		"name": "Nebula",
		"description": "deep space on the surface: glowing clouds in two colours with dark dust lanes and a few small "
				+ "stars, drifting very slowly; space-station windows, a night dome, a backdrop",
		"tags": ["energy", "space", "night", "glow", "animated", "calm"],
		"cost": "light", "cost_ratio": 1.84,
		"animation": {"hz": [0.0, 0.4], "swing": 1.0},
		"define": "FX_NEBULA",
		"options": {
			"color": {"type": "color", "default": "#ff6aa0", "description": "the first clouds' glow",
				"uniform": "fx_color"},
			"color2": {"type": "color", "default": "#3a78ff", "description": "the second clouds' glow",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "description": "how fast the clouds drift",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.2, "max": 8.0, "default": 1.5,
				"description": "metres across the largest clouds", "uniform": "fx_scale"},
			"stars": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "description": "how many stars",
				"uniform": "fx_param"},
			"twinkle": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.15,
				"description": "how much the stars twinkle (slowly), at most 0.4", "uniform": "fx_depth"}}},
	"force_field": {
		"name": "Force field",
		"description": "see-through light in hexagonal cells, brighter at the edges, rows of cells brightening in a "
				+ "slow ripple; shields, barriers, a sci-fi dome or doorway",
		"tags": ["energy", "glow", "sci-fi", "transparent", "animated"],
		"blend": "add", "cost": "medium", "cost_ratio": 3.64,
		"animation": {"hz": [0.1, 1.5], "swing": 0.4},
		"define": "FX_FORCE_FIELD",
		"options": {
			"color": {"type": "color", "default": "#5fd4ff", "description": "the field's light", "uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"},
			"size": {"type": "float", "min": 0.03, "max": 1.0, "default": 0.25, "description": "metres across a cell",
				"uniform": "fx_scale"},
			"rate": {"type": "float", "min": 0.1, "max": 1.5, "default": 0.3,
				"description": "how often the ripple passes a cell, a second (Hz)", "uniform": "fx_rate"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.2,
				"description": "how much the ripple brightens the cells, at most 0.4", "uniform": "fx_depth"}}},
	"circuit": {
		"name": "Circuit",
		"description": "faintly glowing circuit traces with round pads over the surface, darkened to a board, small "
				+ "soft pulses running along them; sci-fi panels, consoles, a server room",
		"tags": ["energy", "sci-fi", "tech", "glow", "animated"],
		"layers": true, "cost": "light", "cost_ratio": 2.26,
		"animation": {"hz": [0.0, 1.0], "swing": 0.6},
		"define": "FX_CIRCUIT",
		"options": {
			"color": {"type": "color", "default": "#bff8ff", "description": "the pulses' light", "uniform": "fx_color"},
			"color2": {"type": "color", "default": "#1fb39a", "description": "the traces' glow",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "description": "how fast the pulses run",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.02, "max": 0.5, "default": 0.08, "description": "metres between traces",
				"uniform": "fx_scale"},
			"pulses": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.7,
				"description": "how bright the pulses are; 0 for still traces", "uniform": "fx_param"}},
		"photo_test": {"speed": 1.0, "strength": 2.0, "pulses": 1.0}},
	"neon": {
		"name": "Neon",
		"description": "a neon tube: a near-white core where it faces you, saturated colour toward the edges, an "
				+ "optional faint hum; signs, tubes, accent strips, a club or diner",
		"tags": ["energy", "glow", "neon", "retro", "sign"],
		"cost": "light", "cost_ratio": 0.5,
		"animation": {"hz": [0.35, 1.5], "swing": 0.2},
		"define": "FX_NEON",
		"options": {
			"color": {"type": "color", "default": "#ff2d95", "description": "the tube's colour", "uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"},
			"core": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how wide the white-hot core is", "uniform": "fx_param"},
			"hum": {"type": "float", "min": 0.0, "max": 0.2, "default": 0.0,
				"description": "a faint slow wavering of the brightness, 0 for steady (at most 0.2)",
				"uniform": "fx_depth"}},
		"photo_test": {"hum": 0.2}},
}
