extends Node

## Watch party on the LAN (idea #51; docs/watch-party.md): two or more headsets play the same file on one clock, and
## each shows the others' head and controllers in the seats beside it. Off until started (party_host / party_join,
## --party=host|join[:IP], or the pane); LAN only: packets from addresses that are not private are dropped.
##
## UDP, one JSON object per packet, "v": 1. The host binds PORT and is the authority on time and state:
##   beacon   host -> broadcast PORT, every 1 s     {id, name, port, file, peers, pin: bool}
##   join     guest -> host                         {id, name, pin}
##   welcome  host -> guest                         {seat, peers, file}        reject {reason}
##   peers    host -> guests, on a change           {peers: [{id, name, seat}]}
##   ping     guest -> host, every 1 s              {seq, t0}      pong host -> guest {seq, t0, th}
##   clock    host -> guests, every 0.25 s and on a change  {ht, pos, playing, file, speed}
##   control  guest -> host                         {action: play | pause | seek | open, pos, path}
##   pose     everyone -> host -> the others, 20 Hz {seat, head, l, r}: [x, y, z, qx, qy, qz, qw] or null
##   bye      either way
## Guests turn the host clock into a target position with the clock offset from the best of the last 8 pings (least
## round trip), and follow it: a seek past 0.5 s off, else a speed trim of up to 5 % (the audio is time-stretched,
## pitch kept) until within 20 ms.
##
##   const WatchParty := preload("res://scripts/party/watch_party.gd")
##   WatchParty.host(main, "Robin")  /  WatchParty.join(main, "Sam", "192.168.1.20")  /  WatchParty.leave()
##   WatchParty.instance().status()   # {role, peers, sync, ...};  signals peers_changed(peers), file_needed(file)

signal peers_changed(peers: Array)
## The host plays a file this headset doesn't have open: {name, path, duration}.
signal file_needed(file: Dictionary)
signal ended(reason: String)

const RemoteServer := preload("res://scripts/remote/remote_server.gd")
const DevCommands := preload("res://scripts/dev/dev_commands.gd")

const NODE_NAME := "WatchParty"
const PORT := 47890
const VERSION := 1
const BEACON_EVERY := 1.0
const CLOCK_EVERY := 0.25
const PING_EVERY := 1.0
const POSE_EVERY := 0.05
const PEER_TIMEOUT := 6.0
const SEEK_THRESHOLD := 0.5
const TRIM_DEADBAND := 0.02
const MAX_TRIM := 0.05
## Seat spacing, metres to the right per seat.
const SEAT_SPACING := 0.8
const COLOURS: Array[Color] = [Color(0.35, 0.75, 1.0), Color(1.0, 0.6, 0.3), Color(0.5, 0.9, 0.5), Color(0.9, 0.5, 0.9)]

var role := ""          # "host" or "guest"
var my_id := ""
var my_name := ""
var my_seat := 0
var pin := ""
var port := PORT
var host_ip := ""
var host_port := PORT
## id -> {name, seat, ip, port, last, pose, avatar}
var peers := {}
var main: Node:
	get:
		var tree := Engine.get_main_loop() as SceneTree
		return tree.current_scene if tree != null else null

var _sock := PacketPeerUDP.new()
var _discover: PacketPeerUDP
var _discover_until := 0.0
var _joined := false
var _t := {"beacon": 0.0, "clock": 0.0, "ping": 0.0, "pose": 0.0}
var _ping_seq := 0
var _pings := {}                  # seq -> t0
var _offsets: Array = []          # [rtt, offset] newest last
var _offset := 0.0
var _rtt := -1.0
var _host_clock := {}             # the last clock: {ht, pos, playing, file, speed, rx}
var _applying := false
var _trim := 0.0
var _seeks := 0
var _last_error := 0.0
var _avatars_root: Node3D
var _beacons := {}                # discovered hosts: "ip:port" -> beacon


## The node made by the last start, until its deferred add_child has run (instance() finds it meanwhile).
static var _pending: Node = null


static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var n: Node = tree.root.get_node_or_null(NODE_NAME) if tree != null else null
	if n == null and is_instance_valid(_pending) and not _pending.is_queued_for_deletion():
		return _pending
	return n


## Adds a new node to the root at the end of the frame (the root may be busy now: main's _ready), unless it was
## stopped meanwhile. The argument is untyped: it may be a freed object by then.
static func _add_later(root: Node, n: Node) -> void:
	_pending = n
	_add_now.call_deferred(root, n)


static func _add_now(root: Node, n) -> void:
	if not is_instance_valid(n) or n != _pending:
		return
	_pending = null
	root.add_child(n)


## Takes a node away at once: out of the tree now (its _exit_tree closes sockets and frees the name, so a new one can
## take both in the same frame), freed later. A node not yet added is freed now.
static func _discard(n: Node) -> void:
	if n == _pending:
		_pending = null
	if n.is_inside_tree():
		n.get_parent().remove_child(n)
		n.queue_free()
	else:
		n.free()


## main.gd calls this at the end of _ready(): --party=host, --party=join or --party=join:IP[:PORT].
static func attach(m: Node, args: Dictionary) -> Node:
	if not args.has("party"):
		return null
	var spec := str(args["party"])
	var name := str(args.get("party-name", "Guest"))
	if spec == "host":
		return host(m, name, str(args.get("party-pin", "")))
	if spec.begins_with("join"):
		var target := spec.trim_prefix("join").trim_prefix(":")
		return join(m, name, target, str(args.get("party-pin", "")))
	push_error("--party=%s: host, join or join:IP" % spec)
	return null


static func host(m: Node, p_name := "Host", p_pin := "", p_port := PORT) -> Node:
	leave()
	var p: Node = (load("res://scripts/party/watch_party.gd") as GDScript).new()
	p.name = NODE_NAME
	p.role = "host"
	p.my_name = p_name
	p.pin = p_pin
	p.port = p_port
	_add_later(m.get_tree().root, p)
	return p


## target: "IP" or "IP:PORT"; "" finds a host by its beacon (the first heard within 5 s).
static func join(m: Node, p_name := "Guest", target := "", p_pin := "") -> Node:
	leave()
	var p: Node = (load("res://scripts/party/watch_party.gd") as GDScript).new()
	p.name = NODE_NAME
	p.role = "guest"
	p.my_name = p_name
	p.pin = p_pin
	if target != "":
		var parts := target.split(":")
		p.host_ip = parts[0]
		p.host_port = int(parts[1]) if parts.size() > 1 else PORT
	_add_later(m.get_tree().root, p)
	return p


static func leave() -> void:
	var p := instance()
	if p == null:
		return
	if p.is_inside_tree():
		p._end("left")  # says bye to the others first
	_discard(p)


func _ready() -> void:
	my_id = "%08x" % (randi() & 0x7fffffff)
	var err: Error = _sock.bind(port if role == "host" else 0, "*")
	if err != OK:
		push_error("Watch party: can't bind UDP %d: %s" % [port, error_string(err)])
		role = ""
		queue_free()
		return
	_sock.set_broadcast_enabled(true)
	_avatars_root = Node3D.new()
	_avatars_root.name = "PartyAvatars"
	var origin: Node = main.get("xr_origin") if main != null else null
	(origin if origin != null else main).add_child(_avatars_root)
	var p: Node = main.player
	p.playing_changed.connect(_on_local_playing)
	p.seeked.connect(_on_local_seek)
	main.file_opened.connect(_on_local_file)
	if role == "guest":
		if host_ip == "":
			_discover = PacketPeerUDP.new()
			if _discover.bind(PORT, "*") != OK:
				push_warning("Watch party: can't listen for beacons on %d (another app holds it); give the host's address" % PORT)
			_discover_until = _now() + 5.0
		else:
			_send_join()
	print("Watch party: %s as %s (%s), UDP %d" % [role, my_name, my_id, _sock.get_local_port()])


func _exit_tree() -> void:
	_sock.close()
	if _discover != null:
		_discover.close()
	if is_instance_valid(_avatars_root):
		_avatars_root.queue_free()
	_set_trim(0.0)


func _end(reason: String) -> void:
	if role == "":
		return
	if role == "host":
		for id: String in peers:
			_send_to(peers[id], {"t": "bye", "reason": reason})
	elif _joined:
		_send_host({"t": "bye", "reason": reason})
	print("Watch party: ended (%s)" % reason)
	role = ""
	ended.emit(reason)
	queue_free()


static func _now() -> float:
	return Time.get_ticks_usec() / 1e6


# --- Network ------------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if role == "":
		return
	var now := _now()
	_receive(_sock)
	if _discover != null:
		_receive(_discover)
		if not _joined and host_ip == "" and now > _discover_until:
			_discover.close()
			_discover = null
			_end("no host found")
			return
	if role == "host":
		if now - _t["beacon"] >= BEACON_EVERY:
			_t["beacon"] = now
			_broadcast({"t": "beacon", "name": my_name, "port": port, "file": _file_info(), "peers": peers.size() + 1,
					"pin": pin != ""})
		if now - _t["clock"] >= CLOCK_EVERY:
			_send_clock()
	elif _joined:
		if now - _t["ping"] >= PING_EVERY:
			_t["ping"] = now
			_ping_seq += 1
			_pings[_ping_seq] = now
			_send_host({"t": "ping", "seq": _ping_seq, "t0": now})
		_follow()
	if (role == "host" or _joined) and now - _t["pose"] >= POSE_EVERY:
		_t["pose"] = now
		_send_pose()
	# Peers that went quiet.
	for id: String in peers.keys():
		if now - float(peers[id]["last"]) > PEER_TIMEOUT:
			if role == "guest":
				if int(peers[id]["seat"]) == 0:
					_end("the host went quiet")
					return
				continue  # Other guests are heard only through their poses; the host's list says who is there.
			_drop_peer(id, "timed out")


func _receive(sock: PacketPeerUDP) -> void:
	while sock.get_available_packet_count() > 0:
		var data := sock.get_packet()
		var ip := sock.get_packet_ip()
		var from_port := sock.get_packet_port()
		if not RemoteServer.is_private(ip):
			continue
		var msg: Variant = JSON.parse_string(data.get_string_from_utf8())
		if not msg is Dictionary or int(msg.get("v", 0)) != VERSION or str(msg.get("id", "")) == my_id:
			continue
		_handle(msg, ip, from_port)


func _handle(msg: Dictionary, ip: String, from_port: int) -> void:
	var t := str(msg.get("t", ""))
	var id := str(msg["id"])
	if peers.has(id):
		peers[id]["last"] = _now()
	match t:
		"beacon":
			_beacons["%s:%d" % [ip, int(msg.get("port", PORT))]] = msg
			if role == "guest" and not _joined and host_ip == "":
				host_ip = ip
				host_port = int(msg.get("port", PORT))
				_send_join()
		"join":
			if role != "host":
				return
			if pin != "" and str(msg.get("pin", "")) != pin:
				_raw_send(ip, from_port, {"t": "reject", "reason": "wrong pin"})
				return
			var seat := 1
			var taken := {}
			for p: Dictionary in peers.values():
				taken[int(p["seat"])] = true
			while taken.has(seat):
				seat += 1
			peers[id] = {"name": str(msg.get("name", "Guest")), "seat": seat, "ip": ip, "port": from_port,
					"last": _now(), "pose": {}}
			_raw_send(ip, from_port, {"t": "welcome", "seat": seat, "peers": _peer_list(), "file": _file_info()})
			_send_peers()
			_send_clock()
			print("Watch party: %s joined from %s, seat %d" % [peers[id]["name"], ip, seat])
		"welcome":
			if role != "guest":
				return
			_joined = true
			my_seat = int(msg["seat"])
			if _discover != null:
				_discover.close()
				_discover = null
			_set_peers(msg.get("peers", []), id, ip, from_port)
			_check_file(msg.get("file", {}))
			print("Watch party: joined %s at %s, seat %d" % [peers.get(id, {}).get("name", "host"), ip, my_seat])
		"reject":
			_end("the host refused: %s" % msg.get("reason", ""))
		"peers":
			if role == "guest":
				_set_peers(msg.get("peers", []), id, ip, from_port)
		"ping":
			if role == "host" and peers.has(id):
				_send_to(peers[id], {"t": "pong", "seq": msg["seq"], "t0": msg["t0"], "th": _now()})
		"pong":
			_on_pong(msg)
		"clock":
			if role == "guest":
				var c: Dictionary = msg
				c["rx"] = _now()
				var file_changed := str(c.get("file", {}).get("name", "")) != str(_host_clock.get("file", {}).get("name", ""))
				_host_clock = c
				if file_changed:
					_check_file(c.get("file", {}))
		"control":
			if role == "host" and peers.has(id):
				_apply_control(msg)
				_send_clock()
		"pose":
			_on_pose(msg, id)
		"bye":
			if role == "guest" and peers.has(id) and int(peers[id]["seat"]) == 0:
				_end("the host ended the party")
			else:
				_drop_peer(id, str(msg.get("reason", "left")))


func _raw_send(ip: String, to_port: int, msg: Dictionary) -> void:
	msg["v"] = VERSION
	msg["id"] = my_id
	_sock.set_dest_address(ip, to_port)
	_sock.put_packet(JSON.stringify(msg).to_utf8_buffer())


func _send_to(peer: Dictionary, msg: Dictionary) -> void:
	_raw_send(peer["ip"], int(peer["port"]), msg)


func _send_host(msg: Dictionary) -> void:
	if host_ip != "":
		_raw_send(host_ip, host_port, msg)


func _broadcast(msg: Dictionary) -> void:
	_raw_send("255.255.255.255", PORT, msg)


func _send_join() -> void:
	_send_host({"t": "join", "name": my_name, "pin": pin})
	# Joins are retried with the next beacon, or here once a second until welcomed.
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(self) and role == "guest" and not _joined and host_ip != "":
			_send_join())


func _peer_list() -> Array:
	var out := [{"id": my_id, "name": my_name, "seat": 0}]
	for id: String in peers:
		out.append({"id": id, "name": peers[id]["name"], "seat": peers[id]["seat"]})
	return out


func _send_peers() -> void:
	var list := _peer_list()
	for id: String in peers:
		_send_to(peers[id], {"t": "peers", "peers": list})
	peers_changed.emit(list)


## Guest: the host's list. Only the host is reached directly (everything goes through it).
func _set_peers(list: Array, host_id: String, ip: String, from_port: int) -> void:
	var seen := {}
	for p: Dictionary in list:
		var id := str(p["id"])
		if id == my_id:
			continue
		seen[id] = true
		if not peers.has(id):
			peers[id] = {"name": str(p["name"]), "seat": int(p["seat"]), "ip": ip if id == host_id else "",
					"port": from_port if id == host_id else 0, "last": _now(), "pose": {}}
		peers[id]["seat"] = int(p["seat"])
	for id: String in peers.keys():
		if not seen.has(id):
			_drop_peer(id, "left", false)
	peers_changed.emit(list)


func _drop_peer(id: String, reason: String, announce := true) -> void:
	if not peers.has(id):
		return
	var p: Dictionary = peers[id]
	print("Watch party: %s %s" % [p["name"], reason])
	if p.get("avatar") != null and is_instance_valid(p["avatar"]):
		p["avatar"].queue_free()
	peers.erase(id)
	if role == "host" and announce:
		_send_peers()


# --- Clock and sync -----------------------------------------------------------------------------------------------

func _file_info() -> Dictionary:
	var m := main
	if m == null or m.current_path == "":
		return {}
	return {"name": str(m.current_path).get_file(), "path": m.current_path, "duration": snappedf(m.player.get_duration(), 0.01)}


func _send_clock() -> void:
	_t["clock"] = _now()
	var m := main
	var c := {"t": "clock", "ht": _now(), "pos": m.player.get_position(), "playing": m.player.is_playing(),
			"file": _file_info(), "speed": float(m.player.speed)}
	for id: String in peers:
		_send_to(peers[id], c.duplicate())


func _on_pong(msg: Dictionary) -> void:
	var t1 := _now()
	var t0 := float(msg["t0"])
	if not _pings.has(int(msg["seq"])):
		return
	_pings.erase(int(msg["seq"]))
	var rtt := t1 - t0
	var offset := float(msg["th"]) - (t0 + t1) / 2.0
	_offsets.append([rtt, offset])
	if _offsets.size() > 8:
		_offsets.pop_front()
	var best: Array = _offsets[0]
	for o: Array in _offsets:
		if o[0] < best[0]:
			best = o
	_rtt = best[0]
	_offset = best[1]


## The host's position now, from its last clock: -1 when unknown.
func host_position() -> float:
	if _host_clock.is_empty() or _offsets.is_empty():
		return -1.0
	var pos := float(_host_clock["pos"])
	if bool(_host_clock["playing"]):
		pos += (_now() + _offset - float(_host_clock["ht"])) * float(_host_clock.get("speed", 1.0))
	return pos


func _same_file() -> bool:
	var m := main
	var f: Dictionary = _host_clock.get("file", {})
	return m != null and not f.is_empty() and str(m.current_path).get_file() == str(f.get("name", ""))


func _check_file(f: Dictionary) -> void:
	if f.is_empty() or _same_file_info(f):
		return
	var path := str(f.get("path", ""))
	if path.contains("://") or FileAccess.file_exists(path):
		print("Watch party: opening the host's file %s" % path)
		_applying = true
		main.open_path(path)
		_applying = false
	else:
		print("Watch party: the host plays %s, not found here" % f.get("name", ""))
		file_needed.emit(f)


func _same_file_info(f: Dictionary) -> bool:
	return str(main.current_path).get_file() == str(f.get("name", ""))


## Guest: follow the host's clock and state.
func _follow() -> void:
	if _host_clock.is_empty() or not _same_file():
		_set_trim(0.0)
		return
	var m := main
	var p: Node = m.player
	var want_playing := bool(_host_clock["playing"])
	if p.is_playing() != want_playing:
		_applying = true
		if want_playing:
			p.play()
		else:
			p.pause()
		_applying = false
	var target := host_position()
	if target < 0.0 or not p.can_seek():
		return
	var err: float = target - float(p.get_position())
	_last_error = err
	if absf(err) > SEEK_THRESHOLD:
		_applying = true
		p.seek(target)
		_applying = false
		_seeks += 1
		_set_trim(0.0)
	elif want_playing and absf(err) > TRIM_DEADBAND:
		_set_trim(clampf(err * 0.5, -MAX_TRIM, MAX_TRIM))
	else:
		_set_trim(0.0)


## A small speed change to close the gap; on top of the user's playback speed.
func _set_trim(trim: float) -> void:
	if is_equal_approx(trim, _trim):
		return
	_trim = trim
	var m := main
	if m == null or m.player.source == null or m.player.source.get_kind() == "window":
		return
	var base := 1.0
	if "features" in m and m.features != null and m.features.get("speed") != null:
		base = float(m.features.speed.speed)
	m.player.speed = base * (1.0 + trim)
	m.player.source.set_playback_speed(base * (1.0 + trim))


# --- Local actions ------------------------------------------------------------------------------------------------

func _on_local_playing(playing: bool) -> void:
	if _applying or role == "":
		return
	if role == "host":
		_send_clock()
	elif _joined:
		_send_host({"t": "control", "action": "play" if playing else "pause", "pos": main.player.get_position()})


func _on_local_seek(seconds: float) -> void:
	if _applying or role == "":
		return
	if role == "host":
		_send_clock()
	elif _joined:
		_send_host({"t": "control", "action": "seek", "pos": seconds})


func _on_local_file(path: String) -> void:
	if _applying or role == "":
		return
	if role == "host":
		_send_clock()
	elif _joined and path != "" and path.get_file() != str(_host_clock.get("file", {}).get("name", "")):
		_send_host({"t": "control", "action": "open", "path": path})


func _apply_control(msg: Dictionary) -> void:
	var p: Node = main.player
	_applying = true
	match str(msg.get("action", "")):
		"play":
			p.play()
		"pause":
			p.pause()
		"seek":
			p.seek(float(msg.get("pos", 0.0)))
		"open":
			var path := str(msg.get("path", ""))
			if path != "" and path != main.current_path and (path.contains("://") or FileAccess.file_exists(path)):
				main.open_path(path)
	_applying = false


# --- Poses and avatars --------------------------------------------------------------------------------------------

func _send_pose() -> void:
	var m := main
	var cam: Node3D = m.camera if m.get("camera") != null else null
	var origin: Node3D = m.get("xr_origin")
	var msg := {"t": "pose", "seat": my_seat if role == "guest" else 0,
			"head": _pack(_local_transform(cam, origin)) if cam != null else null,
			"l": _hand_pose(m.get("left_hand"), origin), "r": _hand_pose(m.get("right_hand"), origin)}
	if role == "host":
		for id: String in peers:
			_send_to(peers[id], msg.duplicate())
	else:
		_send_host(msg)


func _hand_pose(hand: Variant, origin: Node3D) -> Variant:
	var h := hand as XRController3D
	if h == null or not h.get_has_tracking_data():
		return null
	return _pack(_local_transform(h, origin))


static func _local_transform(n: Node3D, origin: Node3D) -> Transform3D:
	if origin == null or not origin.is_inside_tree():
		return n.global_transform
	return origin.global_transform.affine_inverse() * n.global_transform


static func _pack(t: Transform3D) -> Array:
	var q := t.basis.get_rotation_quaternion()
	return [snappedf(t.origin.x, 0.001), snappedf(t.origin.y, 0.001), snappedf(t.origin.z, 0.001),
			snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]


static func _unpack(a: Variant) -> Variant:
	if not a is Array or (a as Array).size() != 7:
		return null
	var q := Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6])).normalized()
	return Transform3D(Basis(q), Vector3(float(a[0]), float(a[1]), float(a[2])))


func _on_pose(msg: Dictionary, id: String) -> void:
	# The host forwards a guest's pose to the other guests.
	if role == "host" and peers.has(id):
		for other: String in peers:
			if other != id:
				var fwd := msg.duplicate()
				fwd["from"] = id
				_send_to(peers[other], fwd)
	# Forwarded poses name their owner in "from"; the host's own have none.
	var who := str(msg.get("from", id))
	if not peers.has(who):
		return
	var p: Dictionary = peers[who]
	p["last"] = _now()
	p["pose"] = msg
	if p.get("avatar") == null or not is_instance_valid(p["avatar"]):
		p["avatar"] = _make_avatar(str(p["name"]), COLOURS[int(p["seat"]) % COLOURS.size()])
		_avatars_root.add_child(p["avatar"])
	var av: Node3D = p["avatar"]
	# In the seat beside: seats are SEAT_SPACING apart, to the right of seat 0.
	av.position = Vector3((int(p["seat"]) - my_seat) * SEAT_SPACING, 0.0, 0.0)
	for part: String in ["head", "l", "r"]:
		var node := av.get_node(part) as Node3D
		var t: Variant = _unpack(msg.get(part))
		node.visible = t != null
		if t != null:
			node.transform = t


func _make_avatar(label: String, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Peer_" + label.validate_node_name()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var head := MeshInstance3D.new()
	head.name = "head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.2
	head.mesh = sphere
	head.material_override = mat
	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.06, 0.04)
	visor.mesh = box
	visor.position = Vector3(0, 0.01, -0.08)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = colour.darkened(0.6)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor.material_override = dark
	head.add_child(visor)
	var tag := Label3D.new()
	tag.text = label
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.0015
	tag.position = Vector3(0, 0.18, 0)
	tag.modulate = colour.lightened(0.4)
	head.add_child(tag)
	root.add_child(head)
	for side in ["l", "r"]:
		var hand := MeshInstance3D.new()
		hand.name = side
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 0.04, 0.14)
		hand.mesh = b
		hand.material_override = mat
		root.add_child(hand)
	return root


# --- Status and commands ------------------------------------------------------------------------------------------

func status() -> Dictionary:
	var list: Array = []
	for id: String in peers:
		var p: Dictionary = peers[id]
		list.append({"id": id, "name": p["name"], "seat": p["seat"], "ip": p["ip"],
				"seen_s_ago": snappedf(_now() - float(p["last"]), 0.1), "pose": not (p["pose"] as Dictionary).is_empty()})
	var out := {"role": role, "id": my_id, "name": my_name, "seat": my_seat, "port": _sock.get_local_port() if _sock.is_bound() else 0,
			"peers": list, "file": _file_info()}
	if role == "guest":
		out["joined"] = _joined
		out["host"] = "%s:%d" % [host_ip, host_port]
		out["sync"] = {"rtt_ms": snappedf(_rtt * 1000.0, 0.1), "offset_ms": snappedf(_offset * 1000.0, 0.1),
				"error_ms": snappedf(_last_error * 1000.0, 0.1), "trim": snappedf(_trim, 0.001), "seeks": _seeks,
				"host_position": snappedf(host_position(), 0.01), "same_file": _same_file()}
	else:
		out["beacons_heard"] = _beacons.size()
	return out


## The name the others see under this headset's avatar: the saved one ([party] name, the Room tab's Name), else
## "Headset". Never the login name: it is the viewer's own.
static func saved_name(m: Node) -> String:
	var n := str(m.settings.get_value("party", "name", ""))
	return n if n != "" else "Headset"


## The saved PIN ([party] pin, the Room tab's PIN), "" for none. Never printed or sent in a reply.
static func saved_pin(m: Node) -> String:
	return str(m.settings.get_value("party", "pin", ""))


## Why a join target is refused, or "": the party is LAN only, so the host must be a private address.
static func target_refusal(target: String) -> String:
	if target == "":
		return ""
	var ip := target.get_slice(":", 0)
	if not ip.is_valid_ip_address():
		return "host: an IP address on this network, or IP:PORT"
	if not RemoteServer.is_private(ip):
		return "host: %s is not on this network (the watch party is LAN only)" % ip
	return ""


## party_host and party_join without a name or PIN use the saved ones, as the Room tab's Host and Join do.
static func register_commands(cmd_host: Node) -> void:
	var name_param := {"name": "name", "type": "string",
			"description": "The name the others see; left out, the saved one (party_settings, the Room tab's Name)."}
	var pin_param := {"name": "pin", "type": "string",
			"description": "The party's PIN; left out, the saved one (party_settings, the Room tab's PIN)."}
	DevCommands.register("party_host", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var m: Node = cmd_host.main
		var p := host(m, str(args.get("name", saved_name(m))), str(args.get("pin", saved_pin(m))))
		await cmd_host.get_tree().process_frame
		if not is_instance_valid(p) or p.role == "":
			return ctx.fail("can't start: UDP %d is in use" % PORT)
		ctx.summary = "watch party: hosting"
		ctx.undo = func() -> void: leave()
		return p.status(), {
		"description": "Starts a watch party on this network as host (the Room tab's Host): every headset that joins "
				+ "plays the host's file on one clock (docs/watch-party.md).",
		"params": [name_param, pin_param],
		"level": "control", "returns": "the party status", "assistant": "control"})
	DevCommands.register("party_join", func(args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var why := target_refusal(str(args["host"]))
		if why != "":
			return ctx.fail(why)
		var m: Node = cmd_host.main
		var p := join(m, str(args.get("name", saved_name(m))), args["host"], str(args.get("pin", saved_pin(m))))
		var until := Time.get_ticks_msec() + 6000
		while is_instance_valid(p) and p.role != "" and not p._joined and Time.get_ticks_msec() < until:
			await cmd_host.get_tree().process_frame
		if not is_instance_valid(p) or p.role == "":
			return ctx.fail("no party joined (no host answered)")
		ctx.summary = "watch party: joined"
		ctx.undo = func() -> void: leave()
		return p.status(), {
		"description": "Joins a watch party on this network (the Room tab's Join): a host's address, or the first host "
				+ "heard within 5 s.",
		"params": [{"name": "host", "type": "string", "default": "",
				"description": "The host's IP or IP:PORT on this network; empty for the first host heard."},
				name_param, pin_param],
		"level": "control", "returns": "the party status", "assistant": "control"})
	DevCommands.register("party_leave", func(_args: Dictionary, ctx: DevCommands.Call) -> Variant:
		var had := instance() != null
		leave()
		if had:
			ctx.summary = "watch party: left"
		return {"left": had}, {"description": "Leaves the watch party, or as host ends it (the Room tab's Leave or End "
		+ "party).", "level": "control", "returns": "{left}", "assistant": "control"})
	DevCommands.register("party_status", func(_args: Dictionary, _ctx: DevCommands.Call) -> Variant:
		var p := instance()
		return p.status() if p != null else {"role": ""}, {
		"description": "The watch party: role, peers, and for a guest the sync (round trip, clock offset, error, "
				+ "speed trim, seeks). Never the PIN.", "returns": "{role, peers, sync, ...}", "assistant": "read"})
