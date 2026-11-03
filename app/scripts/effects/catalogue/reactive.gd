extends RefCounted

## The reactive effects (shaders/fx/fx_reactive.gdshader): surfaces that follow the film, its sound (react_level, set
## by scripts/assistant/room_react.gd while a room uses one) or its colours (the bias light's copy of the picture).
## The room builder starts the react path for a part with one of these, as it does for screen_glow's react.

const SHADER := "res://shaders/fx/fx_reactive.gdshader"

const EFFECTS := {
	"react_sound": {
		"name": "Sound glow",
		"description": "a light inside that rises and settles with the film's sound, soft rings spreading from the "
				+ "middle when it is loud; speakers, a stage's edge, a music room",
		"tags": ["reactive", "sound", "glow", "animated"],
		"layers": true, "cost": "light", "cost_ratio": 1.32,
		"animation": {"hz": [0.5, 3.0], "swing": 0.4},
		"define": "FX_REACT_SOUND",
		"react": "loudness",
		"options": {
			"color": {"type": "color", "default": "#7fb2ff", "description": "the glow's colour", "uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.6, "description": "how bright",
				"uniform": "fx_strength"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.3,
				"description": "how far the sound moves the brightness, at most 0.4", "uniform": "fx_depth"},
			"ring_size": {"type": "float", "min": 0.1, "max": 2.0, "default": 0.5,
				"description": "metres between the rings", "uniform": "fx_scale"}}},
	"react_screen": {
		"name": "Screen sheen",
		"description": "the film's own colours as a soft sheen, each side of the part taking the colour of the "
				+ "picture's side nearest it; ties walls and furniture to the film",
		"tags": ["reactive", "screen", "glow", "ambient", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 1.52,
		"animation": {"hz": [0.0, 0.64], "swing": 1.0},
		"define": "FX_REACT_SCREEN",
		"react": "brightness",
		"options": {
			"color": {"type": "color", "default": "#ffffff", "description": "a tint over the film's colours",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.8, "description": "how strong",
				"uniform": "fx_strength"}}},
	"react_caustics": {
		"name": "Caustics with sound",
		"description": "rippling light as under water, drifting slowly, brighter in loud passages; pools, "
				+ "aquariums, a calm blue room",
		"tags": ["reactive", "sound", "water", "glow", "animated", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 1.53,
		"animation": {"hz": [0.05, 1.0], "swing": 1.0},
		"define": "FX_REACT_CAUSTICS",
		"react": "loudness",
		"options": {
			"color": {"type": "color", "default": "#9fe0ff", "description": "the light's colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.5, "description": "how bright",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "description": "how fast it drifts",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.2, "max": 4.0, "default": 1.0,
				"description": "metres across the pattern's repeat", "uniform": "fx_scale"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.3,
				"description": "how far the sound moves the brightness, at most 0.4", "uniform": "fx_depth"}}},
}
