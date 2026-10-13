extends Control
const Haptics = preload("res://scripts/haptics.gd")
# "Your Turn" / "End of Round" / auction pop-up: a dark band opens across the middle of the screen (fading out
# towards both sides, so the game stays visible around it), two light lines grow out
# from the centre along its edges, the text pops in with a little overshoot and a
# shine sweeps over it; then it all folds away again. Never takes input.
# Usage: var b = TurnBanner.new(); $UILayer.add_child(b); b.play(tr("Your Turn"), color[, subtitle])
# A long title shrinks to fit the window; the optional subtitle is a smaller second line.
# `finished` fires right before it frees itself (not if something frees it earlier).

signal finished

const BAND_HEIGHT: float = 150.0        # at 1080 px window height
const FONT_SIZE: float = 76.0
const SUBTITLE_SIZE: float = 30.0
const SUBTITLE_BAND: float = 1.3        # band height factor when there's a subtitle
const MAX_TEXT_WIDTH: float = 0.88      # of the window width
const LINE_HEIGHT: float = 3.0
const OPEN: float = 0.2
const HOLD: float = 1.15
const CLOSE: float = 0.3

var _band: TextureRect
var _lines: Array[TextureRect] = []
var _text: Control                      # title (+ subtitle), scaled and faded as one
var _shine: TextureRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# soft-edged horizontal strip: transparent at both ends, `a` in the middle
static func _strip(color: Color, a: float) -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	g.colors = PackedColorArray([Color(color, 0.0), Color(color, a), Color(color, a), Color(color, 0.0)])
	var t: GradientTexture2D = GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 4
	return t

func _add_rect(tex: Texture2D) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _make_label(text: String, size: float, color: Color, outline: float, glow: float) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", maxi(3, roundi(outline)))
	if glow > 0.0:
		l.add_theme_color_override("font_shadow_color", Color(color, 0.45))
		l.add_theme_constant_override("shadow_outline_size", roundi(glow))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# shrink to fit the window if the (translated) line is too long
	var font: Font = l.get_theme_font("font")
	var max_w: float = get_viewport_rect().size.x * MAX_TEXT_WIDTH
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size)).x
	if w > max_w:
		size *= max_w / w
	l.add_theme_font_size_override("font_size", roundi(size))
	return l

func play(text: String, color: Color = Color(0.45, 1.0, 0.55), subtitle: String = "") -> void:
	var vp: Vector2 = get_viewport_rect().size
	var s: float = vp.y / 1080.0
	var band_h: float = BAND_HEIGHT * s * (SUBTITLE_BAND if not subtitle.is_empty() else 1.0)
	var cy: float = vp.y * 0.5

	_band = _add_rect(_strip(Color(0.02, 0.05, 0.09), 0.82))
	_band.size = Vector2(vp.x, band_h)
	_band.position = Vector2(0.0, cy - band_h / 2.0)
	_band.pivot_offset = _band.size / 2.0
	_band.scale = Vector2(1.0, 0.0)

	for side: float in [-1.0, 1.0]:
		var line: TextureRect = _add_rect(_strip(color, 0.95))
		line.size = Vector2(vp.x * 0.8, LINE_HEIGHT * s)
		line.position = Vector2(vp.x * 0.1, cy + side * band_h / 2.0 - line.size.y / 2.0)
		line.pivot_offset = line.size / 2.0
		line.scale = Vector2(0.0, 1.0)
		_lines.append(line)

	_text = Control.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_text.size = Vector2(vp.x, band_h)
	_text.position = Vector2(0.0, cy - band_h / 2.0)
	_text.pivot_offset = _text.size / 2.0
	_text.scale = Vector2.ONE * 1.6
	_text.modulate.a = 0.0
	var title: Label = _make_label(text.to_upper(), FONT_SIZE * s, color, 10.0 * s, 18.0 * s)
	_text.add_child(title)
	if subtitle.is_empty():
		title.size = _text.size
	else:
		title.size = Vector2(vp.x, band_h * 0.62)
		var sub: Label = _make_label(subtitle, SUBTITLE_SIZE * s, Color(0.92, 0.95, 1.0), 6.0 * s, 0.0)
		_text.add_child(sub)
		sub.size = Vector2(vp.x, band_h * 0.34)
		sub.position = Vector2(0.0, band_h * 0.6)

	# a bright diagonal glint that runs across the text once it has landed
	_shine = _add_rect(_strip(Color(1.0, 1.0, 1.0), 0.55))
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_shine.material = add
	_shine.size = Vector2(160.0 * s, band_h * 1.4)
	_shine.pivot_offset = _shine.size / 2.0
	_shine.rotation = deg_to_rad(18.0)
	_shine.position = Vector2(-_shine.size.x * 2.0, cy - _shine.size.y / 2.0)
	_shine.modulate.a = 0.0

	Haptics.thump()
	var t: Tween = create_tween()
	t.tween_property(_band, "scale:y", 1.0, OPEN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for line: TextureRect in _lines:
		t.parallel().tween_property(line, "scale:x", 1.0, OPEN * 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_text, "modulate:a", 1.0, OPEN).set_delay(OPEN * 0.4)
	t.parallel().tween_property(_text, "scale", Vector2.ONE, OPEN * 1.6).set_delay(OPEN * 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: _shine.modulate.a = 1.0)
	t.tween_property(_shine, "position:x", vp.x + _shine.size.x, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(maxf(0.0, HOLD - 0.55))
	t.tween_property(_text, "modulate:a", 0.0, CLOSE)
	t.parallel().tween_property(_text, "scale", Vector2.ONE * 0.9, CLOSE)
	t.parallel().tween_property(_band, "scale:y", 0.0, CLOSE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	for line: TextureRect in _lines:
		t.parallel().tween_property(line, "scale:x", 0.0, CLOSE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())
