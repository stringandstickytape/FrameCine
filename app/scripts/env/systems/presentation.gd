extends "res://scripts/env/systems/env_system.gd"

## The presentation chain (docs/environments.md, "The presentation system"): the stages between the film and the
## viewer's eyes, each optional.
##   source         film (gate weave, a slight tilt, flicker, dust, scratches, the lamp's hotspot), tape (tracking
##                  wobble, chroma bleed, head-switch noise at the bottom), broadcast (interlace)
##   transmission   aerial noise (snow), a ghost, a weak signal
##   display        mechanical (a 1930 mechanical-scan set's few orange lines), crt (curvature, round corners, a mask,
##                  scanlines, the glass's reflection), panel (a flat panel's grid and backlight bleed),
##                  rear_projection (soft focus, convergence fringes, a hotspot, lenticular lines, a narrow fan of
##                  light), oled (true blacks, a sheen at a glance)
##   the set        its window (`tube`) and the film in it (aspect_mode: letterbox, pan and scan, 14:9, stretch), a
##                  mirror's flip, the light off the screen's axis (off_axis), switching on and off (switch_on,
##                  switch_off: a CRT's raster opens from a dot and collapses to a line and a dot, a valve set warms
##                  up, a panel comes up) with our own switch sounds, and a channel change (channel)
##   speaker        the sound through a small speaker: a drive-in's window speaker, a telly's, a radio cabinet's, a
##                  flat panel's
## A preset (PRESETS: the TV eras, a worn print, a drive-in's) fills every parameter the document leaves out; the
## document's own values and bindings win. To move a preset's value by a cue, give it in the document.
##
## The picture: while a picture stage is on, the screen's flat mesh draws the film with this system's material
## (shaders/env_presentation.gdshader: the screen's own picture, its uniforms copied each frame, then the stages), and
## the film layer steps aside (film_layer.gd request_scene()): an OpenXR layer would skip the scene's shaders. With
## every picture stage off nothing changes and the film layer stays. Flat screens only.
## The sound: a bus of its own, "Film speaker", just before Film; while a speaker is on, Film sends to it and it to
## Master. The binaural renderer and the film's analysis (on Film) are not touched, and the duck stays keyed from Film.
##
##   picture_on() -> bool, attached, material(), value(param), speaker_now, static PRESETS, static SPEAKERS

const SHADER := preload("res://shaders/env_presentation.gdshader")
const EnvAudio := preload("res://scripts/env/env_audio.gd")
const VideoMode := preload("res://scripts/video_mode.gd")

const SoundBed := preload("res://scripts/env/systems/sound_bed.gd")
const Acoustics := preload("res://scripts/env/systems/acoustics.gd")
const EnvSynth := preload("res://scripts/env/env_synth.gd")

const SOURCES: Array[String] = ["none", "film", "tape", "broadcast"]
const DISPLAYS: Array[String] = ["none", "mechanical", "crt", "panel", "rear_projection", "oled"]
const MASKS: Array[String] = ["none", "shadow", "grille", "slot"]
const ASPECT_MODES: Array[String] = ["letterbox", "pan_and_scan", "fourteen_nine", "stretch"]
## How a set switches on and off ("auto": by its display: a CRT's raster, a valve set's warm-up for the mechanical
## set, a panel's, a rear projection's slow fade).
const SWITCHING: Array[String] = ["auto", "crt", "valve", "panel", "projection"]
## Each way of switching: seconds to come on and to go off, and the sounds of each (env_synth.gd).
const SWITCH := {
	"crt": {"on": 1.6, "off": 1.1, "on_sounds": ["switch_clunk"], "off_sounds": ["switch_clunk", "crt_off"],
			"channel": "channel_clunk"},
	"valve": {"on": 8.0, "off": 2.4, "on_sounds": ["switch_clunk", "valve_hum"],
			"off_sounds": ["switch_clunk", "crt_off"], "channel": "channel_clunk"},
	"panel": {"on": 0.9, "off": 0.35, "on_sounds": [], "off_sounds": [], "channel": ""},
	"projection": {"on": 3.0, "off": 0.6, "on_sounds": ["switch_clunk"], "off_sounds": ["switch_clunk"],
			"channel": "channel_clunk"},
}
## A tube's switching off: seconds to collapse to the dot, and the dot's own seconds when off_dot is -1.
const OFF_COLLAPSE := {"crt": 0.5, "valve": 0.7}
const OFF_DOT := {"crt": 0.6, "valve": 1.7}
## The shortest switching on for each way (the dot's fade-in stays slower than the comfort ceiling's fade).
const SWITCH_MIN_ON := {"crt": 1.5, "valve": 2.0, "panel": 0.6, "projection": 1.0}
## The set's face when it is dark (gamma-encoded): a tube's grey glass, a rear projection's grey-black screen, a
## panel's black, an OLED's true black.
const FACES := {"none": 0.02, "mechanical": 0.015, "crt": 0.035, "panel": 0.012, "rear_projection": 0.045,
		"oled": 0.0}
## The sounds a set makes when it switches (sound_bed.gd LEVELS has their designed levels).
const SWITCH_SOUNDS: Array[String] = ["switch_clunk", "valve_hum", "crt_off", "channel_clunk"]
## The speakers: the band (high-pass and low-pass, Hz; slope 1..4 = 6..24 dB an octave), an EQ6's six bands (dB at
## 32, 100, 320, 1000, 3200 and 10000 Hz), a little drive (0..1), and the stereo width (0: mono).
const SPEAKERS := {
	"window": {"high": 320.0, "low": 3400.0, "slope": 4, "eq": [0, 0, 1, 4, 2, 0], "drive": 0.12, "width": 0.0,
			"description": "a drive-in's window speaker: a tinny band, a little rattle, mono"},
	"telly": {"high": 150.0, "low": 6500.0, "slope": 2, "eq": [0, 0, 0, 2.5, 1, 0], "drive": 0.0, "width": 0.0,
			"description": "a telly's small speaker, mono"},
	"cabinet": {"high": 110.0, "low": 4200.0, "slope": 3, "eq": [0, 0, 3, 1, 0, 0], "drive": 0.04, "width": 0.0,
			"description": "a wooden radio cabinet's speaker, warm and boxy, mono"},
	"panel": {"high": 200.0, "low": 12000.0, "slope": 2, "eq": [0, 0, 0, 0, 1.5, 0], "drive": 0.0, "width": 0.4,
			"description": "a flat panel's thin speakers, narrow stereo"},
}
## The bus the speaker's filters sit on (just before Film, which sends to it while a speaker is on).
const SPEAKER_BUS := &"Film speaker"
## Gate weave at weave 1, as a fraction of the picture's height (real projectors: about 0.1-0.3 %).
const WEAVE_MAX := 0.003
## The flicker's depth at flicker 1 (the picture's light, up or down), and how fast it may waver: a new target this
## often (seconds), followed with this time constant: well under the photosensitivity ceiling (room_schema MAX_HZ).
const FLICKER_DEPTH := 0.035
const FLICKER_STEP := 0.25
const FLICKER_TAU := 0.15
## Film frames a second for the dust and the scratches.
const FILM_FPS := 24.0

## The presets: the TV eras and two of the cinema set's screens. Names are pastiche, never a real mark.
const PRESETS := {
	"worn_print": {"title": "Worn Print", "description": "a 1980s print near the end of its run: gate weave, a "
			+ "slight tilt, dust, scratches and a lamp's flicker",
			"params": {"source": "film", "weave": 0.7, "tilt": 0.35, "flicker": 0.5, "dust": 0.25, "scratches": 0.4,
					"hotspot": 0.4}},
	"starlight_lot_1958": {"title": "Starlight Lot, 1958", "description": "a drive-in: a print with a little "
			+ "weave and dust, a strong lamp's hotspot, the sound from the window speaker",
			"params": {"source": "film", "weave": 0.5, "flicker": 0.4, "dust": 0.3, "scratches": 0.2, "hotspot": 0.6,
					"speaker": "window"}},
	"glowbox_1930": {"title": "Glowbox Thirty, 1930", "description": "a mechanical-scan set: thirty lines "
			+ "glowing orange in a small window, a faint hiss of noise, the sound from a radio cabinet",
			"params": {"display": "mechanical", "mech_lines": 30, "snow": 0.08, "weak": 0.2, "flicker": 0.3,
					"lines": 240, "speaker": "cabinet"}},
	"fireside_1953": {"title": "Fireside, 1953", "description": "a black and white set on a rooftop aerial: a "
			+ "small round-cornered tube, 405-line interlace, snow and a ghost",
			"params": {"source": "broadcast", "interlace": 0.6, "lines": 377, "snow": 0.22, "ghost": 0.25,
					"ghost_shift": 0.035, "display": "crt", "tube": 1.3333, "curvature": 0.9, "corner": 0.6, "mask": "none",
					"scanlines": 0.45, "glass": 0.7, "colour": 0.0, "tint": [0.92, 0.96, 1.0], "speaker": "telly",
					"switching": "valve", "off_dot": 6.0}},
	"colourstar_1972": {"title": "Colourstar, 1972", "description": "an early colour set: a curved tube with a "
			+ "shadow mask, warm and rich colours, interlace, a faint ghost",
			"params": {"source": "broadcast", "interlace": 0.5, "lines": 576, "snow": 0.06, "ghost": 0.12,
					"display": "crt", "tube": 1.3333, "curvature": 0.7, "corner": 0.45, "mask": "shadow", "mask_pitch": 380.0,
					"mask_strength": 0.35, "scanlines": 0.3, "glass": 0.6, "colour": 1.15, "tint": [1.0, 0.97, 0.9],
					"speaker": "telly", "switching": "valve", "warm_up": 5.0, "off_dot": 1.5}},
	"sirclive_1983": {"title": "Sirclive, 1983", "description": "a portable telly on a home computer's aerial "
			+ "lead: 240 bold lines, a little RF noise, bright colours on a shadow mask",
			"params": {"source": "broadcast", "interlace": 0.0, "lines": 240, "snow": 0.05, "ghost": 0.06,
					"ghost_shift": 0.012, "display": "crt", "tube": 1.3333, "curvature": 0.8, "corner": 0.5, "mask": "shadow",
					"mask_pitch": 300.0, "mask_strength": 0.4, "scanlines": 0.65, "glass": 0.6, "colour": 1.2,
					"speaker": "telly", "off_dot": 0.8}},
	"rewinder_1987": {"title": "Rewinder, 1987", "description": "a rented tape on the family telly: tracking "
			+ "wobble, chroma bleed, the head-switch tear at the bottom, a slot mask",
			"params": {"source": "tape", "tracking": 0.5, "head_switch": 0.7, "chroma_bleed": 0.6, "tape_noise": 0.4,
					"lines": 576, "display": "crt", "tube": 1.3333, "curvature": 0.55, "corner": 0.35, "mask": "slot",
					"mask_pitch": 420.0, "mask_strength": 0.3, "scanlines": 0.3, "glass": 0.5, "speaker": "telly",
					"off_dot": 0.5}},
	"nightowl_1993": {"title": "Nightowl, 1993", "description": "a bedroom telly with a flatter tube and an "
			+ "aperture grille, playing a tape that has been watched a few times",
			"params": {"source": "tape", "tracking": 0.25, "head_switch": 0.5, "chroma_bleed": 0.4,
					"tape_noise": 0.25, "lines": 576, "display": "crt", "tube": 1.3333, "curvature": 0.35, "corner": 0.25,
					"mask": "grille", "mask_pitch": 480.0, "mask_strength": 0.3, "scanlines": 0.25, "glass": 0.45,
					"speaker": "telly", "off_dot": 0.25}},
	"freedtv_2005": {"title": "FreeDTV, 2005", "description": "a free digital broadcast on an early flat panel: a "
			+ "clean picture, a faint pixel grid, the backlight glowing through the dark scenes",
			"params": {"display": "panel", "panel_grid": 0.4, "panel_pixels": 1366, "panel_bleed": 0.5,
					"glass": 0.3, "speaker": "panel"}},
	"mirrorlid_1937": {"title": "Mirrorlid, 1937", "description": "a pre-war set whose tube faces up, the picture "
			+ "seen in the mirror in its lid: 405 lines, a small round 5:4 tube with a greenish white, a film panned "
			+ "and scanned to fill it, a long warm-up",
			"params": {"source": "broadcast", "interlace": 0.6, "lines": 377, "snow": 0.16, "ghost": 0.18,
					"ghost_shift": 0.03, "display": "crt", "tube": 1.25, "curvature": 1.0, "corner": 0.75, "mask": "none",
					"scanlines": 0.5, "glass": 0.55, "colour": 0.0, "tint": [0.9, 0.98, 0.9], "aspect_mode": "pan_and_scan",
					"off_axis": 0.2, "switching": "valve", "warm_up": 10.0, "speaker": "cabinet", "off_dot": 8.0}},
	"rental_1966": {"title": "Tellyhire, 1966", "description": "a rented black and white set in a console on "
			+ "splayed legs: 405 lines, a film panned and scanned to fill the 4:3 tube, a valve set's warm-up",
			"params": {"source": "broadcast", "interlace": 0.5, "lines": 377, "snow": 0.08, "ghost": 0.1,
					"display": "crt", "tube": 1.3333, "curvature": 0.6, "corner": 0.4, "mask": "none", "scanlines": 0.4,
					"glass": 0.6, "colour": 0.0, "tint": [0.94, 0.97, 1.0], "aspect_mode": "pan_and_scan",
					"off_axis": 0.15, "switching": "valve", "warm_up": 9.0, "speaker": "telly", "off_dot": 3.0}},
	"projection_2002": {"title": "Bigview, 2002", "description": "a big rear projection set playing a disc: soft "
			+ "focus, faint colour fringes, a hotspot that follows the eye, fine lines on the screen, and a picture "
			+ "that dims when seen from above or below",
			"params": {"display": "rear_projection", "tube": 1.7778, "soft_focus": 0.5, "convergence": 0.45,
					"lenticular": 0.5, "hotspot": 0.5, "off_axis": 0.8, "glass": 0.35, "aspect_mode": "letterbox",
					"switching": "projection", "speaker": "panel"}},
	"slimline_present": {"title": "Slimline, the present", "description": "a very thin OLED panel: true blacks, a "
			+ "sharp picture with a little punch, a sheen only at a glance, the colour shifting a touch from the side",
			"params": {"display": "oled", "tube": 1.7778, "off_axis": 0.25, "glass": 0.3, "aspect_mode": "letterbox",
					"switching": "panel", "speaker": "panel"}},
}


static func spec() -> Dictionary:
	var presets: Array[String] = ["none"]
	var preset_text := []
	for k: String in PRESETS:
		presets.append(k)
		preset_text.append("%s (%s: %s)" % [k, PRESETS[k]["title"], PRESETS[k]["description"]])
	var speakers: Array[String] = ["none"]
	var speaker_text := []
	for k: String in SPEAKERS:
		speakers.append(k)
		speaker_text.append("%s (%s)" % [k, SPEAKERS[k]["description"]])
	return {
		"kind": "screen",
		"description": "The chain of stages between the film and the viewer: a source (a film print's weave, "
				+ "tilt, dust and flicker; a tape's wobble, bleed and tear; a broadcast's interlace), the "
				+ "transmission (snow, a ghost, a weak signal), the display (a mechanical-scan set, a CRT with "
				+ "curvature, round corners, a mask and glass, a flat panel) and the sound through a small "
				+ "speaker. A preset sets a whole era. With a picture stage on, the film is drawn in the room "
				+ "instead of the headset's film layer: one per room.",
		"params": {
			"preset": {"type": "enum", "values": presets, "default": "none", "live": true,
					"description": "a whole chain at once; the document's own values win: " + "; ".join(preset_text)},
			"source": {"type": "enum", "values": SOURCES, "default": "none", "live": true,
					"description": "where the picture comes from: none, film (a print), tape, broadcast"},
			"weave": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "motion": {"max": 1.0},
					"description": "film: gate weave, the picture's unsteady drift (1: about 0.3 % of its height)"},
			"tilt": {"type": "float", "min": -2.0, "max": 2.0, "default": 0.0, "live": true, "motion": {"max": 2.0},
					"description": "film: the picture turned this many degrees on the screen (a crooked projector)"},
			"flicker": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true, "brightness": true,
					"flicker": true, "steady": 0.0, "description": "the lamp's flicker: the light wavers by up "
					+ "to 3.5 %, slower than 3 times a second (off with Flickering lights off)"},
			"dust": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: specks of dust, a new few each frame"},
			"scratches": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: thin scratches running down the print"},
			"hotspot": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "film: the lamp's bright middle, the corners darker; rear projection: a faint "
					+ "bright patch where the eye looks down the projector's light (it follows the head)"},
			"tracking": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"motion": {"max": 1.0}, "description": "tape: the lines' slow sideways wobble"},
			"head_switch": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: the torn, noisy last lines at the bottom"},
			"chroma_bleed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: the colour smeared and late, to the right"},
			"tape_noise": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "tape: noise in the picture and paler colour"},
			"interlace": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "broadcast: the two fields' lines, one after the other"},
			"lines": {"type": "int", "min": 30, "max": 1200, "default": 576, "live": true,
					"description": "the picture's lines (scanlines, interlace, the grain of the snow)"},
			"snow": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: aerial noise, the snow of a weak channel"},
			"ghost": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: a faint second picture to the right (the signal's echo)"},
			"ghost_shift": {"type": "float", "min": 0.005, "max": 0.08, "default": 0.03, "live": true,
					"description": "how far right the ghost is, as a fraction of the width"},
			"weak": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "transmission: a weak signal (paler, flatter, more snow)"},
			"display": {"type": "enum", "values": DISPLAYS, "default": "none", "live": true,
					"description": "the set: none, mechanical (a 1930 mechanical-scan set's few glowing lines), "
					+ "crt (a picture tube), panel (a flat panel), rear_projection (a big set's screen lit from "
					+ "behind), oled (a very thin panel with true blacks)"},
			"curvature": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"description": "crt: how much the tube's face bulges"},
			"corner": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.35, "live": true,
					"description": "crt: the round corners (1: a radius of half the height)"},
			"tube": {"type": "float", "min": 0.0, "max": 3.0, "default": 0.0, "live": true,
					"description": "the set's window: the tube's or the panel's aspect (4:3 is 1.33, 16:9 1.78; 0: "
					+ "the picture's own). Give the room's screen the same shape. A wide film sits letterboxed in a 4:3 "
					+ "tube: the round corners and the bulge are the tube's; outside the window the set's bezel shows"},
			"aspect_mode": {"type": "enum", "values": ASPECT_MODES, "default": "letterbox", "live": true,
					"description": "the film in the set's window: letterbox (all of it, black bars where its shape "
					+ "differs), pan_and_scan (it fills the window, its sides cut off), fourteen_nine (the 14:9 "
					+ "compromise: a little cut, thin bars), stretch (stretched to the window)"},
			"mirror": {"type": "bool", "default": false, "live": true,
					"description": "the picture flipped left to right: a mirror-lid set seen the wrong way round "
					+ "(off: the set's electronics turn it round)"},
			"off_axis": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "how much the picture changes seen from off its axis: a tube a little darker, a "
					+ "rear projection much darker from above and below, a flat panel's colour and contrast shifting"},
			"soft_focus": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "rear projection: the picture a little soft (1: about three pixels of a 1080 film)"},
			"convergence": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "rear projection: the red and the blue a little apart, more at the edges"},
			"lenticular": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.0, "live": true,
					"description": "rear projection: the screen's fine vertical lines (seen close to)"},
			"switching": {"type": "enum", "values": SWITCHING, "default": "auto", "live": true,
					"description": "how the set switches on and off: crt (a dot opens out to the picture; off, it "
					+ "collapses to a line and a dot that fades), valve (a slow warm-up, the picture brightening over "
					+ "seconds), panel (it just comes up and goes black), projection (a slow fade up); auto: by the "
					+ "display"},
			"warm_up": {"type": "float", "min": 0.0, "max": 30.0, "default": 0.0, "live": true,
					"description": "seconds the set takes to come on (0: its way's own: crt 1.6, valve 8, panel 0.9, "
					+ "projection 3)"},
			"starts_off": {"type": "bool", "default": false,
					"description": "the set is off (dark) until a cue switches it on; it comes on by itself when the "
					+ "film plays"},
			"off_dot": {"type": "float", "min": -1.0, "max": 12.0, "default": -1.0, "live": true,
					"description": "crt, valve: seconds the dot lingers once the picture has collapsed (-1: the way's "
					+ "own, 0: none). Sets before spot suppression burned one for seconds; later ones barely showed it"},
			"switch_sounds": {"type": "bool", "default": true, "live": true,
					"description": "the set's own sounds as it switches (a power switch's clunk, the valves' hum "
					+ "rising, the tube's faint tick as it collapses, a channel knob's clunk)"},
			"sound_db": {"type": "float", "min": -30.0, "max": 6.0, "default": 0.0, "live": true, "loudness": true,
					"description": "dB from the switch sounds' designed level"},
			"mask": {"type": "enum", "values": MASKS, "default": "shadow", "live": true,
					"description": "crt: the phosphors' mask: none (black and white), shadow (dot triads), grille "
					+ "(an aperture grille's stripes), slot"},
			"mask_pitch": {"type": "float", "min": 100.0, "max": 1200.0, "default": 420.0, "live": true,
					"description": "crt: the mask's triads across the width (fades out where finer than the "
					+ "headset can show)"},
			"mask_strength": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "crt: how much the mask shows"},
			"scanlines": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "crt: the dark gaps between the lines"},
			"glass": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.5, "live": true,
					"description": "crt and panel: the glass's reflection, a soft light that moves as the head moves"},
			"mech_lines": {"type": "int", "min": 12, "max": 120, "default": 30, "live": true,
					"description": "mechanical: the lines across the picture"},
			"panel_grid": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "panel: the gaps between the pixels (fades out where finer than the headset "
					+ "can show)"},
			"panel_pixels": {"type": "int", "min": 320, "max": 3840, "default": 1366, "live": true,
					"description": "panel: its pixels across"},
			"panel_bleed": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3, "live": true,
					"description": "panel: the backlight through the dark scenes, most at the corners"},
			"colour": {"type": "float", "min": 0.0, "max": 1.5, "default": 1.0, "live": true,
					"description": "the picture's colour: 0 black and white, 1 as it is, more richer"},
			"tint": {"type": "color", "default": [1.0, 1.0, 1.0], "live": true,
					"description": "the set's tint (a black and white tube's blue-white, a warm one)"},
			"gain": {"type": "float", "min": 0.5, "max": 1.5, "default": 1.0, "live": true, "brightness": true,
					"description": "the picture's brightness"},
			"speaker": {"type": "enum", "values": speakers, "default": "none", "live": true,
					"description": "the film's sound through a small speaker: " + "; ".join(speaker_text)},
		},
		"actions": {"glitch": "a moment's trouble: a tape's tracking tears, a broadcast's snow swells, a print "
				+ "jumps in the gate (args: seconds, default 0.6, at most 3)",
				"switch_on": "the set comes on from dark, its own way (args: seconds, else warm_up)",
				"switch_off": "the set goes dark, its own way: a tube collapses to a line and a dot with an "
				+ "afterglow, a panel goes black",
				"channel": "a channel change: the knob's clunk, the picture dips (a moment's snow on a tube; a "
				+ "panel goes black) and comes back (args: seconds, default 1, at least 0.9)"},
		"cost": {"draws": 0, "triangles": 0, "lights": 0, "particles": 0, "texture_mb": 0},
	}


var attached := false
## The speaker in use now ("none" or one of SPEAKERS).
var speaker_now := "none"
var _material: ShaderMaterial
## The screen's uniforms copied: name -> the value last copied.
var _names: Array[String] = []
var _copied := {}
var _given := {}
var _flat: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _weave := Vector2.ZERO
var _weave_target := Vector2.ZERO
var _flick := 0.0
var _flick_target := 0.0
var _flick_t := 0.0
var _frame := -1.0
var _clock := 0.0
## [x, strength, seconds left] per scratch.
var _scratches: Array = []
var _field := 0.0
var _glitch := 0.0
var _glitch_len := 0.6
var _film_send_was := &"Master"
## The set's power: "on", "off", "switching_on", "switching_off"; seconds into a switch and its length.
var power := "on"
var _power_t := 0.0
var _power_len := 1.0
## A tube's collapse in seconds while it switches off (0: no collapse, the light just fades).
var _off_collapse := 0.0
## True: the set stays off even while the film plays (time travel switches a set off before it moves on).
var stay_off := false
## A channel change: seconds left and its length.
var _channel := 0.0
var _channel_len := 1.0
## The screen's middle in the room (the switch sounds come from there).
var _screen_at: Variant = null
var _sound_task := -1
var _made_sounds := {}
var _pending_sounds: Array[String] = []
## Switch and channel sounds played (tests): [sound, volume_db] each.
var sounds_played: Array = []
var _cull_was := 0.0


func setup() -> void:
	_rng.seed = hash(id)
	_given = _document_params()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	for u: Dictionary in SHADER.get_shader_uniform_list():
		var n := str(u["name"])
		if not n.begins_with("pr_"):
			_names.append(n)
	for i in 4:
		_scratches.append([-1.0, 0.0, 0.0])
	_material.set_shader_parameter("pr_aspect", 16.0 / 9.0)
	if bool(params.get("starts_off", false)):
		power = "off"
	_apply()
	_prepare_sounds()


## The parameters the document gives this system (a value or a binding): they win over the preset.
func _document_params() -> Dictionary:
	if host == null:
		return {}
	for entry: Dictionary in host.doc.get("systems", []):
		if str(entry.get("id", entry["system"])) == id and entry.get("params") is Dictionary:
			return (entry["params"] as Dictionary).duplicate()
	return {}


## A parameter as it acts now: the document's (or its binding's, or a cue's on it), else the preset's (with the
## room's Motion and Flickering lights settings), else the default.
func value(param: String) -> Variant:
	if _given.has(param) or param == "preset":
		return params[param]
	var preset: Dictionary = PRESETS.get(str(params.get("preset", "none")), {}).get("params", {})
	if not preset.has(param):
		return params[param]
	var v: Variant = preset[param]
	var ps := param_spec(param)
	if ps.has("motion") and host != null:
		v = float(v) * clampf(float(host.setting("motion") if host.setting("motion") != null else 1.0), 0.0, 1.0)
	if bool(ps.get("flicker", false)) and host != null and host.setting("flicker") == false:
		v = ps.get("steady", 0.0)
	if ps["type"] == "color":
		return RoomSchemaRef.to_color(v)
	return v


static var _spec_cache := {}


## One parameter's spec (spec() built once).
static func param_spec(param: String) -> Dictionary:
	if _spec_cache.is_empty():
		_spec_cache = spec()
	return _spec_cache["params"].get(param, {})


func _f(param: String) -> float:
	return float(value(param))


## Whether a picture stage is on (the film is then drawn in the room). A set that is off or switching draws too.
func picture_on() -> bool:
	return power != "on" or _channel > 0.0 or str(value("source")) != "none" or str(value("display")) != "none" \
			or _f("snow") > 0.0 or _f("tube") > 0.0 or bool(value("mirror")) \
			or _f("ghost") > 0.0 or _f("weak") > 0.0 or not is_equal_approx(_f("colour"), 1.0) \
			or not color_value("tint").is_equal_approx(Color.WHITE) or not is_equal_approx(_f("gain"), 1.0)


func color_value(param: String) -> Color:
	var v: Variant = value(param)
	return v if v is Color else RoomSchemaRef.to_color(v)


func material() -> ShaderMaterial:
	return _material


func _param_changed(param: String, _value: Variant) -> void:
	if _material != null:
		_apply()
		if param in ["preset", "switching", "display", "switch_sounds"]:
			_prepare_sounds()


func act(action: String, args: Dictionary) -> void:
	match action:
		"glitch":
			_glitch_len = clampf(float(args.get("seconds", 0.6)), 0.1, 3.0)
			_glitch = _glitch_len
		"switch_on":
			switch_on(float(args.get("seconds", 0.0)))
		"switch_off":
			switch_off()
		"channel":
			change_channel(float(args.get("seconds", 1.0)))


## Every uniform of the stages from the parameters as they act now (the per-frame ones in tick()).
func _apply() -> void:
	var m := _material
	var source := SOURCES.find(str(value("source")))
	var display := DISPLAYS.find(str(value("display")))
	m.set_shader_parameter("pr_source", maxi(source, 0))
	m.set_shader_parameter("pr_display", maxi(display, 0))
	m.set_shader_parameter("pr_dust", _f("dust"))
	m.set_shader_parameter("pr_hotspot", _f("hotspot"))
	m.set_shader_parameter("pr_bleed", _f("chroma_bleed"))
	m.set_shader_parameter("pr_tape_noise", _f("tape_noise"))
	m.set_shader_parameter("pr_interlace", _f("interlace"))
	m.set_shader_parameter("pr_lines", float(value("lines")))
	m.set_shader_parameter("pr_ghost_shift", _f("ghost_shift"))
	m.set_shader_parameter("pr_weak", _f("weak"))
	m.set_shader_parameter("pr_curvature", _f("curvature"))
	m.set_shader_parameter("pr_corner", _f("corner"))
	m.set_shader_parameter("pr_tube", _f("tube"))
	m.set_shader_parameter("pr_mask", maxi(MASKS.find(str(value("mask"))), 0))
	m.set_shader_parameter("pr_mask_pitch", _f("mask_pitch"))
	m.set_shader_parameter("pr_mask_strength", _f("mask_strength"))
	m.set_shader_parameter("pr_scanlines", _f("scanlines"))
	m.set_shader_parameter("pr_glass", _f("glass"))
	m.set_shader_parameter("pr_mech_lines", float(value("mech_lines")))
	m.set_shader_parameter("pr_panel_grid", _f("panel_grid"))
	m.set_shader_parameter("pr_panel_pixels", float(value("panel_pixels")))
	m.set_shader_parameter("pr_panel_bleed", _f("panel_bleed"))
	m.set_shader_parameter("pr_colour", _f("colour"))
	var t := color_value("tint")
	m.set_shader_parameter("pr_tint", Vector3(t.r, t.g, t.b))
	m.set_shader_parameter("pr_gain", _f("gain"))
	m.set_shader_parameter("pr_aspect_mode", maxi(ASPECT_MODES.find(str(value("aspect_mode"))), 0))
	m.set_shader_parameter("pr_mirror", bool(value("mirror")))
	m.set_shader_parameter("pr_off_axis", _f("off_axis"))
	m.set_shader_parameter("pr_soft", _f("soft_focus"))
	m.set_shader_parameter("pr_convergence", _f("convergence"))
	m.set_shader_parameter("pr_lenticular", _f("lenticular"))
	var face := float(FACES.get(str(value("display")), 0.02))
	m.set_shader_parameter("pr_face", Vector3(face, face, face))
	# A rear projection's soft focus widens the screen's footprint filter: two taps a side are enough for a blur.
	_copied.erase("footprint_taps")
	if soft_taps():
		var taps: Variant = m.get_shader_parameter("footprint_taps")
		m.set_shader_parameter("footprint_taps", mini(int(taps) if taps != null else 3, 2))
	_apply_turn()
	_apply_glitch()
	_apply_power()


## The tilt and the overscan that keeps its corners off the screen (film only).
func _apply_turn(aspect := -1.0) -> void:
	if aspect <= 0.0:
		aspect = float(_material.get_shader_parameter("pr_aspect"))
	var a := deg_to_rad(_f("tilt")) if str(value("source")) == "film" else 0.0
	var fill := cos(absf(a)) + maxf(aspect, 1.0 / maxf(aspect, 0.01)) * sin(absf(a))
	_material.set_shader_parameter("pr_turn", Vector4(cos(a), sin(a), -sin(a), cos(a)) / fill)


## The parameters a glitch swells, now.
func _apply_glitch() -> void:
	var g := clampf(_glitch / maxf(_glitch_len, 0.01), 0.0, 1.0)
	var source := str(value("source"))
	_material.set_shader_parameter("pr_tracking", minf(_f("tracking") + (3.0 * g if source == "tape" else 0.0), 4.0))
	_material.set_shader_parameter("pr_head_switch", minf(_f("head_switch") + (g if source == "tape" else 0.0), 2.0))
	var tuning := 0.45 * _channel_dip() if not _panel_like() else 0.0
	_material.set_shader_parameter("pr_snow", minf(_f("snow") + (0.5 * g if source == "broadcast" else 0.0) + tuning,
			1.0))
	_material.set_shader_parameter("pr_ghost", _f("ghost"))


func tick(delta: float) -> void:
	if _material == null:
		return
	var main := main_node()
	_step_sounds()
	_step_power(delta)
	_attach(main, picture_on())
	_apply_speaker(str(value("speaker")))
	if not attached and main != null:
		return
	_clock += delta
	if _glitch > 0.0 or _channel > 0.0:
		_glitch = maxf(_glitch - delta, 0.0)
		_apply_glitch()
	var source := str(value("source"))
	# The film frame: from the film's position while one plays (the dust holds still on a pause), else the clock.
	var frame := floorf(_clock * FILM_FPS)
	if main != null and main.player.has_source():
		frame = floorf(float(main.player.get_position()) * FILM_FPS)
	var new_frame := frame != _frame
	_frame = frame
	_material.set_shader_parameter("pr_frame", fmod(frame, 997.0))
	if source == "film":
		_step_weave(new_frame)
		if new_frame:
			_step_scratches(1.0 / FILM_FPS)
	else:
		_material.set_shader_parameter("pr_weave", Vector2.ZERO)
	_step_flicker(delta)
	if _f("interlace") > 0.0:
		_field = 1.0 - _field
		_material.set_shader_parameter("pr_field", _field)
	if main != null:
		_copy_uniforms(main)


func _step_weave(new_frame: bool) -> void:
	var w := _f("weave")
	var g := clampf(_glitch / maxf(_glitch_len, 0.01), 0.0, 1.0)
	if w <= 0.0 and g <= 0.0:
		_weave = Vector2.ZERO
	elif new_frame:
		# A slow random walk towards a new target a few times a second, a little jitter each frame (as the
		# projector feature's weave, scripts/env/projector.gd); a glitch jumps it up for a moment.
		var amp := WEAVE_MAX * maxf(w, 3.0 * g)
		if _weave.distance_to(_weave_target) < amp * 0.05 or _rng.randf() < 3.0 / FILM_FPS:
			_weave_target = Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-1.0, 1.0)) * amp
		_weave = _weave.lerp(_weave_target, 0.3)
		_weave +=Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amp * 0.1
	_material.set_shader_parameter("pr_weave", _weave)


func _step_scratches(dt: float) -> void:
	var s := _f("scratches")
	var xs := Vector4(-1, -1, -1, -1)
	var amps := Vector4.ZERO
	for i in 4:
		var sc: Array = _scratches[i]
		sc[2] = float(sc[2]) - dt
		if float(sc[2]) <= 0.0:
			sc[1] = 0.0
			if s > 0.0 and _rng.randf() < s * 0.03:
				sc[0] = _rng.randf_range(0.05, 0.95)
				sc[1] = _rng.randf_range(0.3, 0.8) * s
				sc[2] = _rng.randf_range(0.5, 4.0)
		else:
			sc[0] = clampf(float(sc[0]) + _rng.randf_range(-0.0004, 0.0004), 0.0, 1.0)
		xs[i] = float(sc[0])
		amps[i] = float(sc[1])
	_material.set_shader_parameter("pr_scratch_x", xs)
	_material.set_shader_parameter("pr_scratch_a", amps)


func _step_flicker(delta: float) -> void:
	var f := _f("flicker")
	if f <= 0.0:
		_flick = 0.0
		_material.set_shader_parameter("pr_flicker", 1.0)
		return
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick_t = FLICKER_STEP
		_flick_target = _rng.randf_range(-1.0, 1.0)
	_flick = lerpf(_flick, _flick_target, 1.0 - exp(-delta / FLICKER_TAU))
	_material.set_shader_parameter("pr_flicker", 1.0 + f * FLICKER_DEPTH * _flick)


## The flicker's gain now (tests).
func flicker_gain() -> float:
	return float(_material.get_shader_parameter("pr_flicker"))


# --- Switching on and off, and the channel -----------------------------------------------------------------------------

## The way this set switches (SWITCH's keys): the document's or the preset's, else by its display.
func switch_style() -> String:
	var s := str(value("switching"))
	if SWITCH.has(s):
		return s
	match str(value("display")):
		"crt":
			return "crt"
		"mechanical":
			return "valve"
		"rear_projection":
			return "projection"
	return "panel"


func _panel_like() -> bool:
	return switch_style() == "panel"


## Comes on from dark (seconds: how long; 0: warm_up, else the way's own). Nothing while on or coming on.
func switch_on(seconds := 0.0) -> void:
	if power in ["on", "switching_on"]:
		return
	var style := switch_style()
	var length := seconds if seconds > 0.0 else _f("warm_up")
	if length <= 0.0:
		length = float(SWITCH[style]["on"])
	_power_len = maxf(length, float(SWITCH_MIN_ON[style]))
	_power_t = 0.0
	power = "switching_on"
	_channel = 0.0
	for s: String in SWITCH[style]["on_sounds"]:
		_play_sound(s)
	_apply_power()


## Goes dark its own way. Nothing while off or going off.
func switch_off() -> void:
	if power in ["off", "switching_off"]:
		return
	var style := switch_style()
	_off_collapse = 0.0
	_power_len = float(SWITCH[style]["off"])
	if style in OFF_COLLAPSE and str(value("display")) != "mechanical":
		# A tube: the collapse, then its era's dot (a mechanical set has no tube: its glow just dies).
		_off_collapse = float(OFF_COLLAPSE[style])
		var dot := _f("off_dot")
		_power_len = _off_collapse + (float(OFF_DOT[style]) if dot < 0.0 else dot)
	_power_t = 0.0
	power = "switching_off"
	_channel = 0.0
	for s: String in SWITCH[style]["off_sounds"]:
		_play_sound(s)
	_apply_power()


## A channel change: the knob's clunk, the picture dips and comes back (only while on).
func change_channel(seconds := 1.0) -> void:
	if power != "on":
		return
	_channel_len = clampf(seconds, 0.9, 3.0)
	_channel = _channel_len
	var s := str(SWITCH[switch_style()]["channel"])
	if s != "":
		_play_sound(s)
	_apply_glitch()
	_apply_power()


## 0..1: how far into its dip a channel change is (down over its first 30 %, back over its last 40 %).
func _channel_dip() -> float:
	if _channel <= 0.0:
		return 0.0
	var u := 1.0 - _channel / maxf(_channel_len, 0.01)
	return smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.6, 1.0, u))


func _step_power(delta: float) -> void:
	if power == "off" and not stay_off and host != null and host.get("timeline") != null and str(host.timeline.state) == "playing":
		# Never a dark set over a playing film: it comes on by itself.
		switch_on()
	if power in ["switching_on", "switching_off"]:
		_power_t += delta
		if _power_t >= _power_len:
			power = "on" if power == "switching_on" else "off"
		_apply_power()
	if _channel > 0.0:
		_channel = maxf(_channel - delta, 0.0)
		_apply_power()
		if _channel <= 0.0:
			_apply_glitch()


## The set's power now: [raster (its reach, 1, 1 the whole window), the picture's light, the beam's glow].
func power_now() -> Array:
	var style := switch_style()
	var u := clampf(_power_t / maxf(_power_len, 0.01), 0.0, 1.0)
	match power:
		"off":
			return [Vector2.ONE, 0.0, 0.0]
		"switching_on":
			match style:
				"crt":
					# A dot, the line opening out across, then the raster opening up and down.
					var rx := lerpf(0.012, 1.0, smoothstep(0.2, 0.4, u))
					var ry := lerpf(0.01, 1.0, smoothstep(0.4, 0.8, u))
					var spot := 0.7 * smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.4, 0.7, u))
					return [Vector2(rx, ry), smoothstep(0.15, 0.95, u), spot]
				"valve":
					# Dark while the heaters warm, then the picture comes up dim and a little small, growing.
					var r := lerpf(0.86, 1.0, smoothstep(0.15, 0.9, u))
					return [Vector2(r, r), pow(smoothstep(0.15, 1.0, u), 1.6), 0.0]
				"projection":
					return [Vector2.ONE, pow(smoothstep(0.1, 1.0, u), 1.3), 0.0]
			return [Vector2.ONE, smoothstep(0.3, 1.0, u), 0.0]
		"switching_off":
			if _off_collapse > 0.0:
				# Down to a line, across to a dot, and the dot held a while then fading: its era's seconds.
				var t := _power_t
				var k := _off_collapse
				var ry := lerpf(1.0, 0.01, smoothstep(0.0, 0.55 * k, t))
				var rx := lerpf(1.0, 0.012, smoothstep(0.55 * k, k, t))
				var dot := maxf(_power_len - k, 0.0)
				# Its fade takes at least 0.35 s (comfort: never a quick change), so a brief dot fades as the collapse ends.
				var span := maxf(0.7 * dot, 0.35)
				var fade := smoothstep(_power_len - span, _power_len, t)
				var spot := 0.75 * smoothstep(0.0, k, t) * (1.0 - fade)
				return [Vector2(rx, ry), 1.0 - smoothstep(0.2 * k, k, t), spot]
			return [Vector2.ONE, 1.0 - smoothstep(0.0, 1.0, u), 0.0]
	if _channel > 0.0:
		var depth := 1.0 if _panel_like() else 0.55
		return [Vector2.ONE, 1.0 - depth * _channel_dip(), 0.0]
	return [Vector2.ONE, 1.0, 0.0]


func _apply_power() -> void:
	if _material == null:
		return
	var now := power_now()
	var steady := power == "on" and _channel <= 0.0
	_material.set_shader_parameter("pr_switching", not steady)
	_material.set_shader_parameter("pr_raster", now[0])
	_material.set_shader_parameter("pr_power", now[1])
	_material.set_shader_parameter("pr_spot", now[2])


# --- The switch sounds ---------------------------------------------------------------------------------------------

## The sounds this set may make, made on a worker thread now (the valves' hum takes a moment).
func _prepare_sounds() -> void:
	if not bool(value("switch_sounds")):
		return
	var style := switch_style()
	var want: Array[String] = []
	for s: String in (SWITCH[style]["on_sounds"] as Array) + (SWITCH[style]["off_sounds"] as Array) \
			+ [SWITCH[style]["channel"]]:
		if s != "" and not EnvSynth.cached(s) and not (s in want):
			want.append(s)
	if want.is_empty() or _sound_task >= 0:
		return
	_sound_task = WorkerThreadPool.add_task(func() -> void:
		for s in want:
			_made_sounds[s] = EnvSynth.make(s), false, "presentation sounds")


func _finish_sounds() -> void:
	if _sound_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_sound_task)
	_sound_task = -1
	for s: String in _made_sounds:
		EnvSynth.put(s, _made_sounds[s])
	_made_sounds.clear()


func _step_sounds() -> void:
	if _sound_task >= 0 and WorkerThreadPool.is_task_completed(_sound_task):
		_finish_sounds()
	if _sound_task < 0 and not _pending_sounds.is_empty():
		var due := _pending_sounds.duplicate()
		_pending_sounds.clear()
		for s: String in due:
			_play_sound(s)


## Plays one of SWITCH_SOUNDS at the screen, at its designed level (sound_bed.gd LEVELS) and sound_db, lower while
## the film plays (as a sound bed's film_db), on the room's bus.
func _play_sound(sound: String) -> void:
	if not bool(value("switch_sounds")) or room == null:
		return
	if not EnvSynth.cached(sound):
		if _sound_task >= 0 and not WorkerThreadPool.is_task_completed(_sound_task):
			_pending_sounds.append(sound)
			return
		_finish_sounds()
	var w := EnvSynth.stream(sound)
	if w == null:
		return
	Acoustics.ensure_bus()
	var in_film := host != null and host.get("timeline") != null and str(host.timeline.state) in SoundBed.FILM_STATES
	var db := float(SoundBed.LEVELS.get(sound, -60.0)) + _f("sound_db") + (-8.0 if in_film else 0.0) \
			- EnvAudio.DEFAULT_DB - _level_of(sound, w)
	var p := AudioStreamPlayer3D.new()
	p.name = "%s_%s" % [id, sound]
	p.unit_size = 2.0
	p.max_db = 0.0
	p.attenuation_filter_db = 0.0
	p.position = _sound_place()
	p.bus = Acoustics.BUS
	p.stream = w
	p.volume_db = db
	own(p)
	p.finished.connect(func() -> void:
		_owned.erase(p)
		p.queue_free())
	p.play()
	sounds_played.append([sound, db])


static var _levels := {}


static func _level_of(sound: String, w: AudioStreamWAV) -> float:
	if not _levels.has(sound):
		_levels[sound] = EnvSynth.level_db(w)
	return float(_levels[sound])


## The screen's middle in the room: as the room last placed it, else the document's.
func _sound_place() -> Vector3:
	if _screen_at is Vector3:
		return _screen_at
	if host != null and host.doc.get("screen") is Dictionary:
		return RoomSchemaRef.vec3(host.doc["screen"].get("center", [0.0, 1.2, -2.0]))
	return Vector3(0.0, 1.2, -2.0)


func on_screen_changed(local: Transform3D, _size: Vector2) -> void:
	_screen_at = local.origin


# --- The screen -------------------------------------------------------------------------------------------------------

## The screen's flat mesh draws with this material while a picture stage is on; the film layer steps aside.
func _attach(main: Node, on: bool) -> void:
	if main == null or main.get("screen") == null:
		return
	if on == attached:
		return
	var screen: Node3D = main.screen
	var flat := screen.get_node_or_null("Flat") as MeshInstance3D
	if flat == null:
		return
	var layer: Node = main.features.get("film_layer") if main.get("features") != null else null
	if on:
		_flat = flat
		_copied.clear()
		_copy_uniforms(main)
		flat.material_override = _material
		# The quad may grow to the set's window in the shader: cull it by that.
		_cull_was = flat.extra_cull_margin
		flat.extra_cull_margin = maxf(_cull_was, 1.0)
		if layer != null and layer.has_method("request_scene"):
			layer.call("request_scene", _request_key(), true)
	else:
		_detach_screen(main)
	attached = on


func _detach_screen(main: Node) -> void:
	if _flat != null and is_instance_valid(_flat) and _flat.material_override == _material:
		_flat.material_override = main.screen.material if main != null else null
		_flat.extra_cull_margin = _cull_was
	_flat = null
	var layer: Node = null
	if main != null and is_instance_valid(main) and main.get("features") != null and is_instance_valid(main.features):
		layer = main.features.get("film_layer")
	if layer != null and is_instance_valid(layer) and layer.has_method("request_scene"):
		layer.call("request_scene", _request_key(), false)
	attached = false


## Whether the picture has noise of its own (a tape, a broadcast, snow, a mechanical set): the deband stays off.
func noisy() -> bool:
	return str(value("source")) in ["tape", "broadcast"] or str(value("display")) == "mechanical" \
			or _f("snow") > 0.0 or _f("weak") > 0.0


## Whether the soft focus takes the footprint filter down to two taps a side (a rear projection, soft).
func soft_taps() -> bool:
	return str(value("display")) == "rear_projection" and _f("soft_focus") > 0.0


func _request_key() -> String:
	return "presentation:%d" % get_instance_id()


## The screen's own uniforms (the picture, the projection, the controls) that changed since the last frame, and the
## picture's aspect. The deband stays off under noise (the noise hides the bands, and it saves eight samples).
func _copy_uniforms(main: Node) -> void:
	var src: ShaderMaterial = main.screen.material
	var no_deband := noisy()
	for n in _names:
		var v: Variant = src.get_shader_parameter(n)
		if n == "pc_deband" and no_deband:
			v = 0.0
		if n == "footprint_taps" and soft_taps():
			v = mini(int(v), 2)
		if _copied.has(n) and typeof(_copied[n]) == typeof(v) and _copied[n] == v:
			continue
		_copied[n] = v
		_material.set_shader_parameter(n, v)
	var size: Vector2 = main.screen.get_flat_size()
	var aspect := size.x / maxf(size.y, 0.001)
	if not is_equal_approx(aspect, float(_material.get_shader_parameter("pr_aspect"))):
		_material.set_shader_parameter("pr_aspect", aspect)
		_apply_turn(aspect)


# --- The speaker ------------------------------------------------------------------------------------------------------

## The film's sound through `speaker` ("none": straight to Master, as always).
func _apply_speaker(speaker: String) -> void:
	if not SPEAKERS.has(speaker):
		speaker = "none"
	if speaker == speaker_now:
		return
	EnvAudio.ensure_buses()
	var bus := speaker_bus()
	var film := AudioServer.get_bus_index(EnvAudio.FILM)
	if bus < 0 or film < 0:
		return
	while AudioServer.get_bus_effect_count(bus) > 0:
		AudioServer.remove_bus_effect(bus, 0)
	if speaker == "none":
		AudioServer.lock()
		AudioServer.set_bus_send(film, _film_send_was)
		AudioServer.unlock()
		speaker_now = speaker
		return
	var s: Dictionary = SPEAKERS[speaker]
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = float(s["high"])
	hp.db = (int(s["slope"]) - 1) as AudioEffectFilter.FilterDB
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = float(s["low"])
	lp.db = (int(s["slope"]) - 1) as AudioEffectFilter.FilterDB
	var eq := AudioEffectEQ6.new()
	for i in 6:
		eq.set_band_gain_db(i, float(s["eq"][i]))
	var fx: Array[AudioEffect] = [hp, lp, eq]
	if float(s["drive"]) > 0.0:
		var d := AudioEffectDistortion.new()
		d.mode = AudioEffectDistortion.MODE_WAVESHAPE
		d.drive = float(s["drive"])
		fx.append(d)
	if float(s["width"]) < 1.0:
		var w := AudioEffectStereoEnhance.new()
		w.pan_pullout = float(s["width"])
		fx.append(w)
	for e in fx:
		AudioServer.add_bus_effect(bus, e)
	if speaker_now == "none":
		var was := AudioServer.get_bus_send(film)
		_film_send_was = was if was != SPEAKER_BUS else &"Master"
	AudioServer.lock()
	AudioServer.set_bus_send(film, SPEAKER_BUS)
	AudioServer.unlock()
	speaker_now = speaker


## The speaker's bus, made once just before Film (a bus sends only to one before it); -1 without a Film bus.
static func speaker_bus() -> int:
	var i := AudioServer.get_bus_index(SPEAKER_BUS)
	if i >= 0:
		return i
	var film := AudioServer.get_bus_index(EnvAudio.FILM)
	if film < 1:
		return -1
	AudioServer.lock()
	AudioServer.add_bus(film)
	AudioServer.set_bus_name(film, SPEAKER_BUS)
	AudioServer.set_bus_send(film, &"Master")
	AudioServer.unlock()
	return AudioServer.get_bus_index(SPEAKER_BUS)


func _exit_tree() -> void:
	_finish_sounds()
	_apply_speaker("none")
	var main := main_node()
	if attached or _flat != null:
		_detach_screen(main)
