extends RefCounted

## Help lines (docs/ui-design.md, "Revision 2", "Help lines"): one short line in plain words under each control whose
## name does not say what it does. The texts live here, one dictionary per tab, keyed by the control's visible name
## (a slider row's name, a button's or toggle's caption, or a label next to a row of choices). attach() finds those
## controls in a built tab and puts a line under each: under a slider row its text alone, under a row of buttons
## "Name: text" for each button that has one. A line shows and hides with its control. Styled by the theme (the muted
## label); no colour or font here.
##
## Written so far: the Picture and Sound tabs. The other tabs get theirs as the user names what is unclear.
##
## Languages (docs/i18n.md): the keys are the controls' English names (what their text property holds, in any
## language); the lines are translated where they show: a line alone translates itself, "Name: text" is built with
## tr() and built again when the language changes.

const W := preload("res://ui/pane_widgets.gd")

# i18n: begin
const PICTURE := {
	"Auto": "Guess the 3D layout and shape from the file name and picture size.",
	"Half": "Each eye is squeezed to half width or height in the file: stretch it.",
	"Swap eyes": "Swap left and right if the 3D looks inside out or hurts.",
	"Use for this folder": "Open every file in this folder with this mode.",
	"Clear folder rule": "Forget the mode set for this folder.",
	"Fisheye field": "How wide the fisheye lens was. Wrong: straight lines bend.",
	"Lens field": "How wide each lens sees. Wrong: things double at the join.",
	"Seam": "Slides the back picture sideways until the two halves meet at the join.",
	"Depth": "Moves the whole 3D picture nearer or farther. Use it if 3D strains your eyes.",
	"This file only": "Keep this depth for this file only.",
	"Soft edges": "Fades the sides of 3D, so the frame does not cut what comes out.",
	"Size": "How wide the screen is.",
	"Distance": "How far away the screen is.",
	"Height": "Moves the screen up or down.",
	"Curvature": "Bends the screen around you. 100 % wraps it evenly around your seat.",
	"Zoom": "Enlarges the picture inside the screen (crops the edges).",
	"Size in degrees": "How much of your view the screen fills, whatever its distance.",
	"Follow my head": "The screen comes back in front of you after you look away.",
	"Lying down": "Turns the screen to face you when you lie back (this session).",
	"Reset zoom": "Shows the whole picture again.",
	"Auto crop bars": "Finds black bars above and below the film and removes them.",
	"Grow the screen to keep its height": "Without bars, widen the screen.",
	"Pitch": "Tilts a 180° or 360° picture up or down if the camera was not level.",
	"Roll": "Turns a 180° or 360° picture if the horizon is crooked.",
	"Level": "Removes the pitch and roll corrections.",
	"Brightness": "Lighter or darker overall.",
	"Contrast": "More or less difference between light and dark.",
	"Saturation": "More or less colour. 0 is black and white.",
	"Gamma": "Lighter or darker mid tones, without changing black and white.",
	"Dark-scene lift": "Makes dark scenes easier to see by lifting the darkest parts.",
	"Sharpen": "Crisper edges. Too much makes a halo around them.",
	"Smooth banding": "Hides the steps in dark gradients. Too much softens faint detail.",
	"Deinterlace": "Removes comb lines from old TV or DVD video. Auto: when needed.",
	"Film grain": "Adds the fine noise of projected film.",
	"Gate weave": "Adds the small sideways wobble of film in an old projector.",
	"Reset picture": "Brightness, contrast and the rest back to normal.",
	"Tone map": "Fits bright HDR parts to the headset. Off clips them.",
	"Exposure": "Brighter or darker HDR picture.",
	"Knee": "Where the brightest parts start to compress. Higher: more highlight detail.",
	"HDR brightness": "How bright white is. Lower makes the HDR picture brighter.",
	"Each picture": "How long each photo shows in the slideshow.",
	"Crossfade": "How long one photo fades into the next.",
	"Mark A / B": "Press at the start and the end of a part to repeat it.",
	"Corner size": "How big the small film in the corner is.",
}

const SOUND := {
	"Volume": "How loud the film is.",
	"A/V offset": "Moves the sound earlier or later if lips and voices do not match.",
	"Calibrate": "Opens a test that helps you find the correct offset.",
	"Live delay": "Live streams: shorter is nearer to live, longer has fewer gaps.",
	"Night mode": "Loud scenes quieter, quiet speech louder: for late at night.",
	"Evening out": "How strongly night mode evens out loud and quiet.",
	"Dialogue boost": "Makes voices louder. Only for 5.1 sound and more.",
	"Spatial sound": "Sound from speakers around you and above you, not inside your head.",
	"Bass channel": "Plays the film's separate bass channel (the .1 of 5.1) too.",
	"Room echo and reverb": "The room's echoes and reverb. Off: dry sound, the film only. 100 %: the room as it is built; more: the speakers seem farther.",
	"Auto": "The headset sees what the sound plays on: its own speakers or headphones.",
	"Headset speakers": "Settings for the headset's own speakers.",
	"Headphones": "Settings for earbuds or headphones.",
	"Tune spatial sound": "Hear a sound two ways, pick the better; it then fits your ears.",
	"Play sound on a PC": "The sound plays on a PC, in time with the picture.",
}
# i18n: end

const TABS := {"picture": PICTURE, "sound": SOUND}


## Puts the help lines of `tab` ("picture", "sound") under its controls in `root`. Returns how many it added.
static func attach(root: Control, tab: String) -> int:
	var texts: Dictionary = TABS.get(tab, {})
	if texts.is_empty():
		return 0
	# [target, anchor, text, caption ("" for a line alone)]: found first, inserted after, so the walk sees no new
	# nodes.
	var found: Array = []
	_find(root, texts, found)
	var after := {}
	for f: Array in found:
		var target: Control = f[0]
		var anchor: Control = f[1]
		var text: String = f[2]
		var caption: String = f[3]
		var line := W.help(text) if caption == "" else W.help("", func() -> String:
			return TranslationServer.translate("%s: %s") % [TranslationServer.translate(caption),
					TranslationServer.translate(text)])
		var parent := anchor.get_parent()
		parent.add_child(line)
		# Several lines under one row of buttons keep the buttons' order.
		var at: int = after.get(anchor, anchor.get_index()) + 1
		parent.move_child(line, at)
		after[anchor] = at
		line.visible = target.visible
		target.visibility_changed.connect(func() -> void: line.visible = target.visible)
	return found.size()


static func _find(node: Node, texts: Dictionary, found: Array) -> void:
	for c in node.get_children():
		if c is Control and (c as Control).has_meta("help"):
			continue
		# A slider row (W.slider_row()): the name over the slider (a VBox since the tablet's cards), or beside it.
		if c is BoxContainer and c.has_meta("slider"):
			var first: Node = c.get_child(0)
			var name_label := (first.get_child(0) if first is HBoxContainer else first) as Label
			if name_label != null and texts.has(name_label.text):
				found.append([c, c, str(texts[name_label.text]), ""])
			continue
		# Not section titles (the caps label) and not one choice of a row of choices (its own words say it).
		var skip: bool = (c is Label and (c as Label).theme_type_variation == &"CapsLabel") \
				or (c is Button and (c as Button).button_group != null)
		if not skip and (c is Button or c is Label) and texts.has(str(c.get("text"))):
			var caption := str(c.get("text"))
			var parent := c.get_parent()
			if parent is HBoxContainer:
				found.append([c, parent, str(texts[caption]), caption])
			else:
				found.append([c, c, str(texts[caption]), ""])
			continue
		_find(c, texts, found)
