extends SceneTree

## The --hands spike (scripts/xr_spikes/) without a headset: a fake hand tracker drives the skeleton through
## XRHandModifier3D, a pinch presses the trigger on the controller tracker, a moving controller pose stops the hand
## input; and the override file that switches hand tracking on for the next start.
## godot --headless --xr-mode off --path app --script res://tests/test_hands.gd

const Hands := preload("res://scripts/xr_spikes/hands.gd")
const Spikes := preload("res://scripts/xr_spikes/xr_spikes.gd")


var _fails := 0
var _ht: XRHandTracker
var _palm := Transform3D(Basis(), Vector3(0.2, 1.0, -0.3))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_skeleton()
	_test_override()
	await _test_hands()
	print("test_hands: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _test_skeleton() -> void:
	var sk := Hands.build_skeleton("right")
	_check(sk.get_bone_count() == 26, "26 bones (%d)" % sk.get_bone_count())
	var b := func(n: String) -> int: return sk.find_bone("Right" + n)
	_check(sk.get_bone_parent(b.call("Hand")) == -1, "the wrist is the root")
	_check(sk.get_bone_parent(b.call("Palm")) == b.call("Hand"), "palm under the wrist")
	_check(sk.get_bone_parent(b.call("ThumbMetacarpal")) == b.call("Hand"), "thumb metacarpal under the wrist")
	_check(sk.get_bone_parent(b.call("ThumbTip")) == b.call("ThumbDistal"), "thumb has no intermediate")
	_check(sk.get_bone_parent(b.call("IndexTip")) == b.call("IndexDistal"), "index tip under distal")
	_check(sk.get_bone_parent(b.call("LittleIntermediate")) == b.call("LittleProximal"), "little chain")
	sk.free()


func _test_override() -> void:
	var path := ProjectSettings.globalize_path(Spikes.OVERRIDE)
	# A real override in this user folder is put back afterwards.
	var saved := PackedByteArray()
	if FileAccess.file_exists(Spikes.OVERRIDE):
		saved = FileAccess.get_file_as_bytes(Spikes.OVERRIDE)
	if FileAccess.file_exists(Spikes.OVERRIDE):
		DirAccess.remove_absolute(path)
	Spikes._set_override(true)
	var cfg := ConfigFile.new()
	_check(cfg.load(Spikes.OVERRIDE) == OK and cfg.get_value("xr", "openxr/extensions/hand_tracking", false) == true,
			"override written with hand tracking on")
	_check(cfg.get_value("xr", "openxr/extensions/hand_tracking_unobstructed_data_source", false) == true,
			"override asks for the data source")
	Spikes._set_override(false)
	_check(not FileAccess.file_exists(Spikes.OVERRIDE), "override removed without --hands")
	# A file with other settings in it is never touched.
	var other := ConfigFile.new()
	other.set_value("rendering", "something", 1)
	other.save(Spikes.OVERRIDE)
	Spikes._set_override(false)
	Spikes._set_override(true)
	var again := ConfigFile.new()
	again.load(Spikes.OVERRIDE)
	_check(again.has_section_key("rendering", "something") and not again.has_section("xr"), "a foreign file is kept")
	DirAccess.remove_absolute(path)
	if not saved.is_empty():
		var f := FileAccess.open(Spikes.OVERRIDE, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()


## An open right hand at the palm pose, index pointing ahead (-Z); `pinch` puts the thumb tip on the index tip.
func _pose_hand(pinch: bool) -> void:
	var at := {}
	var fingers := {"Index": -0.02, "Middle": 0.0, "Ring": 0.02, "Little": 0.04}
	at[XRHandTracker.HAND_JOINT_PALM] = Vector3.ZERO
	at[XRHandTracker.HAND_JOINT_WRIST] = Vector3(0, 0, 0.05)
	var base: int = XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL
	var k := 0
	for f: String in fingers:
		for i in 5:
			at[base + k * 5 + i] = Vector3(fingers[f], 0, 0.03 - i * 0.025)
		k += 1
	for i in 4:
		at[XRHandTracker.HAND_JOINT_THUMB_METACARPAL + i] = Vector3(-0.03 - i * 0.01, -0.01, 0.02 - i * 0.02)
	if pinch:
		at[XRHandTracker.HAND_JOINT_THUMB_TIP] = at[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP] + Vector3(0, -0.005, 0)
	var flags := XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED \
			| XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED
	for j: int in at:
		_ht.set_hand_joint_transform(j, Transform3D(Basis(), _palm * at[j]))
		_ht.set_hand_joint_flags(j, flags)
		_ht.set_hand_joint_radius(j, 0.008)
	_ht.set_pose(&"default", _palm, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _test_hands() -> void:
	_ht = XRHandTracker.new()
	_ht.name = &"/user/hand_tracker/right"
	_ht.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	_ht.has_tracking_data = true
	_ht.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	_pose_hand(false)
	XRServer.add_tracker(_ht)
	var origin := XROrigin3D.new()
	root.add_child(origin)
	var hands: Node = Hands.new()
	hands.origin = origin
	root.add_child(hands)
	await _frames(4)

	var sk: Skeleton3D = origin.find_child("RightHandSkeleton", true, false)
	_check(sk != null, "right skeleton made")
	if sk != null:
		var want := _ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
		var dot: Node3D = null
		for att: BoneAttachment3D in sk.find_children("*", "BoneAttachment3D", false, false):
			if att.bone_name == "RightIndexTip":
				dot = att
		var tip := dot.global_position if dot != null else Vector3.INF
		_check(tip.distance_to(want) < 0.002, "index tip dot at the joint (%.4f m off)" % tip.distance_to(want))
		var dots := sk.find_children("*", "BoneAttachment3D", false, false).size()
		_check(dots == 26, "a dot per joint (%d)" % dots)

	var ct := XRServer.get_tracker(&"right_hand") as XRPositionalTracker
	_check(ct != null, "controller tracker there")
	_check(hands.state()["right"]["feeding"], "an open hand feeds the controller tracker")
	_check(not hands.state()["left"]["feeding"], "no left hand data: nothing fed")
	var aim: XRPose = ct.get_pose(&"aim")
	var knuckle := _ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL).origin
	_check(aim != null and aim.transform.origin.distance_to(knuckle) < 0.001, "aim from the index knuckle")
	_check(aim != null and (-aim.transform.basis.z).dot(Vector3.FORWARD) > 0.99, "aim along the index finger")
	_check(float(ct.get_input(&"trigger")) == 0.0, "open hand: trigger up")

	_pose_hand(true)
	await _frames(2)
	_check(hands.state()["right"]["pinched"] and float(ct.get_input(&"trigger")) == 1.0, "pinch: trigger down")
	_pose_hand(false)
	await _frames(2)
	_check(not hands.state()["right"]["pinched"] and float(ct.get_input(&"trigger")) == 0.0, "release: trigger up")

	# The runtime moves the aim pose: a controller is in the hand, so the hand stops feeding.
	_pose_hand(true)
	ct.set_pose(&"aim", Transform3D(Basis(), Vector3(1, 1, 1)), Vector3.ZERO, Vector3.ZERO,
			XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await _frames(1)
	_check(not hands.state()["right"]["feeding"], "controller pose moved: hand input stops")
	_check(float(ct.get_input(&"trigger")) == 0.0, "controller pose moved: trigger left up")
	var p: XRPose = ct.get_pose(&"aim")
	_check(p.transform.origin.is_equal_approx(Vector3(1, 1, 1)), "the controller's pose is left alone")

	# Hand data that comes from a controller (data source extension) never feeds.
	ct.invalidate_pose(&"aim")
	_ht.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	await _frames(2)
	_check(not hands.state()["right"]["feeding"], "controller data source: no hand input")
	_ht.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	await _frames(2)
	_check(hands.state()["right"]["feeding"], "hands again after the controller")

	hands.queue_free()
	origin.queue_free()
	XRServer.remove_tracker(_ht)
	XRServer.remove_tracker(ct)
	await _frames(1)
