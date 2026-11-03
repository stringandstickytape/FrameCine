extends SceneTree

## Host discovery's packets (scripts/net/host_discovery.gd): the NBSTAT request's layout, a node status answer with a
## file server name, a workstation-only answer, and an mDNS answer with name compression (PTR + SRV + A).
## godot --headless --xr-mode off --path app --script res://tests/test_host_discovery.gd

const HostDiscovery := preload("res://scripts/net/host_discovery.gd")

var _fails := 0


func _init() -> void:
	_test_request()
	_test_nbstat()
	_test_mdns()
	print("test_host_discovery: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _test_request() -> void:
	var r := HostDiscovery.nbstat_request(0x1234)
	_check(r.size() == 50, "request is 50 bytes (got %d)" % r.size())
	_check(r[0] == 0x12 and r[1] == 0x34, "transaction id")
	_check(r[12] == 0x20 and r[13] == 0x43 and r[14] == 0x4B, "encoded '*' starts CK")
	_check(r[15] == 0x41 and r[44] == 0x41 and r[45] == 0x00, "zero padding is AA, then the root label")
	_check(r[46] == 0x00 and r[47] == 0x21 and r[49] == 0x01, "type NBSTAT, class IN")


## A node status answer: the names, then the MAC.
static func nbstat_answer(names: Array) -> PackedByteArray:
	var b := PackedByteArray([0x12, 0x34, 0x84, 0x00, 0, 0, 0, 1, 0, 0, 0, 0, 0x20])
	for i in 16:
		b.append_array(PackedByteArray([0x43, 0x4B]) if i == 0 else PackedByteArray([0x41, 0x41]))
	b.append_array(PackedByteArray([0x00, 0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0]))
	var rd := PackedByteArray([names.size()])
	for n: Array in names:
		var name: String = n[0]
		rd.append_array((name + " ".repeat(15 - name.length())).to_ascii_buffer())
		rd.append(n[1])
		rd.append_array(PackedByteArray([0x84 if n[2] else 0x04, 0x00]))
	rd.append_array(PackedByteArray([0x00, 0x15, 0x5d, 0x01, 0x02, 0x03]))
	b.append_array(PackedByteArray([(rd.size() >> 8) & 0xFF, rd.size() & 0xFF]))
	b.append_array(rd)
	return b


func _test_nbstat() -> void:
	var r := HostDiscovery.parse_nbstat(nbstat_answer([["DESKTOP-PC", 0x00, false], ["WORKGROUP", 0x00, true],
			["DESKTOP-PC", 0x20, false]]))
	_check(r.get("name") == "DESKTOP-PC" and r.get("file_server") == true, "file server answer: %s" % r)
	var w := HostDiscovery.parse_nbstat(nbstat_answer([["WORKGROUP", 0x00, true], ["LAPTOP", 0x00, false]]))
	_check(w.get("name") == "LAPTOP" and w.get("file_server") == false, "workstation answer: %s" % w)
	_check(HostDiscovery.parse_nbstat(HostDiscovery.nbstat_request(1)).is_empty(), "a request is not an answer")
	_check(HostDiscovery.parse_nbstat(PackedByteArray([1, 2, 3])).is_empty(), "short packet")


func _test_mdns() -> void:
	var q := HostDiscovery.mdns_query("_smb._tcp.local")
	_check(q.size() == 12 + 17 + 4 and q[q.size() - 2] == 0x80, "query with the QU bit")
	# Answer: PTR _smb._tcp.local -> "Media Box._smb._tcp.local", SRV -> nas.local:445, A nas.local 192.168.1.30.
	var b := PackedByteArray([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 2])
	var svc_at := b.size()
	b.append_array(HostDiscovery._dns_name("_smb._tcp.local"))
	b.append_array(PackedByteArray([0, 12, 0, 1, 0, 0, 0x11, 0x94]))
	var inst := PackedByteArray([9]) + "Media Box".to_utf8_buffer() + PackedByteArray([0xC0, svc_at])
	b.append_array(PackedByteArray([0, inst.size()]))
	var inst_at := b.size()
	b.append_array(inst)
	# SRV: name = pointer to the instance.
	b.append_array(PackedByteArray([0xC0, inst_at, 0, 33, 0x80, 1, 0, 0, 0, 120]))
	var target := HostDiscovery._dns_name("nas.local")
	b.append_array(PackedByteArray([0, 6 + target.size(), 0, 0, 0, 0, 0x01, 0xBD]))
	var target_at := b.size()
	b.append_array(target)
	# A: name = pointer to the target.
	b.append_array(PackedByteArray([0xC0, target_at, 0, 1, 0x80, 1, 0, 0, 0, 120, 0, 4, 192, 168, 1, 30]))
	var recs := HostDiscovery.parse_dns(b)
	_check(recs.size() == 3, "three records (got %d)" % recs.size())
	if recs.size() == 3:
		_check(recs[0]["target"] == "Media Box._smb._tcp.local", "PTR target: %s" % recs[0])
		_check(recs[1]["name"] == "Media Box._smb._tcp.local" and recs[1]["target"] == "nas.local"
				and recs[1]["port"] == 445, "SRV: %s" % recs[1])
		_check(recs[2]["name"] == "nas.local" and recs[2]["address"] == "192.168.1.30", "A: %s" % recs[2])
	var d := HostDiscovery.new()
	var found: Array = []
	d.host_found.connect(func(h: Dictionary) -> void: found.append(h))
	d._on_mdns(b, "192.168.1.30")
	_check(found.size() == 1 and found[0]["name"] == "nas" and found[0]["address"] == "192.168.1.30"
			and found[0]["label"] == "Media Box", "mDNS host: %s" % [found])
	d.free()
