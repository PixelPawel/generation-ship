class_name CardHash
extends RefCounted

# Difference-hash (dHash) sized to the card's own 63.5:89mm aspect ratio,
# rather than the usual square 8x8/9x8 grid, so more of the hash bits reflect
# real card-art structure instead of aspect distortion. 8 wide x 12 tall
# horizontal-difference bits -> 96-bit hash, stored as a '0'/'1' string so it
# round-trips through JSON without needing 96-bit int packing.
const HASH_W: int = 9
const HASH_H: int = 12

static func compute_hash(source: Image, hash_w: int = HASH_W, hash_h: int = HASH_H) -> String:
	var work: Image = source.duplicate()
	if work.is_compressed():
		work.decompress()
	work.convert(Image.FORMAT_RGBA8)
	work.resize(hash_w, hash_h, Image.INTERPOLATE_LANCZOS)

	var bits: String = ""
	for y: int in range(hash_h):
		for x: int in range(hash_w - 1):
			var l: float = _luminance(work.get_pixel(x, y))
			var r: float = _luminance(work.get_pixel(x + 1, y))
			bits += "1" if l < r else "0"
	return bits

static func _luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

static func hamming_distance(a: String, b: String) -> int:
	var n: int = mini(a.length(), b.length())
	var d: int = 0
	for i: int in range(n):
		if a[i] != b[i]:
			d += 1
	d += absi(a.length() - b.length())
	return d
