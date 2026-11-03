extends RefCounted

## Percent-decoding that accepts lowercase hex. The engine's String.uri_decode() reads only uppercase (%3A), and turns
## "%3a" into "3a", silently: seen with an assistant's client, whose /list?path=smb%3a%2f%2f... became
## "smb3a2f2f...". Plus signs are left alone (form decoding turns them into spaces first).
##
##   const Uri := preload("res://scripts/net/uri.gd")
##   Uri.decode("smb%3a%2F%2Fhost")   # "smb://host"


static func decode(s: String) -> String:
	if not s.contains("%"):
		return s
	var src := s.to_utf8_buffer()
	var out := PackedByteArray()
	var i := 0
	while i < src.size():
		var b := src[i]
		if b == 37 and i + 2 < src.size():  # "%" and two more bytes
			var hi := _hex(src[i + 1])
			var lo := _hex(src[i + 2])
			if hi >= 0 and lo >= 0:
				out.append(hi * 16 + lo)
				i += 3
				continue
		out.append(b)
		i += 1
	return out.get_string_from_utf8()


static func _hex(c: int) -> int:
	if c >= 48 and c <= 57:
		return c - 48
	if c >= 65 and c <= 70:
		return c - 55
	if c >= 97 and c <= 102:
		return c - 87
	return -1
