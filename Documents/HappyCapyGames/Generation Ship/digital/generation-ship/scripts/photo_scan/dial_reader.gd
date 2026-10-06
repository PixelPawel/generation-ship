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
# Steps (tuned on synthetic tableau photos, InDesign_Shop/_automation/scan_code/mockups*.py,
# which track every light's true position so failures can be measured per dial):
# 1. find small cyan blobs (marker candidates) on a half-resolution copy —
#    a strict colour test, plus a loose one for tiny blurred markers only;
#    the lights themselves are read on the FULL-resolution photo (tech lights
#    are ~6 px across in a phone photo; halving blurs the dark sockets into
#    the pale ring around them);
# 2. pass 1: markers get a wide radius x angle search until a few confident
#    readings give the photo's scale (px per mm) and which way cards face;
# 3. pass 2: every marker of a plausible size is searched only at the radii a
#    dial can have at that scale, facing within +-21 deg of its nearest
#    confident dial; markers are independent, so this runs on all cores;
# 4. both passes try each dial as a circle and as a few ovals (_SHAPES): a
#    phone held at an angle squashes the dials, and the squash leans
#    differently in different parts of the photo, so it's chosen per dial;
# 5. a reading counts if its 11 lights split cleanly into bright/dark, the
#    parity holds, the code is a real card, lit lights are dots (brighter than
#    the rim between them), unlit ones are holes (darker than the rim — this
#    rejects busy card art that happens to decode) and the size fits its card type.

# Dial radius per card type (mm): the light sockets painted into the 2026-10 frames
# (InDesign_Shop/_automation/scan_code/sockets.json). Tech sockets follow a slightly
# oval ring (3.62-3.72 mm), which the scale tolerance below absorbs.
const DECK_R_MM: Dictionary = {"tech": 3.669, "expedition": 3.975, "sector": 4.229}
const MIN_GAP: float = 0.58          # bright/dark split of the 11 lights (real photos 2026-10-06: misreads 0.45-0.56, true reads mostly 0.65+)
const MAX_DARK: float = 0.40
const MIN_LIT: float = 0.50
const MIN_DOT: float = 0.10          # lit light vs the rim halfway to its neighbours (real photos 2026-10-06: real dials 0.17-0.36, misreads ~0.0)
const MIN_HOLE: float = 0.15         # unlit socket vs the rim halfway to its neighbours
const SCALE_TOLERANCE: float = 0.10
const STRONG_GAP: float = 0.6
const STRONG_WANTED: int = 6
const MARKER_D_MM: Vector2 = Vector2(0.45, 1.3)   # plausible marker blob diameter (mm) in pass 2
# Smaller blobs get a quick look only (circle, facing within +-SMALL_FACING_DEG): under lamp light
# a marker's cyan core can shrink to ~0.25 mm (real photos 2026-10-06), and the full search on
# every speck that size would be far too slow.
const MARKER_SMALL_MM: float = 0.2
const SMALL_FACING_DEG: int = 6
const FACING_WINDOW_DEG: int = 21
const FACING_AGREE_DEG: float = 25.0   # pass 1's confident dials must agree on facing...
const SCALE_AGREE: float = 0.2         # ...and on px per mm (perspective stays well inside this)
const AGREE_MIN: int = 3
const PASS1_MAX_TRIED: int = 800       # a clear photo needs ~450 markers for 6 confident dials
const PASS1_HARD_MAX: int = 1200       # and never more: an unreadable photo searched every cyan speck for minutes
const OVAL_ASPECTS: Array[float] = [0.9, 0.8]
const OVAL_STEP_DEG: int = 30

# Read from the main thread while run() works (plain floats/ints, so safe to poll):
# progress 0..1. attempt stays 1 (kept for the UI's label).
var progress: float = 0.0
## Set from the main thread to stop run() early (a new photo, the screen closed): run() then
## returns [] within a moment, so waiting for its thread doesn't freeze the game.
var cancelled: bool = false
var attempt: int = 1
## Prints the first pass's confident readings and the pass counts (tools/scan_debug).
var debug: bool = false
## Debug: photo spots (near a dial's marker) to search over every radius and angle, printed.
var debug_probes: Array[Vector2] = []
var _w: int = 0
var _h: int = 0
var _lum_data: PackedByteArray = PackedByteArray()   # full-resolution greyscale (Image.FORMAT_L8)
var _codes: Dictionary = {}          # code -> "tech" / "expedition" / "sector"
var _cards: Dictionary = {}          # code -> {card: CardData, is_advanced: bool}
var _shapes: Array[PackedFloat32Array] = []   # circle -> image matrices [a11, a12, a21, a22]
var _circle_only: Array[PackedFloat32Array] = []
var _cos30: PackedFloat32Array = PackedFloat32Array()   # cos/sin of 30*k deg, k = 0..11
var _sin30: PackedFloat32Array = PackedFloat32Array()
var _done_mutex: Mutex = Mutex.new()
var _done: int = 0
var _lum_gain: float = 1.0           # exposure normalisation: the photo's brightest 1% -> ~0.95
var _scale: float = 1.0              # median px per mm of the confident dials
var _plane: Vector3 = Vector3.ZERO   # px per mm ~ a + b*x + c*y (perspective), when fitted
var _has_plane: bool = false
## The photo as read (full resolution, RGB8), for TableauReader after run().
var photo: Image = null
## Every cyan blob found (full-resolution x, y, diameter) — dial markers and the
## lamp pairs on face-down card backs — for TableauReader after run().
var markers: Array[Vector3] = []

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

func _init() -> void:
	_shapes.append(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	_circle_only.append(_shapes[0])
	for asp: float in OVAL_ASPECTS:
		for deg: int in range(0, 180, OVAL_STEP_DEG):
			var ph: float = deg_to_rad(float(deg))
			var c: float = cos(ph)
			var s: float = sin(ph)
			# R(ph) * diag(1, asp) * R(-ph): squashed by asp across direction ph
			_shapes.append(PackedFloat32Array([c * c + asp * s * s, c * s - asp * c * s, c * s - asp * c * s, s * s + asp * c * c]))
	for k: int in 12:
		_cos30.append(cos(deg_to_rad(30.0 * k)))
		_sin30.append(sin(deg_to_rad(30.0 * k)))

## Returns one entry per card read: {code, card: CardData, is_advanced,
## center: Vector2, radius: float (both in source-image pixels), up: Vector2
## (unit, towards the card's top), gap}.
func run(source: Image) -> Array[Dictionary]:
	progress = 0.0
	var img: Image = source.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	photo = img.duplicate() as Image
	var small: Image = img.duplicate() as Image
	@warning_ignore("integer_division")
	small.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	var blobs: Array[Vector3] = []   # full-resolution x, y, diameter
	for b: Vector3 in _find_markers(small.get_data(), small.get_width(), small.get_height()):
		blobs.append(Vector3(b.x * 2.0 + 0.5, b.y * 2.0 + 0.5, b.z * 2.0))
	markers = blobs.duplicate()
	img.convert(Image.FORMAT_L8)
	_w = img.get_width()
	_h = img.get_height()
	_lum_data = img.get_data()
	# exposure: scale brightness so the brightest 1% of the photo reads ~0.95 (dim photos keep
	# their lit lights above MIN_LIT; sampled every 7th pixel, plenty for a percentile)
	var hist: PackedInt32Array = PackedInt32Array()
	hist.resize(256)
	var n_s: int = 0
	for i: int in range(0, _lum_data.size(), 7):
		hist[_lum_data[i]] += 1
		n_s += 1
	var acc: int = 0
	var p99: int = 255
	for v: int in range(255, -1, -1):
		acc += hist[v]
		if float(acc) >= float(n_s) * 0.01:
			p99 = v
			break
	_lum_gain = 0.95 / maxf(float(p99) / 255.0, 0.3)
	progress = 0.1

	var t_pass1: int = Time.get_ticks_msec()
	# Pass 1: scale + facing from the clearest markers, a few at a time on all cores.
	var strong_scales: Array[float] = []
	var strong_at: Array[Vector3] = []   # x, y, facing angle th
	var strong_pos: Array[Vector2] = []
	var strong_raw: Array[float] = []
	var pass1: Array[Vector3] = []
	for b: Vector3 in blobs:
		if b.z >= 2.5 and b.z <= 16.0:
			pass1.append(b)
	var batch: int = maxi(2, OS.get_processor_count())
	var next_i: int = 0
	# a confident misread (a busy bit of art, flash glints) would skew the scale and facing
	# for every card near it: keep reading until STRONG_WANTED of them agree with each other
	# (but once AGREE_MIN agree, give up on more after PASS1_MAX_TRIED markers: a bad photo
	# would otherwise search every marker the slow way)
	while next_i < pass1.size():
		var n_agree: int = _agreeing(strong_at, strong_scales).size()
		if n_agree >= STRONG_WANTED or (n_agree >= AGREE_MIN and next_i >= PASS1_MAX_TRIED) or next_i >= PASS1_HARD_MAX:
			break
		var chunk: Array[Vector3] = pass1.slice(next_i, mini(next_i + batch, pass1.size()))
		var found: Array = []
		found.resize(chunk.size())
		if cancelled:
			break
		var wide_search: Callable = func(i: int) -> void:
			var b: Vector3 = chunk[i]
			var radii: Array[float] = []
			var r: float = maxf(4.0, b.z * 3.4)
			while r <= minf(160.0, b.z * 5.8):
				radii.append(r)
				r += 1.5
			found[i] = _search(b.x, b.y, radii, _all_angles())
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(wide_search, chunk.size()))
		for i: int in chunk.size():
			var e: Dictionary = found[i]
			if not e.is_empty() and float(e["gap"]) >= STRONG_GAP:
				strong_scales.append(float(e["r"]) / float(DECK_R_MM[_codes[int(e["code"])]]))
				strong_at.append(Vector3(chunk[i].x, chunk[i].y, float(e["th"])))
				strong_pos.append(Vector2(chunk[i].x, chunk[i].y))
		next_i += chunk.size()
		progress = 0.1 + 0.3 * float(next_i) / float(pass1.size())
	if debug:
		print("  markers %d, pass1 %d tried %d, strong %d" % [blobs.size(), pass1.size(), next_i, strong_scales.size()])
		for q: int in strong_at.size():
			print("    strong at (%d, %d) facing %d deg, scale %.2f px/mm" % [int(strong_at[q].x), int(strong_at[q].y), roundi(rad_to_deg(strong_at[q].z)), strong_scales[q]])
	for pr: Vector2 in debug_probes:
		var rs: Array[float] = []
		var rr: float = 25.0
		while rr <= 80.0:
			rs.append(rr)
			rr += 1.0
		var pe: Dictionary = {}
		var tried: int = 0
		for b: Vector3 in blobs:
			if Vector2(b.x, b.y).distance_to(pr) > 110.0 or b.z < 2.5:
				continue
			tried += 1
			var e1: Dictionary = _search(b.x, b.y, rs, _all_angles())
			if not e1.is_empty() and (pe.is_empty() or float(e1["gap"]) > float(pe["gap"])):
				pe = e1
				pe["bd"] = b.z
		if pe.is_empty():
			print("    probe %s: %d marker blobs, nothing decodes" % [str(pr), tried])
		else:
			var pcd: CardData = _cards[int(pe["code"])]["card"]
			print("    probe %s: %d blobs, best %d %s at (%d, %d) r %.1f facing %d gap %.2f lum %.2f..%.2f dot %.2f marker d %.1f" % [str(pr), tried, int(pe["code"]), pcd.card_name, int(pe["cx"]), int(pe["cy"]), float(pe["r"]), roundi(rad_to_deg(float(pe["th"]))), float(pe["gap"]), float(pe["lo"]), float(pe["hi"]), float(pe["dot"]), float(pe["bd"])])
	# only the agreeing ones set the scale and the facing
	var keep: Array[int] = _agreeing(strong_at, strong_scales)
	if debug:
		print("    agreeing: %s" % str(keep))
	var kept_scales: Array[float] = []
	var kept_at: Array[Vector3] = []
	var kept_pos: Array[Vector2] = []
	for q: int in keep:
		kept_scales.append(strong_scales[q])
		kept_at.append(strong_at[q])
		kept_pos.append(strong_pos[q])
	strong_scales = kept_scales
	strong_at = kept_at
	strong_pos = kept_pos
	if strong_scales.is_empty():
		progress = 1.0
		return []
	strong_raw = strong_scales.duplicate()
	strong_scales.sort()
	@warning_ignore("integer_division")
	_scale = strong_scales[strong_scales.size() / 2]
	_fit_scale_plane(strong_pos, strong_raw)
	progress = 0.4

	# Pass 2: every plausibly sized marker, at the radii a dial has at its spot in the photo
	# (perspective makes near cards bigger), facing like its nearest confident dial.
	var pass2: Array[Vector3] = []
	for b: Vector3 in blobs:
		var ls: float = _local_scale(b.x, b.y)
		if (b.z >= MARKER_SMALL_MM * ls and b.z <= MARKER_D_MM.y * ls) or (b.z >= MARKER_SMALL_MM * _scale and b.z <= MARKER_D_MM.y * _scale):
			pass2.append(b)
	if debug:
		var n_small: int = 0
		for b: Vector3 in pass2:
			if b.z < MARKER_D_MM.x * minf(_local_scale(b.x, b.y), _scale):
				n_small += 1
		print("  pass2 %d markers (%d small)" % [pass2.size(), n_small])
	var t_pass2: int = Time.get_ticks_msec()
	var results: Array = []
	results.resize(pass2.size())
	_done = 0
	if cancelled:
		progress = 1.0
		return []
	var narrow_search: Callable = func(i: int) -> void:
		if cancelled:
			return
		var b: Vector3 = pass2[i]
		var near: Vector3 = strong_at[0]
		for s: Vector3 in strong_at:
			if Vector2(s.x - b.x, s.y - b.y).length_squared() < Vector2(near.x - b.x, near.y - b.y).length_squared():
				near = s
		var tiny: bool = b.z < MARKER_D_MM.x * minf(_local_scale(b.x, b.y), _scale)
		var window: int = SMALL_FACING_DEG if tiny else FACING_WINDOW_DEG
		var angles: Array[float] = []
		for d: int in range(-window, window + 1, 3):
			angles.append(near.z + deg_to_rad(float(d)))
		# dial sizes for this spot: the perspective slope's estimate and the photo-wide
		# median — the slope can misjudge parts of the photo far from the dials it was
		# fitted on, so both are tried
		var radii2: Array[float] = []
		for sc: float in [_local_scale(b.x, b.y), _scale]:
			for deck: String in DECK_R_MM:
				for f: float in [0.96, 1.0, 1.04]:
					var rr: float = roundf(float(DECK_R_MM[deck]) * sc * f * 2.0) / 2.0
					if not radii2.has(rr):
						radii2.append(rr)
		var e: Dictionary = _search(b.x, b.y, radii2, angles, _circle_only if tiny else _shapes)
		if not e.is_empty():
			e["mx"] = b.x
			e["my"] = b.y
		results[i] = e
		_done_mutex.lock()
		_done += 1
		progress = 0.4 + 0.6 * float(_done) / float(pass2.size())
		_done_mutex.unlock()
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(narrow_search, pass2.size()))

	if debug:
		print("  time: pass1 %.1f s, pass2 %.1f s" % [(t_pass2 - t_pass1) / 1000.0, (Time.get_ticks_msec() - t_pass2) / 1000.0])
	var cands: Array[Dictionary] = []
	for e: Dictionary in results:
		if not e.is_empty():
			cands.append(e)
	cands.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["gap"]) > float(q["gap"]))
	var out: Array[Dictionary] = []
	for e: Dictionary in cands:
		var code: int = int(e["code"])
		var r: float = float(e["r"])
		if float(e["gap"]) < MIN_GAP or float(e["dot"]) < MIN_DOT:
			continue
		var deck_r: float = float(DECK_R_MM[_codes[code]])
		if absf(r / (deck_r * _local_scale(float(e["mx"]), float(e["my"]))) - 1.0) > SCALE_TOLERANCE and absf(r / (deck_r * _scale) - 1.0) > SCALE_TOLERANCE:
			continue
		var c: Vector2 = Vector2(float(e["cx"]), float(e["cy"]))
		var clash: bool = false
		for d: Dictionary in out:
			if (d["center"] as Vector2).distance_to(c) < r * 1.5:
				clash = true
				break
		if clash:
			continue
		var found_card: Dictionary = _cards[code]
		out.append({
			code = code,
			card = found_card["card"],
			is_advanced = bool(found_card["is_advanced"]),
			center = c,
			radius = r,
			up = (Vector2(float(e["mx"]), float(e["my"])) - c).normalized(),
			gap = float(e["gap"]),
			dot = float(e["dot"]),
			th = float(e["th"]),
			shape = e["shape"],
			marker = Vector2(float(e["mx"]), float(e["my"])),
		})
	progress = 1.0
	return out

# The largest group of confident readings that agree with one of them (its anchor) on
# facing and scale — all cards in a tableau face the same way at about the same size.
static func _agreeing(at: Array[Vector3], scales: Array[float]) -> Array[int]:
	var best: Array[int] = []
	for a: int in at.size():
		var grp: Array[int] = []
		for b: int in at.size():
			if absf(angle_difference(at[a].z, at[b].z)) <= deg_to_rad(FACING_AGREE_DEG) \
					and absf(scales[b] / scales[a] - 1.0) <= SCALE_AGREE:
				grp.append(b)
		if grp.size() > best.size():
			best = grp
	return best

# Least-squares plane through the confident dials' px-per-mm (perspective: nearer = bigger).
func _fit_scale_plane(pos: Array[Vector2], scales: Array[float]) -> void:
	_has_plane = false
	if pos.size() < 3:
		return
	var m: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)   # normal equations X^T X
	var rhs: Vector3 = Vector3.ZERO
	for i: int in pos.size():
		var row: Vector3 = Vector3(1.0, pos[i].x, pos[i].y)
		m.x += row * row.x
		m.y += row * row.y
		m.z += row * row.z
		rhs += row * scales[i]
	if absf(m.determinant()) < 1e-6:
		return
	_plane = m.inverse() * rhs
	_has_plane = true

func _local_scale(x: float, y: float) -> float:
	if not _has_plane:
		return _scale
	return clampf(_plane.x + _plane.y * x + _plane.z * y, _scale * 0.8, _scale * 1.25)

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

# Cyan blobs in an RGB8 pixel buffer: x, y, diameter (all in that buffer's pixels).
static func _find_markers(data: PackedByteArray, w: int, h: int) -> Array[Vector3]:
	var blobs: Array[Vector3] = []
	for pass_i: int in 2:
		var loose: bool = pass_i == 1
		var max_area: int = 10 if loose else 400
		var seen: PackedByteArray = PackedByteArray()
		seen.resize(w * h)
		for y: int in range(0, h, 2):
			for x: int in w:
				var i: int = y * w + x
				if seen[i] != 0 or not _cyan_at(data, i, loose):
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
					var px: int = p % w
					@warning_ignore("integer_division")
					var py: int = p / w
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
					for n: int in [p - 1, p + 1, p - w, p + w]:
						if n < 0 or n >= w * h or seen[n] != 0:
							continue
						if (n == p - 1 and px == 0) or (n == p + 1 and px == w - 1):
							continue
						if _cyan_at(data, n, loose):
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

static func _cyan_at(data: PackedByteArray, i: int, loose: bool) -> bool:
	var r: int = data[i * 3]
	var g: int = data[i * 3 + 1]
	var b: int = data[i * 3 + 2]
	return _is_cyan_loose(r, g, b) if loose else _is_cyan(r, g, b)

# ── Dial search ──────────────────────────────────────────────────────────────

# Brightness 0..1 averaged over the 2x2 full-resolution pixels at (x, y); -1 off the image.
func _lum(x: float, y: float) -> float:
	var xi: int = int(x)
	var yi: int = int(y)
	if xi < 1 or yi < 1 or xi >= _w - 1 or yi >= _h - 1:
		return -1.0
	var o: int = yi * _w + xi
	return minf(float(_lum_data[o] + _lum_data[o + 1] + _lum_data[o + _w] + _lum_data[o + _w + 1]) / 1020.0 * _lum_gain, 1.0)

# Best reading for the marker at (mx, my) over every dial shape, radius and facing given.
func _search(mx: float, my: float, radii: Array[float], angles: Array[float], shapes: Array[PackedFloat32Array] = []) -> Dictionary:
	var best: Dictionary = {}
	for shape: PackedFloat32Array in (shapes if not shapes.is_empty() else _shapes):
		var e: Dictionary = _search_shape(mx, my, radii, angles, shape)
		if not e.is_empty() and (best.is_empty() or float(e["gap"]) > float(best["gap"])):
			best = e
			best["shape"] = shape
	return best

func _search_shape(mx: float, my: float, radii: Array[float], angles: Array[float], shape: PackedFloat32Array) -> Dictionary:
	var best: Dictionary = {}
	for r: float in radii:
		for th: float in angles:
			var e: Dictionary = _evaluate(mx, my, r, th, shape)
			if not e.is_empty() and (best.is_empty() or float(e["gap"]) > float(best["gap"])):
				best = e
	if best.is_empty():
		return best
	var r0: float = float(best["r"])
	var th0: float = float(best["th"])
	for dr: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for dth: int in range(-3, 4):
			var e: Dictionary = _evaluate(mx, my, r0 + dr, th0 + deg_to_rad(float(dth)), shape)
			if not e.is_empty() and float(e["gap"]) > float(best["gap"]):
				best = e
	return best

# Dial hypothesis: on the undistorted (circle) dial the centre lies at distance r
# from the marker in direction th; `shape` maps that circle onto the photo.
# Returns {} unless it decodes to a real card's code.
func _evaluate(mx: float, my: float, r: float, th: float, shape: PackedFloat32Array) -> Dictionary:
	var a11: float = shape[0]
	var a12: float = shape[1]
	var a21: float = shape[2]
	var a22: float = shape[3]
	var ct: float = cos(th)
	var st: float = sin(th)
	var cx: float = mx + r * (a11 * ct + a12 * st)
	var cy: float = my + r * (a21 * ct + a22 * st)
	# light k sits at angle th + 180 + 30k (clockwise on screen, y points down)
	var cb: float = -ct
	var sb: float = -st
	var vals: PackedFloat32Array = PackedFloat32Array()
	vals.resize(11)
	for k: int in range(1, 12):
		var u: float = r * (cb * _cos30[k] - sb * _sin30[k])
		var v: float = r * (sb * _cos30[k] + cb * _sin30[k])
		var val: float = _lum(cx + a11 * u + a12 * v, cy + a21 * u + a22 * v)
		if val < 0.0:
			return {}
		vals[k - 1] = val
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
	# rim halfway between neighbouring lights (15 deg either side): lit lights must
	# stand out above it, unlit sockets must be holes below it
	var c15: float = cos(deg_to_rad(15.0))
	var s15: float = sin(deg_to_rad(15.0))
	var dot_sum: float = 0.0
	var dot_n: int = 0
	var hole_sum: float = 0.0
	var hole_n: int = 0
	for k: int in range(1, 12):
		var ck: float = cb * _cos30[k] - sb * _sin30[k]
		var sk: float = sb * _cos30[k] + cb * _sin30[k]
		var u1: float = r * (ck * c15 + sk * s15)
		var v1: float = r * (sk * c15 - ck * s15)
		var u2: float = r * (ck * c15 - sk * s15)
		var v2: float = r * (sk * c15 + ck * s15)
		var m1: float = _lum(cx + a11 * u1 + a12 * v1, cy + a21 * u1 + a22 * v1)
		var m2: float = _lum(cx + a11 * u2 + a12 * v2, cy + a21 * u2 + a22 * v2)
		if vals[k - 1] > thr:
			dot_sum += vals[k - 1] - maxf(m1, m2)
			dot_n += 1
		else:
			hole_sum += minf(m1, m2) - vals[k - 1]
			hole_n += 1
	if hole_sum / maxf(1.0, hole_n) < MIN_HOLE:
		return {}
	return {gap = gap, code = code, cx = cx, cy = cy, r = r, th = th, dot = dot_sum / maxf(1.0, dot_n), lo = sv[0], hi = sv[10]}

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
	@warning_ignore("integer_division")
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
