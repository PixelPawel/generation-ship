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
const STRONG_GAP: float = 0.7
const STRONG_WANTED: int = 6
const MARKER_D_MM: Vector2 = Vector2(0.45, 2.1)   # plausible marker blob diameter (mm) in pass 2 (bigger diamond since 2026-10-14: ~1.5-1.7 mm)
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
const COLUMN_FACING_COS: float = 0.94    # cards of one column face within ~20 deg of each other

# Strip check (2026-11-01): the strip next to a dial (name banner + colour orb on techs and
# expeditions, the part of a sector below the techs that overlap it) stays visible whenever the
# dial does, so every reading is compared with that strip of the card it decoded to and of the
# cards one or two lights away (assets/scan/strips: tools/build_scan_strips.py, EN + the game
# language, as the printed cards may be either). Correlation per colour channel, so lighting and
# white balance drop out. It drops readings with no such card there (busy art that decoded),
# swaps a misread for the neighbouring code whose strip fits clearly better, and lets weaker
# readings in when their strip beats every other card of that type.
const StripLayout = preload("res://scripts/photo_scan/strip_layout.gd")
const STRIP_BOX: Dictionary = {"tech": Rect2(1.0, 52.0, 43.0, 14.5), "expedition": Rect2(1.0, 53.0, 43.0, 13.5), "sector": Rect2(1.0, 21.0, 65.0, 22.0)}
const STRIP_SUB: int = 3                 # photo sub-samples per strip pixel and axis (box average)
const STRIP_PHANTOM: float = 0.35        # below: no card of that code there
const STRIP_SWAP: float = 0.04           # a neighbouring code this much better replaces the reading...
const STRIP_SWAP_MIN: float = 0.45       # ...if it fits well itself (else it's busy art: dropped below)
# a weak reading needs this much and at most STRIP_WEAK_SLACK below the best other card of its
# type (low-contrast synthetic photos 2026-11-01: 191 true / 0 false accepted; some cards'
# strips are near twins, so the true card can trail one by a hair)
const STRIP_WEAK_MIN: float = 0.4
const STRIP_WEAK_SLACK: float = 0.01
const STRIP_WEAK_SWAP_MARGIN: float = 0.02   # a weak misread's stand-in must beat every other card by this
const STRIP_WEAK_TRY: float = 0.15           # ...and is only looked for if the reading's own strip looks like a card at all
const STRIP_SURE_GAP: float = 0.7        # readings this clean are never dropped by their strip alone
# weak readings (below the limits above; kept only if their strip confirms them): the split as
# a share of the dial's own bright-dark range, an absolute floor, and unlit sockets still holes
# (low-contrast synthetic photos 2026-11-01: every true dial decodes right at rel >= 0.45)
const WEAK_GAP: float = 0.15
const WEAK_REL: float = 0.5
const WEAK_HOLE_MIN: float = 0.05
const WEAK_HOLE_REL: float = 0.25
# a low-contrast dial counts as confident in pass 1 with a split this clear relative to its range
const LOWC_STRONG_REL: float = 0.85
const LOWC_STRONG_GAP: float = 0.3

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
## Prints every reading's strip check (tools/scan_debug).
var debug_strips: bool = false
var _strip_arts: Dictionary = {}     # code -> Array[PackedFloat32Array]: per language, planar RGB, each channel centred + unit length
var _strip_dims: Dictionary = {}     # deck -> Vector2i (strip pixels)
var _rgb: PackedByteArray = PackedByteArray()   # the photo, full resolution RGB8

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
	reader._load_strips()
	return reader

# The strip atlases (main thread: textures). EN always, plus the game language.
func _load_strips() -> void:
	var langs: Array[String] = ["EN"]
	var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
	if lang != "EN":
		langs.append(lang)
	for l: String in langs:
		var path: String = "res://assets/scan/strips/%s.png" % l
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		var img: Image = tex.get_image() if tex else null
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGB8)
		for code: int in StripLayout.CELLS:
			if not _codes.has(code):
				continue
			var c: Array = StripLayout.CELLS[code]
			var w: int = int(c[2])
			var h: int = int(c[3])
			var data: PackedByteArray = img.get_region(Rect2i(int(c[0]), int(c[1]), w, h)).get_data()
			var f: PackedFloat32Array = PackedFloat32Array()
			f.resize(w * h * 3)
			for i: int in w * h:
				for ch: int in 3:
					f[ch * w * h + i] = float(data[i * 3 + ch])
			if not _strip_arts.has(code):
				_strip_arts[code] = []
			(_strip_arts[code] as Array).append(_normalise_planar(f, w * h))
			_strip_dims[str(c[4])] = Vector2i(w, h)

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
	_rgb = photo.get_data()
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
	var strong_scales: Array[float] = []
	var strong_at: Array[Vector3] = []   # x, y, facing angle th
	var strong_pos: Array[Vector2] = []
	var strong_raw: Array[float] = []
	var strong_clean: Array[bool] = []  # clean reading (else a low-contrast one)
	# a second try when nothing agrees: the marker search on a white-balanced copy (a warm lamp
	# the phone didn't correct can turn the violet diamond orange-brown); only failed photos pay for it
	for try_i: int in 2:
		if try_i == 1:
			if not strong_scales.is_empty() or cancelled or not _balance(small):
				break
			attempt = 2
			blobs.clear()
			for b: Vector3 in _find_markers(small.get_data(), small.get_width(), small.get_height()):
				blobs.append(Vector3(b.x * 2.0 + 0.5, b.y * 2.0 + 0.5, b.z * 2.0))
			markers = blobs.duplicate()
			strong_scales.clear()
			strong_at.clear()
			strong_pos.clear()
			strong_clean.clear()
		# Pass 1: scale + facing from the clearest markers, a few at a time on all cores.
		var pass1: Array[Vector3] = []
		for b: Vector3 in blobs:
			if b.z >= 2.5 and b.z <= 36.0:
				pass1.append(b)
		var batch: int = maxi(2, OS.get_processor_count())
		var next_i: int = 0
		# a confident misread (a busy bit of art, flash glints) would skew the scale and facing
		# for every card near it: keep reading until STRONG_WANTED of them agree with each other
		# (but once AGREE_MIN agree, give up on more after PASS1_MAX_TRIED markers: a bad photo
		# would otherwise search every marker the slow way)
		while next_i < pass1.size():
			# done once enough clean readings agree; low-contrast ones end the search only when
			# twice as many agree with not a clean one among them (a dim or soft photo)
			var grp: Array[int] = _agreeing(strong_at, strong_scales, strong_clean)
			var n_agree: int = 0
			for q: int in grp:
				if strong_clean[q]:
					n_agree += 1
			if n_agree == 0 and grp.size() >= 2 * STRONG_WANTED:
				n_agree = STRONG_WANTED
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
				# from ~1.9 x the marker blob (the bigger diamond since 2026-10-14: dial radius ~2.2-2.5 x its blob) to 5.8 x (a partly detected, blurred diamond)
				var r: float = maxf(4.0, b.z * 1.9)
				while r <= minf(160.0, b.z * 5.8):
					radii.append(r)
					r += 1.5
				found[i] = _search(b.x, b.y, radii, _all_angles())
			WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(wide_search, chunk.size()))
			for i: int in chunk.size():
				var e: Dictionary = found[i]
				if e.is_empty():
					continue
				var is_clean: bool = bool(e["clean"]) and float(e["gap"]) >= STRONG_GAP
				if is_clean or (float(e["rel"]) >= LOWC_STRONG_REL and float(e["gap"]) >= LOWC_STRONG_GAP):
					strong_scales.append(float(e["r"]) / float(DECK_R_MM[_codes[int(e["code"])]]))
					strong_at.append(Vector3(chunk[i].x, chunk[i].y, float(e["th"])))
					strong_pos.append(Vector2(chunk[i].x, chunk[i].y))
					strong_clean.append(is_clean)
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
		var keep: Array[int] = _agreeing(strong_at, strong_scales, strong_clean)
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
		# fitted on, so both are tried. A decode only counts if its card type's ring is that
		# size here (the size check, inside the search): a sector ring read at a size where it
		# decodes to some tech would otherwise win and hide the sector's own reading.
		var radii2: Array[float] = []
		var lsc: float = _local_scale(b.x, b.y)
		for sc: float in [lsc, _scale]:
			for deck: String in DECK_R_MM:
				for f: float in [0.92, 0.96, 1.0, 1.04, 1.08]:   # +-8 %: dials near the photo edges stray from the fitted slope
					var rr: float = roundf(float(DECK_R_MM[deck]) * sc * f * 2.0) / 2.0
					if not radii2.has(rr):
						radii2.append(rr)
		var e: Dictionary = _search(b.x, b.y, radii2, angles, _circle_only if tiny else _shapes, Vector2(lsc, _scale))
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
	# clean readings first; weak ones (below the limits, above WEAK_*) only where nothing clean
	# was read, and only if their strip confirms them (_check_strips)
	var out: Array[Dictionary] = []
	var weak: Array[Dictionary] = []
	for pass_weak: bool in [false, true]:
		if pass_weak and _strip_arts.is_empty():
			break
		for e: Dictionary in cands:
			var code: int = int(e["code"])
			var r: float = float(e["r"])
			var is_weak: bool = not bool(e["clean"]) or float(e["gap"]) < MIN_GAP or float(e["dot"]) < MIN_DOT
			if is_weak != pass_weak or float(e["gap"]) < WEAK_GAP:
				continue
			var deck_r: float = float(DECK_R_MM[_codes[code]])
			if absf(r / (deck_r * _local_scale(float(e["mx"]), float(e["my"]))) - 1.0) > SCALE_TOLERANCE and absf(r / (deck_r * _scale) - 1.0) > SCALE_TOLERANCE:
				continue
			var c: Vector2 = Vector2(float(e["cx"]), float(e["cy"]))
			var clash: bool = false
			for d: Dictionary in out + weak:
				if (d["center"] as Vector2).distance_to(c) < r * 1.5:
					clash = true
					break
			if clash:
				continue
			var found_card: Dictionary = _cards[code]
			var entry: Dictionary = {
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
			}
			if pass_weak:
				entry["weak"] = true
				weak.append(entry)
			else:
				out.append(entry)
	out = _check_strips(out, weak)
	progress = 1.0
	return out

# ── Strip check ──────────────────────────────────────────────────────────────

# Every reading's strip against its card and the cards one or two lights away (weak readings:
# against every card of their type). Returns the readings kept, misreads swapped.
func _check_strips(strong: Array[Dictionary], weak: Array[Dictionary]) -> Array[Dictionary]:
	if _strip_arts.is_empty():
		return strong
	var all: Array[Dictionary] = strong + weak
	var keep: Array = []
	keep.resize(all.size())
	var verdict: Callable = func(i: int) -> void:
		keep[i] = _strip_verdict(all[i])
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(verdict, all.size()))
	var out: Array[Dictionary] = []
	for i: int in all.size():
		if not bool(keep[i]):
			continue
		var clash: bool = false
		for d: Dictionary in out:
			if (d["center"] as Vector2).distance_to(all[i]["center"] as Vector2) < float(all[i]["radius"]) * 1.5:
				clash = true
				break
		if not clash:
			out.append(all[i])
	return out

func _strip_verdict(d: Dictionary) -> bool:
	var code: int = int(d["code"])
	var deck: String = _codes[code]
	var is_weak: bool = bool(d.get("weak", false))
	var ph: Array[PackedFloat32Array] = _photo_strips(d, deck)
	if ph.is_empty():
		# strip off the photo (a card at its edge): only a really clean dial is trusted unchecked
		d["strip"] = -1.0
		return not is_weak and float(d["gap"]) >= STRIP_SURE_GAP
	var own: float = -2.0
	var at: int = 0
	for s: int in ph.size():
		var v: float = _strip_ncc(ph[s], code)
		if v > own:
			own = v
			at = s
	d["strip"] = own
	var ok: bool = true
	var why: String = "ok"
	var other: float = -2.0
	var other_code: int = 0
	if is_weak:
		# a weak reading whose strip doesn't fit may be a misread too: the neighbouring code that
		# fits clearly better stands in, if it then beats every other card of its type by a margin
		var cand: int = code
		var cand_s: float = own
		if own < STRIP_WEAK_MIN:
			# (busy art that decoded scores ~0 against every card: no use trying neighbours)
			if own < STRIP_WEAK_TRY:
				cand = -1
			for c2: int in (_neighbours(code, deck) if cand > 0 else []):
				var v2: float = _strip_ncc(ph[at], c2)
				if v2 > cand_s:
					cand = c2
					cand_s = v2
			if cand <= 0 or cand == code or cand_s < STRIP_SWAP_MIN or cand_s - own <= STRIP_SWAP:
				cand = -1
		if cand > 0:
			for c3: int in _deck_codes(deck):
				if c3 == cand:
					continue
				var v3: float = _strip_ncc(ph[at], c3)
				if v3 > other:
					other = v3
					other_code = c3
			if cand == code:
				ok = own >= STRIP_WEAK_MIN and own >= other - STRIP_WEAK_SLACK
			else:
				ok = cand_s >= other + STRIP_WEAK_SWAP_MARGIN
		else:
			ok = false
		why = "weak accepted" if ok else "weak rejected"
		if ok and cand != code:
			_swap(d, cand, cand_s)
			why = "weak, swapped from %d" % code
	else:
		for c2: int in _neighbours(code, deck):
			var v2: float = _strip_ncc(ph[at], c2)
			if v2 > other:
				other = v2
				other_code = c2
		if other_code > 0 and other - own > STRIP_SWAP and other >= STRIP_SWAP_MIN:
			_swap(d, other_code, other)
			why = "swapped from %d" % code
		elif own < STRIP_PHANTOM and float(d["gap"]) < STRIP_SURE_GAP:
			ok = false
			why = "dropped"
	if debug_strips:
		var c: Vector2 = d["center"]
		print("    strip %4d at (%d, %d) gap %.2f%s: own %.3f, best other %d %.3f -> %s" % [code, int(c.x), int(c.y), float(d["gap"]),
			" weak" if is_weak else "", own, other_code, other, why])
	return ok

# A reading taken over by another code (its strip fits that card).
func _swap(d: Dictionary, code: int, score: float) -> void:
	var found_card: Dictionary = _cards[code]
	d["code"] = code
	d["card"] = found_card["card"]
	d["is_advanced"] = bool(found_card["is_advanced"])
	d["corrected"] = true
	d["strip"] = score

# The photo under a reading's strip box at the atlas resolution plus a pixel all round (each
# pixel a box average of STRIP_SUB^2 photo samples), as nine windows shifted by up to a pixel
# (the dial pins the card down to about that), each normalised. [] if it leaves the photo.
func _photo_strips(d: Dictionary, deck: String) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var dims: Vector2i = _strip_dims.get(deck, Vector2i.ZERO)
	if dims == Vector2i.ZERO:
		return out
	var box: Rect2 = STRIP_BOX[deck]
	var step: Vector2 = Vector2(box.size.x / dims.x, box.size.y / dims.y)
	var f: Transform2D = _card_frame(d, deck)
	var bw: int = dims.x + 2
	var bh: int = dims.y + 2
	var big: PackedFloat32Array = PackedFloat32Array()
	big.resize(bw * bh * 3)
	var sub: float = 1.0 / STRIP_SUB
	var inv: float = 1.0 / float(STRIP_SUB * STRIP_SUB)
	for j: int in bh:
		for i: int in bw:
			var acc: Vector3 = Vector3.ZERO
			for sj: int in STRIP_SUB:
				for si: int in STRIP_SUB:
					var p: Vector2 = f * Vector2(box.position.x + (i - 1 + (si + 0.5) * sub) * step.x, box.position.y + (j - 1 + (sj + 0.5) * sub) * step.y)
					var xi: int = int(p.x)
					var yi: int = int(p.y)
					if xi < 0 or yi < 0 or xi >= _w or yi >= _h:
						return out
					var o: int = (yi * _w + xi) * 3
					acc += Vector3(_rgb[o], _rgb[o + 1], _rgb[o + 2])
			var k: int = j * bw + i
			big[k] = acc.x * inv
			big[bw * bh + k] = acc.y * inv
			big[2 * bw * bh + k] = acc.z * inv
	var n: int = dims.x * dims.y
	for oy: int in 3:
		for ox: int in 3:
			var win: PackedFloat32Array = PackedFloat32Array()
			win.resize(n * 3)
			for ch: int in 3:
				for j: int in dims.y:
					var src: int = ch * bw * bh + (j + oy) * bw + ox
					var dst: int = ch * n + j * dims.x
					for i: int in dims.x:
						win[dst + i] = big[src + i]
			out.append(_normalise_planar(win, n))
	return out

# Correlation of a normalised photo strip with a card's strip (the best of the languages
# loaded), averaged over the three colour channels: -1..1.
func _strip_ncc(pv: PackedFloat32Array, code: int) -> float:
	var best: float = -2.0
	for art: PackedFloat32Array in (_strip_arts.get(code, []) as Array):
		if art.size() != pv.size():
			continue
		var s: float = 0.0
		for k: int in pv.size():
			s += pv[k] * art[k]
		best = maxf(best, s / 3.0)
	return best

# Each colour plane (n values each) centred and scaled to unit length.
static func _normalise_planar(f: PackedFloat32Array, n: int) -> PackedFloat32Array:
	for ch: int in 3:
		var mean: float = 0.0
		for k: int in range(ch * n, ch * n + n):
			mean += f[k]
		mean /= float(n)
		var ss: float = 0.0
		for k: int in range(ch * n, ch * n + n):
			f[k] -= mean
			ss += f[k] * f[k]
		var norm: float = sqrt(ss)
		for k: int in range(ch * n, ch * n + n):
			f[k] = f[k] / norm if norm > 1e-3 else 0.0
	return f

# Real codes of the same card type one or two code lights away (with the parity light, those
# misreadings pass the parity check too).
func _neighbours(code: int, deck: String) -> Array[int]:
	var out: Array[int] = []
	for a: int in 10:
		var c1: int = code ^ (1 << a)
		if _codes.get(c1, "") == deck and _strip_arts.has(c1):
			out.append(c1)
		for b: int in range(a + 1, 10):
			var c2: int = c1 ^ (1 << b)
			if _codes.get(c2, "") == deck and _strip_arts.has(c2):
				out.append(c2)
	return out

func _deck_codes(deck: String) -> Array[int]:
	var out: Array[int] = []
	for c: int in _strip_arts:
		if _codes.get(c, "") == deck:
			out.append(c)
	return out

# Card millimetres -> photo pixels for a reading (TableauReader.card_frame with the deck given).
static func _card_frame(d: Dictionary, deck: String) -> Transform2D:
	var s: float = float(d["radius"]) / float(DECK_R_MM[deck])
	var th: float = float(d["th"])
	var up: Vector2 = Vector2(-cos(th), -sin(th))
	var right: Vector2 = Vector2(-up.y, up.x)
	var down: Vector2 = -up
	var a: PackedFloat32Array = d["shape"]
	var col0: Vector2 = Vector2(a[0] * right.x + a[1] * right.y, a[2] * right.x + a[3] * right.y) * s
	var col1: Vector2 = Vector2(a[0] * down.x + a[1] * down.y, a[2] * down.x + a[3] * down.y) * s
	var dial: Vector2 = TableauReader.DIAL_MM[deck]
	return Transform2D(col0, col1, (d["center"] as Vector2) - col0 * dial.x - col1 * dial.y)

# Grey-world white balance of the half-size copy the markers are found on, if the photo has a
# clear colour cast (red vs blue means more than 15 % apart). Returns false if it had none.
static func _balance(small: Image) -> bool:
	var data: PackedByteArray = small.get_data()
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for o: int in range(0, data.size() - 2, 3 * 13):
		var v: Vector3 = Vector3(data[o], data[o + 1], data[o + 2])
		if v.x + v.y + v.z > 60.0:
			sum += v
			n += 1
	if n < 100 or minf(sum.x, sum.z) <= 0.0 or absf(sum.x / sum.z - 1.0) < 0.15:
		return false
	var k: Vector3 = Vector3(sum.y / sum.x, 1.0, sum.y / sum.z)
	for o: int in range(0, data.size() - 2, 3):
		data[o] = mini(255, roundi(data[o] * k.x))
		data[o + 2] = mini(255, roundi(data[o + 2] * k.z))
	small.set_data(small.get_width(), small.get_height(), false, Image.FORMAT_RGB8, data)
	return true

# The largest group of confident readings that agree with one of them (its anchor) on
# facing and scale — all cards in a tableau face the same way at about the same size.
# Low-contrast readings off busy art can agree with each other on a wrong size, so the group
# with the most clean readings wins, then the largest.
static func _agreeing(at: Array[Vector3], scales: Array[float], clean: Array[bool]) -> Array[int]:
	var best: Array[int] = []
	var best_score: int = -1
	for a: int in at.size():
		var grp: Array[int] = []
		var n_clean: int = 0
		for b: int in at.size():
			if absf(angle_difference(at[a].z, at[b].z)) <= deg_to_rad(FACING_AGREE_DEG) \
					and absf(scales[b] / scales[a] - 1.0) <= SCALE_AGREE:
				grp.append(b)
				if clean[b]:
					n_clean += 1
		var score: int = n_clean * 1000 + grp.size()
		if score > best_score:
			best = grp
			best_score = score
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

# Dial v2's violet (printed C65 M90, hue ~286): blue well above green, red a bit above green, and
# blue not far below red, which keeps the card art's reds and pinks out (violet is almost absent
# from the art). Ratios, not levels: printed violet is dark (photos: ~90, 55, 104 in good light,
# ~66, 40, 71 dim), warm lamp light eats exactly its blue (~72, 45, 63), and on coated paper under
# the torch it comes out lighter and bluer (~160, 140, 215: red only ~10-15 % above green), hence
# the small margins. Only the diamond is a marker now: the cyan dot of the first test prints went
# (cyan and light blue fill a good part of the card art: thousands of false marker candidates).
static func _is_violet(r: int, g: int, b: int) -> bool:
	return b * 100 > g * 127 and r * 100 > g * 108 and b * 100 >= r * 75 and b - g > 14

static func _is_violet_loose(r: int, g: int, b: int) -> bool:
	return b * 100 > g * 118 and r * 100 > g * 103 and b * 100 >= r * 65 and b - g > 10

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

# A marker's colour: the violet diamond of dial v2 (2026-10).
static func _cyan_at(data: PackedByteArray, i: int, loose: bool) -> bool:
	var r: int = data[i * 3]
	var g: int = data[i * 3 + 1]
	var b: int = data[i * 3 + 2]
	if loose:
		return _is_violet_loose(r, g, b)
	return _is_violet(r, g, b)

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
## size_at: (local, photo-wide) px per mm to hold decodes to their card type's ring size; zero = any.
func _search(mx: float, my: float, radii: Array[float], angles: Array[float], shapes: Array[PackedFloat32Array] = [], size_at: Vector2 = Vector2.ZERO) -> Dictionary:
	var best: Dictionary = {}
	for shape: PackedFloat32Array in (shapes if not shapes.is_empty() else _shapes):
		var e: Dictionary = _search_shape(mx, my, radii, angles, shape, size_at)
		if not e.is_empty() and _better(e, best):
			best = e
			best["shape"] = shape
	return best

func _search_shape(mx: float, my: float, radii: Array[float], angles: Array[float], shape: PackedFloat32Array, size_at: Vector2 = Vector2.ZERO) -> Dictionary:
	var best: Dictionary = {}
	for r: float in radii:
		for th: float in angles:
			var e: Dictionary = _evaluate(mx, my, r, th, shape, size_at)
			if not e.is_empty() and _better(e, best):
				best = e
	if best.is_empty():
		return best
	var r0: float = float(best["r"])
	var th0: float = float(best["th"])
	for dr: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for dth: int in range(-3, 4):
			var e: Dictionary = _evaluate(mx, my, r0 + dr, th0 + deg_to_rad(float(dth)), shape, size_at)
			if not e.is_empty() and _better(e, best):
				best = e
	return best

# Dial hypothesis: on the undistorted (circle) dial the centre lies at distance r
# from the marker in direction th; `shape` maps that circle onto the photo.
# Returns {} unless it decodes to a real card's code.
func _evaluate(mx: float, my: float, r: float, th: float, shape: PackedFloat32Array, size_at: Vector2 = Vector2.ZERO) -> Dictionary:
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
	# clean: the split the reader always demanded; otherwise (a pale print, soft focus, a dim
	# corner) a clear split relative to the dial's own range still counts as a weak reading,
	# which only stays if its strip confirms it (_check_strips)
	var rel: float = gap / maxf(sv[10] - sv[0], 0.001)
	var clean: bool = gap >= 0.22 and sv[cut] <= MAX_DARK and sv[cut + 1] >= MIN_LIT
	if not clean and (gap < WEAK_GAP or rel < WEAK_REL):
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
	if size_at.x > 0.0:
		var deck_r: float = float(DECK_R_MM[_codes[code]])
		if absf(r / (deck_r * size_at.x) - 1.0) > SCALE_TOLERANCE and absf(r / (deck_r * size_at.y) - 1.0) > SCALE_TOLERANCE:
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
	var hole: float = hole_sum / maxf(1.0, hole_n)
	if hole < MIN_HOLE:
		clean = false
		if hole < WEAK_HOLE_MIN or hole < WEAK_HOLE_REL * (sv[10] - sv[0]) or gap < WEAK_GAP or rel < WEAK_REL:
			return {}
	return {gap = gap, code = code, cx = cx, cy = cy, r = r, th = th, dot = dot_sum / maxf(1.0, dot_n), lo = sv[0], hi = sv[10],
		rel = rel, clean = clean}

# Search order: clean readings before weak ones, then the clearer split.
static func _better(e: Dictionary, best: Dictionary) -> bool:
	if best.is_empty():
		return true
	if bool(e["clean"]) != bool(best["clean"]):
		return bool(e["clean"])
	return float(e["gap"]) > float(best["gap"])

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
					# and facing the same way: a loose card dropped near a column's end lies at an angle
					if lateral < 12.0 and absf(v.dot(up)) / px_per_mm < 40.0 and (techs[j]["up"] as Vector2).dot(up) > COLUMN_FACING_COS:
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
