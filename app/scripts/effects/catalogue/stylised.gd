extends RefCounted

## The stylised effects (shaders/fx/fx_stylised.gdshader): drawn looks, pencil hatching, comic halftone, retro pixels,
## a glowing wireframe, stained glass and a two-colour tone. All still and opaque. Their patterns are fixed to the
## part (its own space or its UV) and fade to their average tone where too fine for the pixels; the previews use a
## coarser pitch than the defaults (a 160-pixel sphere of 2 m), so the pattern shows.

const SHADER := "res://shaders/fx/fx_stylised.gdshader"

const EFFECTS := {
	"hatching": {
		"name": "Pencil hatching",
		"description": "a pencil drawing: strokes crossing in more layers as the shade deepens, a soft contour, on "
				+ "white paper or the surface's colour; sketchbook, storyboard and drawn rooms",
		"tags": ["stylised", "drawn", "pencil", "sketch", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 2.1,
		"define": "FX_HATCHING",
		"preview_options": {"pitch": 0.1},
		"options": {
			"color": {"type": "color", "default": "#2a2a33", "description": "the pencil's colour",
				"uniform": "fx_color"},
			"paper": {"type": "enum", "values": ["white", "surface"], "default": "white",
				"description": "white: drawn on paper-white; surface: drawn over the surface's own colour",
				"uniform": "fx_mode"},
			"pitch": {"type": "float", "min": 0.005, "max": 0.2, "default": 0.025,
				"description": "metres between strokes; finer looks more like pencil, coarser like ink pen",
				"uniform": "fx_scale"},
			"strength": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.9,
				"description": "how dark the strokes are", "uniform": "fx_strength"}}},
	"halftone": {
		"name": "Halftone",
		"description": "comic print: dots of the surface's colour on paper, small in the light and growing to merge "
				+ "in the shade; pop-art and comic-book rooms",
		"tags": ["stylised", "comic", "print", "dots", "retro"],
		"layers": true, "cost": "light", "cost_ratio": 1.63,
		"define": "FX_HALFTONE",
		"preview_options": {"pitch": 0.12},
		"options": {
			"pitch": {"type": "float", "min": 0.005, "max": 0.2, "default": 0.03,
				"description": "metres between dots", "uniform": "fx_scale"},
			"paper": {"type": "color", "default": "#f2ead8", "description": "the paper's colour between the dots",
				"uniform": "fx_color2"}}},
	"pixel": {
		"name": "Retro pixels",
		"description": "chunky retro pixels: the surface's colour and picture in square cells with a few hard light "
				+ "steps and few colours; game rooms, arcades, a low-resolution look",
		"tags": ["stylised", "retro", "pixel", "game"],
		"layers": true, "cost": "light", "cost_ratio": 1.21,
		"define": "FX_PIXEL",
		"options": {
			"cells": {"type": "float", "min": 4.0, "max": 128.0, "default": 32.0,
				"description": "cells across the part's picture (its UV); fewer is chunkier", "uniform": "fx_scale"},
			"levels": {"type": "int", "min": 2, "max": 8, "default": 3,
				"description": "hard steps of light and shade (and tones of a green or amber palette); fewer is "
						+ "more retro", "uniform": "px_levels"},
			"palette": {"type": "enum", "values": ["any", "eight", "green", "amber"], "default": "any",
				"description": "any: the surface's own colours; eight: eight fixed colours; green or amber: tones "
						+ "of one colour, as an old monochrome screen", "uniform": "fx_mode"},
			"grid": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.3,
				"description": "how visible the thin gaps between cells are", "uniform": "fx_param"}}},
	"wireframe": {
		"name": "Wireframe",
		"description": "a glowing grid traced over dark faces, as a part drawn by a computer; science fiction, "
				+ "blueprints, a part not yet built",
		"tags": ["stylised", "sci-fi", "glow", "grid", "lines"],
		"layers": false, "cost": "light", "cost_ratio": 1.28,
		"define": "FX_WIREFRAME",
		"preview_options": {"pitch": 0.25},
		"options": {
			"color": {"type": "color", "default": "#46d8ff", "description": "the lines' glow", "uniform": "fx_color"},
			"pitch": {"type": "float", "min": 0.02, "max": 1.0, "default": 0.1,
				"description": "metres between grid lines, along the part's own axes", "uniform": "fx_scale"},
			"strength": {"type": "float", "min": 0.0, "max": 2.0, "default": 1.0,
				"description": "how bright the lines are", "uniform": "fx_strength"},
			"faces": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.15,
				"description": "how much of the surface's own colour shows between the lines (0: black)",
				"uniform": "fx_param"}}},
	"stained_glass": {
		"name": "Stained glass",
		"description": "panes of coloured glass in dark lead, lit from behind and brighter facing the screen; "
				+ "windows, lamps, a chapel or a calm jewel-toned room",
		"tags": ["stylised", "glass", "glow", "colourful", "calm"],
		"layers": false, "cost": "medium", "cost_ratio": 2.86,
		"define": "FX_STAINED_GLASS",
		"preview_options": {"cell": 0.3},
		"options": {
			"palette": {"type": "enum", "values": ["jewel", "warm", "cool", "surface"], "default": "jewel",
				"description": "jewel: ruby, sapphire, emerald, amber, amethyst; warm or cool tones; surface: "
						+ "lighter and darker panes of the surface's colour", "uniform": "fx_mode"},
			"cell": {"type": "float", "min": 0.02, "max": 1.0, "default": 0.12,
				"description": "metres across a pane", "uniform": "fx_scale"},
			"strength": {"type": "float", "min": 0.2, "max": 2.0, "default": 1.0,
				"description": "how bright the light through the glass is", "uniform": "fx_strength"}}},
	"duotone": {
		"name": "Duotone",
		"description": "two colours only: the surface's shade and picture mapped from a shadow colour to a highlight "
				+ "colour; poster-like, moody, ties a room to two colours",
		"tags": ["stylised", "poster", "colour", "calm"],
		"layers": true, "cost": "light", "cost_ratio": 1.17,
		"define": "FX_DUOTONE",
		"options": {
			"shadow": {"type": "color", "default": "#24204f", "description": "the colour of the dark tones",
				"uniform": "fx_color"},
			"highlight": {"type": "color", "default": "#ffb978", "description": "the colour of the light tones",
				"uniform": "fx_color2"},
			"contrast": {"type": "float", "min": 0.0, "max": 1.0, "default": 0.4,
				"description": "0: a soft gradient; 1: nearly two flat colours", "uniform": "fx_param"}}},
}
