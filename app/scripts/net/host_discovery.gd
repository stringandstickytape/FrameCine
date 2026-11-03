extends Node

## SMB host discovery (idea #49): finds file servers on the LAN so nobody types an address in VR. Two ways at once,
## both over UDP with PacketPeerUDP, polled in _process() (never blocks the frame):
##   NetBIOS   a node status query (NBSTAT, UDP 137) to every address of each local /24 network, and one broadcast.
##             Windows PCs and Samba servers answer with their name table; a unique name of type 0x20 means a file
##             server.
##   mDNS      a PTR query for _smb._tcp.local to 224.0.0.251:5353, asking for unicast answers (the QU bit).
##             Samba with Avahi, macOS and most NAS boxes answer with the service, its host and address.
## Each host found is announced once by host_found(); finished() gives them all after `duration` seconds. A host is
## {"name": "DESKTOP-PC", "address": "192.168.1.20", "source": "netbios"|"mdns", "file_server": bool, "port": 445}.
##
## For the pane's Network place (app-shell):
##   var d := preload("res://scripts/net/host_discovery.gd").new(); add_child(d)
##   d.host_found.connect(func(h: Dictionary) -> void: add_row(h))   # "Found: NAME (address)"; open smb://<name or address>
##   d.finished.connect(func(hosts: Array) -> void: d.queue_free())
##   d.start(3.0)

signal host_found(host: Dictionary)
signal finished(hosts: Array)

const NETBIOS_PORT := 137
const MDNS_ADDRESS := "224.0.0.251"
const MDNS_PORT := 5353
const SMB_SERVICE := "_smb._tcp.local"
## Unicast queries sent per frame (254 per /24 network).
const SENDS_PER_FRAME := 64

var hosts: Array[Dictionary] = []
## The NetBIOS port to query (tests use another; real servers answer on 137 only).
var netbios_port := NETBIOS_PORT
var _udp: PacketPeerUDP
var _targets: Array[String] = []
var _sent := 0
var _deadline := 0
var _running := false
var _txid := 0
var _by_address := {}
## mDNS: instance name -> SRV target host; host -> address.
var _srv := {}
var _a := {}


func is_running() -> bool:
	return _running


## Starts a scan for `duration` seconds. Returns false if no socket could be opened.
func start(duration := 3.0) -> bool:
	stop()
	hosts.clear()
	_by_address.clear()
	_srv.clear()
	_a.clear()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(0, "*") != OK:
		push_warning("Host discovery: can't open a UDP socket")
		return false
	_targets.clear()
	for net in local_networks():
		for i in range(1, 255):
			_targets.append("%s.%d" % [net, i])
		_targets.append("%s.255" % net)
	_sent = 0
	_txid = randi() & 0xFFFF
	_deadline = Time.get_ticks_msec() + int(duration * 1000.0)
	_running = true
	_send_mdns()
	set_process(true)
	return true


func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	_running = false
	set_process(false)


func _exit_tree() -> void:
	stop()


## "192.168.2" for each private IPv4 address of this device (as /24 networks).
static func local_networks() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if not a.is_valid_ip_address() or a.contains(":"):
			continue
		var p := a.split(".")
		var o0 := p[0].to_int()
		var o1 := p[1].to_int()
		var private := o0 == 10 or (o0 == 172 and o1 >= 16 and o1 <= 31) or (o0 == 192 and o1 == 168)
		var net := "%s.%s.%s" % [p[0], p[1], p[2]]
		if private and not out.has(net):
			out.append(net)
	return out


func _process(_delta: float) -> void:
	if _udp == null:
		return
	var n := 0
	while _sent < _targets.size() and n < SENDS_PER_FRAME:
		_udp.set_dest_address(_targets[_sent], netbios_port)
		_udp.put_packet(nbstat_request(_txid))
		_sent += 1
		n += 1
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		if port == netbios_port:
			var r := parse_nbstat(pkt)
			if not r.is_empty():
				_add({"name": r["name"], "address": ip, "source": "netbios", "file_server": r["file_server"],
						"port": 445})
		elif port == MDNS_PORT:
			_on_mdns(pkt, ip)
	if Time.get_ticks_msec() >= _deadline:
		stop()
		finished.emit(hosts.duplicate(true))


func _add(h: Dictionary) -> void:
	var key := str(h["address"])
	if _by_address.has(key):
		var old: Dictionary = _by_address[key]
		# NetBIOS knows whether it is a file server; mDNS for _smb._tcp says so too. Keep the better record.
		if not old["file_server"] and h["file_server"]:
			old.merge(h, true)
		return
	_by_address[key] = h
	hosts.append(h)
	host_found.emit(h)


# --- NetBIOS -------------------------------------------------------------------------------------------------------

## A NetBIOS node status (NBSTAT) request for the wildcard name "*".
static func nbstat_request(txid: int) -> PackedByteArray:
	var b := PackedByteArray([(txid >> 8) & 0xFF, txid & 0xFF, 0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0x20])
	var name := PackedByteArray([0x2A])  # "*" padded with zeros to 16 bytes
	name.resize(16)
	for c in name:
		b.append(0x41 + (c >> 4))
		b.append(0x41 + (c & 0x0F))
	b.append_array(PackedByteArray([0x00, 0x00, 0x21, 0x00, 0x01]))
	return b


## {name, file_server} from a node status response, or {}.
static func parse_nbstat(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 57 or (pkt[2] & 0x80) == 0:
		return {}
	var i := 12
	# The answer's name: a label of 32 bytes (or a compression pointer).
	if pkt[i] & 0xC0 == 0xC0:
		i += 2
	else:
		while i < pkt.size() and pkt[i] != 0:
			i += pkt[i] + 1
		i += 1
	if i + 10 >= pkt.size():
		return {}
	var rtype := (pkt[i] << 8) | pkt[i + 1]
	if rtype != 0x21:
		return {}
	i += 10  # type, class, ttl, rdlength
	var count := pkt[i]
	i += 1
	var first_unique := ""
	var server := ""
	for k in count:
		if i + 18 > pkt.size():
			break
		var raw := pkt.slice(i, i + 15).get_string_from_ascii().strip_edges()
		var suffix := pkt[i + 15]
		var group := (pkt[i + 16] & 0x80) != 0
		i += 18
		if group:
			continue
		if first_unique == "" and suffix == 0x00:
			first_unique = raw
		if suffix == 0x20 and server == "":
			server = raw
	var name := server if server != "" else first_unique
	return {} if name == "" else {"name": name, "file_server": server != ""}


# --- mDNS ----------------------------------------------------------------------------------------------------------

func _send_mdns() -> void:
	_udp.set_dest_address(MDNS_ADDRESS, MDNS_PORT)
	_udp.put_packet(mdns_query(SMB_SERVICE))


## A DNS query for PTR `service`, with the QU bit (answer by unicast).
static func mdns_query(service: String) -> PackedByteArray:
	var b := PackedByteArray([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	b.append_array(_dns_name(service))
	b.append_array(PackedByteArray([0x00, 0x0C, 0x80, 0x01]))
	return b


static func _dns_name(name: String) -> PackedByteArray:
	var out := PackedByteArray()
	for label in name.split(".", false):
		var bytes := label.to_utf8_buffer()
		out.append(bytes.size())
		out.append_array(bytes)
	out.append(0)
	return out


func _on_mdns(pkt: PackedByteArray, from_ip: String) -> void:
	for rec in parse_dns(pkt):
		match int(rec["type"]):
			33:  # SRV: instance -> target host
				_srv[rec["name"]] = rec["target"]
			1:  # A
				_a[str(rec["name"]).to_lower()] = rec["address"]
	for instance: String in _srv:
		if not instance.to_lower().ends_with(SMB_SERVICE):
			continue
		var target: String = _srv[instance]
		var address: String = _a.get(target.to_lower(), from_ip)
		var label := instance.trim_suffix("." + SMB_SERVICE)
		var host := target.trim_suffix(".local").trim_suffix(".")
		_add({"name": host if host != "" else label, "address": address, "source": "mdns", "file_server": true,
				"port": 445, "label": label})


## The answer, authority and additional records of a DNS message: [{name, type, ...}] with "target" for PTR and SRV,
## "port" for SRV and "address" for A.
static func parse_dns(pkt: PackedByteArray) -> Array:
	var out: Array = []
	if pkt.size() < 12:
		return out
	var qd := (pkt[4] << 8) | pkt[5]
	var total := ((pkt[6] << 8) | pkt[7]) + ((pkt[8] << 8) | pkt[9]) + ((pkt[10] << 8) | pkt[11])
	var i := 12
	for q in qd:
		var r := _read_name(pkt, i)
		i = r[1] + 4
	for k in total:
		if i >= pkt.size():
			break
		var nr := _read_name(pkt, i)
		i = nr[1]
		if i + 10 > pkt.size():
			break
		var type := (pkt[i] << 8) | pkt[i + 1]
		var rdlen := (pkt[i + 8] << 8) | pkt[i + 9]
		var rd := i + 10
		var rec := {"name": nr[0], "type": type}
		match type:
			12:
				rec["target"] = _read_name(pkt, rd)[0]
			33:
				if rd + 6 <= pkt.size():
					rec["port"] = (pkt[rd + 4] << 8) | pkt[rd + 5]
					rec["target"] = _read_name(pkt, rd + 6)[0]
			1:
				if rdlen == 4 and rd + 4 <= pkt.size():
					rec["address"] = "%d.%d.%d.%d" % [pkt[rd], pkt[rd + 1], pkt[rd + 2], pkt[rd + 3]]
		out.append(rec)
		i = rd + rdlen
	return out


## [name, next offset] of a (possibly compressed) DNS name at `start`.
static func _read_name(pkt: PackedByteArray, start: int) -> Array:
	var labels: Array[String] = []
	var i := start
	var end := -1
	var jumps := 0
	while i < pkt.size():
		var n := pkt[i]
		if n == 0:
			i += 1
			break
		if n & 0xC0 == 0xC0:
			if i + 1 >= pkt.size() or jumps > 16:
				break
			if end < 0:
				end = i + 2
			i = ((n & 0x3F) << 8) | pkt[i + 1]
			jumps += 1
			continue
		labels.append(pkt.slice(i + 1, i + 1 + n).get_string_from_utf8())
		i += n + 1
	return [".".join(labels), end if end >= 0 else i]
