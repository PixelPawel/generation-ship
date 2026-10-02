class_name DialReader
extends RefCounted

# Reads the printed scan-code dials in a tableau photo. Every card has 12
# small lights in light sockets around its colour orb (sockets painted into the frame art, lights
# drawn by InDesign_Shop/_automation/scan_code): light 0 is a cyan orientation marker,
# lights 1-10 (clockwise) are the card's code, MSB first, light 11 is even
# parity. Codes are the "Code" column of the card sheets (CardData.scan_code /
# adv_scan_code). Only a card's name row stays visible in a real tableau and
# the orb is part of it, so this works where matching card art can't.
#
# Steps (tuned on synthetic tableau photos at ~9 px/mm, see the plan notes):
# 1. find small cyan blobs (marker candidates) on a half-resolution copy —
#    a strict colour test, plus a loose one for tiny blurred markers only;
# 2. pass 1: the clearest markers get a wide radius x angle search — the
#    confident readings give the photo's scale (px per mm) and which way the
#    cards face (all cards of one tableau face roughly the same way);
# 3. pass 2: every marker is searched only at the radii a dial can have at
#    that scale and within +-30 deg of those directions;
# 4. a reading counts if its 11 lights split cleanly into bright/dark, the
#    parity holds, the code is a real card, the lights are dots (brighter
#    than the rim between them) and the size fits its card type.
# Falls back to full resolution when nothing reads at half (far-away photo).

# Dial radius per card type (mm): the light sockets painted into the 2026-10 frames
# (InDesign_Shop/_automation/scan_code/sockets.json). Tech sockets follow a slightly
# oval ring (3.62-3.72 mm), which the scale tolerance below absorbs.
const DECK_R_MM: Dictionary = {"tech": 3.669, "expedition": 3.806, "sector": 4.229}
const MIN_GAP: float = 0.45          # bright/dark split of the 11 lights
const MAX_DARK: float = 0.40
const MIN_LIT: float = 0.50
const MIN_DOT: float = 0.05          # lit light vs the rim halfway to its neighbours
const SCALE_TOLERANCE: float = 0.10
const STRONG_GAP: float = 0.6

var _w: int = 0
var _h: int = 0
var _data: PackedByteArray = PackedByteArray()
var _codes: Dictionary = {}          # code -> "tech" / "expedition" / "sector"
var _cards: Dictionary = {}          # code -> {card: CardData, is_advanced: bool}

## Call on the main thread: collects the card codes from CardDatabase (scene
## tree nodes can't be touched from a worker thread). Then run() — safe on
## a thread, it only works on pixels.
static func create() -> DialReader:
	var reader: DialReader = DialReader.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var db: Node = tree.root.get_node_or_null("/root/CardDatabase") if tree else null
	if db == null:
		return reader
	for cd: CardData in db.get("sectors"):
		reader._add(cd.scan_code, cd, false, "sector")
		reader._add(cd.adv_scan_code, cd, true, "sector")
	for cd: CardData in db.get("techs"):
		reader._add(cd.scan_code, cd, false, "tech")
	for cd: CardData in db.get("expeditions"):
		reader._add(cd.scan_code, cd, false, "expedition")
	return reader

func _add(code: int, cd: CardData, is_adv: bool, deck: String) -> void:
	if code > 0 and not _codes.has(code):
		_codes[code] = deck
		_cards[code] = {card = cd, is_advanced = is_adv}

## Returns one entry per card read: {code, card: CardData, is_advanced,
## center: Vector2, radius: float (both in source-image pixels), up: Vector2
## (unit, towards the card's top), gap}.
func run(source: Image) -> Array[Dictionary]:
	var result: Array[Dictionary] = _read_at(source, 2)
	if result.is_empty():
		result = _read_at(source, 1)
	return result

func _read_at(source: Image, factor: int) -> Array[Dictionary]:
	var img: Image = source.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	if factor > 1:
		img.resize(img.get_width() / factor, img.get_height() / factor, Image.INTERPOLATE_BILINEAR)
	_w = img.get_width()
	_h = img.get_height()
	_data = img.get_data()

	var blobs: Array[Vector3] = _find_markers()   # x, y, diameter

	# Pass 1: scale + facing from the clearest markers.
	var strong_scales: Array[float] = []
	var ups: Array[float] = []
	for b: Vector3 in blobs:
		if strong_scales.size() >= 6:
			break
		if b.z < 2.0 or b.z > 8.0:
			continue
		var radii: Array[float] = []
		var r: float = maxf(4.0, b.z * 3.4)
		while r <= minf(80.0, b.z * 5.8):
			radii.append(r)
			r += 0.75
		var e: Dictionary = _search(b.x, b.y, radii, _all_angles())
		if not e.is_empty() and float(e["gap"]) >= STRONG_GAP:
			strong_scales.append(float(e["r"]) / float(DECK_R_MM[_codes[int(e["code"])]]))
			ups.append(float(e["th"]))
	if strong_scales.is_empty():
		return []
	strong_scales.sort()
	var scale: float = strong_scales[strong_scales.size() / 2]

	# Pass 2: every marker, plausible radii and directions only.
	var radii2: Array[float] = []
	for deck: String in DECK_R_MM:
		for f: float in [0.96, 1.0, 1.04]:
			var rr: float = roundf(float(DECK_R_MM[deck]) * scale * f * 2.0) / 2.0
			if not radii2.has(rr):
				radii2.append(rr)
	var angles: Array[float] = []
	for u: float in ups:
		for d: int in range(-30, 31, 3):
			var a: float = u + deg_to_rad(float(d))
			var dup: bool = false
			for other: float in angles:
				if absf(angle_difference(a, other)) < deg_to_rad(1.5):
					dup = true
					break
			if not dup:
				angles.append(a)
	var cands: Array[Dictionary] = []
	for b: Vector3 in blobs:
		var e: Dictionary = _search(b.x, b.y, radii2, angles)
		if not e.is_empty():
			e["mx"] = b.x
			e["my"] = b.y
			cands.append(e)
	cands.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["gap"]) > float(q["gap"]))

	var out: Array[Dictionary] = []
	for e: Dictionary in cands:
		var code: int = int(e["code"])
		var r: float = float(e["r"])
		if float(e["gap"]) < MIN_GAP or float(e["dot"]) < MIN_DOT:
			continue
		if absf(r / (float(DECK_R_MM[_codes[code]]) * scale) - 1.0) > SCALE_TOLERANCE:
			continue
		var c: Vector2 = Vector2(float(e["cx"]), float(e["cy"]))
		var clash: bool = false
		for d: Dictionary in out:
			if ((d["center"] as Vector2) / float(factor)).distance_to(c) < r * 1.5:
				clash = true
				break
		if clash:
			continue
		var found: Dictionary = _cards[code]
		out.append({
			code = code,
			card = found["card"],
			is_advanced = bool(found["is_advanced"]),
			center = c * float(factor),
			radius = r * float(factor),
			up = (Vector2(float(e["mx"]), float(e["my"])) - c).normalized(),
			gap = float(e["gap"]),
		})
	return out

static func _all_angles() -> Array[float]:
	var a: Array[float] = []
	for i: int in 90:
		a.append(deg_to_rad(float(i) * 4.0))
	return a

# ── Marker candidates ────────────────────────────────────────────────────────

static func _is_cyan(r: int, g: int, b: int) -> bool:
	return b > 140 and g > 110 and r < 120 and b - r > 60 and g - r > 35

static func _is_cyan_loose(r: int, g: int, b: int) -> bool:
	return b > 110 and g > 95 and b - r > 45 and g - r > 30

func _find_markers() -> Array[Vector3]:
	var blobs: Array[Vector3] = []
	for pass_i: int in 2:
		var loose: bool = pass_i == 1
		var max_area: int = 10 if loose else 400
		var seen: PackedByteArray = PackedByteArray()
		seen.resize(_w * _h)
		for y: int in range(0, _h, 2):
			for x: int in _w:
				var i: int = y * _w + x
				if seen[i] != 0 or not _cyan_at(i, loose):
					continue
				var stack: PackedInt32Array = PackedInt32Array([i])
				seen[i] = 1
				var count: int = 0
				var sx: float = 0.0
				var sy: float = 0.0
				var min_x: int = x
				var max_x: int = x
				var min_y: int = y
				var max_y: int = y
				var overflow: bool = false
				while not stack.is_empty():
					var p: int = stack[stack.size() - 1]
					stack.remove_at(stack.size() - 1)
					var px: int = p % _w
					var py: int = p / _w
					count += 1
					if count > max_area:
						overflow = true
						break
					sx += px
					sy += py
					min_x = mini(min_x, px)
					max_x = maxi(max_x, px)
					min_y = mini(min_y, py)
					max_y = maxi(max_y, py)
					for n: int in [p - 1, p + 1, p - _w, p + _w]:
						if n < 0 or n >= _w * _h or seen[n] != 0:
							continue
						if (n == p - 1 and px == 0) or (n == p + 1 and px == _w - 1):
							continue
						if _cyan_at(n, loose):
							seen[n] = 1
							stack.append(n)
				if overflow or count < 2:
					continue
				var bw: int = max_x - min_x + 1
				var bh: int = max_y - min_y + 1
				if maxi(bw, bh) > 2.5 * mini(bw, bh):
					continue
				var bx: float = sx / count
				var by: float = sy / count
				var near: bool = false
				for q: Vector3 in blobs:
					if absf(bx - q.x) < 3.0 and absf(by - q.y) < 3.0:
						near = true
						break
				if not near:
					blobs.append(Vector3(bx, by, sqrt(count * 4.0 / PI)))
	return blobs

func _cyan_at(i: int, loose: bool) -> bool:
	var r: int = _data[i * 3]
	var g: int = _data[i * 3 + 1]
	var b: int = _data[i * 3 + 2]
	return _is_cyan_loose(r, g, b) if loose else _is_cyan(r, g, b)

# ── Dial search ──────────────────────────────────────────────────────────────

# Luminance 0..1 averaged over the 2x2 pixels at (x, y); -1 off the image.
func _lum(x: float, y: float) -> float:
	var xi: int = int(x)
	var yi: int = int(y)
	if xi < 1 or yi < 1 or xi >= _w - 1 or yi >= _h - 1:
		return -1.0
	var s: int = 0
	for o: int in [yi * _w + xi, yi * _w + xi + 1, (yi + 1) * _w + xi, (yi + 1) * _w + xi + 1]:
		s += _data[o * 3] * 299 + _data[o * 3 + 1] * 587 + _data[o * 3 + 2] * 114
	return s / 1020000.0

func _search(mx: float, my: float, radii: Array[float], angles: Array[float]) -> Dictionary:
	var best: Dictionary = {}
	for r: float in radii:
		for th: float in angles:
			var e: Dictionary = _evaluate(mx, my, r, th)
			if not e.is_empty() and (best.is_empty() or float(e["gap"]) > float(best["gap"])):
				best = e
	if best.is_empty():
		return best
	var r0: float = float(best["r"])
	var th0: float = float(best["th"])
	for dr: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for dth: int in range(-3, 4):
			var e: Dictionary = _evaluate(mx, my, r0 + dr, th0 + deg_to_rad(float(dth)))
			if not e.is_empty() and float(e["gap"]) > float(best["gap"]):
				best = e
	return best

# Dial hypothesis: centre at distance r from the marker in direction th.
# Returns {} unless it decodes to a real card's code.
func _evaluate(mx: float, my: float, r: float, th: float) -> Dictionary:
	var cx: float = mx + r * cos(th)
	var cy: float = my + r * sin(th)
	var base: float = atan2(my - cy, mx - cx)
	var vals: PackedFloat32Array = PackedFloat32Array()
	for k: int in range(1, 12):
		var a: float = base + deg_to_rad(30.0 * k)    # clockwise on screen (y points down)
		var v: float = _lum(cx + r * cos(a), cy + r * sin(a))
		if v < 0.0:
			return {}
		vals.append(v)
	var sv: PackedFloat32Array = vals.duplicate()
	sv.sort()
	var gap: float = 0.0
	var cut: int = 0
	for i: int in 10:
		if sv[i + 1] - sv[i] > gap:
			gap = sv[i + 1] - sv[i]
			cut = i
	if gap < 0.22 or sv[cut] > MAX_DARK or sv[cut + 1] < MIN_LIT:
		return {}
	var thr: float = (sv[cut] + sv[cut + 1]) / 2.0
	var code: int = 0
	var ones: int = 0
	for k: int in 10:
		var bit: int = 1 if vals[k] > thr else 0
		code = (code << 1) | bit
		ones += bit
	var parity: int = 1 if vals[10] > thr else 0
	if ones % 2 != parity or not _codes.has(code):
		return {}
	var dot_sum: float = 0.0
	var dot_n: int = 0
	for k: int in range(1, 12):
		if vals[k - 1] <= thr:
			continue
		var a: float = base + deg_to_rad(30.0 * k)
		var m1: float = _lum(cx + r * cos(a - deg_to_rad(15.0)), cy + r * sin(a - deg_to_rad(15.0)))
		var m2: float = _lum(cx + r * cos(a + deg_to_rad(15.0)), cy + r * sin(a + deg_to_rad(15.0)))
		dot_sum += vals[k - 1] - maxf(m1, m2)
		dot_n += 1
	return {gap = gap, code = code, cx = cx, cy = cy, r = r, th = th, dot = dot_sum / maxf(1.0, dot_n)}

# ── Grouping into sectors ────────────────────────────────────────────────────

## Groups read cards into sectors: [[sector, tech, tech…], …], each sector's
## techs/expeditions ordered from the sector outwards. A tech column is a
## run of techs whose orbs line up along the cards' "up" axis; each column
## goes to the sector whose orb is nearest its first card. Cards with no
## sector nearby come back as a group without one (first entry {}).
static func group_into_sectors(dials: Array[Dictionary]) -> Array:
	var sectors: Array[Dictionary] = []
	var techs: Array[Dictionary] = []
	var mm_px: Array[float] = []
	for d: Dictionary in dials:
		var cd: CardData = d["card"]
		var deck: String = "sector" if cd.card_type == CardData.CardType.SECTOR else ("expedition" if cd.card_type == CardData.CardType.EXPEDITION else "tech")
		mm_px.append(float(d["radius"]) / float(DECK_R_MM[deck]))
		if deck == "sector":
			sectors.append(d)
		else:
			techs.append(d)
	if dials.is_empty():
		return []
	mm_px.sort()
	var px_per_mm: float = mm_px[mm_px.size() / 2]

	# Columns: chain techs whose lateral offset (across the card's up axis) is small.
	var columns: Array = []
	var used: Dictionary = {}
	for i: int in techs.size():
		if used.has(i):
			continue
		var col: Array[Dictionary] = [techs[i]]
		used[i] = true
		var grew: bool = true
		while grew:
			grew = false
			for j: int in techs.size():
				if used.has(j):
					continue
				for member: Dictionary in col:
					var up: Vector2 = member["up"]
					var v: Vector2 = (techs[j]["center"] as Vector2) - (member["center"] as Vector2)
					var lateral: float = absf(v.dot(Vector2(-up.y, up.x))) / px_per_mm
					if lateral < 12.0 and absf(v.dot(up)) / px_per_mm < 40.0:
						col.append(techs[j])
						used[j] = true
						grew = true
						break
		columns.append(col)

	var groups: Array = []
	var taken: Dictionary = {}
	var column_of_sector: Dictionary = {}
	# nearest sector for each column, closest pairs first
	var pairs: Array = []
	for ci: int in columns.size():
		var col: Array = columns[ci]
		var up: Vector2 = (col[0] as Dictionary)["up"]
		col.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
			return (p["center"] as Vector2).dot(up) < (q["center"] as Vector2).dot(up))   # closest to the sector (lowest along "up") first
		var first: Vector2 = (col[0] as Dictionary)["center"]
		for si: int in sectors.size():
			var dist: float = first.distance_to(sectors[si]["center"] as Vector2) / px_per_mm
			if dist < 60.0:
				pairs.append([dist, ci, si])
	pairs.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var col_done: Dictionary = {}
	for p: Array in pairs:
		var ci: int = int(p[1])
		var si: int = int(p[2])
		if col_done.has(ci) or taken.has(si):
			continue
		col_done[ci] = true
		taken[si] = true
		column_of_sector[si] = ci
	for si: int in sectors.size():
		var group: Array[Dictionary] = [sectors[si]]
		if column_of_sector.has(si):
			for t: Dictionary in columns[int(column_of_sector[si])]:
				group.append(t)
		groups.append(group)
	for ci: int in columns.size():
		if col_done.has(ci):
			continue
		var group: Array[Dictionary] = [{}]
		for t: Dictionary in columns[ci]:
			group.append(t)
		groups.append(group)
	return groups
