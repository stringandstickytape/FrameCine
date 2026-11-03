extends RefCounted

## The skies (shaders/fx/fx_skies.gdshader): whole skies for the room's sky sphere (surfaces "sky"), each drawing its
## own sky from its two colours, the zenith's and the horizon's. room_sky.gdshader's stars and clouds stay as they are;
## these are the richer ones, named by the room document's sky (docs/effects.md, "Connecting it").

const SHADER := "res://shaders/fx/fx_skies.gdshader"

## Options every sky has.
const _ZENITH := {"type": "color", "default": "#02040b", "description": "the sky's colour overhead",
		"uniform": "sky_zenith"}
const _HORIZON := {"type": "color", "default": "#08121f", "description": "the sky's colour at the horizon",
		"uniform": "sky_horizon"}
const _STARS := {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
		"description": "how many stars: 0 none, 1 a clear night far from towns", "uniform": "star_density"}
const _TWINKLE := {"type": "float", "min": 0.0, "max": 0.4, "default": 0.2,
		"description": "how far each star's brightness wanders, slowly, each at its own pace; at most 0.4",
		"uniform": "twinkle"}

const EFFECTS := {
	"sky_aurora": {
		"name": "Aurora sky",
		"description": "a night sky with curtains of green and violet light waving slowly above the horizon, "
				+ "and stars; arctic, calm, magical",
		"tags": ["sky", "night", "aurora", "stars", "animated", "calm"],
		"surfaces": "sky", "cost": "light", "cost_ratio": 2.26,
		"animation": {"hz": [0.02, 1.2], "swing": 0.4},
		"define": "FX_SKY_AURORA",
		"options": {
			"color": {"type": "color", "default": "#3dffa8", "description": "the curtains' colour low down",
				"uniform": "fx_color"},
			"color2": {"type": "color", "default": "#8a5cff", "description": "their colour high up",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 0.8,
				"description": "how bright the curtains are", "uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "how fast they wave and slide", "uniform": "fx_speed"},
			"stars": _STARS, "twinkle": _TWINKLE, "zenith": _ZENITH, "horizon": _HORIZON}},
	"sky_starfield": {
		"name": "Starfield sky",
		"description": "a clear night far from towns: many stars, gently twinkling, and the faint band of the "
				+ "galaxy with dark dust in it; quiet, vast",
		"tags": ["sky", "night", "stars", "space", "calm"],
		"surfaces": "sky", "cost": "light", "cost_ratio": 1.78,
		"animation": {"hz": [0.15, 1.2], "swing": 0.4},
		"photo_test": {"stars": 1.0, "twinkle": 0.4, "strength": 2.0},
		"define": "FX_SKY_STARFIELD",
		"options": {
			"color": {"type": "color", "default": "#c8d4ff", "description": "the galaxy band's glow",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how bright the band is", "uniform": "fx_strength"},
			"dust_size": {"type": "float", "min": 0.5, "max": 2.0, "default": 1.0,
				"description": "how fine the band's dust is", "uniform": "fx_scale"},
			"stars": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.7,
				"description": "how many stars: 0 none, 1 a clear night far from towns", "uniform": "star_density"},
			"twinkle": _TWINKLE, "zenith": _ZENITH, "horizon": _HORIZON}},
	"sky_nebula": {
		"name": "Nebula sky",
		"description": "deep space all round: clouds of glowing gas in two colours with dark dust and stars, "
				+ "changing shape very slowly; science fiction, dreamlike",
		"tags": ["sky", "space", "nebula", "stars", "sci-fi"],
		"surfaces": "sky", "cost": "light", "cost_ratio": 1.56,
		"animation": {"hz": [0.01, 1.2], "swing": 0.4},
		"define": "FX_SKY_NEBULA",
		"options": {
			"color": {"type": "color", "default": "#e0457b", "description": "the gas's first colour",
				"uniform": "fx_color"},
			"color2": {"type": "color", "default": "#3a7bff", "description": "the gas's second colour",
				"uniform": "fx_color2"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright the gas is",
				"uniform": "fx_strength"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3,
				"description": "how fast the clouds change shape", "uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.3, "max": 3.0, "default": 1.0,
				"description": "how large the clouds are", "uniform": "fx_scale"},
			"stars": _STARS, "twinkle": _TWINKLE,
			"background": {"type": "color", "default": "#020308", "description": "the darkness of space",
				"uniform": "sky_zenith"}}},
	"sky_sunset": {
		"name": "Sunset sky",
		"description": "the sun on the horizon with a warm glow round it, the sky deepening overhead, thin streaks "
				+ "of cloud lit from below; golden hour, romantic, warm",
		"tags": ["sky", "sunset", "warm", "dusk", "calm"],
		"surfaces": "sky", "cost": "light", "cost_ratio": 1.48,
		"animation": {"hz": [0.005, 0.1], "swing": 1.0},
		"define": "FX_SKY_SUNSET",
		"options": {
			"glow": {"type": "color", "default": "#ff7a3d", "description": "the sun's glow", "uniform": "fx_color"},
			"cloud_shade": {"type": "color", "default": "#4a2f5c", "description": "the clouds' shaded colour",
				"uniform": "fx_color2"},
			"zenith": {"type": "color", "default": "#1d2f5c", "description": "the sky's colour overhead",
				"uniform": "sky_zenith"},
			"horizon": {"type": "color", "default": "#e8925c", "description": "the sky's colour at the horizon",
				"uniform": "sky_horizon"},
			"sun_height": {"type": "float", "min": -6.0, "max": 20.0, "default": 3.0,
				"description": "degrees above the horizon (below 0: just set)", "uniform": "sun_height"},
			"sun_azimuth": {"type": "float", "min": -180.0, "max": 180.0, "default": 0.0,
				"description": "degrees round from straight ahead, + to the right", "uniform": "sun_azimuth"},
			"clouds": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "description": "how many streaks",
				"uniform": "fx_param"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "description": "how fast they drift",
				"uniform": "fx_speed"}}},
	"sky_clouds": {
		"name": "Cloud layers sky",
		"description": "a day sky with two layers of cloud drifting at their own pace, the high one thin, the low "
				+ "one full and lit on its sunward side; open air, gardens, rooftops",
		"tags": ["sky", "day", "clouds", "calm", "animated"],
		"surfaces": "sky", "cost": "light", "cost_ratio": 2.72,
		"animation": {"hz": [0.005, 0.15], "swing": 1.0},
		"define": "FX_SKY_CLOUDS",
		"options": {
			"color": {"type": "color", "default": "#f2f4f8", "description": "the clouds' lit colour",
				"uniform": "fx_color"},
			"cover": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.45, "description": "how much of the sky",
				"uniform": "fx_param"},
			"speed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4, "description": "how fast they drift",
				"uniform": "fx_speed"},
			"size": {"type": "float", "min": 0.3, "max": 3.0, "default": 1.0, "description": "how large they are",
				"uniform": "fx_scale"},
			"zenith": {"type": "color", "default": "#3f6fb5", "description": "the sky's colour overhead",
				"uniform": "sky_zenith"},
			"horizon": {"type": "color", "default": "#b9cfe6", "description": "the sky's colour at the horizon",
				"uniform": "sky_horizon"}}},
}
