extends RefCounted

## Colours, fonts, styles and small builders for the in-game HUD - the same
## look as uprising_theme.tres (Gloock headings, Barlow Condensed text,
## teal-black panels, bone text, rivet gold) plus the game's own resource
## tokens from the TTS mod (assets/art/ui/icons). No class_name - preload it.

const ICON_DIR := "res://assets/art/ui/icons/"
const FONT_DISPLAY: FontFile = preload("res://assets/art/fonts/Gloock-Regular.ttf")
const FONT_BOLD: FontFile = preload("res://assets/art/fonts/BarlowCondensed-SemiBold.ttf")
const FONT_TEXT: FontFile = preload("res://assets/art/fonts/BarlowCondensed-Medium.ttf")

const GOLD := Color(0.875, 0.745, 0.424)
const GOLD_DEEP := Color(0.47, 0.36, 0.14)
const BONE := Color(0.949, 0.91, 0.769)
const MUTED := Color(0.58, 0.76, 0.78)
const TEAL := Color(0.055, 0.592, 0.635)
const CRIMSON := Color(0.64, 0.11, 0.23)
const EMPIRE := Color(0.77, 0.16, 0.66)
const CHAOS := Color(0.776, 0.812, 0.224)
const PANEL_BG := Color(0.024, 0.102, 0.114, 0.9)
const BUTTON_BG := Color(0.035, 0.15, 0.17, 0.94)
const BUTTON_HOVER := Color(0.06, 0.22, 0.245, 0.97)

## Resource name in actions/state -> icon file.
const RESOURCE_ICON: Dictionary = {"Salt": "salt", "Plunder": "plunder", "Food": "food"}


static func icon(icon_name: String) -> Texture2D:
	var path: String = ICON_DIR + icon_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func panel_style(bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = Color(TEAL, 0.36)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0.016, 0.024, 0.5)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	return sb


## A panel with a coloured strip down its left edge - whose panel it is
## (a faction) or what kind of option it holds.
static func accent_panel_style(accent: Color, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb: StyleBoxFlat = panel_style(bg)
	sb.border_width_left = 3
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.border_color = accent
	sb.content_margin_left = 16
	return sb


static func button_style(bg: Color, edge: Color, edge_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(edge_width)
	sb.border_color = edge
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 6
	return sb


## Normal / hover / pressed / disabled / focus looks for a HUD button.
## "primary" is the gold call to action (End turn, Continue).
static func style_button(b: Button, primary: bool = false) -> void:
	var base: Color = Color(0.29, 0.21, 0.07, 0.96) if primary else BUTTON_BG
	var edge: Color = GOLD if primary else Color(TEAL, 0.45)
	b.add_theme_stylebox_override("normal", button_style(base, edge))
	b.add_theme_stylebox_override("hover", button_style(Color(0.38, 0.28, 0.1, 0.98) if primary else BUTTON_HOVER, GOLD))
	b.add_theme_stylebox_override("pressed", button_style(Color(0.2, 0.15, 0.05, 0.98) if primary else Color(0.02, 0.1, 0.11, 0.98), GOLD))
	b.add_theme_stylebox_override("disabled", button_style(Color(0.024, 0.09, 0.1, 0.8), Color(TEAL, 0.16)))
	b.add_theme_stylebox_override("focus", button_style(Color(0, 0, 0, 0), GOLD))
	b.add_theme_font_override("font", FONT_BOLD)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", GOLD if not primary else BONE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_focus_color", BONE)
	b.add_theme_color_override("font_disabled_color", Color(BONE, 0.32))
	b.focus_mode = Control.FOCUS_ALL


static func label(text: String, size: int, color: Color = BONE, font: Font = FONT_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func heading(text: String, size: int) -> Label:
	var l: Label = label(text, size, BONE, FONT_DISPLAY)
	l.add_theme_color_override("font_shadow_color", Color(0, 0.02, 0.03, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func icon_rect(icon_name: String, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Cost chips: [["ap", 1], ["food", 1]] -> icon + number pairs. An empty
## number shows only the icon (a cost that depends on the card).
static func cost_row(parts: Array, size: int = 15) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	for part: Variant in parts:
		var pair: Array = part
		row.add_child(icon_rect(str(pair[0]), size))
		var n: String = str(pair[1])
		if not n.is_empty():
			var num: Label = label(n, size, BONE, FONT_BOLD)
			row.add_child(num)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(4, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
	if row.get_child_count() > 0:
		row.get_child(row.get_child_count() - 1).queue_free()
	return row


## Unit/defense costs from PlayerboardTable as cost chips.
static func board_cost_parts(cost: Dictionary) -> Array:
	var parts: Array = []
	match str(cost.get("type", "fixed")):
		"or":
			parts.append(["salt", str(int(cost.get("Salt", 0)))])
			parts.append(["plunder", "or %d" % int(cost.get("Plunder", 0))])
		"any":
			parts.append(["salt", ""])
			parts.append(["plunder", ""])
			parts.append(["food", "%d of any" % int(cost.get("amount", 0))])
		_:
			for res: String in ["Salt", "Plunder", "Food"]:
				if int(cost.get(res, 0)) > 0:
					parts.append([RESOURCE_ICON[res], str(int(cost.get(res, 0)))])
	return parts
