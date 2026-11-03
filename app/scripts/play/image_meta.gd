extends RefCounted

## What a photo file says about itself (ideas #22), read from its bytes. Static; preload to use.
##
##   exif_orientation(bytes) -> 1..8      JPEG EXIF orientation (1: as stored)
##   apply_orientation(image, o)          turns / mirrors an Image so it shows upright
##   xmp(bytes) -> String                 the XMP packet: JPEG APP1, PNG iTXt "XML:com.adobe.xmp", WebP "XMP " chunk
##   extended_xmp(bytes) -> String        JPEG extended XMP (several APP1 parts, joined in offset order)
##   xmp_value(xmp, name) -> String       an XMP property as an attribute (GPano:X="v") or an element (<GPano:X>v<)
##   gpano(xmp) -> {}                     photo-sphere fields, or {} without GPano:ProjectionType:
##                                        {projection, full_w, full_h, crop_w, crop_h, crop_left, crop_top}
##   right_eye_jpeg(bytes) -> PackedByteArray   VR180 photos: the right eye's JPEG in GImage:Data (base64), or []
##   mpo_images(bytes) -> Array[PackedByteArray]   the images of an MPO (MPF index in APP2), or [] when none

const XMP_ID := "http://ns.adobe.com/xap/1.0/"
const EXT_XMP_ID := "http://ns.adobe.com/xmp/extension/"


## JPEG marker segments before the image data: [{marker, start (of the payload), length (of the payload)}].
static func jpeg_segments(b: PackedByteArray) -> Array:
	var out: Array = []
	if b.size() < 4 or b[0] != 0xFF or b[1] != 0xD8:
		return out
	var i := 2
	while i + 4 <= b.size():
		if b[i] != 0xFF:
			break
		var marker := b[i + 1]
		if marker == 0xFF:
			i += 1
			continue
		if marker == 0xD9 or marker == 0xDA:
			break
		var length := (b[i + 2] << 8) | b[i + 3]
		if length < 2 or i + 2 + length > b.size():
			break
		out.append({"marker": marker, "start": i + 4, "length": length - 2})
		i += 2 + length
	return out


static func _starts_with(b: PackedByteArray, at: int, text: String) -> bool:
	var t := text.to_ascii_buffer()
	if at + t.size() > b.size():
		return false
	for k in t.size():
		if b[at + k] != t[k]:
			return false
	return true


static func _u16(b: PackedByteArray, at: int, le: bool) -> int:
	return (b[at] | (b[at + 1] << 8)) if le else ((b[at] << 8) | b[at + 1])


static func _u32(b: PackedByteArray, at: int, le: bool) -> int:
	if le:
		return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func exif_orientation(b: PackedByteArray) -> int:
	for s: Dictionary in jpeg_segments(b):
		if s["marker"] != 0xE1 or not _starts_with(b, s["start"], "Exif"):
			continue
		var t: int = s["start"] + 6
		var end: int = s["start"] + s["length"]
		if t + 8 > end:
			return 1
		var le := b[t] == 0x49
		var ifd: int = t + _u32(b, t + 4, le)
		if ifd + 2 > end:
			return 1
		var n := _u16(b, ifd, le)
		for k in n:
			var e := ifd + 2 + k * 12
			if e + 12 > end:
				break
			if _u16(b, e, le) == 0x0112:
				var o := _u16(b, e + 8, le)
				return o if o >= 1 and o <= 8 else 1
		return 1
	return 1


static func apply_orientation(img: Image, o: int) -> void:
	match o:
		2:
			img.flip_x()
		3:
			img.rotate_180()
		4:
			img.flip_y()
		5:
			img.rotate_90(CLOCKWISE)
			img.flip_x()
		6:
			img.rotate_90(CLOCKWISE)
		7:
			img.rotate_90(CLOCKWISE)
			img.flip_y()
		8:
			img.rotate_90(COUNTERCLOCKWISE)


static func xmp(b: PackedByteArray) -> String:
	if b.size() >= 2 and b[0] == 0xFF and b[1] == 0xD8:
		for s: Dictionary in jpeg_segments(b):
			if s["marker"] == 0xE1 and _starts_with(b, s["start"], XMP_ID):
				var off: int = s["start"] + XMP_ID.length() + 1
				return b.slice(off, s["start"] + s["length"]).get_string_from_utf8()
		return ""
	if b.size() > 8 and b[0] == 0x89 and _starts_with(b, 1, "PNG"):
		var i := 8
		while i + 12 <= b.size():
			var length := _u32(b, i, false)
			if _starts_with(b, i + 4, "iTXt") and _starts_with(b, i + 8, "XML:com.adobe.xmp"):
				# keyword \0, compression flag, method, language \0, translated keyword \0, text (uncompressed)
				var data := b.slice(i + 8, i + 8 + length)
				var k := data.find(0) + 3
				k = data.find(0, k) + 1
				k = data.find(0, k) + 1
				return data.slice(k).get_string_from_utf8() if k > 0 else ""
			if _starts_with(b, i + 4, "IEND"):
				break
			i += 12 + length
		return ""
	if _starts_with(b, 0, "RIFF") and _starts_with(b, 8, "WEBP"):
		var i := 12
		while i + 8 <= b.size():
			var length := _u32(b, i + 4, true)
			if _starts_with(b, i, "XMP "):
				return b.slice(i + 8, i + 8 + length).get_string_from_utf8()
			i += 8 + length + (length & 1)
	return ""


static func extended_xmp(b: PackedByteArray) -> String:
	var parts := {}
	var total := 0
	for s: Dictionary in jpeg_segments(b):
		if s["marker"] != 0xE1 or not _starts_with(b, s["start"], EXT_XMP_ID):
			continue
		# id \0, 32-byte GUID, 4-byte full length, 4-byte offset, data
		var h: int = s["start"] + EXT_XMP_ID.length() + 1 + 32
		total = _u32(b, h, false)
		parts[_u32(b, h + 4, false)] = b.slice(h + 8, s["start"] + s["length"])
	if parts.is_empty():
		return ""
	var keys := parts.keys()
	keys.sort()
	var all := PackedByteArray()
	for k: int in keys:
		all.append_array(parts[k])
	return all.slice(0, total if total > 0 else all.size()).get_string_from_utf8()


static func xmp_value(x: String, name: String) -> String:
	if x == "":
		return ""
	var re := RegEx.create_from_string(name.replace(".", "\\.") + "\\s*=\\s*[\"']([^\"']*)[\"']")
	var m := re.search(x)
	if m != null:
		return m.get_string(1)
	re = RegEx.create_from_string("<" + name + ">([^<]*)</" + name + ">")
	m = re.search(x)
	return m.get_string(1).strip_edges() if m != null else ""


static func gpano(x: String) -> Dictionary:
	var projection := xmp_value(x, "GPano:ProjectionType").to_lower()
	if projection == "":
		return {}
	var g := {"projection": projection}
	for k: String in ["FullPanoWidthPixels", "FullPanoHeightPixels", "CroppedAreaImageWidthPixels",
			"CroppedAreaImageHeightPixels", "CroppedAreaLeftPixels", "CroppedAreaTopPixels"]:
		g[k] = xmp_value(x, "GPano:" + k).to_int()
	return {"projection": projection, "full_w": g["FullPanoWidthPixels"], "full_h": g["FullPanoHeightPixels"],
			"crop_w": g["CroppedAreaImageWidthPixels"], "crop_h": g["CroppedAreaImageHeightPixels"],
			"crop_left": g["CroppedAreaLeftPixels"], "crop_top": g["CroppedAreaTopPixels"]}


static func right_eye_jpeg(b: PackedByteArray) -> PackedByteArray:
	var data := xmp_value(extended_xmp(b), "GImage:Data")
	if data == "":
		data = xmp_value(xmp(b), "GImage:Data")
	return Marshalls.base64_to_raw(data) if data != "" else PackedByteArray()


static func mpo_images(b: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for s: Dictionary in jpeg_segments(b):
		if s["marker"] != 0xE2 or not _starts_with(b, s["start"], "MPF"):
			continue
		var t: int = s["start"] + 4
		var le := b[t] == 0x49
		var ifd: int = t + _u32(b, t + 4, le)
		var n := _u16(b, ifd, le)
		for k in n:
			var e := ifd + 2 + k * 12
			if _u16(b, e, le) != 0xB002:
				continue
			var count := _u32(b, e + 4, le) / 16
			var entries: int = t + _u32(b, e + 8, le)
			for j in count:
				var en := entries + j * 16
				if en + 16 > b.size():
					break
				var size := _u32(b, en + 4, le)
				# The first image's offset is 0 (the file's start); the others count from the MPF header.
				var off := _u32(b, en + 8, le)
				var from := 0 if off == 0 else t + off
				if size > 0 and from + size <= b.size():
					out.append(b.slice(from, from + size))
		return out
	return out
