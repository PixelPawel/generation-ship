extends Control
const Haptics = preload("res://scripts/haptics.gd")
const RuleRefs = preload("res://scripts/game/rule_refs.gd")
# Phones: press and hold a hand card to read it at full size. The card's art
# fills most of the screen height; a tap anywhere closes it. No dimming behind
# it — the game stays visible around the card.

const FILL_HEIGHT: float = 0.86
const OPEN_DURATION: float = 0.16
const TERMS_HEIGHT: float = 0.1    # share of the height kept for the rule book buttons

var _art: TextureRect = null
var _terms: Control = null      # rule book buttons for the card's keywords

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

func show_card(cd: CardData, is_advanced: bool) -> void:
	if cd == null:
		return
	var url: String = cd.adv_image_url if is_advanced and not cd.adv_image_url.is_empty() else cd.image_url
	var tex: Texture2D = ImageCache.get_texture(url) if not url.is_empty() else null
	if tex == null:
		return
	_art.texture = tex
	if _terms:
		_terms.queue_free()
		_terms = null
	var terms: Array[Array] = RuleRefs.terms_for([cd] as Array[CardData], [is_advanced] as Array[bool])
	var h: float = size.y * (FILL_HEIGHT if terms.is_empty() else FILL_HEIGHT - TERMS_HEIGHT)
	var aspect: float = float(tex.get_width()) / float(maxi(tex.get_height(), 1))
	_art.size = Vector2(h * aspect, h)
	_art.position = (size - _art.size) / 2.0
	if not terms.is_empty():
		_art.position.y -= size.y * TERMS_HEIGHT / 2.0
		_terms = RuleRefs.make_term_row(terms, 20)
		add_child(_terms)
		_terms.size = Vector2(size.x * 0.9, 0.0)
		_terms.position = Vector2(size.x * 0.05, _art.position.y + _art.size.y + 12.0)
	_art.pivot_offset = _art.size / 2.0
	_art.scale = Vector2.ONE * 0.6
	_art.modulate.a = 0.0
	visible = true
	var t: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(_art, "scale", Vector2.ONE, OPEN_DURATION)
	t.parallel().tween_property(_art, "modulate:a", 1.0, OPEN_DURATION * 0.6)
	Haptics.tick()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		visible = false
		accept_event()
