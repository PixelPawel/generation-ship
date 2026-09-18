class_name SupplyDetector
extends RefCounted

# Detects stored-supply resource tokens (small colored cubes/tiles) within a
# region of a tableau photo, classifying each by nearest match to the game's
# own canonical color tints (CardData.color_tint) rather than card identity.
#
# Unvalidated against real photos or physical tokens — same caveat as
# card_detector.gd, and a harder one: tokens sit ON TOP of colorful card art
# rather than against a neutral table, so the same "not background" mask
# that isolates a whole card will treat the token as part of that same card
# blob rather than a separate small one, and busy card-art detail can produce
# false-positive color matches. Ship this as a first pass with results shown
# editable in the review UI, not as a trusted count — finishing this
# properly needs real photos of real physical tokens on real cards.

const MIN_TOKEN_AREA_FRACTION: float = 0.0005
const MAX_TOKEN_AREA_FRACTION: float = 0.02
const TOKEN_ASPECT_MIN: float = 0.6  # tokens are roughly square/round, unlike cards
const COLOR_MATCH_MAX_DISTANCE: float = 0.35  # normalized RGB distance

const _SUPPLY_COLORS: Array[int] = [
	CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
]

## Returns Dictionary[SupplyColor(int), int] of detected token counts within
## `region` (full-res image coordinates) of `source`.
static func detect(source: Image, region: Rect2i) -> Dictionary:
	var clamped: Rect2i = region.intersection(Rect2i(Vector2i.ZERO, source.get_size()))
	if clamped.size.x <= 0 or clamped.size.y <= 0:
		return {}
	var crop: Image = source.get_region(clamped)
	var bg: Color = _sample_background(crop)

	var w: int = crop.get_width()
	var h: int = crop.get_height()
	var bitmap := BitMap.new()
	bitmap.create(Vector2i(w, h))
	for y: int in range(h):
		for x: int in range(w):
			bitmap.set_bit(x, y, _looks_like_token(crop.get_pixel(x, y), bg))

	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, Vector2i(w, h)), 1.5)
	var min_area: float = MIN_TOKEN_AREA_FRACTION * w * h
	var max_area: float = MAX_TOKEN_AREA_FRACTION * w * h

	var counts: Dictionary = {}
	for poly: PackedVector2Array in polygons:
		var bbox: Rect2 = _bounding_box(poly)
		if bbox.get_area() < min_area or bbox.get_area() > max_area:
			continue
		var ratio: float = minf(bbox.size.x, bbox.size.y) / maxf(bbox.size.x, bbox.size.y)
		if ratio < TOKEN_ASPECT_MIN:
			continue
		var avg_color: Color = _average_color(crop, Rect2i(bbox))
		var best_color: int = _closest_supply_color(avg_color)
		if best_color >= 0:
			counts[best_color] = int(counts.get(best_color, 0)) + 1
	return counts

static func _closest_supply_color(c: Color) -> int:
	var best: int = -1
	var best_dist: float = COLOR_MATCH_MAX_DISTANCE
	for color: int in _SUPPLY_COLORS:
		var tint: Color = CardData.color_tint(color)
		var dist: float = Vector3(c.r - tint.r, c.g - tint.g, c.b - tint.b).length()
		if dist < best_dist:
			best_dist = dist
			best = color
	return best

static func _average_color(img: Image, rect: Rect2i) -> Color:
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var n: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var c: Color = img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n == 0:
		return Color.BLACK
	return Color(r / n, g / n, b / n)

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

static func _looks_like_token(pixel: Color, bg: Color) -> bool:
	var sat: float = pixel.s
	var value_diff: float = absf(pixel.v - bg.v)
	return sat > 0.15 or value_diff > 0.12

static func _bounding_box(poly: PackedVector2Array) -> Rect2:
	var min_v: Vector2 = poly[0]
	var max_v: Vector2 = poly[0]
	for p: Vector2 in poly:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)
