extends Node

## #72 hand tracking spike (--hands; docs/xr-spikes.md). Untested on the device.
##
## For each hand: an XRNode3D on the runtime's hand tracker ("/user/hand_tracker/left" | "right"), a Skeleton3D built
## here with the bone names XRHandModifier3D looks for ("LeftThumbTip", ...), the XRHandModifier3D that poses it, and
## a dot on every joint (BoneAttachment3D). No hand mesh: the spike shows where the joints are.
##
## Input, only while that hand holds no controller: a pinch (thumb tip to index tip) is the trigger, and the index
## finger is the aim pose, written to the controller's own tracker ("left_hand" | "right_hand"). So the pane's laser,
## clicks, and play / pause work unchanged (xr_hand.gd reads the tracker). A hand counts as holding a controller when
## the runtime moved that tracker's aim pose since we last wrote it, or when the hand tracker says its data comes from
## a controller.

const HAND_JOINTS := ["Palm", "Hand", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip",
		"IndexMetacarpal", "IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip",
		"MiddleMetacarpal", "MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip",
		"RingMetacarpal", "RingProximal", "RingIntermediate", "RingDistal", "RingTip",
		"LittleMetacarpal", "LittleProximal", "LittleIntermediate", "LittleDistal", "LittleTip"]
## Pinch with hysteresis: thumb tip to index tip, metres.
const PINCH_ON := 0.015
const PINCH_OFF := 0.03
## The aim direction holds still this long after a pinch starts or ends (the finger moves while pinching).
const AIM_HOLD := 0.25
## The aim follows the finger smoothly (fraction per frame at 90 Hz).
const AIM_SMOOTH := 0.35
const DOT_COLOR := Color(0.55, 0.8, 1.0, 0.85)

var origin: Node3D
var hands := {}


class Hand:
	var side := ""
	var tracker_name := &""
	var controller_name := &""
	var node: XRNode3D
	var skeleton: Skeleton3D
	var pinched := false
	var aim_dir := Vector3.FORWARD
	var hold := 0.0
	var written := Transform3D()
	var have_written := false
	var feeding := false


func _ready() -> void:
	process_priority = -100  # before the controller nodes read their trackers
	for side in ["left", "right"]:
		hands[side] = _make_hand(side)
	print("Hands: skeletons on /user/hand_tracker/left and right; pinch = trigger, index finger = laser")


func _make_hand(side: String) -> Hand:
	var h := Hand.new()
	h.side = side
	h.tracker_name = StringName("/user/hand_tracker/" + side)
	h.controller_name = StringName(side + "_hand")
	h.node = XRNode3D.new()
	h.node.name = side.capitalize() + "HandTracking"
	h.node.tracker = h.tracker_name
	h.node.pose = &"default"
	h.node.show_when_tracked = true
	origin.add_child(h.node)
	h.skeleton = build_skeleton(side)
	h.node.add_child(h.skeleton)
	var mod := XRHandModifier3D.new()
	mod.hand_tracker = h.tracker_name
	mod.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	h.skeleton.add_child(mod)
	_add_dots(h.skeleton, side)
	return h


## A skeleton with one bone per hand joint, named as XRHandModifier3D expects: the wrist ("Hand") is the root, the
## palm and each finger's metacarpal hang from it, each finger a chain to its tip. Rest poses are identity: the
## modifier sets every bone's position and rotation from the tracker.
static func build_skeleton(side: String) -> Skeleton3D:
	var prefix := "Left" if side == "left" else "Right"
	var sk := Skeleton3D.new()
	sk.name = prefix + "HandSkeleton"
	var ids := {}
	for j: String in HAND_JOINTS:
		ids[j] = sk.add_bone(prefix + j)
	for j: String in HAND_JOINTS:
		var parent := ""
		if j == "Palm" or j.ends_with("Metacarpal"):
			parent = "Hand"
		elif j != "Hand":
			var finger := _finger(j)
			var chain: Array = ["Metacarpal", "Proximal", "Intermediate", "Distal", "Tip"] if finger != "Thumb" \
					else ["Metacarpal", "Proximal", "Distal", "Tip"]
			parent = finger + chain[chain.find(j.trim_prefix(finger)) - 1]
		if parent != "":
			sk.set_bone_parent(ids[j], ids[parent])
	return sk


static func _finger(joint: String) -> String:
	for f in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		if joint.begins_with(f):
			return f
	return ""


func _add_dots(sk: Skeleton3D, side: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = DOT_COLOR
	var prefix := "Left" if side == "left" else "Right"
	for j: String in HAND_JOINTS:
		var att := BoneAttachment3D.new()
		att.bone_name = prefix + j
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.006 if j.ends_with("Tip") else 0.008
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		dot.mesh = sphere
		dot.material_override = mat
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(dot)
		sk.add_child(att)


func _process(delta: float) -> void:
	for h: Hand in hands.values():
		_update_input(h, delta)


func _update_input(h: Hand, delta: float) -> void:
	var ht := XRServer.get_tracker(h.tracker_name) as XRHandTracker
	if ht == null or not ht.has_tracking_data:
		_stop_feeding(h)
		return
	var ct := _controller_tracker(h)
	if ht.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER or _runtime_moved(h, ct):
		_stop_feeding(h)
		return
	var thumb := ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var tip := ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var knuckle := ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL).origin
	var gap := thumb.distance_to(tip)
	var was := h.pinched
	if not h.pinched and gap < PINCH_ON:
		h.pinched = true
	elif h.pinched and gap > PINCH_OFF:
		h.pinched = false
	if was != h.pinched:
		h.hold = AIM_HOLD
	h.hold = maxf(h.hold - delta, 0.0)
	var want := (tip - knuckle).normalized()
	if want.length() > 0.5 and h.hold <= 0.0:
		h.aim_dir = h.aim_dir.slerp(want, AIM_SMOOTH).normalized() if h.feeding else want
	var aim := Transform3D(Basis.looking_at(h.aim_dir, Vector3.UP if absf(h.aim_dir.y) < 0.95 else Vector3.BACK),
			knuckle)
	ct.set_pose(&"aim", aim, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	ct.set_input(&"trigger", 1.0 if h.pinched else 0.0)
	h.written = aim
	h.have_written = true
	h.feeding = true


func _stop_feeding(h: Hand) -> void:
	if not h.feeding:
		return
	h.feeding = false
	h.have_written = false
	var ct := XRServer.get_tracker(h.controller_name) as XRPositionalTracker
	if ct != null:
		ct.set_input(&"trigger", 0.0)
	h.pinched = false


## The controller tracker of this hand; made when there is none (a desktop test).
func _controller_tracker(h: Hand) -> XRPositionalTracker:
	var ct := XRServer.get_tracker(h.controller_name) as XRPositionalTracker
	if ct == null:
		ct = XRControllerTracker.new()
		ct.name = h.controller_name
		ct.hand = XRPositionalTracker.TRACKER_HAND_LEFT if h.side == "left" else XRPositionalTracker.TRACKER_HAND_RIGHT
		XRServer.add_tracker(ct)
	return ct


## True when something other than us set the aim pose since our last write: the runtime, from a held controller.
func _runtime_moved(h: Hand, ct: XRPositionalTracker) -> bool:
	var p := ct.get_pose(&"aim")
	if p == null or not p.has_tracking_data:
		return false
	return not h.have_written or not p.transform.is_equal_approx(h.written)


## For tests and the status line: {side: {feeding, pinched}}.
func state() -> Dictionary:
	var out := {}
	for h: Hand in hands.values():
		out[h.side] = {"feeding": h.feeding, "pinched": h.pinched}
	return out
