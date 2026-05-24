extends Control

signal fuse_clicked(src: int, dst: int)

const ICON_SZ    := 52.0
const ICON_HALF  := ICON_SZ * 0.5
const ARROW_OFF  := 31.0   # distance from icon centre to arrow tip/tail
const ARROW_W    := 3.5
const ARROW_HOVER_W := 5.5
const ARROW_GLOW_W  := 18.0
const ARROW_HIT  := 26.0   # px from line to count as a hit

const COL_ARROW    := Color(0.9, 0.2, 0.3)
const COL_DIM      := Color(0.55, 0.55, 0.6, 0.28)
const COL_GLOW     := Color(1.0, 0.4, 0.5, 0.25)
const COL_1TO1     := Color(0.15, 0.92, 0.42)
const COL_1TO1_GLOW := Color(0.15, 0.92, 0.42, 0.25)

var _pos: Dictionary = {}     # int (SupplyColor) -> Vector2 centre
var _arrows: Array = []       # Array[Dictionary] { src, dst, hovered, disabled }
var _labels: Dictionary = {}  # int -> Label
var _time: float = 0.0

func setup(positions: Dictionary, fuse_map: Dictionary, icon_textures: Dictionary) -> void:
	_pos = positions
	for src: int in fuse_map:
		for dst: int in fuse_map[src]:
			_arrows.append({ "src": src, "dst": dst, "hovered": false, "disabled": true, "is_1to1": false })
	_build_icons(icon_textures)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _build_icons(icon_textures: Dictionary) -> void:
	for color: int in _pos:
		var center: Vector2 = _pos[color]

		var icon := TextureRect.new()
		icon.texture = icon_textures.get(color)
		icon.custom_minimum_size = Vector2(ICON_SZ, ICON_SZ)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = center - Vector2(ICON_HALF, ICON_HALF)
		add_child(icon)

		var lbl := Label.new()
		lbl.text = "0"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 32)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.custom_minimum_size = Vector2(ICON_SZ, ICON_SZ)
		lbl.size = Vector2(ICON_SZ, ICON_SZ)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.position = center - Vector2(ICON_HALF, ICON_HALF - 4.0)
		add_child(lbl)
		_labels[color] = lbl

func update_label(color: int, count: int) -> void:
	var lbl: Label = _labels.get(color) as Label
	if lbl:
		lbl.text = str(count)

func get_label_global_rect(color: int) -> Rect2:
	var lbl: Label = _labels.get(color) as Label
	return lbl.get_global_rect() if lbl else Rect2()

func set_arrow_enabled(src: int, dst: int, enabled: bool, is_1to1: bool = false) -> void:
	for arrow: Dictionary in _arrows:
		if arrow.src == src and arrow.dst == dst:
			arrow.disabled = not enabled
			arrow.is_1to1 = is_1to1
			queue_redraw()
			return

func _endpoints(arrow: Dictionary) -> Array:
	var a: Vector2 = _pos.get(arrow.src, Vector2.ZERO)
	var b: Vector2 = _pos.get(arrow.dst, Vector2.ZERO)
	var d: Vector2 = (b - a).normalized()
	return [a + d * ARROW_OFF, b - d * ARROW_OFF]

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	for arrow: Dictionary in _arrows:
		var pts: Array = _endpoints(arrow)
		var p1: Vector2 = pts[0]
		var p2: Vector2 = pts[1]
		var dir: Vector2 = (p2 - p1).normalized()
		var total_len: float = (p2 - p1).length()
		var shaft_end: Vector2 = p2 - dir * 20.0  # stop at arrowhead base
		var shaft_len: float = (shaft_end - p1).length()
		var is_1to1: bool = arrow.get("is_1to1", false)

		var col_base: Color = COL_DIM
		var col_glow: Color = COL_GLOW
		if not arrow.disabled:
			col_base = COL_1TO1 if is_1to1 else COL_ARROW
			col_glow = COL_1TO1_GLOW if is_1to1 else COL_GLOW

		# Pulsing pill-shaped glow (circles at endpoints avoid flat/boxy caps)
		if not arrow.disabled:
			var pulse: float = 0.5 + 0.5 * sin(_time * 2.2 + float(arrow.src) * 1.3)
			var glow_a: float = lerpf(0.10, 0.30, pulse)
			var gc: Color = Color(col_glow.r, col_glow.g, col_glow.b, glow_a)
			draw_circle(p1, 5.0, gc)
			draw_line(p1, shaft_end, gc, 10.0, true)

		# Shaft
		var shaft_w: float = ARROW_HOVER_W if (arrow.hovered and not arrow.disabled) else ARROW_W
		var shaft_col: Color = col_base.lightened(0.3) if (arrow.hovered and not arrow.disabled) else col_base
		draw_line(p1, shaft_end, shaft_col, shaft_w, true)

		# Sweeping highlight (active only)
		if not arrow.disabled:
			var speed: float = 80.0 if is_1to1 else 55.0
			var sweep_len: float = minf(14.0, shaft_len * 0.38)
			var phase: float = fmod(_time * speed, shaft_len + sweep_len)
			var s0: float = clampf(phase - sweep_len, 0.0, shaft_len)
			var s1: float = clampf(phase, 0.0, shaft_len)
			if s1 > s0:
				var bright: Color = col_base.lightened(0.55)
				bright.a = 0.95
				draw_line(p1 + dir * s0, p1 + dir * s1, bright, shaft_w + 1.5, true)

		# Arrowhead
		var head_col: Color = col_base.lightened(0.3) if (arrow.hovered and not arrow.disabled) else col_base
		_draw_head(p2, dir, head_col)

func _draw_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	var perp: Vector2 = dir.rotated(PI * 0.5) * 10.0
	var base: Vector2 = tip - dir * 20.0
	var dim: Color = col.darkened(0.35)
	draw_polygon(
		PackedVector2Array([tip, base + perp, base - perp]),
		PackedColorArray([col, dim, dim])
	)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var sq: float = ab.length_squared()
	if sq < 1e-6:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / sq, 0.0, 1.0))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var changed: bool = false
		for arrow: Dictionary in _arrows:
			var pts: Array = _endpoints(arrow)
			var should: bool = _seg_dist(event.position, pts[0], pts[1]) < ARROW_HIT
			if arrow.hovered != should:
				arrow.hovered = should
				changed = true
		if changed:
			queue_redraw()
		var any_hovered: bool = false
		for arrow: Dictionary in _arrows:
			if arrow.hovered and not arrow.disabled:
				any_hovered = true
				break
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if any_hovered else Control.CURSOR_ARROW

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for arrow: Dictionary in _arrows:
			if arrow.disabled:
				continue
			var pts: Array = _endpoints(arrow)
			if _seg_dist(event.position, pts[0], pts[1]) < ARROW_HIT:
				fuse_clicked.emit(int(arrow.src), int(arrow.dst))
				break
