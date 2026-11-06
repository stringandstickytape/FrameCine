extends RefCounted

## A GIF's first frame as an image (the engine reads JPEG, PNG and WebP, not GIF): the picture library keeps a GIF
## saved to Downloads as its first frame (scripts/pictures/picture_library.gd). GIF87a and GIF89a, global and local
## colour tables, the first frame's transparent colour, interlaced or not; the frame laid on the logical screen,
## transparent elsewhere. Data only: nothing in the file is run.
##
##   GifDecode.first_frame(bytes) -> Image (RGBA8) or null

## Larger than this a side is not read (the library keeps 2048 anyway).
const MAX_SIDE := 8192


static func first_frame(b: PackedByteArray) -> Image:
	if b.size() < 13 or b.slice(0, 3).get_string_from_ascii() != "GIF":
		return null
	var sw := b.decode_u16(6)
	var sh := b.decode_u16(8)
	if sw == 0 or sh == 0 or sw > MAX_SIDE or sh > MAX_SIDE:
		return null
	var flags := b[10]
	var at := 13
	var global := PackedByteArray()
	if flags & 0x80:
		var n := 3 * (1 << ((flags & 7) + 1))
		if at + n > b.size():
			return null
		global = b.slice(at, at + n)
		at += n
	var transparent := -1
	while at < b.size():
		var block := b[at]
		at += 1
		if block == 0x21:
			if at >= b.size():
				return null
			var label := b[at]
			at += 1
			if label == 0xF9 and at + 5 < b.size() and b[at] >= 4:
				if b[at + 1] & 1:
					transparent = b[at + 4]
			at = _skip_blocks(b, at)
			if at < 0:
				return null
		elif block == 0x2C:
			return _frame(b, at, sw, sh, global, transparent)
		else:
			# 0x3B (the end) or anything else: no frame.
			return null
	return null


static func _skip_blocks(b: PackedByteArray, at: int) -> int:
	while at < b.size():
		var n := b[at]
		at += 1
		if n == 0:
			return at
		at += n
	return -1


static func _frame(b: PackedByteArray, at: int, sw: int, sh: int, global: PackedByteArray, transparent: int) -> Image:
	if at + 9 > b.size():
		return null
	var fx := b.decode_u16(at)
	var fy := b.decode_u16(at + 2)
	var fw := b.decode_u16(at + 4)
	var fh := b.decode_u16(at + 6)
	var flags := b[at + 8]
	at += 9
	var table := global
	if flags & 0x80:
		var n := 3 * (1 << ((flags & 7) + 1))
		if at + n > b.size():
			return null
		table = b.slice(at, at + n)
		at += n
	if table.is_empty() or fw == 0 or fh == 0 or at >= b.size():
		return null
	var min_code := b[at]
	at += 1
	if min_code < 2 or min_code > 11:
		return null
	# The image data's sub-blocks joined.
	var data := PackedByteArray()
	while at < b.size():
		var n := b[at]
		at += 1
		if n == 0:
			break
		data.append_array(b.slice(at, at + n))
		at += n
	var indices := _lzw(data, min_code, fw * fh)
	if indices.is_empty():
		return null
	var rows := PackedInt32Array()
	rows.resize(fh)
	if flags & 0x40:
		var r := 0
		for pass_start_step: Array in [[0, 8], [4, 8], [2, 4], [1, 2]]:
			var y: int = pass_start_step[0]
			while y < fh:
				rows[r] = y
				r += 1
				y += int(pass_start_step[1])
	else:
		for y in fh:
			rows[y] = y
	var out := PackedByteArray()
	out.resize(sw * sh * 4)
	var colours := table.size() / 3
	for r in fh:
		var y := fy + rows[r]
		if y >= sh:
			continue
		for x in fw:
			var px := fx + x
			if px >= sw:
				continue
			var i := r * fw + x
			if i >= indices.size():
				break
			var c := indices[i]
			if c == transparent or c >= colours:
				continue
			var o := (y * sw + px) * 4
			out[o] = table[c * 3]
			out[o + 1] = table[c * 3 + 1]
			out[o + 2] = table[c * 3 + 2]
			out[o + 3] = 255
	return Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, out)


## GIF's LZW: codes of growing width, least significant bit first; a clear code starts the table again.
static func _lzw(data: PackedByteArray, min_code: int, want: int) -> PackedByteArray:
	var clear := 1 << min_code
	var stop := clear + 1
	var out := PackedByteArray()
	var prefix := PackedInt32Array()
	var suffix := PackedByteArray()
	prefix.resize(4096)
	suffix.resize(4096)
	for i in clear:
		suffix[i] = i
	var next := clear + 2
	var width := min_code + 1
	var prev := -1
	var bits := 0
	var acc := 0
	var stack := PackedByteArray()
	for byte in data:
		acc |= byte << bits
		bits += 8
		while bits >= width:
			var code := acc & ((1 << width) - 1)
			acc >>= width
			bits -= width
			if code == clear:
				next = clear + 2
				width = min_code + 1
				prev = -1
				continue
			if code == stop:
				return out
			var first := 0
			var c := code
			stack.clear()
			if code >= next:
				if prev < 0 or code > next:
					return out
				# The KwKwK case: the previous string and its own first byte.
				c = prev
			while c >= clear:
				stack.append(suffix[c])
				c = prefix[c]
			stack.append(c)
			first = c
			for k in range(stack.size() - 1, -1, -1):
				out.append(stack[k])
			if code >= next:
				out.append(first)
			if prev >= 0 and next < 4096:
				prefix[next] = prev
				suffix[next] = first
				next += 1
				if next == (1 << width) and width < 12:
					width += 1
			prev = code
			if out.size() >= want:
				return out
	return out
