class_name TableauReader
extends RefCounted

# Second step of Scan Tableau, after DialReader: works out what belongs to each sector.
# Every read dial pins down its card exactly (position, size, which way is up, and the
# oval squash of an angled photo), so each sector's surroundings can be looked at in the
# sector's own millimetre coordinates, whatever angle the photo was taken from:
#  * archived face-up: any card whose dial sits below a sector (players either slide the
#    archive under the sector or leave it fully visible below — both count);
#  * archived face-down: tech backs below a sector, counted by matching the lower part of
#    the back art (the "TECH" label) down the strip below it;
#  * stored supply: whatever in the sector's area no identified card art, card back or the
#    table explains, split into clumps, each clump fitted with the token mix whose colours
#    best explain it (tokens overlap, and each token's icon has other colours than its base).
# Tuned on synthetic photos (InDesign_Shop/_automation/scan_code/mockups2.py); archive counts
# are reliable there, token counts only a first guess until tuned on real photos.

const DIAL_MM: Dictionary = {"sector": Vector2(60.80, 36.72), "tech": Vector2(36.57, 59.33), "expedition": Vector2(37.17, 60.80)}
const SIZE_MM: Dictionary = {"sector": Vector2(67.0, 44.0), "tech": Vector2(44.0, 67.0), "expedition": Vector2(44.0, 67.0)}
const ART_PPM: float = 3.0                       # card art / token zone resolution (px per mm)
# archived face-up: dial centre within this box below the sector (sector mm)
const ARCHIVE_BOX: Rect2 = Rect2(-12.0, 40.0, 91.0, 144.0)
# face-down backs: strip below the sector, template = back rows 49-66 mm (the "TECH" label)
const BACK_PPM: float = 1.0
const BACK_ZONE: Rect2 = Rect2(-8.0, 30.0, 83.0, 214.0)
const BACK_ROWS: Vector2 = Vector2(49.0, 66.0)
const BACK_X_RANGE: Vector2 = Vector2(-6.0, 20.0)   # back's left edge relative to the sector's
const BACK_MIN_NCC: float = 0.6
const BACK_SPACING_MM: float = 12.0
# stored supply
const TOKEN_ZONE: Rect2 = Rect2(-12.0, 8.0, 91.0, 102.0)
const ART_MATCH: float = 60.0                    # colour distance a pixel still counts as the art
const TABLE_MATCH: float = 40.0
const TOKEN_COLOUR_MAX: float = 80.0
const CLUMP_MIN_MM2: float = 60.0
const VISIBLE_RANGE: Vector2 = Vector2(0.5, 1.15)
const PER_TOKEN_PENALTY: float = 25.0
# token base colours (punchboard art) and each token's colour signature: mm^2 of one ~14 mm
# token falling into each colour class (Dust, Metals, Liquids, Organix, Electrix, Thrust)
const TOKEN_ORDER: Array[int] = [CardData.SupplyColor.DUST, CardData.SupplyColor.METALS, CardData.SupplyColor.LIQUIDS,
	CardData.SupplyColor.ORGANIX, CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST]
const TOKEN_RGB: Array[Vector3] = [Vector3(208, 204, 218), Vector3(186, 24, 40), Vector3(70, 124, 191),
	Vector3(63, 168, 53), Vector3(233, 120, 36), Vector3(240, 181, 4)]
const TOKEN_SIG: Array = [
	[125.0, 3.0, 0.0, 0.0, 1.0, 0.0], [0.0, 171.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 2.0, 85.0, 0.0, 0.0, 0.0], [0.0, 2.0, 0.0, 97.0, 0.0, 0.0],
	[0.0, 24.0, 0.0, 0.0, 92.0, 4.0], [8.0, 3.0, 0.0, 0.0, 53.0, 75.0]]

var progress: float = 0.0
var _art: Array[Image] = []       # per dial: its card art at ART_PPM (RGB8), or null
var _backs: Array[Image] = []     # tech back art at ART_PPM (EN + the game language)
var _photo: PackedByteArray = PackedByteArray()
var _pw: int = 0
var _ph: int = 0
var _done_mutex: Mutex = Mutex.new()
var _done: int = 0

## Main thread: loads the art of every read card (textures can't be decoded safely on a
## worker thread). Then analyze() on a thread.
static func create(dials: Array[Dictionary]) -> TableauReader:
	var tr: TableauReader = TableauReader.new()
	for d: Dictionary in dials:
		var cd: CardData = d["card"]
		var path: String = cd.adv_local_art_path if bool(d.get("is_advanced", false)) else cd.local_art_path
		var size_mm: Vector2 = SIZE_MM[deck_of(d)]
		tr._art.append(_load_art(path, size_mm))
	var langs: Array[String] = ["EN"]
	var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
	if lang != "EN":
		langs.append(lang)
	for l: String in langs:
		var back: Image = _load_art("res://assets/cards/Tech/%s/GS Techs Back 44x67mm.png" % l, SIZE_MM["tech"])
		if back:
			tr._backs.append(back)
	return tr

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
		var backs: Array[Vector3] = _find_backs(dials[si])
		var supply: Dictionary = _count_tokens(dials, si, backs)
		results[k] = {backs = backs.size(), supply = supply}
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
	progress = 1.0
	return groups

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

static func _art_at(img: Image, u: float, v: float) -> Vector3:
	# bilinear at card mm (u, v) of art stored at ART_PPM
	var x: float = u * ART_PPM
	var y: float = v * ART_PPM
	var w: int = img.get_width()
	var h: int = img.get_height()
	x = clampf(x, 0.0, w - 1.001)
	y = clampf(y, 0.0, h - 1.001)
	var xi: int = int(x)
	var yi: int = int(y)
	var c00: Color = img.get_pixel(xi, yi)
	var c10: Color = img.get_pixel(xi + 1, yi)
	var c01: Color = img.get_pixel(xi, yi + 1)
	var c11: Color = img.get_pixel(xi + 1, yi + 1)
	var c: Color = c00.lerp(c10, x - xi).lerp(c01.lerp(c11, x - xi), y - yi)
	return Vector3(c.r, c.g, c.b) * 255.0

# ── Archived face-down: tech backs below the sector ──────────────────────────

# Each back found: Vector3(left x mm, top y mm, 1 if upside down else 0), sector mm.
func _find_backs(sd: Dictionary) -> Array[Vector3]:
	var found: Array[Vector3] = []
	if _backs.is_empty():
		return found
	var zw: int = int(BACK_ZONE.size.x * BACK_PPM)
	var zh: int = int(BACK_ZONE.size.y * BACK_PPM)
	var zone: PackedFloat32Array = _rectify(card_frame(sd), BACK_ZONE, BACK_PPM)
	var tw: int = int(44.0 * BACK_PPM)
	var th_: int = int((BACK_ROWS.y - BACK_ROWS.x) * BACK_PPM)
	var rowbest: PackedFloat32Array = PackedFloat32Array()
	rowbest.resize(zh - th_ + 1)
	rowbest.fill(-1.0)
	var rowx: PackedInt32Array = PackedInt32Array()
	rowx.resize(zh - th_ + 1)
	var rowflip: PackedByteArray = PackedByteArray()
	rowflip.resize(zh - th_ + 1)
	var x_lo: int = maxi(0, int((BACK_X_RANGE.x - BACK_ZONE.position.x) * BACK_PPM))
	var x_hi: int = mini(zw - tw, int((BACK_X_RANGE.y - BACK_ZONE.position.x) * BACK_PPM))
	for back: Image in _backs:
		for flip: int in 2:
			var tpl: PackedFloat32Array = _back_template(back, flip == 1, tw, th_)
			var tn: float = 0.0
			for t: float in tpl:
				tn += t * t
			tn = sqrt(tn)
			var n: float = float(tw * th_)
			for y: int in range(0, zh - th_ + 1):
				for x: int in range(x_lo, x_hi + 1):
					var dot: float = 0.0
					var s: Vector3 = Vector3.ZERO
					var s2: float = 0.0
					for ty: int in th_:
						var zo: int = ((y + ty) * zw + x) * 3
						var to: int = ty * tw * 3
						for tx: int in tw * 3:
							var z: float = zone[zo + tx]
							dot += z * tpl[to + tx]
							s2 += z * z
							s[tx % 3] += z
					var var_sum: float = s2 - (s.x * s.x + s.y * s.y + s.z * s.z) / n
					var ncc: float = dot / (sqrt(maxf(var_sum, 1e-6)) * tn + 1e-6)
					if ncc > rowbest[y]:
						rowbest[y] = ncc
						rowx[y] = x
						rowflip[y] = flip
	var order: Array = range(rowbest.size())
	order.sort_custom(func(a: int, b: int) -> bool: return rowbest[a] > rowbest[b])
	var peaks: Array[int] = []
	for y: int in order:
		if rowbest[y] < BACK_MIN_NCC:
			break
		var clear: bool = true
		for p: int in peaks:
			if absf(float(y - p)) <= BACK_SPACING_MM * BACK_PPM:
				clear = false
				break
		if clear:
			peaks.append(y)
	for p: int in peaks:
		# the matched rows are the card's physical rows BACK_ROWS either way up
		var top: float = BACK_ZONE.position.y + p / BACK_PPM - BACK_ROWS.x
		found.append(Vector3(BACK_ZONE.position.x + rowx[p] / BACK_PPM, top, 1.0 if rowflip[p] == 1 else 0.0))
	return found

# Rows BACK_ROWS of the back art sampled at BACK_PPM, per-channel mean removed. Upside down,
# the same physical rows show art rows 67-66 .. 67-49 turned around.
static func _back_template(back: Image, flipped: bool, tw: int, th_: int) -> PackedFloat32Array:
	var t: PackedFloat32Array = PackedFloat32Array()
	t.resize(tw * th_ * 3)
	var mean: Vector3 = Vector3.ZERO
	for j: int in th_:
		for i: int in tw:
			var u: float = (i + 0.5) / BACK_PPM
			var v: float = BACK_ROWS.x + (j + 0.5) / BACK_PPM
			var c: Vector3 = _art_at(back, 44.0 - u, 67.0 - v) if flipped else _art_at(back, u, v)
			var o: int = (j * tw + i) * 3
			t[o] = c.x
			t[o + 1] = c.y
			t[o + 2] = c.z
			mean += c
	mean /= float(tw * th_)
	for k: int in tw * th_:
		t[k * 3] -= mean.x
		t[k * 3 + 1] -= mean.y
		t[k * 3 + 2] -= mean.z
	return t

# ── Stored supply ────────────────────────────────────────────────────────────

func _count_tokens(dials: Array[Dictionary], si: int, backs: Array[Vector3]) -> Dictionary:
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
	var reach: float = float(dials[si]["radius"]) / float(DialReader.DECK_R_MM["sector"]) * 140.0
	# every identified card near the sector, then the face-down backs found below it
	var layers: Array = []
	for i: int in dials.size():
		if _art[i] == null or (dials[i]["center"] as Vector2).distance_to(centre) > reach:
			continue
		# zone (sector mm) -> this card's mm
		layers.append([card_frame(dials[i]).affine_inverse() * sframe, _art[i], SIZE_MM[deck_of(dials[i])], i == si])
	for b: Vector3 in backs:
		var to_back: Transform2D = Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(-b.x, -b.y))
		if b.z > 0.5:   # upside down: (u, v) -> (44 - u, 67 - v)
			to_back = Transform2D(Vector2(-1, 0), Vector2(0, -1), Vector2(44.0 + b.x, 67.0 + b.y))
		layers.append([to_back, _backs[0], SIZE_MM["tech"], false])
	for layer: Array in layers:
		var to_card: Transform2D = layer[0]
		var art: Image = layer[1]
		var card_mm: Vector2 = layer[2]
		# lighting: per-channel median photo/art ratio over the card (every 3rd pixel)
		var ratios: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
		for j: int in range(0, h, 3):
			for i: int in range(0, w, 3):
				var uv: Vector2 = to_card * Vector2(TOKEN_ZONE.position.x + i / ART_PPM, TOKEN_ZONE.position.y + j / ART_PPM)
				if uv.x < 0.5 or uv.y < 0.5 or uv.x > card_mm.x - 0.5 or uv.y > card_mm.y - 0.5:
					continue
				var e: Vector3 = _art_at(art, uv.x, uv.y)
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
		if bool(layer[3]):
			sector_gain = gain
		for j: int in h:
			for i: int in w:
				var uv: Vector2 = to_card * Vector2(TOKEN_ZONE.position.x + i / ART_PPM, TOKEN_ZONE.position.y + j / ART_PPM)
				if uv.x < 0.5 or uv.y < 0.5 or uv.x > card_mm.x - 0.5 or uv.y > card_mm.y - 0.5:
					continue
				var e: Vector3 = _art_at(art, uv.x, uv.y) * gain
				var o: int = (j * w + i) * 3
				var d: float = Vector3(zone[o] - e.x, zone[o + 1] - e.y, zone[o + 2] - e.z).length()
				var k: int = j * w + i
				covered[k] = 1
				if d < best[k]:
					best[k] = d
	# table colour: median of what no card covers
	var tr: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for k: int in range(0, w * h, 2):
		if covered[k] == 0:
			for c: int in 3:
				tr[c].append(zone[k * 3 + c])
	var table: Vector3 = Vector3(90, 62, 42)
	if tr[0].size() > 100:
		for c: int in 3:
			tr[c].sort()
			table[c] = tr[c][tr[c].size() >> 1]
	# unexplained pixels, cleaned up (open twice), classified by token colour
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
	# clumps -> best-fitting token mix
	var counts: Dictionary = {}
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(w * h)
	var mm2: float = 1.0 / (ART_PPM * ART_PPM)
	for k0: int in w * h:
		if cand[k0] == 0 or seen[k0] != 0:
			continue
		var obs: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
		var area: float = 0.0
		var stack: PackedInt32Array = PackedInt32Array([k0])
		seen[k0] = 1
		while not stack.is_empty():
			var k: int = stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			area += mm2
			if cls[k] < 6:
				obs[cls[k]] += mm2
			var x: int = k % w
			for n: int in [k - 1, k + 1, k - w, k + w]:
				if n < 0 or n >= w * h or cand[n] == 0 or seen[n] != 0:
					continue
				if (n == k - 1 and x == 0) or (n == k + 1 and x == w - 1):
					continue
				seen[n] = 1
				stack.append(n)
		if area < CLUMP_MIN_MM2:
			continue
		var mix: PackedInt32Array = _best_mix(obs)
		for t: int in 6:
			if mix[t] > 0:
				var col: int = TOKEN_ORDER[t]
				counts[col] = int(counts.get(col, 0)) + mix[t]
	return counts

# Token counts (0-3 each, 1-6 total) whose colour signatures best explain a clump's colour areas.
static func _best_mix(obs: PackedFloat32Array) -> PackedInt32Array:
	var best: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var obs_sum: float = 0.0
	for v: float in obs:
		obs_sum += v
	if obs_sum < CLUMP_MIN_MM2 * 0.5:
		return best
	var best_err: float = INF
	var combo: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	for code: int in 4096:
		var c: int = code
		var total: int = 0
		for t: int in 6:
			combo[t] = c & 3
			c = c >> 2
			total += combo[t]
		if total == 0 or total > 6:
			continue
		var pred: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])
		for t: int in 6:
			if combo[t] == 0:
				continue
			for q: int in 6:
				pred[q] += combo[t] * float(TOKEN_SIG[t][q])
		var op: float = 0.0
		var pp: float = 0.0
		for q: int in 6:
			op += obs[q] * pred[q]
			pp += pred[q] * pred[q]
		var s: float = clampf(op / maxf(pp, 1e-6), VISIBLE_RANGE.x, VISIBLE_RANGE.y)
		var err: float = PER_TOKEN_PENALTY * total
		for q: int in 6:
			err += absf(obs[q] - s * pred[q])
		if err < best_err:
			best_err = err
			best = combo.duplicate()
	return best

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
