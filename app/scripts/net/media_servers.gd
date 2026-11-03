extends RefCounted

## Media servers on the LAN (UPnP/DLNA ContentDirectory; ideas #68 and #86; docs/media-servers.md), in GDScript only:
## SSDP discovery (M-SEARCH to 239.255.255.250:1900), the device description, Browse over SOAP, and DIDL-Lite results.
## Videos come out as the HTTP URLs the server gives; MediaSource plays them once the engine reads http:// (requested
## from engine-demux). All of it blocks: call it on a worker thread (browse_commands.gd and the pane do).
##
## Paths, as the file browser uses them:
##   upnp://                       the servers found (discovery runs when none are known, or with discover())
##   upnp://<uuid>/                a server's root;  upnp://<uuid>/<object id, URI-encoded>  a folder
## list(path) -> {entries: [{name, is_dir, size, path, url?, mime?, duration?, resolution?}], error, parent}
## A video's `path` is its http:// URL: main.open_path(url, true, sibling_urls) plays it.

const HttpGet := preload("res://scripts/net/http_get.gd")
const Uri := preload("res://scripts/net/uri.gd")

const SCHEME := "upnp://"
const SSDP_ADDR := "239.255.255.250"
const SSDP_PORT := 1900
const SEARCH_TARGETS: Array[String] = ["urn:schemas-upnp-org:device:MediaServer:1",
		"urn:schemas-upnp-org:service:ContentDirectory:1"]
const PAGE := 200
const MAX_ITEMS := 5000
## Extensions put back on item titles that lack them (the player's list: scripts/video/video_source_factory.gd).
const VIDEO_EXTENSIONS: Array[String] = ["mkv", "mk3d", "mp4", "m4v", "mov", "qt", "avi", "divx", "xvid", "ts", "m2ts",
		"mts", "m2t", "tp", "trp", "webm", "wmv", "asf", "mpg", "mpeg", "mpe", "m1v", "m2v", "mpv", "vob", "evo", "vro",
		"rm", "rmvb", "rv", "flv", "f4v", "ogv", "ogm", "3gp", "3g2", "mxf", "nut", "dv", "dif", "wtv", "dvr-ms", "nsv",
		"ivf", "y4m", "mjpg", "mjpeg", "amv", "bik", "smk", "nuv", "h264", "264", "avc", "h265", "265", "hevc", "obu",
		"h263", "vc1"]

## uuid -> {name, location, control, service, model}
static var servers := {}
## "uuid/object id" -> parent object id, from the listings seen.
static var _parents := {}
static var _lock := Mutex.new()


static func is_upnp(path: String) -> bool:
	return path.begins_with(SCHEME)


## Blocking: M-SEARCH for `seconds`, then each new server's description. Returns the servers known: [{uuid, name, ...}].
static func discover(seconds := 3.0) -> Array:
	var locations := ssdp_search(seconds)
	for loc: String in locations:
		add_server(loc)
	return known()


static func known() -> Array:
	_lock.lock()
	var out: Array = []
	for uuid: String in servers:
		out.append(servers[uuid].merged({"uuid": uuid}))
	_lock.unlock()
	return out


## The LOCATION URLs that answered an M-SEARCH within `seconds` (private addresses only).
static func ssdp_search(seconds: float) -> Array[String]:
	var sock := PacketPeerUDP.new()
	var out: Array[String] = []
	if sock.bind(0, "*") != OK:
		return out
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var next_send := 0
	var sends := 0
	while Time.get_ticks_msec() < end:
		if sends < 2 and Time.get_ticks_msec() >= next_send:
			for st in SEARCH_TARGETS:
				var msg := "M-SEARCH * HTTP/1.1\r\nHOST: %s:%d\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: %s\r\n\r\n" \
						% [SSDP_ADDR, SSDP_PORT, st]
				sock.set_dest_address(SSDP_ADDR, SSDP_PORT)
				sock.put_packet(msg.to_utf8_buffer())
			sends += 1
			next_send = Time.get_ticks_msec() + 700
		while sock.get_available_packet_count() > 0:
			var text := sock.get_packet().get_string_from_utf8()
			var ip := sock.get_packet_ip()
			if not _private(ip):
				continue
			var h := parse_headers(text)
			var loc := str(h.get("location", ""))
			if loc != "" and loc not in out:
				out.append(loc)
		OS.delay_msec(10)
	sock.close()
	return out


static func _private(ip: String) -> bool:
	return ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("127.") \
			or ip.begins_with("169.254.") or (ip.begins_with("172.") and int(ip.get_slice(".", 1)) >= 16
			and int(ip.get_slice(".", 1)) <= 31) or ip.begins_with("fd") or ip.begins_with("fe80") or ip == "::1"


## "HTTP/1.1 200 OK\r\nLOCATION: x\r\n..." -> {"location": "x", ...} (lower-case names).
static func parse_headers(text: String) -> Dictionary:
	var h := {}
	for line in text.split("\n"):
		var i := line.find(":")
		if i > 0:
			h[line.substr(0, i).strip_edges().to_lower()] = line.substr(i + 1).strip_edges()
	return h


## Blocking: reads a device description and remembers the server. {uuid, name, ...} or {error}.
static func add_server(location: String) -> Dictionary:
	var r := HttpGet.request(location, HTTPClient.METHOD_GET, [], "", 5.0)
	if r["error"] != "" or int(r["code"]) != 200:
		return {"error": "%s: %s" % [location, r["error"] if r["error"] != "" else "HTTP %d" % r["code"]]}
	var d := parse_description(r["body"], str(r.get("url", location)))
	if d.has("error"):
		return {"error": "%s: %s" % [location, d["error"]]}
	_lock.lock()
	servers[d["uuid"]] = {"name": d["name"], "location": location, "control": d["control"], "service": d["service"],
			"model": d["model"]}
	_lock.unlock()
	return d


## A device description -> {uuid, name, model, control (absolute URL), service (its serviceType)} or {error}.
static func parse_description(xml: PackedByteArray, location: String) -> Dictionary:
	var p := XMLParser.new()
	if p.open_buffer(xml) != OK:
		return {"error": "not XML"}
	var stack: Array[String] = []
	var text := ""
	var base := ""
	var devices: Array = []        # [{type, name, udn, model}] in document order
	var services: Array = []       # [{type, control}]
	var svc := {}
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := _local(p.get_node_name())
				if not p.is_empty():
					stack.append(n)
				text = ""
				if n == "device":
					devices.append({})
				elif n == "service":
					svc = {}
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				text += p.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var n := _local(p.get_node_name())
				var value := text.strip_edges().xml_unescape()
				if not stack.is_empty():
					stack.pop_back()
				match n:
					"URLBase":
						base = value
					"deviceType", "friendlyName", "UDN", "modelName":
						if not devices.is_empty():
							devices[-1][n] = value
					"serviceType", "controlURL":
						svc[n] = value
					"service":
						services.append(svc)
				text = ""
	var dev: Dictionary = {}
	for d: Dictionary in devices:
		if str(d.get("deviceType", "")).contains("MediaServer"):
			dev = d
			break
	if dev.is_empty() and not devices.is_empty():
		dev = devices[0]
	var cd: Dictionary = {}
	for s: Dictionary in services:
		if str(s.get("serviceType", "")).contains("ContentDirectory"):
			cd = s
			break
	if cd.is_empty():
		return {"error": "no ContentDirectory service (not a media server)"}
	var udn := str(dev.get("UDN", "")).trim_prefix("uuid:")
	if udn == "":
		udn = location.md5_text().substr(0, 12)
	return {"uuid": udn, "name": str(dev.get("friendlyName", "Media server")), "model": str(dev.get("modelName", "")),
			"control": HttpGet.resolve(base if base != "" else location, str(cd.get("controlURL", ""))),
			"service": str(cd.get("serviceType", "urn:schemas-upnp-org:service:ContentDirectory:1"))}


static func _local(name: String) -> String:
	var i := name.find(":")
	return name.substr(i + 1) if i >= 0 else name


## Blocking: a folder's children, all pages. {containers: [...], items: [...], error}.
static func browse(uuid: String, object_id: String) -> Dictionary:
	_lock.lock()
	var s: Dictionary = servers.get(uuid, {})
	_lock.unlock()
	if s.is_empty():
		return {"containers": [], "items": [], "error": "unknown server %s (discover first)" % uuid}
	var containers: Array = []
	var items: Array = []
	var start := 0
	while start < MAX_ITEMS:
		var body := ('<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
				+ ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:Browse xmlns:u="%s">'
				+ '<ObjectID>%s</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter>'
				+ '<StartingIndex>%d</StartingIndex><RequestedCount>%d</RequestedCount><SortCriteria></SortCriteria>'
				+ '</u:Browse></s:Body></s:Envelope>') % [s["service"], object_id.xml_escape(), start, PAGE]
		var r := HttpGet.request(s["control"], HTTPClient.METHOD_POST,
				['Content-Type: text/xml; charset="utf-8"', 'SOAPAction: "%s#Browse"' % s["service"]], body, 10.0)
		if r["error"] != "" or int(r["code"]) != 200:
			var why: String = r["error"] if r["error"] != "" else "HTTP %d%s" % [r["code"], _soap_fault(r["body"])]
			return {"containers": containers, "items": items, "error": "browse %s: %s" % [object_id, why]}
		var page := parse_browse_response(r["body"])
		if page.has("error"):
			return {"containers": containers, "items": items, "error": page["error"]}
		var got: Dictionary = parse_didl(page["result"], str(r.get("url", s["control"])))
		containers.append_array(got["containers"])
		items.append_array(got["items"])
		var returned := int(page["returned"])
		start += returned
		if returned <= 0 or start >= int(page["total"]):
			break
	_lock.lock()
	for c: Dictionary in containers:
		_parents["%s/%s" % [uuid, c["id"]]] = object_id
	_lock.unlock()
	return {"containers": containers, "items": items, "error": ""}


static func _soap_fault(body: PackedByteArray) -> String:
	var t := body.get_string_from_utf8()
	var i := t.find("errorDescription>")
	if i < 0:
		return ""
	var j := t.find("<", i + 17)
	return ": " + t.substr(i + 17, j - i - 17)


## The Browse response envelope -> {result (DIDL-Lite text), returned, total} or {error}.
static func parse_browse_response(xml: PackedByteArray) -> Dictionary:
	var p := XMLParser.new()
	if p.open_buffer(xml) != OK:
		return {"error": "Browse: not XML"}
	var out := {"result": "", "returned": 0, "total": 0}
	var current := ""
	var text := ""
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				current = _local(p.get_node_name())
				text = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				text += p.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				match _local(p.get_node_name()):
					"Result":
						out["result"] = text.xml_unescape() if not text.contains("<DIDL") else text
					"NumberReturned":
						out["returned"] = int(text)
					"TotalMatches":
						out["total"] = int(text)
				text = ""
	return out


## DIDL-Lite -> {containers: [{id, title, count}], items: [{id, title, url, mime, size, duration, resolution, class}]}.
## Videos only (upnp:class object.item.videoItem, or a video/* resource); each item's best resource is its first
## http-get one with a video type (servers list the original first).
static func parse_didl(didl: String, base_url: String) -> Dictionary:
	var out := {"containers": [], "items": []}
	var p := XMLParser.new()
	if didl == "" or p.open_buffer(didl.to_utf8_buffer()) != OK:
		return out
	var obj := {}
	var res: Array = []
	var res_attrs := {}
	var text := ""
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := _local(p.get_node_name())
				text = ""
				if n == "container" or n == "item":
					obj = {"kind": n, "id": _attr(p, "id"), "count": int(_attr(p, "childCount", "-1"))}
					res = []
				elif n == "res":
					res_attrs = {}
					for i in p.get_attribute_count():
						res_attrs[_local(p.get_attribute_name(i))] = p.get_attribute_value(i)
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				text += p.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var n := _local(p.get_node_name())
				var value := text.strip_edges().xml_unescape()
				match n:
					"title":
						obj["title"] = value
					"class":
						obj["class"] = value
					"res":
						res.append(res_attrs.merged({"url": HttpGet.resolve(base_url, value)}))
					"container":
						out["containers"].append({"id": obj["id"], "title": obj.get("title", obj["id"]), "count": obj["count"]})
					"item":
						var best := _best_res(res)
						var is_video := str(obj.get("class", "")).begins_with("object.item.videoItem") \
								or str(best.get("mime", "")).begins_with("video/")
						if is_video and not best.is_empty():
							out["items"].append({"id": obj["id"], "title": obj.get("title", obj["id"]),
									"url": best["url"], "mime": best["mime"], "size": int(best.get("size", "0")),
									"duration": _hms(str(best.get("duration", ""))),
									"resolution": str(best.get("resolution", "")),
									"seekable": best["seekable"], "class": obj.get("class", "")})
				text = ""
	return out


static func _attr(p: XMLParser, name: String, default := "") -> String:
	return p.get_named_attribute_value_safe(name) if p.has_attribute(name) else default


## The first http-get resource with a video type, else the first http one: {url, mime, size, duration, resolution,
## seekable (DLNA.ORG_OP byte-seek flag)}.
static func _best_res(res: Array) -> Dictionary:
	var pick := {}
	for r: Dictionary in res:
		var info := str(r.get("protocolInfo", "")).split(":")
		if info.size() < 3 or info[0] != "http-get" or not str(r["url"]).begins_with("http"):
			continue
		var mime := info[2]
		var cand := r.merged({"mime": mime})
		var op := ""
		if info.size() > 3:
			var m := RegEx.create_from_string("DLNA\\.ORG_OP=(\\d)(\\d)").search(info[3])
			op = m.get_string(2) if m != null else ""
		cand["seekable"] = op != "0"
		if mime.begins_with("video/"):
			return cand
		if pick.is_empty():
			pick = cand
	return pick


## "1:23:45.678" -> seconds; 0 when absent.
static func _hms(s: String) -> float:
	if s == "":
		return 0.0
	var total := 0.0
	for part in s.split(":"):
		total = total * 60.0 + part.to_float()
	return snappedf(total, 0.001)


## Blocking: the file-browser listing of a upnp:// path.
static func list(path: String) -> Dictionary:
	if path == SCHEME or path == "upnp:":
		var list := known()
		if list.is_empty():
			list = discover(3.0)
		var entries: Array = []
		for s: Dictionary in list:
			entries.append({"name": s["name"], "is_dir": true, "size": 0, "path": SCHEME + str(s["uuid"]) + "/"})
		return {"entries": entries, "error": "" if not entries.is_empty() else "no media server answered on the LAN",
				"parent": ""}
	var rest := path.trim_prefix(SCHEME)
	var slash := rest.find("/")
	var uuid := rest if slash < 0 else rest.substr(0, slash)
	var oid := "0" if slash < 0 or rest.substr(slash + 1) == "" else Uri.decode(rest.substr(slash + 1))
	var r := browse(uuid, oid)
	var entries: Array = []
	for c: Dictionary in r["containers"]:
		entries.append({"name": c["title"], "is_dir": true, "size": maxi(int(c["count"]), 0),
				"path": SCHEME + uuid + "/" + str(c["id"]).uri_encode()})
	for it: Dictionary in r["items"]:
		var name := str(it["title"])
		var ext := str(it["url"]).get_file().get_extension().get_slice("?", 0).to_lower()
		if ext in VIDEO_EXTENSIONS and not name.to_lower().ends_with("." + ext):
			name += "." + ext
		entries.append({"name": name, "is_dir": false, "size": it["size"], "path": it["url"], "url": it["url"],
				"mime": it["mime"], "duration": it["duration"], "resolution": it["resolution"],
				"seekable": it["seekable"]})
	return {"entries": entries, "error": r["error"], "parent": parent_of(path)}


static func parent_of(path: String) -> String:
	var rest := path.trim_prefix(SCHEME)
	var slash := rest.find("/")
	if slash < 0 or rest.substr(slash + 1) == "":
		return SCHEME
	var uuid := rest.substr(0, slash)
	var oid := Uri.decode(rest.substr(slash + 1))
	_lock.lock()
	var parent: String = _parents.get("%s/%s" % [uuid, oid], "0")
	_lock.unlock()
	return SCHEME + uuid + "/" + ("" if parent == "0" else parent.uri_encode())
