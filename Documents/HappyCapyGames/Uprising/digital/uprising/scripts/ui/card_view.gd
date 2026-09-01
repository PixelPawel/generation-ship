class_name CardView
extends RefCounted
## Renders a card's art (CardDatabase.*.texture_path) as an actual Control
## node -- every card model has had a working texture_path since the asset
## pipeline was built, but nothing displayed it until now. Used by
## game_board.gd's Hand panel and Feat-choice picker.

const FALLBACK_COLOR := Color(0.15, 0.15, 0.18)


## A plain (non-interactive) card thumbnail: the art if `texture_path`
## actually loads, else a colored placeholder labeled with `card_name` --
## a missing/failed image should be visibly obvious, not silently blank.
static func make(texture_path: String, card_name: String, size: Vector2) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = size
	box.tooltip_text = card_name

	var tex: Texture2D = load(texture_path) if (texture_path != "" and ResourceLoader.exists(texture_path)) else null
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.custom_minimum_size = size
		box.add_child(rect)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = FALLBACK_COLOR
		box.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = card_name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = size
		box.add_child(label)

	return box


## Same visuals as make(), wrapped in a flat Button so `on_pressed` fires on
## click -- used for the Build Phase Feat-choice picker.
static func make_button(texture_path: String, card_name: String, size: Vector2, on_pressed: Callable) -> Control:
	var button := Button.new()
	button.custom_minimum_size = size
	button.flat = true
	button.pressed.connect(on_pressed)
	button.add_child(make(texture_path, card_name, size))
	return button
