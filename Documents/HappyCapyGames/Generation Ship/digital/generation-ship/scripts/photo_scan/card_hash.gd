class_name CardHash
extends RefCounted

# Difference-hash (dHash) sized to the card's own aspect ratio, rather than
# the usual square 8x8/9x8 grid, so more of the hash bits reflect real
# card-art structure instead of aspect distortion.
#
# Recalibrated 2026-09-21 against real photos of the physical game (a photo
# of "Seasons" scored WORSE against its own correct reference than an
# unrelated card at the original 9x12/horizontal-only/no-white-balance
# settings). Two changes, validated together against several real photographed
# cards with known ground truth:
#
# 1. Gray-world white balance before hashing: a real photo's overall color
#    cast (camera white balance, ambient lighting) shifts the printed card's
#    actual colors enough to measurably change which cells look lighter/
#    darker than their neighbors -- rescaling each of R/G/B so their average
#    across the image matches (the "gray world" assumption: a sufficiently
#    varied image's average color should be roughly neutral) cancels most of
#    that cast. Applied to BOTH sides of every comparison (the reference art
#    has its own, much smaller, cast too) so this must run inside
#    compute_hash() itself, not as a separate step some caller might forget.
# 2. A bigger 16x22 grid, and BOTH horizontal and vertical neighbor
#    comparisons (not just horizontal) -- more than doubles the original
#    96-bit hash's resolution and roughly triples its bit count, giving real
#    photographed cards (rank #1 and #2 of 137 on the two tech cards tested,
#    up from unranked/tied-with-wrong-answers before) enough signal to stand
#    out from similar-looking cards. Smaller (9x12) and much bigger (20x28)
#    grids were both tried and scored worse on the same test photos -- this
#    isn't "more resolution is strictly better", it's a specific sweet spot,
#    so don't casually retune without re-testing against real photos.
const HASH_W: int = 16
const HASH_H: int = 22

static func compute_hash(source: Image, hash_w: int = HASH_W, hash_h: int = HASH_H) -> String:
	var work: Image = _white_balance(source)
	work.resize(hash_w, hash_h, Image.INTERPOLATE_LANCZOS)

	var lum := []
	lum.resize(hash_w * hash_h)
	for y: int in range(hash_h):
		for x: int in range(hash_w):
			lum[y * hash_w + x] = _luminance(work.get_pixel(x, y))

	var bits: String = ""
	for y: int in range(hash_h):
		for x: int in range(hash_w - 1):
			bits += "1" if lum[y * hash_w + x] < lum[y * hash_w + x + 1] else "0"
	for y: int in range(hash_h - 1):
		for x: int in range(hash_w):
			bits += "1" if lum[y * hash_w + x] < lum[(y + 1) * hash_w + x] else "0"
	return bits

## Gray-world white balance: rescales each of R/G/B so their average across
## the image's opaque pixels matches the overall gray average, canceling most
## of a global color cast (camera white balance, ambient lighting tint).
static func _white_balance(source: Image) -> Image:
	var work: Image = source.duplicate()
	if work.is_compressed():
		work.decompress()
	work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()

	var sum_r: float = 0.0
	var sum_g: float = 0.0
	var sum_b: float = 0.0
	var n: int = 0
	for y: int in range(h):
		for x: int in range(w):
			var c: Color = work.get_pixel(x, y)
			if c.a < 0.5:
				continue
			sum_r += c.r
			sum_g += c.g
			sum_b += c.b
			n += 1
	if n == 0:
		return work

	var avg_r: float = sum_r / n
	var avg_g: float = sum_g / n
	var avg_b: float = sum_b / n
	var gray: float = (avg_r + avg_g + avg_b) / 3.0
	var scale_r: float = gray / avg_r if avg_r > 0.01 else 1.0
	var scale_g: float = gray / avg_g if avg_g > 0.01 else 1.0
	var scale_b: float = gray / avg_b if avg_b > 0.01 else 1.0

	for y: int in range(h):
		for x: int in range(w):
			var c: Color = work.get_pixel(x, y)
			work.set_pixel(x, y, Color(
				clampf(c.r * scale_r, 0.0, 1.0),
				clampf(c.g * scale_g, 0.0, 1.0),
				clampf(c.b * scale_b, 0.0, 1.0),
				c.a
			))
	return work

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
