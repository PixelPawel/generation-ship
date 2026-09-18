class_name CardDetector
extends RefCounted

# Finds card-shaped regions in a photo of a few cards fanned out on a plain
# table (the guided per-sector capture flow — see the photo-scan plan).
# Cards are colorful against the game's neutral gray/felt table in every
# reference photo we have, so a saturation/value-vs-background threshold
# segments them cleanly without needing real edge/contour CV.
#
# Godot's BitMap.opaque_to_polygons() (normally used to turn a sprite's alpha
# channel into collision polygons) does the connected-component contour
# extraction for us — no need to hand-roll flood fill/union-find.
#
# Validation status (2026-09-18, against synthetic composites of real card
# art on a gray background — no physical copy available to photograph yet):
# detect() reliably finds the right NUMBER of cards with plausible card-ratio
# bounding boxes. extract_card()+CardMatcher end-to-end identification is
# still inconsistent (1 of 4 correct in the last test run) — the straightened
# crop's exact framing/scale doesn't yet line up tightly enough with the
# reference art's edge-to-edge framing to survive hashing reliably. Likely
# needs either a tighter/more precise mask boundary (the segmentation edge
# may include a sliver of background or clip part of the card's own border)
# or a margin-search step that tries a few crop insets and keeps the best
# match. Finishing this calibration properly really wants real photos of
# real physical cards, not more synthetic tests — revisit once the physical
# copy is available.

const CARD_ASPECT: float = 63.5 / 89.0
const ASPECT_TOLERANCE: float = 0.30  # accept ratio within this of CARD_ASPECT
const MIN_AREA_FRACTION: float = 0.01  # relative to the (downscaled) detection image
const DETECT_WIDTH: int = 900  # downscale target for the segmentation pass — plenty for blob shapes, keeps the per-pixel scan fast

## Returns an Array[Dictionary] of candidate cards, sorted left-to-right
## (fan/stack order matters for "top card" scoring effects). Each entry is
## {"rect": Rect2i, "centroid": Vector2, "angle": float}, rect/centroid in the
## ORIGINAL image's coordinates. Pass an entry to extract_card() to get a
## straightened, hashable crop — a rotated card's own axis-aligned bounding
## box still pulls in background/neighboring-card pixels, so detect() alone
## isn't enough.
static func detect(source: Image) -> Array[Dictionary]:
	var scale: float = float(DETECT_WIDTH) / float(source.get_width())
	var work: Image = source.duplicate()
	if work.is_compressed():
		work.decompress()
	work.convert(Image.FORMAT_RGBA8)
	var detect_h: int = maxi(1, roundi(source.get_height() * scale))
	work.resize(DETECT_WIDTH, detect_h, Image.INTERPOLATE_BILINEAR)

	var bg: Color = _sample_background(work)
	var bitmap: BitMap = BitMap.new()
	bitmap.create(Vector2i(DETECT_WIDTH, detect_h))
	for y: int in range(detect_h):
		for x: int in range(DETECT_WIDTH):
			bitmap.set_bit(x, y, _looks_like_card(work.get_pixel(x, y), bg))

	# Close small gaps (JPEG noise, thin dark card borders reading as
	# "background") and drop speckle before extracting contours.
	bitmap.grow_mask(1, Rect2i(Vector2i.ZERO, Vector2i(DETECT_WIDTH, detect_h)))
	bitmap.grow_mask(-1, Rect2i(Vector2i.ZERO, Vector2i(DETECT_WIDTH, detect_h)))

	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, Vector2i(DETECT_WIDTH, detect_h)), 2.0)

	var min_area: float = MIN_AREA_FRACTION * DETECT_WIDTH * detect_h
	var candidates: Array[Dictionary] = []
	for poly: PackedVector2Array in polygons:
		var bbox: Rect2 = _bounding_box(poly)
		if bbox.get_area() < min_area:
			continue
		var ratio: float = minf(bbox.size.x, bbox.size.y) / maxf(bbox.size.x, bbox.size.y)
		if absf(ratio - CARD_ASPECT) > ASPECT_TOLERANCE:
			continue

		# Orientation must come from the actual mask PIXELS (area moments),
		# not the polygon's boundary vertices — a blocky staircase contour
		# from a low-res bitmap has wildly uneven vertex density along its
		# jagged edges, which badly biases a vertex-based PCA estimate.
		var moments: Dictionary = _mask_moments(bitmap, Rect2i(bbox).grow(2))
		var full_res_rect: Rect2 = Rect2(bbox.position / scale, bbox.size / scale)
		candidates.append({
			"rect": Rect2i(full_res_rect),
			"centroid": (moments["centroid"] as Vector2) / scale,
			"angle": moments["angle"],  # rotation is scale-invariant
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["rect"] as Rect2i).position.x < (b["rect"] as Rect2i).position.x)
	return candidates

## Groups detected candidates into per-sector clusters by spatial proximity —
## for a single whole-tableau photo covering every sector at once: each
## sector's own card group (sector + techs + tucked) sits close together,
## with a visible gap to the next sector's group. Returns Array[Array] of
## candidate-dictionary arrays, one per cluster, sorted left-to-right by the
## cluster's own leftmost edge. Untested against real photos (see file-level
## note) — the gap threshold below is a starting guess, not a tuned value.
static func cluster_candidates(candidates: Array[Dictionary]) -> Array:
	if candidates.is_empty():
		return []
	var widths: Array[float] = []
	for c: Dictionary in candidates:
		widths.append(float((c["rect"] as Rect2i).size.x))
	widths.sort()
	var median_width: float = widths[widths.size() / 2]
	var gap_threshold: float = median_width * 0.75

	var n: int = candidates.size()
	var parent: Array[int] = []
	for i: int in range(n):
		parent.append(i)
	var find_root: Callable = func(start: int) -> int:
		var x: int = start
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x

	for i: int in range(n):
		for j: int in range(i + 1, n):
			var a: Rect2 = candidates[i]["rect"] as Rect2i
			var b: Rect2 = candidates[j]["rect"] as Rect2i
			if _rect_gap(a, b) < gap_threshold:
				var ri: int = find_root.call(i)
				var rj: int = find_root.call(j)
				if ri != rj:
					parent[ri] = rj

	var groups: Dictionary = {}
	for i: int in range(n):
		var root: int = find_root.call(i)
		if not groups.has(root):
			groups[root] = []
		(groups[root] as Array).append(candidates[i])

	var clusters: Array = groups.values()
	clusters.sort_custom(func(a: Array, b: Array) -> bool:
		return _cluster_left_edge(a) < _cluster_left_edge(b))
	return clusters

static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()

static func _cluster_left_edge(cluster: Array) -> float:
	var min_x: float = INF
	for c: Dictionary in cluster:
		min_x = minf(min_x, (c["rect"] as Rect2i).position.x)
	return min_x

## Straightens a detected card to a canonical upright crop of out_size,
## sampled from the ORIGINAL (full-res) image, by inverse-mapping each output
## pixel through the detected rotation with bilinear sampling — Godot's Image
## has no arbitrary-angle rotate, so this is done by hand.
static func extract_card(source: Image, candidate: Dictionary, out_size: Vector2i = Vector2i(90, 126)) -> Image:
	var centroid: Vector2 = candidate["centroid"]
	var angle: float = candidate["angle"]
	var rect: Rect2i = candidate["rect"]

	# angle is the rectangle's long-axis direction from +X (~90 degrees for
	# an upright portrait card, not 0) and is only defined up to +-180
	# degrees (a line has no "up"); out_size is always portrait, so convert
	# to "rotation away from upright" and resolve the ambiguity by picking
	# whichever of the two 180-degrees-apart candidates is closer to upright
	# — correct as long as the true rotation is well under 90 degrees, true
	# for any reasonably-fanned-out photo.
	var rot: float = angle - PI / 2.0
	if rot > PI / 2.0:
		rot -= PI
	elif rot < -PI / 2.0:
		rot += PI

	var cos_r: float = cos(-rot)
	var sin_r: float = sin(-rot)
	var half_w: float = rect.size.x / 2.0
	var half_h: float = rect.size.y / 2.0
	var min_v: Vector2 = Vector2.INF
	var max_v: Vector2 = -Vector2.INF
	for corner: Vector2 in [Vector2(-half_w, -half_h), Vector2(half_w, -half_h), Vector2(half_w, half_h), Vector2(-half_w, half_h)]:
		var r: Vector2 = Vector2(corner.x * cos_r - corner.y * sin_r, corner.x * sin_r + corner.y * cos_r)
		min_v = min_v.min(r)
		max_v = max_v.max(r)
	var src_w: float = max_v.x - min_v.x
	var src_h: float = max_v.y - min_v.y

	var cos_a: float = cos(rot)
	var sin_a: float = sin(rot)
	var out := Image.create(out_size.x, out_size.y, false, Image.FORMAT_RGBA8)
	var sw: int = source.get_width()
	var sh: int = source.get_height()
	for oy: int in range(out_size.y):
		for ox: int in range(out_size.x):
			# Map output pixel -> centered "straightened" space -> rotate back
			# into the source image's original (rotated-card) space.
			var lx: float = (float(ox) / out_size.x - 0.5) * src_w
			var ly: float = (float(oy) / out_size.y - 0.5) * src_h
			var sx: float = centroid.x + lx * cos_a - ly * sin_a
			var sy: float = centroid.y + lx * sin_a + ly * cos_a
			if sx < 0.0 or sy < 0.0 or sx >= sw - 1 or sy >= sh - 1:
				out.set_pixel(ox, oy, Color(0, 0, 0, 0))
			else:
				out.set_pixel(ox, oy, _bilinear(source, sx, sy))
	return out

## Area-moment centroid + dominant-axis angle over the mask's true bits
## within rect (clamped to the bitmap's own bounds).
static func _mask_moments(bitmap: BitMap, rect: Rect2i) -> Dictionary:
	var size: Vector2i = bitmap.get_size()
	var clamped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, size))
	var n: int = 0
	var sum_x: float = 0.0
	var sum_y: float = 0.0
	for y: int in range(clamped.position.y, clamped.end.y):
		for x: int in range(clamped.position.x, clamped.end.x):
			if bitmap.get_bit(x, y):
				n += 1
				sum_x += x
				sum_y += y
	if n == 0:
		return {"centroid": Vector2(clamped.get_center()), "angle": 0.0}
	var cx: float = sum_x / n
	var cy: float = sum_y / n

	var sxx: float = 0.0
	var syy: float = 0.0
	var sxy: float = 0.0
	for y: int in range(clamped.position.y, clamped.end.y):
		for x: int in range(clamped.position.x, clamped.end.x):
			if bitmap.get_bit(x, y):
				var dx: float = x - cx
				var dy: float = y - cy
				sxx += dx * dx
				syy += dy * dy
				sxy += dx * dy
	var angle: float = 0.5 * atan2(2.0 * sxy, sxx - syy)
	return {"centroid": Vector2(cx, cy), "angle": angle}

static func _bilinear(img: Image, x: float, y: float) -> Color:
	var x0: int = int(floor(x))
	var y0: int = int(floor(y))
	var fx: float = x - x0
	var fy: float = y - y0
	var c00: Color = img.get_pixel(x0, y0)
	var c10: Color = img.get_pixel(x0 + 1, y0)
	var c01: Color = img.get_pixel(x0, y0 + 1)
	var c11: Color = img.get_pixel(x0 + 1, y0 + 1)
	var top: Color = c00.lerp(c10, fx)
	var bottom: Color = c01.lerp(c11, fx)
	return top.lerp(bottom, fy)

static func _sample_background(img: Image) -> Color:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var corners: Array[Color] = [
		img.get_pixel(0, 0), img.get_pixel(w - 1, 0),
		img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1),
	]
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	for c: Color in corners:
		r += c.r
		g += c.g
		b += c.b
	return Color(r / 4.0, g / 4.0, b / 4.0)

static func _looks_like_card(pixel: Color, bg: Color) -> bool:
	var sat: float = pixel.s
	var value_diff: float = absf(pixel.v - bg.v)
	return sat > 0.12 or value_diff > 0.10

static func _bounding_box(poly: PackedVector2Array) -> Rect2:
	var min_v: Vector2 = poly[0]
	var max_v: Vector2 = poly[0]
	for p: Vector2 in poly:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)
