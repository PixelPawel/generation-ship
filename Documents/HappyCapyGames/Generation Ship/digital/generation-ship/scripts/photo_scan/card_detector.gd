class_name CardDetector
extends RefCounted

# Finds card-shaped regions in a photo of a tableau, including fanned/
# overlapping stacks of tech cards on a sector.
#
# Godot's BitMap.opaque_to_polygons() (normally used to turn a sprite's alpha
# channel into collision polygons) does the connected-component contour
# extraction for us — no need to hand-roll flood fill/union-find.
#
# Calibrated 2026-09-21 against real photos of the physical game on a wood
# table (previously only synthetic composites were available). Two real
# problems showed up that a synthetic gray-background test never exercised:
#
# 1. Background segmentation: the original version sampled only the image's 4
#    corner pixels and flagged anything sufficiently saturated OR different
#    in brightness as "card". A real wood table has real saturation (measured
#    s=0.2-0.5 in the corners of a test photo, from the wood's own brown
#    hue) — so that threshold alone classified almost the entire table as
#    "card", merging the whole photo into one giant blob. Fixed by sampling a
#    wide border ring (not just 4 points) to build a background COLOR
#    CLUSTER (mean + per-channel std in RGB) and classifying by normalized
#    distance from that cluster instead of by saturation/value alone — this
#    correctly separates "brown wood" from "printed card colors" even though
#    both can be saturated. Verified by rendering the mask to a PNG and
#    visually confirming it isolates the 3 sector stacks cleanly.
#
# 2. Fanned/overlapping cards: a sector's tech cards are photographed
#    overlapping (a sliver of each exposed), so they form ONE connected blob,
#    not one blob per card — no amount of segmentation tuning fixes that,
#    since the cards really are touching in the photo. Rather than trying to
#    find per-card edges directly, detect() now treats each blob as a whole
#    STACK: it measures the blob's own oriented width (~= one card's width,
#    fanning is vertical) and height, derives a single card's expected height
#    from CARD_ASPECT, and infers how many cards are fanned in from the
#    excess height using FAN_OVERLAP_FRACTION (how much of each card's height
#    is exposed above the one below it, calibrated from real photos — see
#    that constant). The stack is then sliced into that many evenly-spaced,
#    card-shaped candidate regions along its own long axis, ordered from the
#    bottom of the stack (where the sector card anchors the fan) upward,
#    matching the review flow's "slot 0 is the sector" convention.
#
# Remaining known weakness: a stack photographed at a strong angle near the
# frame's edge can end up with a near-square oriented bounding box (keystone
# perspective distortion), which throws off the width/height split this
# relies on — one real test photo undercounted a 2-card stack as 1 for
# exactly this reason. Manual add/remove in the review screen (see
# photo_scan.gd) is the correction path for whatever this gets wrong, same as
# for identification confidence — this is a best-effort pre-fill, not a
# guarantee.

const CARD_ASPECT: float = 63.5 / 89.0
# The reference art files (what identification hashes are actually built
# from) are 520x791 -- aspect 0.6574, confirmed identical across every tech
# card checked -- which is NOT the same as the physical card's own
# width:height (0.7135, used above for CARD_ASPECT). A ~9% aspect mismatch
# barely shows to the eye, but CardHash force-resizes to a fixed tiny 9x12
# grid regardless of input shape, so it measurably shifts where edges land
# in that grid -- confirmed directly: a real, cleanly-extracted crop of a
# known card scored a WORSE hash distance against its own correct reference
# than an unrelated card, until the extracted crop's own shape was corrected
# to this aspect instead of the physical one. CARD_ASPECT above still governs
# how tall a single card is estimated to be from its measured width for
# STACK-SLICING purposes (real-world geometry) -- this constant instead
# governs the shape of the final crop that gets handed to the hash matcher.
const REFERENCE_ART_ASPECT: float = 520.0 / 791.0
const MIN_AREA_FRACTION: float = 0.005  # relative to the (downscaled) detection image
const DETECT_WIDTH: int = 900  # downscale target for the segmentation pass — plenty for blob shapes, keeps the per-pixel scan fast

# Background color-cluster sampling: a ring around the image border, not just
# the 4 corners (a real table's lighting/color varies enough across the frame
# that 4 points aren't representative — see file header).
const BG_MARGIN_FRACTION: float = 0.06
const BG_SAMPLE_STRIDE: int = 3
const BG_STD_FLOOR: float = 0.03  # keeps a very uniform background from making the threshold hypersensitive to JPEG noise
const BG_DISTANCE_THRESHOLD: float = 4.0  # "how many (floored) std devs" of RGB distance counts as foreground

# Morphological closing (merges internal dark holes from a card's own text/
# icons into one solid blob) followed by opening (drops thin noise like a
# stray highlight or a rubber band's ring edge) — both tuned small enough to
# never bridge the real gap between two separate sectors' stacks at
# DETECT_WIDTH resolution (a larger radius did exactly that in testing).
const CLOSE_RADIUS: int = 3
const OPEN_RADIUS: int = 3

const MIN_FILL_RATIO: float = 0.45  # rejects hollow/irregular non-card blobs (a rubber band ring, a light reflection) that pass the area check
# Recalibrated (0.23 -> 0.6) after fixing card_w to use _tip_width() instead
# of the whole stack's perpendicular extent (see that function) — the old
# card_w was ~1.6x too large (inflated by sideways drift across the fan), so
# card_h_est was too large too, which had been silently compensated for by
# an artificially small overlap fraction tuned against that same inflated
# card_h_est. Recalibrated from 3 real stacks with known card counts (3, 3,
# 2) using the corrected card_h_est: solving for whatever fraction makes
# n_est round to the right count for all three at once gives a valid range
# of about 0.55-0.75; 0.6 sits safely inside it. Each additional card beyond
# the first adds roughly this fraction of a card's height to the stack's
# total height (i.e. this much of it stays exposed above the card below it).
const FAN_OVERLAP_FRACTION: float = 0.6
const MAX_CARDS_PER_STACK: int = 6

## Returns an Array[Dictionary] of candidate cards, sorted left-to-right by
## which stack they belong to, and bottom-to-top (sector first) within a
## stack. Each entry is {"rect": Rect2i, "centroid": Vector2, "angle": float},
## rect/centroid in the ORIGINAL image's coordinates. Pass an entry to
## extract_card() to get a straightened, hashable crop.
static func detect(source: Image) -> Array[Dictionary]:
	var scale: float = float(DETECT_WIDTH) / float(source.get_width())
	var work: Image = source.duplicate()
	if work.is_compressed():
		work.decompress()
	work.convert(Image.FORMAT_RGBA8)
	var detect_h: int = maxi(1, roundi(source.get_height() * scale))
	work.resize(DETECT_WIDTH, detect_h, Image.INTERPOLATE_BILINEAR)

	var bg: Dictionary = _sample_background(work)
	var bitmap: BitMap = BitMap.new()
	bitmap.create(Vector2i(DETECT_WIDTH, detect_h))
	for y: int in range(detect_h):
		for x: int in range(DETECT_WIDTH):
			bitmap.set_bit(x, y, _looks_like_card(work.get_pixel(x, y), bg))

	var full_rect := Rect2i(Vector2i.ZERO, Vector2i(DETECT_WIDTH, detect_h))
	bitmap.grow_mask(CLOSE_RADIUS, full_rect)
	bitmap.grow_mask(-CLOSE_RADIUS, full_rect)
	bitmap.grow_mask(-OPEN_RADIUS, full_rect)
	bitmap.grow_mask(OPEN_RADIUS, full_rect)

	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(full_rect, 2.0)
	var min_area: float = MIN_AREA_FRACTION * DETECT_WIDTH * detect_h

	# One inner array per detected stack, each already ordered bottom-first;
	# stacks themselves get sorted left-to-right before flattening at the end
	# (sorting the flat candidate list directly by X would scramble a
	# stack's internal bottom-first order for cards sharing nearly the same
	# X, which is every card in a mostly-vertical fan).
	var stacks: Array[Array] = []
	for poly: PackedVector2Array in polygons:
		var bbox: Rect2 = _bounding_box(poly)
		if bbox.get_area() < min_area:
			continue

		var m: Dictionary = _mask_moments(bitmap, Rect2i(bbox).grow(2))
		var extent_u: float = m["extent_u"]
		var extent_v: float = m["extent_v"]
		var oriented_area: float = extent_u * extent_v
		if oriented_area <= 0.0 or float(m["filled"]) / oriented_area < MIN_FILL_RATIO:
			continue

		var stack_h: float = maxf(extent_u, extent_v)
		var angle: float = m["angle"]
		var centroid: Vector2 = m["centroid"]
		# `angle` is the blob's PRINCIPAL (largest-variance) axis by
		# construction, which should be the long (stack-height) axis — but
		# confirm against the actual measured extents rather than assuming,
		# since a near-square blob (bad segmentation/perspective) can have
		# noise decide which axis PCA calls "first".
		var long_dir: Vector2 = Vector2(cos(angle), sin(angle))
		var perp_dir: Vector2 = Vector2(-sin(angle), cos(angle))
		if extent_v > extent_u:
			var tmp: Vector2 = long_dir
			long_dir = perp_dir
			perp_dir = tmp

		# card_w from the WHOLE stack's perpendicular extent is unreliable —
		# a fan photographed at an angle drifts sideways as well as down
		# (confirmed against a real photo: the whole-stack perpendicular
		# extent measured ~1.6x a hand-measured single card's true width),
		# so it's really "card width + accumulated drift", not just card
		# width. Only the tip of the stack (its outermost ~15% along the
		# long axis) has just ONE card present, so measuring the
		# perpendicular extent there instead gives the true card width.
		var card_w: float = _tip_width(bitmap, Rect2i(bbox).grow(2), centroid, long_dir, perp_dir, stack_h)
		var card_h_est: float = card_w / CARD_ASPECT
		if card_h_est <= 0.0:
			continue
		var n_est: float = stack_h / card_h_est
		var n: int = clampi(roundi((n_est - 1.0) / FAN_OVERLAP_FRACTION) + 1, 1, MAX_CARDS_PER_STACK)

		var offsets: Array[float] = []
		if n <= 1:
			offsets.append(0.0)
		else:
			var span: float = stack_h - card_h_est
			for i: int in range(n):
				offsets.append(-stack_h / 2.0 + card_h_est / 2.0 + span * float(i) / float(n - 1))

		# The crop's own shape (what extract_card() actually samples) uses
		# REFERENCE_ART_ASPECT, not CARD_ASPECT -- see that constant's note.
		# card_w (a real measurement) stays the same either way.
		var card_h_for_crop: float = card_w / REFERENCE_ART_ASPECT

		var stack_candidates: Array[Dictionary] = []
		for u: float in offsets:
			var slice_centroid_detect: Vector2 = centroid + long_dir * u
			var full_centroid: Vector2 = slice_centroid_detect / scale
			var full_size: Vector2 = Vector2(card_w, card_h_for_crop) / scale
			stack_candidates.append({
				"rect": Rect2i(Vector2i(full_centroid - full_size / 2.0), Vector2i(full_size)),
				"centroid": full_centroid,
				"angle": angle,
			})
		# Bottom-of-screen-first — the sector card anchors the bottom of its
		# fan, and the review flow's slot 0 is always treated as the sector.
		stack_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["centroid"] as Vector2).y > (b["centroid"] as Vector2).y)
		stacks.append(stack_candidates)

	stacks.sort_custom(func(a: Array, b: Array) -> bool:
		return _stack_left_edge(a) < _stack_left_edge(b))

	var candidates: Array[Dictionary] = []
	for stack_id: int in range(stacks.size()):
		for c: Dictionary in stacks[stack_id]:
			c["stack_id"] = stack_id
			candidates.append(c)
	return candidates

static func _stack_left_edge(stack: Array) -> float:
	var min_x: float = INF
	for c: Dictionary in stack:
		min_x = minf(min_x, (c["rect"] as Rect2i).position.x)
	return min_x

## Groups detected candidates into per-sector clusters. If every candidate
## already carries a "stack_id" (set by detect(), which already knows exactly
## which physical stack/blob each candidate came from), that's used directly
## — it's authoritative, unlike re-deriving proximity from scratch, which
## real photos showed merging separate sectors placed less than about a
## card's width apart (a real, common layout) back into one cluster. Falls
## back to the original gap-based heuristic for candidates built any other
## way (e.g. hand-constructed in a test). Returns Array[Array] of
## candidate-dictionary arrays, one per cluster, sorted left-to-right by the
## cluster's own leftmost edge.
static func cluster_candidates(candidates: Array[Dictionary]) -> Array:
	if candidates.is_empty():
		return []
	if candidates.all(func(c: Dictionary) -> bool: return c.has("stack_id")):
		var by_stack: Dictionary = {}
		for c: Dictionary in candidates:
			var id: int = c["stack_id"]
			if not by_stack.has(id):
				by_stack[id] = []
			(by_stack[id] as Array).append(c)
		var stack_clusters: Array = by_stack.values()
		stack_clusters.sort_custom(func(a: Array, b: Array) -> bool:
			return _cluster_left_edge(a) < _cluster_left_edge(b))
		return stack_clusters

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
## has no arbitrary-angle rotate, so this is done by hand. out_size defaults
## to Vector2i.ZERO, meaning "derive it from the candidate's own rect aspect
## at BASE_OUT_WIDTH" -- any FIXED default here, whatever aspect it used,
## risked silently drifting out of sync with whatever aspect the rect itself
## ends up shaped to (this happened once already: a hardcoded 90x126 default
## didn't match a rect deliberately shaped to REFERENCE_ART_ASPECT, quietly
## re-introducing the exact stretch mismatch that shaping was meant to fix).
## Callers that want a specific pixel size can still pass one explicitly.
const BASE_OUT_WIDTH: int = 360

static func extract_card(source: Image, candidate: Dictionary, out_size: Vector2i = Vector2i.ZERO) -> Image:
	var centroid: Vector2 = candidate["centroid"]
	var angle: float = candidate["angle"]
	var rect: Rect2i = candidate["rect"]
	if out_size == Vector2i.ZERO:
		out_size = Vector2i(BASE_OUT_WIDTH, roundi(BASE_OUT_WIDTH * float(rect.size.y) / float(rect.size.x)))

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

## Area-moment centroid + oriented (principal-axis) extents + fill count over
## the mask's true bits within rect (clamped to the bitmap's own bounds).
## extent_u/extent_v are the mask's own spread along its principal axis
## (angle) and the perpendicular one — NOT a simple axis-aligned width/height
## — so a rotated stack's true card-width/stack-height survive without being
## inflated by the rotation the way an axis-aligned bounding box would be.
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
		return {"centroid": Vector2(clamped.get_center()), "angle": 0.0, "extent_u": 0.0, "extent_v": 0.0, "filled": 0}
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

	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	var min_u: float = INF
	var max_u: float = -INF
	var min_v: float = INF
	var max_v: float = -INF
	for y: int in range(clamped.position.y, clamped.end.y):
		for x: int in range(clamped.position.x, clamped.end.x):
			if bitmap.get_bit(x, y):
				var dx: float = x - cx
				var dy: float = y - cy
				var u: float = dx * cos_a + dy * sin_a
				var v: float = -dx * sin_a + dy * cos_a
				min_u = minf(min_u, u)
				max_u = maxf(max_u, u)
				min_v = minf(min_v, v)
				max_v = maxf(max_v, v)
	return {
		"centroid": Vector2(cx, cy),
		"angle": angle,
		"extent_u": max_u - min_u,
		"extent_v": max_v - min_v,
		"filled": n,
	}

const TIP_SLICE_FRACTION: float = 0.15

## The perpendicular (card-width) extent of a fanned stack's WHOLE mask
## includes any sideways drift accumulated across the fan (cards photographed
## at an angle rarely stack in a perfectly straight line), so it measures
## "card width plus drift", not card width alone. Only the outermost slice at
## either end of the stack has just one card present (nothing overlapping it
## from beyond that end), so measuring the perpendicular extent within a
## short slice there instead gives an undrifted single-card width. Returns
## the smaller (more conservative) of the two ends' measurements.
static func _tip_width(bitmap: BitMap, rect: Rect2i, centroid: Vector2, long_dir: Vector2, perp_dir: Vector2, stack_h: float) -> float:
	var size: Vector2i = bitmap.get_size()
	var clamped: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, size))
	var slice_len: float = stack_h * TIP_SLICE_FRACTION

	var min_u: float = INF
	var max_u: float = -INF
	for y: int in range(clamped.position.y, clamped.end.y):
		for x: int in range(clamped.position.x, clamped.end.x):
			if bitmap.get_bit(x, y):
				var d: Vector2 = Vector2(x, y) - centroid
				var u: float = d.dot(long_dir)
				min_u = minf(min_u, u)
				max_u = maxf(max_u, u)
	if min_u == INF:
		return 0.0

	var low_min_v: float = INF
	var low_max_v: float = -INF
	var high_min_v: float = INF
	var high_max_v: float = -INF
	for y: int in range(clamped.position.y, clamped.end.y):
		for x: int in range(clamped.position.x, clamped.end.x):
			if bitmap.get_bit(x, y):
				var d: Vector2 = Vector2(x, y) - centroid
				var u: float = d.dot(long_dir)
				var v: float = d.dot(perp_dir)
				if u <= min_u + slice_len:
					low_min_v = minf(low_min_v, v)
					low_max_v = maxf(low_max_v, v)
				if u >= max_u - slice_len:
					high_min_v = minf(high_min_v, v)
					high_max_v = maxf(high_max_v, v)

	var low_width: float = low_max_v - low_min_v if low_min_v != INF else INF
	var high_width: float = high_max_v - high_min_v if high_min_v != INF else INF
	return minf(low_width, high_width)

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

## Samples a ring around the image border (not just the 4 corners — see file
## header) to build a background color cluster: mean + per-channel std in
## RGB. (A median/MAD version of this was tried to resist a border ring that
## isn't purely background — one real test photo had a puzzle box edge and a
## bit of clothing inside that margin — but re-tuning BG_DISTANCE_THRESHOLD
## for the resulting smaller std didn't converge cleanly within a reasonable
## number of passes against the 4 real photos on hand; reverted. Worth
## revisiting with more real photos to calibrate against.)
static func _sample_background(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var margin: int = maxi(4, roundi(minf(w, h) * BG_MARGIN_FRACTION))
	var half_margin: int = margin / 2

	var samples: Array[Color] = []
	for x: int in range(0, w, BG_SAMPLE_STRIDE):
		for y: int in [0, half_margin, h - 1 - half_margin, h - 1]:
			if y >= 0 and y < h:
				samples.append(img.get_pixel(x, y))
	for y: int in range(0, h, BG_SAMPLE_STRIDE):
		for x: int in [0, half_margin, w - 1 - half_margin, w - 1]:
			if x >= 0 and x < w:
				samples.append(img.get_pixel(x, y))

	var mean := Color(0.0, 0.0, 0.0, 0.0)
	for s: Color in samples:
		mean += s
	mean /= samples.size()

	var var_r: float = 0.0
	var var_g: float = 0.0
	var var_b: float = 0.0
	for s: Color in samples:
		var_r += (s.r - mean.r) * (s.r - mean.r)
		var_g += (s.g - mean.g) * (s.g - mean.g)
		var_b += (s.b - mean.b) * (s.b - mean.b)
	var count: int = samples.size()
	return {
		"mean": mean,
		"std": Vector3(sqrt(var_r / count), sqrt(var_g / count), sqrt(var_b / count)),
	}

## Normalized RGB distance from the background color cluster — a pixel far
## enough (in units of that channel's own std dev, floored so a very uniform
## background doesn't become hypersensitive to JPEG noise) from the
## background's mean color counts as "card". Replaces a plain
## saturation/value threshold, which a real (non-neutral-colored) table
## background defeats — see file header.
static func _looks_like_card(pixel: Color, bg: Dictionary) -> bool:
	var mean: Color = bg["mean"]
	var std: Vector3 = bg["std"]
	var dr: float = (pixel.r - mean.r) / maxf(std.x, BG_STD_FLOOR)
	var dg: float = (pixel.g - mean.g) / maxf(std.y, BG_STD_FLOOR)
	var db: float = (pixel.b - mean.b) / maxf(std.z, BG_STD_FLOOR)
	return sqrt(dr * dr + dg * dg + db * db) > BG_DISTANCE_THRESHOLD

static func _bounding_box(poly: PackedVector2Array) -> Rect2:
	var min_v: Vector2 = poly[0]
	var max_v: Vector2 = poly[0]
	for p: Vector2 in poly:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)
