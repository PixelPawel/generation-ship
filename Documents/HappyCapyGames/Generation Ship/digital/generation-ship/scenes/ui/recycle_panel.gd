class_name RecyclePanel
extends Control

const _SUPPLY_ICON_PATHS: Array[String] = [
	"res://assets/ui/supply/Dust.png",
	"res://assets/ui/supply/Metals.png",
	"res://assets/ui/supply/Liquids.png",
	"res://assets/ui/supply/Organix.png",
	"res://assets/ui/supply/Electrix.png",
	"res://assets/ui/supply/Thrust.png",
]
const _SUPPLY_NAMES: Array[String] = ["Dust", "Metals", "Liquids", "Organix", "Electrix", "Thrust"]

signal confirmed()
signal cancelled()

var _card_image: TextureRect = null
var _card_name_label: Label = null
var _gain_icon: TextureRect = null
var _gain_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	outer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(outer_vbox)

	var title: Label = Label.new()
	title.text = "Recycle Card"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	_card_image = TextureRect.new()
	_card_image.custom_minimum_size = Vector2(216.0, 302.0)
	_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card_image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	_card_image.material = mat
	outer_vbox.add_child(_card_image)

	_card_name_label = Label.new()
	_card_name_label.add_theme_font_size_override("font_size", 18)
	_card_name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_card_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(_card_name_label)

	var gain_row: HBoxContainer = HBoxContainer.new()
	gain_row.add_theme_constant_override("separation", 8)
	gain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(gain_row)

	var gain_prefix: Label = Label.new()
	gain_prefix.text = "Gain:"
	gain_prefix.add_theme_font_size_override("font_size", 22)
	gain_prefix.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	gain_row.add_child(gain_prefix)

	_gain_icon = TextureRect.new()
	_gain_icon.custom_minimum_size = Vector2(28.0, 28.0)
	_gain_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gain_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gain_row.add_child(_gain_icon)

	_gain_label = Label.new()
	_gain_label.add_theme_font_size_override("font_size", 22)
	_gain_label.add_theme_color_override("font_color", Color.WHITE)
	gain_row.add_child(_gain_label)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(btn_row)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140.0, 52.0)
	cancel_btn.add_theme_font_size_override("font_size", 22)
	cancel_btn.pressed.connect(func() -> void: _on_cancelled())
	btn_row.add_child(cancel_btn)

	var confirm_btn: Button = Button.new()
	confirm_btn.text = "Recycle"
	confirm_btn.custom_minimum_size = Vector2(140.0, 52.0)
	confirm_btn.add_theme_font_size_override("font_size", 22)
	confirm_btn.pressed.connect(func() -> void: _on_confirmed())
	btn_row.add_child(confirm_btn)

func show_recycle(card_data: CardData, color: CardData.SupplyColor, bonus: int) -> void:
	if card_data:
		var url: String = card_data.local_art_path if not card_data.local_art_path.is_empty() else card_data.image_url
		_card_image.texture = ImageCache.get_texture(url) if not url.is_empty() else null
		_card_name_label.text = card_data.card_name
	else:
		_card_image.texture = null
		_card_name_label.text = ""
	_gain_icon.texture = load(_SUPPLY_ICON_PATHS[int(color)]) as Texture2D
	var color_name: String = _SUPPLY_NAMES[int(color)]
	if bonus > 0:
		_gain_label.text = "%d %s (Trash Compactor +%d)" % [1 + bonus, color_name, bonus]
	else:
		_gain_label.text = "1 %s" % color_name
	show()

func _on_confirmed() -> void:
	hide()
	confirmed.emit()

func _on_cancelled() -> void:
	hide()
	cancelled.emit()
