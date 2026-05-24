class_name CardFace
extends Control

# Portrait size for tech/expedition cards (matches frame ratio 1770:2589)
const SIZE_PORTRAIT  := Vector2i(512, 750)
# Landscape size for sector cards (matches frame ratio 2589:1770)
const SIZE_LANDSCAPE := Vector2i(750, 512)

const _MYRIAD_PATH := "res://assets/fonts/Myriad Variable Concept.ttf"
const _ETHNO_PATH  := "res://assets/fonts/Ethnocentric-Regular.otf"

const _EFFECT_FONT_SZ := 44   # 8 pt × 4
const _NAME_FONT_SZ   := 36   # 7 pt × 4
const _COST_FONT_SZ   := 36   # 7 pt × 4
const _FLAVOR_FONT_SZ := 38

const _PAD := 10.0  # inner padding inside each panel

# Portrait zones — fractions of 512×750 viewport, derived from 1770×2589 frame pixel scan
const _PORT_ART_L  := 0.164   # left edge of transparent art window
const _PORT_ART_T  := 0.116   # top edge of transparent art window
const _PORT_ART_R  := 0.836   # right edge of transparent art window
const _PORT_ART_B  := 0.440   # bottom edge of transparent art window
const _PORT_EFF_T  := 0.625   # top of gray effect panel
const _PORT_EFF_B  := 0.810   # bottom of gray effect panel
const _PORT_NAM_T  := 0.855   # top of name banner
const _PORT_NAM_B  := 0.925   # bottom of name banner
const _PORT_COST_X := 0.100   # cost badge center x
const _PORT_COST_Y := 0.090   # cost badge center y

# Landscape zones — fractions of 750×512 viewport, derived from 2589×1770 frame pixel scan
const _LAND_ART_L  := 0.198   # left edge of transparent art window
const _LAND_ART_R  := 0.802   # right edge of transparent art window
const _LAND_ART_B  := 0.492   # bottom of transparent art window (top is 0)
const _LAND_EFF_T  := 0.530   # top of effect panel
const _LAND_EFF_B  := 0.847   # bottom of effect panel
const _LAND_COST_X := 0.040   # cost badge center x
const _LAND_COST_Y := 0.080   # cost badge center y
const _LAND_NAM_CX := 0.902   # center x of right-side name panel

var _art_rect:         TextureRect
var _frame_rect:       TextureRect
var _name_label:       Label
var _cost_label:       Label
var _effect_label:     RichTextLabel
var _flavor_label:     Label

# Cached font variations (created once in build())
var _font_myriad_sb:    FontVariation
var _font_ethno_italic: FontVariation

static func viewport_size(cd: CardData, is_advanced: bool) -> Vector2i:
	if cd.card_type == CardData.CardType.SECTOR and not is_advanced:
		return SIZE_LANDSCAPE
	return SIZE_PORTRAIT

# ── Setup ─────────────────────────────────────────────────────────────────────

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_fonts()

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.15)
	add_child(bg)

	_art_rect = TextureRect.new()
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_art_rect)

	# Flavor overlaid on art — must be added BEFORE frame so frame chrome renders above it
	_flavor_label = _make_label(_font_myriad_sb, _FLAVOR_FONT_SZ)
	_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavor_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_flavor_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_flavor_label.add_theme_constant_override("shadow_offset_x", 2)
	_flavor_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_flavor_label)

	_frame_rect = TextureRect.new()
	_frame_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_frame_rect)

	_name_label = _make_label(_font_ethno_italic, _NAME_FONT_SZ)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)

	_cost_label = _make_label(_font_ethno_italic, _COST_FONT_SZ)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.add_theme_color_override("font_color", Color.WHITE)
	_cost_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_cost_label.add_theme_constant_override("shadow_offset_x", 1)
	_cost_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_cost_label)

	_effect_label = RichTextLabel.new()
	_effect_label.bbcode_enabled = true
	_effect_label.scroll_active = false
	_effect_label.fit_content = false
	if _font_myriad_sb:
		_effect_label.add_theme_font_override("normal_font", _font_myriad_sb)
	_effect_label.add_theme_font_size_override("normal_font_size", _EFFECT_FONT_SZ)
	_effect_label.add_theme_color_override("default_color", Color.WHITE)
	add_child(_effect_label)

func populate(cd: CardData, is_advanced: bool) -> void:
	var is_landscape := (cd.card_type == CardData.CardType.SECTOR and not is_advanced)
	var w := float(size.x)
	var h := float(size.y)

	var art_path := CardAssets.art_path(cd, is_advanced)
	if not art_path.is_empty():
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(art_path)) == OK:
			_art_rect.texture = ImageTexture.create_from_image(img)

	var frame_path := CardAssets.frame_path(cd, is_advanced)
	if not frame_path.is_empty() and ResourceLoader.exists(frame_path):
		_frame_rect.texture = load(frame_path) as Texture2D

	var display_name := cd.adv_name if is_advanced else cd.card_name
	var cost         := CardData.effective_cost(cd, is_advanced)
	var effect       := cd.adv_effect_text if is_advanced else cd.effect_text
	var flavor       := cd.adv_flavor_text if is_advanced else cd.flavor_text

	if is_landscape:
		_layout_landscape(display_name, cost, effect, flavor, w, h)
	else:
		_layout_portrait(display_name, cost, effect, flavor, w, h)

func _layout_portrait(
		display_name: String, cost: int, effect: String, flavor: String,
		w: float, h: float) -> void:
	# Art: positioned to exactly match the transparent art window in the frame
	var art_l := w * _PORT_ART_L
	var art_t := h * _PORT_ART_T
	var art_r := w * _PORT_ART_R
	var art_b := h * _PORT_ART_B
	_art_rect.position = Vector2(art_l, art_t)
	_art_rect.size = Vector2(art_r - art_l, art_b - art_t)

	# Cost: centered in the circular badge (top-left chrome)
	_cost_label.text = str(cost) if cost > 0 else ""
	var cost_h := float(_COST_FONT_SZ) + 4.0
	var cost_w := 62.0
	_cost_label.position = Vector2(w * _PORT_COST_X - cost_w * 0.5, h * _PORT_COST_Y - cost_h * 0.5)
	_cost_label.size = Vector2(cost_w, cost_h)

	# Flavor: overlaid on art in its lower quarter (renders behind frame chrome)
	var art_inner_h := art_b - art_t
	var flav_t := art_t + art_inner_h * 0.76
	_flavor_label.text = flavor
	_flavor_label.position = Vector2(art_l + _PAD, flav_t)
	_flavor_label.size = Vector2(art_r - art_l - _PAD * 2.0, art_b - flav_t)

	# Effect: centered inside gray effect panel
	_effect_label.position = Vector2(art_l + _PAD, h * _PORT_EFF_T + _PAD)
	_effect_label.size = Vector2(art_r - art_l - _PAD * 2.0,
		h * (_PORT_EFF_B - _PORT_EFF_T) - _PAD * 2.0)
	_effect_label.text = "[center]%s[/center]" % effect

	# Name: centered inside name banner, stops before supply icon on right
	_name_label.text = display_name
	_name_label.pivot_offset = Vector2.ZERO
	_name_label.rotation_degrees = 0.0
	_name_label.position = Vector2(art_l, h * _PORT_NAM_T)
	# Right edge at ~82% to leave room for supply icon
	_name_label.size = Vector2(w * 0.820 - art_l, h * (_PORT_NAM_B - _PORT_NAM_T))

func _layout_landscape(
		display_name: String, cost: int, effect: String, flavor: String,
		w: float, h: float) -> void:
	# Art: positioned to exactly match the transparent art window in the frame
	var art_l := w * _LAND_ART_L
	var art_r := w * _LAND_ART_R
	var art_b := h * _LAND_ART_B
	_art_rect.position = Vector2(art_l, 0.0)
	_art_rect.size = Vector2(art_r - art_l, art_b)

	# Cost: centered in the pipe-column badge (top-left)
	_cost_label.text = str(cost) if cost > 0 else ""
	var cost_h := float(_COST_FONT_SZ) + 4.0
	var cost_w := 54.0
	_cost_label.position = Vector2(w * _LAND_COST_X - cost_w * 0.5, h * _LAND_COST_Y - cost_h * 0.5)
	_cost_label.size = Vector2(cost_w, cost_h)

	# Flavor: overlaid on art near the bottom of the art window
	var flav_t := art_b * 0.76
	_flavor_label.text = flavor
	_flavor_label.position = Vector2(art_l + _PAD, flav_t)
	_flavor_label.size = Vector2(art_r - art_l - _PAD * 2.0, art_b - flav_t)

	# Effect: centered inside effect panel
	_effect_label.position = Vector2(art_l + _PAD, h * _LAND_EFF_T + _PAD)
	_effect_label.size = Vector2(art_r - art_l - _PAD * 2.0,
		h * (_LAND_EFF_B - _LAND_EFF_T) - _PAD * 2.0)
	_effect_label.text = "[center]%s[/center]" % effect

	# Name: rotated -90° and centered in the right navy panel
	var right_cx := w * _LAND_NAM_CX
	var name_natural_w := h - _PAD * 2.0
	var name_natural_h := float(_NAME_FONT_SZ) + 10.0
	_name_label.text = display_name
	_name_label.size = Vector2(name_natural_w, name_natural_h)
	_name_label.pivot_offset = Vector2(name_natural_w * 0.5, name_natural_h * 0.5)
	_name_label.rotation_degrees = -90.0
	_name_label.position = Vector2(right_cx - name_natural_w * 0.5,
		h * 0.5 - name_natural_h * 0.5)

# ── Font creation ─────────────────────────────────────────────────────────────

func _create_fonts() -> void:
	if ResourceLoader.exists(_MYRIAD_PATH):
		var ff := load(_MYRIAD_PATH) as FontFile
		_font_myriad_sb = FontVariation.new()
		_font_myriad_sb.base_font = ff
		_font_myriad_sb.variation_opentype = {"wght": 600}

	if ResourceLoader.exists(_ETHNO_PATH):
		var ff := load(_ETHNO_PATH) as FontFile
		_font_ethno_italic = FontVariation.new()
		_font_ethno_italic.base_font = ff
		# ~12° shear for pseudo-italic (tan 12° ≈ 0.213)
		_font_ethno_italic.variation_transform = Transform2D(
			Vector2(1.0, 0.0),
			Vector2(0.213, 1.0),
			Vector2.ZERO)

func _make_label(font: Font, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl
