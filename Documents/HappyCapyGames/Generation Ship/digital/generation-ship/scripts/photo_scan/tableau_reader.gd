class_name TableauReader
extends RefCounted

# Second step of Scan Tableau, after DialReader: works out what belongs to each sector.
# Every read dial pins down its card exactly (position, size, which way is up, and the
# oval squash of an angled photo), so each sector's surroundings can be looked at in the
# sector's own millimetre coordinates, whatever angle the photo was taken from:
#  * archived face-up: any card whose dial sits below a sector (players either slide the
#    archive under the sector or leave it fully visible below — both count);
#  * archived face-down: the TECH lettering of the backs below a sector, counted as word
#    blobs (robust to the small rotations of an archive cascade);
#  * stored supply: per supply colour, what no identified card art (±1 mm), card back or
#    the table explains, icon holes filled, kept only if it has a token's compact shape
#    and size (printed supply icons are far smaller, coloured name plates the wrong shape);
#    the count comes from the size, so two touching tokens of one colour count as 2.
# Tuned on synthetic photos (InDesign_Shop/_automation/scan_code/mockups2.py); token
# counts still need tuning on real photos of real tokens.

const DIAL_MM: Dictionary = {"sector": Vector2(60.80, 36.72), "tech": Vector2(36.57, 59.33), "expedition": Vector2(37.17, 60.80)}
const SIZE_MM: Dictionary = {"sector": Vector2(67.0, 44.0), "tech": Vector2(44.0, 67.0), "expedition": Vector2(44.0, 67.0)}
const ART_PPM: float = 3.0                       # card art / token zone resolution (px per mm)
# archived face-up: dial centre within this box below the sector (sector mm)
const ARCHIVE_BOX: Rect2 = Rect2(-12.0, 40.0, 91.0, 144.0)
# archived face-down: TECH labels (cream word, ~26 x 6 mm) in the strip below the sector
const LABEL_PPM: float = 2.0
const LABEL_ZONE: Rect2 = Rect2(-10.0, 40.0, 87.0, 204.0)
const LABEL_W_MM: Vector2 = Vector2(24.0, 34.0)
const LABEL_H_MM: Vector2 = Vector2(3.0, 10.0)
const LABEL_MERGE_MM: float = 1.5
const LABEL_TO_CARD: Vector2 = Vector2(9.0, 47.5)    # the label's top-left in back-card mm
# stored supply
const TOKEN_ZONE: Rect2 = Rect2(-12.0, 8.0, 91.0, 102.0)
const ART_MATCH: float = 60.0                    # colour distance a pixel still counts as the art
const ART_SLACK_MM: float = 1.0                  # ...also when the art matches this far off
const TABLE_MATCH: float = 40.0
const TOKEN_COLOUR_MAX: float = 80.0
const TOKEN_AREA_MIN: float = 0.45               # of a token's area (its base colour + filled icon)
const TOKEN_SOLIDITY: float = 0.8
const TOKEN_ELONGATION: float = 2.2
const TOKEN_MAX_PER_CLUMP: int = 4
# Dust, Metals, Liquids, Organix, Electrix, Thrust: base colours (punchboard art) and each
# token's area in mm^2 at ~14 mm across (circle, square, oval, hexagon, pentagon, octagon)
const TOKEN_ORDER: Array[int] = [CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST]
const TOKEN_RGB: Array[Vector3] = [Vector3(208, 204, 218), Vector3(186, 24, 40), Vector3(70, 124, 191),
	Vector3(63, 168, 53), Vector3(233, 120, 36), Vector3(240, 181, 4)]
const TOKEN_SIL_MM2: Array[float] = [153.8, 186.2, 96.1, 127.4, 128.8, 149.7]

var progress: float = 0.0
var _art: Array[Image] = []       # per dial: its card art at ART_PPM (RGB8), or null
var _backs: Array[Image] = []     # tech back art at ART_PPM (EN + the game language)
var _art_f: Array[PackedFloat32Array] = []   # _art as blurred floats (empty where no art)
var _art_size: Array[Vector2i] = []
var _back_f: PackedFloat32Array = PackedFloat32Array()
var _back_size: Vector2i = Vector2i.ZERO
var _photo: PackedByteArray = PackedByteArray()
var _pw: int = 0
var _ph: int = 0
var _done_mutex: Mutex = Mutex.new()
var _done: int = 0

## Main thread: loads the art of every read card (textures can't be decoded safely on a
## worker thread). Then analyze() on a thread.
static func create(dials: Array[Dictionary]) -> TableauReader:
	var reader: TableauReader = TableauReader.new()
	for d: Dictionary in dials:
		var cd: CardData = d["card"]
		var path: String = cd.adv_local_art_path if bool(d.get("is_advanced", false)) else cd.local_art_path
		var size_mm: Vector2 = SIZE_MM[deck_of(d)]
		reader._art.append(_load_art(path, size_mm))
	var langs: Array[String] = ["EN"]
	var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
	if lang != "EN":
		langs.append(lang)
	for l: String in langs:
		var back: Image = _load_art("res://assets/cards/Tech/%s/GS Techs Back 44x67mm.png" % l, SIZE_MM["tech"])
		if back:
			reader._backs.append(back)
	return reader

static func _load_art(path: String, size_mm: Vector2) -> Image:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(roundi(size_mm.x * ART_PPM), roundi(size_mm.y * ART_PPM), Image.INTERPOLATE_LANCZOS)
	return img

static func deck_of(d: Dictionary) -> String:
	var cd: CardData = d["card"]
	if cd.card_type == CardData.CardType.SECTOR:
		return "sector"
	return "expedition" if cd.card_type == CardData.CardType.EXPEDITION else "tech"

## Card millimetres (x right, y down, origin at the card's top-left) -> photo pixels.
static func card_frame(d: Dictionary) -> Transform2D:
	var deck: String = deck_of(d)
	var s: float = float(d["radius"]) / float(DialReader.DECK_R_MM[deck])
	var th: float = float(d["th"])
	var up: Vector2 = Vector2(-cos(th), -sin(th))      # undistorted dial: centre -> marker
	var right: Vector2 = Vector2(-up.y, up.x)
	var down: Vector2 = -up
	var a: PackedFloat32Array = d["shape"]
	var col0: Vector2 = Vector2(a[0] * right.x + a[1] * right.y, a[2] * right.x + a[3] * right.y) * s
	var col1: Vector2 = Vector2(a[0] * down.x + a[1] * down.y, a[2] * down.x + a[3] * down.y) * s
	var dial: Vector2 = DIAL_MM[deck]
	var origin: Vector2 = (d["center"] as Vector2) - col0 * dial.x - col1 * dial.y
	return Transform2D(col0, col1, origin)

## Returns groups like DialReader.group_into_sectors ([sector or {}, techs…]); each sector
## dict additionally gets "archived_up" (dials), "archived_down" (int) and "supply"
## (SupplyColor int -> count).
func analyze(photo: Image, dials: Array[Dictionary]) -> Array:
	progress = 0.0
	_photo = photo.get_data()
	_pw = photo.get_width()
	_ph = photo.get_height()
	# card art as blurred float arrays, all cards at once on every core
	_art_f.clear()
	_art_f.resize(_art.size())
	_art_size.clear()
	for img: Image in _art:
		_art_size.append(Vector2i(img.get_width(), img.get_height()) if img else Vector2i.ZERO)
	var to_floats: Callable = func(i: int) -> void:
		_art_f[i] = _art_floats(_art[i]) if _art[i] else PackedFloat32Array()
	if not _art.is_empty():
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(to_floats, _art.size()))
	if not _backs.is_empty():
		_back_f = _art_floats(_backs[0])
		_back_size = Vector2i(_backs[0].get_width(), _backs[0].get_height())
	var sector_idx: Array[int] = []
	for i: int in dials.size():
		if deck_of(dials[i]) == "sector":
			sector_idx.append(i)
	# archived face-up: a non-sector dial below a sector (nearest sector below wins)
	var archived_of: Dictionary = {}     # dial index -> sector dial index
	for i: int in dials.size():
		if deck_of(dials[i]) == "sector":
			continue
		var best_y: float = INF
		for si: int in sector_idx:
			var local: Vector2 = card_frame(dials[si]).affine_inverse() * (dials[i]["center"] as Vector2)
			if ARCHIVE_BOX.has_point(local) and local.y < best_y:
				best_y = local.y
				archived_of[i] = si
	var results: Array = []
	results.resize(sector_idx.size())
	_done = 0
	var per_sector: Callable = func(k: int) -> void:
		var si: int = sector_idx[k]
		var labels: Array[Vector2] = _find_back_labels(dials[si])
		var supply: Dictionary = _count_tokens(dials, si, labels)
		results[k] = {backs = labels.size(), supply = supply}
		_done_mutex.lock()
		_done += 1
		progress = float(_done) / float(sector_idx.size())
		_done_mutex.unlock()
	if not sector_idx.is_empty():
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(per_sector, sector_idx.size()))

	var rest: Array[Dictionary] = []
	for i: int in dials.size():
		if not archived_of.has(i):
			rest.append(dials[i])
	var groups: Array = DialReader.group_into_sectors(rest)
	for g: Array in groups:
		var sd: Dictionary = g[0]
		if sd.is_empty():
			continue
		var si: int = dials.find(sd)
		var k: int = sector_idx.find(si)
		var ups: Array[Dictionary] = []
		for i: int in archived_of:
			if int(archived_of[i]) == si:
				ups.append(dials[i])
		sd["archived_up"] = ups
		sd["archived_down"] = int(results[k]["backs"]) if k >= 0 else 0
		sd["supply"] = results[k]["supply"] if k >= 0 else {}
	_sort_left_to_right(groups, dials)
	progress = 1.0
	return groups

# Sectors in the order they lie in the photo, left to right as the cards face (so a
# rotated or tilted shot still comes out in table order). A group without a sector
# goes by its first card.
static func _sort_left_to_right(groups: Array, dials: Array[Dictionary]) -> void:
	if dials.is_empty():
		return
	var up_sum: Vector2 = Vector2.ZERO
	for d: Dictionary in dials:
		up_sum += d["up"] as Vector2
	var up: Vector2 = up_sum.normalized()
	var right: Vector2 = Vector2(-up.y, up.x)
	groups.sort_custom(func(a: Array, b: Array) -> bool:
		return _group_anchor(a).dot(right) < _group_anchor(b).dot(right))

static func _group_anchor(g: Array) -> Vector2:
	for d: Dictionary in g:
		if not d.is_empty():
			return d["center"]
	return Vector2.ZERO

# ── Photo sampling ───────────────────────────────────────────────────────────

func _sample(x: float, y: float) -> Vector3:
	if x < 0.0 or y < 0.0 or x >= _pw - 1 or y >= _ph - 1:
		return Vector3(-1.0, -1.0, -1.0)
	var xi: int = int(x)
	var yi: int = int(y)
	var fx: float = x - xi
	var fy: float = y - yi
	var o: int = (yi * _pw + xi) * 3
	var o2: int = o + _pw * 3
	var out: Vector3 = Vector3.ZERO
	for c: int in 3:
		var top: float = lerpf(float(_photo[o + c]), float(_photo[o + 3 + c]), fx)
		var bot: float = lerpf(float(_photo[o2 + c]), float(_photo[o2 + 3 + c]), fx)
		out[c] = lerpf(top, bot, fy)
	return out

# The photo over a rectangle of card millimetres, as rows of RGB (PackedFloat32Array, w*h*3).
func _rectify(frame: Transform2D, box: Rect2, ppm: float) -> PackedFloat32Array:
	var w: int = int(box.size.x * ppm)
	var h: int = int(box.size.y * ppm)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(w * h * 3)
	for j: int in h:
		for i: int in w:
			var p: Vector2 = frame * Vector2(box.position.x + i / ppm, box.position.y + j / ppm)
			var v: Vector3 = _sample(p.x, p.y)
			var o: int = (j * w + i) * 3
			out[o] = v.x
			out[o + 1] = v.y
			out[o + 2] = v.z
	return out

# ── Card art as blurred float arrays (same blur as the photo zone) ──────────

# RGB8 image -> PackedFloat32Array w*h*3, box-blurred like the photo so fine print
# compares fairly.
static func _art_floats(img: Image) -> PackedFloat32Array:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = img.get_data()
	var f: PackedFloat32Array = PackedFloat32Array()
	f.resize(w * h * 3)
	for k: int in w * h * 3:
		f[k] = float(data[k])
	return _box_blur(f, w, h, 2)

# Bilinear sample of a w*h*3 float array at pixel (x, y), clamped to the edge.
static func _arr_at(a: PackedFloat32Array, w: int, h: int, x: float, y: float) -> Vector3:
	x = clampf(x, 0.0, w - 1.001)
	y = clampf(y, 0.0, h - 1.001)
	var xi: int = int(x)
	var yi: int = int(y)
	var fx: float = x - xi
	var fy: float = y - yi
	var o: int = (yi * w + xi) * 3
	var o2: int = o + w * 3
	var out: Vector3 = Vector3.ZERO
	for c: int in 3:
		var top: float = lerpf(a[o + c], a[o + 3 + c], fx)
		var bot: float = lerpf(a[o2 + c], a[o2 + 3 + c], fx)
		out[c] = lerpf(top, bot, fy)
	return out

# ── Archived face-down: the TECH lettering of the backs below the sector ─────

# Top-left (sector mm) of every TECH label in the strip below the sector: cream letters
# with a black outline, merged into one word blob of about 26 x 6 mm. Robust to the
# small rotations of an archive cascade, and nothing on a card's front looks like it.
func _find_back_labels(sd: Dictionary) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var w: int = int(LABEL_ZONE.size.x * LABEL_PPM)
	var h: int = int(LABEL_ZONE.size.y * LABEL_PPM)
	var z: PackedFloat32Array = _rectify(card_frame(sd), LABEL_ZONE, LABEL_PPM)
	# exposure: the strip's brightest 2% (per-pixel max channel) -> 245
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(256)
	for k: int in w * h:
		var m: float = maxf(z[k * 3], maxf(z[k * 3 + 1], z[k * 3 + 2]))
		hist[clampi(roundi(m), 0, 255)] += 1
	var acc: int = 0
	var p98: int = 255
	for v: int in range(255, -1, -1):
		acc += hist[v]
		if float(acc) >= float(w * h) * 0.02:
			p98 = v
			break
	var gain: float = 245.0 / maxf(float(p98), 60.0)
	var cream: PackedByteArray = PackedByteArray()
	cream.resize(w * h)
	for k: int in w * h:
		var r: float = z[k * 3] * gain
		var g: float = z[k * 3 + 1] * gain
		var b: float = z[k * 3 + 2] * gain
		if r > 225.0 and g > 205.0 and b > 140.0 and b < 220.0 and r - b > 15.0:
			cream[k] = 1
	# letters -> one word: close gaps along the rows
	var reach: int = maxi(1, int(LABEL_MERGE_MM * LABEL_PPM))
	var word: PackedByteArray = _erode_rows(_dilate_rows(cream, w, h, reach), w, h, reach)
	for comp: Dictionary in _components(word, w, h):
		var box: Rect2i = comp["box"]
		var bw: float = box.size.x / LABEL_PPM
		var bh: float = box.size.y / LABEL_PPM
		var fill: float = float(comp["count"]) / float(box.size.x * box.size.y)
		if bw >= LABEL_W_MM.x and bw <= LABEL_W_MM.y and bh >= LABEL_H_MM.x and bh <= LABEL_H_MM.y and fill > 0.25:
			found.append(Vector2(LABEL_ZONE.position.x + box.position.x / LABEL_PPM, LABEL_ZONE.position.y + box.position.y / LABEL_PPM))
	return found

# ── Stored supply: token-coloured, token-shaped, token-sized blobs ───────────

func _count_tokens(dials: Array[Dictionary], si: int, labels: Array[Vector2]) -> Dictionary:
	var sframe: Transform2D = card_frame(dials[si])
	var w: int = int(TOKEN_ZONE.size.x * ART_PPM)
	var h: int = int(TOKEN_ZONE.size.y * ART_PPM)
	var zone: PackedFloat32Array = _box_blur(_rectify(sframe, TOKEN_ZONE, ART_PPM), w, h, 2)
	var best: PackedFloat32Array = PackedFloat32Array()
	best.resize(w * h)
	best.fill(1e9)
	var covered: PackedByteArray = PackedByteArray()
	covered.resize(w * h)
	var sector_gain: Vector3 = Vector3.ONE
	var centre: Vector2 = dials[si]["center"]
	var reach_px: float = float(dials[si]["radius"]) / float(DialReader.DECK_R_MM["sector"]) * 140.0
	# what's known to lie there: every identified card near the sector, and the
	# face-down backs whose labels were found (zone/sector mm -> that card's mm)
	var layers: Array = []
	for i: int in dials.size():
		if _art_f[i].is_empty() or (dials[i]["center"] as Vector2).distance_to(centre) > reach_px:
			continue
		layers.append([card_frame(dials[i]).affine_inverse() * sframe, _art_f[i], _art_size[i], SIZE_MM[deck_of(dials[i])], i == si])
	if not _back_f.is_empty():
		for lab: Vector2 in labels:
			var card_at: Vector2 = lab - LABEL_TO_CARD
			layers.append([Transform2D(Vector2(1, 0), Vector2(0, 1), -card_at), _back_f, _back_size, SIZE_MM["tech"], false])
	var slack: float = ART_SLACK_MM * ART_PPM
	for layer: Array in layers:
		var to_card: Transform2D = layer[0]
		var art: PackedFloat32Array = layer[1]
		var asz: Vector2i = layer[2]
		var card_mm: Vector2 = layer[3]
		# only the zone pixels this card can cover (its corners' bounding box)
		var span: Rect2i = _card_span(to_card, card_mm, w, h)
		if span.size.x <= 0 or span.size.y <= 0:
			continue
		# lighting: per-channel median photo/art ratio over the card (every 3rd pixel)
		var ratios: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
		for j: int in range(span.position.y, span.end.y, 3):
			for i: int in range(span.position.x, span.end.x, 3):
				var uv: Vector2 = to_card * Vector2(TOKEN_ZONE.position.x + i / ART_PPM, TOKEN_ZONE.position.y + j / ART_PPM)
				if uv.x < 0.5 or uv.y < 0.5 or uv.x > card_mm.x - 0.5 or uv.y > card_mm.y - 0.5:
					continue
				var e: Vector3 = _arr_at(art, asz.x, asz.y, uv.x * ART_PPM, uv.y * ART_PPM)
				if e.x + e.y + e.z <= 60.0:
					continue
				var o: int = (j * w + i) * 3
				for c: int in 3:
					ratios[c].append(zone[o + c] / maxf(e[c], 8.0))
		var gain: Vector3 = Vector3.ONE
		if ratios[0].size() > 50:
			for c: int in 3:
				ratios[c].sort()
				gain[c] = ratios[c][ratios[c].size() >> 1]
		if bool(layer[4]):
			sector_gain = gain
		for j: int in range(span.position.y, span.end.y):
			for i: int in range(span.position.x, span.end.x):
				var uv: Vector2 = to_card * Vector2(TOKEN_ZONE.position.x + i / ART_PPM, TOKEN_ZONE.position.y + j / ART_PPM)
				if uv.x < 0.5 or uv.y < 0.5 or uv.x > card_mm.x - 0.5 or uv.y > card_mm.y - 0.5:
					continue
				var k: int = j * w + i
				var o: int = k * 3
				var px: Vector3 = Vector3(zone[o], zone[o + 1], zone[o + 2])
				var ax: float = uv.x * ART_PPM
				var ay: float = uv.y * ART_PPM
				var d: float = px.distance_to(_arr_at(art, asz.x, asz.y, ax, ay) * gain)
				# a printed detail a millimetre off still counts as the art
				if d >= ART_MATCH:
					for dy: float in [-slack, 0.0, slack]:
						for dx: float in [-slack, 0.0, slack]:
							if dx == 0.0 and dy == 0.0:
								continue
							d = minf(d, px.distance_to(_arr_at(art, asz.x, asz.y, ax + dx, ay + dy) * gain))
				covered[k] = 1
				if d < best[k]:
					best[k] = d
	# table colour: median of what no card covers
	var uncovered: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for k: int in range(0, w * h, 2):
		if covered[k] == 0:
			for c: int in 3:
				uncovered[c].append(zone[k * 3 + c])
	var table: Vector3 = Vector3(90, 62, 42)
	if uncovered[0].size() > 100:
		for c: int in 3:
			uncovered[c].sort()
			table[c] = uncovered[c][uncovered[c].size() >> 1]
	# unexplained pixels, cleaned up (opened twice), then classified by token colour
	var cand: PackedByteArray = PackedByteArray()
	cand.resize(w * h)
	for k: int in w * h:
		var o: int = k * 3
		var tdist: float = Vector3(zone[o] - table.x, zone[o + 1] - table.y, zone[o + 2] - table.z).length()
		cand[k] = 0 if best[k] < ART_MATCH or tdist < TABLE_MATCH else 1
	cand = _dilate(_dilate(_erode(_erode(cand, w, h), w, h), w, h), w, h)
	var cls: PackedByteArray = PackedByteArray()
	cls.resize(w * h)
	cls.fill(255)
	for k: int in w * h:
		if cand[k] == 0:
			continue
		var o: int = k * 3
		var px: Vector3 = Vector3(zone[o] / maxf(sector_gain.x, 0.2), zone[o + 1] / maxf(sector_gain.y, 0.2), zone[o + 2] / maxf(sector_gain.z, 0.2))
		var bd: float = INF
		var bi: int = 255
		for t: int in TOKEN_RGB.size():
			var dd: float = px.distance_to(TOKEN_RGB[t])
			if dd < bd:
				bd = dd
				bi = t
		cls[k] = bi if bd < TOKEN_COLOUR_MAX else 254
	# per colour: blobs with the icon holes filled, kept if compact and token-sized;
	# the count comes from the size (two touching tokens of one colour = 2)
	var counts: Dictionary = {}
	var mm2: float = 1.0 / (ART_PPM * ART_PPM)
	for t: int in TOKEN_RGB.size():
		var m: PackedByteArray = PackedByteArray()
		m.resize(w * h)
		var any: bool = false
		for k: int in w * h:
			if cls[k] == t:
				m[k] = 1
				any = true
		if not any:
			continue
		m = _erode(_erode(_dilate(_dilate(m, w, h), w, h), w, h), w, h)
		for comp: Dictionary in _components(m, w, h):
			var filled: Dictionary = _filled_blob(comp, w)
			var area: float = float(filled["count"]) * mm2
			var per: float = area / TOKEN_SIL_MM2[t]
			if per < TOKEN_AREA_MIN:
				continue
			var n_tok: int = maxi(1, roundi(per))
			if n_tok > TOKEN_MAX_PER_CLUMP:
				continue
			if n_tok == 1 and (float(filled["solidity"]) < TOKEN_SOLIDITY or float(filled["elongation"]) > TOKEN_ELONGATION):
				continue
			var col: int = TOKEN_ORDER[t]
			counts[col] = int(counts.get(col, 0)) + n_tok
	return counts

# Zone pixels (TOKEN_ZONE at ART_PPM, w x h) a card can cover, given zone mm -> card mm.
static func _card_span(to_card: Transform2D, card_mm: Vector2, w: int, h: int) -> Rect2i:
	var to_zone: Transform2D = to_card.affine_inverse()
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for c: Vector2 in [Vector2.ZERO, Vector2(card_mm.x, 0.0), Vector2(0.0, card_mm.y), card_mm]:
		var p: Vector2 = ((to_zone * c) - TOKEN_ZONE.position) * ART_PPM
		lo = lo.min(p)
		hi = hi.max(p)
	var x0: int = clampi(floori(lo.x) - 1, 0, w)
	var y0: int = clampi(floori(lo.y) - 1, 0, h)
	var x1: int = clampi(ceili(hi.x) + 1, 0, w)
	var y1: int = clampi(ceili(hi.y) + 1, 0, h)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

# ── Blob helpers ─────────────────────────────────────────────────────────────

# 4-connected components of a mask: [{box: Rect2i, count, pixels: PackedInt32Array}]
static func _components(m: PackedByteArray, w: int, h: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	for k0: int in w * h:
		if m[k0] == 0 or seen[k0] != 0:
			continue
		var pixels: PackedInt32Array = PackedInt32Array()
		var stack: PackedInt32Array = PackedInt32Array([k0])
		seen[k0] = 1
		var x0: int = w
		var y0: int = h
		var x1: int = -1
		var y1: int = -1
		while not stack.is_empty():
			var k: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			pixels.append(k)
			var x: int = k % w
			@warning_ignore("integer_division")
			var y: int = k / w
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			for n: int in [k - 1, k + 1, k - w, k + w]:
				if n < 0 or n >= w * h or m[n] == 0 or seen[n] != 0:
					continue
				if (n == k - 1 and x == 0) or (n == k + 1 and x == w - 1):
					continue
				seen[n] = 1
				stack.append(n)
		out.append({box = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), count = pixels.size(), pixels = pixels})
	return out

# A blob closed (3 px) with its holes (a token's icon) filled, measured: pixel count,
# solidity (area / convex hull area) and elongation (sqrt of the covariance eigenvalue ratio).
static func _filled_blob(comp: Dictionary, w: int) -> Dictionary:
	var box: Rect2i = comp["box"]
	var pad: int = 4
	var lw: int = box.size.x + pad * 2
	var lh: int = box.size.y + pad * 2
	var m: PackedByteArray = PackedByteArray()
	m.resize(lw * lh)
	for k: int in (comp["pixels"] as PackedInt32Array):
		@warning_ignore("integer_division")
		var y: int = k / w
		var x: int = k % w
		m[(y - box.position.y + pad) * lw + (x - box.position.x + pad)] = 1
	for i: int in 3:
		m = _dilate(m, lw, lh)
	for i: int in 3:
		m = _erode(m, lw, lh)
	# fill holes: whatever background the border can't reach
	var outside: PackedByteArray = PackedByteArray()
	outside.resize(lw * lh)
	var stack: PackedInt32Array = PackedInt32Array()
	for x: int in lw:
		stack.append(x)
		stack.append((lh - 1) * lw + x)
	for y: int in lh:
		stack.append(y * lw)
		stack.append(y * lw + lw - 1)
	while not stack.is_empty():
		var k: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if k < 0 or k >= lw * lh or outside[k] != 0 or m[k] != 0:
			continue
		outside[k] = 1
		var x: int = k % lw
		if x > 0:
			stack.append(k - 1)
		if x < lw - 1:
			stack.append(k + 1)
		stack.append(k - lw)
		stack.append(k + lw)
	var pts: Array[Vector2] = []
	var sx: float = 0.0
	var sy: float = 0.0
	for k: int in lw * lh:
		if outside[k] == 0:
			@warning_ignore("integer_division")
			var p: Vector2 = Vector2(k % lw, k / lw)
			pts.append(p)
			sx += p.x
			sy += p.y
	var n: int = pts.size()
	if n < 5:
		return {count = n, solidity = 0.0, elongation = 99.0}
	var mean: Vector2 = Vector2(sx, sy) / n
	var cxx: float = 0.0
	var cyy: float = 0.0
	var cxy: float = 0.0
	for p: Vector2 in pts:
		var d: Vector2 = p - mean
		cxx += d.x * d.x
		cyy += d.y * d.y
		cxy += d.x * d.y
	cxx /= n
	cyy /= n
	cxy /= n
	var trace: float = cxx + cyy
	var disc: float = sqrt(maxf((cxx - cyy) * (cxx - cyy) / 4.0 + cxy * cxy, 0.0))
	var l1: float = trace / 2.0 + disc
	var l2: float = maxf(trace / 2.0 - disc, 1e-6)
	var hull: PackedVector2Array = Geometry2D.convex_hull(PackedVector2Array(pts))
	var hull_area: float = 0.0
	for i: int in hull.size() - 1:
		hull_area += hull[i].x * hull[i + 1].y - hull[i + 1].x * hull[i].y
	hull_area = absf(hull_area) / 2.0
	return {count = n, solidity = float(n) / maxf(hull_area, 1.0), elongation = sqrt(l1 / l2)}

static func _box_blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp: PackedFloat32Array = src.duplicate()
	var out: PackedFloat32Array = src.duplicate()
	for j: int in h:           # horizontal
		for i: int in w:
			var s: Vector3 = Vector3.ZERO
			var n: int = 0
			for d: int in range(-r, r + 1):
				var x: int = clampi(i + d, 0, w - 1)
				var o: int = (j * w + x) * 3
				s += Vector3(src[o], src[o + 1], src[o + 2])
				n += 1
			var oo: int = (j * w + i) * 3
			tmp[oo] = s.x / n
			tmp[oo + 1] = s.y / n
			tmp[oo + 2] = s.z / n
	for j: int in h:           # vertical
		for i: int in w:
			var s: Vector3 = Vector3.ZERO
			var n: int = 0
			for d: int in range(-r, r + 1):
				var y: int = clampi(j + d, 0, h - 1)
				var o: int = (y * w + i) * 3
				s += Vector3(tmp[o], tmp[o + 1], tmp[o + 2])
				n += 1
			var oo: int = (j * w + i) * 3
			out[oo] = s.x / n
			out[oo + 1] = s.y / n
			out[oo + 2] = s.z / n
	return out

static func _erode(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for j: int in range(1, h - 1):
		for i: int in range(1, w - 1):
			var k: int = j * w + i
			if m[k] != 0 and m[k - 1] != 0 and m[k + 1] != 0 and m[k - w] != 0 and m[k + w] != 0:
				out[k] = 1
	return out

static func _dilate(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out: PackedByteArray = m.duplicate()
	for j: int in range(1, h - 1):
		for i: int in range(1, w - 1):
			var k: int = j * w + i
			if m[k] == 0 and (m[k - 1] != 0 or m[k + 1] != 0 or m[k - w] != 0 or m[k + w] != 0):
				out[k] = 1
	return out

# Row-wise dilate / erode by `r` px (merging letters into words).
static func _dilate_rows(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for j: int in h:
		for i: int in w:
			if m[j * w + i] == 0:
				continue
			for d: int in range(maxi(0, i - r), mini(w, i + r + 1)):
				out[j * w + d] = 1
	return out

static func _erode_rows(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for j: int in h:
		for i: int in w:
			var keep: bool = true
			for d: int in range(i - r, i + r + 1):
				if d >= 0 and d < w and m[j * w + d] == 0:
					keep = false
					break
			if keep:
				out[j * w + i] = 1
	return out
