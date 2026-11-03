extends RefCounted

## QR code encoder (ISO/IEC 18004), no library: byte mode, versions 1 to 10 (up to 213 bytes at level M), error
## correction L, M, Q or H, the mask chosen by the standard's penalty rules. For the phone remote's address
## (remote_server.gd), but general. The structure follows the well-known reference algorithm: data codewords,
## Reed-Solomon blocks interleaved, function patterns, zig-zag placement, masking, format and version bits.
##
##   var m := QrCode.encode("http://192.168.1.50:47880/?k=abc")   # Array of PackedByteArray rows, 1 = dark
##   var img := QrCode.to_image(m, 8)                               # white border of 4 modules

const MAX_VERSION := 10
## Error correction levels: index into the tables, and the 2 format bits.
const ECL := {"L": [0, 1], "M": [1, 0], "Q": [2, 3], "H": [3, 2]}
## ECC codewords per block, [level][version] (version 0 unused).
const ECC_PER_BLOCK := [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26],
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24],
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28],
]
## Number of error correction blocks, [level][version].
const NUM_BLOCKS := [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5],
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8],
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8],
]


## The QR matrix for `text` (UTF-8), smallest version that fits: Array of PackedByteArray rows (1 dark, 0 light).
## Empty when the text is too long for version 10.
static func encode(text: String, level := "M") -> Array:
	var data := text.to_utf8_buffer()
	var ecl: Array = ECL.get(level, ECL["M"])
	var version := 0
	for v in range(1, MAX_VERSION + 1):
		var count_bits := 8 if v <= 9 else 16
		if 4 + count_bits + data.size() * 8 <= _data_codewords(v, ecl[0]) * 8:
			version = v
			break
	if version == 0:
		return []
	# Bit stream: byte mode, length, data, terminator, pad to a byte, pad bytes.
	var bits: Array[int] = []
	_append_bits(bits, 0x4, 4)
	_append_bits(bits, data.size(), 8 if version <= 9 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity := _data_codewords(version, ecl[0]) * 8
	_append_bits(bits, 0, mini(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < capacity:
		_append_bits(bits, pad, 8)
		pad ^= 0xEC ^ 0x11
	var codewords := PackedByteArray()
	codewords.resize(bits.size() / 8)
	for i in bits.size():
		codewords[i >> 3] |= bits[i] << (7 - (i & 7))
	var all := _add_ecc_and_interleave(codewords, version, ecl[0])

	var size := version * 4 + 17
	var modules: Array = []
	var is_function: Array = []
	for y in size:
		var row := PackedByteArray()
		row.resize(size)
		modules.append(row)
		var frow := PackedByteArray()
		frow.resize(size)
		is_function.append(frow)
	_draw_function_patterns(modules, is_function, version, ecl[1])
	_draw_codewords(modules, is_function, all)
	# Pick the mask with the lowest penalty.
	var best := 0
	var best_penalty := 1 << 30
	for mask in 8:
		_apply_mask(modules, is_function, mask)
		_draw_format_bits(modules, is_function, ecl[1], mask)
		var p := _penalty(modules)
		if p < best_penalty:
			best = mask
			best_penalty = p
		_apply_mask(modules, is_function, mask)  # XOR again: undo
	_apply_mask(modules, is_function, best)
	_draw_format_bits(modules, is_function, ecl[1], best)
	return modules


## An image of the matrix: `scale` pixels per module, a light border of `border` modules.
static func to_image(modules: Array, scale := 8, border := 4, dark := Color.BLACK, light := Color.WHITE) -> Image:
	var n := modules.size()
	var px := (n + border * 2) * scale
	var img := Image.create_empty(maxi(px, 1), maxi(px, 1), false, Image.FORMAT_RGB8)
	img.fill(light)
	for y in n:
		var row: PackedByteArray = modules[y]
		for x in n:
			if row[x] == 1:
				img.fill_rect(Rect2i((x + border) * scale, (y + border) * scale, scale, scale), dark)
	return img


## The matrix as text, two characters per module ("##" dark), for logs and tests.
static func to_text(modules: Array) -> String:
	var lines: Array[String] = []
	for row: PackedByteArray in modules:
		var s := ""
		for v in row:
			s += "##" if v == 1 else "  "
		lines.append(s)
	return "\n".join(lines)


static func _append_bits(bits: Array[int], value: int, length: int) -> void:
	for i in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


static func _raw_data_modules(ver: int) -> int:
	var result := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var num_align := ver / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if ver >= 7:
			result -= 36
	return result


static func _data_codewords(ver: int, ecl_index: int) -> int:
	return _raw_data_modules(ver) / 8 - ECC_PER_BLOCK[ecl_index][ver] * NUM_BLOCKS[ecl_index][ver]


static func _add_ecc_and_interleave(data: PackedByteArray, ver: int, ecl_index: int) -> PackedByteArray:
	var num_blocks: int = NUM_BLOCKS[ecl_index][ver]
	var ecc_len: int = ECC_PER_BLOCK[ecl_index][ver]
	var raw := _raw_data_modules(ver) / 8
	var num_short := num_blocks - raw % num_blocks
	var short_len := raw / num_blocks
	var divisor := _rs_divisor(ecc_len)
	var blocks: Array[PackedByteArray] = []
	var k := 0
	for i in num_blocks:
		var n := short_len - ecc_len + (0 if i < num_short else 1)
		var dat := data.slice(k, k + n)
		k += n
		var ecc := _rs_remainder(dat, divisor)
		if i < num_short:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var out := PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= num_short:
				out.append(blocks[j][i])
	return out


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result = result.slice(1)
		result.append(0)
		for i in divisor.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


static func _put(modules: Array, is_function: Array, x: int, y: int, dark: bool) -> void:
	modules[y][x] = 1 if dark else 0
	is_function[y][x] = 1


static func _draw_function_patterns(modules: Array, is_function: Array, ver: int, format_bits: int) -> void:
	var size := modules.size()
	for i in size:
		_put(modules, is_function, 6, i, i % 2 == 0)
		_put(modules, is_function, i, 6, i % 2 == 0)
	for c: Vector2i in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var xx := c.x + dx
				var yy := c.y + dy
				if xx >= 0 and xx < size and yy >= 0 and yy < size:
					var dist := maxi(absi(dx), absi(dy))
					_put(modules, is_function, xx, yy, dist != 2 and dist != 4)
	var pos := _alignment_positions(ver)
	var n := pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_put(modules, is_function, pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	# Reserve the format areas (real bits drawn after masking).
	_draw_format_bits(modules, is_function, format_bits, 0)
	if ver >= 7:
		var rem := ver
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits := (ver << 12) | rem
		for i in 18:
			var bit := ((bits >> i) & 1) != 0
			var a := size - 11 + i % 3
			var b := i / 3
			_put(modules, is_function, a, b, bit)
			_put(modules, is_function, b, a, bit)


static func _alignment_positions(ver: int) -> Array[int]:
	if ver == 1:
		return []
	var num_align := ver / 7 + 2
	var size := ver * 4 + 17
	var step := (ver * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
	var result: Array[int] = [6]
	var p := size - 7
	while result.size() < num_align:
		result.insert(1, p)
		p -= step
	return result


static func _draw_format_bits(modules: Array, is_function: Array, format_bits: int, mask: int) -> void:
	var data := (format_bits << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	var size := modules.size()
	var bit := func(i: int) -> bool: return ((bits >> i) & 1) != 0
	for i in 6:
		_put(modules, is_function, 8, i, bit.call(i))
	_put(modules, is_function, 8, 7, bit.call(6))
	_put(modules, is_function, 8, 8, bit.call(7))
	_put(modules, is_function, 7, 8, bit.call(8))
	for i in range(9, 15):
		_put(modules, is_function, 14 - i, 8, bit.call(i))
	for i in 8:
		_put(modules, is_function, size - 1 - i, 8, bit.call(i))
	for i in range(8, 15):
		_put(modules, is_function, 8, size - 15 + i, bit.call(i))
	_put(modules, is_function, 8, size - 8, true)


static func _draw_codewords(modules: Array, is_function: Array, data: PackedByteArray) -> void:
	var size := modules.size()
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if is_function[y][x] == 0 and i < data.size() * 8:
					modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


static func _apply_mask(modules: Array, is_function: Array, mask: int) -> void:
	var size := modules.size()
	for y in size:
		for x in size:
			if is_function[y][x] == 1:
				continue
			var invert := false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y][x] ^= 1


## The standard's penalty: runs of 5+, 2x2 blocks, finder-like patterns, dark/light balance.
static func _penalty(modules: Array) -> int:
	var size := modules.size()
	var result := 0
	var finder := [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
	var finder_rev := [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
	for pass_ in 2:
		for a in size:
			var run := 1
			for b in range(1, size + 1):
				var same := false
				if b < size:
					var cur: int = modules[a][b] if pass_ == 0 else modules[b][a]
					var prev: int = modules[a][b - 1] if pass_ == 0 else modules[b - 1][a]
					same = cur == prev
				if same:
					run += 1
				else:
					if run >= 5:
						result += 3 + (run - 5)
					run = 1
			for b in range(0, size - 10):
				var m1 := true
				var m2 := true
				for k in 11:
					var v: int = modules[a][b + k] if pass_ == 0 else modules[b + k][a]
					if v != finder[k]:
						m1 = false
					if v != finder_rev[k]:
						m2 = false
				if m1:
					result += 40
				if m2:
					result += 40
	var dark := 0
	for y in size:
		for x in size:
			dark += modules[y][x]
			if y < size - 1 and x < size - 1:
				var c: int = modules[y][x]
				if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
					result += 3
	var total := size * size
	var k2 := (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += maxi(k2, 0) * 10
	return result
