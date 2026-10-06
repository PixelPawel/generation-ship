class_name TableauReader
extends RefCounted

# Second step of Scan Tableau, after DialReader: works out what belongs to each sector.
# Every read dial pins down its card exactly (position, size, which way is up, and the
# oval squash of an angled photo), so each sector's surroundings can be looked at in the
# sector's own millimetre coordinates, whatever angle the photo was taken from:
#  * archived face-up: any card whose dial sits below a sector (players either slide the
#    archive under the sector or leave it fully visible below — both count);
#  * archived face-down: the two cyan lamps flanking the TECH logo on every tech back,
#    counted as pairs below a sector (they also place each back exactly); the TECH
#    lettering itself is the fallback when no lamp pair shows;
#  * stored supply: what no identified card art (±1 mm), card back or the table explains,
#    in a token colour, is matched against the real token art (assets/scan/tokens) at 12
#    rotations, scored on the art inside the token and on how well the blob fits the token's
#    outline (circle, ellipse, square, hexagon, pentagon, nonagon) — so printed supply icons,
#    coloured plates and orange-vs-yellow mix-ups drop out. Matched tokens are counted one
#    by one (touching tokens included).
# Tuned on synthetic photos (InDesign_Shop/_automation/scan_code/mockups2.py); the token
# templates, colours and sizes since come from photos of the real tokens (2026-10-06).

const DIAL_MM: Dictionary = {"sector": Vector2(60.80, 36.72), "tech": Vector2(36.57, 59.33), "expedition": Vector2(37.17, 60.80)}
const SIZE_MM: Dictionary = {"sector": Vector2(67.0, 44.0), "tech": Vector2(44.0, 67.0), "expedition": Vector2(44.0, 67.0)}
const ART_PPM: float = 3.0                       # card art / token zone resolution (px per mm)
# a column of cards whose sector wasn't read (its dial covered) gets a placeholder sector
# where that sector must lie: the column's lowest tech covers the sector's top 18 mm and sits
# ~5 mm in from its left edge, so the sector's top-left is at (-5, 49) in that tech's mm
const PLACEHOLDER_AT_ON_TECH: Vector2 = Vector2(-5.0, 49.0)
const PLACEHOLDER_MIN_GAP_MM: float = 50.0   # sector dials closer than this across the row share one slot
const PLACEHOLDER_ROW_MM: float = 25.0       # how far off the read sectors' row a placeholder may sit
const MAX_SECTORS: int = 6
# archived face-up: dial centre within this box below the sector (sector mm)
const ARCHIVE_BOX: Rect2 = Rect2(-12.0, 40.0, 91.0, 144.0)
# archived face-down: TECH labels (cream word, ~26 x 6 mm) in the strip below the sector
const LABEL_PPM: float = 2.0
const LABEL_ZONE: Rect2 = Rect2(-10.0, 40.0, 87.0, 204.0)
const LABEL_W_MM: Vector2 = Vector2(24.0, 34.0)
const LABEL_H_MM: Vector2 = Vector2(3.0, 10.0)
const LABEL_MERGE_MM: float = 1.5
const LABEL_TO_CARD: Vector2 = Vector2(9.0, 52.5)    # the label's top-left in back-card mm
const BACK_SETTLE_MM: float = 3.0                    # search around that for the best fit
# the back's two cyan lamps, either side of the TECH logo (back-card mm: 6.4 and 37.9, 55.85)
const LAMP_GAP_MM: float = 31.5
const LAMP_GAP_TOL_MM: float = 4.5                 # wide: lower cascade cards look bigger on angled shots
const LAMP_DY_MAX_MM: float = 3.5                    # level with each other (in sector mm)
const LAMP_LOGO_MIN: float = 0.2                     # share of cream TECH lettering between a real pair
const LAMP_D_MM: Vector2 = Vector2(0.5, 2.2)          # plausible blob diameter
const LAMP_MERGE_MM: float = 3.5                     # a lamp's light and bits of its glow
const LAMP_ZONE: Rect2 = Rect2(-15.0, 40.0, 100.0, 210.0)
const LAMP_NOT_A_DIAL_MM: float = 2.5                # blobs this close to a read dial's marker are that marker
const LAMP_PAIR_SPACING_MM: float = 8.0              # cascaded cards are always further apart
const LAMP_MID_ON_CARD: Vector2 = Vector2(22.15, 55.85)
const BACK_SETTLE_STEP_MM: float = 1.0
# stored supply
const TOKEN_ZONE: Rect2 = Rect2(-12.0, 8.0, 91.0, 102.0)
const ART_MATCH: float = 60.0                    # colour distance a pixel still counts as the art
const ART_SLACK_MM: float = 1.0                  # ...also when the art matches this far off
const TABLE_MATCH: float = 40.0
const TOKEN_COLOUR_MAX: float = 80.0
const TOKEN_NEAR: float = 30.0                    # token-coloured pixels count even over card art of that colour
# token types in order: Dust, Metals, Liquids, Organix, Electrix, Thrust (circle, square,
# oval, hexagon, pentagon, octagon)
const TOKEN_ORDER: Array[int] = [CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST]
# measured on the real punched tokens (photos 2026-10-06), in the reader's lighting-corrected
# colours — flatter and darker than the print colours (Dust 208,204,218 / Metals 186,24,40 /
# Liquids 70,124,191 / Organix 63,168,53 / Electrix 233,120,36 / Thrust 240,181,4)
const TOKEN_RGB: Array[Vector3] = [Vector3(159, 148, 142), Vector3(184, 64, 66), Vector3(69, 124, 148),
	Vector3(112, 147, 53), Vector3(193, 121, 56), Vector3(192, 139, 47)]
const TOKEN_FILES: Array[String] = ["Dust", "Metals", "Liquids", "Organix", "Electrix", "Thrust"]
const TOKEN_MM: float = 16.5                     # a real token's long side, roughly (for spacing)
# each template's long side (its whole PNG canvas) in mm: the real punched tokens measured
# against a ruler (photo 2026-10-06), visible cardboard edge taken off
const TOKEN_SIZE_MM: Array[float] = [16.2, 13.3, 17.7, 18.0, 17.1, 18.0]
const MATCH_PPM: float = 1.5                     # art matching resolution
# the matching grid's width (TOKEN_ZONE at MATCH_PPM, as _find_tokens builds it)
const MATCH_GRID_W: int = int(int(TOKEN_ZONE.size.x * ART_PPM) * (MATCH_PPM / ART_PPM))
const MATCH_ROT_STEP: int = 30
const MATCH_MIN: float = 0.45                    # match score a token needs (real tokens next to each other: ~0.45)
const MATCH_MIN_NEXT: float = 0.55               # ...and every further token in the same blob
const MATCH_SHARE_WEIGHT: float = 0.15           # how much a blob's colour share counts when choosing the type
const MATCH_SHAPE_WEIGHT: float = 0.4            # share of the score from the outline fit
const MATCH_SEARCH_MM: float = 3.0               # search this far around a candidate
const MATCH_MAX_PER_BLOB: int = 4
const MATCH_SAME_TOKEN: float = 0.7              # matches closer than this x TOKEN_MM are one token
const MATCH_TYPE_SHARE: float = 0.15            # a token type is tried if this much of a blob is its colour
const MATCH_BLOB_MIN_MM2: float = 29.0           # smaller blobs aren't a token's worth
const MATCH_MM2_PER_TOKEN: float = 180.0          # roughly a real token's area, to bound the matches per blob

var progress: float = 0.0
## Prints every token candidate blob and its match scores (tools/scan_debug).
var debug: bool = false
## Card used as the placeholder sector (set by the caller; null = no placeholders).
var placeholder_card: CardData = null
var _art: Array[Image] = []       # per dial: its card art at ART_PPM (RGB8), or null
var _backs: Array[Image] = []     # tech back art at ART_PPM (EN + the game language)
var _art_f: Array[PackedFloat32Array] = []   # _art as blurred floats (empty where no art)
var _art_size: Array[Vector2i] = []
var _back_f: PackedFloat32Array = PackedFloat32Array()
var _back_size: Vector2i = Vector2i.ZERO
var _token_imgs: Array[Image] = []   # the six token arts (RGBA8), TOKEN_FILES order
# per token: one template per rotation {w, h, rgb (centred, masked), mask, n, norm}
var _templates: Array = []
var _photo: PackedByteArray = PackedByteArray()
var _pw: int = 0
var _photo_gain: float = 1.0      # exposure: the photo's brightest 2% -> 245 (for colour tests)
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
	for n: String in TOKEN_FILES:
		var tex: Texture2D = load("res://assets/scan/tokens/%s.png" % n) as Texture2D
		var img: Image = tex.get_image() if tex else null
		if img:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
		reader._token_imgs.append(img)
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
func analyze(photo: Image, dials: Array[Dictionary], markers: Array[Vector3] = []) -> Array:
	progress = 0.0
	_photo = photo.get_data()
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(256)
	var n_px: int = 0
	for o: int in range(0, _photo.size() - 2, 3 * 37):
		hist[maxi(_photo[o], maxi(_photo[o + 1], _photo[o + 2]))] += 1
		n_px += 1
	var acc: int = 0
	var p98: int = 255
	for v: int in range(255, -1, -1):
		acc += hist[v]
		if float(acc) >= float(n_px) * 0.02:
			p98 = v
			break
	_photo_gain = 245.0 / maxf(float(p98), 60.0)
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
	_build_token_templates()
	if not _backs.is_empty():
		_back_f = _art_floats(_backs[0])
		_back_size = Vector2i(_backs[0].get_width(), _backs[0].get_height())
	var sector_idx: Array[int] = []
	for i: int in dials.size():
		if deck_of(dials[i]) == "sector":
			sector_idx.append(i)
	var archived_of: Dictionary = _archived_face_up(dials, sector_idx)
	# columns without their sector (dial covered): a placeholder sector where it must lie,
	# so the ship keeps its order and that column's cards, archive and supply still count
	if placeholder_card:
		var loose: Array[Dictionary] = []
		for i: int in dials.size():
			if not archived_of.has(i):   # sectors too, so columns that have one keep it
				loose.append(dials[i])
		var n_read: int = sector_idx.size()
		var candidates: Array[Dictionary] = []
		for g: Array in DialReader.group_into_sectors(loose):
			if not (g[0] as Dictionary).is_empty() or g.size() < 2:
				continue
			var tech: Dictionary = g[1]          # the column's card nearest its sector
			var ph: Dictionary = {
				card = placeholder_card, is_advanced = false, placeholder = true,
				center = card_frame(tech) * (PLACEHOLDER_AT_ON_TECH + DIAL_MM["sector"]),
				radius = float(tech["radius"]) * float(DialReader.DECK_R_MM["sector"]) / float(DialReader.DECK_R_MM[deck_of(tech)]),
				up = tech["up"], th = tech["th"], shape = tech["shape"], gap = 0.0,
			}
			if _placeholder_fits(ph, dials, sector_idx, candidates):
				candidates.append(ph)
		# keep the ones that end up with techs of their own, most cards first, up to 6 sectors
		if not candidates.is_empty():
			var trial: Array[Dictionary] = []
			for i: int in dials.size():
				if not archived_of.has(i):
					trial.append(dials[i])
			trial.append_array(candidates)
			var techs_of: Dictionary = {}
			for g: Array in DialReader.group_into_sectors(trial):
				if not (g[0] as Dictionary).is_empty() and (g[0] as Dictionary).has("placeholder"):
					techs_of[candidates.find(g[0])] = g.size() - 1
			var keep: Array[int] = []
			for c: int in candidates.size():
				if int(techs_of.get(c, 0)) > 0:
					keep.append(c)
			keep.sort_custom(func(a: int, b: int) -> bool: return int(techs_of[a]) > int(techs_of[b]))
			keep.resize(clampi(MAX_SECTORS - n_read, 0, keep.size()))
			for c: int in keep:
				dials.append(candidates[c])
				_art.append(null)
				_art_f.append(PackedFloat32Array())
				_art_size.append(Vector2i.ZERO)
				sector_idx.append(dials.size() - 1)
			archived_of = _archived_face_up(dials, sector_idx)
	var results: Array = []
	results.resize(sector_idx.size())
	_done = 0
	var per_sector: Callable = func(k: int) -> void:
		var si: int = sector_idx[k]
		# face-down backs: lamp pairs, else the TECH lettering; either places the back
		# face-down backs are counted by their lamp pairs (the TECH lettering found
		# phantom backs now and then); the lettering still places backs whose lamps
		# don't show, for the token check
		var backs_at: Array[Vector2] = []    # each back's top-left, sector mm
		for mid: Vector2 in _find_lamp_pairs(dials[si], markers, dials):
			backs_at.append(mid - LAMP_MID_ON_CARD)
		var n_backs: int = backs_at.size()
		if backs_at.is_empty():
			for lab: Vector2 in _find_back_labels(dials[si]):
				backs_at.append(lab - LABEL_TO_CARD)
		results[k] = {backs = n_backs, tokens = _find_tokens(dials, si, backs_at), supply = {}}
		_done_mutex.lock()
		_done += 1
		progress = float(_done) / float(sector_idx.size())
		_done_mutex.unlock()
	if not sector_idx.is_empty():
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(per_sector, sector_idx.size()))

	_assign_tokens(results, dials, sector_idx)

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

# A placeholder sector must lie in the row of the sectors that were read and not on top
# of one of them (or of another placeholder): else its column belongs to a read sector.
static func _placeholder_fits(ph: Dictionary, dials: Array[Dictionary], sector_idx: Array[int],
		others: Array[Dictionary]) -> bool:
	var px_mm: float = float(ph["radius"]) / float(DialReader.DECK_R_MM["sector"])
	var up: Vector2 = ph["up"]
	var across: Vector2 = Vector2(-up.y, up.x)
	var row: Array[float] = []
	var taken: Array[Vector2] = []
	for si: int in sector_idx:
		row.append(((dials[si]["center"] as Vector2) - (ph["center"] as Vector2)).dot(up) / px_mm)
		taken.append(dials[si]["center"])
	for o: Dictionary in others:
		taken.append(o["center"])
	for c: Vector2 in taken:
		if absf((c - (ph["center"] as Vector2)).dot(across)) / px_mm < PLACEHOLDER_MIN_GAP_MM:
			return false
	if not row.is_empty():
		row.sort()
		@warning_ignore("integer_division")
		if absf(row[row.size() / 2]) > PLACEHOLDER_ROW_MM:
			return false
	return true

# Face-up archive: each non-sector dial below a sector (nearest sector below wins) ->
# {dial index: sector dial index}.
static func _archived_face_up(dials: Array[Dictionary], sector_idx: Array[int]) -> Dictionary:
	var archived_of: Dictionary = {}
	for i: int in dials.size():
		if deck_of(dials[i]) == "sector":
			continue
		var best_y: float = INF
		for si: int in sector_idx:
			var local: Vector2 = card_frame(dials[si]).affine_inverse() * (dials[i]["center"] as Vector2)
			if ARCHIVE_BOX.has_point(local) and local.y < best_y:
				best_y = local.y
				archived_of[i] = si
	return archived_of

# A token near two columns is found by both sectors: it goes to the one whose column it
# lies closest to (its sector-mm x nearest that sector card's middle). Fills each
# result's "supply" (SupplyColor -> count).
static func _assign_tokens(results: Array, dials: Array[Dictionary], sector_idx: Array[int]) -> void:
	for k: int in results.size():
		var sd: Dictionary = dials[sector_idx[k]]
		var same_px: float = float(sd["radius"]) / float(DialReader.DECK_R_MM["sector"]) * TOKEN_MM * MATCH_SAME_TOKEN
		var supply: Dictionary = {}
		for tok: Array in (results[k]["tokens"] as Array):
			var mine: float = absf(float(tok[2]) - SIZE_MM["sector"].x / 2.0)
			var keep: bool = true
			for k2: int in results.size():
				if k2 == k:
					continue
				for other: Array in (results[k2]["tokens"] as Array):
					if int(other[0]) == int(tok[0]) and (other[1] as Vector2).distance_to(tok[1] as Vector2) < same_px 							and absf(float(other[2]) - SIZE_MM["sector"].x / 2.0) < mine:
						keep = false
			if keep:
				supply[int(tok[0])] = int(supply.get(int(tok[0]), 0)) + 1
		results[k]["supply"] = supply

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

# Midpoints (sector mm) of the cyan lamp pairs below the sector: two lamps level with
# each other, LAMP_GAP_MM apart — one per face-down tech back.
func _find_lamp_pairs(sd: Dictionary, markers: Array[Vector3], dials: Array[Dictionary]) -> Array[Vector2]:
	var mids: Array[Vector2] = []
	var to_mm: Transform2D = card_frame(sd).affine_inverse()
	var px_mm: float = float(sd["radius"]) / float(DialReader.DECK_R_MM["sector"])
	var pts: Array[Vector3] = []    # merged lamps: x, y (sector mm), blob count
	for b: Vector3 in markers:
		if b.z < LAMP_D_MM.x * px_mm or b.z > LAMP_D_MM.y * px_mm:
			continue
		var is_marker: bool = false
		for d: Dictionary in dials:
			if d.has("marker") and (d["marker"] as Vector2).distance_to(Vector2(b.x, b.y)) < LAMP_NOT_A_DIAL_MM * px_mm:
				is_marker = true
				break
		if is_marker:
			continue
		var p: Vector2 = to_mm * Vector2(b.x, b.y)
		if not LAMP_ZONE.has_point(p):
			continue
		var merged: bool = false
		for i: int in pts.size():
			var centre_mm: Vector2 = Vector2(pts[i].x, pts[i].y) / pts[i].z
			if centre_mm.distance_to(p) < LAMP_MERGE_MM:
				pts[i] += Vector3(p.x, p.y, 1.0)
				merged = true
				break
		if not merged:
			pts.append(Vector3(p.x, p.y, 1.0))
	var lamps: Array[Vector2] = []
	for q: Vector3 in pts:
		lamps.append(Vector2(q.x, q.y) / q.z)
	var cands: Array = []   # [error, left index, right index]
	for i: int in lamps.size():
		for j: int in lamps.size():
			var dx: float = lamps[j].x - lamps[i].x
			var dy: float = absf(lamps[j].y - lamps[i].y)
			if dx > 0.0 and absf(dx - LAMP_GAP_MM) <= LAMP_GAP_TOL_MM and dy <= LAMP_DY_MAX_MM:
				# a real pair has the TECH lettering between its lamps
				if _cream_between(card_frame(sd), lamps[i], lamps[j]) < LAMP_LOGO_MIN:
					continue
				cands.append([absf(dx - LAMP_GAP_MM) + dy, i, j])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var used: Dictionary = {}
	for c: Array in cands:
		var i: int = c[1]
		var j: int = c[2]
		if used.has(i) or used.has(j):
			continue
		var mid: Vector2 = (lamps[i] + lamps[j]) / 2.0
		var near: bool = false
		for m: Vector2 in mids:
			if absf(m.y - mid.y) < LAMP_PAIR_SPACING_MM:
				near = true
				break
		if near:
			continue
		used[i] = true
		used[j] = true
		mids.append(mid)
	return mids

# Share of cream TECH-lettering colour along the line between two lamps (sector mm),
# sampled on three rows through the logo.
func _cream_between(frame: Transform2D, a: Vector2, b: Vector2) -> float:
	var n: int = 0
	var cream: int = 0
	for step: int in 25:
		var t: float = 0.2 + 0.6 * float(step) / 24.0
		for dv: float in [-1.0, 0.0, 1.0]:
			var p: Vector2 = frame * (a.lerp(b, t) + Vector2(0.0, dv))
			var c: Vector3 = _sample(p.x, p.y)
			if c.x < 0.0:
				continue
			c *= _photo_gain
			n += 1
			if c.x > 215.0 and c.y > 195.0 and c.z > 130.0 and c.z < 225.0 and c.x - c.z > 15.0:
				cream += 1
	return float(cream) / float(maxi(n, 1))

# ── Stored supply: token-coloured, token-shaped, token-sized blobs ───────────

# Tokens found in the sector's area: [[supply colour, photo position, sector-mm x], …]
# (a token between two columns can be found by both; analyze() gives it to one).
func _find_tokens(dials: Array[Dictionary], si: int, backs_at: Array[Vector2]) -> Array:
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
	# face-down backs found below the sector (zone/sector mm -> that card's mm)
	var layers: Array = []
	for i: int in dials.size():
		if _art_f[i].is_empty() or (dials[i]["center"] as Vector2).distance_to(centre) > reach_px:
			continue
		layers.append([card_frame(dials[i]).affine_inverse() * sframe, _art_f[i], _art_size[i], SIZE_MM[deck_of(dials[i])], i == si])
	if not _back_f.is_empty():
		for at: Vector2 in backs_at:
			# settle each back where its art fits best (a label places it only roughly)
			var card_at: Vector2 = _settle_back(zone, w, h, at)
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
		# a token on card art of its own colour (grey Dust on sector frames, Electrix on orange
		# art) looks "explained": keep token-coloured pixels anyway — the template match (icon +
		# outline) sorts out plain card art
		if cand[k] == 0 and tdist >= TABLE_MATCH:
			var px0: Vector3 = Vector3(zone[o] / maxf(sector_gain.x, 0.2), zone[o + 1] / maxf(sector_gain.y, 0.2), zone[o + 2] / maxf(sector_gain.z, 0.2))
			for t0: int in TOKEN_RGB.size():
				if px0.distance_to(TOKEN_RGB[t0]) < TOKEN_NEAR:
					cand[k] = 1
					break
	cand = _dilate(_dilate(_erode(_erode(cand, w, h), w, h), w, h), w, h)
	if bool(dials[si].get("placeholder", false)):
		# a placeholder's real art is unknown: leave its own card area out
		for j: int in h:
			for i: int in w:
				var p_mm: Vector2 = TOKEN_ZONE.position + Vector2(i, j) / ART_PPM
				if p_mm.x >= 0.0 and p_mm.x <= SIZE_MM["sector"].x and p_mm.y >= 0.0 and p_mm.y <= SIZE_MM["sector"].y:
					cand[j * w + i] = 0
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
	if debug:
		var counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
		var n_cand: int = 0
		for k: int in w * h:
			if cand[k] != 0:
				n_cand += 1
				counts[mini(int(cls[k]), 6) if cls[k] < 6 else 6] += 1
		print("    sector %d: gain %s, table %s, unexplained px %d, by colour D/M/L/O/E/T/none %s" % [
			si, str(sector_gain), str(table.round()), n_cand, str(counts)])
	# Candidates: blobs of any token colour, icon holes filled (an icon can split a token's
	# base colour into slivers), each matched against the real art of every token type
	# with enough colour in it: score = art inside the token + how well the blob fits its
	# outline.
	var found: Array = []
	if _templates.is_empty():
		return found
	var mm2: float = 1.0 / (ART_PPM * ART_PPM)
	# matching grid (MATCH_PPM): gain-normalised colours and the token-coloured mask
	var k_m: float = MATCH_PPM / ART_PPM
	var ws: int = int(w * k_m)
	var hs: int = int(h * k_m)
	var zs: PackedFloat32Array = PackedFloat32Array()
	zs.resize(ws * hs * 3)
	var tokmask: PackedByteArray = PackedByteArray()
	tokmask.resize(w * h)
	for k: int in w * h:
		if cls[k] < 6:
			tokmask[k] = 1
	tokmask = _fill_holes(_erode(_erode(_erode(_dilate(_dilate(_dilate(tokmask, w, h), w, h), w, h), w, h), w, h), w, h), w, h)
	var ms: PackedByteArray = PackedByteArray()
	ms.resize(ws * hs)
	for j: int in hs:
		for i: int in ws:
			var sx: int = mini(int(i / k_m), w - 1)
			var sy: int = mini(int(j / k_m), h - 1)
			var o: int = (sy * w + sx) * 3
			var oo: int = (j * ws + i) * 3
			zs[oo] = zone[o] / maxf(sector_gain.x, 0.2)
			zs[oo + 1] = zone[o + 1] / maxf(sector_gain.y, 0.2)
			zs[oo + 2] = zone[o + 2] / maxf(sector_gain.z, 0.2)
			ms[j * ws + i] = tokmask[sy * w + sx]
	zs = _box_blur(zs, ws, hs, 1)
	var ms_sum: PackedInt32Array = _integral(ms, ws, hs)
	var centres: Array[Vector2] = []
	var same_px: float = MATCH_SAME_TOKEN * TOKEN_MM * MATCH_PPM
	var pad: int = int(MATCH_SEARCH_MM * MATCH_PPM)
	var comps: Array[Dictionary] = _components(tokmask, w, h)
	for comp: Dictionary in comps:
		var area: float = float(comp["count"]) * mm2
		if area < MATCH_BLOB_MIN_MM2:
			continue
		# token types with enough of their colour in this blob
		var share: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
		for k: int in (comp["pixels"] as PackedInt32Array):
			if cls[k] < 6:
				share[cls[k]] += 1
		if debug:
			var bc: Vector2 = TOKEN_ZONE.position + Vector2((comp["box"] as Rect2i).get_center()) / ART_PPM
			var sc: Array[String] = []
			for t: int in 6:
				if share[t] > 0:
					sc.append("%s %d%%" % [TOKEN_FILES[t], roundi(100.0 * share[t] / float(comp["count"]))])
				if share[t] > 0 and not _templates.is_empty():
					var r0: Dictionary = _match_token(zs, ws, hs, ms, ms_sum, t,
						Rect2i(int((comp["box"] as Rect2i).position.x * k_m) - pad, int((comp["box"] as Rect2i).position.y * k_m) - pad,
						int((comp["box"] as Rect2i).size.x * k_m) + pad * 2, int((comp["box"] as Rect2i).size.y * k_m) + pad * 2))
					if not r0.is_empty():
						sc.append("  -> %s score %.2f" % [TOKEN_FILES[t], float(r0["score"])])
			print("    sector %d blob at %s mm, %.0f mm2 (photo %s): %s" % [si, str(bc.round()), area,
				str((sframe * bc).round()), ", ".join(sc)])
		var types: Array[int] = []
		for t: int in 6:
			if float(share[t]) >= MATCH_TYPE_SHARE * float(comp["count"]):
				types.append(t)
		if types.is_empty():
			continue
		var box: Rect2i = comp["box"]
		var region: Rect2i = Rect2i(int(box.position.x * k_m) - pad, int(box.position.y * k_m) - pad,
			int(box.size.x * k_m) + pad * 2, int(box.size.y * k_m) + pad * 2)
		var n_max: int = mini(MATCH_MAX_PER_BLOB, maxi(1, roundi(area / MATCH_MM2_PER_TOKEN)) + 1)
		var work: PackedFloat32Array = zs.duplicate()
		for _try: int in n_max:
			var hit: Dictionary = {}
			# the type also needs its colour: a square Metals template fits almost any blob
			# about as well as the right one, so a blob's colour share tips the choice — counted
			# on what's left of the blob (two touching tokens: once one is matched, the other's
			# colour must decide the next)
			var share_now: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
			var cnt_now: int = 0
			for k: int in (comp["pixels"] as PackedInt32Array):
				if cls[k] >= 6:
					continue
				@warning_ignore("integer_division")
				var oo: int = (mini(int((k / w) * k_m), hs - 1) * ws + mini(int((k % w) * k_m), ws - 1)) * 3
				if work[oo] == 0.0 and work[oo + 1] == 0.0 and work[oo + 2] == 0.0:
					continue   # blanked: an earlier match in this blob
				share_now[cls[k]] += 1
				cnt_now += 1
			for alt: int in types:
				var r: Dictionary = _match_token(work, ws, hs, ms, ms_sum, alt, region)
				if r.is_empty():
					continue
				r["rank"] = float(r["score"]) + MATCH_SHARE_WEIGHT * float(share_now[alt]) / float(maxi(cnt_now, 1))
				if hit.is_empty() or float(r["rank"]) > float(hit["rank"]):
					hit = r
					hit["token"] = alt
			# a further token in an already matched blob has to be convincing on its own
			if hit.is_empty() or float(hit["score"]) < (MATCH_MIN if _try == 0 else MATCH_MIN_NEXT):
				break
			var tp: Dictionary = (_templates[int(hit["token"])] as Array)[int(hit["rot"])]
			var at: Vector2i = hit["at"]
			# blank the matched token so the next search finds the next one
			var tmask: PackedByteArray = tp["mask"]
			var tw: int = tp["w"]
			for ty: int in int(tp["h"]):
				for tx: int in tw:
					if tmask[ty * tw + tx] != 0:
						var o: int = ((at.y + ty) * ws + at.x + tx) * 3
						work[o] = 0.0
						work[o + 1] = 0.0
						work[o + 2] = 0.0
			var c: Vector2 = Vector2(at) + Vector2(tw, int(tp["h"])) / 2.0
			var seen: bool = false
			for prev: Vector2 in centres:
				if prev.distance_to(c) < same_px:
					seen = true
					break
			if seen:
				continue
			centres.append(c)
			var at_mm: Vector2 = TOKEN_ZONE.position + c / MATCH_PPM
			found.append([TOKEN_ORDER[int(hit["token"])], sframe * at_mm, at_mm.x])
	return found

# Best position (sector mm, card's top-left) for a face-down back near `guess`, within
# +-BACK_SETTLE_MM: the shift whose back art differs least from the photo (sampled sparsely,
# per-channel gain taken out by comparing brightness-normalised colours).
func _settle_back(zone: PackedFloat32Array, w: int, h: int, guess: Vector2) -> Vector2:
	var best_at: Vector2 = guess
	var best_err: float = INF
	var steps: int = int(BACK_SETTLE_MM / BACK_SETTLE_STEP_MM)
	for sy: int in range(-steps, steps + 1):
		for sx: int in range(-steps, steps + 1):
			var at: Vector2 = guess + Vector2(sx, sy) * BACK_SETTLE_STEP_MM
			var err: float = 0.0
			var n: int = 0
			for v: int in range(2, 66, 3):
				for u: int in range(2, 43, 3):
					var zp: Vector2 = (at + Vector2(u, v) - TOKEN_ZONE.position) * ART_PPM
					var zi: int = int(zp.x)
					var zj: int = int(zp.y)
					if zi < 0 or zj < 0 or zi >= w or zj >= h:
						continue
					var o: int = (zj * w + zi) * 3
					var px: Vector3 = Vector3(zone[o], zone[o + 1], zone[o + 2])
					var e: Vector3 = _arr_at(_back_f, _back_size.x, _back_size.y, float(u) * ART_PPM, float(v) * ART_PPM)
					err += (px / maxf(px.length(), 1.0)).distance_to(e / maxf(e.length(), 1.0))
					n += 1
			if n > 40 and err / n < best_err:
				best_err = err / n
				best_at = at
	return best_at

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

# ── Token art matching ───────────────────────────────────────────────────────

# Templates of the six token arts at MATCH_PPM, every MATCH_ROT_STEP degrees: colours
# box-blurred like the photo, centred per channel over the token, plus its outline mask.
func _build_token_templates() -> void:
	_templates.clear()
	for ti: int in _token_imgs.size():
		var img: Image = _token_imgs[ti]
		var rots: Array = []
		if img == null:
			_templates.append(rots)
			continue
		# shrink smoothly to the matching scale first (picking single pixels from the
		# full-size art would alias the fine icon lines), then rotate that
		var scale: float = TOKEN_SIZE_MM[ti] * MATCH_PPM / float(maxi(img.get_width(), img.get_height()))
		var small: Image = img.duplicate() as Image
		small.resize(maxi(3, roundi(img.get_width() * scale)), maxi(3, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		var sw: int = small.get_width()
		var sh: int = small.get_height()
		var data: PackedByteArray = small.get_data()
		var side: int = int(ceil(sqrt(float(sw * sw + sh * sh)))) + 2
		for deg: int in range(0, 360, MATCH_ROT_STEP):
			var a: float = deg_to_rad(float(deg))
			var ca: float = cos(a)
			var sa: float = sin(a)
			var rgb: PackedFloat32Array = PackedFloat32Array()
			rgb.resize(side * side * 3)
			var mask: PackedByteArray = PackedByteArray()
			mask.resize(side * side)
			for y: int in side:
				for x: int in side:
					# template pixel -> source pixel (rotate about the centres)
					var dx: float = x + 0.5 - side / 2.0
					var dy: float = y + 0.5 - side / 2.0
					var sxf: float = ca * dx + sa * dy + sw / 2.0
					var syf: float = -sa * dx + ca * dy + sh / 2.0
					var sxi: int = int(sxf)
					var syi: int = int(syf)
					if sxi < 0 or syi < 0 or sxi >= sw or syi >= sh:
						continue
					var o: int = (syi * sw + sxi) * 4
					if data[o + 3] < 160:
						continue
					mask[y * side + x] = 1
					rgb[(y * side + x) * 3] = float(data[o])
					rgb[(y * side + x) * 3 + 1] = float(data[o + 1])
					rgb[(y * side + x) * 3 + 2] = float(data[o + 2])
			rgb = _box_blur(rgb, side, side, 1)
			var mean: Vector3 = Vector3.ZERO
			var n: int = 0
			for k: int in side * side:
				if mask[k] != 0:
					mean += Vector3(rgb[k * 3], rgb[k * 3 + 1], rgb[k * 3 + 2])
					n += 1
			mean /= float(maxi(n, 1))
			var norm: float = 0.0
			for k: int in side * side:
				for c: int in 3:
					if mask[k] != 0:
						rgb[k * 3 + c] -= mean[c]
						norm += rgb[k * 3 + c] * rgb[k * 3 + c]
					else:
						rgb[k * 3 + c] = 0.0
			# masked pixels as offsets: into the matching grid (its width is fixed) and the template
			var poff: PackedInt32Array = PackedInt32Array()
			var toff: PackedInt32Array = PackedInt32Array()
			for y: int in side:
				for x: int in side:
					if mask[y * side + x] != 0:
						poff.append(y * MATCH_GRID_W + x)
						toff.append((y * side + x) * 3)
			rots.append({w = side, h = side, rgb = rgb, mask = mask, n = n, norm = sqrt(norm), poff = poff, toff = toff})
		_templates.append(rots)

# Best placement of token `t` with its centre inside `region` (matching grid px):
# {score, at (template top-left), rot}. Score = (1 - w) * colour NCC over the token
# + w * IoU of the token's outline with the token-coloured mask.
func _match_token(zs: PackedFloat32Array, ws: int, hs: int, ms: PackedByteArray, ms_sum: PackedInt32Array,
		t: int, region: Rect2i) -> Dictionary:
	var rots: Array = _templates[t]
	# coarse: every 2nd position, every rotation; then fine around the best, +-1 rotation step
	var best: Dictionary = {}
	for ri: int in rots.size():
		_match_scan(zs, ws, hs, ms, ms_sum, rots[ri], ri, region, 2, best)
	if best.is_empty():
		return best
	var at: Vector2i = best["at"]
	var r0: int = best["rot"]
	for dr: int in [-1, 0, 1]:
		var ri: int = posmod(r0 + dr, rots.size())
		var tp: Dictionary = rots[ri]
		@warning_ignore("integer_division")
		var c: Vector2i = at + Vector2i(int(rots[r0]["w"]) / 2 - int(tp["w"]) / 2, int(rots[r0]["h"]) / 2 - int(tp["h"]) / 2)
		_match_scan(zs, ws, hs, ms, ms_sum, tp, ri, Rect2i(c.x - 2 + int(tp["w"]) / 2, c.y - 2 + int(tp["h"]) / 2, 5, 5), 1, best)
	return best

# Scores template `tp` with its centre at every `step`-th position of `region` (matching grid
# px), updating `best` {score, at (template top-left), rot}. Score = (1 - w) * colour NCC over
# the token + w * IoU of the token's outline with the token-coloured mask.
func _match_scan(zs: PackedFloat32Array, ws: int, hs: int, ms: PackedByteArray, ms_sum: PackedInt32Array,
		tp: Dictionary, ri: int, region: Rect2i, step: int, best: Dictionary) -> void:
	var tw: int = tp["w"]
	var th: int = tp["h"]
	var rgb: PackedFloat32Array = tp["rgb"]
	var poff: PackedInt32Array = tp["poff"]   # masked template pixel -> offset in the matching grid
	var toff: PackedInt32Array = tp["toff"]   # ...and in the template
	var n: float = float(tp["n"])
	var tnorm: float = tp["norm"]
	@warning_ignore("integer_division")
	var y_lo: int = maxi(0, region.position.y - th / 2)
	@warning_ignore("integer_division")
	var y_hi: int = mini(hs - th, region.end.y - th / 2)
	@warning_ignore("integer_division")
	var x_lo: int = maxi(0, region.position.x - tw / 2)
	@warning_ignore("integer_division")
	var x_hi: int = mini(ws - tw, region.end.x - tw / 2)
	var cnt: int = poff.size()
	for y: int in range(y_lo, y_hi + 1, step):
		for x: int in range(x_lo, x_hi + 1, step):
			var base: int = y * ws + x
			var dot: float = 0.0
			var sr: float = 0.0
			var sg: float = 0.0
			var sb: float = 0.0
			var s2: float = 0.0
			var inter: int = 0
			for i: int in cnt:
				var m: int = base + poff[i]
				var zo: int = m * 3
				var to: int = toff[i]
				var r: float = zs[zo]
				var g: float = zs[zo + 1]
				var b: float = zs[zo + 2]
				dot += r * rgb[to] + g * rgb[to + 1] + b * rgb[to + 2]
				sr += r
				sg += g
				sb += b
				s2 += r * r + g * g + b * b
				inter += ms[m]
			var var_sum: float = s2 - (sr * sr + sg * sg + sb * sb) / n
			var ncc: float = dot / (sqrt(maxf(var_sum, 1e-6)) * tnorm + 1e-6)
			var window: int = _rect_sum(ms_sum, ws, x, y, tw, th)
			var iou: float = float(inter) / float(maxi(int(n) + window - inter, 1))
			var score: float = (1.0 - MATCH_SHAPE_WEIGHT) * ncc + MATCH_SHAPE_WEIGHT * iou
			if best.is_empty() or score > float(best["score"]):
				best["score"] = score
				best["at"] = Vector2i(x, y)
				best["rot"] = ri

# Summed-area table of a 0/1 mask, (w + 1) x (h + 1).
static func _integral(m: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize((w + 1) * (h + 1))
	for y: int in h:
		var row: int = 0
		for x: int in w:
			row += m[y * w + x]
			out[(y + 1) * (w + 1) + x + 1] = out[y * (w + 1) + x + 1] + row
	return out

static func _rect_sum(sat: PackedInt32Array, w: int, x: int, y: int, rw: int, rh: int) -> int:
	var stride: int = w + 1
	return sat[(y + rh) * stride + x + rw] - sat[y * stride + x + rw] - sat[(y + rh) * stride + x] + sat[y * stride + x]

# Fills the holes of a mask (whatever background the border can't reach).
static func _fill_holes(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var outside: PackedByteArray = PackedByteArray()
	outside.resize(w * h)
	var stack: PackedInt32Array = PackedInt32Array()
	for x: int in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y: int in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var k: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if k < 0 or k >= w * h or outside[k] != 0 or m[k] != 0:
			continue
		outside[k] = 1
		var x: int = k % w
		if x > 0:
			stack.append(k - 1)
		if x < w - 1:
			stack.append(k + 1)
		stack.append(k - w)
		stack.append(k + w)
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	for k: int in w * h:
		out[k] = 1 if outside[k] == 0 else 0
	return out

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
