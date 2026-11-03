extends RefCounted

## The first eight effects (shaders/room_effect.gdshader, unchanged; room_outline.gdshader for toon_outline's second
## pass), as room_schema.gd EFFECTS has them: the same names, options, bounds and defaults, with the library's
## metadata added. Their uniforms are set as assistant_room.gd _effect() sets them, so they draw exactly as before.

const SHADER := "res://shaders/room_effect.gdshader"

const EFFECTS := {
	"rim_glow": {
		"name": "Rim glow",
		"description": "a soft glowing rim where the surface turns away (fresnel); calm, suits any shape, layers "
				+ "over any colour or material",
		"tags": ["glow", "edge", "calm", "subtle"],
		"layers": true, "cost": "light", "cost_ratio": 1.34,
		"define": "FX_RIM_GLOW",
		"options": {
			"color": {"type": "color", "default": "#88ccff", "description": "the rim's light", "uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0,
				"description": "how bright the rim is", "uniform": "fx_strength"}}},
	"hologram": {
		"name": "Hologram",
		"description": "see-through light with fine drifting scanlines, brighter edges and a faint flicker; "
				+ "science fiction displays and ghostly copies",
		"tags": ["energy", "glow", "sci-fi", "transparent", "animated"],
		"blend": "add", "cost": "light", "cost_ratio": 2.26,
		"animation": {"hz": [0.35, 2.0], "swing": 0.25},
		"define": "FX_HOLOGRAM",
		"options": {
			"color": {"type": "color", "default": "#66ddff", "description": "the light's colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0, "description": "how bright",
				"uniform": "fx_strength"}}},
	"glass": {
		"name": "Glass",
		"description": "clear in the middle, reflective at grazing angles, tinted by the material's colour; "
				+ "windows, bottles, vitrines",
		"tags": ["material", "transparent", "reflective", "calm"],
		"blend": "alpha", "layers": true, "cost": "light", "cost_ratio": 2.07,
		"define": "FX_GLASS",
		"options": {}},
	"metal": {
		"name": "Metal",
		"description": "a polished look: the room's light above, dark below, the screen's glint; the colour tints "
				+ "it (white chrome, gold brass, orange copper)",
		"tags": ["material", "reflective", "polished"],
		"layers": true, "cost": "light", "cost_ratio": 2.12,
		"define": "FX_METAL",
		"options": {
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0,
				"description": "how strong the highlights are", "uniform": "fx_strength"}}},
	"toon_outline": {
		"name": "Toon outline",
		"description": "cel shading (three hard-edged tones of the colour) with a dark outline; cartoon and comic "
				+ "rooms",
		"tags": ["stylised", "cartoon", "outline"],
		"layers": true, "passes": 2, "cost": "light", "cost_ratio": 1.6,
		"define": "FX_TOON",
		"second_pass": "res://shaders/room_outline.gdshader",
		"options": {
			"color": {"type": "color", "default": "#101010", "description": "the outline's colour",
				"uniform": "outline_color", "pass": 1},
			"width": {"type": "float", "min": 0.5, "max": 4.0, "default": 2.0,
				"description": "pixels, the same near and far", "uniform": "width", "pass": 1}}},
	"dissolve": {
		"name": "Dissolve",
		"description": "eaten away by noise, with a glowing edge (amount 0: whole, 1: gone); a part appearing or "
				+ "burning away",
		"tags": ["transition", "glow", "fire"],
		"blend": "cutout", "layers": true, "cost": "light", "cost_ratio": 1.58,
		"define": "FX_DISSOLVE",
		"options": {
			"amount": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how much is gone: 0 whole, 1 gone", "uniform": "fx_amount"},
			"color": {"type": "color", "default": "#ff8833", "description": "the edge's glow",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.5,
				"description": "how bright the edge is", "uniform": "fx_strength"}}},
	"pulse": {
		"name": "Pulse",
		"description": "a glow that swells and fades smoothly, brightest facing you; a slow heartbeat or a "
				+ "breathing standby light",
		"tags": ["glow", "animated", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 1.62,
		"animation": {"hz": [0.05, 3.0], "swing": 0.4},
		"define": "FX_PULSE",
		"options": {
			"color": {"type": "color", "default": "#ffcc88", "description": "the glow's colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.6, "description": "how bright",
				"uniform": "fx_strength"},
			"rate": {"type": "float", "min": 0.05, "max": 3.0, "default": 0.5, "description": "Hz, at most 3",
				"uniform": "fx_rate"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.3,
				"description": "how far the brightness swings, at most 0.4", "uniform": "fx_depth"}}},
	"flicker": {
		"name": "Flicker",
		"description": "candlelight: a glow wandering on several slow waves, never a strobe; candles, lanterns, "
				+ "a fire's glow",
		"tags": ["glow", "fire", "warm", "animated"],
		"layers": true, "cost": "light", "cost_ratio": 1.6,
		"animation": {"hz": [0.05, 3.0], "swing": 0.4},
		"define": "FX_FLICKER",
		"options": {
			"color": {"type": "color", "default": "#ffaa55", "description": "the glow's colour",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.6, "description": "how bright",
				"uniform": "fx_strength"},
			"rate": {"type": "float", "min": 0.2, "max": 3.0, "default": 1.5, "description": "Hz, at most 3",
				"uniform": "fx_rate"},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.25,
				"description": "how far the brightness swings, at most 0.4", "uniform": "fx_depth"}}},
}
