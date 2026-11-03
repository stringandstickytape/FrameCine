extends RefCounted

## The transitions (shaders/fx/fx_transitions.gdshader; fx_outline_glow.gdshader for selection_outline's glow): a
## part appearing behind a moving plane or band by band, and a glowing outline to pick a part out. wipe and scan_in
## are still: their amount is set (0 hidden .. 1 whole), as dissolve's, by whatever runs the transition; their size
## is the part's length along the axis in metres, so the amount runs from one end of it to the other.

const SHADER := "res://shaders/fx/fx_transitions.gdshader"
const OUTLINE_GLOW := "res://shaders/fx/fx_outline_glow.gdshader"

const EFFECTS := {
	"wipe": {
		"name": "Wipe",
		"description": "the part shown up to a plane moving along it, with a soft glowing line at the edge (amount 0: "
				+ "hidden, 1: whole); a part being built, revealed or scanned in",
		"tags": ["transition", "reveal", "glow", "clean"],
		"blend": "cutout", "layers": true, "cost": "light", "cost_ratio": 2.44,
		"define": "FX_WIPE",
		"preview_options": {"amount": 0.6, "size": 2.0},
		"options": {
			"amount": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how much is shown: 0 hidden, 1 whole", "uniform": "fx_amount"},
			"axis": {"type": "enum", "values": ["x", "y", "z"], "default": "y",
				"description": "the part's own axis the plane moves along, from its negative end (y: bottom up)",
				"uniform": "fx_mode"},
			"size": {"type": "float", "min": 0.05, "max": 20.0, "default": 1.0,
				"description": "the part's length along the axis in metres, so 0..1 spans it exactly",
				"uniform": "fx_scale"},
			"color": {"type": "color", "default": "#7fd4ff", "description": "the edge's glow", "uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.2,
				"description": "how bright the edge is", "uniform": "fx_strength"}}},
	"scan_in": {
		"name": "Scan in",
		"description": "materialising from the bottom up: a faint grid, then glowing horizontal bands that close into "
				+ "the solid part behind a bright scan line (amount 0: nothing, 1: whole); arrivals, teleports",
		"tags": ["transition", "reveal", "sci-fi", "glow", "hologram"],
		"blend": "cutout", "layers": true, "cost": "medium", "cost_ratio": 2.86,
		"define": "FX_SCAN_IN",
		"preview_options": {"amount": 0.6, "size": 2.0, "band": 0.05},
		"options": {
			"amount": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5,
				"description": "how far it has materialised: 0 nothing, 1 whole", "uniform": "fx_amount"},
			"size": {"type": "float", "min": 0.05, "max": 20.0, "default": 1.0,
				"description": "the part's height in metres (its own y), so 0..1 spans it exactly",
				"uniform": "fx_scale"},
			"band": {"type": "float", "min": 0.005, "max": 0.2, "default": 0.03,
				"description": "metres between the bands it appears in", "uniform": "scan_pitch"},
			"color": {"type": "color", "default": "#5fe3ff", "description": "the glow of the bands and the scan line",
				"uniform": "fx_color"},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0,
				"description": "how bright the glow is", "uniform": "fx_strength"}}},
	"selection_outline": {
		"name": "Selection outline",
		"description": "a soft glowing outline around the part, the part itself unchanged, breathing slowly or still; "
				+ "picks out a chosen, pointed-at or important part",
		"tags": ["transition", "outline", "glow", "highlight", "calm"],
		"layers": true, "passes": 2, "cost": "light", "cost_ratio": 1.34,
		"animation": {"hz": [0.1, 1.0], "swing": 0.4},
		"define": "FX_SELECTION_OUTLINE",
		"second_pass": OUTLINE_GLOW,
		"options": {
			"color": {"type": "color", "default": "#73ccff", "description": "the glow's colour",
				"uniform": "glow_color", "pass": 1},
			"strength": {"type": "float", "min": 0.0, "max": 3.0, "default": 1.0,
				"description": "how bright the glow is", "uniform": "glow_strength", "pass": 1},
			"width": {"type": "float", "min": 1.0, "max": 12.0, "default": 4.0,
				"description": "pixels, the same near and far", "uniform": "width", "pass": 1},
			"rate": {"type": "float", "min": 0.1, "max": 1.0, "default": 0.5,
				"description": "breaths a second (Hz), at most 1", "uniform": "breath_rate", "pass": 1},
			"swing": {"type": "float", "min": 0.0, "max": 0.4, "default": 0.2,
				"description": "how far the glow brightens and dims as it breathes, at most 0.4; 0: still",
				"uniform": "breath_swing", "pass": 1}}},
}
