extends SceneTree

## Media servers (scripts/net/media_servers.gd, http_get.gd) without a network: SSDP headers, a device description with
## an embedded MediaServer and a relative controlURL, a Browse envelope with escaped DIDL, items (video kept, audio
## and image-only skipped, the video resource picked, DLNA byte-seek flag), URL splitting and resolving.
## godot --headless --xr-mode off --path app --script res://tests/test_media_servers.gd

const MediaServers := preload("res://scripts/net/media_servers.gd")
const HttpGet := preload("res://scripts/net/http_get.gd")

const DESCRIPTION := """<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><URLBase>http://10.0.0.5:8200/</URLBase>
<device><deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType><friendlyName>NAS</friendlyName><UDN>uuid:root-1</UDN>
<deviceList><device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
<friendlyName>Films &amp; TV</friendlyName><modelName>m</modelName><UDN>uuid:abc-123</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType><controlURL>/cm</controlURL></service>
<service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:2</serviceType><controlURL>ctl/ContentDir</controlURL></service>
</serviceList></device></deviceList></device></root>"""

const DIDL := """<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
<container id="64$1" parentID="64" childCount="12"><dc:title>Series</dc:title><upnp:class>object.container.storageFolder</upnp:class></container>
<item id="64$2" parentID="64"><dc:title>Lamps &amp; Lanterns</dc:title><upnp:class>object.item.videoItem.movie</upnp:class>
<res protocolInfo="http-get:*:image/jpeg:*">http://10.0.0.5:8200/thumb/2.jpg</res>
<res protocolInfo="http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0" size="1234567" duration="1:02:03.500" resolution="3840x2160">http://10.0.0.5:8200/MediaItems/2.mkv</res></item>
<item id="64$3" parentID="64"><dc:title>Song</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class>
<res protocolInfo="http-get:*:audio/mpeg:*">http://10.0.0.5:8200/MediaItems/3.mp3</res></item>
<item id="64$4" parentID="64"><dc:title>Live</dc:title><upnp:class>object.item.videoItem</upnp:class>
<res protocolInfo="http-get:*:video/mp2t:DLNA.ORG_OP=10">/MediaItems/4.ts</res></item>
</DIDL-Lite>"""

var _fails := 0


func _init() -> void:
	_test_headers()
	_test_description()
	_test_browse()
	_test_urls()
	print("test_media_servers: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + what)


func _test_headers() -> void:
	var h := MediaServers.parse_headers("HTTP/1.1 200 OK\r\nLocation: http://10.0.0.5:8200/rootDesc.xml\r\nST: x\r\n\r\n")
	_check(h.get("location") == "http://10.0.0.5:8200/rootDesc.xml", "SSDP: LOCATION, any case")


func _test_description() -> void:
	var d := MediaServers.parse_description(DESCRIPTION.to_utf8_buffer(), "http://10.0.0.5:8200/rootDesc.xml")
	_check(d.get("uuid") == "abc-123", "description: the embedded MediaServer's UDN (got %s)" % d.get("uuid"))
	_check(d.get("name") == "Films & TV", "description: name unescaped (got %s)" % d.get("name"))
	_check(d.get("control") == "http://10.0.0.5:8200/ctl/ContentDir", "description: controlURL on URLBase (got %s)" % d.get("control"))
	_check(str(d.get("service")).ends_with("ContentDirectory:2"), "description: the service's own version")
	var bad := MediaServers.parse_description("<root><device><friendlyName>x</friendlyName></device></root>".to_utf8_buffer(), "http://a/")
	_check(bad.has("error"), "description without ContentDirectory: an error")


func _test_browse() -> void:
	var envelope := ('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
			+ '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>%s</Result>'
			+ '<NumberReturned>4</NumberReturned><TotalMatches>9</TotalMatches></u:BrowseResponse></s:Body></s:Envelope>') \
			% DIDL.xml_escape()
	var page := MediaServers.parse_browse_response(envelope.to_utf8_buffer())
	_check(page["returned"] == 4 and page["total"] == 9, "browse: counts")
	_check(str(page["result"]).begins_with("<DIDL-Lite"), "browse: Result unescaped")
	var got := MediaServers.parse_didl(page["result"], "http://10.0.0.5:8200/ctl/ContentDir")
	_check(got["containers"].size() == 1 and got["containers"][0]["id"] == "64$1" and got["containers"][0]["count"] == 12,
			"didl: the container, id and child count")
	_check(got["items"].size() == 2, "didl: two videos, the song skipped (got %d)" % got["items"].size())
	var it: Dictionary = got["items"][0]
	_check(it["title"] == "Lamps & Lanterns", "didl: title (got %s)" % it["title"])
	_check(it["url"] == "http://10.0.0.5:8200/MediaItems/2.mkv", "didl: the video resource, not the thumbnail")
	_check(it["mime"] == "video/x-matroska" and it["size"] == 1234567 and it["resolution"] == "3840x2160", "didl: res attributes")
	_check(is_equal_approx(it["duration"], 3723.5), "didl: duration (got %s)" % it["duration"])
	_check(it["seekable"] == true, "didl: DLNA.ORG_OP=01 is byte-seekable")
	var live: Dictionary = got["items"][1]
	_check(live["seekable"] == false, "didl: DLNA.ORG_OP=10 is not byte-seekable")
	_check(live["url"] == "http://10.0.0.5:8200/MediaItems/4.ts", "didl: a relative resource URL resolved")


func _test_urls() -> void:
	_check(HttpGet.split("http://10.0.0.5:8200/a/b?x=1") == ["http", "10.0.0.5", 8200, "/a/b?x=1"], "split: host, port, path")
	_check(HttpGet.split("https://host") == ["https", "host", 443, "/"], "split: defaults")
	_check(HttpGet.split("smb://x/y").is_empty(), "split: not http")
	_check(HttpGet.resolve("http://h:1/dir/desc.xml", "ctl") == "http://h:1/dir/ctl", "resolve: relative")
	_check(HttpGet.resolve("http://h:1/dir/desc.xml", "/ctl") == "http://h:1/ctl", "resolve: absolute path")
	_check(MediaServers.parent_of("upnp://abc/") == "upnp://", "parent: a server's root")
