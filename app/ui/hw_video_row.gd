extends VBoxContainer

## The System tab's row for hardware 10-bit video (scripts/play/hw_video.gd): "Hardware 10-bit video: on (P010 from
## the system's video driver) / on (Q10C through the GPU, stock driver) / off: 10-bit plays in software", and Details
## (the decoder's formats, a Q10C failure in this run, hardware VP9). Read-only: nothing to set up.

const W := preload("res://ui/pane_widgets.gd")

var hw: Node
var _label: Label
var _details_button: Button
var _details: Label


func _init() -> void:
	name = "HwVideoRow"
	add_theme_constant_override("separation", 4)


func bind(p_hw: Node) -> void:
	hw = p_hw
	_label = W.ellipsis(W.label(""))
	_details_button = W.toggle("Details", func(on: bool) -> void:
		_details.visible = on
		refresh())
	add_child(W.hbox([_label, _details_button]))
	_details = W.label("", &"MutedLabel")
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.visible = false
	add_child(_details)
	hw.changed.connect(refresh)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())
	refresh()


func refresh() -> void:
	var s: Dictionary = hw.status()
	_label.text = "Hardware 10-bit video: %s" % s["text"]
	if _details.visible:
		_details.text = details_text(s)


## The status in words (Details).
static func details_text(s: Dictionary) -> String:
	var yes_no := func(v: Variant) -> String: return "yes" if bool(v) else "no"
	var lines: Array[String] = [
		"The system's video driver offers P010: %s" % yes_no.call(s.get("p010")),
		"The GPU reads the stock driver's Q10C: %s" % yes_no.call(s.get("q10c")),
	]
	if str(s.get("q10c_off_reason", "")) != "":
		lines.append("Q10C is off until the player restarts: %s" % s["q10c_off_reason"])
	if str(s.get("decoder_formats", "")) != "":
		lines.append("Decoder formats: %s" % s["decoder_formats"])
	lines.append("VP9 in hardware: %s" % yes_no.call(s.get("hw_vp9")))
	return "\n".join(lines)
